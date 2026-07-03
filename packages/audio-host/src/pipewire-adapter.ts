import type { CommandResult, CommandRunner } from "./types.js";
import { sinkNameForMonitor, sinkNameForOutput } from "./runtime-adapter.js";
import type { HostRuntimeConfiguration, HostRuntimeEndpoint, HostRuntimeOperationResult } from "./runtime-adapter.js";

export type PipeWireRuntimeMode = "dry-run" | "apply";

export interface PipeWireRuntimeAdapterOptions {
  readonly mode?: PipeWireRuntimeMode;
  readonly sinkPrefix?: string;
  readonly timeoutMs?: number;
}

export interface PipeWireRuntimeCommandLogEntry {
  readonly operation: "unload" | "apply" | "verify" | "rollback";
  readonly command: "pw-link" | "pw-cli";
  readonly args: readonly string[];
  readonly skipped: boolean;
}

export interface PipeWireGraphRuntimeAdapter {
  readonly commandLog: readonly PipeWireRuntimeCommandLogEntry[];
  unload(configuration: HostRuntimeConfiguration): Promise<HostRuntimeOperationResult>;
  apply(configuration: HostRuntimeConfiguration): Promise<HostRuntimeOperationResult>;
  verify(configuration: HostRuntimeConfiguration): Promise<HostRuntimeOperationResult>;
  rollback(configuration: HostRuntimeConfiguration): Promise<HostRuntimeOperationResult>;
}

interface PipeWireRuntimeContext {
  readonly mode: PipeWireRuntimeMode;
  readonly sinkPrefix: string;
  runPwLink(
    operation: PipeWireRuntimeCommandLogEntry["operation"],
    args: readonly string[]
  ): Promise<CommandResult>;
  runPwCli(
    operation: PipeWireRuntimeCommandLogEntry["operation"],
    args: readonly string[]
  ): Promise<CommandResult>;
}

interface PipeWireRoutePlan {
  readonly routeId: string;
  readonly label: string;
  readonly active: boolean;
  readonly pairs: readonly PipeWireLinkPair[];
}

interface PipeWireLinkPair {
  readonly outputPort: string;
  readonly inputPort: string;
}

interface PipeWireRoutePlanResult {
  readonly ok: true;
  readonly plans: readonly PipeWireRoutePlan[];
}

interface PreparedPipeWireRoutePlans extends PipeWireRoutePlanResult {
  readonly existingPairs: readonly PipeWireLinkPair[];
}

interface PipeWireNode {
  readonly id: string;
  readonly name: string;
}

interface PipeWireVirtualSinkEndpoint {
  readonly kind: "output" | "monitor";
  readonly endpoint: HostRuntimeEndpoint;
}

function isPipeWireNodeList(
  result: readonly PipeWireNode[] | HostRuntimeOperationResult
): result is readonly PipeWireNode[] {
  return Array.isArray(result);
}

const defaultTimeoutMs = 5000;
const defaultSinkPrefix = "loopwire";

export function createPipeWireGraphRuntimeAdapter(
  runner: CommandRunner,
  options: PipeWireRuntimeAdapterOptions = {}
): PipeWireGraphRuntimeAdapter {
  const commandLog: PipeWireRuntimeCommandLogEntry[] = [];
  const context = createPipeWireRuntimeContext(runner, options, commandLog);

  return {
    commandLog,
    unload: (configuration) => unloadPipeWireLinks(context, configuration),
    apply: (configuration) => applyPipeWireLinks(context, configuration),
    verify: (configuration) => verifyPipeWireLinks(context, configuration),
    rollback: (configuration) => unloadPipeWireLinks(context, configuration)
  };
}

function createPipeWireRuntimeContext(
  runner: CommandRunner,
  options: PipeWireRuntimeAdapterOptions,
  commandLog: PipeWireRuntimeCommandLogEntry[]
): PipeWireRuntimeContext {
  const mode = options.mode ?? "dry-run";
  const timeoutMs = options.timeoutMs ?? defaultTimeoutMs;
  const sinkPrefix = options.sinkPrefix ?? defaultSinkPrefix;

  return {
    mode,
    sinkPrefix,
    async runPwLink(operation, args) {
      commandLog.push({ operation, command: "pw-link", args, skipped: mode === "dry-run" });

      if (mode === "dry-run") {
        return { command: "pw-link", args, exitCode: 0, stdout: "", stderr: "" };
      }

      return runner.run("pw-link", args, { timeoutMs });
    },
    async runPwCli(operation, args) {
      commandLog.push({ operation, command: "pw-cli", args, skipped: mode === "dry-run" });

      if (mode === "dry-run") {
        return { command: "pw-cli", args, exitCode: 0, stdout: "", stderr: "" };
      }

      return runner.run("pw-cli", args, { timeoutMs });
    }
  };
}

async function applyPipeWireLinks(
  context: PipeWireRuntimeContext,
  configuration: HostRuntimeConfiguration
): Promise<HostRuntimeOperationResult> {
  const validation = validatePipeWireConfiguration(configuration);

  if (!validation.ok) {
    return validation;
  }

  if (context.mode === "dry-run") {
    await context.runPwLink("apply", ["-o"]);
    await context.runPwLink("apply", ["-i"]);
    await context.runPwLink("apply", ["-l"]);
    return { ok: true, message: `Dry run planned ${activePipeWirePlanCount(configuration)} PipeWire link plan(s)` };
  }

  const createdNodes = await createMissingVirtualSinkNodes(context, configuration, "apply");

  if (!isPipeWireNodeList(createdNodes)) {
    return createdNodes;
  }

  const effectiveConfiguration = withVirtualEndpointDeviceNames(context, configuration);
  const prepared = await preparePipeWireRoutePlans(context, effectiveConfiguration, "apply");

  if (!isPreparedPipeWireRoutePlans(prepared)) {
    await destroyPipeWireNodes(context, "rollback", createdNodes);
    return prepared;
  }

  const existingPairs = new Set(prepared.existingPairs.map(linkPairKey));
  const createdPairs: PipeWireLinkPair[] = [];
  const mutedPairs = prepared.plans.filter((plan) => !plan.active).flatMap((plan) => plan.pairs);
  let unlinkedMuted = 0;
  let alreadyLinked = 0;

  for (const pair of mutedPairs) {
    if (!existingPairs.has(linkPairKey(pair))) {
      continue;
    }

    const unlinked = await context.runPwLink("apply", ["-d", pair.outputPort, pair.inputPort]);
    if (unlinked.exitCode !== 0) {
      await destroyPipeWireNodes(context, "rollback", createdNodes);
      return failed(`Could not unlink muted PipeWire ports ${pair.outputPort} -> ${pair.inputPort}`, unlinked);
    }

    existingPairs.delete(linkPairKey(pair));
    unlinkedMuted += 1;
  }

  for (const pair of prepared.plans.filter((plan) => plan.active).flatMap((plan) => plan.pairs)) {
    if (existingPairs.has(linkPairKey(pair))) {
      alreadyLinked += 1;
      continue;
    }

    const linked = await context.runPwLink("apply", [pair.outputPort, pair.inputPort]);
    if (linked.exitCode !== 0) {
      await unlinkPipeWirePairs(context, "rollback", createdPairs.toReversed());
      await destroyPipeWireNodes(context, "rollback", createdNodes);
      return failed(`Could not link PipeWire ports ${pair.outputPort} -> ${pair.inputPort}`, linked);
    }

    createdPairs.push(pair);
  }

  return {
    ok: true,
    message: [
      createdNodes.length > 0 ? `Created ${createdNodes.length} PipeWire virtual sink node(s)` : undefined,
      unlinkedMuted > 0 ? `Unlinked ${unlinkedMuted} muted PipeWire link pair(s)` : undefined,
      `Linked ${createdPairs.length} PipeWire port pair(s); ${alreadyLinked} already linked`
    ].filter((item): item is string => item !== undefined).join("; ")
  };
}

async function verifyPipeWireLinks(
  context: PipeWireRuntimeContext,
  configuration: HostRuntimeConfiguration
): Promise<HostRuntimeOperationResult> {
  const validation = validatePipeWireConfiguration(configuration);

  if (!validation.ok) {
    return validation;
  }

  if (context.mode === "dry-run") {
    await context.runPwLink("verify", ["-o"]);
    await context.runPwLink("verify", ["-i"]);
    await context.runPwLink("verify", ["-l"]);
    return { ok: true, message: `Dry run verified ${activePipeWirePlanCount(configuration)} PipeWire link plan(s)` };
  }

  const prepared = await preparePipeWireRoutePlans(context, withVirtualEndpointDeviceNames(context, configuration), "verify");

  if (!isPreparedPipeWireRoutePlans(prepared)) {
    return prepared;
  }

  const existingPairs = new Set(prepared.existingPairs.map(linkPairKey));
  const missing = prepared.plans
    .filter((plan) => plan.active)
    .flatMap((plan) => plan.pairs)
    .filter((pair) => !existingPairs.has(linkPairKey(pair)))
    .map((pair) => `${pair.outputPort} -> ${pair.inputPort}`);
  const muted = prepared.plans
    .filter((plan) => !plan.active)
    .flatMap((plan) => plan.pairs)
    .filter((pair) => existingPairs.has(linkPairKey(pair)))
    .map((pair) => `${pair.outputPort} -> ${pair.inputPort}`);

  if (missing.length > 0) {
    return { ok: false, message: `Missing PipeWire link(s): ${missing.join(", ")}` };
  }

  if (muted.length > 0) {
    return { ok: false, message: `Muted PipeWire link(s) still connected: ${muted.join(", ")}` };
  }

  return { ok: true, message: `Verified ${prepared.plans.filter((plan) => plan.active).length} PipeWire link plan(s)` };
}

async function unloadPipeWireLinks(
  context: PipeWireRuntimeContext,
  configuration: HostRuntimeConfiguration
): Promise<HostRuntimeOperationResult> {
  const validation = validatePipeWireConfiguration(configuration);

  if (!validation.ok) {
    return validation;
  }

  if (context.mode === "dry-run") {
    await context.runPwLink("unload", ["-o"]);
    await context.runPwLink("unload", ["-i"]);
    await context.runPwLink("unload", ["-l"]);
    return { ok: true, message: `Dry run unlinked ${activePipeWirePlanCount(configuration)} PipeWire link plan(s)` };
  }

  const effectiveConfiguration = withVirtualEndpointDeviceNames(context, configuration);
  const prepared = await preparePipeWireRoutePlans(context, effectiveConfiguration, "unload");

  if (!isPreparedPipeWireRoutePlans(prepared)) {
    return prepared;
  }

  const expected = new Set(prepared.plans.flatMap((plan) => plan.pairs).map(linkPairKey));
  const pairsToUnlink = prepared.existingPairs.filter((pair) => expected.has(linkPairKey(pair)));
  const unlinked = await unlinkPipeWirePairs(context, "unload", pairsToUnlink);

  if (!unlinked.ok) {
    return unlinked;
  }

  const destroyed = await destroyConfiguredVirtualSinkNodes(context, "unload", configuration);

  if (typeof destroyed !== "number") {
    return destroyed;
  }

  return {
    ok: true,
    message: [
      pairsToUnlink.length === 0 ? "No Loopwire PipeWire links to unload" : `Unlinked ${pairsToUnlink.length} PipeWire port pair(s)`,
      destroyed > 0 ? `Destroyed ${destroyed} PipeWire virtual sink node(s)` : undefined
    ].filter((item): item is string => item !== undefined).join("; ")
  };
}

async function preparePipeWireRoutePlans(
  context: PipeWireRuntimeContext,
  configuration: HostRuntimeConfiguration,
  operation: PipeWireRuntimeCommandLogEntry["operation"]
): Promise<PreparedPipeWireRoutePlans | HostRuntimeOperationResult> {
  const outputPorts = await context.runPwLink(operation, ["-o"]);
  if (outputPorts.exitCode !== 0) {
    return failed("Could not list PipeWire output ports", outputPorts);
  }

  const inputPorts = await context.runPwLink(operation, ["-i"]);
  if (inputPorts.exitCode !== 0) {
    return failed("Could not list PipeWire input ports", inputPorts);
  }

  const links = await context.runPwLink(operation, ["-l"]);
  if (links.exitCode !== 0) {
    return failed("Could not list PipeWire links", links);
  }

  const planResult = createPipeWireRoutePlans(configuration, parsePorts(outputPorts.stdout), parsePorts(inputPorts.stdout));

  if (!isPipeWireRoutePlanResult(planResult)) {
    return planResult;
  }

  return {
    ok: true,
    plans: planResult.plans,
    existingPairs: parsePipeWireLinks(links.stdout)
  };
}

function validatePipeWireConfiguration(configuration: HostRuntimeConfiguration): HostRuntimeOperationResult {
  for (const route of configuration.routes ?? []) {
    if (route.gain !== undefined && route.gain !== 1) {
      return {
        ok: false,
        message: `Route ${route.id} has gain ${route.gain}; native PipeWire links only support unity gain for now`
      };
    }
  }

  return { ok: true };
}

async function createMissingVirtualSinkNodes(
  context: PipeWireRuntimeContext,
  configuration: HostRuntimeConfiguration,
  operation: PipeWireRuntimeCommandLogEntry["operation"]
): Promise<readonly PipeWireNode[] | HostRuntimeOperationResult> {
  const virtualSinks = virtualSinkEndpoints(configuration);

  if (virtualSinks.length === 0) {
    return [];
  }

  const nodes = await listPipeWireNodes(context, operation);

  if (!isPipeWireNodeList(nodes)) {
    return nodes;
  }

  const nodesByName = new Map(nodes.map((node) => [node.name, node]));
  const createdNodes: PipeWireNode[] = [];

  for (const target of virtualSinks) {
    const nodeName = virtualSinkNodeName(context, configuration, target);

    if (nodesByName.has(nodeName)) {
      continue;
    }

    const created = await context.runPwCli(operation, [
      "create-node",
      "adapter",
      renderPipeWireVirtualSinkProps(nodeName, target.endpoint.label, target.endpoint.channels)
    ]);

    if (created.exitCode !== 0) {
      await destroyPipeWireNodes(context, "rollback", createdNodes.toReversed());
      return failed(`Could not create PipeWire virtual ${target.kind} sink ${target.endpoint.label}`, created);
    }

    const refreshed = await listPipeWireNodes(context, operation);

    if (!isPipeWireNodeList(refreshed)) {
      await destroyPipeWireNodes(context, "rollback", createdNodes.toReversed());
      return refreshed;
    }

    const node = refreshed.find((candidate) => candidate.name === nodeName);

    if (!node) {
      await destroyPipeWireNodes(context, "rollback", createdNodes.toReversed());
      return { ok: false, message: `PipeWire virtual sink ${nodeName} did not appear after creation` };
    }

    nodesByName.set(nodeName, node);
    createdNodes.push(node);
  }

  return createdNodes;
}

async function destroyConfiguredVirtualSinkNodes(
  context: PipeWireRuntimeContext,
  operation: PipeWireRuntimeCommandLogEntry["operation"],
  configuration: HostRuntimeConfiguration
): Promise<number | HostRuntimeOperationResult> {
  const virtualSinks = virtualSinkEndpoints(configuration);

  if (virtualSinks.length === 0) {
    return 0;
  }

  const nodes = await listPipeWireNodes(context, operation);

  if (!isPipeWireNodeList(nodes)) {
    return nodes;
  }

  const nodeNames = new Set(virtualSinks.map((target) => virtualSinkNodeName(context, configuration, target)));
  const destroyTargets = nodes.filter((node) => nodeNames.has(node.name));
  const destroyed = await destroyPipeWireNodes(context, operation, destroyTargets);

  if (!destroyed.ok) {
    return destroyed;
  }

  return destroyTargets.length;
}

async function listPipeWireNodes(
  context: PipeWireRuntimeContext,
  operation: PipeWireRuntimeCommandLogEntry["operation"]
): Promise<readonly PipeWireNode[] | HostRuntimeOperationResult> {
  const listed = await context.runPwCli(operation, ["list-objects", "Node"]);

  if (listed.exitCode !== 0) {
    return failed("Could not list PipeWire nodes", listed);
  }

  return parsePipeWireNodes(listed.stdout);
}

async function destroyPipeWireNodes(
  context: PipeWireRuntimeContext,
  operation: PipeWireRuntimeCommandLogEntry["operation"],
  nodes: readonly PipeWireNode[]
): Promise<HostRuntimeOperationResult> {
  for (const node of nodes) {
    const destroyed = await context.runPwCli(operation, ["destroy", node.id]);

    if (destroyed.exitCode !== 0) {
      return failed(`Could not destroy PipeWire virtual sink ${node.name}`, destroyed);
    }
  }

  return { ok: true };
}

function withVirtualEndpointDeviceNames(
  context: PipeWireRuntimeContext,
  configuration: HostRuntimeConfiguration
): HostRuntimeConfiguration {
  return {
    ...configuration,
    outputs: configuration.outputs.map((output) => (
      normalizedDeviceName(output)
        ? output
        : { ...output, deviceName: virtualSinkNodeName(context, configuration, { kind: "output", endpoint: output }) }
    )),
    monitors: (configuration.monitors ?? []).map((monitor) => (
      normalizedDeviceName(monitor)
        ? monitor
        : { ...monitor, deviceName: virtualSinkNodeName(context, configuration, { kind: "monitor", endpoint: monitor }) }
    ))
  };
}

function virtualSinkEndpoints(configuration: HostRuntimeConfiguration): readonly PipeWireVirtualSinkEndpoint[] {
  const outputs = configuration.outputs
    .filter((output) => !normalizedDeviceName(output))
    .map((endpoint): PipeWireVirtualSinkEndpoint => ({ kind: "output", endpoint }));
  const monitors = (configuration.monitors ?? [])
    .filter((monitor) => !normalizedDeviceName(monitor))
    .map((endpoint): PipeWireVirtualSinkEndpoint => ({ kind: "monitor", endpoint }));

  return [...outputs, ...monitors];
}

function virtualSinkNodeName(
  context: PipeWireRuntimeContext,
  configuration: HostRuntimeConfiguration,
  target: PipeWireVirtualSinkEndpoint
): string {
  return target.kind === "output"
    ? sinkNameForOutput(context.sinkPrefix, configuration, target.endpoint)
    : sinkNameForMonitor(context.sinkPrefix, configuration, target.endpoint);
}

function renderPipeWireVirtualSinkProps(nodeName: string, description: string, channels: number): string {
  return `{ factory.name=support.null-audio-sink node.name="${escapePipeWireString(nodeName)}" ` +
    `node.description="${escapePipeWireString(description)}" media.class=Audio/Sink object.linger=true ` +
    `audio.position=[${audioPositionsForChannels(channels).join(" ")}] ` +
    "adapter.auto-port-config={ mode=dsp monitor=true position=preserve } }";
}

function escapePipeWireString(value: string): string {
  return value.replace(/\\/g, "\\\\").replace(/"/g, "\\\"");
}

function audioPositionsForChannels(channels: number): readonly string[] {
  const layouts: Record<number, readonly string[]> = {
    1: ["MONO"],
    2: ["FL", "FR"],
    3: ["FL", "FR", "FC"],
    4: ["FL", "FR", "RL", "RR"],
    5: ["FL", "FR", "FC", "RL", "RR"],
    6: ["FL", "FR", "FC", "LFE", "RL", "RR"],
    8: ["FL", "FR", "FC", "LFE", "RL", "RR", "SL", "SR"]
  };

  if (layouts[channels]) {
    return layouts[channels];
  }

  return Array.from({ length: Math.max(1, channels) }, (_value, index) => `AUX${index}`);
}

function activePipeWirePlanCount(configuration: HostRuntimeConfiguration): number {
  return (configuration.routes ?? []).length + configuration.outputs.length *
    (configuration.monitors ?? []).length;
}

function createPipeWireRoutePlans(
  configuration: HostRuntimeConfiguration,
  outputPorts: readonly string[],
  inputPorts: readonly string[]
): PipeWireRoutePlanResult | HostRuntimeOperationResult {
  const inputs = new Map((configuration.inputs ?? []).map((input) => [input.id, input]));
  const outputs = new Map(configuration.outputs.map((output) => [output.id, output]));
  const plans: PipeWireRoutePlan[] = [];

  for (const route of configuration.routes ?? []) {
    const source = inputs.get(route.from);
    const target = outputs.get(route.to);

    if (!source || !target) {
      return { ok: false, message: `Route ${route.id} references an unknown endpoint` };
    }

    const sourceDeviceName = normalizedDeviceName(source);
    const targetDeviceName = normalizedDeviceName(target);

    if (!sourceDeviceName || !targetDeviceName) {
      return { ok: false, message: `Route ${route.id} needs input and output deviceName for native PipeWire linking` };
    }

    const sourcePorts = selectEndpointPorts(outputPorts, source, sourceDeviceName);
    const targetPorts = selectEndpointPorts(inputPorts, target, targetDeviceName);
    const channelCount = Math.min(source.channels, target.channels);

    if (sourcePorts.length < channelCount) {
      return { ok: false, message: `Missing PipeWire output ports for ${source.label} (${sourceDeviceName})` };
    }

    if (targetPorts.length < channelCount) {
      return { ok: false, message: `Missing PipeWire input ports for ${target.label} (${targetDeviceName})` };
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

    const outputMonitorPorts = selectMonitorSourcePorts(outputPorts, output, outputDeviceName);

    for (const monitor of configuration.monitors ?? []) {
      const monitorDeviceName = normalizedDeviceName(monitor);

      if (!monitorDeviceName) {
        return {
          ok: false,
          message: `Monitor ${monitor.id} needs a deviceName; native PipeWire monitor routing requires an existing sink`
        };
      }

      const monitorTargetPorts = selectEndpointPorts(inputPorts, monitor, monitorDeviceName);
      const channelCount = Math.min(output.channels, monitor.channels);

      if (outputMonitorPorts.length < channelCount) {
        return { ok: false, message: `Missing PipeWire monitor output ports for ${output.label} (${outputDeviceName})` };
      }

      if (monitorTargetPorts.length < channelCount) {
        return { ok: false, message: `Missing PipeWire input ports for ${monitor.label} (${monitorDeviceName})` };
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

function isPreparedPipeWireRoutePlans(
  result: PreparedPipeWireRoutePlans | HostRuntimeOperationResult
): result is PreparedPipeWireRoutePlans {
  return result.ok === true && "plans" in result && "existingPairs" in result;
}

function isPipeWireRoutePlanResult(
  result: PipeWireRoutePlanResult | HostRuntimeOperationResult
): result is PipeWireRoutePlanResult {
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

async function unlinkPipeWirePairs(
  context: PipeWireRuntimeContext,
  operation: PipeWireRuntimeCommandLogEntry["operation"],
  pairs: readonly PipeWireLinkPair[]
): Promise<HostRuntimeOperationResult> {
  for (const pair of pairs) {
    const unlinked = await context.runPwLink(operation, ["-d", pair.outputPort, pair.inputPort]);

    if (unlinked.exitCode !== 0) {
      return failed(`Could not unlink PipeWire ports ${pair.outputPort} -> ${pair.inputPort}`, unlinked);
    }
  }

  return { ok: true };
}

function parsePorts(output: string): readonly string[] {
  return output.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
}

function parsePipeWireLinks(output: string): readonly PipeWireLinkPair[] {
  const pairs: PipeWireLinkPair[] = [];
  let currentOutputPort: string | undefined;

  for (const line of output.split(/\r?\n/)) {
    const trimmed = line.trim();

    if (!trimmed) {
      continue;
    }

    if (!trimmed.startsWith("|")) {
      currentOutputPort = trimmed;
      continue;
    }

    const target = trimmed.match(/^\|->\s+(.+)$/)?.[1]?.trim();
    if (currentOutputPort && target) {
      pairs.push({ outputPort: currentOutputPort, inputPort: target });
    }
  }

  return pairs;
}

function parsePipeWireNodes(output: string): readonly PipeWireNode[] {
  const nodes: PipeWireNode[] = [];
  let currentId: string | undefined;
  let currentName: string | undefined;

  const flush = () => {
    if (currentId && currentName) {
      nodes.push({ id: currentId, name: currentName });
    }
  };

  for (const line of output.split(/\r?\n/)) {
    const id = line.trim().match(/^id\s+(\d+),/)?.[1];

    if (id) {
      flush();
      currentId = id;
      currentName = undefined;
      continue;
    }

    const name = line.trim().match(/^node\.name\s*=\s*"(.+)"$/)?.[1];

    if (name) {
      currentName = name;
    }
  }

  flush();
  return nodes;
}

function linkPairKey(pair: PipeWireLinkPair): string {
  return `${pair.outputPort}\u0000${pair.inputPort}`;
}

function failed(message: string, result: CommandResult): HostRuntimeOperationResult {
  const detail = firstLine(result.stderr) ?? firstLine(result.stdout) ?? `exit ${result.exitCode}`;
  return { ok: false, message: `${message}: ${detail}` };
}

function firstLine(output: string): string | undefined {
  return output.split(/\r?\n/).map((line) => line.trim()).find(Boolean);
}
