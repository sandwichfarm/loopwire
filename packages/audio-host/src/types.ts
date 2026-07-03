export type AudioBackendKind = "pipewire" | "pulseaudio" | "jack" | "alsa";

export type BackendAvailability = "available" | "unavailable";

export interface BackendCandidate {
  readonly kind: AudioBackendKind;
  readonly displayName: string;
  readonly availability: BackendAvailability;
  readonly priority: number;
  readonly reason?: string;
}

export type CommandErrorCode = "missing" | "timeout" | "failed";

export interface CommandResult {
  readonly command: string;
  readonly args: readonly string[];
  readonly exitCode: number;
  readonly stdout: string;
  readonly stderr: string;
  readonly errorCode?: CommandErrorCode;
}

export interface CommandRunner {
  run(command: string, args: readonly string[], options?: CommandRunOptions): Promise<CommandResult>;
}

export interface CommandRunOptions {
  readonly timeoutMs?: number;
}

export type CapabilityState = "implemented" | "planned" | "unavailable";

export type BackendTransport = "native" | "compatibility" | "bridge" | "hardware";

export type MixingControlScope = "graph-edge" | "stream" | "link-only" | "unavailable";

export interface BackendOperations {
  readonly detect: CapabilityState;
  readonly enumerateDevices: CapabilityState;
  readonly createVirtualDevice: CapabilityState;
  readonly routeAudio: CapabilityState;
  readonly monitorAudio: CapabilityState;
  readonly apply: CapabilityState;
  readonly verify: CapabilityState;
  readonly rollback: CapabilityState;
}

export interface BackendDiagnostic {
  readonly level: "info" | "warning" | "error";
  readonly code: string;
  readonly message: string;
}

export interface BackendMixingSemantics {
  readonly controlScope: MixingControlScope;
  readonly supportsPerEdgeGain: boolean;
  readonly supportsPerEdgeMute: boolean;
  readonly warning?: string;
}

export interface CommandProbe {
  readonly command: string;
  readonly args: readonly string[];
  readonly exitCode: number;
  readonly available: boolean;
  readonly summary: string;
}

export interface BackendCapabilityReport {
  readonly kind: AudioBackendKind;
  readonly displayName: string;
  readonly availability: BackendAvailability;
  readonly priority: number;
  readonly transport: BackendTransport;
  readonly version?: string;
  readonly serverName?: string;
  readonly operations: BackendOperations;
  readonly mixing: BackendMixingSemantics;
  readonly gaps: readonly string[];
  readonly diagnostics: readonly BackendDiagnostic[];
  readonly commands: readonly CommandProbe[];
}

export interface AudioBackendDetectionReport {
  readonly generatedAt: string;
  readonly platform: NodeJS.Platform;
  readonly reports: readonly BackendCapabilityReport[];
  readonly candidates: readonly BackendCandidate[];
}

export interface AudioPlaybackDevice {
  readonly backend: AudioBackendKind;
  readonly deviceName: string;
  readonly label: string;
  readonly detail?: string;
}

export interface AudioPlaybackDeviceReport {
  readonly generatedAt: string;
  readonly backend: AudioBackendKind;
  readonly devices: readonly AudioPlaybackDevice[];
  readonly diagnostics: readonly BackendDiagnostic[];
  readonly commands: readonly CommandProbe[];
}

export interface AudioInputSource {
  readonly backend: AudioBackendKind;
  readonly sourceId: string;
  readonly sourceName: string;
  readonly label: string;
  readonly detail?: string;
  readonly channels: number;
}

export interface AudioInputSourceReport {
  readonly generatedAt: string;
  readonly backend: AudioBackendKind;
  readonly sources: readonly AudioInputSource[];
  readonly diagnostics: readonly BackendDiagnostic[];
  readonly commands: readonly CommandProbe[];
}
