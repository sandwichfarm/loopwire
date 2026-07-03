import { describe, expect, it } from "vitest";
import { detectAudioBackends, enumerateInputSources, enumeratePlaybackDevices, toBackendCandidates } from "../src/index.js";
import { createFakeRunner } from "./fake-runner.js";

describe("detectAudioBackends", () => {
  it("detects PipeWire and PulseAudio compatibility with truthful routing gaps", async () => {
    const report = await detectAudioBackends(
      createFakeRunner({
        "pw-cli --version": { stdout: "pw-cli 1.4.9\n" },
        "wpctl status": { stdout: "PipeWire 'pipewire-0' [1.4.9, host, cookie:1]\n" },
        "pactl info": { stdout: "Server Name: PulseAudio (on PipeWire 1.4.9)\nServer Version: 15.0.0\n" },
        jack_lsp: { exitCode: 1, stderr: "Cannot connect to server\n" },
        "aplay -l": { stdout: "card 0: PCH [HDA Intel PCH], device 0: ALC [ALC]\n" }
      }),
      new Date("2026-07-03T12:00:00.000Z"),
      "linux"
    );

    expect(report.generatedAt).toBe("2026-07-03T12:00:00.000Z");
    expect(report.platform).toBe("linux");
    expect(report.reports.find((item) => item.kind === "pipewire")).toMatchObject({
      availability: "available",
      version: "1.4.9",
      operations: {
        detect: "implemented",
        createVirtualDevice: "implemented",
        monitorAudio: "implemented",
        routeAudio: "implemented",
        rollback: "implemented"
      },
      mixing: {
        controlScope: "link-only",
        supportsPerEdgeGain: false,
        supportsPerEdgeMute: true
      },
      gaps: ["per-edge gain controls"]
    });
    expect(report.reports.find((item) => item.kind === "pulseaudio")).toMatchObject({
      displayName: "PulseAudio Compatibility",
      availability: "available",
      serverName: "PulseAudio (on PipeWire 1.4.9)",
      operations: {
        createVirtualDevice: "implemented",
        routeAudio: "implemented",
        monitorAudio: "implemented",
        rollback: "implemented"
      },
      mixing: {
        controlScope: "stream",
        supportsPerEdgeGain: false,
        supportsPerEdgeMute: false
      },
      gaps: ["true per-edge mixing beyond sink-input controls"]
    });
    expect(report.reports.find((item) => item.kind === "jack")).toMatchObject({
      availability: "unavailable"
    });
    expect(report.reports.find((item) => item.kind === "alsa")).toMatchObject({
      availability: "available"
    });
  });

  it("uses pw-cli info fallback when wpctl is missing", async () => {
    const report = await detectAudioBackends(
      createFakeRunner({
        "pw-cli --version": { stdout: "pw-cli\nCompiled with libpipewire 1.2.0\n" },
        "wpctl status": { exitCode: 127, stderr: "wpctl: command not found", errorCode: "missing" },
        "pw-cli info 0": { stdout: "id: 0\npermissions: rwxm\n" }
      }),
      new Date("2026-07-03T12:00:00.000Z")
    );

    expect(report.reports.find((item) => item.kind === "pipewire")).toMatchObject({
      availability: "available",
      version: "1.2.0"
    });
  });

  it("reports JACK existing-port routing as implemented when jack_lsp succeeds", async () => {
    const report = await detectAudioBackends(
      createFakeRunner({
        jack_lsp: { stdout: "system:capture_1\nsystem:playback_1\n" }
      }),
      new Date("2026-07-03T12:00:00.000Z")
    );

    expect(report.reports.find((item) => item.kind === "jack")).toMatchObject({
      availability: "available",
      operations: {
        enumerateDevices: "implemented",
        createVirtualDevice: "planned",
        routeAudio: "implemented",
        monitorAudio: "implemented",
        apply: "implemented",
        verify: "implemented",
        rollback: "implemented"
      },
      mixing: {
        controlScope: "link-only",
        supportsPerEdgeGain: false,
        supportsPerEdgeMute: true
      },
      gaps: ["virtual device creation", "virtual monitor sink creation", "per-edge gain controls"]
    });
  });

  it("reports every backend as unavailable when commands are missing", async () => {
    const report = await detectAudioBackends(createFakeRunner({}), new Date("2026-07-03T12:00:00.000Z"));

    expect(report.reports).toHaveLength(4);
    expect(report.reports.every((item) => item.availability === "unavailable")).toBe(true);
    expect(report.candidates.every((item) => item.availability === "unavailable")).toBe(true);
    expect(report.candidates.map((item) => item.reason).every(Boolean)).toBe(true);
  });

  it("redacts local identity details from command summaries", async () => {
    const report = await detectAudioBackends(
      createFakeRunner({
        "pw-cli --version": { stdout: "pw-cli\n" },
        "wpctl status": { stdout: "PipeWire 'pipewire-0' [1.6.7, alice@studio, cookie:123]\n" },
        "pactl info": { stdout: "Server String: /run/user/1000/pulse/native\nServer Name: PulseAudio\n" }
      }),
      new Date("2026-07-03T12:00:00.000Z")
    );

    expect(report.reports.find((item) => item.kind === "pipewire")?.commands[1]?.summary).toContain("<user@host>");
    expect(report.reports.find((item) => item.kind === "pipewire")?.commands[1]?.summary).toContain("cookie:<redacted>");
    expect(report.reports.find((item) => item.kind === "pulseaudio")?.commands[0]?.summary).toBe(
      "Server String: /run/user/<uid>/pulse/native"
    );
  });
});

describe("enumeratePlaybackDevices", () => {
  it("lists PipeWire input ports as monitor target device candidates", async () => {
    const report = await enumeratePlaybackDevices(
      createFakeRunner({
        "pw-link -i": {
          stdout: [
            "alsa_output.usb.Focusrite_Scarlett.analog-stereo:playback_FL",
            "alsa_output.usb.Focusrite_Scarlett.analog-stereo:playback_FR",
            "bluez_output.00_11_22_33_44_55.a2dp-sink:playback_FL"
          ].join("\n")
        }
      }),
      "pipewire",
      new Date("2026-07-03T12:05:00.000Z")
    );

    expect(report.generatedAt).toBe("2026-07-03T12:05:00.000Z");
    expect(report.backend).toBe("pipewire");
    expect(report.devices).toEqual([
      {
        backend: "pipewire",
        deviceName: "alsa_output.usb.Focusrite_Scarlett.analog-stereo",
        label: "usb Focusrite Scarlett analog stereo",
        detail: "2 input port(s)"
      },
      {
        backend: "pipewire",
        deviceName: "bluez_output.00_11_22_33_44_55.a2dp-sink",
        label: "00 11 22 33 44 55 a2dp sink",
        detail: "1 input port(s)"
      }
    ]);
    expect(report.diagnostics[0]).toMatchObject({ level: "info", code: "PLAYBACK_DEVICES_AVAILABLE" });
    expect(report.commands[0]).toMatchObject({ command: "pw-link", args: ["-i"], available: true });
  });

  it("lists PulseAudio playback sinks as monitor target candidates", async () => {
    const report = await enumeratePlaybackDevices(
      createFakeRunner({
        "pactl list short sinks": {
          stdout: [
            "47\talsa_output.usb.Focusrite_Scarlett.analog-stereo\tPipeWire\ts32le 2ch 48000Hz\tRUNNING",
            "55\tbluez_output.00_11_22_33_44_55.a2dp-sink\tPipeWire\ts16le 2ch 44100Hz\tIDLE"
          ].join("\n")
        }
      }),
      "pulseaudio",
      new Date("2026-07-03T12:10:00.000Z")
    );

    expect(report.generatedAt).toBe("2026-07-03T12:10:00.000Z");
    expect(report.backend).toBe("pulseaudio");
    expect(report.devices).toEqual([
      {
        backend: "pulseaudio",
        deviceName: "alsa_output.usb.Focusrite_Scarlett.analog-stereo",
        label: "usb Focusrite Scarlett analog stereo",
        detail: "RUNNING - s32le 2ch 48000Hz"
      },
      {
        backend: "pulseaudio",
        deviceName: "bluez_output.00_11_22_33_44_55.a2dp-sink",
        label: "00 11 22 33 44 55 a2dp sink",
        detail: "IDLE - s16le 2ch 44100Hz"
      }
    ]);
    expect(report.diagnostics[0]).toMatchObject({ level: "info", code: "PLAYBACK_DEVICES_AVAILABLE" });
    expect(report.commands[0]).toMatchObject({ command: "pactl", args: ["list", "short", "sinks"], available: true });
  });

  it("lists JACK input ports as monitor target candidates", async () => {
    const report = await enumeratePlaybackDevices(
      createFakeRunner({
        "jack_lsp -p": {
          stdout: [
            "system:playback_1",
            "    properties: input, physical, terminal,",
            "system:playback_2",
            "    properties: input, physical, terminal,",
            "ardour:master/audio_out 1",
            "    properties: output,",
            "loopwire_program:monitor_1",
            "    properties: output,"
          ].join("\n")
        }
      }),
      "jack",
      new Date("2026-07-03T12:12:00.000Z")
    );

    expect(report.generatedAt).toBe("2026-07-03T12:12:00.000Z");
    expect(report.backend).toBe("jack");
    expect(report.devices).toEqual([
      {
        backend: "jack",
        deviceName: "system",
        label: "system",
        detail: "2 input port(s)"
      }
    ]);
    expect(report.diagnostics[0]).toMatchObject({ level: "info", code: "PLAYBACK_DEVICES_AVAILABLE" });
    expect(report.commands[0]).toMatchObject({ command: "jack_lsp", args: ["-p"], available: true });
  });

  it("reports PulseAudio sink enumeration failure without throwing", async () => {
    const report = await enumeratePlaybackDevices(
      createFakeRunner({
        "pactl list short sinks": { exitCode: 1, stderr: "connection refused\n" }
      }),
      "pulseaudio",
      new Date("2026-07-03T12:15:00.000Z")
    );

    expect(report.devices).toEqual([]);
    expect(report.diagnostics[0]).toMatchObject({
      level: "warning",
      code: "PLAYBACK_ENUMERATION_FAILED",
      message: "Could not list PulseAudio sinks. Probe result: connection refused."
    });
  });

  it("reports PipeWire input-port enumeration failure without throwing", async () => {
    const report = await enumeratePlaybackDevices(
      createFakeRunner({
        "pw-link -i": { exitCode: 1, stderr: "no graph\n" }
      }),
      "pipewire",
      new Date("2026-07-03T12:20:00.000Z")
    );

    expect(report.devices).toEqual([]);
    expect(report.diagnostics[0]).toMatchObject({
      level: "warning",
      code: "PLAYBACK_ENUMERATION_FAILED",
      message: "Could not list PipeWire input ports. Probe result: no graph."
    });
  });

  it("reports JACK playback-port enumeration failure without throwing", async () => {
    const report = await enumeratePlaybackDevices(
      createFakeRunner({
        "jack_lsp -p": { exitCode: 1, stderr: "Cannot connect to server\n" }
      }),
      "jack",
      new Date("2026-07-03T12:21:00.000Z")
    );

    expect(report.devices).toEqual([]);
    expect(report.diagnostics[0]).toMatchObject({
      level: "warning",
      code: "PLAYBACK_ENUMERATION_FAILED",
      message: "Could not list JACK ports. Probe result: Cannot connect to server."
    });
  });

  it("keeps unsupported backends in manual monitor-target mode", async () => {
    const report = await enumeratePlaybackDevices(
      createFakeRunner({
        "aplay -l": { stdout: "card 0: PCH [HDA Intel PCH], device 0: ALC [ALC]\n" }
      }),
      "alsa",
      new Date("2026-07-03T12:20:00.000Z")
    );

    expect(report.devices).toEqual([]);
    expect(report.commands).toEqual([]);
    expect(report.diagnostics[0]).toMatchObject({
      level: "warning",
      code: "PLAYBACK_ENUMERATION_MANUAL"
    });
  });
});

describe("enumerateInputSources", () => {
  it("lists PipeWire output ports as source candidates", async () => {
    const report = await enumerateInputSources(
      createFakeRunner({
        "pw-link -o": {
          stdout: [
            "alsa_input.usb.Focusrite_Scarlett.analog-stereo:capture_FL",
            "alsa_input.usb.Focusrite_Scarlett.analog-stereo:capture_FR",
            "Firefox:output_FL"
          ].join("\n")
        }
      }),
      "pipewire",
      new Date("2026-07-03T12:22:00.000Z")
    );

    expect(report.generatedAt).toBe("2026-07-03T12:22:00.000Z");
    expect(report.backend).toBe("pipewire");
    expect(report.sources).toEqual([
      {
        backend: "pipewire",
        sourceId: "alsa-input-usb-focusrite-scarlett-analog-stereo",
        sourceName: "alsa_input.usb.Focusrite_Scarlett.analog-stereo",
        label: "usb Focusrite Scarlett analog stereo",
        detail: "2 output port(s)",
        channels: 2
      },
      {
        backend: "pipewire",
        sourceId: "firefox",
        sourceName: "Firefox",
        label: "Firefox",
        detail: "1 output port(s)",
        channels: 1
      }
    ]);
    expect(report.diagnostics[0]).toMatchObject({ level: "info", code: "INPUT_SOURCES_AVAILABLE" });
    expect(report.commands[0]).toMatchObject({ command: "pw-link", args: ["-o"], available: true });
  });

  it("lists PulseAudio sink inputs as source candidates", async () => {
    const report = await enumerateInputSources(
      createFakeRunner({
        "pactl list sink-inputs": {
          stdout: [
            "Sink Input #77",
            "    Sink: 32",
            "    Sample Specification: float32le 2ch 48000Hz",
            "    Properties:",
            "        application.name = \"Firefox\"",
            "        media.name = \"AudioStream\"",
            "        application.process.binary = \"firefox\"",
            "",
            "Sink Input #82",
            "    Sink: 47",
            "    Sample Specification: s16le 1ch 48000Hz",
            "    Properties:",
            "        application.name = \"Meeting App\"",
            "        media.name = \"Call Audio\"",
            "        application.process.binary = \"meeting-app\""
          ].join("\n")
        }
      }),
      "pulseaudio",
      new Date("2026-07-03T12:25:00.000Z")
    );

    expect(report.generatedAt).toBe("2026-07-03T12:25:00.000Z");
    expect(report.backend).toBe("pulseaudio");
    expect(report.sources).toEqual([
      {
        backend: "pulseaudio",
        sourceId: "firefox-77",
        sourceName: "firefox",
        label: "Firefox",
        detail: "AudioStream - Sink 32",
        channels: 2
      },
      {
        backend: "pulseaudio",
        sourceId: "meeting-app-82",
        sourceName: "meeting-app",
        label: "Meeting App",
        detail: "Call Audio - meeting-app - Sink 47",
        channels: 1
      }
    ]);
    expect(report.diagnostics[0]).toMatchObject({ level: "info", code: "INPUT_SOURCES_AVAILABLE" });
    expect(report.commands[0]).toMatchObject({ command: "pactl", args: ["list", "sink-inputs"], available: true });
  });

  it("lists JACK output ports as source candidates", async () => {
    const report = await enumerateInputSources(
      createFakeRunner({
        "jack_lsp -p": {
          stdout: [
            "system:capture_1",
            "    properties: output, physical, terminal,",
            "system:capture_2",
            "    properties: output, physical, terminal,",
            "ardour:master/audio_out 1",
            "    properties: output,",
            "system:playback_1",
            "    properties: input, physical, terminal,"
          ].join("\n")
        }
      }),
      "jack",
      new Date("2026-07-03T12:27:00.000Z")
    );

    expect(report.generatedAt).toBe("2026-07-03T12:27:00.000Z");
    expect(report.backend).toBe("jack");
    expect(report.sources).toEqual([
      {
        backend: "jack",
        sourceId: "system",
        sourceName: "system",
        label: "system",
        detail: "2 output port(s)",
        channels: 2
      },
      {
        backend: "jack",
        sourceId: "ardour",
        sourceName: "ardour",
        label: "ardour",
        detail: "1 output port(s)",
        channels: 1
      }
    ]);
    expect(report.diagnostics[0]).toMatchObject({ level: "info", code: "INPUT_SOURCES_AVAILABLE" });
    expect(report.commands[0]).toMatchObject({ command: "jack_lsp", args: ["-p"], available: true });
  });

  it("reports PulseAudio stream enumeration failure without throwing", async () => {
    const report = await enumerateInputSources(
      createFakeRunner({
        "pactl list sink-inputs": { exitCode: 1, stderr: "connection refused\n" }
      }),
      "pulseaudio",
      new Date("2026-07-03T12:30:00.000Z")
    );

    expect(report.sources).toEqual([]);
    expect(report.diagnostics[0]).toMatchObject({
      level: "warning",
      code: "INPUT_SOURCE_ENUMERATION_FAILED",
      message: "Could not list PulseAudio streams. Probe result: connection refused."
    });
  });

  it("reports PipeWire output-port enumeration failure without throwing", async () => {
    const report = await enumerateInputSources(
      createFakeRunner({
        "pw-link -o": { exitCode: 1, stderr: "no graph\n" }
      }),
      "pipewire",
      new Date("2026-07-03T12:35:00.000Z")
    );

    expect(report.sources).toEqual([]);
    expect(report.diagnostics[0]).toMatchObject({
      level: "warning",
      code: "INPUT_SOURCE_ENUMERATION_FAILED",
      message: "Could not list PipeWire output ports. Probe result: no graph."
    });
  });

  it("reports JACK source-port enumeration failure without throwing", async () => {
    const report = await enumerateInputSources(
      createFakeRunner({
        "jack_lsp -p": { exitCode: 1, stderr: "Cannot connect to server\n" }
      }),
      "jack",
      new Date("2026-07-03T12:36:00.000Z")
    );

    expect(report.sources).toEqual([]);
    expect(report.diagnostics[0]).toMatchObject({
      level: "warning",
      code: "INPUT_SOURCE_ENUMERATION_FAILED",
      message: "Could not list JACK ports. Probe result: Cannot connect to server."
    });
  });

  it("keeps unsupported backends in static source mode", async () => {
    const report = await enumerateInputSources(
      createFakeRunner({
        "aplay -l": { stdout: "card 0: PCH [HDA Intel PCH], device 0: ALC [ALC]\n" }
      }),
      "alsa",
      new Date("2026-07-03T12:35:00.000Z")
    );

    expect(report.sources).toEqual([]);
    expect(report.commands).toEqual([]);
    expect(report.diagnostics[0]).toMatchObject({
      level: "warning",
      code: "INPUT_SOURCE_ENUMERATION_MANUAL"
    });
  });
});

describe("toBackendCandidates", () => {
  it("preserves selection priority and user-facing unavailable reasons", async () => {
    const report = await detectAudioBackends(
      createFakeRunner({
        "wpctl status": { stdout: "PipeWire\n" },
        "pw-cli --version": { stdout: "pw-cli 1.4.9\n" }
      }),
      new Date("2026-07-03T12:00:00.000Z")
    );

    expect(toBackendCandidates(report.reports).map((candidate) => candidate.kind)).toEqual([
      "pipewire",
      "pulseaudio",
      "jack",
      "alsa"
    ]);
    expect(toBackendCandidates(report.reports)[0]).toMatchObject({
      kind: "pipewire",
      availability: "available",
      priority: 10
    });
  });
});
