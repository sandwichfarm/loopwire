import { describe, expect, it } from "vitest";
import type { LoopwireConfiguration } from "@loopwire/core";
import type { CommandResult } from "@loopwire/audio-host/runtime";
import { evaluateDspLiveCapabilityResult, routesWithOffEndpointsMuted, toHostRuntimeConfiguration } from "./runtime";

const configuration: LoopwireConfiguration = {
  id: "device",
  name: "Device",
  description: "",
  inputs: [
    { id: "mic", label: "Mic", role: "input", channels: 2 },
    { id: "app", label: "App", role: "input", channels: 2, enabled: false }
  ],
  outputs: [{ id: "bus", label: "Channels 1 & 2", role: "output", channels: 2 }],
  monitors: [{ id: "phones", label: "Headphones", role: "monitor", channels: 2, enabled: false }],
  routes: [
    { id: "mic-bus", from: "mic", to: "bus", gain: 1, muted: false },
    { id: "app-bus", from: "app", to: "bus", gain: 0.8, muted: false },
    { id: "bus-phones", from: "bus", to: "phones", gain: 1, muted: false }
  ],
  updatedAt: ""
};

describe("routesWithOffEndpointsMuted", () => {
  it("mutes routes whose source or target endpoint is Off", () => {
    const routes = routesWithOffEndpointsMuted(configuration);

    expect(routes.find((route) => route.id === "mic-bus")?.muted).toBe(false);
    expect(routes.find((route) => route.id === "app-bus")?.muted).toBe(true);
    expect(routes.find((route) => route.id === "bus-phones")?.muted).toBe(true);
  });
});

describe("toHostRuntimeConfiguration", () => {
  it("carries the Off-endpoint muting into the host adapter contract", () => {
    const host = toHostRuntimeConfiguration(configuration);

    expect(host.routes?.find((route) => route.id === "app-bus")?.muted).toBe(true);
    expect(host.routes?.find((route) => route.id === "mic-bus")?.muted).toBe(false);
    expect(host.inputs?.map((input) => input.id)).toEqual(["mic", "app"]);
  });
});

function capabilityResult(overrides: Partial<CommandResult>): CommandResult {
  return {
    command: "loopwire-live-dsp-provider",
    args: ["capabilities"],
    exitCode: 0,
    stdout: "",
    stderr: "",
    ...overrides
  };
}

const liveCapabilities = {
  supportsLiveGraph: true,
  operations: ["read-source", "write-output", "verify-output", "clear-output"]
};

describe("evaluateDspLiveCapabilityResult", () => {
  it("accepts a live provider declaring every required operation", () => {
    const result = evaluateDspLiveCapabilityResult(capabilityResult({ stdout: JSON.stringify(liveCapabilities) }));

    expect(result.ok).toBe(true);
  });

  it("fails on a nonzero exit code with the first command line", () => {
    const result = evaluateDspLiveCapabilityResult(
      capabilityResult({ exitCode: 1, stderr: "provider exploded\nmore detail" })
    );

    expect(result.ok).toBe(false);
    expect(result.message).toContain("provider exploded");
  });

  it("rejects providers without supportsLiveGraph:true", () => {
    const result = evaluateDspLiveCapabilityResult(
      capabilityResult({ stdout: JSON.stringify({ ...liveCapabilities, supportsLiveGraph: false }) })
    );

    expect(result.ok).toBe(false);
    expect(result.message).toContain("supportsLiveGraph:true");
  });

  it("names missing required operations", () => {
    const result = evaluateDspLiveCapabilityResult(
      capabilityResult({ stdout: JSON.stringify({ supportsLiveGraph: true, operations: ["read-source"] }) })
    );

    expect(result.ok).toBe(false);
    expect(result.message).toContain("write-output, verify-output, clear-output");
  });

  it("rejects invalid capability JSON", () => {
    const result = evaluateDspLiveCapabilityResult(capabilityResult({ stdout: "{not json" }));

    expect(result.ok).toBe(false);
    expect(result.message).toContain("invalid JSON");
  });
});
