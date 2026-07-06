import {
  schemaVersion,
  type AudioBackendKind,
  type AudioEndpoint,
  type AudioRoute,
  type LoopwireConfiguration,
  type LoopwireState
} from "./types.js";

const demoTimestamp = "2026-07-03T12:00:00.000Z";

export interface CreateConfigurationInput {
  readonly name: string;
  readonly description?: string;
  readonly inputs?: readonly AudioEndpoint[];
  readonly outputs?: readonly AudioEndpoint[];
  readonly monitors?: readonly AudioEndpoint[];
  readonly routes?: readonly AudioRoute[];
}

export interface UpdateConfigurationInput {
  readonly name?: string;
  readonly description?: string;
  readonly inputs?: readonly AudioEndpoint[];
  readonly outputs?: readonly AudioEndpoint[];
  readonly monitors?: readonly AudioEndpoint[];
  readonly routes?: readonly AudioRoute[];
}

export interface AddInputSourceInput {
  readonly id?: string;
  readonly label: string;
  readonly channels?: number;
  readonly deviceName?: string;
  readonly routeToOutputId?: string;
  readonly gain?: number;
}

export interface AddOutputBusInput {
  readonly id?: string;
  readonly label: string;
  readonly channels?: number;
  readonly deviceName?: string;
  readonly routeExistingInputs?: boolean | "host-device";
  readonly gain?: number;
}

export interface AddMonitorInput {
  readonly id?: string;
  readonly label: string;
  readonly channels?: number;
  readonly deviceName?: string;
}

export interface AddRouteInput {
  readonly id?: string;
  readonly from: string;
  readonly to: string;
  readonly gain?: number;
}

export interface ConfigurationMutationResult {
  readonly state: LoopwireState;
  readonly configuration: LoopwireConfiguration;
}

export interface DeleteConfigurationResult {
  readonly state: LoopwireState;
  readonly removedConfiguration: LoopwireConfiguration;
}

export function createEmptyState(now = demoTimestamp): LoopwireState {
  return {
    version: schemaVersion,
    configurations: [],
    hiddenMonitorIds: [],
    appliedAt: now
  };
}

export function createDefaultState(now = demoTimestamp): LoopwireState {
  const configurations = createDefaultConfigurations(now);
  const activeConfigurationId = configurations[0]?.id ?? "";

  return {
    version: schemaVersion,
    configurations,
    activeConfigurationId,
    hiddenMonitorIds: [],
    appliedAt: now
  };
}

export function createConfiguration(
  state: LoopwireState,
  input: CreateConfigurationInput,
  updatedAt: string
): ConfigurationMutationResult {
  const name = normalizeConfigurationName(input.name);
  const configuration: LoopwireConfiguration = {
    id: makeUniqueConfigurationId(slugify(name), state.configurations),
    name,
    description: input.description?.trim() ?? "",
    inputs: input.inputs ?? [],
    outputs: input.outputs ?? [createDefaultOutput()],
    monitors: input.monitors ?? [],
    routes: input.routes ?? [],
    updatedAt
  };

  return insertConfiguration(state, configuration, updatedAt);
}

export function updateConfiguration(
  state: LoopwireState,
  configurationId: string,
  input: UpdateConfigurationInput,
  updatedAt: string
): ConfigurationMutationResult {
  const existing = getConfigurationById(state, configurationId);
  const configuration: LoopwireConfiguration = {
    ...existing,
    ...(input.name !== undefined ? { name: normalizeConfigurationName(input.name) } : {}),
    ...(input.description !== undefined ? { description: input.description.trim() } : {}),
    ...(input.inputs !== undefined ? { inputs: input.inputs } : {}),
    ...(input.outputs !== undefined ? { outputs: input.outputs } : {}),
    ...(input.monitors !== undefined ? { monitors: input.monitors } : {}),
    ...(input.routes !== undefined ? { routes: input.routes } : {}),
    updatedAt
  };

  validateConfigurationGraph(configuration);

  return {
    state: {
      ...state,
      configurations: state.configurations.map((candidate) => (candidate.id === configurationId ? configuration : candidate))
    },
    configuration
  };
}

export function addInputSourceToConfiguration(
  state: LoopwireState,
  configurationId: string,
  input: AddInputSourceInput,
  updatedAt: string
): ConfigurationMutationResult {
  const configuration = getConfigurationById(state, configurationId);
  const sourceId = slugify(input.id ?? input.label) || "source";
  const label = input.label.trim();

  if (!label) {
    throw new Error("Input source label is required.");
  }

  assertEndpointAvailable(configuration, sourceId, label, "Input source");

  const outputId = input.routeToOutputId ?? configuration.outputs[0]?.id;
  const output = configuration.outputs.find((candidate) => candidate.id === outputId);

  if (!output) {
    throw new Error(`Unknown Loopwire output: ${outputId ?? "none"}`);
  }

  const gain = input.gain ?? 1;
  if (!isValidRouteGain(gain)) {
    throw new Error("Route gain must be between 0 and 1.");
  }

  const source: AudioEndpoint = {
    id: sourceId,
    label,
    role: "input",
    channels: input.channels ?? output.channels,
    ...(input.deviceName ? { deviceName: input.deviceName.trim() } : {})
  };
  const route: AudioRoute = {
    id: makeUniqueRouteId(`${source.id}-${output.id}`, configuration.routes),
    from: source.id,
    to: output.id,
    gain,
    muted: false
  };

  return updateConfiguration(
    state,
    configurationId,
    {
      inputs: [...configuration.inputs, source],
      routes: [...configuration.routes, route]
    },
    updatedAt
  );
}

export function addOutputBusToConfiguration(
  state: LoopwireState,
  configurationId: string,
  input: AddOutputBusInput,
  updatedAt: string
): ConfigurationMutationResult {
  const configuration = getConfigurationById(state, configurationId);
  const outputId = slugify(input.id ?? input.label) || "output";
  const label = input.label.trim();

  if (!label) {
    throw new Error("Output bus label is required.");
  }

  assertEndpointAvailable(configuration, outputId, label, "Output bus");

  const gain = input.gain ?? 1;
  if (!isValidRouteGain(gain)) {
    throw new Error("Route gain must be between 0 and 1.");
  }

  const fallbackChannels = configuration.outputs[0]?.channels ?? 2;
  const output: AudioEndpoint = {
    id: outputId,
    label,
    role: "output",
    channels: input.channels ?? fallbackChannels,
    ...(input.deviceName ? { deviceName: input.deviceName.trim() } : {})
  };
  const routedSources = selectExistingInputsForOutputRoute(configuration.inputs, input.routeExistingInputs);
  const routes =
    routedSources.length === 0
      ? configuration.routes
      : [
          ...configuration.routes,
          ...routedSources.map((source) => ({
            id: makeUniqueRouteId(`${source.id}-${output.id}`, configuration.routes),
            from: source.id,
            to: output.id,
            gain,
            muted: false
          }))
        ];

  return updateConfiguration(
    state,
    configurationId,
    {
      outputs: [...configuration.outputs, output],
      routes
    },
    updatedAt
  );
}

function selectExistingInputsForOutputRoute(
  inputs: readonly AudioEndpoint[],
  mode: AddOutputBusInput["routeExistingInputs"]
): readonly AudioEndpoint[] {
  if (mode === false) {
    return [];
  }

  if (mode === "host-device") {
    return inputs.filter((source) => Boolean(source.deviceName?.trim()));
  }

  return inputs;
}

export function addMonitorToConfiguration(
  state: LoopwireState,
  configurationId: string,
  input: AddMonitorInput,
  updatedAt: string
): ConfigurationMutationResult {
  const configuration = getConfigurationById(state, configurationId);
  const monitorId = slugify(input.id ?? input.label) || "monitor";
  const label = input.label.trim();

  if (!label) {
    throw new Error("Monitor label is required.");
  }

  assertEndpointAvailable(configuration, monitorId, label, "Monitor");

  const fallbackChannels = configuration.outputs[0]?.channels ?? 2;
  const monitor: AudioEndpoint = {
    id: monitorId,
    label,
    role: "monitor",
    channels: input.channels ?? fallbackChannels,
    ...(input.deviceName ? { deviceName: input.deviceName.trim() } : {})
  };

  return updateConfiguration(
    state,
    configurationId,
    {
      monitors: [...configuration.monitors, monitor]
    },
    updatedAt
  );
}

export function removeInputSourceFromConfiguration(
  state: LoopwireState,
  configurationId: string,
  sourceId: string,
  updatedAt: string
): ConfigurationMutationResult {
  const configuration = getConfigurationById(state, configurationId);
  const source = configuration.inputs.find((candidate) => candidate.id === sourceId);

  if (!source) {
    throw new Error(`Unknown Loopwire input: ${sourceId}`);
  }

  return updateConfiguration(
    state,
    configurationId,
    {
      inputs: configuration.inputs.filter((candidate) => candidate.id !== source.id),
      routes: configuration.routes.filter((route) => route.from !== source.id)
    },
    updatedAt
  );
}

export function removeOutputBusFromConfiguration(
  state: LoopwireState,
  configurationId: string,
  outputId: string,
  updatedAt: string
): ConfigurationMutationResult {
  const configuration = getConfigurationById(state, configurationId);
  const output = configuration.outputs.find((candidate) => candidate.id === outputId);

  if (!output) {
    throw new Error(`Unknown Loopwire output: ${outputId}`);
  }

  if (configuration.outputs.length <= 1) {
    throw new Error("Configuration must keep at least one output.");
  }

  return updateConfiguration(
    state,
    configurationId,
    {
      outputs: configuration.outputs.filter((candidate) => candidate.id !== output.id),
      routes: configuration.routes.filter((route) => route.to !== output.id && route.from !== output.id)
    },
    updatedAt
  );
}

export function removeMonitorFromConfiguration(
  state: LoopwireState,
  configurationId: string,
  monitorId: string,
  updatedAt: string
): ConfigurationMutationResult {
  const configuration = getConfigurationById(state, configurationId);
  const monitor = configuration.monitors.find((candidate) => candidate.id === monitorId);

  if (!monitor) {
    throw new Error(`Unknown Loopwire monitor: ${monitorId}`);
  }

  const result = updateConfiguration(
    state,
    configurationId,
    {
      monitors: configuration.monitors.filter((candidate) => candidate.id !== monitor.id),
      routes: configuration.routes.filter((route) => route.to !== monitor.id)
    },
    updatedAt
  );

  return {
    state: setMonitorHidden(result.state, configurationId, monitor.id, false),
    configuration: result.configuration
  };
}

export function addRouteToConfiguration(
  state: LoopwireState,
  configurationId: string,
  input: AddRouteInput,
  updatedAt: string
): ConfigurationMutationResult {
  const configuration = getConfigurationById(state, configurationId);
  const source =
    configuration.inputs.find((candidate) => candidate.id === input.from) ??
    configuration.outputs.find((candidate) => candidate.id === input.from);
  const output =
    source?.role === "output"
      ? configuration.monitors.find((candidate) => candidate.id === input.to)
      : configuration.outputs.find((candidate) => candidate.id === input.to);

  if (!source) {
    throw new Error(`Unknown Loopwire input: ${input.from}`);
  }

  if (!output) {
    throw new Error(
      source.role === "output" ? `Unknown Loopwire monitor: ${input.to}` : `Unknown Loopwire output: ${input.to}`
    );
  }

  if (configuration.routes.some((route) => route.from === source.id && route.to === output.id)) {
    throw new Error(`Route already exists: ${source.label} to ${output.label}`);
  }

  const gain = input.gain ?? 1;
  if (!isValidRouteGain(gain)) {
    throw new Error("Route gain must be between 0 and 1.");
  }

  const route: AudioRoute = {
    id: makeUniqueRouteId(input.id ?? `${source.id}-${output.id}`, configuration.routes),
    from: source.id,
    to: output.id,
    gain,
    muted: false
  };

  return updateConfiguration(
    state,
    configurationId,
    {
      routes: [...configuration.routes, route]
    },
    updatedAt
  );
}

export function removeRouteFromConfiguration(
  state: LoopwireState,
  configurationId: string,
  routeId: string,
  updatedAt: string
): ConfigurationMutationResult {
  const configuration = getConfigurationById(state, configurationId);

  if (!configuration.routes.some((route) => route.id === routeId)) {
    throw new Error(`Unknown Loopwire route: ${routeId}`);
  }

  return updateConfiguration(
    state,
    configurationId,
    {
      routes: configuration.routes.filter((route) => route.id !== routeId)
    },
    updatedAt
  );
}

export function duplicateConfiguration(
  state: LoopwireState,
  configurationId: string,
  updatedAt: string
): ConfigurationMutationResult {
  const source = getConfigurationById(state, configurationId);
  const configuration: LoopwireConfiguration = {
    ...source,
    id: makeUniqueConfigurationId(`${source.id}-copy`, state.configurations),
    name: `${source.name} Copy`,
    updatedAt
  };

  return insertConfiguration(state, configuration, updatedAt);
}

/**
 * Removes a configuration and permits an empty device list (unlike
 * {@link deleteConfiguration}, which protects the legacy at-least-one invariant).
 */
export function removeConfiguration(state: LoopwireState, configurationId: string, appliedAt: string): DeleteConfigurationResult {
  const removedConfiguration = getConfigurationById(state, configurationId);
  const configurations = state.configurations.filter((configuration) => configuration.id !== configurationId);
  const activeConfigurationId =
    state.activeConfigurationId === configurationId ? configurations[0]?.id : state.activeConfigurationId;
  const { activeConfigurationId: _previousActiveId, ...rest } = state;

  return {
    state: {
      ...rest,
      configurations,
      ...(activeConfigurationId ? { activeConfigurationId } : {}),
      ...(state.activeConfigurationId === configurationId ? { appliedAt } : {})
    },
    removedConfiguration
  };
}

export function deleteConfiguration(state: LoopwireState, configurationId: string, appliedAt: string): DeleteConfigurationResult {
  if (state.configurations.length <= 1) {
    throw new Error("Loopwire must keep at least one configuration.");
  }

  const removedConfiguration = getConfigurationById(state, configurationId);
  const configurations = state.configurations.filter((configuration) => configuration.id !== configurationId);
  const activeConfigurationId =
    state.activeConfigurationId === configurationId ? configurations[0]?.id : state.activeConfigurationId;

  if (!activeConfigurationId) {
    throw new Error("Loopwire must keep an active configuration.");
  }

  return {
    state: {
      ...state,
      configurations,
      activeConfigurationId,
      ...(state.activeConfigurationId === configurationId ? { appliedAt } : {})
    },
    removedConfiguration
  };
}

export function setRouteGain(
  state: LoopwireState,
  configurationId: string,
  routeId: string,
  gain: number,
  updatedAt: string
): ConfigurationMutationResult {
  if (!isValidRouteGain(gain)) {
    throw new Error("Route gain must be between 0 and 1.");
  }

  return updateRoute(state, configurationId, routeId, { gain }, updatedAt);
}

export function setRouteMuted(
  state: LoopwireState,
  configurationId: string,
  routeId: string,
  muted: boolean,
  updatedAt: string
): ConfigurationMutationResult {
  return updateRoute(state, configurationId, routeId, { muted }, updatedAt);
}

export function insertConfiguration(
  state: LoopwireState,
  configuration: LoopwireConfiguration,
  updatedAt: string
): ConfigurationMutationResult {
  const nextConfiguration = {
    ...configuration,
    id: makeUniqueConfigurationId(configuration.id || slugify(configuration.name), state.configurations),
    updatedAt
  };

  validateConfigurationGraph(nextConfiguration);

  return {
    state: {
      ...state,
      configurations: [...state.configurations, nextConfiguration]
    },
    configuration: nextConfiguration
  };
}

export function activateConfiguration(
  state: LoopwireState,
  configurationId: string,
  appliedAt: string
): LoopwireState {
  assertConfigurationExists(state, configurationId);

  return {
    ...state,
    activeConfigurationId: configurationId,
    appliedAt
  };
}

export function setSelectedBackend(state: LoopwireState, selectedBackend: AudioBackendKind): LoopwireState {
  return {
    ...state,
    selectedBackend
  };
}

export function setEndpointDeviceName(
  state: LoopwireState,
  configurationId: string,
  endpointId: string,
  deviceName: string,
  updatedAt: string
): ConfigurationMutationResult {
  const configuration = getConfigurationById(state, configurationId);
  const endpoint = [...configuration.inputs, ...configuration.outputs, ...configuration.monitors].find(
    (candidate) => candidate.id === endpointId
  );

  if (!endpoint) {
    throw new Error(`Unknown Loopwire endpoint: ${endpointId}`);
  }

  const updateEndpoint = (candidate: AudioEndpoint): AudioEndpoint => {
    if (candidate.id !== endpoint.id) {
      return candidate;
    }

    const normalizedDeviceName = deviceName.trim();

    if (!normalizedDeviceName) {
      const { deviceName: _deviceName, ...rest } = candidate;
      return rest;
    }

    return { ...candidate, deviceName: normalizedDeviceName };
  };

  return updateConfiguration(
    state,
    configurationId,
    {
      inputs: configuration.inputs.map(updateEndpoint),
      outputs: configuration.outputs.map(updateEndpoint),
      monitors: configuration.monitors.map(updateEndpoint)
    },
    updatedAt
  );
}

export function setMonitorHidden(
  state: LoopwireState,
  configurationId: string,
  monitorId: string,
  hidden: boolean
): LoopwireState {
  assertConfigurationExists(state, configurationId);

  const hiddenMonitorIds = new Set(state.hiddenMonitorIds);
  const scopedId = monitorVisibilityId(configurationId, monitorId);
  hiddenMonitorIds.delete(monitorId);

  if (hidden) {
    hiddenMonitorIds.add(scopedId);
  } else {
    hiddenMonitorIds.delete(scopedId);
  }

  return {
    ...state,
    hiddenMonitorIds: [...hiddenMonitorIds].toSorted()
  };
}

export function setConfigurationEnabled(
  state: LoopwireState,
  configurationId: string,
  enabled: boolean,
  updatedAt: string
): ConfigurationMutationResult {
  return patchConfigurationControls(state, configurationId, { enabled }, updatedAt);
}

export function setConfigurationMuted(
  state: LoopwireState,
  configurationId: string,
  muted: boolean,
  updatedAt: string
): ConfigurationMutationResult {
  return patchConfigurationControls(state, configurationId, { muted }, updatedAt);
}

export function setConfigurationVolume(
  state: LoopwireState,
  configurationId: string,
  volume: number,
  updatedAt: string
): ConfigurationMutationResult {
  if (!isValidRouteGain(volume)) {
    throw new Error("Device volume must be between 0 and 1.");
  }

  return patchConfigurationControls(state, configurationId, { volume }, updatedAt);
}

export function setEndpointEnabled(
  state: LoopwireState,
  configurationId: string,
  endpointId: string,
  enabled: boolean,
  updatedAt: string
): ConfigurationMutationResult {
  return patchEndpoint(state, configurationId, endpointId, { enabled }, updatedAt);
}

export function setEndpointVolume(
  state: LoopwireState,
  configurationId: string,
  endpointId: string,
  volume: number,
  updatedAt: string
): ConfigurationMutationResult {
  if (!isValidRouteGain(volume)) {
    throw new Error("Endpoint volume must be between 0 and 1.");
  }

  return patchEndpoint(state, configurationId, endpointId, { volume }, updatedAt);
}

export function setEndpointMuteWhenCapturing(
  state: LoopwireState,
  configurationId: string,
  endpointId: string,
  muteWhenCapturing: boolean,
  updatedAt: string
): ConfigurationMutationResult {
  const configuration = getConfigurationById(state, configurationId);

  if (!configuration.inputs.some((candidate) => candidate.id === endpointId)) {
    throw new Error(`Mute-when-capturing only applies to input sources: ${endpointId}`);
  }

  return patchEndpoint(state, configurationId, endpointId, { muteWhenCapturing }, updatedAt);
}

export function isConfigurationEnabled(configuration: LoopwireConfiguration): boolean {
  return configuration.enabled !== false;
}

export function isConfigurationMuted(configuration: LoopwireConfiguration): boolean {
  return configuration.muted === true;
}

export function configurationVolume(configuration: LoopwireConfiguration): number {
  return configuration.volume ?? 1;
}

export function isEndpointEnabled(endpoint: AudioEndpoint): boolean {
  return endpoint.enabled !== false;
}

export function endpointVolume(endpoint: AudioEndpoint): number {
  return endpoint.volume ?? 1;
}

export function findActiveConfiguration(state: LoopwireState): LoopwireConfiguration | undefined {
  const activeId = state.activeConfigurationId ?? state.configurations[0]?.id;
  return state.configurations.find((candidate) => candidate.id === activeId);
}

export function getActiveConfiguration(state: LoopwireState): LoopwireConfiguration {
  const activeId = state.activeConfigurationId ?? state.configurations[0]?.id;
  const configuration = state.configurations.find((candidate) => candidate.id === activeId);

  if (!configuration) {
    throw new Error("Loopwire state has no active configuration.");
  }

  return configuration;
}

export function getConfigurationById(state: LoopwireState, configurationId: string): LoopwireConfiguration {
  const configuration = state.configurations.find((candidate) => candidate.id === configurationId);

  if (!configuration) {
    throw new Error(`Unknown Loopwire configuration: ${configurationId}`);
  }

  return configuration;
}

export function getVisibleMonitors(state: LoopwireState, configuration: LoopwireConfiguration): LoopwireConfiguration["monitors"] {
  return configuration.monitors.filter((monitor) => !isMonitorHidden(state, configuration, monitor.id));
}

export function isMonitorHidden(
  state: LoopwireState,
  configuration: LoopwireConfiguration,
  monitorId: string
): boolean {
  const hidden = new Set(state.hiddenMonitorIds);
  return hidden.has(monitorVisibilityId(configuration.id, monitorId)) || hidden.has(monitorId);
}

export function validateConfigurationGraph(configuration: LoopwireConfiguration): void {
  if (!configuration.id.trim()) {
    throw new Error("Configuration id is required.");
  }

  if (!configuration.name.trim()) {
    throw new Error("Configuration name is required.");
  }

  if (configuration.outputs.length === 0) {
    throw new Error("Configuration must include at least one output.");
  }

  const endpoints = [...configuration.inputs, ...configuration.outputs, ...configuration.monitors];
  const endpointIds = new Set<string>();

  for (const endpoint of endpoints) {
    if (!endpoint.id.trim() || !endpoint.label.trim() || endpoint.channels <= 0) {
      throw new Error(`Invalid endpoint in configuration: ${configuration.id}`);
    }

    if (endpoint.deviceName !== undefined && !endpoint.deviceName.trim()) {
      throw new Error(`Invalid endpoint device in configuration: ${endpoint.id}`);
    }

    if (endpointIds.has(endpoint.id)) {
      throw new Error(`Duplicate endpoint id in configuration: ${endpoint.id}`);
    }

    endpointIds.add(endpoint.id);
  }

  const inputIds = new Set(configuration.inputs.map((endpoint) => endpoint.id));
  const outputIds = new Set(configuration.outputs.map((endpoint) => endpoint.id));
  const monitorIds = new Set(configuration.monitors.map((endpoint) => endpoint.id));
  const routeIds = new Set<string>();
  const routePairs = new Set<string>();

  for (const route of configuration.routes) {
    const inputToOutput = inputIds.has(route.from) && outputIds.has(route.to);
    const outputToMonitor = outputIds.has(route.from) && monitorIds.has(route.to);

    if (!route.id.trim() || (!inputToOutput && !outputToMonitor)) {
      throw new Error(`Invalid route in configuration: ${route.id}`);
    }

    if (routeIds.has(route.id)) {
      throw new Error(`Duplicate route id in configuration: ${route.id}`);
    }

    routeIds.add(route.id);

    const routePair = `${route.from}->${route.to}`;
    if (routePairs.has(routePair)) {
      throw new Error(`Duplicate route pair in configuration: ${route.from} to ${route.to}`);
    }

    routePairs.add(routePair);

    if (!isValidRouteGain(route.gain)) {
      throw new Error("Route gain must be between 0 and 1.");
    }
  }
}

function assertConfigurationExists(state: LoopwireState, configurationId: string): void {
  getConfigurationById(state, configurationId);
}

function monitorVisibilityId(configurationId: string, monitorId: string): string {
  return `${configurationId}:${monitorId}`;
}

function createDefaultOutput(): AudioEndpoint {
  return { id: "output", label: "Main Output", role: "output", channels: 2 };
}

function patchConfigurationControls(
  state: LoopwireState,
  configurationId: string,
  patch: Pick<Partial<LoopwireConfiguration>, "enabled" | "muted" | "volume">,
  updatedAt: string
): ConfigurationMutationResult {
  const existing = getConfigurationById(state, configurationId);
  const configuration: LoopwireConfiguration = { ...existing, ...patch, updatedAt };

  return {
    state: {
      ...state,
      configurations: state.configurations.map((candidate) => (candidate.id === configurationId ? configuration : candidate))
    },
    configuration
  };
}

function patchEndpoint(
  state: LoopwireState,
  configurationId: string,
  endpointId: string,
  patch: Pick<Partial<AudioEndpoint>, "enabled" | "volume" | "muteWhenCapturing">,
  updatedAt: string
): ConfigurationMutationResult {
  const configuration = getConfigurationById(state, configurationId);
  const endpoint = [...configuration.inputs, ...configuration.outputs, ...configuration.monitors].find(
    (candidate) => candidate.id === endpointId
  );

  if (!endpoint) {
    throw new Error(`Unknown Loopwire endpoint: ${endpointId}`);
  }

  const applyPatch = (candidate: AudioEndpoint): AudioEndpoint =>
    candidate.id === endpointId ? { ...candidate, ...patch } : candidate;

  return updateConfiguration(
    state,
    configurationId,
    {
      inputs: configuration.inputs.map(applyPatch),
      outputs: configuration.outputs.map(applyPatch),
      monitors: configuration.monitors.map(applyPatch)
    },
    updatedAt
  );
}

function updateRoute(
  state: LoopwireState,
  configurationId: string,
  routeId: string,
  patch: Pick<Partial<AudioRoute>, "gain" | "muted">,
  updatedAt: string
): ConfigurationMutationResult {
  const configuration = getConfigurationById(state, configurationId);

  if (!configuration.routes.some((route) => route.id === routeId)) {
    throw new Error(`Unknown Loopwire route: ${routeId}`);
  }

  return updateConfiguration(
    state,
    configurationId,
    {
      routes: configuration.routes.map((route) => (route.id === routeId ? { ...route, ...patch } : route))
    },
    updatedAt
  );
}

function isValidRouteGain(gain: number): boolean {
  return Number.isFinite(gain) && gain >= 0 && gain <= 1;
}

function normalizeConfigurationName(name: string): string {
  const normalized = name.trim();
  return normalized || "Untitled Configuration";
}

function makeUniqueConfigurationId(baseId: string, configurations: readonly LoopwireConfiguration[]): string {
  const existingIds = new Set(configurations.map((configuration) => configuration.id));
  const normalizedBase = slugify(baseId) || "configuration";
  let candidate = normalizedBase;
  let suffix = 2;

  while (existingIds.has(candidate)) {
    candidate = `${normalizedBase}-${suffix}`;
    suffix += 1;
  }

  return candidate;
}

function makeUniqueRouteId(baseId: string, routes: readonly AudioRoute[]): string {
  const existingIds = new Set(routes.map((route) => route.id));
  const normalizedBase = slugify(baseId) || "route";
  let candidate = normalizedBase;
  let suffix = 2;

  while (existingIds.has(candidate)) {
    candidate = `${normalizedBase}-${suffix}`;
    suffix += 1;
  }

  return candidate;
}

function assertEndpointAvailable(configuration: LoopwireConfiguration, id: string, label: string, kind: string): void {
  const endpoints = [...configuration.inputs, ...configuration.outputs, ...configuration.monitors];
  if (endpoints.some((endpoint) => endpoint.id === id || endpoint.label.toLowerCase() === label.toLowerCase())) {
    throw new Error(`${kind} already exists in configuration: ${label}`);
  }
}

function slugify(value: string): string {
  return value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

function createDefaultConfigurations(updatedAt: string): LoopwireConfiguration[] {
  return [
    {
      id: "studio",
      name: "Studio",
      description: "Mic, browser, and monitor mix for focused recording.",
      inputs: [
        { id: "mic", label: "Studio Mic", role: "input", channels: 2 },
        { id: "browser", label: "Browser Audio", role: "input", channels: 2 }
      ],
      outputs: [{ id: "recorder", label: "Recorder Bus", role: "output", channels: 2 }],
      monitors: [
        { id: "headphones", label: "Headphones", role: "monitor", channels: 2 },
        { id: "meters", label: "Meter Bridge", role: "monitor", channels: 2 }
      ],
      routes: [
        { id: "mic-recorder", from: "mic", to: "recorder", gain: 0.86, muted: false },
        { id: "browser-recorder", from: "browser", to: "recorder", gain: 0.62, muted: false }
      ],
      updatedAt
    },
    {
      id: "call",
      name: "Call",
      description: "Clean microphone and app-return mix for meetings.",
      inputs: [
        { id: "mic", label: "Studio Mic", role: "input", channels: 2 },
        { id: "system", label: "System Return", role: "input", channels: 2 }
      ],
      outputs: [{ id: "meeting", label: "Meeting App", role: "output", channels: 2 }],
      monitors: [{ id: "headphones", label: "Headphones", role: "monitor", channels: 2 }],
      routes: [
        { id: "mic-meeting", from: "mic", to: "meeting", gain: 0.9, muted: false },
        { id: "system-meeting", from: "system", to: "meeting", gain: 0.42, muted: false }
      ],
      updatedAt
    },
    {
      id: "stream",
      name: "Stream",
      description: "Mic, game, music, and monitor split for live broadcasts.",
      inputs: [
        { id: "mic", label: "Studio Mic", role: "input", channels: 2 },
        { id: "game", label: "Game Capture", role: "input", channels: 2 },
        { id: "music", label: "Music Player", role: "input", channels: 2 }
      ],
      outputs: [{ id: "broadcast", label: "Broadcast Bus", role: "output", channels: 2 }],
      monitors: [
        { id: "headphones", label: "Headphones", role: "monitor", channels: 2 },
        { id: "producer", label: "Producer Monitor", role: "monitor", channels: 2 }
      ],
      routes: [
        { id: "mic-broadcast", from: "mic", to: "broadcast", gain: 0.84, muted: false },
        { id: "game-broadcast", from: "game", to: "broadcast", gain: 0.7, muted: false },
        { id: "music-broadcast", from: "music", to: "broadcast", gain: 0.35, muted: false }
      ],
      updatedAt
    }
  ];
}
