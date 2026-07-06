import { describe, expect, it } from "vitest";
import type { LoopwireConfiguration } from "@loopwire/core";
import { cablePath, channelCablesFor, dragConnection, portId } from "./geometry";

describe("cablePath", () => {
  it("draws a straight line when rows align", () => {
    expect(cablePath({ x: 10, y: 40 }, { x: 200, y: 40 })).toBe("M 10 40 L 200 40");
  });

  it("draws a horizontal-tangent bezier otherwise", () => {
    const path = cablePath({ x: 0, y: 0 }, { x: 100, y: 80 });
    expect(path).toBe("M 0 0 C 40 0, 60 80, 100 80");
  });

  it("keeps a minimum bend for short spans", () => {
    const path = cablePath({ x: 0, y: 0 }, { x: 10, y: 50 });
    expect(path).toBe("M 0 0 C 24 0, -14 50, 10 50");
  });
});

describe("channelCablesFor", () => {
  const configuration: LoopwireConfiguration = {
    id: "device",
    name: "Device",
    description: "",
    inputs: [
      { id: "mic", label: "Mic", role: "input", channels: 1 },
      { id: "app", label: "App", role: "input", channels: 2 }
    ],
    outputs: [{ id: "bus", label: "Channels 1 & 2", role: "output", channels: 2 }],
    monitors: [{ id: "phones", label: "Headphones", role: "monitor", channels: 2 }],
    routes: [
      { id: "mic-bus", from: "mic", to: "bus", gain: 1, muted: false },
      { id: "app-bus", from: "app", to: "bus", gain: 1, muted: false },
      { id: "bus-phones", from: "bus", to: "phones", gain: 1, muted: false }
    ],
    updatedAt: ""
  };

  it("expands routes into per-channel cables (1→1, 2→2)", () => {
    const cables = channelCablesFor(configuration);

    expect(cables.filter((cable) => cable.routeId === "mic-bus")).toHaveLength(1);
    expect(cables.filter((cable) => cable.routeId === "app-bus")).toHaveLength(2);
    expect(cables.filter((cable) => cable.routeId === "bus-phones")).toHaveLength(2);

    const appCables = cables.filter((cable) => cable.routeId === "app-bus");
    expect(appCables[0]).toMatchObject({ fromPort: portId("app", 1, "out"), toPort: portId("bus", 1, "in") });
    expect(appCables[1]).toMatchObject({ fromPort: portId("app", 2, "out"), toPort: portId("bus", 2, "in") });
  });

  it("skips routes whose endpoints are missing", () => {
    const broken = { ...configuration, routes: [{ id: "x", from: "gone", to: "bus", gain: 1, muted: false }] };
    expect(channelCablesFor(broken)).toHaveLength(0);
  });
});

describe("dragConnection", () => {
  it("connects source out to bus in, either drag direction", () => {
    const source = { endpointId: "mic", role: "source-out" as const };
    const bus = { endpointId: "bus", role: "bus-in" as const };

    expect(dragConnection(source, bus)).toEqual({ from: "mic", to: "bus" });
    expect(dragConnection(bus, source)).toEqual({ from: "mic", to: "bus" });
  });

  it("connects bus out to monitor in", () => {
    expect(
      dragConnection({ endpointId: "bus", role: "bus-out" }, { endpointId: "phones", role: "monitor-in" })
    ).toEqual({ from: "bus", to: "phones" });
  });

  it("rejects incompatible pairs", () => {
    expect(dragConnection({ endpointId: "mic", role: "source-out" }, { endpointId: "phones", role: "monitor-in" })).toBeNull();
    expect(dragConnection({ endpointId: "a", role: "bus-in" }, { endpointId: "b", role: "monitor-in" })).toBeNull();
    expect(dragConnection({ endpointId: "a", role: "source-out" }, { endpointId: "b", role: "bus-out" })).toBeNull();
  });
});
