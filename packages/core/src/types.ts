export const schemaVersion = 2 as const;
export const legacySchemaVersionV1 = 1 as const;

export const audioBackendKinds = ["pipewire", "pulseaudio", "jack", "alsa", "dsp"] as const;

export type AudioBackendKind = (typeof audioBackendKinds)[number];

export type BackendAvailability = "available" | "unavailable";

export interface BackendCandidate {
  readonly kind: AudioBackendKind;
  readonly displayName: string;
  readonly availability: BackendAvailability;
  readonly priority: number;
  readonly reason?: string;
}

export type BackendDecision =
  | {
      readonly mode: "none";
      readonly reason: string;
    }
  | {
      readonly mode: "auto";
      readonly backend: BackendCandidate;
      readonly reason: string;
    }
  | {
      readonly mode: "prompt";
      readonly candidates: readonly BackendCandidate[];
      readonly reason: string;
    };

export type EndpointRole = "input" | "output" | "monitor";

export const endpointKinds = ["app", "capture", "system", "pass-thru"] as const;

/** Source classification: app stream, capture hardware, system source, or Loopwire pass-thru. */
export type EndpointKind = (typeof endpointKinds)[number];

export interface AudioEndpoint {
  readonly id: string;
  readonly label: string;
  readonly role: EndpointRole;
  readonly channels: number;
  readonly deviceName?: string;
  /** Source kind from enumeration. Absent for legacy states and unclassified sources. */
  readonly kind?: EndpointKind;
  /** Defaults to true when absent (schema v1 states have no per-endpoint switch). */
  readonly enabled?: boolean;
  /** 0–1 configured endpoint volume. Defaults to 1 when absent. */
  readonly volume?: number;
  /** App-capture sources only: mute host playback while Loopwire captures. Defaults to false. */
  readonly muteWhenCapturing?: boolean;
}

export interface AudioRoute {
  readonly id: string;
  readonly from: string;
  readonly to: string;
  readonly gain: number;
  readonly muted: boolean;
}

export interface LoopwireConfiguration {
  readonly id: string;
  readonly name: string;
  readonly description: string;
  readonly inputs: readonly AudioEndpoint[];
  readonly outputs: readonly AudioEndpoint[];
  readonly monitors: readonly AudioEndpoint[];
  readonly routes: readonly AudioRoute[];
  readonly updatedAt: string;
  /** Whole-device switch. Defaults to true when absent (schema v1). */
  readonly enabled?: boolean;
  /** Device-level mute. Defaults to false when absent. */
  readonly muted?: boolean;
  /** 0–1 configured device volume. Defaults to 1 when absent. */
  readonly volume?: number;
}

export interface LoopwireState {
  readonly version: typeof schemaVersion;
  readonly selectedBackend?: AudioBackendKind;
  readonly configurations: readonly LoopwireConfiguration[];
  readonly activeConfigurationId?: string;
  readonly hiddenMonitorIds: readonly string[];
  readonly appliedAt?: string;
}

export interface PersistedStateV1 {
  readonly version: typeof legacySchemaVersionV1;
  readonly selectedBackend?: AudioBackendKind;
  readonly configurations: readonly LoopwireConfiguration[];
  readonly activeConfigurationId?: string;
  readonly hiddenMonitorIds: readonly string[];
  readonly appliedAt?: string;
}

export interface PersistedStateV2 {
  readonly version: typeof schemaVersion;
  readonly selectedBackend?: AudioBackendKind;
  readonly configurations: readonly LoopwireConfiguration[];
  readonly activeConfigurationId?: string;
  readonly hiddenMonitorIds: readonly string[];
  readonly appliedAt?: string;
}
