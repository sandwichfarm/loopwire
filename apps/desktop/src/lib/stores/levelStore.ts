import { readable, type Readable } from "svelte/store";

/**
 * Per-port audio levels, keyed by `${endpointId}:${channelIndex}` (1-based).
 * Values are 0–1 linear meter levels.
 *
 * Loopwire currently ships no per-port level stream from the PipeWire adapter
 * (documented capability gap). Meters render their silent track when a port
 * has no level entry — the UI never simulates host-owned audio state.
 */
export type PortLevels = ReadonlyMap<string, number>;

export interface LevelProvider {
  subscribe(listener: (levels: PortLevels) => void): () => void;
}

export const silentLevelProvider: LevelProvider = {
  subscribe(listener) {
    listener(new Map());
    return () => undefined;
  }
};

export function portLevelKey(endpointId: string, channelIndex: number): string {
  return `${endpointId}:${channelIndex}`;
}

export function levelFor(levels: PortLevels, endpointId: string, channelIndex: number): number {
  return levels.get(portLevelKey(endpointId, channelIndex)) ?? 0;
}

export function peakLevelFor(levels: PortLevels, endpointId: string, channels: number): number {
  let peak = 0;
  for (let channel = 1; channel <= channels; channel += 1) {
    peak = Math.max(peak, levelFor(levels, endpointId, channel));
  }

  return peak;
}

export function createLevelStore(provider: LevelProvider = silentLevelProvider): Readable<PortLevels> {
  return readable<PortLevels>(new Map(), (set) => provider.subscribe(set));
}
