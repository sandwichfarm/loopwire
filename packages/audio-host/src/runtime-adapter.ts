import type { CommandResult, CommandRunner } from "./types.js";

export type PactlRuntimeMode = "dry-run" | "apply";
export type MissingStreamVerificationMode = "fail" | "pending";

export interface HostRuntimeEndpoint {
  readonly id: string;
  readonly label: string;
  readonly channels: number;
  readonly deviceName?: string;
}

export interface HostRuntimeConfiguration {
  readonly id: string;
  readonly name: string;
  readonly inputs?: readonly HostRuntimeEndpoint[];
  readonly outputs: readonly HostRuntimeEndpoint[];
  readonly monitors?: readonly HostRuntimeEndpoint[];
  readonly routes?: readonly HostRuntimeRoute[];
}

export interface HostRuntimeRoute {
  readonly id: string;
  readonly from: string;
  readonly to: string;
  readonly gain?: number;
  readonly muted: boolean;
}

export interface HostRuntimeOperationResult {
  readonly ok: boolean;
  readonly message?: string;
}

export interface PactlRuntimeAdapterOptions {
  readonly mode?: PactlRuntimeMode;
  readonly missingStreamVerification?: MissingStreamVerificationMode;
  readonly sinkPrefix?: string;
  readonly timeoutMs?: number;
}

export interface PactlRuntimeCommandLogEntry {
  readonly operation: "unload" | "apply" | "verify" | "rollback";
  readonly command: string;
  readonly args: readonly string[];
  readonly skipped: boolean;
}

export interface PactlVirtualSinkRuntimeAdapter {
  readonly commandLog: readonly PactlRuntimeCommandLogEntry[];
  unload(configuration: HostRuntimeConfiguration): Promise<HostRuntimeOperationResult>;
  apply(configuration: HostRuntimeConfiguration): Promise<HostRuntimeOperationResult>;
  refreshRoutes(configuration: HostRuntimeConfiguration): Promise<HostRuntimeOperationResult>;
  verify(configuration: HostRuntimeConfiguration): Promise<HostRuntimeOperationResult>;
  rollback(configuration: HostRuntimeConfiguration): Promise<HostRuntimeOperationResult>;
}

interface PactlRuntimeContext {
  readonly mode: PactlRuntimeMode;
  readonly missingStreamVerification: MissingStreamVerificationMode;
  readonly sinkPrefix: string;
  runPactl(
    operation: PactlRuntimeCommandLogEntry["operation"],
    args: readonly string[]
  ): Promise<CommandResult>;
}

const defaultTimeoutMs = 5000;
const defaultSinkPrefix = "loopwire";

export function createPactlVirtualSinkRuntimeAdapter(
  runner: CommandRunner,
  options: PactlRuntimeAdapterOptions = {}
): PactlVirtualSinkRuntimeAdapter {
  const commandLog: PactlRuntimeCommandLogEntry[] = [];
  const context = createPactlRuntimeContext(runner, options, commandLog);

  return {
    commandLog,
    unload: (configuration) => unloadPactlVirtualSinks(context, configuration),
    apply: (configuration) => applyPactlVirtualSinks(context, configuration),
    refreshRoutes: (configuration) => routeConfiguredSinkInputs(context, configuration, []),
    verify: (configuration) => verifyPactlVirtualSinks(context, configuration),
    rollback: (configuration) => unloadPactlVirtualSinks(context, configuration)
  };
}

function createPactlRuntimeContext(
  runner: CommandRunner,
  options: PactlRuntimeAdapterOptions,
  commandLog: PactlRuntimeCommandLogEntry[]
): PactlRuntimeContext {
  const mode = options.mode ?? "dry-run";
  const missingStreamVerification = options.missingStreamVerification ?? "fail";
  const timeoutMs = options.timeoutMs ?? defaultTimeoutMs;
  const sinkPrefix = sanitizeName(options.sinkPrefix ?? defaultSinkPrefix);

  return {
    mode,
    missingStreamVerification,
    sinkPrefix,
    async runPactl(operation, args) {
      commandLog.push({ operation, command: "pactl", args, skipped: mode === "dry-run" });

      if (mode === "dry-run") {
        return { command: "pactl", args, exitCode: 0, stdout: "", stderr: "" };
      }

      return runner.run("pactl", args, { timeoutMs });
    }
  };
}

async function unloadPactlVirtualSinks(
  context: PactlRuntimeContext,
  configuration: HostRuntimeConfiguration
): Promise<HostRuntimeOperationResult> {
  const matchers = moduleMatchersForConfiguration(context.sinkPrefix, configuration);
  const modules = await context.runPactl("unload", ["list", "short", "modules"]);

  if (modules.exitCode !== 0) {
    return failed("Could not list PulseAudio modules for unload", modules);
  }

  const moduleIds = parseModuleIdsForMatchers(modules.stdout, matchers);

  for (const moduleId of moduleIds) {
    const unloaded = await context.runPactl("unload", ["unload-module", moduleId]);

    if (unloaded.exitCode !== 0) {
      return failed(`Could not unload Loopwire module ${moduleId}`, unloaded);
    }
  }

  return {
    ok: true,
    message: moduleIds.length === 0 ? "No Loopwire modules to unload" : `Unloaded ${moduleIds.length} Loopwire module(s)`
  };
}

async function applyPactlVirtualSinks(
  context: PactlRuntimeContext,
  configuration: HostRuntimeConfiguration
): Promise<HostRuntimeOperationResult> {
  if (configuration.outputs.length === 0) {
    return { ok: false, message: "Configuration has no outputs to materialize as virtual sinks" };
  }

  const routeShape = validatePactlStreamRouteShape(configuration);
  if (!routeShape.ok) {
    return routeShape;
  }

  const existing = await unloadPactlVirtualSinks(context, configuration);
  if (!existing.ok) {
    return existing;
  }

  const loadedModuleIds: string[] = [];

  for (const output of configuration.outputs) {
    const loaded = await context.runPactl("apply", [
      "load-module",
      "module-null-sink",
      ...moduleArgs(context.sinkPrefix, configuration, output)
    ]);

    if (loaded.exitCode !== 0) {
      await unloadLoadedModuleIds(context, loadedModuleIds);
      return failed(`Could not create virtual sink for ${output.label}`, loaded);
    }

    const loadedId = firstLine(loaded.stdout);
    if (loadedId) {
      loadedModuleIds.push(loadedId);
    }
  }

  const monitored = await applyMonitorLoopbacks(context, configuration, loadedModuleIds);
  if (!monitored.ok) {
    return monitored;
  }

  const routed = await routeConfiguredSinkInputs(context, configuration, loadedModuleIds);
  if (!routed.ok) {
    return routed;
  }

  const suffix = [monitored.message, routed.message].filter(Boolean).join("; ");

  return {
    ok: true,
    message: suffix
      ? `Created ${configuration.outputs.length} virtual sink(s); ${suffix}`
      : `Created ${configuration.outputs.length} virtual sink(s)`
  };
}

async function verifyPactlVirtualSinks(
  context: PactlRuntimeContext,
  configuration: HostRuntimeConfiguration
): Promise<HostRuntimeOperationResult> {
  const routeShape = validatePactlStreamRouteShape(configuration);
  if (!routeShape.ok) {
    return routeShape;
  }

  const expectedSinkNames = expectedVirtualSinkNames(context.sinkPrefix, configuration);
  const listed = await context.runPactl("verify", ["list", "short", "sinks"]);

  if (listed.exitCode !== 0) {
    return failed("Could not list PulseAudio sinks for verification", listed);
  }

  if (context.mode === "dry-run") {
    return { ok: true, message: `Dry run verified ${expectedSinkNames.length} expected virtual sink(s)` };
  }

  const actualSinkNames = parseSinkNames(listed.stdout);
  const missing = expectedSinkNames.filter((sinkName) => !actualSinkNames.has(sinkName));

  if (missing.length > 0) {
    return { ok: false, message: `Missing Loopwire virtual sink(s): ${missing.join(", ")}` };
  }

  const missingMonitorTargets = monitorTargetSinkNames(configuration).filter((sinkName) => !actualSinkNames.has(sinkName));

  if (missingMonitorTargets.length > 0) {
    return { ok: false, message: `Missing monitor target sink(s): ${missingMonitorTargets.join(", ")}` };
  }

  const routed = await verifyConfiguredSinkInputs(context, configuration);
  if (!routed.ok) {
    return routed;
  }

  const monitored = await verifyConfiguredMonitorLoopbacks(context, configuration);
  if (!monitored.ok) {
    return monitored;
  }

  const verificationNotes = [routed.message, monitored.message].filter(Boolean);

  return {
    ok: true,
    message:
      verificationNotes.length > 0
        ? verificationNotes.join("; ")
        : `Verified ${expectedSinkNames.length} Loopwire sink(s)`
  };
}

async function unloadLoadedModuleIds(context: PactlRuntimeContext, moduleIds: readonly string[]): Promise<void> {
  for (const moduleId of moduleIds) {
    await context.runPactl("rollback", ["unload-module", moduleId]);
  }
}

async function applyMonitorLoopbacks(
  context: PactlRuntimeContext,
  configuration: HostRuntimeConfiguration,
  loadedModuleIds: string[]
): Promise<HostRuntimeOperationResult> {
  const monitors = configuration.monitors ?? [];

  if (monitors.length === 0) {
    return { ok: true };
  }

  for (const monitor of monitors.filter((item) => !item.deviceName)) {
    const loaded = await context.runPactl("apply", [
      "load-module",
      "module-null-sink",
      ...monitorModuleArgs(context.sinkPrefix, configuration, monitor)
    ]);

    if (loaded.exitCode !== 0) {
      await unloadLoadedModuleIds(context, loadedModuleIds);
      return failed(`Could not create monitor sink for ${monitor.label}`, loaded);
    }

    const loadedId = firstLine(loaded.stdout);
    if (loadedId) {
      loadedModuleIds.push(loadedId);
    }
  }

  const plans = createMonitorLoopbackPlans(context.sinkPrefix, configuration);

  for (const plan of plans) {
    const loaded = await context.runPactl("apply", [
      "load-module",
      ...monitorLoopbackModuleArgs(plan)
    ]);

    if (loaded.exitCode !== 0) {
      await unloadLoadedModuleIds(context, loadedModuleIds);
      return failed(`Could not link monitor ${plan.label}`, loaded);
    }

    const loadedId = firstLine(loaded.stdout);
    if (loadedId) {
      loadedModuleIds.push(loadedId);
    }
  }

  return {
    ok: true,
    message: `Created ${virtualMonitorCount(monitors)} monitor sink(s); Linked ${plans.length} monitor loopback(s)`
  };
}

async function routeConfiguredSinkInputs(
  context: PactlRuntimeContext,
  configuration: HostRuntimeConfiguration,
  loadedModuleIds: readonly string[]
): Promise<HostRuntimeOperationResult> {
  const routeShape = validatePactlStreamRouteShape(configuration);
  if (!routeShape.ok) {
    return routeShape;
  }

  const routePlans = createSinkInputRoutePlans(context.sinkPrefix, configuration);

  if (routePlans.length === 0) {
    return { ok: true };
  }

  const listed = await context.runPactl("apply", ["list", "sink-inputs"]);
  if (listed.exitCode !== 0) {
    await unloadLoadedModuleIds(context, loadedModuleIds);
    return failed("Could not list PulseAudio sink inputs for routing", listed);
  }

  const sinkInputs = parseSinkInputs(listed.stdout);
  const changedInputs: SinkInputRollback[] = [];
  let moveCount = 0;

  for (const plan of routePlans) {
    const matches = sinkInputs.filter((sinkInput) => sinkInputMatchesRoute(sinkInput, plan));

    for (const sinkInput of matches) {
      const rollback = sinkInputRollbackState(sinkInput);

      if (sinkInput.sinkName !== plan.targetSinkName) {
        const moved = await context.runPactl("apply", ["move-sink-input", sinkInput.id, plan.targetSinkName]);
        if (moved.exitCode !== 0) {
          await rollbackSinkInputs(context, changedInputs);
          await unloadLoadedModuleIds(context, loadedModuleIds);
          return failed(`Could not move sink input ${sinkInput.id} to ${plan.targetSinkName}`, moved);
        }
      }

      changedInputs.push(rollback);

      const controlled = await applySinkInputControls(context, sinkInput.id, plan);
      if (!controlled.ok) {
        await rollbackSinkInputs(context, changedInputs);
        await unloadLoadedModuleIds(context, loadedModuleIds);
        return controlled;
      }

      moveCount += 1;
    }
  }

  return { ok: true, message: `Applied ${moveCount} matching sink input route(s)` };
}

async function verifyConfiguredSinkInputs(
  context: PactlRuntimeContext,
  configuration: HostRuntimeConfiguration
): Promise<HostRuntimeOperationResult> {
  const routePlans = createSinkInputRoutePlans(context.sinkPrefix, configuration);

  if (routePlans.length === 0) {
    return { ok: true };
  }

  const listed = await context.runPactl("verify", ["list", "sink-inputs"]);
  if (listed.exitCode !== 0) {
    return failed("Could not list PulseAudio sink inputs for route verification", listed);
  }

  const sinkInputs = parseSinkInputs(listed.stdout);
  const missingMatches = routePlans
    .filter((plan) => !sinkInputs.some((sinkInput) => sinkInputMatchesRoute(sinkInput, plan)))
    .map((plan) => plan.routeId);
  const wrongSinkInputs = routePlans.flatMap((plan) =>
    sinkInputs
      .filter((sinkInput) => sinkInputMatchesRoute(sinkInput, plan))
      .filter((sinkInput) => sinkInput.sinkName !== plan.targetSinkName)
      .map((sinkInput) => `${sinkInput.id}->${sinkInput.sinkName ?? "unknown"} expected ${plan.targetSinkName}`)
  );
  const wrongControls = routePlans.flatMap((plan) =>
    sinkInputs
      .filter((sinkInput) => sinkInputMatchesRoute(sinkInput, plan))
      .flatMap((sinkInput) => sinkInputControlMismatches(sinkInput, plan))
  );

  if (missingMatches.length > 0 && context.missingStreamVerification === "fail") {
    return { ok: false, message: `Missing matching PulseAudio stream(s) for route(s): ${missingMatches.join(", ")}` };
  }

  if (wrongSinkInputs.length > 0) {
    return { ok: false, message: `Misrouted Loopwire sink input(s): ${wrongSinkInputs.join(", ")}` };
  }

  if (wrongControls.length > 0) {
    return { ok: false, message: `Misconfigured Loopwire sink input(s): ${wrongControls.join(", ")}` };
  }

  if (missingMatches.length > 0) {
    return { ok: true, message: `Pending matching PulseAudio stream(s) for route(s): ${missingMatches.join(", ")}` };
  }

  return { ok: true };
}

async function verifyConfiguredMonitorLoopbacks(
  context: PactlRuntimeContext,
  configuration: HostRuntimeConfiguration
): Promise<HostRuntimeOperationResult> {
  const plans = createMonitorLoopbackPlans(context.sinkPrefix, configuration);

  if (plans.length === 0) {
    return { ok: true };
  }

  const listed = await context.runPactl("verify", ["list", "short", "modules"]);
  if (listed.exitCode !== 0) {
    return failed("Could not list PulseAudio modules for monitor verification", listed);
  }

  const moduleLines = parseModuleLines(listed.stdout);
  const missing = plans
    .filter((plan) => !moduleLines.some((line) => monitorLoopbackMatcher(plan).fragments.every((item) => line.includes(item))))
    .map((plan) => plan.label);

  if (missing.length > 0) {
    return { ok: false, message: `Missing Loopwire monitor loopback(s): ${missing.join(", ")}` };
  }

  return { ok: true };
}

async function applySinkInputControls(
  context: PactlRuntimeContext,
  sinkInputId: string,
  plan: SinkInputRoutePlan
): Promise<HostRuntimeOperationResult> {
  if (plan.gain !== undefined) {
    const volume = await context.runPactl("apply", [
      "set-sink-input-volume",
      sinkInputId,
      `${toPulseVolumePercent(plan.gain)}%`
    ]);
    if (volume.exitCode !== 0) {
      return failed(`Could not set sink input ${sinkInputId} volume`, volume);
    }
  }

  const mute = await context.runPactl("apply", ["set-sink-input-mute", sinkInputId, plan.muted ? "1" : "0"]);
  if (mute.exitCode !== 0) {
    return failed(`Could not set sink input ${sinkInputId} mute`, mute);
  }

  return { ok: true };
}

function sinkInputRollbackState(sinkInput: ParsedSinkInput): SinkInputRollback {
  return {
    sinkInputId: sinkInput.id,
    ...(sinkInput.sinkName ? { originalSinkName: sinkInput.sinkName } : {}),
    ...(sinkInput.volumePercent !== undefined ? { originalVolumePercent: sinkInput.volumePercent } : {}),
    ...(sinkInput.muted !== undefined ? { originalMuted: sinkInput.muted } : {})
  };
}

async function rollbackSinkInputs(context: PactlRuntimeContext, changedInputs: readonly SinkInputRollback[]): Promise<void> {
  for (const changedInput of changedInputs.toReversed()) {
    if (changedInput.originalMuted !== undefined) {
      await context.runPactl("rollback", [
        "set-sink-input-mute",
        changedInput.sinkInputId,
        changedInput.originalMuted ? "1" : "0"
      ]);
    }

    if (changedInput.originalVolumePercent !== undefined) {
      await context.runPactl("rollback", [
        "set-sink-input-volume",
        changedInput.sinkInputId,
        `${changedInput.originalVolumePercent}%`
      ]);
    }

    if (changedInput.originalSinkName) {
      await context.runPactl("rollback", ["move-sink-input", changedInput.sinkInputId, changedInput.originalSinkName]);
    }
  }
}

export function sinkNameForOutput(
  sinkPrefix: string,
  configuration: HostRuntimeConfiguration,
  output: HostRuntimeEndpoint
): string {
  return [sanitizeName(sinkPrefix), sanitizeName(configuration.id), sanitizeName(output.id)].join("_").slice(0, 80);
}

export function sinkNameForMonitor(
  sinkPrefix: string,
  configuration: HostRuntimeConfiguration,
  monitor: HostRuntimeEndpoint
): string {
  return [sanitizeName(sinkPrefix), sanitizeName(configuration.id), "monitor", sanitizeName(monitor.id)].join("_").slice(0, 80);
}

interface SinkInputRoutePlan {
  readonly routeId: string;
  readonly sourceTokens: readonly string[];
  readonly targetSinkName: string;
  readonly gain?: number;
  readonly muted: boolean;
}

interface MonitorLoopbackPlan {
  readonly label: string;
  readonly sourceName: string;
  readonly targetSinkName: string;
}

interface ModuleMatcher {
  readonly fragments: readonly string[];
}

interface ParsedSinkInput {
  readonly id: string;
  readonly sinkName?: string;
  readonly volumePercent?: number;
  readonly muted?: boolean;
  readonly searchableText: string;
}

interface SinkInputRollback {
  readonly sinkInputId: string;
  readonly originalSinkName?: string;
  readonly originalVolumePercent?: number;
  readonly originalMuted?: boolean;
}

function moduleArgs(
  sinkPrefix: string,
  configuration: HostRuntimeConfiguration,
  output: HostRuntimeEndpoint
): readonly string[] {
  const sinkName = sinkNameForOutput(sinkPrefix, configuration, output);
  return virtualSinkModuleArgs(sinkName, configuration, output);
}

function monitorModuleArgs(
  sinkPrefix: string,
  configuration: HostRuntimeConfiguration,
  monitor: HostRuntimeEndpoint
): readonly string[] {
  const sinkName = sinkNameForMonitor(sinkPrefix, configuration, monitor);
  return virtualSinkModuleArgs(sinkName, configuration, monitor);
}

function expectedVirtualSinkNames(
  sinkPrefix: string,
  configuration: HostRuntimeConfiguration
): readonly string[] {
  const outputSinkNames = configuration.outputs.map((output) => sinkNameForOutput(sinkPrefix, configuration, output));
  const monitorSinkNames = (configuration.monitors ?? [])
    .filter((monitor) => !monitor.deviceName)
    .map((monitor) => sinkNameForMonitor(sinkPrefix, configuration, monitor));

  return [...outputSinkNames, ...monitorSinkNames];
}

function virtualSinkModuleArgs(
  sinkName: string,
  configuration: HostRuntimeConfiguration,
  endpoint: HostRuntimeEndpoint
): readonly string[] {
  const channels = Math.max(1, Math.min(endpoint.channels, 32));
  const description = sanitizeName(`Loopwire_${configuration.name}_${endpoint.label}`).slice(0, 80);

  return [`sink_name=${sinkName}`, `channels=${channels}`, `sink_properties=device.description=${description}`];
}

function createSinkInputRoutePlans(
  sinkPrefix: string,
  configuration: HostRuntimeConfiguration
): readonly SinkInputRoutePlan[] {
  const inputs = new Map((configuration.inputs ?? []).map((input) => [input.id, input]));
  const outputs = new Map(configuration.outputs.map((output) => [output.id, output]));

  return (configuration.routes ?? [])
    .flatMap((route) => {
      const input = inputs.get(route.from);
      const output = outputs.get(route.to);

      if (!input || !output) {
        return [];
      }

      return [
        {
          routeId: route.id,
          sourceTokens: routeSourceTokens(input),
          targetSinkName: sinkNameForOutput(sinkPrefix, configuration, output),
          ...(route.gain !== undefined ? { gain: route.gain } : {}),
          muted: route.muted
        }
      ];
    });
}

function validatePactlStreamRouteShape(configuration: HostRuntimeConfiguration): HostRuntimeOperationResult {
  const inputs = new Map((configuration.inputs ?? []).map((input) => [input.id, input]));
  const routesBySource = new Map<string, HostRuntimeRoute[]>();

  for (const route of configuration.routes ?? []) {
    routesBySource.set(route.from, [...(routesBySource.get(route.from) ?? []), route]);
  }

  const duplicateSourceRoutes = [...routesBySource.entries()].filter(([, routes]) => routes.length > 1);

  if (duplicateSourceRoutes.length === 0) {
    return { ok: true };
  }

  const details = duplicateSourceRoutes.map(([sourceId, routes]) => {
    const sourceLabel = inputs.get(sourceId)?.label ?? sourceId;
    return `${sourceLabel} uses routes ${routes.map((route) => route.id).join(", ")}`;
  });

  return {
    ok: false,
    message: `PulseAudio compatibility cannot route one source to multiple outputs: ${details.join("; ")}`
  };
}

function routeSourceTokens(input: HostRuntimeEndpoint): readonly string[] {
  return [input.id, input.label, input.deviceName]
    .map((value) => value?.toLowerCase())
    .filter((value): value is string => Boolean(value));
}

function createMonitorLoopbackPlans(
  sinkPrefix: string,
  configuration: HostRuntimeConfiguration
): readonly MonitorLoopbackPlan[] {
  return configuration.outputs.flatMap((output) =>
    (configuration.monitors ?? []).map((monitor) => {
      const sourceName = `${sinkNameForOutput(sinkPrefix, configuration, output)}.monitor`;
      const targetSinkName = monitor.deviceName ?? sinkNameForMonitor(sinkPrefix, configuration, monitor);

      return {
        label: `${sourceName} -> ${targetSinkName}`,
        sourceName,
        targetSinkName
      };
    })
  );
}

function monitorLoopbackModuleArgs(plan: MonitorLoopbackPlan): readonly string[] {
  return ["module-loopback", `source=${plan.sourceName}`, `sink=${plan.targetSinkName}`, "latency_msec=20"];
}

function moduleMatchersForConfiguration(
  sinkPrefix: string,
  configuration: HostRuntimeConfiguration
): readonly ModuleMatcher[] {
  const outputMatchers = configuration.outputs.map((output) => ({
    fragments: [`sink_name=${sinkNameForOutput(sinkPrefix, configuration, output)}`]
  }));
  const monitorMatchers = (configuration.monitors ?? [])
    .filter((monitor) => !monitor.deviceName)
    .map((monitor) => ({
      fragments: [`sink_name=${sinkNameForMonitor(sinkPrefix, configuration, monitor)}`]
    }));
  const loopbackMatchers = createMonitorLoopbackPlans(sinkPrefix, configuration).map(monitorLoopbackMatcher);

  return [...outputMatchers, ...monitorMatchers, ...loopbackMatchers];
}

function monitorTargetSinkNames(configuration: HostRuntimeConfiguration): readonly string[] {
  const targetNames = (configuration.monitors ?? []).flatMap((monitor) => (monitor.deviceName ? [monitor.deviceName] : []));
  return [...new Set(targetNames)];
}

function virtualMonitorCount(monitors: readonly HostRuntimeEndpoint[]): number {
  return monitors.filter((monitor) => !monitor.deviceName).length;
}

function monitorLoopbackMatcher(plan: MonitorLoopbackPlan): ModuleMatcher {
  return {
    fragments: ["module-loopback", `source=${plan.sourceName}`, `sink=${plan.targetSinkName}`]
  };
}

function parseModuleIdsForMatchers(output: string, matchers: readonly ModuleMatcher[]): readonly string[] {
  return parseModuleLines(output)
    .map((line) => line.trim())
    .filter(Boolean)
    .flatMap((line) => {
      const [moduleId] = line.split(/\s+/, 1);
      const matchesModule = matchers.some((matcher) => matcher.fragments.every((fragment) => line.includes(fragment)));
      return moduleId && matchesModule ? [moduleId] : [];
    });
}

function parseModuleLines(output: string): readonly string[] {
  return output.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
}

function parseSinkNames(output: string): ReadonlySet<string> {
  return new Set(
    output
      .split(/\r?\n/)
      .map((line) => line.trim().split(/\s+/)[1])
      .filter((name): name is string => Boolean(name))
  );
}

function parseSinkInputs(output: string): readonly ParsedSinkInput[] {
  return output
    .split(/\n(?=Sink Input #)/)
    .map((block) => parseSinkInputBlock(block))
    .filter((sinkInput): sinkInput is ParsedSinkInput => sinkInput !== undefined);
}

function parseSinkInputBlock(block: string): ParsedSinkInput | undefined {
  const id = block.match(/Sink Input #(\d+)/)?.[1];

  if (!id) {
    return undefined;
  }

  const sinkName = block.match(/^\s*Sink:\s+([^\s]+)/m)?.[1];
  const volumePercent = Number.parseInt(block.match(/^\s*Volume:.*?\/\s*([0-9]+)%\s*\//m)?.[1] ?? "", 10);
  const muteValue = block.match(/^\s*Mute:\s+(yes|no)/m)?.[1];

  return {
    id,
    ...(sinkName ? { sinkName } : {}),
    ...(Number.isFinite(volumePercent) ? { volumePercent } : {}),
    ...(muteValue ? { muted: muteValue === "yes" } : {}),
    searchableText: block.toLowerCase()
  };
}

function sinkInputMatchesRoute(sinkInput: ParsedSinkInput, plan: SinkInputRoutePlan): boolean {
  return plan.sourceTokens.some((token) => sinkInput.searchableText.includes(token));
}

function sinkInputControlMismatches(sinkInput: ParsedSinkInput, plan: SinkInputRoutePlan): readonly string[] {
  const mismatches: string[] = [];

  if (plan.gain !== undefined && sinkInput.volumePercent !== toPulseVolumePercent(plan.gain)) {
    mismatches.push(`${sinkInput.id} volume ${sinkInput.volumePercent ?? "unknown"}% expected ${toPulseVolumePercent(plan.gain)}%`);
  }

  if (sinkInput.muted !== undefined && sinkInput.muted !== plan.muted) {
    mismatches.push(`${sinkInput.id} mute ${sinkInput.muted ? "yes" : "no"} expected ${plan.muted ? "yes" : "no"}`);
  }

  return mismatches;
}

function toPulseVolumePercent(gain: number): number {
  return Math.max(0, Math.min(100, Math.round(gain * 100)));
}

function failed(message: string, result: CommandResult): HostRuntimeOperationResult {
  const detail = firstLine(result.stderr) ?? firstLine(result.stdout) ?? `exit ${result.exitCode}`;
  return { ok: false, message: `${message}: ${detail}` };
}

function firstLine(output: string): string | undefined {
  return output.split(/\r?\n/).map((line) => line.trim()).find(Boolean);
}

function sanitizeName(value: string): string {
  const sanitized = value
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, "_")
    .replace(/_+/g, "_")
    .replace(/^_+|_+$/g, "");

  return sanitized || "unnamed";
}
