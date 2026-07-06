import { describe, expect, it } from "vitest";
import type { LoopwireConfiguration } from "@loopwire/core";
import type { LiveApplyBackendCapability } from "./live-apply-preflight";
import {
  createLiveApplyPreflightLog,
  describeConfigurationSwitchPreflight,
  describeLiveApplyPreflight,
  getNativeGainBlockerRoutes
} from "./live-apply-preflight";

const baseConfiguration: LoopwireConfiguration = {
  id: "studio",
  name: "Studio",
  description: "Test mix",
  updatedAt: "2026-07-04T00:00:00.000Z",
  inputs: [
    { id: "mic", role: "input", label: "Studio Mic", channels: 2, deviceName: "studio_mic" },
    { id: "call", role: "input", label: "Call Audio", channels: 2 }
  ],
  outputs: [
    { id: "program", role: "output", label: "Program", channels: 2, deviceName: "program_out" },
    { id: "stream", role: "output", label: "Stream", channels: 2 }
  ],
  monitors: [
    { id: "phones", role: "monitor", label: "Headphones", channels: 2, deviceName: "system" },
    { id: "booth", role: "monitor", label: "Booth", channels: 2 }
  ],
  routes: [
    { id: "mic-program", from: "mic", to: "program", gain: 1, muted: false },
    { id: "call-stream", from: "call", to: "stream", gain: 0.6, muted: false }
  ]
};

const graphEdgePipeWire: LiveApplyBackendCapability = {
  kind: "pipewire",
  displayName: "PipeWire DSP",
  operations: {
    createVirtualDevice: "implemented"
  },
  mixing: {
    controlScope: "graph-edge",
    supportsPerEdgeGain: true,
    supportsPerEdgeMute: true
  }
};

const graphEdgeJack: LiveApplyBackendCapability = {
  kind: "jack",
  displayName: "JACK DSP",
  operations: {
    createVirtualDevice: "implemented"
  },
  mixing: {
    controlScope: "graph-edge",
    supportsPerEdgeGain: true,
    supportsPerEdgeMute: true
  }
};

const graphEdgeDsp: LiveApplyBackendCapability = {
  kind: "dsp",
  displayName: "DSP Provider",
  mixing: {
    controlScope: "graph-edge",
    supportsPerEdgeGain: true,
    supportsPerEdgeMute: true
  }
};

const unavailablePulseAudio: LiveApplyBackendCapability = {
  kind: "pulseaudio",
  displayName: "PulseAudio",
  availability: "unavailable",
  operations: {
    createVirtualDevice: "implemented"
  },
  mixing: {
    controlScope: "stream",
    supportsPerEdgeGain: true,
    supportsPerEdgeMute: true
  },
  gaps: ["PulseAudio compatibility daemon is not reachable"],
  diagnostics: [
    {
      level: "warning",
      code: "pulseaudio.unavailable",
      message: "PulseAudio service is not reachable."
    }
  ]
};

describe("describeLiveApplyPreflight", () => {
  it("blocks live apply until a backend is selected", () => {
    expect(describeLiveApplyPreflight(baseConfiguration, undefined)).toEqual({
      ok: false,
      mode: "blocked",
      badge: "Blocked",
      message: "Choose a detected backend before arming live apply.",
      blockers: ["Choose a detected backend before arming live apply."]
    });
  });

  it("blocks the selected backend when current detection reports it unavailable", () => {
    expect(describeLiveApplyPreflight(baseConfiguration, "pulseaudio", undefined, unavailablePulseAudio)).toEqual({
      ok: false,
      mode: "blocked",
      badge: "Blocked",
      message: "PulseAudio is unavailable for live apply: PulseAudio service is not reachable.",
      blockers: ["PulseAudio is unavailable for live apply: PulseAudio service is not reachable."]
    });
  });

  it("allows PulseAudio because stream-level gain and mute are handled by the backend adapter", () => {
    expect(describeLiveApplyPreflight(baseConfiguration, "pulseaudio")).toEqual({
      ok: true,
      mode: "ready",
      badge: "Ready",
      message: "PulseAudio live apply is ready for Studio.",
      blockers: []
    });
  });

  it("blocks PulseAudio when one source is routed to multiple outputs", () => {
    const result = describeLiveApplyPreflight(
      {
        ...baseConfiguration,
        routes: [
          ...baseConfiguration.routes,
          { id: "mic-stream", from: "mic", to: "stream", gain: 0.8, muted: false }
        ]
      },
      "pulseaudio"
    );

    expect(result).toEqual({
      ok: false,
      mode: "blocked",
      badge: "Blocked",
      message: "PulseAudio compatibility can route each source to only one output; adjust Studio Mic -> Program and Studio Mic -> Stream.",
      blockers: [
        "PulseAudio compatibility can route each source to only one output; adjust Studio Mic -> Program and Studio Mic -> Stream."
      ]
    });
  });

  it("allows PulseAudio when saved fan-out routes are muted behind one active route", () => {
    const result = describeLiveApplyPreflight(
      {
        ...baseConfiguration,
        routes: [
          ...baseConfiguration.routes,
          { id: "mic-stream-muted", from: "mic", to: "stream", gain: 0.8, muted: true }
        ]
      },
      "pulseaudio"
    );

    expect(result).toEqual({
      ok: true,
      mode: "ready",
      badge: "Ready",
      message: "PulseAudio live apply is ready for Studio.",
      blockers: []
    });
  });

  it("still blocks PulseAudio when one source has only multiple muted output routes", () => {
    const result = describeLiveApplyPreflight(
      {
        ...baseConfiguration,
        routes: [
          { id: "mic-program-muted", from: "mic", to: "program", gain: 1, muted: true },
          { id: "mic-stream-muted", from: "mic", to: "stream", gain: 0.8, muted: true }
        ]
      },
      "pulseaudio"
    );

    expect(result.blockers).toEqual([
      "PulseAudio compatibility can route each source to only one output; adjust Studio Mic -> Program and Studio Mic -> Stream."
    ]);
  });

  it("blocks ALSA because it is diagnostics-only", () => {
    expect(describeLiveApplyPreflight(baseConfiguration, "alsa").blockers).toEqual([
      "ALSA live apply is not implemented; use PipeWire, PulseAudio, or JACK."
    ]);
  });

  it("blocks persisted DSP provider live apply until desktop provider settings are live-ready", () => {
    const result = describeLiveApplyPreflight(baseConfiguration, "dsp");

    expect(result).toEqual({
      ok: false,
      mode: "blocked",
      badge: "Blocked",
      message:
        "DSP provider live apply needs live provider settings. Save a live DSP provider command in Settings before " +
        "arming host apply.",
      blockers: [
        "DSP provider live apply needs live provider settings. Save a live DSP provider command in Settings before " +
          "arming host apply."
      ]
    });
  });

  it("blocks DSP provider live apply even when graph-edge capability is reported without provider settings", () => {
    expect(describeLiveApplyPreflight(baseConfiguration, "dsp", undefined, graphEdgeDsp)).toEqual({
      ok: false,
      mode: "blocked",
      badge: "Blocked",
      message:
        "DSP provider live apply needs live provider settings. Save a live DSP provider command in Settings before " +
        "arming host apply.",
      blockers: [
        "DSP provider live apply needs live provider settings. Save a live DSP provider command in Settings before " +
          "arming host apply."
      ]
    });
  });

  it("allows DSP provider live apply once desktop provider settings are live-ready", () => {
    expect(describeLiveApplyPreflight(baseConfiguration, "dsp", undefined, graphEdgeDsp, {
      dspProviderReady: true
    })).toEqual({
      ok: true,
      mode: "ready",
      badge: "Ready",
      message: "DSP Provider live apply is ready for Studio.",
      blockers: []
    });
  });

  it("blocks native PipeWire when route gain is non-unity or sources lack host ports", () => {
    const result = describeLiveApplyPreflight(baseConfiguration, "pipewire");

    expect(result.message).toBe("Resolve 2 blockers before live apply can be armed.");
    expect(result.blockers).toEqual([
      "PipeWire live apply needs 100% route gain for Call Audio -> Stream. Use Reset gains, or switch to a " +
        "graph-edge/DSP-capable backend when one is available.",
      "PipeWire live apply needs host source ports for Call Audio."
    ]);
  });

  it("allows muted native routes to retain non-unity gain values", () => {
    const mutedConfiguration: LoopwireConfiguration = {
      ...baseConfiguration,
      inputs: baseConfiguration.inputs.map((input) => ({ ...input, deviceName: input.deviceName ?? "call_audio" })),
      routes: baseConfiguration.routes.map((route) =>
        route.id === "call-stream" ? { ...route, gain: 0.6, muted: true } : route
      )
    };

    expect(describeLiveApplyPreflight(mutedConfiguration, "pipewire")).toMatchObject({
      ok: true,
      badge: "Ready",
      blockers: []
    });
    expect(describeLiveApplyPreflight(mutedConfiguration, "jack").blockers[0]).not.toContain("100% route gain");
    expect(getNativeGainBlockerRoutes(mutedConfiguration, "pipewire").map((route) => route.id)).toEqual([]);
    expect(getNativeGainBlockerRoutes(mutedConfiguration, "jack").map((route) => route.id)).toEqual([]);
  });

  it("does not block gain or unbound sources when the backend creates virtual devices with graph-edge gain", () => {
    const result = describeLiveApplyPreflight(
      baseConfiguration,
      "pipewire",
      (kind) => (kind === "pipewire" ? "PipeWire DSP" : kind),
      graphEdgePipeWire
    );

    // Unbound sources become Loopwire-owned virtual nodes on this backend.
    expect(result).toMatchObject({ ok: true, mode: "ready", blockers: [] });
    expect(getNativeGainBlockerRoutes(baseConfiguration, "pipewire", graphEdgePipeWire)).toEqual([]);
  });

  it("blocks native JACK when any routed or monitored endpoint lacks an existing port binding", () => {
    const result = describeLiveApplyPreflight(baseConfiguration, "jack");

    expect(result.message).toBe("Resolve 2 blockers before live apply can be armed.");
    expect(result.blockers).toEqual([
      "JACK live apply needs 100% route gain for Call Audio -> Stream. Use Reset gains, or switch to a " +
        "graph-edge/DSP-capable backend when one is available.",
      "JACK live apply needs existing JACK ports or saved provider settings for " +
        "Call Audio (loopwire_studio_input_call), Stream (loopwire_studio_stream), and 1 more endpoint."
    ]);
  });

  it("allows native JACK provider settings to cover Loopwire-owned virtual port gaps", () => {
    const result = describeLiveApplyPreflight(
      {
        ...baseConfiguration,
        routes: baseConfiguration.routes.map((route) => ({ ...route, gain: 1 }))
      },
      "jack",
      undefined,
      undefined,
      { jackProviderReady: true }
    );

    expect(result).toEqual({
      ok: true,
      mode: "ready",
      badge: "Ready",
      message: "JACK live apply is ready for Studio.",
      blockers: []
    });
  });

  it("allows JACK graph-edge DSP backends that create their own virtual ports", () => {
    expect(describeLiveApplyPreflight(
      baseConfiguration,
      "jack",
      (kind) => (kind === "jack" ? "JACK DSP" : kind),
      graphEdgeJack
    )).toEqual({
      ok: true,
      mode: "ready",
      badge: "Ready",
      message: "JACK DSP live apply is ready for Studio.",
      blockers: []
    });
  });

  it("allows native JACK once endpoint bindings and route gains are live-safe", () => {
    const result = describeLiveApplyPreflight(
      {
        ...baseConfiguration,
        inputs: baseConfiguration.inputs.map((input) => ({ ...input, deviceName: input.deviceName ?? "call_audio" })),
        outputs: baseConfiguration.outputs.map((output) => ({ ...output, deviceName: output.deviceName ?? "stream_out" })),
        monitors: baseConfiguration.monitors.map((monitor) => ({ ...monitor, deviceName: monitor.deviceName ?? "booth_out" })),
        routes: baseConfiguration.routes.map((route) => ({ ...route, gain: 1 }))
      },
      "jack"
    );

    expect(result).toEqual({
      ok: true,
      mode: "ready",
      badge: "Ready",
      message: "JACK live apply is ready for Studio.",
      blockers: []
    });
  });
});

describe("getNativeGainBlockerRoutes", () => {
  it("only treats PipeWire and JACK as native link backends with unity-gain preflight", () => {
    expect(getNativeGainBlockerRoutes(baseConfiguration, "pipewire").map((route) => route.id)).toEqual(["call-stream"]);
    expect(getNativeGainBlockerRoutes(baseConfiguration, "jack").map((route) => route.id)).toEqual(["call-stream"]);
    expect(getNativeGainBlockerRoutes(baseConfiguration, "pulseaudio")).toEqual([]);
    expect(getNativeGainBlockerRoutes(baseConfiguration, "alsa")).toEqual([]);
  });
});

describe("describeConfigurationSwitchPreflight", () => {
  it("uses the selected backend capability report for the switch guard", () => {
    const result = describeConfigurationSwitchPreflight(
      baseConfiguration,
      "pipewire",
      [graphEdgeJack, graphEdgePipeWire],
      (kind) => (kind === "pipewire" ? "PipeWire DSP" : kind)
    );

    // Graph-edge gain + virtual-device creation clear both static blockers.
    expect(result).toMatchObject({ ok: true, mode: "ready", blockers: [] });
  });

  it("does not use a capability report for a different backend", () => {
    const result = describeConfigurationSwitchPreflight(
      baseConfiguration,
      "pipewire",
      [graphEdgeJack],
      (kind) => (kind === "pipewire" ? "PipeWire" : kind)
    );

    expect(result.message).toBe("Resolve 2 blockers before live apply can be armed.");
    expect(result.blockers[0]).toContain("PipeWire live apply needs 100% route gain");
  });

  it("blocks configuration switching when the selected backend report is unavailable", () => {
    const result = describeConfigurationSwitchPreflight(
      baseConfiguration,
      "pulseaudio",
      [graphEdgePipeWire, unavailablePulseAudio]
    );

    expect(result).toEqual({
      ok: false,
      mode: "blocked",
      badge: "Blocked",
      message: "PulseAudio is unavailable for live apply: PulseAudio service is not reachable.",
      blockers: ["PulseAudio is unavailable for live apply: PulseAudio service is not reachable."]
    });
  });
});

describe("createLiveApplyPreflightLog", () => {
  it("records every blocked switch preflight reason as runtime verification evidence", () => {
    const preflight = describeConfigurationSwitchPreflight(
      baseConfiguration,
      "pipewire",
      [],
      (kind) => (kind === "pipewire" ? "PipeWire" : kind)
    );

    expect(createLiveApplyPreflightLog("studio", preflight)).toEqual([
      {
        operation: "verify",
        configurationId: "studio",
        ok: false,
        message:
          "PipeWire live apply needs 100% route gain for Call Audio -> Stream. Use Reset gains, or switch to a " +
          "graph-edge/DSP-capable backend when one is available."
      },
      {
        operation: "verify",
        configurationId: "studio",
        ok: false,
        message: "PipeWire live apply needs host source ports for Call Audio."
      }
    ]);
  });

  it("does not create runtime log noise when preflight is ready", () => {
    const preflight = describeLiveApplyPreflight(
      {
        ...baseConfiguration,
        inputs: baseConfiguration.inputs.map((input) => ({ ...input, deviceName: input.deviceName ?? "call_audio" })),
        routes: baseConfiguration.routes.map((route) => ({ ...route, gain: 1 }))
      },
      "pipewire"
    );

    expect(createLiveApplyPreflightLog("studio", preflight)).toEqual([]);
  });
});
