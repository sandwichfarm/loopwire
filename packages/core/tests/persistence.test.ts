import { describe, expect, it } from "vitest";
import {
  activateConfiguration,
  createDefaultState,
  exportConfiguration,
  getActiveConfiguration,
  importConfiguration,
  restoreState,
  serializeState,
  setMonitorHidden,
  setSelectedBackend
} from "../src/index.js";

describe("persistence", () => {
  it("round-trips the selected backend, active configuration, hidden monitors, and applied timestamp", () => {
    const original = setSelectedBackend(
      setMonitorHidden(activateConfiguration(createDefaultState(), "call", "2026-07-03T11:00:00.000Z"), "call", "headphones", true),
      "jack"
    );

    const restored = restoreState(serializeState(original));

    expect(restored.ok).toBe(true);
    expect(restored.state.selectedBackend).toBe("jack");
    expect(restored.state.activeConfigurationId).toBe("call");
    expect(restored.state.hiddenMonitorIds).toEqual(["call:headphones"]);
    expect(restored.state.appliedAt).toBe("2026-07-03T11:00:00.000Z");
  });

  it("preserves explicit DSP provider backend selection for background restore", () => {
    const original = setSelectedBackend(createDefaultState(), "dsp");
    const restored = restoreState(serializeState(original));

    expect(restored.ok).toBe(true);
    expect(restored.state.selectedBackend).toBe("dsp");
  });

  it("falls back when the payload is corrupt", () => {
    const fallback = createDefaultState("2026-07-03T12:00:00.000Z");
    const restored = restoreState("{nope", fallback);

    expect(restored.ok).toBe(false);
    expect(restored.state).toBe(fallback);
  });

  it("normalizes a stale active configuration to the first available config", () => {
    const state = createDefaultState();
    const payload = JSON.parse(serializeState(state)) as Record<string, unknown>;
    payload.activeConfigurationId = "gone";

    const restored = restoreState(JSON.stringify(payload));

    expect(restored.ok).toBe(true);
    expect(restored.state.activeConfigurationId).toBe("studio");
  });

  it("imports an exported configuration with a unique id", () => {
    const state = createDefaultState("2026-07-03T12:00:00.000Z");
    const raw = exportConfiguration(getActiveConfiguration(state));
    const imported = importConfiguration(state, raw, "2026-07-03T12:05:00.000Z");

    expect(imported.ok).toBe(true);
    if (!imported.ok) {
      return;
    }

    expect(imported.configuration.id).toBe("studio-2");
    expect(imported.configuration.name).toBe("Studio");
    expect(imported.configuration.updatedAt).toBe("2026-07-03T12:05:00.000Z");
    expect(imported.state.configurations).toHaveLength(4);
    expect(imported.state.activeConfigurationId).toBe("studio");
  });

  it("round-trips monitor device names", () => {
    const state = createDefaultState("2026-07-03T12:00:00.000Z");
    const payload = JSON.parse(serializeState(state)) as Record<string, unknown>;
    const configurations = payload.configurations as Array<Record<string, unknown>>;
    const studio = configurations[0]!;
    studio.monitors = [{ id: "headphones", label: "Headphones", role: "monitor", channels: 2, deviceName: "sink.usb" }];

    const restored = restoreState(JSON.stringify(payload));

    expect(restored.ok).toBe(true);
    expect(getActiveConfiguration(restored.state).monitors[0]?.deviceName).toBe("sink.usb");
  });

  it("rejects invalid imported configurations without changing state", () => {
    const state = createDefaultState();
    const imported = importConfiguration(
      state,
      JSON.stringify({
        kind: "loopwire.configuration",
        version: 1,
        configuration: { id: "bad", name: "Bad", description: "", inputs: [], outputs: [], monitors: [], routes: [] }
      }),
      "2026-07-03T12:10:00.000Z"
    );

    expect(imported.ok).toBe(false);
    expect(imported.state).toBe(state);
  });

  it("migrates legacy v0 persisted state into the current schema", () => {
    const state = createDefaultState("2026-07-03T12:00:00.000Z");
    const legacy = {
      version: 0,
      selectedBackend: "pipewire",
      configurations: state.configurations,
      activeId: "call",
      hiddenMonitors: ["headphones"],
      appliedAt: "2026-07-03T12:20:00.000Z"
    };

    const restored = restoreState(JSON.stringify(legacy));

    expect(restored.ok).toBe(true);
    expect(restored.state.version).toBe(2);
    expect(restored.state.activeConfigurationId).toBe("call");
    expect(restored.state.hiddenMonitorIds).toEqual(["headphones"]);
    expect(restored.state.appliedAt).toBe("2026-07-03T12:20:00.000Z");
  });
});
