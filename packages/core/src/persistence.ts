import { createDefaultState, insertConfiguration, validateConfigurationGraph } from "./configuration.js";
import {
  audioBackendKinds,
  endpointKinds,
  legacySchemaVersionV1,
  schemaVersion,
  type AudioEndpoint,
  type AudioRoute,
  type EndpointKind,
  type LoopwireConfiguration,
  type LoopwireState,
  type PersistedStateV2
} from "./types.js";

export const configurationExportKind = "loopwire.configuration" as const;
export const configurationExportVersion = 1 as const;

export interface ConfigurationExportV1 {
  readonly kind: typeof configurationExportKind;
  readonly version: typeof configurationExportVersion;
  readonly configuration: LoopwireConfiguration;
}

export type ImportConfigurationResult =
  | {
      readonly ok: true;
      readonly state: LoopwireState;
      readonly configuration: LoopwireConfiguration;
    }
  | {
      readonly ok: false;
      readonly state: LoopwireState;
      readonly reason: string;
    };

export type RestoreResult =
  | {
      readonly ok: true;
      readonly state: LoopwireState;
    }
  | {
      readonly ok: false;
      readonly state: LoopwireState;
      readonly reason: string;
    };

export function serializeState(state: LoopwireState): string {
  const persisted: PersistedStateV2 = {
    version: schemaVersion,
    configurations: state.configurations,
    hiddenMonitorIds: state.hiddenMonitorIds,
    ...(state.selectedBackend ? { selectedBackend: state.selectedBackend } : {}),
    ...(state.activeConfigurationId ? { activeConfigurationId: state.activeConfigurationId } : {}),
    ...(state.appliedAt ? { appliedAt: state.appliedAt } : {})
  };

  return JSON.stringify(persisted, null, 2);
}

export function exportConfiguration(configuration: LoopwireConfiguration): string {
  validateConfigurationGraph(configuration);

  const payload: ConfigurationExportV1 = {
    kind: configurationExportKind,
    version: configurationExportVersion,
    configuration
  };

  return JSON.stringify(payload, null, 2);
}

export function importConfiguration(
  state: LoopwireState,
  raw: string,
  importedAt: string
): ImportConfigurationResult {
  try {
    const value: unknown = JSON.parse(raw);
    const configuration = parseConfigurationExport(value);

    if (!configuration) {
      return { ok: false, state, reason: "Imported Loopwire configuration failed schema validation." };
    }

    const result = insertConfiguration(state, configuration, importedAt);
    return { ok: true, state: result.state, configuration: result.configuration };
  } catch (error) {
    return {
      ok: false,
      state,
      reason: error instanceof Error ? error.message : "Imported Loopwire configuration could not be parsed."
    };
  }
}

export function restoreState(raw: string | null, fallback: LoopwireState = createDefaultState()): RestoreResult {
  if (!raw) {
    return { ok: false, state: fallback, reason: "No persisted Loopwire state found." };
  }

  try {
    const value: unknown = JSON.parse(raw);
    const state = parsePersistedState(value);

    if (!state) {
      return { ok: false, state: fallback, reason: "Persisted Loopwire state failed schema validation." };
    }

    return { ok: true, state };
  } catch (error) {
    return {
      ok: false,
      state: fallback,
      reason: error instanceof Error ? error.message : "Persisted Loopwire state could not be parsed."
    };
  }
}

function parsePersistedState(value: unknown): LoopwireState | null {
  if (!isRecord(value)) {
    return null;
  }

  if (value.version === schemaVersion || value.version === legacySchemaVersionV1) {
    return parseModernState(value);
  }

  if (value.version === 0) {
    return parseStateV0(value);
  }

  return null;
}

/**
 * Parses schema v2 payloads and migrates v1 payloads in place: v2 only adds
 * optional device/endpoint control fields, so a v1 payload parses cleanly and
 * is re-stamped with the current schema version.
 */
function parseModernState(value: unknown): LoopwireState | null {
  if (!isRecord(value) || !Array.isArray(value.configurations)) {
    return null;
  }

  const configurations = parseConfigurationArray(value.configurations);
  if (!configurations) {
    return null;
  }

  const selectedBackend = parseOptionalBackend(value.selectedBackend);
  const activeConfigurationId = parseOptionalString(value.activeConfigurationId);
  const hiddenMonitorIds = parseStringArray(value.hiddenMonitorIds);
  const appliedAt = parseOptionalString(value.appliedAt);
  const normalizedActiveId = normalizeActiveConfigurationId(configurations, activeConfigurationId);

  return {
    version: schemaVersion,
    configurations,
    hiddenMonitorIds,
    ...(selectedBackend ? { selectedBackend } : {}),
    ...(normalizedActiveId ? { activeConfigurationId: normalizedActiveId } : {}),
    ...(appliedAt ? { appliedAt } : {})
  };
}

function parseStateV0(value: Record<string, unknown>): LoopwireState | null {
  if (!Array.isArray(value.configurations)) {
    return null;
  }

  const configurations = parseConfigurationArray(value.configurations);
  if (!configurations) {
    return null;
  }

  const selectedBackend = parseOptionalBackend(value.selectedBackend);
  const activeConfigurationId = parseOptionalString(value.activeId);
  const hiddenMonitorIds = parseStringArray(value.hiddenMonitors);
  const appliedAt = parseOptionalString(value.appliedAt);
  const normalizedActiveId = normalizeActiveConfigurationId(configurations, activeConfigurationId);

  return {
    version: schemaVersion,
    configurations,
    hiddenMonitorIds,
    ...(selectedBackend ? { selectedBackend } : {}),
    ...(normalizedActiveId ? { activeConfigurationId: normalizedActiveId } : {}),
    ...(appliedAt ? { appliedAt } : {})
  };
}

function parseConfigurationExport(value: unknown): LoopwireConfiguration | null {
  if (!isRecord(value) || value.kind !== configurationExportKind || value.version !== configurationExportVersion) {
    return null;
  }

  return parseConfiguration(value.configuration);
}

function parseConfigurationArray(value: unknown[]): readonly LoopwireConfiguration[] | null {
  const configurations: LoopwireConfiguration[] = [];

  for (const item of value) {
    const configuration = parseConfiguration(item);
    if (!configuration) {
      return null;
    }

    configurations.push(configuration);
  }

  return configurations;
}

function parseConfiguration(value: unknown): LoopwireConfiguration | null {
  if (!isRecord(value)) {
    return null;
  }

  const id = parseString(value.id);
  const name = parseString(value.name);
  const description = parseString(value.description);
  const updatedAt = parseString(value.updatedAt);
  const inputs = parseEndpointArray(value.inputs);
  const outputs = parseEndpointArray(value.outputs);
  const monitors = parseEndpointArray(value.monitors);
  const routes = parseRouteArray(value.routes);
  const enabled = parseOptionalBoolean(value.enabled);
  const muted = parseOptionalBoolean(value.muted);
  const volume = parseOptionalUnitNumber(value.volume);

  if (!id || !name || description === null || !updatedAt || !inputs || !outputs || !monitors || !routes) {
    return null;
  }

  const configuration = {
    id,
    name,
    description,
    inputs,
    outputs,
    monitors,
    routes,
    updatedAt,
    ...(enabled !== undefined ? { enabled } : {}),
    ...(muted !== undefined ? { muted } : {}),
    ...(volume !== undefined ? { volume } : {})
  };

  try {
    validateConfigurationGraph(configuration);
    return configuration;
  } catch {
    return null;
  }
}

function parseEndpointArray(value: unknown): readonly AudioEndpoint[] | null {
  if (!Array.isArray(value)) {
    return null;
  }

  const endpoints: AudioEndpoint[] = [];

  for (const item of value) {
    const endpoint = parseEndpoint(item);
    if (!endpoint) {
      return null;
    }

    endpoints.push(endpoint);
  }

  return endpoints;
}

function parseEndpoint(value: unknown): AudioEndpoint | null {
  if (!isRecord(value)) {
    return null;
  }

  const id = parseString(value.id);
  const label = parseString(value.label);
  const role = value.role;
  const channels = value.channels;
  const deviceName = parseOptionalString(value.deviceName);
  const enabled = parseOptionalBoolean(value.enabled);
  const volume = parseOptionalUnitNumber(value.volume);
  const muteWhenCapturing = parseOptionalBoolean(value.muteWhenCapturing);
  const kind = parseOptionalEndpointKind(value.kind);

  if (!id || !label || (role !== "input" && role !== "output" && role !== "monitor") || !isPositiveInteger(channels)) {
    return null;
  }

  return {
    id,
    label,
    role,
    channels,
    ...(deviceName ? { deviceName } : {}),
    ...(enabled !== undefined ? { enabled } : {}),
    ...(volume !== undefined ? { volume } : {}),
    ...(muteWhenCapturing !== undefined ? { muteWhenCapturing } : {}),
    ...(kind !== undefined ? { kind } : {})
  };
}

function parseRouteArray(value: unknown): readonly AudioRoute[] | null {
  if (!Array.isArray(value)) {
    return null;
  }

  const routes: AudioRoute[] = [];

  for (const item of value) {
    const route = parseRoute(item);
    if (!route) {
      return null;
    }

    routes.push(route);
  }

  return routes;
}

function parseRoute(value: unknown): AudioRoute | null {
  if (!isRecord(value)) {
    return null;
  }

  const id = parseString(value.id);
  const from = parseString(value.from);
  const to = parseString(value.to);
  const gain = value.gain;
  const muted = value.muted;

  if (!id || !from || !to || typeof gain !== "number" || typeof muted !== "boolean") {
    return null;
  }

  return { id, from, to, gain, muted };
}

function normalizeActiveConfigurationId(
  configurations: readonly LoopwireConfiguration[],
  activeConfigurationId: string | undefined
): string | undefined {
  if (activeConfigurationId && configurations.some((configuration) => configuration.id === activeConfigurationId)) {
    return activeConfigurationId;
  }

  return configurations[0]?.id;
}

function parseOptionalBackend(value: unknown): LoopwireState["selectedBackend"] {
  return audioBackendKinds.some((kind) => kind === value) ? (value as LoopwireState["selectedBackend"]) : undefined;
}

function parseStringArray(value: unknown): readonly string[] {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string").toSorted() : [];
}

function parseOptionalString(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

function parseOptionalEndpointKind(value: unknown): EndpointKind | undefined {
  return endpointKinds.some((kind) => kind === value) ? (value as EndpointKind) : undefined;
}

function parseOptionalBoolean(value: unknown): boolean | undefined {
  return typeof value === "boolean" ? value : undefined;
}

function parseOptionalUnitNumber(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 && value <= 1 ? value : undefined;
}

function parseString(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function isPositiveInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value) && value > 0;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
