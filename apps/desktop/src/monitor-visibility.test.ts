import { describe, expect, it } from "vitest";
import { createDefaultState, getActiveConfiguration, setMonitorHidden } from "@loopwire/core";
import { groupMonitorsByVisibility, restoreHiddenMonitors } from "./monitor-visibility";

describe("groupMonitorsByVisibility", () => {
  it("keeps hidden monitors out of the visible monitor grid", () => {
    const state = setMonitorHidden(createDefaultState(), "studio", "headphones", true);
    const configuration = getActiveConfiguration(state);

    expect(groupMonitorsByVisibility(state, configuration)).toMatchObject({
      visible: [{ id: "meters" }],
      hidden: [{ id: "headphones" }]
    });
  });

  it("keeps monitor visibility scoped to the active configuration", () => {
    const state = setMonitorHidden(createDefaultState(), "studio", "headphones", true);
    const callConfiguration = state.configurations.find((configuration) => configuration.id === "call");

    expect(callConfiguration).toBeDefined();
    expect(groupMonitorsByVisibility(state, callConfiguration!).hidden).toEqual([]);
    expect(groupMonitorsByVisibility(state, callConfiguration!).visible.map((monitor) => monitor.id)).toContain(
      "headphones"
    );
  });

  it("restores every hidden monitor for one configuration", () => {
    const state = setMonitorHidden(
      setMonitorHidden(createDefaultState(), "studio", "headphones", true),
      "studio",
      "meters",
      true
    );
    const configuration = getActiveConfiguration(state);

    const restored = restoreHiddenMonitors(state, configuration);

    expect(groupMonitorsByVisibility(restored, configuration)).toMatchObject({
      visible: [{ id: "headphones" }, { id: "meters" }],
      hidden: []
    });
    expect(restored.hiddenMonitorIds).toEqual([]);
  });

  it("keeps other configurations hidden when restoring the active configuration", () => {
    const state = setMonitorHidden(
      setMonitorHidden(createDefaultState(), "studio", "headphones", true),
      "call",
      "headphones",
      true
    );
    const studioConfiguration = getActiveConfiguration(state);
    const callConfiguration = state.configurations.find((configuration) => configuration.id === "call");

    expect(callConfiguration).toBeDefined();
    const restored = restoreHiddenMonitors(state, studioConfiguration);

    expect(groupMonitorsByVisibility(restored, studioConfiguration).hidden).toEqual([]);
    expect(groupMonitorsByVisibility(restored, callConfiguration!).hidden.map((monitor) => monitor.id)).toEqual([
      "headphones"
    ]);
  });
});
