import { describe, expect, it } from "vitest";
import { createDefaultState, getActiveConfiguration, setMonitorHidden } from "@loopwire/core";
import { groupMonitorsByVisibility } from "./monitor-visibility";

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
});
