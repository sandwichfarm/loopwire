import { describe, expect, it } from "vitest";
import {
  describeRouteControlSemantics,
  describeSelectedRouteControlSemantics,
  routeGainEditingLockedForBackend,
  type RouteControlBackendCapability
} from "./route-control-semantics";

const graphEdgePipeWire: RouteControlBackendCapability = {
  kind: "pipewire",
  displayName: "PipeWire DSP",
  mixing: {
    controlScope: "graph-edge",
    supportsPerEdgeGain: true,
    supportsPerEdgeMute: true,
    warning: "DSP engine owns graph-edge controls."
  }
};

describe("route control semantics", () => {
  it("describes backend-specific route control scopes", () => {
    expect(describeRouteControlSemantics("pulseaudio")).toEqual({
      mode: "stream",
      badge: "Stream",
      message: "PulseAudio controls whole matching streams; each source can route to only one output."
    });
    expect(describeRouteControlSemantics("pipewire")).toEqual({
      mode: "link",
      badge: "Link",
      message: "Native PipeWire applies route mute by disconnecting links; per-edge gain remains planned."
    });
    expect(describeRouteControlSemantics("jack")).toEqual({
      mode: "link",
      badge: "Link",
      message: "Native JACK applies route mute by disconnecting connections; per-edge gain remains planned."
    });
    expect(describeRouteControlSemantics("alsa")).toEqual({
      mode: "planned",
      badge: "Planned",
      message: "ALSA route apply and per-edge controls are not implemented yet."
    });
    expect(describeRouteControlSemantics("dsp")).toEqual({
      mode: "planned",
      badge: "DSP",
      message:
        "DSP provider controls are available through provider-backed background restore; desktop live apply needs " +
        "provider command settings first."
    });
  });

  it("uses backend-selection state when no backend is selected", () => {
    expect(describeSelectedRouteControlSemantics(undefined, "prompt")).toMatchObject({
      badge: "Choose",
      message: "Choose a detected backend to see host route-control semantics."
    });
    expect(describeSelectedRouteControlSemantics(undefined, "none")).toMatchObject({
      badge: "No backend",
      message: "No Linux audio backend probes succeeded; route controls stay in app preview."
    });
  });

  it("uses detected graph-edge mixing semantics instead of backend-name fallbacks", () => {
    expect(describeRouteControlSemantics("pipewire", graphEdgePipeWire)).toEqual({
      mode: "edge",
      badge: "Graph",
      message: "PipeWire DSP applies independent per-route gain and mute at the graph edge."
    });
    expect(routeGainEditingLockedForBackend("pipewire", graphEdgePipeWire)).toBe(false);
    expect(describeSelectedRouteControlSemantics("pipewire", "auto", graphEdgePipeWire)).toMatchObject({
      mode: "edge",
      badge: "Graph"
    });
  });

  it("locks route gain editing only for native link backends", () => {
    expect(routeGainEditingLockedForBackend("pipewire")).toBe(true);
    expect(routeGainEditingLockedForBackend("jack")).toBe(true);
    expect(routeGainEditingLockedForBackend("pulseaudio")).toBe(false);
    expect(routeGainEditingLockedForBackend("alsa")).toBe(false);
    expect(routeGainEditingLockedForBackend("dsp")).toBe(false);
    expect(routeGainEditingLockedForBackend(undefined)).toBe(false);
  });
});
