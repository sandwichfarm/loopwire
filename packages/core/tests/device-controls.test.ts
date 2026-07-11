import { describe, expect, it } from "vitest";
import {
  addMonitorToConfiguration,
  addRouteToConfiguration,
  configurationVolume,
  createConfiguration,
  createDefaultState,
  createEmptyState,
  endpointVolume,
  findActiveConfiguration,
  getActiveConfiguration,
  isConfigurationEnabled,
  isConfigurationMuted,
  isEndpointEnabled,
  removeConfiguration,
  removeMonitorFromConfiguration,
  removeOutputBusFromConfiguration,
  restoreState,
  serializeState,
  setConfigurationEnabled,
  setConfigurationMuted,
  setConfigurationVolume,
  setEndpointEnabled,
  setEndpointMuteWhenCapturing,
  setEndpointVolume,
  schemaVersion
} from "../src/index.js";

const at = "2026-07-06T10:00:00.000Z";

describe("empty state", () => {
  it("creates a state with no configurations and no active id", () => {
    const state = createEmptyState(at);

    expect(state.configurations).toHaveLength(0);
    expect(state.activeConfigurationId).toBeUndefined();
    expect(findActiveConfiguration(state)).toBeUndefined();
  });

  it("removeConfiguration allows removing the last configuration", () => {
    const created = createConfiguration(createEmptyState(at), { name: "Loopwire Device 1" }, at);
    const removed = removeConfiguration(created.state, created.configuration.id, at);

    expect(removed.state.configurations).toHaveLength(0);
    expect(removed.state.activeConfigurationId).toBeUndefined();
    expect(removed.removedConfiguration.name).toBe("Loopwire Device 1");
  });

  it("removeConfiguration moves the active id to the next remaining device", () => {
    let state = createEmptyState(at);
    const first = createConfiguration(state, { name: "A" }, at);
    const second = createConfiguration(first.state, { name: "B" }, at);
    state = { ...second.state, activeConfigurationId: first.configuration.id };

    const removed = removeConfiguration(state, first.configuration.id, at);

    expect(removed.state.activeConfigurationId).toBe(second.configuration.id);
  });

  it("round-trips an empty state through persistence", () => {
    const restored = restoreState(serializeState(createEmptyState(at)));

    expect(restored.ok).toBe(true);
    expect(restored.state.configurations).toHaveLength(0);
  });
});

describe("moveConfiguration", () => {
  it("reorders devices and clamps the target index", async () => {
    const { moveConfiguration } = await import("../src/index.js");
    const state = createDefaultState(at); // studio, call, stream

    const moved = moveConfiguration(state, "stream", 0, at);
    expect(moved.configurations.map((configuration) => configuration.id)).toEqual(["stream", "studio", "call"]);

    const clamped = moveConfiguration(state, "studio", 99, at);
    expect(clamped.configurations.map((configuration) => configuration.id)).toEqual(["call", "stream", "studio"]);

    expect(moveConfiguration(state, "call", 1, at)).toBe(state);
    expect(() => moveConfiguration(state, "missing", 0, at)).toThrow(/Unknown Loopwire configuration/);
  });
});

describe("device-level controls", () => {
  it("defaults to enabled, unmuted, full volume", () => {
    const configuration = getActiveConfiguration(createDefaultState(at));

    expect(isConfigurationEnabled(configuration)).toBe(true);
    expect(isConfigurationMuted(configuration)).toBe(false);
    expect(configurationVolume(configuration)).toBe(1);
  });

  it("sets and persists enabled, muted, and volume", () => {
    let state = createDefaultState(at);
    const id = getActiveConfiguration(state).id;
    state = setConfigurationEnabled(state, id, false, at).state;
    state = setConfigurationMuted(state, id, true, at).state;
    state = setConfigurationVolume(state, id, 0.4, at).state;

    const restored = restoreState(serializeState(state));
    expect(restored.ok).toBe(true);

    const configuration = getActiveConfiguration(restored.state);
    expect(isConfigurationEnabled(configuration)).toBe(false);
    expect(isConfigurationMuted(configuration)).toBe(true);
    expect(configurationVolume(configuration)).toBe(0.4);
  });

  it("rejects device volume outside 0..1", () => {
    const state = createDefaultState(at);
    const id = getActiveConfiguration(state).id;

    expect(() => setConfigurationVolume(state, id, 1.5, at)).toThrow(/between 0 and 1/);
  });
});

describe("endpoint controls", () => {
  it("defaults endpoints to enabled at full volume", () => {
    const configuration = getActiveConfiguration(createDefaultState(at));
    const source = configuration.inputs[0]!;

    expect(isEndpointEnabled(source)).toBe(true);
    expect(endpointVolume(source)).toBe(1);
  });

  it("sets endpoint enabled, volume, and mute-when-capturing", () => {
    let state = createDefaultState(at);
    const configuration = getActiveConfiguration(state);
    const source = configuration.inputs[0]!;

    state = setEndpointEnabled(state, configuration.id, source.id, false, at).state;
    state = setEndpointVolume(state, configuration.id, source.id, 0.25, at).state;
    state = setEndpointMuteWhenCapturing(state, configuration.id, source.id, true, at).state;

    const restored = restoreState(serializeState(state));
    expect(restored.ok).toBe(true);

    const updated = getActiveConfiguration(restored.state).inputs[0]!;
    expect(isEndpointEnabled(updated)).toBe(false);
    expect(endpointVolume(updated)).toBe(0.25);
    expect(updated.muteWhenCapturing).toBe(true);
  });

  it("rejects mute-when-capturing on non-input endpoints", () => {
    const state = createDefaultState(at);
    const configuration = getActiveConfiguration(state);
    const monitor = configuration.monitors[0]!;

    expect(() => setEndpointMuteWhenCapturing(state, configuration.id, monitor.id, true, at)).toThrow(
      /only applies to input sources/
    );
  });
});

describe("monitor routes", () => {
  it("adds an output-to-monitor route and validates it", () => {
    const state = createDefaultState(at);
    const configuration = getActiveConfiguration(state);
    const output = configuration.outputs[0]!;
    const monitor = configuration.monitors[0]!;

    const updated = addRouteToConfiguration(state, configuration.id, { from: output.id, to: monitor.id }, at);
    const route = updated.configuration.routes.at(-1)!;

    expect(route.from).toBe(output.id);
    expect(route.to).toBe(monitor.id);

    const restored = restoreState(serializeState(updated.state));
    expect(restored.ok).toBe(true);
  });

  it("rejects monitor-to-monitor or input-to-monitor routes", () => {
    const state = createDefaultState(at);
    const configuration = getActiveConfiguration(state);
    const source = configuration.inputs[0]!;
    const monitor = configuration.monitors[0]!;

    expect(() => addRouteToConfiguration(state, configuration.id, { from: source.id, to: monitor.id }, at)).toThrow();
    expect(() => addRouteToConfiguration(state, configuration.id, { from: monitor.id, to: monitor.id }, at)).toThrow();
  });

  it("drops monitor routes when the monitor is removed", () => {
    const state = createDefaultState(at);
    const configuration = getActiveConfiguration(state);
    const output = configuration.outputs[0]!;
    const monitor = configuration.monitors[0]!;
    const withRoute = addRouteToConfiguration(state, configuration.id, { from: output.id, to: monitor.id }, at);

    const removed = removeMonitorFromConfiguration(withRoute.state, configuration.id, monitor.id, at);

    expect(removed.configuration.routes.some((route) => route.to === monitor.id)).toBe(false);
  });

  it("drops monitor routes when the source output bus is removed", () => {
    let state = createDefaultState(at);
    const configuration = getActiveConfiguration(state);
    const monitor = configuration.monitors[0]!;
    const firstOutput = configuration.outputs[0]!;

    const withSecondBus = addRouteToConfiguration(
      {
        ...state,
        configurations: state.configurations.map((candidate) =>
          candidate.id === configuration.id
            ? {
                ...candidate,
                outputs: [...candidate.outputs, { id: "bus-2", label: "Channels 3 & 4", role: "output" as const, channels: 2 }]
              }
            : candidate
        )
      },
      configuration.id,
      { from: "bus-2", to: monitor.id },
      at
    );

    const removed = removeOutputBusFromConfiguration(withSecondBus.state, configuration.id, "bus-2", at);

    expect(removed.configuration.routes.some((route) => route.from === "bus-2")).toBe(false);
    expect(removed.configuration.routes.some((route) => route.to === firstOutput.id)).toBe(true);
  });
});

describe("schema v2 migration", () => {
  it("re-stamps v1 payloads with the current schema version", () => {
    const state = createDefaultState(at);
    const payload = JSON.parse(serializeState(state)) as Record<string, unknown>;
    payload.version = 1;

    const restored = restoreState(JSON.stringify(payload));

    expect(restored.ok).toBe(true);
    expect(restored.state.version).toBe(schemaVersion);
  });

  it("adds a monitor without implicit routes", () => {
    const state = createDefaultState(at);
    const configuration = getActiveConfiguration(state);
    const updated = addMonitorToConfiguration(state, configuration.id, { label: "Desk Speakers" }, at);

    expect(updated.configuration.routes).toEqual(configuration.routes);
  });
});

describe("endpoint kind", () => {
  it("round-trips endpoint kind through serialize and restore", () => {
    const { state } = createConfiguration(
      createEmptyState(at),
      {
        name: "Kinds",
        inputs: [
          { id: "pass-thru", label: "Pass-Thru", role: "input", channels: 2, kind: "pass-thru" },
          { id: "browser", label: "Browser", role: "input", channels: 2, kind: "app" },
          { id: "mic", label: "Studio Mic", role: "input", channels: 2 }
        ]
      },
      at
    );

    const restored = restoreState(serializeState(state));

    expect(restored.ok).toBe(true);
    const inputs = restored.state.configurations[0]?.inputs ?? [];
    expect(inputs.map((input) => input.kind)).toEqual(["pass-thru", "app", undefined]);
  });

  it("drops unknown kind values instead of rejecting the state", () => {
    const state = createDefaultState(at);
    const payload = JSON.parse(serializeState(state)) as {
      configurations: { inputs: Record<string, unknown>[] }[];
    };
    payload.configurations[0]!.inputs[0]!.kind = "bogus";

    const restored = restoreState(JSON.stringify(payload));

    expect(restored.ok).toBe(true);
    expect(restored.state.configurations[0]?.inputs[0]?.kind).toBeUndefined();
  });
});
