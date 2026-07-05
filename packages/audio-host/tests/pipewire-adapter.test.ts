import { describe, expect, it } from "vitest";
import { createPipeWireGraphRuntimeAdapter, type HostRuntimeConfiguration } from "../src/index.js";
import type { CommandResult, CommandRunner } from "../src/types.js";

type CommandKey = string;
type CommandResponse = Partial<CommandResult> | readonly Partial<CommandResult>[];

const pipeWireConfiguration: HostRuntimeConfiguration = {
  id: "Native Mix",
  name: "Native Mix",
  inputs: [{ id: "mic", label: "Studio Mic", channels: 2, deviceName: "alsa_input.studio" }],
  outputs: [{ id: "program", label: "Program Out", channels: 2, deviceName: "loopwire_program" }],
  routes: [{ id: "mic-program", from: "mic", to: "program", muted: false }]
};

const monitoredPipeWireConfiguration: HostRuntimeConfiguration = {
  ...pipeWireConfiguration,
  monitors: [{ id: "headphones", label: "Headphones", channels: 2, deviceName: "alsa_output.headphones" }]
};

function createRecordingRunner(results: Record<CommandKey, CommandResponse>): {
  readonly runner: CommandRunner;
  readonly calls: string[];
} {
  const calls: string[] = [];
  const counts = new Map<string, number>();

  return {
    calls,
    runner: {
      async run(command, args) {
        const key = [command, ...args].join(" ");
        calls.push(key);
        const result = selectCommandResult(results[key] ?? results[command] ?? {}, key, counts);

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

function selectCommandResult(
  result: CommandResponse,
  key: string,
  counts: Map<string, number>
): Partial<CommandResult> {
  if (!Array.isArray(result)) {
    return result;
  }

  const index = counts.get(key) ?? 0;
  counts.set(key, index + 1);
  return result[Math.min(index, result.length - 1)] ?? {};
}

describe("createPipeWireGraphRuntimeAdapter", () => {
  it("dry-runs apply and verify without mutating the host", async () => {
    const { runner, calls } = createRecordingRunner({});
    const adapter = createPipeWireGraphRuntimeAdapter(runner);

    const apply = await adapter.apply(pipeWireConfiguration);
    const verify = await adapter.verify(pipeWireConfiguration);

    expect(apply).toEqual({ ok: true, message: "Dry run planned 1 PipeWire link plan(s)" });
    expect(verify).toEqual({ ok: true, message: "Dry run verified 1 PipeWire link plan(s)" });
    expect(calls).toEqual([]);
    expect(adapter.commandLog.map((entry) => [entry.operation, entry.args.join(" "), entry.skipped])).toEqual([
      ["apply", "-o", true],
      ["apply", "-i", true],
      ["apply", "-l", true],
      ["verify", "-o", true],
      ["verify", "-i", true],
      ["verify", "-l", true]
    ]);
  });

  it("links matching PipeWire ports by endpoint device names", async () => {
    const { runner, calls } = createRecordingRunner({
      "pw-link -o": { stdout: sourcePorts() },
      "pw-link -i": { stdout: targetPorts() },
      "pw-link -l": { stdout: "" },
      "pw-link alsa_input.studio:capture_FL loopwire_program:playback_FL": { stdout: "" },
      "pw-link alsa_input.studio:capture_FR loopwire_program:playback_FR": { stdout: "" }
    });
    const adapter = createPipeWireGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply(pipeWireConfiguration);

    expect(result).toEqual({ ok: true, message: "Linked 2 PipeWire port pair(s); 0 already linked" });
    expect(calls).toEqual([
      "pw-link -o",
      "pw-link -i",
      "pw-link -l",
      "pw-link alsa_input.studio:capture_FL loopwire_program:playback_FL",
      "pw-link alsa_input.studio:capture_FR loopwire_program:playback_FR"
    ]);
  });

  it("creates virtual PipeWire output sinks before linking matching ports", async () => {
    const virtualOutputConfiguration: HostRuntimeConfiguration = {
      ...pipeWireConfiguration,
      outputs: [{ id: "program", label: "Program Out", channels: 2 }]
    };
    const { runner, calls } = createRecordingRunner({
      "pw-cli list-objects Node": [
        { stdout: "" },
        { stdout: pipeWireNode("99", "loopwire_native_mix_program") }
      ],
      "pw-cli": { stdout: "" },
      "pw-link -o": { stdout: sourcePorts() },
      "pw-link -i": { stdout: virtualTargetPorts() },
      "pw-link -l": { stdout: "" },
      "pw-link alsa_input.studio:capture_FL loopwire_native_mix_program:playback_FL": { stdout: "" },
      "pw-link alsa_input.studio:capture_FR loopwire_native_mix_program:playback_FR": { stdout: "" }
    });
    const adapter = createPipeWireGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply(virtualOutputConfiguration);

    expect(result).toEqual({
      ok: true,
      message: "Created 1 PipeWire virtual sink node(s); Linked 2 PipeWire port pair(s); 0 already linked"
    });
    expect(calls).toEqual([
      "pw-cli list-objects Node",
      "pw-cli create-node adapter " + pipeWireVirtualSinkProps("loopwire_native_mix_program", "Program Out", "FL FR"),
      "pw-cli list-objects Node",
      "pw-link -o",
      "pw-link -i",
      "pw-link -l",
      "pw-link alsa_input.studio:capture_FL loopwire_native_mix_program:playback_FL",
      "pw-link alsa_input.studio:capture_FR loopwire_native_mix_program:playback_FR"
    ]);
  });

  it("skips PipeWire links that already exist", async () => {
    const { runner, calls } = createRecordingRunner({
      "pw-link -o": { stdout: sourcePorts() },
      "pw-link -i": { stdout: targetPorts() },
      "pw-link -l": { stdout: pipeWireLinks([["alsa_input.studio:capture_FL", "loopwire_program:playback_FL"]]) },
      "pw-link alsa_input.studio:capture_FR loopwire_program:playback_FR": { stdout: "" }
    });
    const adapter = createPipeWireGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply(pipeWireConfiguration);

    expect(result).toEqual({ ok: true, message: "Linked 1 PipeWire port pair(s); 1 already linked" });
    expect(calls).toEqual([
      "pw-link -o",
      "pw-link -i",
      "pw-link -l",
      "pw-link alsa_input.studio:capture_FR loopwire_program:playback_FR"
    ]);
  });

  it("unlinks muted PipeWire route links during apply", async () => {
    const mutedConfiguration: HostRuntimeConfiguration = {
      ...pipeWireConfiguration,
      routes: [{ id: "mic-program", from: "mic", to: "program", muted: true }]
    };
    const { runner, calls } = createRecordingRunner({
      "pw-link -o": { stdout: sourcePorts() },
      "pw-link -i": { stdout: targetPorts() },
      "pw-link -l": {
        stdout: pipeWireLinks([
          ["alsa_input.studio:capture_FL", "loopwire_program:playback_FL"],
          ["alsa_input.studio:capture_FR", "loopwire_program:playback_FR"]
        ])
      },
      "pw-link -d alsa_input.studio:capture_FL loopwire_program:playback_FL": { stdout: "" },
      "pw-link -d alsa_input.studio:capture_FR loopwire_program:playback_FR": { stdout: "" }
    });
    const adapter = createPipeWireGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply(mutedConfiguration);

    expect(result).toEqual({
      ok: true,
      message: "Unlinked 2 muted PipeWire link pair(s); Linked 0 PipeWire port pair(s); 0 already linked"
    });
    expect(calls).toEqual([
      "pw-link -o",
      "pw-link -i",
      "pw-link -l",
      "pw-link -d alsa_input.studio:capture_FL loopwire_program:playback_FL",
      "pw-link -d alsa_input.studio:capture_FR loopwire_program:playback_FR"
    ]);
  });

  it("links configured outputs to physical monitor sinks", async () => {
    const { runner, calls } = createRecordingRunner({
      "pw-link -o": { stdout: sourcePortsWithMonitor() },
      "pw-link -i": { stdout: `${targetPorts()}\n${monitorTargetPorts()}` },
      "pw-link -l": { stdout: "" },
      "pw-link alsa_input.studio:capture_FL loopwire_program:playback_FL": { stdout: "" },
      "pw-link alsa_input.studio:capture_FR loopwire_program:playback_FR": { stdout: "" },
      "pw-link loopwire_program:monitor_FL alsa_output.headphones:playback_FL": { stdout: "" },
      "pw-link loopwire_program:monitor_FR alsa_output.headphones:playback_FR": { stdout: "" }
    });
    const adapter = createPipeWireGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply(monitoredPipeWireConfiguration);

    expect(result).toEqual({ ok: true, message: "Linked 4 PipeWire port pair(s); 0 already linked" });
    expect(calls).toEqual([
      "pw-link -o",
      "pw-link -i",
      "pw-link -l",
      "pw-link alsa_input.studio:capture_FL loopwire_program:playback_FL",
      "pw-link alsa_input.studio:capture_FR loopwire_program:playback_FR",
      "pw-link loopwire_program:monitor_FL alsa_output.headphones:playback_FL",
      "pw-link loopwire_program:monitor_FR alsa_output.headphones:playback_FR"
    ]);
  });

  it("creates virtual PipeWire monitor sinks before linking monitor ports", async () => {
    const virtualMonitorConfiguration: HostRuntimeConfiguration = {
      ...monitoredPipeWireConfiguration,
      monitors: [{ id: "headphones", label: "Headphones", channels: 2 }]
    };
    const { runner, calls } = createRecordingRunner({
      "pw-cli list-objects Node": [
        { stdout: "" },
        { stdout: pipeWireNode("100", "loopwire_native_mix_monitor_headphones") }
      ],
      "pw-cli": { stdout: "" },
      "pw-link -o": { stdout: sourcePortsWithMonitor() },
      "pw-link -i": { stdout: `${targetPorts()}\n${virtualMonitorTargetPorts()}` },
      "pw-link -l": { stdout: "" },
      "pw-link alsa_input.studio:capture_FL loopwire_program:playback_FL": { stdout: "" },
      "pw-link alsa_input.studio:capture_FR loopwire_program:playback_FR": { stdout: "" },
      "pw-link loopwire_program:monitor_FL loopwire_native_mix_monitor_headphones:playback_FL": { stdout: "" },
      "pw-link loopwire_program:monitor_FR loopwire_native_mix_monitor_headphones:playback_FR": { stdout: "" }
    });
    const adapter = createPipeWireGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply(virtualMonitorConfiguration);

    expect(result).toEqual({
      ok: true,
      message: "Created 1 PipeWire virtual sink node(s); Linked 4 PipeWire port pair(s); 0 already linked"
    });
    expect(calls).toEqual([
      "pw-cli list-objects Node",
      "pw-cli create-node adapter " +
        pipeWireVirtualSinkProps("loopwire_native_mix_monitor_headphones", "Headphones", "FL FR"),
      "pw-cli list-objects Node",
      "pw-link -o",
      "pw-link -i",
      "pw-link -l",
      "pw-link alsa_input.studio:capture_FL loopwire_program:playback_FL",
      "pw-link alsa_input.studio:capture_FR loopwire_program:playback_FR",
      "pw-link loopwire_program:monitor_FL loopwire_native_mix_monitor_headphones:playback_FL",
      "pw-link loopwire_program:monitor_FR loopwire_native_mix_monitor_headphones:playback_FR"
    ]);
  });

  it("fails verification when a configured PipeWire link is missing", async () => {
    const { runner } = createRecordingRunner({
      "pw-link -o": { stdout: sourcePorts() },
      "pw-link -i": { stdout: targetPorts() },
      "pw-link -l": { stdout: pipeWireLinks([["alsa_input.studio:capture_FL", "loopwire_program:playback_FL"]]) }
    });
    const adapter = createPipeWireGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.verify(pipeWireConfiguration);

    expect(result).toEqual({
      ok: false,
      message: "Missing PipeWire link(s): alsa_input.studio:capture_FR -> loopwire_program:playback_FR"
    });
  });

  it("fails verification when a configured PipeWire monitor link is missing", async () => {
    const { runner } = createRecordingRunner({
      "pw-link -o": { stdout: sourcePortsWithMonitor() },
      "pw-link -i": { stdout: `${targetPorts()}\n${monitorTargetPorts()}` },
      "pw-link -l": {
        stdout: pipeWireLinks([
          ["alsa_input.studio:capture_FL", "loopwire_program:playback_FL"],
          ["alsa_input.studio:capture_FR", "loopwire_program:playback_FR"],
          ["loopwire_program:monitor_FL", "alsa_output.headphones:playback_FL"]
        ])
      }
    });
    const adapter = createPipeWireGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.verify(monitoredPipeWireConfiguration);

    expect(result).toEqual({
      ok: false,
      message: "Missing PipeWire link(s): loopwire_program:monitor_FR -> alsa_output.headphones:playback_FR"
    });
  });

  it("fails verification when a muted PipeWire route is still linked", async () => {
    const mutedConfiguration: HostRuntimeConfiguration = {
      ...pipeWireConfiguration,
      routes: [{ id: "mic-program", from: "mic", to: "program", muted: true }]
    };
    const { runner } = createRecordingRunner({
      "pw-link -o": { stdout: sourcePorts() },
      "pw-link -i": { stdout: targetPorts() },
      "pw-link -l": {
        stdout: pipeWireLinks([
          ["alsa_input.studio:capture_FL", "loopwire_program:playback_FL"],
          ["alsa_input.studio:capture_FR", "loopwire_program:playback_FR"]
        ])
      }
    });
    const adapter = createPipeWireGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.verify(mutedConfiguration);

    expect(result).toEqual({
      ok: false,
      message:
        "Muted PipeWire link(s) still connected: alsa_input.studio:capture_FL -> loopwire_program:playback_FL, " +
        "alsa_input.studio:capture_FR -> loopwire_program:playback_FR"
    });
  });

  it("unloads only the PipeWire links that match the configuration", async () => {
    const { runner, calls } = createRecordingRunner({
      "pw-link -o": { stdout: sourcePorts() },
      "pw-link -i": { stdout: targetPorts() },
      "pw-link -l": {
        stdout: pipeWireLinks([
          ["alsa_input.studio:capture_FL", "loopwire_program:playback_FL"],
          ["alsa_input.studio:capture_FR", "loopwire_program:playback_FR"],
          ["other:output_FL", "loopwire_program:playback_FL"]
        ])
      },
      "pw-link -d alsa_input.studio:capture_FL loopwire_program:playback_FL": { stdout: "" },
      "pw-link -d alsa_input.studio:capture_FR loopwire_program:playback_FR": { stdout: "" }
    });
    const adapter = createPipeWireGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.rollback(pipeWireConfiguration);

    expect(result).toEqual({ ok: true, message: "Unlinked 2 PipeWire port pair(s)" });
    expect(calls).toEqual([
      "pw-link -o",
      "pw-link -i",
      "pw-link -l",
      "pw-link -d alsa_input.studio:capture_FL loopwire_program:playback_FL",
      "pw-link -d alsa_input.studio:capture_FR loopwire_program:playback_FR"
    ]);
  });

  it("destroys configured virtual PipeWire output sinks during unload", async () => {
    const virtualOutputConfiguration: HostRuntimeConfiguration = {
      ...pipeWireConfiguration,
      outputs: [{ id: "program", label: "Program Out", channels: 2 }]
    };
    const { runner, calls } = createRecordingRunner({
      "pw-link -o": { stdout: sourcePorts() },
      "pw-link -i": { stdout: virtualTargetPorts() },
      "pw-link -l": {
        stdout: pipeWireLinks([
          ["alsa_input.studio:capture_FL", "loopwire_native_mix_program:playback_FL"],
          ["alsa_input.studio:capture_FR", "loopwire_native_mix_program:playback_FR"]
        ])
      },
      "pw-link -d alsa_input.studio:capture_FL loopwire_native_mix_program:playback_FL": { stdout: "" },
      "pw-link -d alsa_input.studio:capture_FR loopwire_native_mix_program:playback_FR": { stdout: "" },
      "pw-cli list-objects Node": { stdout: pipeWireNode("99", "loopwire_native_mix_program") },
      "pw-cli destroy 99": { stdout: "" }
    });
    const adapter = createPipeWireGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.unload(virtualOutputConfiguration);

    expect(result).toEqual({
      ok: true,
      message: "Unlinked 2 PipeWire port pair(s); Destroyed 1 PipeWire virtual sink node(s)"
    });
    expect(calls).toEqual([
      "pw-link -o",
      "pw-link -i",
      "pw-link -l",
      "pw-link -d alsa_input.studio:capture_FL loopwire_native_mix_program:playback_FL",
      "pw-link -d alsa_input.studio:capture_FR loopwire_native_mix_program:playback_FR",
      "pw-cli list-objects Node",
      "pw-cli destroy 99"
    ]);
  });

  it("unloads configured PipeWire monitor links with the selected configuration", async () => {
    const { runner, calls } = createRecordingRunner({
      "pw-link -o": { stdout: sourcePortsWithMonitor() },
      "pw-link -i": { stdout: `${targetPorts()}\n${monitorTargetPorts()}` },
      "pw-link -l": {
        stdout: pipeWireLinks([
          ["alsa_input.studio:capture_FL", "loopwire_program:playback_FL"],
          ["alsa_input.studio:capture_FR", "loopwire_program:playback_FR"],
          ["loopwire_program:monitor_FL", "alsa_output.headphones:playback_FL"],
          ["loopwire_program:monitor_FR", "alsa_output.headphones:playback_FR"]
        ])
      },
      "pw-link -d alsa_input.studio:capture_FL loopwire_program:playback_FL": { stdout: "" },
      "pw-link -d alsa_input.studio:capture_FR loopwire_program:playback_FR": { stdout: "" },
      "pw-link -d loopwire_program:monitor_FL alsa_output.headphones:playback_FL": { stdout: "" },
      "pw-link -d loopwire_program:monitor_FR alsa_output.headphones:playback_FR": { stdout: "" }
    });
    const adapter = createPipeWireGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.rollback(monitoredPipeWireConfiguration);

    expect(result).toEqual({ ok: true, message: "Unlinked 4 PipeWire port pair(s)" });
    expect(calls).toEqual([
      "pw-link -o",
      "pw-link -i",
      "pw-link -l",
      "pw-link -d alsa_input.studio:capture_FL loopwire_program:playback_FL",
      "pw-link -d alsa_input.studio:capture_FR loopwire_program:playback_FR",
      "pw-link -d loopwire_program:monitor_FL alsa_output.headphones:playback_FL",
      "pw-link -d loopwire_program:monitor_FR alsa_output.headphones:playback_FR"
    ]);
  });

  it("destroys configured virtual PipeWire monitor sinks during unload", async () => {
    const virtualMonitorConfiguration: HostRuntimeConfiguration = {
      ...monitoredPipeWireConfiguration,
      monitors: [{ id: "headphones", label: "Headphones", channels: 2 }]
    };
    const { runner, calls } = createRecordingRunner({
      "pw-link -o": { stdout: sourcePortsWithMonitor() },
      "pw-link -i": { stdout: `${targetPorts()}\n${virtualMonitorTargetPorts()}` },
      "pw-link -l": {
        stdout: pipeWireLinks([
          ["alsa_input.studio:capture_FL", "loopwire_program:playback_FL"],
          ["alsa_input.studio:capture_FR", "loopwire_program:playback_FR"],
          ["loopwire_program:monitor_FL", "loopwire_native_mix_monitor_headphones:playback_FL"],
          ["loopwire_program:monitor_FR", "loopwire_native_mix_monitor_headphones:playback_FR"]
        ])
      },
      "pw-link -d alsa_input.studio:capture_FL loopwire_program:playback_FL": { stdout: "" },
      "pw-link -d alsa_input.studio:capture_FR loopwire_program:playback_FR": { stdout: "" },
      "pw-link -d loopwire_program:monitor_FL loopwire_native_mix_monitor_headphones:playback_FL": { stdout: "" },
      "pw-link -d loopwire_program:monitor_FR loopwire_native_mix_monitor_headphones:playback_FR": { stdout: "" },
      "pw-cli list-objects Node": { stdout: pipeWireNode("100", "loopwire_native_mix_monitor_headphones") },
      "pw-cli destroy 100": { stdout: "" }
    });
    const adapter = createPipeWireGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.unload(virtualMonitorConfiguration);

    expect(result).toEqual({
      ok: true,
      message: "Unlinked 4 PipeWire port pair(s); Destroyed 1 PipeWire virtual sink node(s)"
    });
    expect(calls).toEqual([
      "pw-link -o",
      "pw-link -i",
      "pw-link -l",
      "pw-link -d alsa_input.studio:capture_FL loopwire_program:playback_FL",
      "pw-link -d alsa_input.studio:capture_FR loopwire_program:playback_FR",
      "pw-link -d loopwire_program:monitor_FL loopwire_native_mix_monitor_headphones:playback_FL",
      "pw-link -d loopwire_program:monitor_FR loopwire_native_mix_monitor_headphones:playback_FR",
      "pw-cli list-objects Node",
      "pw-cli destroy 100"
    ]);
  });

  it("rolls back PipeWire links created before a later link fails", async () => {
    const { runner, calls } = createRecordingRunner({
      "pw-link -o": { stdout: sourcePorts() },
      "pw-link -i": { stdout: targetPorts() },
      "pw-link -l": { stdout: "" },
      "pw-link alsa_input.studio:capture_FL loopwire_program:playback_FL": { stdout: "" },
      "pw-link alsa_input.studio:capture_FR loopwire_program:playback_FR": { exitCode: 1, stderr: "link failed\n" },
      "pw-link -d alsa_input.studio:capture_FL loopwire_program:playback_FL": { stdout: "" }
    });
    const adapter = createPipeWireGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply(pipeWireConfiguration);

    expect(result).toEqual({
      ok: false,
      message: "Could not link PipeWire ports alsa_input.studio:capture_FR -> loopwire_program:playback_FR: link failed"
    });
    expect(calls).toEqual([
      "pw-link -o",
      "pw-link -i",
      "pw-link -l",
      "pw-link alsa_input.studio:capture_FL loopwire_program:playback_FL",
      "pw-link alsa_input.studio:capture_FR loopwire_program:playback_FR",
      "pw-link -d alsa_input.studio:capture_FL loopwire_program:playback_FL"
    ]);
  });

  it("rolls back created virtual PipeWire sinks when linking fails", async () => {
    const virtualOutputConfiguration: HostRuntimeConfiguration = {
      ...pipeWireConfiguration,
      outputs: [{ id: "program", label: "Program Out", channels: 2 }]
    };
    const { runner, calls } = createRecordingRunner({
      "pw-cli list-objects Node": [
        { stdout: "" },
        { stdout: pipeWireNode("99", "loopwire_native_mix_program") }
      ],
      "pw-cli": { stdout: "" },
      "pw-link -o": { stdout: sourcePorts() },
      "pw-link -i": { stdout: virtualTargetPorts() },
      "pw-link -l": { stdout: "" },
      "pw-link alsa_input.studio:capture_FL loopwire_native_mix_program:playback_FL": { stdout: "" },
      "pw-link alsa_input.studio:capture_FR loopwire_native_mix_program:playback_FR": {
        exitCode: 1,
        stderr: "link failed\n"
      },
      "pw-link -d alsa_input.studio:capture_FL loopwire_native_mix_program:playback_FL": { stdout: "" },
      "pw-cli destroy 99": { stdout: "" }
    });
    const adapter = createPipeWireGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply(virtualOutputConfiguration);

    expect(result).toEqual({
      ok: false,
      message:
        "Could not link PipeWire ports alsa_input.studio:capture_FR -> " +
        "loopwire_native_mix_program:playback_FR: link failed"
    });
    expect(calls).toEqual([
      "pw-cli list-objects Node",
      "pw-cli create-node adapter " + pipeWireVirtualSinkProps("loopwire_native_mix_program", "Program Out", "FL FR"),
      "pw-cli list-objects Node",
      "pw-link -o",
      "pw-link -i",
      "pw-link -l",
      "pw-link alsa_input.studio:capture_FL loopwire_native_mix_program:playback_FL",
      "pw-link alsa_input.studio:capture_FR loopwire_native_mix_program:playback_FR",
      "pw-link -d alsa_input.studio:capture_FL loopwire_native_mix_program:playback_FL",
      "pw-cli destroy 99"
    ]);
  });

  it("rolls back created virtual PipeWire monitor sinks when monitor linking fails", async () => {
    const virtualMonitorConfiguration: HostRuntimeConfiguration = {
      ...monitoredPipeWireConfiguration,
      monitors: [{ id: "headphones", label: "Headphones", channels: 2 }]
    };
    const { runner, calls } = createRecordingRunner({
      "pw-cli list-objects Node": [
        { stdout: "" },
        { stdout: pipeWireNode("100", "loopwire_native_mix_monitor_headphones") }
      ],
      "pw-cli": { stdout: "" },
      "pw-link -o": { stdout: sourcePortsWithMonitor() },
      "pw-link -i": { stdout: `${targetPorts()}\n${virtualMonitorTargetPorts()}` },
      "pw-link -l": { stdout: "" },
      "pw-link alsa_input.studio:capture_FL loopwire_program:playback_FL": { stdout: "" },
      "pw-link alsa_input.studio:capture_FR loopwire_program:playback_FR": { stdout: "" },
      "pw-link loopwire_program:monitor_FL loopwire_native_mix_monitor_headphones:playback_FL": {
        exitCode: 1,
        stderr: "monitor link failed\n"
      },
      "pw-link -d alsa_input.studio:capture_FR loopwire_program:playback_FR": { stdout: "" },
      "pw-link -d alsa_input.studio:capture_FL loopwire_program:playback_FL": { stdout: "" },
      "pw-cli destroy 100": { stdout: "" }
    });
    const adapter = createPipeWireGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply(virtualMonitorConfiguration);

    expect(result).toEqual({
      ok: false,
      message:
        "Could not link PipeWire ports loopwire_program:monitor_FL -> " +
        "loopwire_native_mix_monitor_headphones:playback_FL: monitor link failed"
    });
    expect(calls).toEqual([
      "pw-cli list-objects Node",
      "pw-cli create-node adapter " +
        pipeWireVirtualSinkProps("loopwire_native_mix_monitor_headphones", "Headphones", "FL FR"),
      "pw-cli list-objects Node",
      "pw-link -o",
      "pw-link -i",
      "pw-link -l",
      "pw-link alsa_input.studio:capture_FL loopwire_program:playback_FL",
      "pw-link alsa_input.studio:capture_FR loopwire_program:playback_FR",
      "pw-link loopwire_program:monitor_FL loopwire_native_mix_monitor_headphones:playback_FL",
      "pw-link -d alsa_input.studio:capture_FR loopwire_program:playback_FR",
      "pw-link -d alsa_input.studio:capture_FL loopwire_program:playback_FL",
      "pw-cli destroy 100"
    ]);
  });

  it("rejects non-unity gain before attempting PipeWire commands", async () => {
    const { runner, calls } = createRecordingRunner({});
    const adapter = createPipeWireGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply({
      ...pipeWireConfiguration,
      routes: [{ id: "mic-program", from: "mic", to: "program", gain: 0.5, muted: false }]
    });

    expect(result).toEqual({
      ok: false,
      message: "Route mic-program has gain 0.5; native PipeWire links only support unity gain for now"
    });
    expect(calls).toEqual([]);
  });

  it("allows non-unity gain on muted PipeWire routes", async () => {
    const mutedConfiguration: HostRuntimeConfiguration = {
      ...pipeWireConfiguration,
      routes: [{ id: "mic-program", from: "mic", to: "program", gain: 0.5, muted: true }]
    };
    const { runner, calls } = createRecordingRunner({
      "pw-link -o": { stdout: sourcePorts() },
      "pw-link -i": { stdout: targetPorts() },
      "pw-link -l": {
        stdout: pipeWireLinks([
          ["alsa_input.studio:capture_FL", "loopwire_program:playback_FL"],
          ["alsa_input.studio:capture_FR", "loopwire_program:playback_FR"]
        ])
      },
      "pw-link -d alsa_input.studio:capture_FL loopwire_program:playback_FL": { stdout: "" },
      "pw-link -d alsa_input.studio:capture_FR loopwire_program:playback_FR": { stdout: "" }
    });
    const adapter = createPipeWireGraphRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply(mutedConfiguration);

    expect(result).toEqual({
      ok: true,
      message: "Unlinked 2 muted PipeWire link pair(s); Linked 0 PipeWire port pair(s); 0 already linked"
    });
    expect(calls).toEqual([
      "pw-link -o",
      "pw-link -i",
      "pw-link -l",
      "pw-link -d alsa_input.studio:capture_FL loopwire_program:playback_FL",
      "pw-link -d alsa_input.studio:capture_FR loopwire_program:playback_FR"
    ]);
  });

});

function sourcePorts(): string {
  return ["alsa_input.studio:capture_FL", "alsa_input.studio:capture_FR", "unrelated:output_FL"].join("\n");
}

function sourcePortsWithMonitor(): string {
  return `${sourcePorts()}\nloopwire_program:monitor_FL\nloopwire_program:monitor_FR`;
}

function targetPorts(): string {
  return ["loopwire_program:playback_FL", "loopwire_program:playback_FR", "other:playback_FL"].join("\n");
}

function virtualTargetPorts(): string {
  return ["loopwire_native_mix_program:playback_FL", "loopwire_native_mix_program:playback_FR", "other:playback_FL"].join("\n");
}

function monitorTargetPorts(): string {
  return ["alsa_output.headphones:playback_FL", "alsa_output.headphones:playback_FR"].join("\n");
}

function virtualMonitorTargetPorts(): string {
  return [
    "loopwire_native_mix_monitor_headphones:playback_FL",
    "loopwire_native_mix_monitor_headphones:playback_FR"
  ].join("\n");
}

function pipeWireLinks(pairs: readonly (readonly [string, string])[]): string {
  return pairs.map(([source, target]) => `${source}\n  |-> ${target}`).join("\n");
}

function pipeWireNode(id: string, name: string): string {
  return [
    `id ${id}, type PipeWire:Interface:Node/3`,
    ` \tnode.name = "${name}"`,
    ' \tmedia.class = "Audio/Sink"'
  ].join("\n");
}

function pipeWireVirtualSinkProps(name: string, description: string, positions: string): string {
  return `{ factory.name=support.null-audio-sink node.name="${name}" node.description="${description}" ` +
    `media.class=Audio/Sink object.linger=true audio.position=[${positions}] ` +
    "adapter.auto-port-config={ mode=dsp monitor=true position=preserve } }";
}
