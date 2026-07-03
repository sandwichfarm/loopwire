import { describe, expect, it } from "vitest";
import { createJackGraphRuntimeAdapter, type HostRuntimeConfiguration } from "../src/index.js";
import type { CommandResult, CommandRunner } from "../src/types.js";

type CommandKey = string;

const jackConfiguration: HostRuntimeConfiguration = {
  id: "JACK Mix",
  name: "JACK Mix",
  inputs: [{ id: "mic", label: "Studio Mic", channels: 2, deviceName: "studio_mic" }],
  outputs: [{ id: "program", label: "Program Out", channels: 2, deviceName: "loopwire_program" }],
  routes: [{ id: "mic-program", from: "mic", to: "program", muted: false }]
};

const monitoredJackConfiguration: HostRuntimeConfiguration = {
  ...jackConfiguration,
  monitors: [{ id: "headphones", label: "Headphones", channels: 2, deviceName: "system" }]
};

function createRecordingRunner(results: Record<CommandKey, Partial<CommandResult>>): {
  readonly runner: CommandRunner;
  readonly calls: string[];
} {
  const calls: string[] = [];

  return {
    calls,
    runner: {
      async run(command, args) {
        const key = [command, ...args].join(" ");
        calls.push(key);
        const result = results[key] ?? results[command] ?? {};

        return {
          command,
          args,
          exitCode: result.exitCode ?? 0,
          stdout: result.stdout ?? "",
          stderr: result.stderr ?? "",
          ...(result.errorCode ? { errorCode: result.errorCode } : {})
        };
      }
    }
  };
}

describe("createJackGraphRuntimeAdapter", () => {
  it("dry-runs apply and verify without mutating the host", async () => {
    const { runner, calls } = createRecordingRunner({});
    const adapter = createJackGraphRuntimeAdapter(runner);

    const apply = await adapter.apply(jackConfiguration);
    const verify = await adapter.verify(jackConfiguration);

    expect(apply).toEqual({ ok: true, message: "Dry run planned 1 JACK connection plan(s)" });
    expect(verify).toEqual({ ok: true, message: "Dry run verified 1 JACK connection plan(s)" });
    expect(calls).toEqual([]);
    expect(adapter.commandLog.map((entry) => [entry.operation, entry.command, entry.args.join(" "), entry.skipped])).toEqual([
      ["apply", "jack_lsp", "", true],
      ["apply", "jack_lsp", "-c", true],
      ["verify", "jack_lsp", "", true],
      ["verify", "jack_lsp", "-c", true]
    ]);
  });

  it("connects matching JACK ports by endpoint device names", async () => {
    const { runner, calls } = createRecordingRunner({
      jack_lsp: { stdout: jackPorts() },
      "jack_lsp -c": { stdout: "" },
      "jack_connect studio_mic:capture_1 loopwire_program:playback_1": { stdout: "" },
      "jack_connect studio_mic:capture_2 loopwire_program:playback_2": { stdout: "" }
    });
    const adapter = createJackGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply(jackConfiguration);

    expect(result).toEqual({ ok: true, message: "Connected 2 JACK port pair(s); 0 already connected" });
    expect(calls).toEqual([
      "jack_lsp",
      "jack_lsp -c",
      "jack_connect studio_mic:capture_1 loopwire_program:playback_1",
      "jack_connect studio_mic:capture_2 loopwire_program:playback_2"
    ]);
  });

  it("skips JACK connections that already exist", async () => {
    const { runner, calls } = createRecordingRunner({
      jack_lsp: { stdout: jackPorts() },
      "jack_lsp -c": { stdout: jackConnections([["studio_mic:capture_1", "loopwire_program:playback_1"]]) },
      "jack_connect studio_mic:capture_2 loopwire_program:playback_2": { stdout: "" }
    });
    const adapter = createJackGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply(jackConfiguration);

    expect(result).toEqual({ ok: true, message: "Connected 1 JACK port pair(s); 1 already connected" });
    expect(calls).toEqual([
      "jack_lsp",
      "jack_lsp -c",
      "jack_connect studio_mic:capture_2 loopwire_program:playback_2"
    ]);
  });

  it("disconnects muted JACK route connections during apply", async () => {
    const mutedConfiguration: HostRuntimeConfiguration = {
      ...jackConfiguration,
      routes: [{ id: "mic-program", from: "mic", to: "program", muted: true }]
    };
    const { runner, calls } = createRecordingRunner({
      jack_lsp: { stdout: jackPorts() },
      "jack_lsp -c": {
        stdout: jackConnections([
          ["studio_mic:capture_1", "loopwire_program:playback_1"],
          ["studio_mic:capture_2", "loopwire_program:playback_2"]
        ])
      },
      "jack_disconnect studio_mic:capture_1 loopwire_program:playback_1": { stdout: "" },
      "jack_disconnect studio_mic:capture_2 loopwire_program:playback_2": { stdout: "" }
    });
    const adapter = createJackGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply(mutedConfiguration);

    expect(result).toEqual({
      ok: true,
      message: "Disconnected 2 muted JACK port pair(s); Connected 0 JACK port pair(s); 0 already connected"
    });
    expect(calls).toEqual([
      "jack_lsp",
      "jack_lsp -c",
      "jack_disconnect studio_mic:capture_1 loopwire_program:playback_1",
      "jack_disconnect studio_mic:capture_2 loopwire_program:playback_2"
    ]);
  });

  it("connects configured outputs to physical JACK monitor sinks", async () => {
    const { runner, calls } = createRecordingRunner({
      jack_lsp: { stdout: jackPortsWithMonitor() },
      "jack_lsp -c": { stdout: "" },
      "jack_connect studio_mic:capture_1 loopwire_program:playback_1": { stdout: "" },
      "jack_connect studio_mic:capture_2 loopwire_program:playback_2": { stdout: "" },
      "jack_connect loopwire_program:monitor_1 system:playback_1": { stdout: "" },
      "jack_connect loopwire_program:monitor_2 system:playback_2": { stdout: "" }
    });
    const adapter = createJackGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply(monitoredJackConfiguration);

    expect(result).toEqual({ ok: true, message: "Connected 4 JACK port pair(s); 0 already connected" });
    expect(calls).toEqual([
      "jack_lsp",
      "jack_lsp -c",
      "jack_connect studio_mic:capture_1 loopwire_program:playback_1",
      "jack_connect studio_mic:capture_2 loopwire_program:playback_2",
      "jack_connect loopwire_program:monitor_1 system:playback_1",
      "jack_connect loopwire_program:monitor_2 system:playback_2"
    ]);
  });

  it("fails verification when a configured JACK connection is missing", async () => {
    const { runner } = createRecordingRunner({
      jack_lsp: { stdout: jackPorts() },
      "jack_lsp -c": { stdout: jackConnections([["studio_mic:capture_1", "loopwire_program:playback_1"]]) }
    });
    const adapter = createJackGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.verify(jackConfiguration);

    expect(result).toEqual({
      ok: false,
      message: "Missing JACK connection(s): studio_mic:capture_2 -> loopwire_program:playback_2"
    });
  });

  it("fails verification when a muted JACK route is still connected", async () => {
    const mutedConfiguration: HostRuntimeConfiguration = {
      ...jackConfiguration,
      routes: [{ id: "mic-program", from: "mic", to: "program", muted: true }]
    };
    const { runner } = createRecordingRunner({
      jack_lsp: { stdout: jackPorts() },
      "jack_lsp -c": {
        stdout: jackConnections([
          ["studio_mic:capture_1", "loopwire_program:playback_1"],
          ["studio_mic:capture_2", "loopwire_program:playback_2"]
        ])
      }
    });
    const adapter = createJackGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.verify(mutedConfiguration);

    expect(result).toEqual({
      ok: false,
      message:
        "Muted JACK connection(s) still connected: studio_mic:capture_1 -> loopwire_program:playback_1, " +
        "studio_mic:capture_2 -> loopwire_program:playback_2"
    });
  });

  it("disconnects only JACK connections that match the configuration", async () => {
    const { runner, calls } = createRecordingRunner({
      jack_lsp: { stdout: jackPorts() },
      "jack_lsp -c": {
        stdout: jackConnections([
          ["studio_mic:capture_1", "loopwire_program:playback_1"],
          ["studio_mic:capture_2", "loopwire_program:playback_2"],
          ["other:output_1", "loopwire_program:playback_1"]
        ])
      },
      "jack_disconnect studio_mic:capture_1 loopwire_program:playback_1": { stdout: "" },
      "jack_disconnect studio_mic:capture_2 loopwire_program:playback_2": { stdout: "" }
    });
    const adapter = createJackGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.rollback(jackConfiguration);

    expect(result).toEqual({ ok: true, message: "Disconnected 2 JACK port pair(s)" });
    expect(calls).toEqual([
      "jack_lsp",
      "jack_lsp -c",
      "jack_disconnect studio_mic:capture_1 loopwire_program:playback_1",
      "jack_disconnect studio_mic:capture_2 loopwire_program:playback_2"
    ]);
  });

  it("rolls back JACK connections created before a later connection fails", async () => {
    const { runner, calls } = createRecordingRunner({
      jack_lsp: { stdout: jackPorts() },
      "jack_lsp -c": { stdout: "" },
      "jack_connect studio_mic:capture_1 loopwire_program:playback_1": { stdout: "" },
      "jack_connect studio_mic:capture_2 loopwire_program:playback_2": { exitCode: 1, stderr: "connect failed\n" },
      "jack_disconnect studio_mic:capture_1 loopwire_program:playback_1": { stdout: "" }
    });
    const adapter = createJackGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply(jackConfiguration);

    expect(result).toEqual({
      ok: false,
      message: "Could not connect JACK ports studio_mic:capture_2 -> loopwire_program:playback_2: connect failed"
    });
    expect(calls).toEqual([
      "jack_lsp",
      "jack_lsp -c",
      "jack_connect studio_mic:capture_1 loopwire_program:playback_1",
      "jack_connect studio_mic:capture_2 loopwire_program:playback_2",
      "jack_disconnect studio_mic:capture_1 loopwire_program:playback_1"
    ]);
  });

  it("rejects non-unity gain before attempting JACK commands", async () => {
    const { runner, calls } = createRecordingRunner({});
    const adapter = createJackGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply({
      ...jackConfiguration,
      routes: [{ id: "mic-program", from: "mic", to: "program", gain: 0.5, muted: false }]
    });

    expect(result).toEqual({
      ok: false,
      message: "Route mic-program has gain 0.5; native JACK connections only support unity gain for now"
    });
    expect(calls).toEqual([]);
  });

  it("rejects virtual JACK monitor sinks before attempting commands", async () => {
    const { runner, calls } = createRecordingRunner({});
    const adapter = createJackGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply({
      ...jackConfiguration,
      monitors: [{ id: "headphones", label: "Headphones", channels: 2 }]
    });

    expect(result).toEqual({
      ok: false,
      message: "Monitor headphones needs a deviceName; native JACK monitor routing requires an existing sink"
    });
    expect(calls).toEqual([]);
  });
});

function jackPorts(): string {
  return [
    "studio_mic:capture_1",
    "studio_mic:capture_2",
    "loopwire_program:playback_1",
    "loopwire_program:playback_2",
    "other:output_1"
  ].join("\n");
}

function jackPortsWithMonitor(): string {
  return `${jackPorts()}\nloopwire_program:monitor_1\nloopwire_program:monitor_2\nsystem:playback_1\nsystem:playback_2`;
}

function jackConnections(pairs: readonly (readonly [string, string])[]): string {
  return pairs.map(([source, target]) => `${source}\n   ${target}`).join("\n");
}
