import { describe, expect, it } from "vitest";
import type { LoopwireConfiguration } from "@loopwire/core";
import type { LiveApplyBackendCapability } from "./live-apply-preflight";
import {
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

  it("blocks ALSA because it is diagnostics-only", () => {
    expect(describeLiveApplyPreflight(baseConfiguration, "alsa").blockers).toEqual([
      "ALSA live apply is not implemented; use PipeWire, PulseAudio, or JACK."
    ]);
  });

  it("blocks persisted DSP provider live apply until explicit provider capability is available", () => {
    const result = describeLiveApplyPreflight(baseConfiguration, "dsp");

    expect(result).toEqual({
      ok: false,
      mode: "blocked",
      badge: "Blocked",
      message:
        "DSP provider live apply needs an explicit live provider capability report; use background restore provider " +
        "settings or select PipeWire, PulseAudio, or JACK for desktop live apply.",
      blockers: [
        "DSP provider live apply needs an explicit live provider capability report; use background restore provider " +
          "settings or select PipeWire, PulseAudio, or JACK for desktop live apply."
      ]
    });
  });

  it("allows DSP provider live apply when graph-edge capability is explicit", () => {
    expect(describeLiveApplyPreflight(baseConfiguration, "dsp", undefined, graphEdgeDsp)).toMatchObject({
      ok: true,
      badge: "Ready",
      message: "DSP Provider live apply is ready for Studio."
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

  it("does not block route gain when detected backend semantics support graph-edge gain", () => {
    const result = describeLiveApplyPreflight(
      baseConfiguration,
      "pipewire",
      (kind) => (kind === "pipewire" ? "PipeWire DSP" : kind),
      graphEdgePipeWire
    );

    expect(result.message).toBe("PipeWire DSP live apply needs host source ports for Call Audio.");
    expect(result.blockers).toEqual(["PipeWire DSP live apply needs host source ports for Call Audio."]);
    expect(getNativeGainBlockerRoutes(baseConfiguration, "pipewire", graphEdgePipeWire)).toEqual([]);
  });

  it("blocks native JACK when any routed or monitored endpoint lacks an existing port binding", () => {
    const result = describeLiveApplyPreflight(baseConfiguration, "jack");

    expect(result.message).toBe("Resolve 2 blockers before live apply can be armed.");
    expect(result.blockers).toEqual([
      "JACK live apply needs 100% route gain for Call Audio -> Stream. Use Reset gains, or switch to a " +
        "graph-edge/DSP-capable backend when one is available.",
      "JACK live apply needs host bindings to existing JACK ports for " +
        "Call Audio (loopwire_studio_input_call), Stream (loopwire_studio_stream), and 1 more endpoint."
    ]);
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

    expect(result.message).toBe("PipeWire DSP live apply needs host source ports for Call Audio.");
    expect(result.blockers).toEqual(["PipeWire DSP live apply needs host source ports for Call Audio."]);
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
