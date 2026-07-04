import { createDspMixPlan, listDspSourceRequests, renderDspMixPlan, runDspMixCycle } from "@loopwire/core";
import type {
  AudioEndpoint,
  ConfigurationRuntimeAdapter,
  ConfigurationRuntimePlan,
  DspMixPlan,
  DspRenderedOutput,
  DspSourceBufferResult,
  DspSourceBuffers,
  DspSourceRequest,
  LoopwireConfiguration
} from "@loopwire/core";
import type {
  HostRuntimeConfiguration,
  HostRuntimeEndpoint,
  HostRuntimeOperationResult,
  HostRuntimeRoute
} from "./runtime-adapter.js";
import type { CommandResult, CommandRunOptions, CommandRunner } from "./types.js";

export type DspRuntimeMode = "dry-run" | "apply";

export interface DspGraphRuntimeAdapterOptions {
  readonly mode?: DspRuntimeMode;
  readonly failOnMissingSources?: boolean;
  readonly frameCount?: number;
}

export type DspOutputVerificationResult = boolean | HostRuntimeOperationResult | void;

export interface DspRuntimePorts {
  readSource(request: DspSourceRequest): DspSourceBufferResult | Promise<DspSourceBufferResult>;
  writeOutput(output: DspRenderedOutput): void | Promise<void>;
  verifyOutput?(output: DspRenderedOutput): DspOutputVerificationResult | Promise<DspOutputVerificationResult>;
  clearOutput?(outputId: string, configuration: HostRuntimeConfiguration): void | Promise<void>;
}

export interface DspRuntimeCommandPortOptions {
  readonly command?: string;
  readonly timeoutMs?: number;
}

export interface DspRuntimeCommandLogEntry {
  readonly operation: "unload" | "apply" | "verify" | "rollback";
  readonly action: "plan" | "read" | "write" | "verify" | "clear";
  readonly target: string;
  readonly skipped: boolean;
}

export interface DspGraphRuntimeAdapter {
  readonly commandLog: readonly DspRuntimeCommandLogEntry[];
  unload(configuration: HostRuntimeConfiguration): Promise<HostRuntimeOperationResult>;
  apply(configuration: HostRuntimeConfiguration): Promise<HostRuntimeOperationResult>;
  verify(configuration: HostRuntimeConfiguration): Promise<HostRuntimeOperationResult>;
  rollback(configuration: HostRuntimeConfiguration): Promise<HostRuntimeOperationResult>;
}

export interface DspConfigurationRuntimeAdapter extends ConfigurationRuntimeAdapter {
  readonly commandLog: readonly DspRuntimeCommandLogEntry[];
}

interface DspRuntimeContext {
  readonly mode: DspRuntimeMode;
  readonly failOnMissingSources: boolean;
  readonly frameCount?: number;
  readonly ports: DspRuntimePorts;
  readonly commandLog: DspRuntimeCommandLogEntry[];
  currentOutputIds: string[];
}

type DspRuntimeOperation = DspRuntimeCommandLogEntry["operation"];

const defaultDspProviderCommand = "loopwire-dsp-provider";

export function createDspRuntimeCommandPorts(
  runner: CommandRunner,
  options: DspRuntimeCommandPortOptions = {}
): DspRuntimePorts {
  const command = options.command ?? defaultDspProviderCommand;

  return {
    async readSource(request) {
      const result = await runner.run(command, readSourceArgs(request), commandOptions(options));
      assertProviderSuccess(result, "read-source", request.sourceId);

      return decodeSourcePayload(result.stdout, request);
    },
    async writeOutput(output) {
      const result = await runner.run(
        command,
        renderedOutputArgs("write-output", output),
        commandOptions(options, encodeRenderedOutput(output))
      );
      assertProviderSuccess(result, "write-output", output.outputId);
    },
    async verifyOutput(output) {
      const result = await runner.run(
        command,
        renderedOutputArgs("verify-output", output),
        commandOptions(options, encodeRenderedOutput(output))
      );

      if (result.exitCode !== 0) {
        return { ok: false, message: providerFailureMessage(result, "verify-output", output.outputId) };
      }

      try {
        return decodeVerificationPayload(result.stdout, output.outputId);
      } catch (error) {
        return { ok: false, message: errorMessage(error) };
      }
    },
    async clearOutput(outputId, configuration) {
      const result = await runner.run(command, clearOutputArgs(outputId, configuration), commandOptions(options));
      assertProviderSuccess(result, "clear-output", outputId);
    }
  };
}

export function createDspGraphRuntimeAdapter(
  ports: DspRuntimePorts,
  options: DspGraphRuntimeAdapterOptions = {}
): DspGraphRuntimeAdapter {
  const commandLog: DspRuntimeCommandLogEntry[] = [];
  const context: DspRuntimeContext = {
    mode: options.mode ?? "dry-run",
    failOnMissingSources: options.failOnMissingSources ?? true,
    ...(options.frameCount !== undefined ? { frameCount: options.frameCount } : {}),
    ports,
    commandLog,
    currentOutputIds: []
  };

  return {
    commandLog,
    unload: (configuration) => clearDspOutputs(context, "unload", configuration),
    apply: (configuration) => applyDspMix(context, configuration),
    verify: (configuration) => verifyDspMix(context, configuration),
    rollback: (configuration) => restoreDspOutputs(context, configuration)
  };
}

export function createDspConfigurationRuntimeAdapter(
  ports: DspRuntimePorts,
  options: DspGraphRuntimeAdapterOptions = {}
): DspConfigurationRuntimeAdapter {
  const graphAdapter = createDspGraphRuntimeAdapter(ports, options);

  return {
    commandLog: graphAdapter.commandLog,
    unload: (configuration, _plan) => runConfigurationOperation(graphAdapter, "unload", configuration, _plan),
    apply: (configuration, _plan) => runConfigurationOperation(graphAdapter, "apply", configuration, _plan),
    verify: (configuration, _plan) => runConfigurationOperation(graphAdapter, "verify", configuration, _plan),
    rollback: (configuration, _plan) => runConfigurationOperation(graphAdapter, "rollback", configuration, _plan)
  };
}

function runConfigurationOperation(
  adapter: DspGraphRuntimeAdapter,
  operation: DspRuntimeOperation,
  configuration: LoopwireConfiguration,
  _plan: ConfigurationRuntimePlan
): Promise<HostRuntimeOperationResult> {
  return adapter[operation](configuration);
}

async function applyDspMix(
  context: DspRuntimeContext,
  configuration: HostRuntimeConfiguration
): Promise<HostRuntimeOperationResult> {
  const plan = createPlanResult(configuration);

  if (!isDspMixPlan(plan)) {
    return plan;
  }

  logPlan(context, "apply", plan);

  if (context.mode === "dry-run") {
    logDryRunPorts(context, "apply", plan, "write");
    return {
      ok: true,
      message: `Planned DSP mix for ${sourceCount(plan)} source(s) and ${plan.outputs.length} output(s)`
    };
  }

  try {
    const result = await runDspMixCycle(
      plan,
      {
        async readSource(request) {
          context.commandLog.push({ operation: "apply", action: "read", target: request.sourceId, skipped: false });
          return context.ports.readSource(request);
        },
        async writeOutput(output) {
          context.commandLog.push({ operation: "apply", action: "write", target: output.outputId, skipped: false });
          return context.ports.writeOutput(output);
        }
      },
      {
        failOnMissingSources: context.failOnMissingSources,
        ...(context.frameCount !== undefined ? { frameCount: context.frameCount } : {})
      }
    );
    context.currentOutputIds = [...result.writtenOutputs];

    if (!result.ok) {
      return { ok: false, message: result.message };
    }

    return {
      ok: true,
      message: `Rendered DSP mix to ${result.writtenOutputs.length} output(s); peaks: ${formatPeaks(
        result.rendered.outputs
      )}`
    };
  } catch (error) {
    return { ok: false, message: `Could not apply DSP mix: ${errorMessage(error)}` };
  }
}

async function verifyDspMix(
  context: DspRuntimeContext,
  configuration: HostRuntimeConfiguration
): Promise<HostRuntimeOperationResult> {
  const plan = createPlanResult(configuration);

  if (!isDspMixPlan(plan)) {
    return plan;
  }

  logPlan(context, "verify", plan);

  if (context.mode === "dry-run") {
    logDryRunPorts(context, "verify", plan, "verify");
    return {
      ok: true,
      message: `Planned DSP verification for ${sourceCount(plan)} source(s) and ${plan.outputs.length} output(s)`
    };
  }

  if (!context.ports.verifyOutput) {
    return { ok: false, message: "DSP verification requires a verifyOutput port" };
  }

  try {
    const sources = await readVerificationSources(context, plan);
    const rendered = renderDspMixPlan(
      plan,
      sources.buffers,
      context.frameCount !== undefined ? { frameCount: context.frameCount } : {}
    );
    const missingSources = uniqueSorted([...sources.missingSources, ...rendered.missingSources]);

    if (context.failOnMissingSources && missingSources.length > 0) {
      return { ok: false, message: `Missing DSP source buffer(s): ${missingSources.join(", ")}` };
    }

    for (const output of rendered.outputs) {
      context.commandLog.push({ operation: "verify", action: "verify", target: output.outputId, skipped: false });

      const verified = normalizeVerificationResult(output, await context.ports.verifyOutput(output));

      if (!verified.ok) {
        return verified;
      }
    }

    return { ok: true, message: `Verified DSP mix outputs: ${rendered.outputs.map((output) => output.outputId).join(", ")}` };
  } catch (error) {
    return { ok: false, message: `Could not verify DSP mix: ${errorMessage(error)}` };
  }
}

async function clearDspOutputs(
  context: DspRuntimeContext,
  operation: "unload" | "rollback",
  configuration: HostRuntimeConfiguration
): Promise<HostRuntimeOperationResult> {
  const plan = createPlanResult(configuration);

  if (!isDspMixPlan(plan)) {
    return plan;
  }

  logPlan(context, operation, plan);

  if (context.mode === "dry-run" || !context.ports.clearOutput) {
    for (const output of plan.outputs) {
      context.commandLog.push({ operation, action: "clear", target: output.outputId, skipped: true });
    }

    return { ok: true, message: `Planned DSP output clear for ${plan.outputs.length} output(s)` };
  }

  for (const output of plan.outputs) {
    context.commandLog.push({ operation, action: "clear", target: output.outputId, skipped: false });

    try {
      await context.ports.clearOutput(output.outputId, configuration);
    } catch (error) {
      return { ok: false, message: `Could not clear DSP output ${output.outputId}: ${errorMessage(error)}` };
    }
  }

  return { ok: true, message: `Cleared DSP outputs: ${plan.outputs.map((output) => output.outputId).join(", ")}` };
}

async function restoreDspOutputs(
  context: DspRuntimeContext,
  configuration: HostRuntimeConfiguration
): Promise<HostRuntimeOperationResult> {
  const plan = createPlanResult(configuration);

  if (!isDspMixPlan(plan)) {
    return plan;
  }

  logPlan(context, "rollback", plan);

  if (context.mode === "dry-run") {
    logDryRunPorts(context, "rollback", plan, "write");
    return {
      ok: true,
      message: `Planned DSP rollback for ${sourceCount(plan)} source(s) and ${plan.outputs.length} output(s)`
    };
  }

  if (context.ports.clearOutput) {
    for (const outputId of context.currentOutputIds) {
      context.commandLog.push({ operation: "rollback", action: "clear", target: outputId, skipped: false });

      try {
        await context.ports.clearOutput(outputId, configuration);
      } catch (error) {
        return { ok: false, message: `Could not clear DSP output ${outputId}: ${errorMessage(error)}` };
      }
    }
  }

  try {
    const result = await runDspMixCycle(
      plan,
      {
        async readSource(request) {
          context.commandLog.push({ operation: "rollback", action: "read", target: request.sourceId, skipped: false });
          return context.ports.readSource(request);
        },
        async writeOutput(output) {
          context.commandLog.push({ operation: "rollback", action: "write", target: output.outputId, skipped: false });
          return context.ports.writeOutput(output);
        }
      },
      {
        failOnMissingSources: context.failOnMissingSources,
        ...(context.frameCount !== undefined ? { frameCount: context.frameCount } : {})
      }
    );
    context.currentOutputIds = [...result.writtenOutputs];

    if (!result.ok) {
      return { ok: false, message: result.message };
    }

    return {
      ok: true,
      message: `Restored DSP mix to ${result.writtenOutputs.length} output(s); peaks: ${formatPeaks(
        result.rendered.outputs
      )}`
    };
  } catch (error) {
    return { ok: false, message: `Could not restore DSP mix: ${errorMessage(error)}` };
  }
}

function readSourceArgs(request: DspSourceRequest): readonly string[] {
  const args = [
    "read-source",
    "--source-id",
    request.sourceId,
    "--channels",
    String(request.channels)
  ];

  return request.frameCount === undefined ? args : [...args, "--frames", String(request.frameCount)];
}

function renderedOutputArgs(operation: "write-output" | "verify-output", output: DspRenderedOutput): readonly string[] {
  return [
    operation,
    "--output-id",
    output.outputId,
    "--channels",
    String(output.channels.length),
    "--frames",
    String(outputFrameCount(output)),
    "--peak",
    formatPeak(output.peak),
    "--configuration-id",
    output.configurationId
  ];
}

function clearOutputArgs(outputId: string, configuration: HostRuntimeConfiguration): readonly string[] {
  return ["clear-output", "--configuration-id", configuration.id, "--output-id", outputId];
}

function commandOptions(options: DspRuntimeCommandPortOptions, input?: string): CommandRunOptions {
  const base = options.timeoutMs !== undefined ? { timeoutMs: options.timeoutMs } : {};

  return input === undefined ? base : { ...base, input };
}

function encodeRenderedOutput(output: DspRenderedOutput): string {
  return JSON.stringify({
    configurationId: output.configurationId,
    outputId: output.outputId,
    peak: output.peak,
    channels: output.channels.map((channel) => Array.from(channel))
  });
}

function decodeSourcePayload(stdout: string, request: DspSourceRequest): DspSourceBufferResult {
  const text = stdout.trim();

  if (!text) {
    throw new Error(`DSP provider read-source returned empty stdout for ${request.sourceId}`);
  }

  const payload = parseProviderJson(text, "read-source", request.sourceId);

  if (payload === null) {
    return undefined;
  }

  if (!isRecord(payload)) {
    throw new Error(`DSP provider read-source returned invalid payload for ${request.sourceId}`);
  }

  if (payload.missing === true) {
    return undefined;
  }

  if (!Array.isArray(payload.channels)) {
    throw new Error(`DSP provider read-source returned no channels for ${request.sourceId}`);
  }

  if (payload.channels.length !== request.channels) {
    throw new Error(
      `DSP provider read-source returned ${payload.channels.length} channel(s) for ${request.sourceId}; expected ${request.channels}`
    );
  }

  return payload.channels.map((channel, channelIndex) => decodeSourceChannel(channel, request, channelIndex));
}

function decodeSourceChannel(
  channel: unknown,
  request: DspSourceRequest,
  channelIndex: number
): Float32Array {
  if (!Array.isArray(channel)) {
    throw new Error(`DSP provider read-source returned invalid channel ${channelIndex} for ${request.sourceId}`);
  }

  if (request.frameCount !== undefined && channel.length !== request.frameCount) {
    throw new Error(
      `DSP provider read-source returned ${channel.length} frame(s) for ${request.sourceId}:${channelIndex}; expected ${request.frameCount}`
    );
  }

  const samples: number[] = [];

  for (const [frameIndex, sample] of channel.entries()) {
    if (typeof sample !== "number" || !Number.isFinite(sample)) {
      throw new Error(
        `DSP provider read-source returned invalid sample at ${request.sourceId}:${channelIndex}:${frameIndex}`
      );
    }

    samples.push(sample);
  }

  return Float32Array.from(samples);
}

function decodeVerificationPayload(stdout: string, outputId: string): DspOutputVerificationResult {
  const text = stdout.trim();

  if (!text) {
    throw new Error(`DSP provider verify-output returned empty stdout for ${outputId}`);
  }

  const payload = parseProviderJson(text, "verify-output", outputId);

  if (typeof payload === "boolean") {
    return payload;
  }

  if (!isRecord(payload) || typeof payload.ok !== "boolean") {
    throw new Error(`DSP provider verify-output returned invalid result for ${outputId}`);
  }

  if (!payload.ok) {
    return {
      ok: false,
      message: typeof payload.message === "string" ? payload.message : `DSP output ${outputId} did not verify`
    };
  }

  return { ok: true, ...(typeof payload.message === "string" ? { message: payload.message } : {}) };
}

function parseProviderJson(text: string, operation: string, target: string): unknown {
  try {
    return JSON.parse(text) as unknown;
  } catch {
    throw new Error(`DSP provider ${operation} returned invalid JSON for ${target}`);
  }
}

function assertProviderSuccess(result: CommandResult, operation: string, target: string): void {
  if (result.exitCode !== 0) {
    throw new Error(providerFailureMessage(result, operation, target));
  }
}

function providerFailureMessage(result: CommandResult, operation: string, target: string): string {
  return `DSP provider ${operation} failed for ${target}: ${firstLine(result.stderr) ?? firstLine(result.stdout) ?? `exit ${result.exitCode}`}`;
}

function outputFrameCount(output: DspRenderedOutput): number {
  return output.channels[0]?.length ?? 0;
}

function createPlanResult(configuration: HostRuntimeConfiguration): DspMixPlan | HostRuntimeOperationResult {
  try {
    return createDspMixPlan(toLoopwireConfiguration(configuration));
  } catch (error) {
    return { ok: false, message: `Invalid DSP runtime configuration: ${errorMessage(error)}` };
  }
}

function toLoopwireConfiguration(configuration: HostRuntimeConfiguration): LoopwireConfiguration {
  return {
    id: configuration.id,
    name: configuration.name,
    description: "Host runtime DSP graph",
    updatedAt: "1970-01-01T00:00:00.000Z",
    inputs: (configuration.inputs ?? []).map((endpoint) => toAudioEndpoint(endpoint, "input")),
    outputs: configuration.outputs.map((endpoint) => toAudioEndpoint(endpoint, "output")),
    monitors: (configuration.monitors ?? []).map((endpoint) => toAudioEndpoint(endpoint, "monitor")),
    routes: (configuration.routes ?? []).map(toAudioRoute)
  };
}

function toAudioEndpoint(
  endpoint: HostRuntimeEndpoint,
  role: AudioEndpoint["role"]
): AudioEndpoint {
  const base = {
    id: endpoint.id,
    label: endpoint.label,
    role,
    channels: endpoint.channels
  };

  return endpoint.deviceName === undefined ? base : { ...base, deviceName: endpoint.deviceName };
}

function toAudioRoute(route: HostRuntimeRoute): LoopwireConfiguration["routes"][number] {
  return {
    id: route.id,
    from: route.from,
    to: route.to,
    gain: route.gain ?? 1,
    muted: route.muted
  };
}

async function readVerificationSources(
  context: DspRuntimeContext,
  plan: DspMixPlan
): Promise<{
  readonly buffers: DspSourceBuffers;
  readonly missingSources: readonly string[];
}> {
  const buffers: Record<string, readonly Float32Array[]> = {};
  const missingSources: string[] = [];

  for (const request of listDspSourceRequests(plan, context.frameCount)) {
    context.commandLog.push({ operation: "verify", action: "read", target: request.sourceId, skipped: false });

    const source = await context.ports.readSource(request);

    if (!source) {
      missingSources.push(request.sourceId);
      continue;
    }

    buffers[request.sourceId] = source;
  }

  return { buffers, missingSources: uniqueSorted(missingSources) };
}

function normalizeVerificationResult(
  output: DspRenderedOutput,
  result: DspOutputVerificationResult
): HostRuntimeOperationResult {
  if (result === undefined || result === true) {
    return { ok: true };
  }

  if (result === false) {
    return { ok: false, message: `DSP output ${output.outputId} did not match verifier` };
  }

  return result;
}

function logPlan(
  context: DspRuntimeContext,
  operation: DspRuntimeOperation,
  plan: DspMixPlan
): void {
  context.commandLog.push({ operation, action: "plan", target: plan.configurationId, skipped: false });
}

function logDryRunPorts(
  context: DspRuntimeContext,
  operation: DspRuntimeOperation,
  plan: DspMixPlan,
  outputAction: "write" | "verify"
): void {
  for (const request of listDspSourceRequests(plan, context.frameCount)) {
    context.commandLog.push({ operation, action: "read", target: request.sourceId, skipped: true });
  }

  for (const output of plan.outputs) {
    context.commandLog.push({ operation, action: outputAction, target: output.outputId, skipped: true });
  }
}

function isDspMixPlan(result: DspMixPlan | HostRuntimeOperationResult): result is DspMixPlan {
  return "outputs" in result;
}

function sourceCount(plan: DspMixPlan): number {
  return listDspSourceRequests(plan).length;
}

function formatPeaks(outputs: readonly DspRenderedOutput[]): string {
  return outputs.map((output) => `${output.outputId}=${formatPeak(output.peak)}`).join(", ");
}

function formatPeak(value: number): string {
  return value.toFixed(3).replace(/0+$/, "").replace(/\.$/, "");
}

function uniqueSorted(values: readonly string[]): readonly string[] {
  return [...new Set(values)].sort((left, right) => left.localeCompare(right));
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : "unknown error";
}

function firstLine(value: string): string | undefined {
  const line = value
    .split(/\r?\n/u)
    .map((candidate) => candidate.trim())
    .find(Boolean);

  return line === "" ? undefined : line;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
