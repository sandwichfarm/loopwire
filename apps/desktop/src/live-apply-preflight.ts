import type {
  AudioBackendKind,
  AudioEndpoint,
  AudioRoute,
  BackendAvailability,
  LoopwireConfiguration
} from "@loopwire/core";
import { describeJackPortRequirements, type JackPortRequirement } from "@loopwire/audio-host/runtime";

export type LiveApplyCapabilityState = "implemented" | "planned" | "unavailable";
export type LiveApplyMixingControlScope = "graph-edge" | "stream" | "link-only" | "unavailable";

export interface LiveApplyBackendCapability {
  readonly kind: AudioBackendKind;
  readonly displayName: string;
  readonly availability?: BackendAvailability;
  readonly mixing?: {
    readonly controlScope: LiveApplyMixingControlScope;
    readonly supportsPerEdgeGain: boolean;
    readonly supportsPerEdgeMute: boolean;
  };
  readonly operations?: {
    readonly createVirtualDevice?: LiveApplyCapabilityState;
  };
  readonly gaps?: readonly string[];
  readonly diagnostics?: readonly {
    readonly level: "info" | "warning" | "error";
    readonly code: string;
    readonly message: string;
  }[];
}

export interface LiveApplyPreflight {
  readonly ok: boolean;
  readonly mode: "ready" | "blocked";
  readonly badge: string;
  readonly message: string;
  readonly blockers: readonly string[];
}

type BackendDisplayName = (kind: AudioBackendKind) => string;

const defaultBackendDisplayName: BackendDisplayName = (kind) => {
  const labels: Record<AudioBackendKind, string> = {
    pipewire: "PipeWire",
    pulseaudio: "PulseAudio",
    jack: "JACK",
    alsa: "ALSA",
    dsp: "DSP Provider"
  };

  return labels[kind];
};

export function describeLiveApplyPreflight(
  configuration: LoopwireConfiguration,
  backend: AudioBackendKind | undefined,
  displayBackendName: BackendDisplayName = defaultBackendDisplayName,
  capability?: LiveApplyBackendCapability
): LiveApplyPreflight {
  const blockers = liveApplyBlockers(configuration, backend, displayBackendName, capability);

  if (blockers.length === 0) {
    return {
      ok: true,
      mode: "ready",
      badge: "Ready",
      message: backend
        ? `${displayBackendName(backend)} live apply is ready for ${configuration.name}.`
        : "Choose a backend before arming live apply.",
      blockers
    };
  }

  return {
    ok: false,
    mode: "blocked",
    badge: "Blocked",
    message: blockers.length > 1
      ? `Resolve ${blockers.length} blockers before live apply can be armed.`
      : blockers[0] ?? "Live apply is blocked.",
    blockers
  };
}

export function describeConfigurationSwitchPreflight(
  configuration: LoopwireConfiguration,
  backend: AudioBackendKind | undefined,
  capabilities: readonly LiveApplyBackendCapability[],
  displayBackendName: BackendDisplayName = defaultBackendDisplayName
): LiveApplyPreflight {
  return describeLiveApplyPreflight(
    configuration,
    backend,
    displayBackendName,
    capabilities.find((capability) => capability.kind === backend)
  );
}

export function getNativeGainBlockerRoutes(
  configuration: LoopwireConfiguration,
  backend: AudioBackendKind | undefined,
  capability?: LiveApplyBackendCapability
): readonly AudioRoute[] {
  if (backend !== "pipewire" && backend !== "jack") {
    return [];
  }

  if (backendSupportsPerEdgeGain(backend, capability)) {
    return [];
  }

  return configuration.routes.filter((route) => route.gain !== 1);
}

function liveApplyBlockers(
  configuration: LoopwireConfiguration,
  backend: AudioBackendKind | undefined,
  displayBackendName: BackendDisplayName,
  capability?: LiveApplyBackendCapability
): readonly string[] {
  if (!backend) {
    return ["Choose a detected backend before arming live apply."];
  }

  const unavailableBackendBlocker = backendAvailabilityBlocker(backend, displayBackendName, capability);

  if (unavailableBackendBlocker) {
    return [unavailableBackendBlocker];
  }

  if (backend === "alsa") {
    return ["ALSA live apply is not implemented; use PipeWire, PulseAudio, or JACK."];
  }

  if (backend === "dsp" && !backendSupportsPerEdgeGain(backend, capability)) {
    return [
      "DSP provider live apply needs an explicit live provider capability report; use background restore provider " +
        "settings or select PipeWire, PulseAudio, or JACK for desktop live apply."
    ];
  }

  if (backend === "pulseaudio") {
    if (backendSupportsPerEdgeGain(backend, capability)) {
      return [];
    }

    const fanOutRoutes = getPulseAudioFanOutRoutes(configuration);
    return fanOutRoutes.map(
      (routes) =>
        "PulseAudio compatibility can route each source to only one output; adjust " +
        `${formatRouteList(configuration, routes)}.`
    );
  }

  const inputs = new Map(configuration.inputs.map((input) => [input.id, input]));
  const nonUnityGainRoutes = getNativeGainBlockerRoutes(configuration, backend, capability);
  const missingSourceRoutes = configuration.routes.filter((route) => !inputs.get(route.from)?.deviceName?.trim());
  const missingSources = uniqueEndpointsForRoutes(configuration.inputs, missingSourceRoutes, "from");
  const missingJackPorts =
    backend === "jack" && !backendCreatesVirtualDevices(backend, capability)
      ? missingJackPortEndpoints(configuration)
      : [];
  const blockers: string[] = [];

  if (nonUnityGainRoutes.length > 0) {
    blockers.push(
      `${displayBackendName(backend)} live apply needs 100% route gain for ` +
        `${formatRouteList(configuration, nonUnityGainRoutes)}. Use Reset gains, or switch to a ` +
        "graph-edge/DSP-capable backend when one is available."
    );
  }

  if (backend === "pipewire" && missingSourceRoutes.length > 0) {
    blockers.push(
      `${displayBackendName(backend)} live apply needs host source ports for ${formatEndpointList(missingSources)}.`
    );
  }

  if (missingJackPorts.length > 0) {
    blockers.push(
      `JACK live apply needs host bindings to existing JACK ports for ${formatEndpointList(missingJackPorts)}.`
    );
  }

  return blockers;
}

function backendAvailabilityBlocker(
  backend: AudioBackendKind,
  displayBackendName: BackendDisplayName,
  capability?: LiveApplyBackendCapability
): string | undefined {
  if (capability?.kind !== backend || capability.availability !== "unavailable") {
    return undefined;
  }

  return `${displayBackendName(backend)} is unavailable for live apply: ${unavailableBackendReason(capability)}`;
}

function unavailableBackendReason(capability: LiveApplyBackendCapability): string {
  const diagnosticReason = capability.diagnostics?.find((diagnostic) => diagnostic.message.trim())?.message.trim();
  const gapReason = capability.gaps?.find((gap) => gap.trim())?.trim();
  const reason = diagnosticReason ?? gapReason ?? "backend detection reported it as unavailable";

  return reason.endsWith(".") ? reason : `${reason}.`;
}

function backendSupportsPerEdgeGain(
  backend: AudioBackendKind,
  capability?: LiveApplyBackendCapability
): boolean {
  return capability?.kind === backend && capability.mixing?.supportsPerEdgeGain === true;
}

function backendCreatesVirtualDevices(
  backend: AudioBackendKind,
  capability?: LiveApplyBackendCapability
): boolean {
  return capability?.kind === backend && capability.operations?.createVirtualDevice === "implemented";
}

function missingJackPortEndpoints(configuration: LoopwireConfiguration): readonly AudioEndpoint[] {
  const seen = new Set<string>();
  const endpoints: AudioEndpoint[] = [];

  for (const requirement of describeJackPortRequirements(configuration).filter(isLoopwireOwnedJackRequirement)) {
    if (seen.has(requirement.endpointId)) {
      continue;
    }

    const endpoint = findEndpoint(configuration, requirement.endpointId);

    if (!endpoint) {
      continue;
    }

    seen.add(endpoint.id);
    endpoints.push({
      ...endpoint,
      label: `${endpoint.label} (${requirement.deviceName})`
    });
  }

  return endpoints;
}

function isLoopwireOwnedJackRequirement(requirement: JackPortRequirement): boolean {
  return requirement.source === "loopwire-owned";
}

function getPulseAudioFanOutRoutes(configuration: LoopwireConfiguration): readonly (readonly AudioRoute[])[] {
  const routesBySource = new Map<string, AudioRoute[]>();

  for (const route of configuration.routes) {
    routesBySource.set(route.from, [...(routesBySource.get(route.from) ?? []), route]);
  }

  return [...routesBySource.values()].filter((routes) => routes.length > 1);
}

function findEndpoint(configuration: LoopwireConfiguration, endpointId: string): AudioEndpoint | undefined {
  return [...configuration.inputs, ...configuration.outputs, ...configuration.monitors].find(
    (endpoint) => endpoint.id === endpointId
  );
}

function formatRouteList(configuration: LoopwireConfiguration, routes: readonly AudioRoute[]): string {
  const firstRoute = routes[0];
  const secondRoute = routes[1];

  if (!firstRoute) {
    return "the selected routes";
  }

  if (routes.length === 1) {
    return describeRouteLabel(configuration, firstRoute);
  }

  if (routes.length === 2 && secondRoute) {
    return `${describeRouteLabel(configuration, firstRoute)} and ${describeRouteLabel(configuration, secondRoute)}`;
  }

  if (!secondRoute) {
    return describeRouteLabel(configuration, firstRoute);
  }

  if (routes.length === 3 && secondRoute) {
    return `${describeRouteLabel(configuration, firstRoute)}, ${describeRouteLabel(configuration, secondRoute)}, and 1 more route`;
  }

  return `${describeRouteLabel(configuration, firstRoute)}, ${describeRouteLabel(configuration, secondRoute)}, and ` +
    `${routes.length - 2} more routes`;
}

function describeRouteLabel(configuration: LoopwireConfiguration, route: AudioRoute): string {
  return `${endpointLabel(configuration.inputs, route.from)} -> ${endpointLabel(configuration.outputs, route.to)}`;
}

function endpointLabel(endpoints: readonly AudioEndpoint[], endpointId: string): string {
  return endpoints.find((endpoint) => endpoint.id === endpointId)?.label ?? endpointId;
}

function uniqueEndpointsForRoutes(
  endpoints: readonly AudioEndpoint[],
  routes: readonly AudioRoute[],
  side: "from" | "to"
): readonly AudioEndpoint[] {
  const endpointById = new Map(endpoints.map((endpoint) => [endpoint.id, endpoint]));
  const seen = new Set<string>();
  const result: AudioEndpoint[] = [];

  for (const route of routes) {
    const endpointId = route[side];
    const endpoint = endpointById.get(endpointId);

    if (!endpoint || seen.has(endpoint.id)) {
      continue;
    }

    seen.add(endpoint.id);
    result.push(endpoint);
  }

  return result;
}

function formatEndpointList(endpoints: readonly AudioEndpoint[]): string {
  const firstEndpoint = endpoints[0];
  const secondEndpoint = endpoints[1];

  if (!firstEndpoint) {
    return "the selected endpoints";
  }

  if (endpoints.length === 1) {
    return firstEndpoint.label;
  }

  if (endpoints.length === 2 && secondEndpoint) {
    return `${firstEndpoint.label} and ${secondEndpoint.label}`;
  }

  if (!secondEndpoint) {
    return firstEndpoint.label;
  }

  if (endpoints.length === 3 && secondEndpoint) {
    return `${firstEndpoint.label}, ${secondEndpoint.label}, and 1 more endpoint`;
  }

  return `${firstEndpoint.label}, ${secondEndpoint.label}, and ${endpoints.length - 2} more endpoints`;
}
