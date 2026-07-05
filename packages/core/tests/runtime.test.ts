import { describe, expect, it } from "vitest";
import {
  applyBackendSelection,
  applyConfigurationSwitch,
  createBackendSelectionPlan,
  createConfigurationSwitchPlan,
  createDefaultState,
  verifyStartupConfiguration,
  type ConfigurationRuntimeAdapter,
  type RuntimeOperation
} from "../src/index.js";

function createAdapter(failingOperation?: RuntimeOperation): {
  readonly adapter: ConfigurationRuntimeAdapter;
  readonly calls: string[];
} {
  const calls: string[] = [];

  function run(operation: RuntimeOperation): ConfigurationRuntimeAdapter[RuntimeOperation] {
    return (configuration) => {
      calls.push(`${operation}:${configuration.id}`);

      if (operation === failingOperation) {
        return { ok: false, message: `${operation} failed` };
      }

      return { ok: true, message: `${operation} ok` };
    };
  }

  return {
    calls,
    adapter: {
      unload: run("unload"),
      apply: run("apply"),
      verify: run("verify"),
      rollback: run("rollback")
    }
  };
}

describe("configuration runtime", () => {
  it("plans a switch as unload, apply, and verify", () => {
    const state = createDefaultState("2026-07-03T12:00:00.000Z");
    const plan = createConfigurationSwitchPlan(state, "stream", "2026-07-03T12:30:00.000Z");

    expect(plan.fromConfigurationId).toBe("studio");
    expect(plan.toConfigurationId).toBe("stream");
    expect(plan.operations).toEqual(["unload", "apply", "verify"]);
    expect(plan.reason).toBe("switch");
  });

  it("switches configurations only after verify succeeds", async () => {
    const state = createDefaultState("2026-07-03T12:00:00.000Z");
    const { adapter, calls } = createAdapter();

    const result = await applyConfigurationSwitch(state, "stream", adapter, "2026-07-03T12:35:00.000Z");

    expect(result.ok).toBe(true);
    expect(result.status).toBe("verified");
    expect(result.state.activeConfigurationId).toBe("stream");
    expect(result.state.appliedAt).toBe("2026-07-03T12:35:00.000Z");
    expect(calls).toEqual(["unload:studio", "apply:stream", "verify:stream"]);
  });

  it("rolls back to the previous configuration when apply fails", async () => {
    const state = createDefaultState("2026-07-03T12:00:00.000Z");
    const { adapter, calls } = createAdapter("apply");

    const result = await applyConfigurationSwitch(state, "stream", adapter, "2026-07-03T12:40:00.000Z");

    expect(result.ok).toBe(false);
    expect(result.status).toBe("rolled_back");
    expect(result.state.activeConfigurationId).toBe("studio");
    expect(calls).toEqual(["unload:studio", "apply:stream", "rollback:studio"]);
  });

  it("rolls back to the previous configuration when verify fails", async () => {
    const state = createDefaultState("2026-07-03T12:00:00.000Z");
    const { adapter, calls } = createAdapter("verify");

    const result = await applyConfigurationSwitch(state, "stream", adapter, "2026-07-03T12:45:00.000Z");

    expect(result.ok).toBe(false);
    expect(result.status).toBe("rolled_back");
    expect(result.state.activeConfigurationId).toBe("studio");
    expect(calls).toEqual(["unload:studio", "apply:stream", "verify:stream", "rollback:studio"]);
  });

  it("re-applies the selected startup configuration without unloading another configuration", async () => {
    const state = { ...createDefaultState("2026-07-03T12:00:00.000Z"), activeConfigurationId: "call" };
    const { adapter, calls } = createAdapter();

    const result = await verifyStartupConfiguration(state, adapter, "2026-07-03T12:50:00.000Z");

    expect(result.ok).toBe(true);
    expect(result.plan.reason).toBe("startup");
    expect(result.plan.operations).toEqual(["apply", "verify"]);
    expect(result.state.activeConfigurationId).toBe("call");
    expect(result.state.appliedAt).toBe("2026-07-03T12:50:00.000Z");
    expect(calls).toEqual(["apply:call", "verify:call"]);
  });

  it("plans a backend change as apply and verify of the active configuration", () => {
    const state = { ...createDefaultState("2026-07-03T12:00:00.000Z"), activeConfigurationId: "call" };
    const plan = createBackendSelectionPlan(state, "2026-07-03T12:55:00.000Z");

    expect(plan.reason).toBe("backend-change");
    expect(plan.toConfigurationId).toBe("call");
    expect(plan.operations).toEqual(["apply", "verify"]);
    expect(plan.fromConfigurationId).toBeUndefined();
  });

  it("commits a selected backend only after the active configuration verifies", async () => {
    const state = createDefaultState("2026-07-03T12:00:00.000Z");
    const { adapter, calls } = createAdapter();

    const result = await applyBackendSelection(state, "jack", adapter, "2026-07-03T13:00:00.000Z");

    expect(result.ok).toBe(true);
    expect(result.plan.reason).toBe("backend-change");
    expect(result.state.selectedBackend).toBe("jack");
    expect(result.state.activeConfigurationId).toBe("studio");
    expect(result.state.appliedAt).toBe("2026-07-03T13:00:00.000Z");
    expect(calls).toEqual(["apply:studio", "verify:studio"]);
  });

  it("keeps the previous backend when backend-change verification fails", async () => {
    const state = { ...createDefaultState("2026-07-03T12:00:00.000Z"), selectedBackend: "pipewire" as const };
    const { adapter, calls } = createAdapter("verify");

    const result = await applyBackendSelection(state, "jack", adapter, "2026-07-03T13:05:00.000Z");

    expect(result.ok).toBe(false);
    expect(result.status).toBe("rolled_back");
    expect(result.state.selectedBackend).toBe("pipewire");
    expect(calls).toEqual(["apply:studio", "verify:studio", "rollback:studio"]);
  });
});
