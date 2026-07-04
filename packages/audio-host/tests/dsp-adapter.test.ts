import {
  applyConfigurationSwitch,
  createDefaultState,
  verifyStartupConfiguration,
  type DspRenderedOutput,
  type DspSourceRequest
} from "@loopwire/core";
import { describe, expect, it } from "vitest";
import {
  createDspConfigurationRuntimeAdapter,
  createDspGraphRuntimeAdapter,
  createDspRuntimeCommandPorts,
  type CommandResult,
  type CommandRunOptions,
  type CommandRunner,
  type HostRuntimeConfiguration
} from "../src/index.js";

const configuration: HostRuntimeConfiguration = {
  id: "studio",
  name: "Studio",
  inputs: [
    { id: "mic", label: "Studio Mic", channels: 2 },
    { id: "browser", label: "Browser", channels: 2 }
  ],
  outputs: [
    { id: "stream", label: "Stream", channels: 2 },
    { id: "recorder", label: "Recorder", channels: 2 }
  ],
  routes: [
    { id: "mic-stream", from: "mic", to: "stream", gain: 0.5, muted: false },
    { id: "mic-recorder", from: "mic", to: "recorder", gain: 0.25, muted: false },
    { id: "browser-stream", from: "browser", to: "stream", gain: 0.75, muted: true }
  ]
};

describe("createDspGraphRuntimeAdapter", () => {
  it("plans DSP ports in dry-run mode without reading or writing buffers", async () => {
    let readCount = 0;
    let writeCount = 0;
    const adapter = createDspGraphRuntimeAdapter(
      {
        readSource() {
          readCount += 1;
          return undefined;
        },
        writeOutput() {
          writeCount += 1;
        }
      },
      { mode: "dry-run", frameCount: 2 }
    );

    await expect(adapter.apply(configuration)).resolves.toEqual({
      ok: true,
      message: "Planned DSP mix for 2 source(s) and 2 output(s)"
    });
    expect(readCount).toBe(0);
    expect(writeCount).toBe(0);
    expect(adapter.commandLog).toEqual([
      { operation: "apply", action: "plan", target: "studio", skipped: false },
      { operation: "apply", action: "read", target: "browser", skipped: true },
      { operation: "apply", action: "read", target: "mic", skipped: true },
      { operation: "apply", action: "write", target: "stream", skipped: true },
      { operation: "apply", action: "write", target: "recorder", skipped: true }
    ]);
  });

  it("renders and writes DSP outputs through injected ports", async () => {
    const reads: string[] = [];
    const written: DspRenderedOutput[] = [];
    const adapter = createDspGraphRuntimeAdapter(
      {
        readSource(request) {
          reads.push(formatRequest(request));
          return sourceForRequest(request);
        },
        writeOutput(output) {
          written.push(output);
        }
      },
      { mode: "apply", frameCount: 2 }
    );

    await expect(adapter.apply(configuration)).resolves.toEqual({
      ok: true,
      message: "Rendered DSP mix to 2 output(s); peaks: stream=0.5, recorder=0.25"
    });
    expect(reads).toEqual(["browser:2:2", "mic:2:2"]);
    expect(written.map((output) => output.outputId)).toEqual(["stream", "recorder"]);
    expect(outputSamples(written, "stream")).toEqual([
      [0.5, 0.25],
      [0.125, -0.125]
    ]);
    expect(outputSamples(written, "recorder")).toEqual([
      [0.25, 0.125],
      [0.0625, -0.0625]
    ]);
  });

  it("renders through a command-backed DSP provider with JSON stdin payloads", async () => {
    const { runner, calls } = createDspProviderRunner((call) => {
      if (call.args[0] === "read-source") {
        const sourceId = argumentValue(call.args, "--source-id");

        return {
          stdout: JSON.stringify({
            channels: sourceForRequest({
              sourceId,
              channels: Number(argumentValue(call.args, "--channels")),
              frameCount: Number(argumentValue(call.args, "--frames"))
            }).map((channel) => Array.from(channel))
          })
        };
      }

      return { stdout: "ok\n" };
    });
    const ports = createDspRuntimeCommandPorts(runner, { command: "loopwire-dsp-test", timeoutMs: 900 });
    const adapter = createDspGraphRuntimeAdapter(ports, { mode: "apply", frameCount: 2 });

    await expect(adapter.apply(configuration)).resolves.toEqual({
      ok: true,
      message: "Rendered DSP mix to 2 output(s); peaks: stream=0.5, recorder=0.25"
    });
    expect(calls.map(commandLine)).toEqual([
      "loopwire-dsp-test read-source --source-id browser --channels 2 --frames 2",
      "loopwire-dsp-test read-source --source-id mic --channels 2 --frames 2",
      "loopwire-dsp-test write-output --output-id stream --channels 2 --frames 2 --peak 0.5",
      "loopwire-dsp-test write-output --output-id recorder --channels 2 --frames 2 --peak 0.25"
    ]);
    expect(calls.every((call) => call.options?.timeoutMs === 900)).toBe(true);
    expect(providerPayloads(calls, "write-output")).toEqual([
      {
        outputId: "stream",
        peak: 0.5,
        channels: [
          [0.5, 0.25],
          [0.125, -0.125]
        ]
      },
      {
        outputId: "recorder",
        peak: 0.25,
        channels: [
          [0.25, 0.125],
          [0.0625, -0.0625]
        ]
      }
    ]);
  });

  it("surfaces command-backed DSP verification failures from provider JSON", async () => {
    const { runner, calls } = createDspProviderRunner((call) => {
      if (call.args[0] === "read-source") {
        const sourceId = argumentValue(call.args, "--source-id");

        return {
          stdout: JSON.stringify({
            channels: sourceForRequest({
              sourceId,
              channels: Number(argumentValue(call.args, "--channels")),
              frameCount: Number(argumentValue(call.args, "--frames"))
            }).map((channel) => Array.from(channel))
          })
        };
      }

      if (argumentValue(call.args, "--output-id") === "recorder") {
        return { stdout: JSON.stringify({ ok: false, message: "recorder peak mismatch" }) };
      }

      return { stdout: JSON.stringify({ ok: true, message: "stream ok" }) };
    });
    const ports = createDspRuntimeCommandPorts(runner, { command: "loopwire-dsp-test" });
    const adapter = createDspGraphRuntimeAdapter(ports, { mode: "apply", frameCount: 2 });

    await expect(adapter.verify(configuration)).resolves.toEqual({
      ok: false,
      message: "recorder peak mismatch"
    });
    expect(providerPayloads(calls, "verify-output").map((payload) => payload.outputId)).toEqual(["stream", "recorder"]);
  });

  it("omits provider frame arguments when DSP source requests do not specify a frame count", async () => {
    const { runner, calls } = createDspProviderRunner(() => ({
      stdout: JSON.stringify({ channels: [[1, 0.5], [0.25, -0.25]] })
    }));
    const ports = createDspRuntimeCommandPorts(runner, { command: "loopwire-dsp-test" });

    await expect(
      ports.readSource({
        sourceId: "mic",
        sourceLabel: "Studio Mic",
        channels: 2
      })
    ).resolves.toHaveLength(2);
    expect(calls.map(commandLine)).toEqual(["loopwire-dsp-test read-source --source-id mic --channels 2"]);
  });

  it("fails closed before writes when a command-backed source buffer is malformed", async () => {
    const { runner, calls } = createDspProviderRunner((call) => {
      if (call.args[0] === "read-source" && argumentValue(call.args, "--source-id") === "browser") {
        return { stdout: JSON.stringify({ channels: [[1, 1]] }) };
      }

      return {
        stdout: JSON.stringify({
          channels: sourceForRequest({
            sourceId: argumentValue(call.args, "--source-id"),
            channels: Number(argumentValue(call.args, "--channels")),
            frameCount: Number(argumentValue(call.args, "--frames"))
          }).map((channel) => Array.from(channel))
        })
      };
    });
    const ports = createDspRuntimeCommandPorts(runner, { command: "loopwire-dsp-test" });
    const adapter = createDspGraphRuntimeAdapter(ports, { mode: "apply", frameCount: 2 });

    await expect(adapter.apply(configuration)).resolves.toEqual({
      ok: false,
      message: "Could not apply DSP mix: DSP provider read-source returned 1 channel(s) for browser; expected 2"
    });
    expect(calls.map((call) => call.args[0])).toEqual(["read-source"]);
  });

  it("fails closed on missing DSP source buffers before writing outputs", async () => {
    const written: DspRenderedOutput[] = [];
    const adapter = createDspGraphRuntimeAdapter(
      {
        readSource(request) {
          return request.sourceId === "mic" ? sourceForRequest(request) : undefined;
        },
        writeOutput(output) {
          written.push(output);
        }
      },
      { mode: "apply", frameCount: 2 }
    );

    await expect(adapter.apply(configuration)).resolves.toEqual({
      ok: false,
      message: "Missing DSP source buffer(s): browser"
    });
    expect(written).toEqual([]);
    expect(adapter.commandLog.map((entry) => entry.action)).toEqual(["plan", "read", "read"]);
  });

  it("requires an injected output verifier for apply-mode verification", async () => {
    const adapter = createDspGraphRuntimeAdapter(
      {
        readSource: sourceForRequest,
        writeOutput() {}
      },
      { mode: "apply", frameCount: 2 }
    );

    await expect(adapter.verify(configuration)).resolves.toEqual({
      ok: false,
      message: "DSP verification requires a verifyOutput port"
    });
  });

  it("verifies rendered outputs through an injected verifier", async () => {
    const verified: string[] = [];
    const adapter = createDspGraphRuntimeAdapter(
      {
        readSource: sourceForRequest,
        writeOutput() {},
        verifyOutput(output) {
          verified.push(output.outputId);
          return output.outputId === "recorder" ? { ok: false, message: "recorder peak mismatch" } : true;
        }
      },
      { mode: "apply", frameCount: 2 }
    );

    await expect(adapter.verify(configuration)).resolves.toEqual({
      ok: false,
      message: "recorder peak mismatch"
    });
    expect(verified).toEqual(["stream", "recorder"]);
  });

  it("restores DSP outputs during rollback through the core runtime transaction", async () => {
    const written: DspRenderedOutput[] = [];
    const cleared: string[] = [];
    const adapter = createDspConfigurationRuntimeAdapter(
      {
        readSource: defaultStateSourceForRequest,
        writeOutput(output) {
          written.push(output);
        },
        verifyOutput(output) {
          return output.outputId === "broadcast" ? { ok: false, message: "broadcast mismatch" } : true;
        },
        clearOutput(outputId) {
          cleared.push(outputId);
        }
      },
      { mode: "apply", frameCount: 2 }
    );
    const result = await applyConfigurationSwitch(
      createDefaultState("2026-07-04T00:00:00.000Z"),
      "stream",
      adapter,
      "2026-07-04T01:00:00.000Z"
    );

    expect(result).toMatchObject({
      ok: false,
      status: "rolled_back",
      reason: "broadcast mismatch"
    });
    expect(result.state.activeConfigurationId).toBe("studio");
    expect(cleared).toEqual(["recorder", "broadcast"]);
    expect(written.map((output) => output.outputId)).toEqual(["broadcast", "recorder"]);
    expect(outputSamples(written, "recorder")).toEqual([
      [expect.closeTo(1.48), expect.closeTo(1.48)],
      [expect.closeTo(1.48), expect.closeTo(1.48)]
    ]);
  });

  it("re-applies and verifies startup DSP output through the core runtime transaction", async () => {
    const written: DspRenderedOutput[] = [];
    const verified: string[] = [];
    const state = {
      ...createDefaultState("2026-07-04T00:00:00.000Z"),
      activeConfigurationId: "stream"
    };
    const adapter = createDspConfigurationRuntimeAdapter(
      {
        readSource: defaultStateSourceForRequest,
        writeOutput(output) {
          written.push(output);
        },
        verifyOutput(output) {
          verified.push(output.outputId);
          return true;
        }
      },
      { mode: "apply", frameCount: 2 }
    );

    const result = await verifyStartupConfiguration(state, adapter, "2026-07-04T01:15:00.000Z");

    expect(result).toMatchObject({
      ok: true,
      status: "verified"
    });
    expect(result.plan.operations).toEqual(["apply", "verify"]);
    expect(result.state.activeConfigurationId).toBe("stream");
    expect(result.state.appliedAt).toBe("2026-07-04T01:15:00.000Z");
    expect(written.map((output) => output.outputId)).toEqual(["broadcast"]);
    expect(verified).toEqual(["broadcast"]);
    expect(adapter.commandLog).toEqual([
      { operation: "apply", action: "plan", target: "stream", skipped: false },
      { operation: "apply", action: "read", target: "game", skipped: false },
      { operation: "apply", action: "read", target: "mic", skipped: false },
      { operation: "apply", action: "read", target: "music", skipped: false },
      { operation: "apply", action: "write", target: "broadcast", skipped: false },
      { operation: "verify", action: "plan", target: "stream", skipped: false },
      { operation: "verify", action: "read", target: "game", skipped: false },
      { operation: "verify", action: "read", target: "mic", skipped: false },
      { operation: "verify", action: "read", target: "music", skipped: false },
      { operation: "verify", action: "verify", target: "broadcast", skipped: false }
    ]);
  });

  it("restores DSP outputs when rollback is called directly", async () => {
    const written: DspRenderedOutput[] = [];
    const cleared: string[] = [];
    const adapter = createDspGraphRuntimeAdapter(
      {
        readSource: sourceForRequest,
        writeOutput(output) {
          written.push(output);
        },
        verifyOutput() {
          return true;
        },
        clearOutput(outputId) {
          cleared.push(outputId);
        }
      },
      { mode: "apply", frameCount: 2 }
    );

    await expect(adapter.apply(configuration)).resolves.toMatchObject({ ok: true });
    await expect(adapter.rollback(configuration)).resolves.toEqual({
      ok: true,
      message: "Restored DSP mix to 2 output(s); peaks: stream=0.5, recorder=0.25"
    });
    expect(cleared).toEqual(["stream", "recorder"]);
    expect(written.map((output) => output.outputId)).toEqual(["stream", "recorder", "stream", "recorder"]);
  });

  it("clears DSP outputs during unload through an injected clear port", async () => {
    const cleared: string[] = [];
    const adapter = createDspGraphRuntimeAdapter(
      {
        readSource: sourceForRequest,
        writeOutput() {},
        clearOutput(outputId) {
          cleared.push(outputId);
        }
      },
      { mode: "apply", frameCount: 2 }
    );

    await expect(adapter.unload(configuration)).resolves.toEqual({
      ok: true,
      message: "Cleared DSP outputs: stream, recorder"
    });
    expect(cleared).toEqual(["stream", "recorder"]);
    expect(adapter.commandLog).toEqual([
      { operation: "unload", action: "plan", target: "studio", skipped: false },
      { operation: "unload", action: "clear", target: "stream", skipped: false },
      { operation: "unload", action: "clear", target: "recorder", skipped: false }
    ]);
  });
});

function sourceForRequest(request: DspSourceRequest): readonly Float32Array[] {
  if (request.sourceId === "mic") {
    return [new Float32Array([1, 0.5]), new Float32Array([0.25, -0.25])];
  }

  return [new Float32Array([1, 1]), new Float32Array([1, 1])];
}

function defaultStateSourceForRequest(request: DspSourceRequest): readonly Float32Array[] {
  const values: Record<string, number> = {
    browser: 1,
    game: 1,
    mic: 1,
    music: 1,
    system: 1
  };
  const value = values[request.sourceId] ?? 0;

  return [new Float32Array([value, value]), new Float32Array([value, value])];
}

function formatRequest(request: DspSourceRequest): string {
  return `${request.sourceId}:${request.channels}:${request.frameCount}`;
}

function outputSamples(outputs: readonly DspRenderedOutput[], outputId: string): number[][] {
  const output = outputs.find((candidate) => candidate.outputId === outputId);

  if (!output) {
    throw new Error(`Missing output: ${outputId}`);
  }

  return output.channels.map((channel) => Array.from(channel));
}

interface RecordedCommandCall {
  readonly command: string;
  readonly args: readonly string[];
  readonly options?: CommandRunOptions;
}

function createDspProviderRunner(
  handler: (call: RecordedCommandCall) => Partial<CommandResult>
): { readonly runner: CommandRunner; readonly calls: readonly RecordedCommandCall[] } {
  const calls: RecordedCommandCall[] = [];

  return {
    calls,
    runner: {
      async run(command, args, options) {
        const call = options === undefined ? { command, args } : { command, args, options };
        calls.push(call);

        const result = handler(call);

        return {
          command,
          args,
          exitCode: result.exitCode ?? 0,
          stdout: result.stdout ?? "",
          stderr: result.stderr ?? "",
          ...(result.errorCode !== undefined ? { errorCode: result.errorCode } : {})
        };
      }
    }
  };
}

function commandLine(call: RecordedCommandCall): string {
  return [call.command, ...call.args].join(" ");
}

function providerPayloads(calls: readonly RecordedCommandCall[], operation: string): unknown[] {
  return calls
    .filter((call) => call.args[0] === operation)
    .map((call) => JSON.parse(call.options?.input ?? "{}") as unknown);
}

function argumentValue(args: readonly string[], name: string): string {
  const index = args.indexOf(name);

  if (index === -1 || args[index + 1] === undefined) {
    throw new Error(`Missing argument: ${name}`);
  }

  return args[index + 1];
}
