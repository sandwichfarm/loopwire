import { describe, expect, it } from "vitest";
import type { LoopwireConfiguration } from "@loopwire/core";
import { routesWithOffEndpointsMuted, toHostRuntimeConfiguration } from "./runtime";

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
