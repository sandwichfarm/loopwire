export const schemaVersion = 1 as const;

export const audioBackendKinds = ["pipewire", "pulseaudio", "jack", "alsa"] as const;

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

export interface AudioEndpoint {
  readonly id: string;
  readonly label: string;
  readonly role: EndpointRole;
  readonly channels: number;
  readonly deviceName?: string;
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
  readonly version: typeof schemaVersion;
  readonly selectedBackend?: AudioBackendKind;
  readonly configurations: readonly LoopwireConfiguration[];
  readonly activeConfigurationId?: string;
  readonly hiddenMonitorIds: readonly string[];
  readonly appliedAt?: string;
}
