import type { HostRuntimeConfiguration, HostRuntimeEndpoint, HostRuntimeOperationResult } from "./runtime-adapter.js";
import type { CommandResult, CommandRunner } from "./types.js";

export type JackRuntimeMode = "dry-run" | "apply";

export interface JackRuntimeAdapterOptions {
  readonly mode?: JackRuntimeMode;
  readonly timeoutMs?: number;
}

export interface JackRuntimeCommandLogEntry {
  readonly operation: "unload" | "apply" | "verify" | "rollback";
  readonly command: "jack_lsp" | "jack_connect" | "jack_disconnect";
  readonly args: readonly string[];
  readonly skipped: boolean;
}

export interface JackGraphRuntimeAdapter {
  readonly commandLog: readonly JackRuntimeCommandLogEntry[];
  unload(configuration: HostRuntimeConfiguration): Promise<HostRuntimeOperationResult>;
  apply(configuration: HostRuntimeConfiguration): Promise<HostRuntimeOperationResult>;
  verify(configuration: HostRuntimeConfiguration): Promise<HostRuntimeOperationResult>;
  rollback(configuration: HostRuntimeConfiguration): Promise<HostRuntimeOperationResult>;
}

interface JackRuntimeContext {
  readonly mode: JackRuntimeMode;
  runJack(
    operation: JackRuntimeCommandLogEntry["operation"],
    command: JackRuntimeCommandLogEntry["command"],
    args: readonly string[]
  ): Promise<CommandResult>;
}

interface JackConnectionPlan {
  readonly routeId: string;
  readonly label: string;
  readonly active: boolean;
  readonly pairs: readonly JackConnectionPair[];
}

interface JackConnectionPair {
  readonly outputPort: string;
  readonly inputPort: string;
}

interface JackConnectionPlanResult {
  readonly ok: true;
  readonly plans: readonly JackConnectionPlan[];
}

interface PreparedJackConnectionPlans extends JackConnectionPlanResult {
  readonly existingPairs: readonly JackConnectionPair[];
}

const defaultTimeoutMs = 5000;

export function createJackGraphRuntimeAdapter(
  runner: CommandRunner,
  options: JackRuntimeAdapterOptions = {}
): JackGraphRuntimeAdapter {
  const commandLog: JackRuntimeCommandLogEntry[] = [];
  const context = createJackRuntimeContext(runner, options, commandLog);

  return {
    commandLog,
    unload: (configuration) => unloadJackConnections(context, configuration),
    apply: (configuration) => applyJackConnections(context, configuration),
    verify: (configuration) => verifyJackConnections(context, configuration),
    rollback: (configuration) => unloadJackConnections(context, configuration)
  };
}

function createJackRuntimeContext(
  runner: CommandRunner,
  options: JackRuntimeAdapterOptions,
  commandLog: JackRuntimeCommandLogEntry[]
): JackRuntimeContext {
  const mode = options.mode ?? "dry-run";
  const timeoutMs = options.timeoutMs ?? defaultTimeoutMs;

  return {
    mode,
    async runJack(operation, command, args) {
      commandLog.push({ operation, command, args, skipped: mode === "dry-run" });

      if (mode === "dry-run") {
        return { command, args, exitCode: 0, stdout: "", stderr: "" };
      }

      return runner.run(command, args, { timeoutMs });
    }
  };
}

async function applyJackConnections(
  context: JackRuntimeContext,
  configuration: HostRuntimeConfiguration
): Promise<HostRuntimeOperationResult> {
  const validation = validateJackConfiguration(configuration);

  if (!validation.ok) {
    return validation;
  }

  if (context.mode === "dry-run") {
    await context.runJack("apply", "jack_lsp", []);
    await context.runJack("apply", "jack_lsp", ["-c"]);
    return { ok: true, message: `Dry run planned ${activeJackPlanCount(configuration)} JACK connection plan(s)` };
  }

  const prepared = await prepareJackConnectionPlans(context, configuration, "apply");

  if (!isPreparedJackConnectionPlans(prepared)) {
    return prepared;
  }

  const existingPairs = new Set(prepared.existingPairs.map(connectionPairKey));
  const createdPairs: JackConnectionPair[] = [];
  const mutedPairs = prepared.plans.filter((plan) => !plan.active).flatMap((plan) => plan.pairs);
  let disconnectedMuted = 0;
  let alreadyConnected = 0;

  for (const pair of mutedPairs) {
    if (!existingPairs.has(connectionPairKey(pair))) {
      continue;
    }

    const disconnected = await context.runJack("apply", "jack_disconnect", [pair.outputPort, pair.inputPort]);
    if (disconnected.exitCode !== 0) {
      return failed(`Could not disconnect muted JACK ports ${pair.outputPort} -> ${pair.inputPort}`, disconnected);
    }

    existingPairs.delete(connectionPairKey(pair));
    disconnectedMuted += 1;
  }

  for (const pair of prepared.plans.filter((plan) => plan.active).flatMap((plan) => plan.pairs)) {
    if (existingPairs.has(connectionPairKey(pair))) {
      alreadyConnected += 1;
      continue;
    }

    const connected = await context.runJack("apply", "jack_connect", [pair.outputPort, pair.inputPort]);
    if (connected.exitCode !== 0) {
      await disconnectJackPairs(context, "rollback", createdPairs.toReversed());
      return failed(`Could not connect JACK ports ${pair.outputPort} -> ${pair.inputPort}`, connected);
    }

    createdPairs.push(pair);
  }

  return {
    ok: true,
    message: [
      disconnectedMuted > 0 ? `Disconnected ${disconnectedMuted} muted JACK port pair(s)` : undefined,
      `Connected ${createdPairs.length} JACK port pair(s); ${alreadyConnected} already connected`
    ].filter((item): item is string => item !== undefined).join("; ")
  };
}

async function verifyJackConnections(
  context: JackRuntimeContext,
  configuration: HostRuntimeConfiguration
): Promise<HostRuntimeOperationResult> {
  const validation = validateJackConfiguration(configuration);

  if (!validation.ok) {
    return validation;
  }

  if (context.mode === "dry-run") {
    await context.runJack("verify", "jack_lsp", []);
    await context.runJack("verify", "jack_lsp", ["-c"]);
    return { ok: true, message: `Dry run verified ${activeJackPlanCount(configuration)} JACK connection plan(s)` };
  }

  const prepared = await prepareJackConnectionPlans(context, configuration, "verify");

  if (!isPreparedJackConnectionPlans(prepared)) {
    return prepared;
  }

  const existingPairs = new Set(prepared.existingPairs.map(connectionPairKey));
  const missing = prepared.plans
    .filter((plan) => plan.active)
    .flatMap((plan) => plan.pairs)
    .filter((pair) => !existingPairs.has(connectionPairKey(pair)))
    .map((pair) => `${pair.outputPort} -> ${pair.inputPort}`);
  const muted = prepared.plans
    .filter((plan) => !plan.active)
    .flatMap((plan) => plan.pairs)
    .filter((pair) => existingPairs.has(connectionPairKey(pair)))
    .map((pair) => `${pair.outputPort} -> ${pair.inputPort}`);

  if (missing.length > 0) {
    return { ok: false, message: `Missing JACK connection(s): ${missing.join(", ")}` };
  }

  if (muted.length > 0) {
    return { ok: false, message: `Muted JACK connection(s) still connected: ${muted.join(", ")}` };
  }

  return { ok: true, message: `Verified ${prepared.plans.filter((plan) => plan.active).length} JACK connection plan(s)` };
}

async function unloadJackConnections(
  context: JackRuntimeContext,
  configuration: HostRuntimeConfiguration
): Promise<HostRuntimeOperationResult> {
  const validation = validateJackConfiguration(configuration);

  if (!validation.ok) {
    return validation;
  }

  if (context.mode === "dry-run") {
    await context.runJack("unload", "jack_lsp", []);
    await context.runJack("unload", "jack_lsp", ["-c"]);
    return { ok: true, message: `Dry run disconnected ${activeJackPlanCount(configuration)} JACK connection plan(s)` };
  }

  const prepared = await prepareJackConnectionPlans(context, configuration, "unload");

  if (!isPreparedJackConnectionPlans(prepared)) {
    return prepared;
  }

  const expected = new Set(prepared.plans.flatMap((plan) => plan.pairs).map(connectionPairKey));
  const pairsToDisconnect = prepared.existingPairs.filter((pair) => expected.has(connectionPairKey(pair)));
  const disconnected = await disconnectJackPairs(context, "unload", pairsToDisconnect);

  if (!disconnected.ok) {
    return disconnected;
  }

  return {
    ok: true,
    message: pairsToDisconnect.length === 0
      ? "No Loopwire JACK connections to unload"
      : `Disconnected ${pairsToDisconnect.length} JACK port pair(s)`
  };
}

async function prepareJackConnectionPlans(
  context: JackRuntimeContext,
  configuration: HostRuntimeConfiguration,
  operation: JackRuntimeCommandLogEntry["operation"]
): Promise<PreparedJackConnectionPlans | HostRuntimeOperationResult> {
  const ports = await context.runJack(operation, "jack_lsp", []);
  if (ports.exitCode !== 0) {
    return failed("Could not list JACK ports", ports);
  }

  const connections = await context.runJack(operation, "jack_lsp", ["-c"]);
  if (connections.exitCode !== 0) {
    return failed("Could not list JACK connections", connections);
  }

  const planResult = createJackConnectionPlans(configuration, parsePorts(ports.stdout));

  if (!isJackConnectionPlanResult(planResult)) {
    return planResult;
  }

  return {
    ok: true,
    plans: planResult.plans,
    existingPairs: parseJackConnections(connections.stdout)
  };
}

function validateJackConfiguration(configuration: HostRuntimeConfiguration): HostRuntimeOperationResult {
  for (const route of configuration.routes ?? []) {
    if (route.gain !== undefined && route.gain !== 1) {
      return {
        ok: false,
        message: `Route ${route.id} has gain ${route.gain}; native JACK connections only support unity gain for now`
      };
    }
  }

  for (const monitor of configuration.monitors ?? []) {
    if (!normalizedDeviceName(monitor)) {
      return {
        ok: false,
        message: `Monitor ${monitor.id} needs a deviceName; native JACK monitor routing requires an existing sink`
      };
    }
  }

  return { ok: true };
}

function activeJackPlanCount(configuration: HostRuntimeConfiguration): number {
  return (configuration.routes ?? []).length + configuration.outputs.length *
    (configuration.monitors ?? []).length;
}

function createJackConnectionPlans(
  configuration: HostRuntimeConfiguration,
  ports: readonly string[]
): JackConnectionPlanResult | HostRuntimeOperationResult {
  const inputs = new Map((configuration.inputs ?? []).map((input) => [input.id, input]));
  const outputs = new Map(configuration.outputs.map((output) => [output.id, output]));
  const plans: JackConnectionPlan[] = [];

  for (const route of configuration.routes ?? []) {
    const source = inputs.get(route.from);
    const target = outputs.get(route.to);

    if (!source || !target) {
      return { ok: false, message: `Route ${route.id} references an unknown endpoint` };
    }

    const sourceDeviceName = normalizedDeviceName(source);
    const targetDeviceName = normalizedDeviceName(target);

    if (!sourceDeviceName || !targetDeviceName) {
      return { ok: false, message: `Route ${route.id} needs input and output deviceName for native JACK connections` };
    }

    const sourcePorts = selectEndpointPorts(ports, source, sourceDeviceName);
    const targetPorts = selectEndpointPorts(ports, target, targetDeviceName);
    const channelCount = Math.min(source.channels, target.channels);

    if (sourcePorts.length < channelCount) {
      return { ok: false, message: `Missing JACK output ports for ${source.label} (${sourceDeviceName})` };
    }

    if (targetPorts.length < channelCount) {
      return { ok: false, message: `Missing JACK input ports for ${target.label} (${targetDeviceName})` };
    }

    plans.push({
      routeId: route.id,
      label: `${source.label} -> ${target.label}`,
      active: !route.muted,
      pairs: sourcePorts.slice(0, channelCount).map((outputPort, index) => ({
        outputPort,
        inputPort: targetPorts[index] ?? targetPorts[0] ?? targetDeviceName
      }))
    });
  }

  for (const output of configuration.outputs) {
    const outputDeviceName = normalizedDeviceName(output);

    if (!outputDeviceName) {
      continue;
    }

    const outputMonitorPorts = selectMonitorSourcePorts(ports, output, outputDeviceName);

    for (const monitor of configuration.monitors ?? []) {
      const monitorDeviceName = normalizedDeviceName(monitor);

      if (!monitorDeviceName) {
        return {
          ok: false,
          message: `Monitor ${monitor.id} needs a deviceName; native JACK monitor routing requires an existing sink`
        };
      }

      const monitorTargetPorts = selectEndpointPorts(ports, monitor, monitorDeviceName);
      const channelCount = Math.min(output.channels, monitor.channels);

      if (outputMonitorPorts.length < channelCount) {
        return { ok: false, message: `Missing JACK monitor output ports for ${output.label} (${outputDeviceName})` };
      }

      if (monitorTargetPorts.length < channelCount) {
        return { ok: false, message: `Missing JACK input ports for ${monitor.label} (${monitorDeviceName})` };
      }

      plans.push({
        routeId: `${output.id}->${monitor.id}`,
        label: `${output.label} monitor -> ${monitor.label}`,
        active: true,
        pairs: outputMonitorPorts.slice(0, channelCount).map((outputPort, index) => ({
          outputPort,
          inputPort: monitorTargetPorts[index] ?? monitorTargetPorts[0] ?? monitorDeviceName
        }))
      });
    }
  }

  return { ok: true, plans };
}

function isPreparedJackConnectionPlans(
  result: PreparedJackConnectionPlans | HostRuntimeOperationResult
): result is PreparedJackConnectionPlans {
  return result.ok === true && "plans" in result && "existingPairs" in result;
}

function isJackConnectionPlanResult(
  result: JackConnectionPlanResult | HostRuntimeOperationResult
): result is JackConnectionPlanResult {
  return result.ok === true && "plans" in result;
}

function selectEndpointPorts(
  ports: readonly string[],
  endpoint: HostRuntimeEndpoint,
  deviceName: string
): readonly string[] {
  const matches = ports.filter((port) => port === deviceName || port.startsWith(`${deviceName}:`));
  return matches.slice(0, Math.max(1, endpoint.channels));
}

function selectMonitorSourcePorts(
  ports: readonly string[],
  endpoint: HostRuntimeEndpoint,
  deviceName: string
): readonly string[] {
  const monitorPorts = ports.filter((port) => port.startsWith(`${deviceName}:monitor_`));
  return monitorPorts.slice(0, Math.max(1, endpoint.channels));
}

function normalizedDeviceName(endpoint: HostRuntimeEndpoint): string | undefined {
  const value = endpoint.deviceName?.trim();
  return value ? value : undefined;
}

async function disconnectJackPairs(
  context: JackRuntimeContext,
  operation: JackRuntimeCommandLogEntry["operation"],
  pairs: readonly JackConnectionPair[]
): Promise<HostRuntimeOperationResult> {
  for (const pair of pairs) {
    const disconnected = await context.runJack(operation, "jack_disconnect", [pair.outputPort, pair.inputPort]);

    if (disconnected.exitCode !== 0) {
      return failed(`Could not disconnect JACK ports ${pair.outputPort} -> ${pair.inputPort}`, disconnected);
    }
  }

  return { ok: true };
}

function parsePorts(output: string): readonly string[] {
  return output.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
}

function parseJackConnections(output: string): readonly JackConnectionPair[] {
  const pairs: JackConnectionPair[] = [];
  let currentOutputPort: string | undefined;

  for (const line of output.split(/\r?\n/)) {
    const trimmed = line.trim();

    if (!trimmed) {
      continue;
    }

    if (!/^\s/.test(line)) {
      currentOutputPort = trimmed;
      continue;
    }

    if (currentOutputPort) {
      pairs.push({ outputPort: currentOutputPort, inputPort: trimmed });
    }
  }

  return pairs;
}

function connectionPairKey(pair: JackConnectionPair): string {
  return `${pair.outputPort}\u0000${pair.inputPort}`;
}

function failed(message: string, result: CommandResult): HostRuntimeOperationResult {
  const detail = firstLine(result.stderr) ?? firstLine(result.stdout) ?? `exit ${result.exitCode}`;
  return { ok: false, message: `${message}: ${detail}` };
}

function firstLine(output: string): string | undefined {
  return output.split(/\r?\n/).map((line) => line.trim()).find(Boolean);
}
