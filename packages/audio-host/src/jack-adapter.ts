import { sinkNameForMonitor, sinkNameForOutput } from "./runtime-adapter.js";
import type { HostRuntimeConfiguration, HostRuntimeEndpoint, HostRuntimeOperationResult } from "./runtime-adapter.js";
import type { CommandResult, CommandRunner } from "./types.js";

export type JackRuntimeMode = "dry-run" | "apply";

export interface JackRuntimeAdapterOptions {
  readonly mode?: JackRuntimeMode;
  readonly timeoutMs?: number;
  readonly clientPrefix?: string;
  readonly virtualPortProvider?: JackVirtualPortProvider;
}

export interface JackVirtualPortCommandProviderOptions {
  readonly command?: string;
  readonly timeoutMs?: number;
}

export interface JackPortRequirementOptions {
  readonly clientPrefix?: string;
}

export type JackPortRequirementKind = "route-source" | "route-target" | "monitor-source" | "monitor-target";

export interface JackPortRequirement {
  readonly endpointId: string;
  readonly endpointLabel: string;
  readonly kind: JackPortRequirementKind;
  readonly deviceName: string;
  readonly source: "configured" | "loopwire-owned";
  readonly channelCount: number;
  readonly suggestedPorts: readonly string[];
}

export interface JackPortReadinessRequirement extends JackPortRequirement {
  readonly ready: boolean;
  readonly matchedPorts: readonly string[];
  readonly missingPorts: readonly string[];
}

export interface JackPortReadinessReport {
  readonly ok: boolean;
  readonly requirements: readonly JackPortReadinessRequirement[];
  readonly portCount: number;
  readonly missingCount: number;
}

export interface JackVirtualPortProvisionPlan {
  readonly configurationId: string;
  readonly requirements: readonly JackPortReadinessRequirement[];
  readonly missingPorts: readonly string[];
}

export interface JackVirtualPortProvider {
  ensurePorts(plan: JackVirtualPortProvisionPlan): HostRuntimeOperationResult | Promise<HostRuntimeOperationResult>;
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
  readonly clientPrefix: string;
  readonly virtualPortProvider?: JackVirtualPortProvider;
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
const defaultClientPrefix = "loopwire";

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

export function createJackVirtualPortCommandProvider(
  runner: CommandRunner,
  options: JackVirtualPortCommandProviderOptions = {}
): JackVirtualPortProvider {
  const command = options.command ?? "loopwire-jack-ports";

  return {
    async ensurePorts(plan) {
      const args = jackVirtualPortProviderArgs(plan);
      const result = await runner.run(
        command,
        args,
        options.timeoutMs !== undefined ? { timeoutMs: options.timeoutMs } : {}
      );

      if (result.exitCode !== 0) {
        return {
          ok: false,
          message: `JACK virtual port provider failed: ${firstLine(result.stderr) ?? firstLine(result.stdout) ?? `exit ${result.exitCode}`}`
        };
      }

      return {
        ok: true,
        message: firstLine(result.stdout) ?? "JACK virtual port provider completed"
      };
    }
  };
}

function jackVirtualPortProviderArgs(plan: JackVirtualPortProvisionPlan): readonly string[] {
  return [
    "ensure",
    "--configuration-id",
    plan.configurationId,
    ...plan.requirements.flatMap((requirement) => [
      "--requirement",
      [
        requirement.kind,
        requirement.source,
        requirement.endpointId,
        requirement.deviceName,
        String(requirement.channelCount)
      ].join(":")
    ]),
    ...plan.missingPorts.flatMap((port) => ["--port", port])
  ];
}

export function describeJackPortRequirements(
  configuration: HostRuntimeConfiguration,
  options: JackPortRequirementOptions = {}
): readonly JackPortRequirement[] {
  const clientPrefix = sanitizeName(options.clientPrefix ?? defaultClientPrefix);
  const inputs = new Map((configuration.inputs ?? []).map((input) => [input.id, input]));
  const outputs = new Map(configuration.outputs.map((output) => [output.id, output]));
  const requirements: JackPortRequirement[] = [];

  for (const route of configuration.routes ?? []) {
    const source = inputs.get(route.from);
    const target = outputs.get(route.to);

    if (!source || !target) {
      continue;
    }

    const channelCount = Math.min(source.channels, target.channels);
    requirements.push(jackPortRequirement(clientPrefix, configuration, source, "route-source", channelCount));
    requirements.push(jackPortRequirement(clientPrefix, configuration, target, "route-target", channelCount));
  }

  for (const output of configuration.outputs) {
    for (const monitor of configuration.monitors ?? []) {
      const channelCount = Math.min(output.channels, monitor.channels);
      requirements.push(jackPortRequirement(clientPrefix, configuration, output, "monitor-source", channelCount));
      requirements.push(jackPortRequirement(clientPrefix, configuration, monitor, "monitor-target", channelCount));
    }
  }

  return requirements;
}

export function describeJackPortReadiness(
  configuration: HostRuntimeConfiguration,
  ports: readonly string[],
  options: JackPortRequirementOptions = {}
): JackPortReadinessReport {
  const requirements = describeJackPortRequirements(configuration, options).map((requirement) => {
    const matchedPorts = matchingJackPorts(requirement.kind, requirement.deviceName, ports).slice(0, requirement.channelCount);
    const missingPorts = missingSuggestedJackPorts(requirement.kind, requirement.deviceName, requirement.channelCount, ports);

    return {
      ...requirement,
      ready: matchedPorts.length >= requirement.channelCount,
      matchedPorts,
      missingPorts
    };
  });
  const missingCount = requirements.reduce((count, requirement) => count + requirement.missingPorts.length, 0);

  return {
    ok: missingCount === 0,
    requirements,
    portCount: ports.length,
    missingCount
  };
}

function createJackRuntimeContext(
  runner: CommandRunner,
  options: JackRuntimeAdapterOptions,
  commandLog: JackRuntimeCommandLogEntry[]
): JackRuntimeContext {
  const mode = options.mode ?? "dry-run";
  const timeoutMs = options.timeoutMs ?? defaultTimeoutMs;
  const clientPrefix = sanitizeName(options.clientPrefix ?? defaultClientPrefix);

  return {
    mode,
    clientPrefix,
    ...(options.virtualPortProvider ? { virtualPortProvider: options.virtualPortProvider } : {}),
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

  const ensuredPorts = await ensureLoopwireOwnedJackPorts(
    context,
    configuration,
    parsePorts(ports.stdout),
    operation
  );

  if (!isJackPortList(ensuredPorts)) {
    return ensuredPorts;
  }

  const planResult = createJackConnectionPlans(configuration, ensuredPorts.ports, context.clientPrefix);

  if (!isJackConnectionPlanResult(planResult)) {
    return planResult;
  }

  return {
    ok: true,
    plans: planResult.plans,
    existingPairs: parseJackConnections(connections.stdout)
  };
}

async function ensureLoopwireOwnedJackPorts(
  context: JackRuntimeContext,
  configuration: HostRuntimeConfiguration,
  ports: readonly string[],
  operation: JackRuntimeCommandLogEntry["operation"]
): Promise<{ readonly ports: readonly string[] } | HostRuntimeOperationResult> {
  if (!context.virtualPortProvider) {
    return { ports };
  }

  const readiness = describeJackPortReadiness(configuration, ports, { clientPrefix: context.clientPrefix });
  const missingRequirements = readiness.requirements.filter((requirement) => !requirement.ready);
  const missingLoopwireRequirements = missingRequirements.filter((requirement) => requirement.source === "loopwire-owned");

  if (missingLoopwireRequirements.length === 0 || missingRequirements.length !== missingLoopwireRequirements.length) {
    return { ports };
  }

  const plan: JackVirtualPortProvisionPlan = {
    configurationId: configuration.id,
    requirements: missingLoopwireRequirements,
    missingPorts: uniqueSorted(missingLoopwireRequirements.flatMap((requirement) => requirement.missingPorts))
  };
  const result = await context.virtualPortProvider.ensurePorts(plan);

  if (!result.ok) {
    return {
      ok: false,
      message: `Could not create Loopwire JACK virtual ports: ${result.message ?? "provider failed"}`
    };
  }

  const refreshed = await context.runJack(operation, "jack_lsp", []);

  if (refreshed.exitCode !== 0) {
    return failed("Could not list JACK ports after virtual port creation", refreshed);
  }

  const refreshedPorts = parsePorts(refreshed.stdout);
  const remainingMissingPorts = describeJackPortReadiness(configuration, refreshedPorts, {
    clientPrefix: context.clientPrefix
  }).requirements
    .filter((requirement) => !requirement.ready && requirement.source === "loopwire-owned")
    .flatMap((requirement) => requirement.missingPorts);

  if (remainingMissingPorts.length > 0) {
    return {
      ok: false,
      message: `Loopwire JACK virtual port provider did not create required ports: ${uniqueSorted(
        remainingMissingPorts
      ).join(", ")}`
    };
  }

  return { ports: refreshedPorts };
}

function isJackPortList(
  result: { readonly ports: readonly string[] } | HostRuntimeOperationResult
): result is { readonly ports: readonly string[] } {
  return "ports" in result;
}

function validateJackConfiguration(configuration: HostRuntimeConfiguration): HostRuntimeOperationResult {
  const inputs = new Map((configuration.inputs ?? []).map((input) => [input.id, input]));
  const outputs = new Map(configuration.outputs.map((output) => [output.id, output]));

  for (const route of configuration.routes ?? []) {
    if (!route.muted && route.gain !== undefined && route.gain !== 1) {
      return {
        ok: false,
        message: `Route ${route.id} has gain ${route.gain}; native JACK connections only support unity gain for now`
      };
    }

    const source = inputs.get(route.from);
    const target = outputs.get(route.to);

    if (!source || !target) {
      return { ok: false, message: `Route ${route.id} references an unknown endpoint` };
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
  ports: readonly string[],
  clientPrefix: string
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

    const sourceDeviceName = jackEndpointDeviceName(clientPrefix, configuration, source, "input");
    const targetDeviceName = jackEndpointDeviceName(clientPrefix, configuration, target, "output");

    const sourcePorts = selectEndpointPorts(ports, source, sourceDeviceName);
    const targetPorts = selectEndpointPorts(ports, target, targetDeviceName);
    const channelCount = Math.min(source.channels, target.channels);

    if (sourcePorts.length < channelCount) {
      return {
        ok: false,
        message: missingJackPortsMessage("output", source.label, sourceDeviceName, "route-source", channelCount, ports)
      };
    }

    if (targetPorts.length < channelCount) {
      return {
        ok: false,
        message: missingJackPortsMessage("input", target.label, targetDeviceName, "route-target", channelCount, ports)
      };
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
    const outputDeviceName = jackEndpointDeviceName(clientPrefix, configuration, output, "output");
    const outputMonitorPorts = selectMonitorSourcePorts(ports, output, outputDeviceName);

    for (const monitor of configuration.monitors ?? []) {
      const monitorDeviceName = jackEndpointDeviceName(clientPrefix, configuration, monitor, "monitor");
      const monitorTargetPorts = selectEndpointPorts(ports, monitor, monitorDeviceName);
      const channelCount = Math.min(output.channels, monitor.channels);

      if (outputMonitorPorts.length < channelCount) {
        return {
          ok: false,
          message: missingJackPortsMessage("monitor output", output.label, outputDeviceName, "monitor-source", channelCount, ports)
        };
      }

      if (monitorTargetPorts.length < channelCount) {
        return {
          ok: false,
          message: missingJackPortsMessage("input", monitor.label, monitorDeviceName, "monitor-target", channelCount, ports)
        };
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

type JackEndpointKind = "input" | "output" | "monitor";

function jackEndpointDeviceName(
  clientPrefix: string,
  configuration: HostRuntimeConfiguration,
  endpoint: HostRuntimeEndpoint,
  kind: JackEndpointKind
): string {
  const explicitDeviceName = normalizedDeviceName(endpoint);

  if (explicitDeviceName) {
    return explicitDeviceName;
  }

  if (kind === "input") {
    return [
      sanitizeName(clientPrefix),
      sanitizeName(configuration.id),
      "input",
      sanitizeName(endpoint.id)
    ].join("_").slice(0, 80);
  }

  if (kind === "monitor") {
    return sinkNameForMonitor(clientPrefix, configuration, endpoint);
  }

  return sinkNameForOutput(clientPrefix, configuration, endpoint);
}

function jackPortRequirement(
  clientPrefix: string,
  configuration: HostRuntimeConfiguration,
  endpoint: HostRuntimeEndpoint,
  kind: JackPortRequirementKind,
  channelCount: number
): JackPortRequirement {
  const endpointKind = kind === "route-source"
    ? "input"
    : kind === "monitor-target"
      ? "monitor"
      : "output";
  const deviceName = jackEndpointDeviceName(clientPrefix, configuration, endpoint, endpointKind);

  return {
    endpointId: endpoint.id,
    endpointLabel: endpoint.label,
    kind,
    deviceName,
    source: normalizedDeviceName(endpoint) ? "configured" : "loopwire-owned",
    channelCount,
    suggestedPorts: suggestedJackPorts(deviceName, kind, channelCount)
  };
}

function suggestedJackPorts(
  deviceName: string,
  kind: JackPortRequirementKind,
  channelCount: number
): readonly string[] {
  const suffix = kind === "route-source"
    ? "capture"
    : kind === "monitor-source"
      ? "monitor"
      : "playback";

  return Array.from({ length: Math.max(1, channelCount) }, (_, index) => `${deviceName}:${suffix}_${index + 1}`);
}

function matchingJackPorts(
  kind: JackPortRequirementKind,
  deviceName: string,
  ports: readonly string[]
): readonly string[] {
  if (kind === "monitor-source") {
    return ports.filter((port) => port.startsWith(`${deviceName}:monitor_`));
  }

  return ports.filter((port) => port === deviceName || port.startsWith(`${deviceName}:`));
}

function missingSuggestedJackPorts(
  kind: JackPortRequirementKind,
  deviceName: string,
  channelCount: number,
  ports: readonly string[]
): readonly string[] {
  const missingCount = Math.max(0, channelCount - matchingJackPorts(kind, deviceName, ports).length);

  if (missingCount === 0) {
    return [];
  }

  const portSet = new Set(ports);
  return suggestedJackPorts(deviceName, kind, channelCount)
    .filter((port) => !portSet.has(port))
    .slice(0, missingCount);
}

function missingJackPortsMessage(
  role: string,
  label: string,
  deviceName: string,
  kind: JackPortRequirementKind,
  channelCount: number,
  ports: readonly string[]
): string {
  const missingPorts = missingSuggestedJackPorts(kind, deviceName, channelCount, ports);
  const suffix = missingPorts.length > 0 ? `: ${missingPorts.join(", ")}` : "";

  return `Missing JACK ${role} ports for ${label} (${deviceName})${suffix}`;
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

function uniqueSorted(values: readonly string[]): readonly string[] {
  return [...new Set(values)].sort((left, right) => left.localeCompare(right));
}

function sanitizeName(value: string): string {
  const sanitized = value
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, "_")
    .replace(/_+/g, "_")
    .replace(/^_+|_+$/g, "");

  return sanitized || "unnamed";
}
