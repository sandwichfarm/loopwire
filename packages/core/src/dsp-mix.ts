import { validateConfigurationGraph } from "./configuration.js";
import type { AudioEndpoint, AudioRoute, LoopwireConfiguration } from "./types.js";

export interface DspMixPlan {
  readonly configurationId: string;
  readonly configurationName: string;
  readonly outputs: readonly DspOutputPlan[];
}

export interface DspOutputPlan {
  readonly outputId: string;
  readonly outputLabel: string;
  readonly channels: number;
  readonly contributions: readonly DspRouteContribution[];
}

export interface DspRouteContribution {
  readonly routeId: string;
  readonly sourceId: string;
  readonly sourceLabel: string;
  readonly gain: number;
  readonly effectiveGain: number;
  readonly muted: boolean;
  readonly channelPairs: readonly DspChannelPair[];
}

export interface DspChannelPair {
  readonly sourceChannel: number;
  readonly outputChannel: number;
}

export type DspSourceBuffers = Readonly<Record<string, readonly Float32Array[]>>;

export interface DspRenderOptions {
  readonly frameCount?: number;
}

export interface DspRenderResult {
  readonly outputs: readonly DspRenderedOutput[];
  readonly missingSources: readonly string[];
}

export interface DspRenderedOutput {
  readonly configurationId: string;
  readonly outputId: string;
  readonly outputLabel: string;
  readonly channels: readonly Float32Array[];
  readonly peak: number;
  readonly missingSources: readonly string[];
}

export interface DspSourceRequest {
  readonly sourceId: string;
  readonly sourceLabel: string;
  readonly channels: number;
  readonly frameCount?: number;
}

export interface DspMixCyclePorts {
  readSource(request: DspSourceRequest): DspSourceBufferResult | Promise<DspSourceBufferResult>;
  writeOutput(output: DspRenderedOutput): void | Promise<void>;
}

export type DspSourceBufferResult = readonly Float32Array[] | undefined;

export interface DspMixCycleOptions extends DspRenderOptions {
  readonly failOnMissingSources?: boolean;
}

export type DspMixCycleResult =
  | {
      readonly ok: true;
      readonly rendered: DspRenderResult;
      readonly writtenOutputs: readonly string[];
      readonly missingSources: readonly string[];
    }
  | {
      readonly ok: false;
      readonly message: string;
      readonly rendered: DspRenderResult;
      readonly writtenOutputs: readonly string[];
      readonly missingSources: readonly string[];
    };

export function createDspMixPlan(configuration: LoopwireConfiguration): DspMixPlan {
  validateConfigurationGraph(configuration);

  const inputs = new Map(configuration.inputs.map((input) => [input.id, input]));

  return {
    configurationId: configuration.id,
    configurationName: configuration.name,
    outputs: configuration.outputs.map((output) => ({
      outputId: output.id,
      outputLabel: output.label,
      channels: output.channels,
      contributions: routeContributionsForOutput(configuration.routes, inputs, output)
    }))
  };
}

export function renderDspMixPlan(
  plan: DspMixPlan,
  sources: DspSourceBuffers,
  options: DspRenderOptions = {}
): DspRenderResult {
  const frameCount = options.frameCount ?? inferFrameCount(sources);
  const outputs = plan.outputs.map((output) => renderOutput(plan.configurationId, output, sources, frameCount));
  const missingSources = uniqueSorted(outputs.flatMap((output) => output.missingSources));

  return { outputs, missingSources };
}

export function listDspSourceRequests(
  plan: DspMixPlan,
  frameCount?: number
): readonly DspSourceRequest[] {
  const requests = new Map<string, DspSourceRequest>();

  for (const output of plan.outputs) {
    for (const contribution of output.contributions) {
      const channels = contribution.channelPairs.reduce(
        (count, pair) => Math.max(count, pair.sourceChannel + 1),
        0
      );
      const existing = requests.get(contribution.sourceId);

      requests.set(contribution.sourceId, {
        sourceId: contribution.sourceId,
        sourceLabel: contribution.sourceLabel,
        channels: Math.max(existing?.channels ?? 0, channels),
        ...(frameCount !== undefined ? { frameCount } : {})
      });
    }
  }

  return [...requests.values()].sort((left, right) => left.sourceId.localeCompare(right.sourceId));
}

export async function runDspMixCycle(
  plan: DspMixPlan,
  ports: DspMixCyclePorts,
  options: DspMixCycleOptions = {}
): Promise<DspMixCycleResult> {
  const sources = await readCycleSources(plan, ports, options.frameCount);
  const rendered = renderDspMixPlan(plan, sources.buffers, options);
  const missingSources = uniqueSorted([...sources.missingSources, ...rendered.missingSources]);
  const writtenOutputs: string[] = [];

  if (options.failOnMissingSources && missingSources.length > 0) {
    return {
      ok: false,
      message: `Missing DSP source buffer(s): ${missingSources.join(", ")}`,
      rendered,
      writtenOutputs,
      missingSources
    };
  }

  for (const output of rendered.outputs) {
    try {
      await ports.writeOutput(output);
      writtenOutputs.push(output.outputId);
    } catch (error) {
      return {
        ok: false,
        message: `Could not write DSP output ${output.outputId}: ${errorMessage(error)}`,
        rendered,
        writtenOutputs,
        missingSources
      };
    }
  }

  return { ok: true, rendered, writtenOutputs, missingSources };
}

function routeContributionsForOutput(
  routes: readonly AudioRoute[],
  inputs: ReadonlyMap<string, AudioEndpoint>,
  output: AudioEndpoint
): readonly DspRouteContribution[] {
  return routes
    .filter((route) => route.to === output.id)
    .map((route) => {
      const source = inputs.get(route.from);

      if (!source) {
        throw new Error(`Invalid route in configuration: ${route.id}`);
      }

      return {
        routeId: route.id,
        sourceId: source.id,
        sourceLabel: source.label,
        gain: route.gain,
        effectiveGain: route.muted ? 0 : route.gain,
        muted: route.muted,
        channelPairs: createChannelPairs(source.channels, output.channels)
      };
    });
}

function createChannelPairs(sourceChannels: number, outputChannels: number): readonly DspChannelPair[] {
  return Array.from({ length: Math.min(sourceChannels, outputChannels) }, (_, index) => ({
    sourceChannel: index,
    outputChannel: index
  }));
}

function renderOutput(
  configurationId: string,
  output: DspOutputPlan,
  sources: DspSourceBuffers,
  frameCount: number
): DspRenderedOutput {
  const channels = Array.from({ length: output.channels }, () => new Float32Array(frameCount));
  const missingSources = new Set<string>();

  for (const contribution of output.contributions) {
    const sourceChannels = sources[contribution.sourceId];

    if (!sourceChannels) {
      missingSources.add(contribution.sourceId);
      continue;
    }

    if (contribution.effectiveGain === 0) {
      continue;
    }

    mixContribution(channels, sourceChannels, contribution, frameCount);
  }

  return {
    configurationId,
    outputId: output.outputId,
    outputLabel: output.outputLabel,
    channels,
    peak: measurePeak(channels),
    missingSources: uniqueSorted([...missingSources])
  };
}

function mixContribution(
  outputChannels: readonly Float32Array[],
  sourceChannels: readonly Float32Array[],
  contribution: DspRouteContribution,
  frameCount: number
): void {
  for (const pair of contribution.channelPairs) {
    const source = sourceChannels[pair.sourceChannel];
    const output = outputChannels[pair.outputChannel];

    if (!source || !output) {
      continue;
    }

    for (let frame = 0; frame < frameCount; frame += 1) {
      output[frame] = (output[frame] ?? 0) + (source[frame] ?? 0) * contribution.effectiveGain;
    }
  }
}

function inferFrameCount(sources: DspSourceBuffers): number {
  let frameCount = 0;

  for (const channels of Object.values(sources)) {
    for (const channel of channels) {
      frameCount = Math.max(frameCount, channel.length);
    }
  }

  return frameCount;
}

async function readCycleSources(
  plan: DspMixPlan,
  ports: DspMixCyclePorts,
  frameCount?: number
): Promise<{
  readonly buffers: DspSourceBuffers;
  readonly missingSources: readonly string[];
}> {
  const buffers: Record<string, readonly Float32Array[]> = {};
  const missingSources: string[] = [];

  for (const request of listDspSourceRequests(plan, frameCount)) {
    const source = await ports.readSource(request);

    if (!source) {
      missingSources.push(request.sourceId);
      continue;
    }

    buffers[request.sourceId] = source;
  }

  return { buffers, missingSources: uniqueSorted(missingSources) };
}

function measurePeak(channels: readonly Float32Array[]): number {
  let peak = 0;

  for (const channel of channels) {
    for (const sample of channel) {
      peak = Math.max(peak, Math.abs(sample));
    }
  }

  return peak;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : "unknown error";
}

function uniqueSorted(values: readonly string[]): readonly string[] {
  return [...new Set(values)].sort((left, right) => left.localeCompare(right));
}
