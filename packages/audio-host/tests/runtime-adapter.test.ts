import { describe, expect, it } from "vitest";
import {
  createPactlVirtualSinkRuntimeAdapter,
  sinkNameForMonitor,
  sinkNameForOutput,
  type HostRuntimeConfiguration
} from "../src/index.js";
import type { CommandResult, CommandRunner } from "../src/types.js";

type CommandKey = string;

const streamConfiguration: HostRuntimeConfiguration = {
  id: "Stream Deck",
  name: "Stream Mix",
  outputs: [
    { id: "Main Out", label: "Main Output", channels: 2 },
    { id: "Monitor Out", label: "Monitor Output", channels: 2 }
  ]
};

const routedConfiguration: HostRuntimeConfiguration = {
  id: "Routed Mix",
  name: "Routed Mix",
  inputs: [
    { id: "firefox", label: "Firefox", channels: 2 },
    { id: "discord", label: "Discord", channels: 2 }
  ],
  outputs: [{ id: "Program", label: "Program", channels: 2 }],
  routes: [
    { id: "firefox-program", from: "firefox", to: "Program", gain: 0.42, muted: false },
    { id: "discord-program", from: "discord", to: "Program", gain: 0.25, muted: true }
  ]
};

const monitoredConfiguration: HostRuntimeConfiguration = {
  id: "Monitored Mix",
  name: "Monitored Mix",
  outputs: [{ id: "Program", label: "Program", channels: 2 }],
  monitors: [
    { id: "Headphones", label: "Headphones", channels: 2 },
    { id: "Meters", label: "Meter Bridge", channels: 2 }
  ]
};

const physicalMonitorConfiguration: HostRuntimeConfiguration = {
  id: "Physical Monitor Mix",
  name: "Physical Monitor Mix",
  outputs: [{ id: "Program", label: "Program", channels: 2 }],
  monitors: [{ id: "Headphones", label: "Headphones", channels: 2, deviceName: "alsa_output.usb_headphones" }]
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

describe("createPactlVirtualSinkRuntimeAdapter", () => {
  it("builds deterministic virtual sink names", () => {
    expect(sinkNameForOutput("Loopwire", streamConfiguration, streamConfiguration.outputs[0])).toBe(
      "loopwire_stream_deck_main_out"
    );
    expect(sinkNameForMonitor("Loopwire", monitoredConfiguration, monitoredConfiguration.monitors?.[0] ?? neverEndpoint())).toBe(
      "loopwire_monitored_mix_monitor_headphones"
    );
  });

  it("dry-runs apply and verify without mutating the host", async () => {
    const { runner, calls } = createRecordingRunner({});
    const adapter = createPactlVirtualSinkRuntimeAdapter(runner);

    const apply = await adapter.apply(streamConfiguration);
    const verify = await adapter.verify(streamConfiguration);

    expect(apply).toMatchObject({ ok: true });
    expect(verify).toMatchObject({ ok: true });
    expect(calls).toEqual([]);
    expect(adapter.commandLog.map((entry) => [entry.operation, entry.args.join(" "), entry.skipped])).toEqual([
      ["unload", "list short modules", true],
      ["apply", expectedLoadArgs("main_out", "main_output"), true],
      ["apply", expectedLoadArgs("monitor_out", "monitor_output"), true],
      ["verify", "list short sinks", true]
    ]);
  });

  it("rolls back modules that loaded before an apply failure", async () => {
    const firstLoad = [
      "pactl",
      "load-module",
      "module-null-sink",
      "sink_name=loopwire_stream_deck_main_out",
      "channels=2",
      "sink_properties=device.description=loopwire_stream_mix_main_output"
    ].join(" ");
    const secondLoad = [
      "pactl",
      "load-module",
      "module-null-sink",
      "sink_name=loopwire_stream_deck_monitor_out",
      "channels=2",
      "sink_properties=device.description=loopwire_stream_mix_monitor_output"
    ].join(" ");
    const { runner, calls } = createRecordingRunner({
      "pactl list short modules": { stdout: "" },
      [firstLoad]: { stdout: "42\n" },
      [secondLoad]: { exitCode: 1, stderr: "sink create failed\n" },
      "pactl unload-module 42": { stdout: "" }
    });
    const adapter = createPactlVirtualSinkRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply(streamConfiguration);

    expect(result).toMatchObject({
      ok: false,
      message: "Could not create virtual sink for Monitor Output: sink create failed"
    });
    expect(calls).toEqual(["pactl list short modules", firstLoad, secondLoad, "pactl unload-module 42"]);
  });

  it("fails verification when an expected virtual sink is missing", async () => {
    const { runner } = createRecordingRunner({
      "pactl list short sinks": {
        stdout: "1\tloopwire_stream_deck_main_out\tPipeWire\tfloat32le 2ch 48000Hz\tRUNNING\n"
      }
    });
    const adapter = createPactlVirtualSinkRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.verify(streamConfiguration);

    expect(result).toEqual({
      ok: false,
      message: "Missing Loopwire virtual sink(s): loopwire_stream_deck_monitor_out"
    });
  });

  it("moves matching sink inputs to their Loopwire virtual sink", async () => {
    const load = expectedPactlLoad("routed_mix", "program", "program");
    const { runner, calls } = createRecordingRunner({
      "pactl list short modules": { stdout: "" },
      [load]: { stdout: "42\n" },
      "pactl list sink-inputs": {
        stdout: [
          sinkInputBlock("77", "old_sink", { "application.name": "Firefox" }),
          sinkInputBlock("88", "chat_sink", { "application.name": "Discord" })
        ].join("\n")
      },
      "pactl move-sink-input 77 loopwire_routed_mix_program": { stdout: "" },
      "pactl set-sink-input-volume 77 42%": { stdout: "" },
      "pactl set-sink-input-mute 77 0": { stdout: "" },
      "pactl move-sink-input 88 loopwire_routed_mix_program": { stdout: "" },
      "pactl set-sink-input-volume 88 25%": { stdout: "" },
      "pactl set-sink-input-mute 88 1": { stdout: "" }
    });
    const adapter = createPactlVirtualSinkRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply(routedConfiguration);

    expect(result).toEqual({
      ok: true,
      message: "Created 1 virtual sink(s); Applied 2 matching sink input route(s)"
    });
    expect(calls).toEqual([
      "pactl list short modules",
      load,
      "pactl list sink-inputs",
      "pactl move-sink-input 77 loopwire_routed_mix_program",
      "pactl set-sink-input-volume 77 42%",
      "pactl set-sink-input-mute 77 0",
      "pactl move-sink-input 88 loopwire_routed_mix_program",
      "pactl set-sink-input-volume 88 25%",
      "pactl set-sink-input-mute 88 1"
    ]);
  });

  it("refreshes matching sink input routes without recreating virtual sinks", async () => {
    const { runner, calls } = createRecordingRunner({
      "pactl list sink-inputs": {
        stdout: sinkInputBlock("77", "old_sink", { "application.name": "Firefox" })
      },
      "pactl move-sink-input 77 loopwire_routed_mix_program": { stdout: "" },
      "pactl set-sink-input-volume 77 42%": { stdout: "" },
      "pactl set-sink-input-mute 77 0": { stdout: "" }
    });
    const adapter = createPactlVirtualSinkRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.refreshRoutes(routedConfiguration);

    expect(result).toEqual({
      ok: true,
      message: "Applied 1 matching sink input route(s)"
    });
    expect(calls).toEqual([
      "pactl list sink-inputs",
      "pactl move-sink-input 77 loopwire_routed_mix_program",
      "pactl set-sink-input-volume 77 42%",
      "pactl set-sink-input-mute 77 0"
    ]);
  });

  it("matches discovered source device names when routing sink inputs", async () => {
    const discoveredConfiguration: HostRuntimeConfiguration = {
      id: "Discovered Mix",
      name: "Discovered Mix",
      inputs: [{ id: "call-audio-77", label: "Call Audio", channels: 2, deviceName: "firefox" }],
      outputs: [{ id: "Program", label: "Program", channels: 2 }],
      routes: [{ id: "call-program", from: "call-audio-77", to: "Program", gain: 0.5, muted: false }]
    };
    const load = expectedPactlLoadWithName("discovered_mix", "program", "program", "discovered_mix");
    const { runner, calls } = createRecordingRunner({
      "pactl list short modules": { stdout: "" },
      [load]: { stdout: "42\n" },
      "pactl list sink-inputs": {
        stdout: sinkInputBlock("77", "old_sink", { "application.process.binary": "firefox", "application.name": "Firefox" })
      },
      "pactl move-sink-input 77 loopwire_discovered_mix_program": { stdout: "" },
      "pactl set-sink-input-volume 77 50%": { stdout: "" },
      "pactl set-sink-input-mute 77 0": { stdout: "" }
    });
    const adapter = createPactlVirtualSinkRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply(discoveredConfiguration);

    expect(result).toEqual({
      ok: true,
      message: "Created 1 virtual sink(s); Applied 1 matching sink input route(s)"
    });
    expect(calls).toEqual([
      "pactl list short modules",
      load,
      "pactl list sink-inputs",
      "pactl move-sink-input 77 loopwire_discovered_mix_program",
      "pactl set-sink-input-volume 77 50%",
      "pactl set-sink-input-mute 77 0"
    ]);
  });

  it("rejects PulseAudio routes that fan one source out to multiple outputs", async () => {
    const duplicateSourceConfiguration: HostRuntimeConfiguration = {
      ...routedConfiguration,
      outputs: [
        ...(routedConfiguration.outputs ?? []),
        { id: "Monitor", label: "Monitor", channels: 2 }
      ],
      routes: [
        ...(routedConfiguration.routes ?? []),
        { id: "firefox-monitor", from: "firefox", to: "Monitor", gain: 0.8, muted: false }
      ]
    };
    const { runner, calls } = createRecordingRunner({});
    const adapter = createPactlVirtualSinkRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply(duplicateSourceConfiguration);
    const refreshed = await adapter.refreshRoutes(duplicateSourceConfiguration);
    const verified = await adapter.verify(duplicateSourceConfiguration);

    expect(result).toEqual({
      ok: false,
      message:
        "PulseAudio compatibility cannot route one source to multiple outputs: Firefox uses routes firefox-program, firefox-monitor"
    });
    expect(refreshed).toEqual(result);
    expect(verified).toEqual(result);
    expect(calls).toEqual([]);
  });

  it("creates monitor sinks and loopbacks for configured monitors", async () => {
    const outputLoad = expectedPactlLoadWithName("monitored_mix", "program", "program", "monitored_mix");
    const headphonesLoad = expectedMonitorLoad("monitored_mix", "headphones", "headphones");
    const metersLoad = expectedMonitorLoad("monitored_mix", "meters", "meter_bridge");
    const headphonesLoopback = expectedLoopbackLoad(
      "loopwire_monitored_mix_program.monitor",
      "loopwire_monitored_mix_monitor_headphones"
    );
    const metersLoopback = expectedLoopbackLoad(
      "loopwire_monitored_mix_program.monitor",
      "loopwire_monitored_mix_monitor_meters"
    );
    const { runner, calls } = createRecordingRunner({
      "pactl list short modules": { stdout: "" },
      [outputLoad]: { stdout: "42\n" },
      [headphonesLoad]: { stdout: "43\n" },
      [metersLoad]: { stdout: "44\n" },
      [headphonesLoopback]: { stdout: "45\n" },
      [metersLoopback]: { stdout: "46\n" }
    });
    const adapter = createPactlVirtualSinkRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply(monitoredConfiguration);

    expect(result).toEqual({
      ok: true,
      message: "Created 1 virtual sink(s); Created 2 monitor sink(s); Linked 2 monitor loopback(s)"
    });
    expect(calls).toEqual([
      "pactl list short modules",
      outputLoad,
      headphonesLoad,
      metersLoad,
      headphonesLoopback,
      metersLoopback
    ]);
  });

  it("links output monitor sources directly to configured physical monitor sinks", async () => {
    const outputLoad = expectedPactlLoadWithName("physical_monitor_mix", "program", "program", "physical_monitor_mix");
    const monitorLoopback = expectedLoopbackLoad("loopwire_physical_monitor_mix_program.monitor", "alsa_output.usb_headphones");
    const { runner, calls } = createRecordingRunner({
      "pactl list short modules": { stdout: "" },
      [outputLoad]: { stdout: "42\n" },
      [monitorLoopback]: { stdout: "45\n" }
    });
    const adapter = createPactlVirtualSinkRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply(physicalMonitorConfiguration);

    expect(result).toEqual({
      ok: true,
      message: "Created 1 virtual sink(s); Created 0 monitor sink(s); Linked 1 monitor loopback(s)"
    });
    expect(calls).toEqual(["pactl list short modules", outputLoad, monitorLoopback]);
  });

  it("unloads created sinks when monitor loopback creation fails", async () => {
    const oneMonitorConfiguration: HostRuntimeConfiguration = {
      ...monitoredConfiguration,
      monitors: [{ id: "Headphones", label: "Headphones", channels: 2 }]
    };
    const outputLoad = expectedPactlLoadWithName("monitored_mix", "program", "program", "monitored_mix");
    const headphonesLoad = expectedMonitorLoad("monitored_mix", "headphones", "headphones");
    const headphonesLoopback = expectedLoopbackLoad(
      "loopwire_monitored_mix_program.monitor",
      "loopwire_monitored_mix_monitor_headphones"
    );
    const { runner, calls } = createRecordingRunner({
      "pactl list short modules": { stdout: "" },
      [outputLoad]: { stdout: "42\n" },
      [headphonesLoad]: { stdout: "43\n" },
      [headphonesLoopback]: { exitCode: 1, stderr: "loopback failed\n" },
      "pactl unload-module 42": { stdout: "" },
      "pactl unload-module 43": { stdout: "" }
    });
    const adapter = createPactlVirtualSinkRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply(oneMonitorConfiguration);

    expect(result).toEqual({
      ok: false,
      message: "Could not link monitor loopwire_monitored_mix_program.monitor -> loopwire_monitored_mix_monitor_headphones: loopback failed"
    });
    expect(calls).toEqual([
      "pactl list short modules",
      outputLoad,
      headphonesLoad,
      headphonesLoopback,
      "pactl unload-module 42",
      "pactl unload-module 43"
    ]);
  });

  it("moves already-routed sink inputs back when a later move fails", async () => {
    const routedFailureConfiguration: HostRuntimeConfiguration = {
      ...routedConfiguration,
      inputs: [
        ...(routedConfiguration.inputs ?? []),
        { id: "spotify", label: "Spotify", channels: 2 }
      ],
      routes: [
        ...(routedConfiguration.routes ?? []),
        { id: "spotify-program", from: "spotify", to: "Program", gain: 0.35, muted: false }
      ]
    };
    const load = expectedPactlLoad("routed_mix", "program", "program");
    const { runner, calls } = createRecordingRunner({
      "pactl list short modules": { stdout: "" },
      [load]: { stdout: "42\n" },
      "pactl list sink-inputs": {
        stdout: [
          sinkInputBlock("77", "old_firefox", { "application.name": "Firefox" }),
          sinkInputBlock("88", "old_spotify", { "application.name": "Spotify" })
        ].join("\n")
      },
      "pactl move-sink-input 77 loopwire_routed_mix_program": { stdout: "" },
      "pactl set-sink-input-volume 77 42%": { stdout: "" },
      "pactl set-sink-input-mute 77 0": { stdout: "" },
      "pactl move-sink-input 88 loopwire_routed_mix_program": { exitCode: 1, stderr: "move failed\n" },
      "pactl set-sink-input-mute 77 0": { stdout: "" },
      "pactl set-sink-input-volume 77 100%": { stdout: "" },
      "pactl move-sink-input 77 old_firefox": { stdout: "" },
      "pactl unload-module 42": { stdout: "" }
    });
    const adapter = createPactlVirtualSinkRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.apply(routedFailureConfiguration);

    expect(result).toEqual({
      ok: false,
      message: "Could not move sink input 88 to loopwire_routed_mix_program: move failed"
    });
    expect(calls).toEqual([
      "pactl list short modules",
      load,
      "pactl list sink-inputs",
      "pactl move-sink-input 77 loopwire_routed_mix_program",
      "pactl set-sink-input-volume 77 42%",
      "pactl set-sink-input-mute 77 0",
      "pactl move-sink-input 88 loopwire_routed_mix_program",
      "pactl set-sink-input-mute 77 0",
      "pactl set-sink-input-volume 77 100%",
      "pactl move-sink-input 77 old_firefox",
      "pactl unload-module 42"
    ]);
  });

  it("fails verification when a matching stream is on the wrong sink", async () => {
    const { runner } = createRecordingRunner({
      "pactl list short sinks": {
        stdout: "1\tloopwire_routed_mix_program\tPipeWire\tfloat32le 2ch 48000Hz\tRUNNING\n"
      },
      "pactl list sink-inputs": {
        stdout: [
          sinkInputBlock("77", "old_sink", { "application.name": "Firefox" }, 42, false),
          sinkInputBlock("88", "loopwire_routed_mix_program", { "application.name": "Discord" }, 25, true)
        ].join("\n")
      }
    });
    const adapter = createPactlVirtualSinkRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.verify(routedConfiguration);

    expect(result).toEqual({
      ok: false,
      message: "Misrouted Loopwire sink input(s): 77->old_sink expected loopwire_routed_mix_program"
    });
  });

  it("fails verification when a configured route has no matching live stream", async () => {
    const { runner } = createRecordingRunner({
      "pactl list short sinks": {
        stdout: "1\tloopwire_routed_mix_program\tPipeWire\tfloat32le 2ch 48000Hz\tRUNNING\n"
      },
      "pactl list sink-inputs": {
        stdout: sinkInputBlock("77", "loopwire_routed_mix_program", { "application.name": "Spotify" })
      }
    });
    const adapter = createPactlVirtualSinkRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.verify(routedConfiguration);

    expect(result).toEqual({
      ok: false,
      message: "Missing matching PulseAudio stream(s) for route(s): firefox-program, discord-program"
    });
  });

  it("allows startup verification to keep absent matching streams pending", async () => {
    const { runner } = createRecordingRunner({
      "pactl list short sinks": {
        stdout: "1\tloopwire_routed_mix_program\tPipeWire\tfloat32le 2ch 48000Hz\tRUNNING\n"
      },
      "pactl list sink-inputs": {
        stdout: sinkInputBlock("77", "loopwire_routed_mix_program", { "application.name": "Spotify" })
      }
    });
    const adapter = createPactlVirtualSinkRuntimeAdapter(runner, {
      mode: "apply",
      missingStreamVerification: "pending"
    });

    const result = await adapter.verify(routedConfiguration);

    expect(result).toEqual({
      ok: true,
      message: "Pending matching PulseAudio stream(s) for route(s): firefox-program, discord-program"
    });
  });

  it("fails verification when route gain or mute does not match host state", async () => {
    const { runner } = createRecordingRunner({
      "pactl list short sinks": {
        stdout: "1\tloopwire_routed_mix_program\tPipeWire\tfloat32le 2ch 48000Hz\tRUNNING\n"
      },
      "pactl list sink-inputs": {
        stdout: [
          sinkInputBlock("77", "loopwire_routed_mix_program", { "application.name": "Firefox" }, 100, true),
          sinkInputBlock("88", "loopwire_routed_mix_program", { "application.name": "Discord" }, 25, true)
        ].join("\n")
      }
    });
    const adapter = createPactlVirtualSinkRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.verify(routedConfiguration);

    expect(result).toEqual({
      ok: false,
      message: "Misconfigured Loopwire sink input(s): 77 volume 100% expected 42%, 77 mute yes expected no"
    });
  });

  it("fails verification when a configured monitor loopback is missing", async () => {
    const { runner } = createRecordingRunner({
      "pactl list short sinks": {
        stdout: [
          "1\tloopwire_monitored_mix_program\tPipeWire\tfloat32le 2ch 48000Hz\tRUNNING",
          "2\tloopwire_monitored_mix_monitor_headphones\tPipeWire\tfloat32le 2ch 48000Hz\tRUNNING",
          "3\tloopwire_monitored_mix_monitor_meters\tPipeWire\tfloat32le 2ch 48000Hz\tRUNNING"
        ].join("\n")
      },
      "pactl list short modules": {
        stdout: [
          "45\tmodule-loopback\tsource=loopwire_monitored_mix_program.monitor sink=loopwire_monitored_mix_monitor_headphones"
        ].join("\n")
      }
    });
    const adapter = createPactlVirtualSinkRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.verify(monitoredConfiguration);

    expect(result).toEqual({
      ok: false,
      message:
        "Missing Loopwire monitor loopback(s): loopwire_monitored_mix_program.monitor -> loopwire_monitored_mix_monitor_meters"
    });
  });

  it("fails verification when a physical monitor target sink is missing", async () => {
    const { runner, calls } = createRecordingRunner({
      "pactl list short sinks": {
        stdout: "1\tloopwire_physical_monitor_mix_program\tPipeWire\tfloat32le 2ch 48000Hz\tRUNNING\n"
      }
    });
    const adapter = createPactlVirtualSinkRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.verify(physicalMonitorConfiguration);

    expect(result).toEqual({
      ok: false,
      message: "Missing monitor target sink(s): alsa_output.usb_headphones"
    });
    expect(calls).toEqual(["pactl list short sinks"]);
  });

  it("unloads only modules matching the configuration sinks", async () => {
    const { runner, calls } = createRecordingRunner({
      "pactl list short modules": {
        stdout: [
          "41\tmodule-null-sink\tsink_name=other_app_sink",
          "42\tmodule-null-sink\tsink_name=loopwire_stream_deck_main_out channels=2",
          "43\tmodule-null-sink\tsink_name=loopwire_stream_deck_monitor_out channels=2"
        ].join("\n")
      },
      "pactl unload-module 42": { stdout: "" },
      "pactl unload-module 43": { stdout: "" }
    });
    const adapter = createPactlVirtualSinkRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.rollback(streamConfiguration);

    expect(result).toMatchObject({ ok: true });
    expect(calls).toEqual(["pactl list short modules", "pactl unload-module 42", "pactl unload-module 43"]);
  });

  it("unloads physical-monitor loopbacks without unloading physical sinks", async () => {
    const { runner, calls } = createRecordingRunner({
      "pactl list short modules": {
        stdout: [
          "42\tmodule-null-sink\tsink_name=loopwire_physical_monitor_mix_program channels=2",
          "45\tmodule-loopback\tsource=loopwire_physical_monitor_mix_program.monitor sink=alsa_output.usb_headphones",
          "46\tmodule-loopback\tsource=other.monitor sink=alsa_output.usb_headphones"
        ].join("\n")
      },
      "pactl unload-module 42": { stdout: "" },
      "pactl unload-module 45": { stdout: "" }
    });
    const adapter = createPactlVirtualSinkRuntimeAdapter(runner, { mode: "apply" });

    const result = await adapter.rollback(physicalMonitorConfiguration);

    expect(result).toMatchObject({ ok: true });
    expect(calls).toEqual(["pactl list short modules", "pactl unload-module 42", "pactl unload-module 45"]);
  });
});

function expectedLoadArgs(outputId: string, outputLabel: string): string {
  return [
    "load-module",
    "module-null-sink",
    `sink_name=loopwire_stream_deck_${outputId}`,
    "channels=2",
    `sink_properties=device.description=loopwire_stream_mix_${outputLabel}`
  ].join(" ");
}

function expectedPactlLoad(configurationId: string, outputId: string, outputLabel: string): string {
  return expectedPactlLoadWithName(configurationId, outputId, outputLabel, "routed_mix");
}

function expectedPactlLoadWithName(
  configurationId: string,
  outputId: string,
  outputLabel: string,
  configurationName: string
): string {
  return [
    "pactl",
    "load-module",
    "module-null-sink",
    `sink_name=loopwire_${configurationId}_${outputId}`,
    "channels=2",
    `sink_properties=device.description=loopwire_${configurationName}_${outputLabel}`
  ].join(" ");
}

function expectedMonitorLoad(configurationId: string, monitorId: string, monitorLabel: string): string {
  return [
    "pactl",
    "load-module",
    "module-null-sink",
    `sink_name=loopwire_${configurationId}_monitor_${monitorId}`,
    "channels=2",
    `sink_properties=device.description=loopwire_monitored_mix_${monitorLabel}`
  ].join(" ");
}

function expectedLoopbackLoad(sourceName: string, targetSinkName: string): string {
  return ["pactl", "load-module", "module-loopback", `source=${sourceName}`, `sink=${targetSinkName}`, "latency_msec=20"].join(
    " "
  );
}

function neverEndpoint(): never {
  throw new Error("Expected monitored configuration to include a monitor.");
}

function sinkInputBlock(
  id: string,
  sinkName: string,
  properties: Record<string, string>,
  volumePercent = 100,
  muted = false
): string {
  const propertyLines = Object.entries(properties)
    .map(([key, value]) => `    ${key} = "${value}"`)
    .join("\n");

  return [
    `Sink Input #${id}`,
    `    Sink: ${sinkName}`,
    `    Volume: front-left: 65536 / ${volumePercent}% / 0.00 dB`,
    `    Mute: ${muted ? "yes" : "no"}`,
    "    Properties:",
    propertyLines
  ].join("\n");
}
