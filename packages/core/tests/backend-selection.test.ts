import { describe, expect, it } from "vitest";
import { createDefaultState, selectBackend, type BackendCandidate } from "../src/index.js";

const pipewire: BackendCandidate = {
  kind: "pipewire",
  displayName: "PipeWire",
  availability: "available",
  priority: 10
};

const jack: BackendCandidate = {
  kind: "jack",
  displayName: "JACK",
  availability: "available",
  priority: 30
};

describe("selectBackend", () => {
  it("does not treat first-run state as a persisted backend choice", () => {
    const state = createDefaultState();

    expect(state.selectedBackend).toBeUndefined();
    expect(selectBackend([jack, pipewire], state.selectedBackend).mode).toBe("prompt");
  });

  it("auto-selects the only available backend", () => {
    expect(selectBackend([pipewire])).toMatchObject({
      mode: "auto",
      backend: pipewire
    });
  });

  it("prompts when multiple available backends are detected", () => {
    const decision = selectBackend([jack, pipewire]);

    expect(decision.mode).toBe("prompt");
    if (decision.mode === "prompt") {
      expect(decision.candidates.map((candidate) => candidate.kind)).toEqual(["pipewire", "jack"]);
    }
  });

  it("keeps the persisted backend when it is still available", () => {
    expect(selectBackend([pipewire, jack], "jack")).toMatchObject({
      mode: "auto",
      backend: jack
    });
  });

  it("reports no backend when every candidate is unavailable", () => {
    const decision = selectBackend([
      {
        ...pipewire,
        availability: "unavailable",
        reason: "pipewire service is not running"
      }
    ]);

    expect(decision).toEqual({
      mode: "none",
      reason: "No supported Linux audio backend is currently available."
    });
  });
});
