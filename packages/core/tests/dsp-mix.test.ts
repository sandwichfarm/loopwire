import { describe, expect, it } from "vitest";
import {
  createDspMixPlan,
  listDspSourceRequests,
  renderDspMixPlan,
  runDspMixCycle,
  type DspRenderedOutput,
  type LoopwireConfiguration
} from "../src/index.js";

const configuration: LoopwireConfiguration = {
  id: "studio",
  name: "Studio",
  description: "Program and recorder split",
  updatedAt: "2026-07-04T00:00:00.000Z",
  inputs: [
    { id: "mic", label: "Studio Mic", role: "input", channels: 2 },
    { id: "browser", label: "Browser", role: "input", channels: 2 }
  ],
  outputs: [
    { id: "stream", label: "Stream", role: "output", channels: 2 },
    { id: "recorder", label: "Recorder", role: "output", channels: 2 }
  ],
  monitors: [],
  routes: [
    { id: "mic-stream", from: "mic", to: "stream", gain: 0.5, muted: false },
    { id: "mic-recorder", from: "mic", to: "recorder", gain: 0.25, muted: false },
    { id: "browser-stream", from: "browser", to: "stream", gain: 0.75, muted: true }
  ]
};

describe("DSP mix planning", () => {
  it("builds per-output contribution plans with effective gain and channel pairs", () => {
    expect(createDspMixPlan(configuration)).toEqual({
      configurationId: "studio",
      configurationName: "Studio",
      outputs: [
        {
          outputId: "stream",
          outputLabel: "Stream",
          channels: 2,
          contributions: [
            {
              routeId: "mic-stream",
              sourceId: "mic",
              sourceLabel: "Studio Mic",
              gain: 0.5,
              effectiveGain: 0.5,
              muted: false,
              channelPairs: [
                { sourceChannel: 0, outputChannel: 0 },
                { sourceChannel: 1, outputChannel: 1 }
              ]
            },
            {
              routeId: "browser-stream",
              sourceId: "browser",
              sourceLabel: "Browser",
              gain: 0.75,
              effectiveGain: 0,
              muted: true,
              channelPairs: [
                { sourceChannel: 0, outputChannel: 0 },
                { sourceChannel: 1, outputChannel: 1 }
              ]
            }
          ]
        },
        {
          outputId: "recorder",
          outputLabel: "Recorder",
          channels: 2,
          contributions: [
            {
              routeId: "mic-recorder",
              sourceId: "mic",
              sourceLabel: "Studio Mic",
              gain: 0.25,
              effectiveGain: 0.25,
              muted: false,
              channelPairs: [
                { sourceChannel: 0, outputChannel: 0 },
                { sourceChannel: 1, outputChannel: 1 }
              ]
            }
          ]
        }
      ]
    });
  });

  it("renders independent per-edge gain and mute into output buffers", () => {
    const rendered = renderDspMixPlan(createDspMixPlan(configuration), {
      mic: [new Float32Array([1, 0.5]), new Float32Array([0.25, -0.25])],
      browser: [new Float32Array([1, 1]), new Float32Array([1, 1])]
    });

    expect(rendered.missingSources).toEqual([]);
    expect(outputSamples(rendered, "stream")).toEqual([
      [0.5, 0.25],
      [0.125, -0.125]
    ]);
    expect(outputSamples(rendered, "recorder")).toEqual([
      [0.25, 0.125],
      [0.0625, -0.0625]
    ]);
    expect(rendered.outputs.map((output) => [output.outputId, output.peak])).toEqual([
      ["stream", 0.5],
      ["recorder", 0.25]
    ]);
  });

  it("sums multiple active sources into one output without clamping float headroom", () => {
    const mix = createDspMixPlan({
      ...configuration,
      outputs: [{ id: "stream", label: "Stream", role: "output", channels: 1 }],
      routes: [
        { id: "mic-stream", from: "mic", to: "stream", gain: 0.5, muted: false },
        { id: "browser-stream", from: "browser", to: "stream", gain: 0.75, muted: false }
      ]
    });
    const rendered = renderDspMixPlan(mix, {
      mic: [new Float32Array([1, -1])],
      browser: [new Float32Array([1, -1])]
    });

    expect(outputSamples(rendered, "stream")).toEqual([[1.25, -1.25]]);
    expect(rendered.outputs[0]?.peak).toBe(1.25);
  });

  it("reports missing source buffers and renders silence for unavailable sources", () => {
    const rendered = renderDspMixPlan(createDspMixPlan(configuration), {}, { frameCount: 2 });

    expect(rendered.missingSources).toEqual(["browser", "mic"]);
    expect(outputSamples(rendered, "stream")).toEqual([
      [0, 0],
      [0, 0]
    ]);
    expect(outputSamples(rendered, "recorder")).toEqual([
      [0, 0],
      [0, 0]
    ]);
  });

  it("lists each required source once for backend capture adapters", () => {
    expect(listDspSourceRequests(createDspMixPlan(configuration))).toEqual([
      { sourceId: "browser", sourceLabel: "Browser", channels: 2 },
      { sourceId: "mic", sourceLabel: "Studio Mic", channels: 2 }
    ]);
  });

  it("runs a DSP cycle by reading sources once and writing every rendered output", async () => {
    const readCalls: string[] = [];
    const written: DspRenderedOutput[] = [];
    const result = await runDspMixCycle(createDspMixPlan(configuration), {
      async readSource(source) {
        readCalls.push(`${source.sourceId}:${source.channels}:${source.frameCount}`);

        if (source.sourceId === "mic") {
          return [new Float32Array([1, 0.5]), new Float32Array([0.25, -0.25])];
        }

        return [new Float32Array([1, 1]), new Float32Array([1, 1])];
      },
      async writeOutput(output) {
        written.push(output);
      }
    });

    expect(result).toMatchObject({
      ok: true,
      writtenOutputs: ["stream", "recorder"],
      missingSources: []
    });
    expect(readCalls).toEqual(["browser:2:undefined", "mic:2:undefined"]);
    expect(written.map((output) => output.outputId)).toEqual(["stream", "recorder"]);
    expect(outputSamples(result.rendered, "stream")).toEqual([
      [0.5, 0.25],
      [0.125, -0.125]
    ]);
  });

  it("can fail closed on missing source buffers before writing outputs", async () => {
    const written: DspRenderedOutput[] = [];
    const result = await runDspMixCycle(
      createDspMixPlan(configuration),
      {
        async readSource(source) {
          return source.sourceId === "mic" ? [new Float32Array([1, 1]), new Float32Array([1, 1])] : undefined;
        },
        async writeOutput(output) {
          written.push(output);
        }
      },
      { failOnMissingSources: true, frameCount: 2 }
    );

    expect(result).toEqual({
      ok: false,
      message: "Missing DSP source buffer(s): browser",
      rendered: expect.any(Object),
      writtenOutputs: [],
      missingSources: ["browser"]
    });
    expect(written).toEqual([]);
  });

  it("reports output write failures with the successfully written outputs", async () => {
    const result = await runDspMixCycle(createDspMixPlan(configuration), {
      async readSource() {
        return [new Float32Array([1, 1]), new Float32Array([1, 1])];
      },
      async writeOutput(output) {
        if (output.outputId === "recorder") {
          throw new Error("sink unavailable");
        }
      }
    });

    expect(result).toEqual({
      ok: false,
      message: "Could not write DSP output recorder: sink unavailable",
      rendered: expect.any(Object),
      writtenOutputs: ["stream"],
      missingSources: []
    });
  });
});

function outputSamples(
  rendered: ReturnType<typeof renderDspMixPlan>,
  outputId: string
): number[][] {
  const output = rendered.outputs.find((candidate) => candidate.outputId === outputId);
  if (!output) {
    throw new Error(`Missing output: ${outputId}`);
  }

  return output.channels.map((channel) => Array.from(channel));
}
