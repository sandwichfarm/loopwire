import type { LoopwireConfiguration } from "@loopwire/core";

export interface Point {
  readonly x: number;
  readonly y: number;
}

export type PortSide = "in" | "out";

/** Stable DOM/measurement key for a port dot: endpoint, 1-based channel, side. */
export function portId(endpointId: string, channel: number, side: PortSide): string {
  return `${endpointId}:${channel}:${side}`;
}

/**
 * Horizontal-tangent cable path (visual-system §7): straight when the rows
 * align, otherwise a cubic bezier whose control points sit at ~40% of the
 * horizontal distance so the cable leaves and enters ports horizontally.
 */
export function cablePath(from: Point, to: Point): string {
  if (Math.abs(from.y - to.y) < 0.5) {
    return `M ${round(from.x)} ${round(from.y)} L ${round(to.x)} ${round(to.y)}`;
  }

  const bend = Math.max(24, Math.abs(to.x - from.x) * 0.4);
  return `M ${round(from.x)} ${round(from.y)} C ${round(from.x + bend)} ${round(from.y)}, ${round(to.x - bend)} ${round(
    to.y
  )}, ${round(to.x)} ${round(to.y)}`;
}

function round(value: number): number {
  return Math.round(value * 10) / 10;
}

export interface ChannelCable {
  readonly id: string;
  readonly routeId: string;
  readonly fromPort: string;
  readonly toPort: string;
  /** Ids of the endpoints on both ends, for Off-state dimming. */
  readonly fromEndpointId: string;
  readonly toEndpointId: string;
}

/**
 * Expands endpoint-level `AudioRoute`s into per-channel visual cables
 * (channel 1 → channel 1, 2 → 2, …), matching the reference's auto-cabling.
 * A route between an N-channel and an M-channel endpoint draws min(N, M)
 * cables; selecting or deleting any of them acts on the whole route.
 */
export function channelCablesFor(configuration: LoopwireConfiguration): readonly ChannelCable[] {
  const endpoints = new Map(
    [...configuration.inputs, ...configuration.outputs, ...configuration.monitors].map((endpoint) => [endpoint.id, endpoint])
  );

  return configuration.routes.flatMap((route) => {
    const from = endpoints.get(route.from);
    const to = endpoints.get(route.to);

    if (!from || !to) {
      return [];
    }

    const pairs = Math.min(from.channels, to.channels);
    return Array.from({ length: pairs }, (_, index) => ({
      id: `${route.id}#${index + 1}`,
      routeId: route.id,
      fromPort: portId(from.id, index + 1, "out"),
      toPort: portId(to.id, index + 1, "in"),
      fromEndpointId: from.id,
      toEndpointId: to.id
    }));
  });
}

export type DragPortRole = "source-out" | "bus-in" | "bus-out" | "monitor-in";

export interface DragEndpointInfo {
  readonly endpointId: string;
  readonly role: DragPortRole;
}

/**
 * Cable drags connect an out-port to an in-port one stage downstream:
 * source → bus, or bus → monitor. Everything else is rejected.
 */
export function dragConnection(a: DragEndpointInfo, b: DragEndpointInfo): { readonly from: string; readonly to: string } | null {
  const pair = [a, b] as const;
  const out = pair.find((port) => port.role === "source-out" || port.role === "bus-out");
  const inPort = pair.find((port) => port.role === "bus-in" || port.role === "monitor-in");

  if (!out || !inPort || out === (inPort as DragEndpointInfo)) {
    return null;
  }

  if (out.role === "source-out" && inPort.role !== "bus-in") {
    return null;
  }

  if (out.role === "bus-out" && inPort.role !== "monitor-in") {
    return null;
  }

  return { from: out.endpointId, to: inPort.endpointId };
}
