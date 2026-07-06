import { describe, expect, it } from "vitest";
import {
  createDefaultState,
  getConfigurationById,
  updateConfiguration,
  type LoopwireConfiguration,
  type LoopwireState
} from "@loopwire/core";
import { resetNativeRouteGainsForLiveApply } from "./native-gain-reset";
import type { LiveApplyBackendCapability } from "./live-apply-preflight";

const updatedAt = "2026-07-06T08:00:00.000Z";
const graphEdgePipeWire: LiveApplyBackendCapability = {
  kind: "pipewire",
  displayName: "PipeWire DSP",
  mixing: {
    controlScope: "graph-edge",
    supportsPerEdgeGain: true,
    supportsPerEdgeMute: true
  }
};

function studioWithRoutes(
  routes: LoopwireConfiguration["routes"]
): { readonly state: LoopwireState; readonly configuration: LoopwireConfiguration } {
  const state = createDefaultState("2026-07-06T07:50:00.000Z");
  const result = updateConfiguration(
    state,
    "studio",
    {
      routes
    },
    "2026-07-06T07:55:00.000Z"
  );

  return {
    state: result.state,
    configuration: result.configuration
  };
}

describe("resetNativeRouteGainsForLiveApply", () => {
  it("resets unmuted native PipeWire blockers while preserving muted saved gains", () => {
    const { state, configuration } = studioWithRoutes([
      { id: "mic-recorder", from: "mic", to: "recorder", gain: 0.5, muted: false },
      { id: "browser-recorder", from: "browser", to: "recorder", gain: 0.25, muted: true }
    ]);
    const result = resetNativeRouteGainsForLiveApply({
      state,
      configuration,
      backend: "pipewire",
      updatedAt
    });
    const updated = getConfigurationById(result.state, "studio");

    expect(result.routes.map((route) => route.id)).toEqual(["mic-recorder"]);
    expect(updated.routes.map((route) => [route.id, route.gain, route.muted])).toEqual([
      ["mic-recorder", 1, false],
      ["browser-recorder", 0.25, true]
    ]);
    expect(updated.updatedAt).toBe(updatedAt);
  });

  it("resets every unmuted native JACK blocker with one deterministic timestamp", () => {
    const { state, configuration } = studioWithRoutes([
      { id: "mic-recorder", from: "mic", to: "recorder", gain: 0.5, muted: false },
      { id: "browser-recorder", from: "browser", to: "recorder", gain: 0.25, muted: false }
    ]);
    const result = resetNativeRouteGainsForLiveApply({
      state,
      configuration,
      backend: "jack",
      updatedAt
    });
    const updated = getConfigurationById(result.state, "studio");

    expect(result.routes.map((route) => route.id)).toEqual(["mic-recorder", "browser-recorder"]);
    expect(updated.routes.map((route) => [route.id, route.gain])).toEqual([
      ["mic-recorder", 1],
      ["browser-recorder", 1]
    ]);
    expect(updated.updatedAt).toBe(updatedAt);
  });

  it("does not rewrite stream or graph-edge backends", () => {
    const { state, configuration } = studioWithRoutes([
      { id: "mic-recorder", from: "mic", to: "recorder", gain: 0.5, muted: false }
    ]);

    expect(resetNativeRouteGainsForLiveApply({
      state,
      configuration,
      backend: "pulseaudio",
      updatedAt
    })).toEqual({
      state,
      routes: []
    });
    expect(resetNativeRouteGainsForLiveApply({
      state,
      configuration,
      backend: "pipewire",
      capability: graphEdgePipeWire,
      updatedAt
    })).toEqual({
      state,
      routes: []
    });
  });
});
