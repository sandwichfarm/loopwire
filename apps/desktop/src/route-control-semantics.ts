import type { AudioBackendKind } from "@loopwire/core";

export type RouteControlMode = "edge" | "stream" | "link" | "planned";
export type RouteControlCapabilityState = "implemented" | "planned" | "unavailable";
export type RouteControlScope = "graph-edge" | "stream" | "link-only" | "unavailable";

export interface RouteControlMixingSemantics {
  readonly controlScope: RouteControlScope;
  readonly supportsPerEdgeGain: boolean;
  readonly supportsPerEdgeMute: boolean;
  readonly warning?: string;
}

export interface RouteControlBackendCapability {
  readonly kind: AudioBackendKind;
  readonly displayName: string;
  readonly mixing?: RouteControlMixingSemantics;
  readonly operations?: {
    readonly createVirtualDevice?: RouteControlCapabilityState;
  };
}

export interface RouteControlSemantics {
  readonly mode: RouteControlMode;
  readonly badge: string;
  readonly message: string;
}

export function routeGainEditingLockedForBackend(
  backend: AudioBackendKind | undefined,
  capability?: RouteControlBackendCapability
): boolean {
  if (backend && capability?.kind === backend && capability.mixing) {
    return capability.mixing.controlScope === "link-only" && !capability.mixing.supportsPerEdgeGain;
  }

  return backend === "pipewire" || backend === "jack";
}

export function describeSelectedRouteControlSemantics(
  backend: AudioBackendKind | undefined,
  decisionMode: "auto" | "none" | "prompt",
  capability?: RouteControlBackendCapability
): RouteControlSemantics {
  if (!backend && decisionMode === "prompt") {
    return {
      mode: "planned",
      badge: "Choose",
      message: "Choose a detected backend to see host route-control semantics."
    };
  }

  if (!backend && decisionMode === "none") {
    return {
      mode: "planned",
      badge: "No backend",
      message: "No Linux audio backend probes succeeded; route controls stay in app preview."
    };
  }

  if (backend) {
    return describeRouteControlSemantics(backend, capability);
  }

  return {
    mode: "planned",
    badge: "Choose",
    message: "Choose a detected backend to see host route-control semantics."
  };
}

export function describeRouteControlSemantics(
  backend: AudioBackendKind,
  capability?: RouteControlBackendCapability
): RouteControlSemantics {
  if (backend === "dsp") {
    return {
      mode: "planned",
      badge: "DSP",
      message:
        "DSP provider controls are available through provider-backed background restore; desktop live apply needs " +
        "provider command settings first."
    };
  }

  if (capability?.kind === backend && capability.mixing) {
    return describeDetectedRouteControlSemantics(capability);
  }

  if (backend === "pulseaudio") {
    return {
      mode: "stream",
      badge: "Stream",
      message: "PulseAudio controls whole matching streams; each source can route to only one output."
    };
  }

  if (backend === "pipewire") {
    return {
      mode: "link",
      badge: "Link",
      message: "Native PipeWire applies route mute by disconnecting links; per-edge gain remains planned."
    };
  }

  if (backend === "jack") {
    return {
      mode: "link",
      badge: "Link",
      message: "Native JACK applies route mute by disconnecting connections; per-edge gain remains planned."
    };
  }

  return {
    mode: "planned",
    badge: "Planned",
    message: `${backend.toUpperCase()} route apply and per-edge controls are not implemented yet.`
  };
}

function describeDetectedRouteControlSemantics(capability: RouteControlBackendCapability): RouteControlSemantics {
  const mixing = capability.mixing;

  if (!mixing) {
    return describeRouteControlSemantics(capability.kind);
  }

  if (mixing.controlScope === "graph-edge") {
    return {
      mode: "edge",
      badge: "Graph",
      message: `${capability.displayName} applies independent per-route gain and mute at the graph edge.`
    };
  }

  if (mixing.controlScope === "stream") {
    return {
      mode: "stream",
      badge: "Stream",
      message: mixing.warning ?? `${capability.displayName} controls whole matching streams.`
    };
  }

  if (mixing.controlScope === "link-only") {
    return {
      mode: "link",
      badge: "Link",
      message: mixing.warning ?? `${capability.displayName} applies mute by disconnecting graph links.`
    };
  }

  return {
    mode: "planned",
    badge: "Planned",
    message: mixing.warning ?? `${capability.displayName} route controls are unavailable.`
  };
}
