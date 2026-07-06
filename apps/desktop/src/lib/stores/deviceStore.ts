import { derived, get, writable, type Readable } from "svelte/store";
import {
  addInputSourceToConfiguration,
  addMonitorToConfiguration,
  addOutputBusToConfiguration,
  addRouteToConfiguration,
  createConfiguration,
  createEmptyState,
  findActiveConfiguration,
  moveConfiguration,
  removeConfiguration,
  removeInputSourceFromConfiguration,
  removeMonitorFromConfiguration,
  removeOutputBusFromConfiguration,
  removeRouteFromConfiguration,
  restoreState,
  serializeState,
  setConfigurationEnabled,
  setConfigurationMuted,
  setConfigurationVolume,
  setEndpointEnabled,
  setEndpointMuteWhenCapturing,
  setEndpointVolume,
  setRouteGain,
  updateConfiguration,
  type AudioEndpoint,
  type LoopwireConfiguration,
  type LoopwireState
} from "@loopwire/core";

export type DeviceActionResult = { readonly ok: true } | { readonly ok: false; readonly message: string };

export interface StatePersistencePort {
  load(): Promise<string | null>;
  save(raw: string): void;
}

export interface AddSourceInput {
  readonly id?: string;
  readonly label: string;
  readonly channels?: number;
  readonly deviceName?: string;
}

export interface AddMonitorInput {
  readonly id?: string;
  readonly label: string;
  readonly channels?: number;
  readonly deviceName?: string;
}

const defaultDeviceNamePattern = /^Loopwire Device (\d+)$/;

export function nextDeviceName(configurations: readonly LoopwireConfiguration[]): string {
  const used = new Set(
    configurations
      .map((configuration) => defaultDeviceNamePattern.exec(configuration.name)?.[1])
      .filter((digits): digits is string => Boolean(digits))
      .map((digits) => Number.parseInt(digits, 10))
  );

  let index = 1;
  while (used.has(index)) {
    index += 1;
  }

  return `Loopwire Device ${index}`;
}

export function nextBusLabel(outputs: readonly AudioEndpoint[]): { readonly label: string; readonly startChannel: number } {
  const startChannel = outputs.reduce((sum, output) => sum + output.channels, 0) + 1;
  return { label: `Channels ${startChannel} & ${startChannel + 1}`, startChannel };
}

export function channelLabel(index: number): string {
  if (index === 1) {
    return "1 (L)";
  }

  if (index === 2) {
    return "2 (R)";
  }

  return String(index);
}

function noopPersistence(): StatePersistencePort {
  return {
    load: async () => null,
    save: () => undefined
  };
}

export function createDeviceStore(persistence: StatePersistencePort = noopPersistence()) {
  const state = writable<LoopwireState>(createEmptyState(new Date().toISOString()));

  const devices: Readable<readonly LoopwireConfiguration[]> = derived(state, ($state) => $state.configurations);
  const selectedDevice: Readable<LoopwireConfiguration | undefined> = derived(state, findActiveConfiguration);

  function apply(next: LoopwireState): void {
    state.set(next);
    persistence.save(serializeState(next));
  }

  function mutate(action: (current: LoopwireState, now: string) => LoopwireState): DeviceActionResult {
    try {
      apply(action(get(state), new Date().toISOString()));
      return { ok: true };
    } catch (error) {
      return { ok: false, message: error instanceof Error ? error.message : "Loopwire could not apply this change." };
    }
  }

  async function restore(): Promise<void> {
    const raw = await persistence.load();
    const restored = restoreState(raw, createEmptyState(new Date().toISOString()));
    state.set(restored.state);
  }

  function snapshot(): LoopwireState {
    return get(state);
  }

  function restoreSnapshot(previous: LoopwireState): void {
    apply(previous);
  }

  /** Creates a device with the default graph: Pass-Thru source wired to a Channels 1 & 2 bus. */
  function createDevice(): { readonly result: DeviceActionResult; readonly deviceId?: string } {
    let deviceId: string | undefined;
    const result = mutate((current, now) => {
      const created = createConfiguration(
        current,
        {
          name: nextDeviceName(current.configurations),
          description: "",
          inputs: [{ id: "pass-thru", label: "Pass-Thru", role: "input", channels: 2 }],
          outputs: [{ id: "channels-1-2", label: "Channels 1 & 2", role: "output", channels: 2 }],
          routes: [{ id: "pass-thru-channels-1-2", from: "pass-thru", to: "channels-1-2", gain: 1, muted: false }]
        },
        now
      );
      deviceId = created.configuration.id;
      return { ...created.state, activeConfigurationId: created.configuration.id, appliedAt: now };
    });

    return deviceId === undefined ? { result } : { result, deviceId };
  }

  function selectDevice(deviceId: string): DeviceActionResult {
    return mutate((current, now) => {
      if (!current.configurations.some((configuration) => configuration.id === deviceId)) {
        throw new Error(`Unknown Loopwire device: ${deviceId}`);
      }

      return { ...current, activeConfigurationId: deviceId, appliedAt: now };
    });
  }

  function removeDevice(deviceId: string): { readonly result: DeviceActionResult; readonly removed?: LoopwireConfiguration } {
    let removed: LoopwireConfiguration | undefined;
    const result = mutate((current, now) => {
      const outcome = removeConfiguration(current, deviceId, now);
      removed = outcome.removedConfiguration;
      return outcome.state;
    });

    return removed === undefined ? { result } : { result, removed };
  }

  function moveDevice(deviceId: string, toIndex: number): DeviceActionResult {
    return mutate((current, now) => moveConfiguration(current, deviceId, toIndex, now));
  }

  function renameDevice(deviceId: string, name: string): DeviceActionResult {
    return mutate((current, now) => updateConfiguration(current, deviceId, { name }, now).state);
  }

  function setDeviceEnabled(deviceId: string, enabled: boolean): DeviceActionResult {
    return mutate((current, now) => setConfigurationEnabled(current, deviceId, enabled, now).state);
  }

  function setDeviceMuted(deviceId: string, muted: boolean): DeviceActionResult {
    return mutate((current, now) => setConfigurationMuted(current, deviceId, muted, now).state);
  }

  function setDeviceVolume(deviceId: string, volume: number): DeviceActionResult {
    return mutate((current, now) => setConfigurationVolume(current, deviceId, volume, now).state);
  }

  /** Adds a source and auto-cables it to the first bus (spec §3.3). */
  function addSource(deviceId: string, input: AddSourceInput): DeviceActionResult {
    return mutate((current, now) =>
      addInputSourceToConfiguration(
        current,
        deviceId,
        {
          label: input.label,
          ...(input.id ? { id: input.id } : {}),
          ...(input.channels ? { channels: input.channels } : {}),
          ...(input.deviceName ? { deviceName: input.deviceName } : {})
        },
        now
      ).state
    );
  }

  /** Appends the next channel bus; no auto-routing of existing sources (drag or re-add wires them). */
  function addBus(deviceId: string): DeviceActionResult {
    return mutate((current, now) => {
      const configuration = current.configurations.find((candidate) => candidate.id === deviceId);

      if (!configuration) {
        throw new Error(`Unknown Loopwire device: ${deviceId}`);
      }

      const { label } = nextBusLabel(configuration.outputs);
      return addOutputBusToConfiguration(
        current,
        deviceId,
        { label, channels: 2, routeExistingInputs: false },
        now
      ).state;
    });
  }

  /** Adds a monitor and auto-cables every bus to it (spec §3.5). */
  function addMonitor(deviceId: string, input: AddMonitorInput): DeviceActionResult {
    return mutate((current, now) => {
      const added = addMonitorToConfiguration(
        current,
        deviceId,
        {
          label: input.label,
          ...(input.id ? { id: input.id } : {}),
          ...(input.channels ? { channels: input.channels } : {}),
          ...(input.deviceName ? { deviceName: input.deviceName } : {})
        },
        now
      );
      const monitor = added.configuration.monitors.at(-1);

      if (!monitor) {
        return added.state;
      }

      let next = added.state;
      for (const bus of added.configuration.outputs) {
        next = addRouteToConfiguration(next, deviceId, { from: bus.id, to: monitor.id }, now).state;
      }

      return next;
    });
  }

  function removeSource(deviceId: string, endpointId: string): DeviceActionResult {
    return mutate((current, now) => removeInputSourceFromConfiguration(current, deviceId, endpointId, now).state);
  }

  function removeBus(deviceId: string, endpointId: string): DeviceActionResult {
    return mutate((current, now) => removeOutputBusFromConfiguration(current, deviceId, endpointId, now).state);
  }

  function removeMonitor(deviceId: string, endpointId: string): DeviceActionResult {
    return mutate((current, now) => removeMonitorFromConfiguration(current, deviceId, endpointId, now).state);
  }

  function addRoute(deviceId: string, from: string, to: string): DeviceActionResult {
    return mutate((current, now) => addRouteToConfiguration(current, deviceId, { from, to }, now).state);
  }

  function removeRoute(deviceId: string, routeId: string): DeviceActionResult {
    return mutate((current, now) => removeRouteFromConfiguration(current, deviceId, routeId, now).state);
  }

  function setSourceEnabled(deviceId: string, endpointId: string, enabled: boolean): DeviceActionResult {
    return mutate((current, now) => setEndpointEnabled(current, deviceId, endpointId, enabled, now).state);
  }

  /**
   * Source volume drives the gain of every route leaving the source (the
   * value host adapters consume); endpoints without routes (monitors) store
   * the value as configured endpoint volume instead.
   */
  function setSourceVolume(deviceId: string, endpointId: string, volume: number): DeviceActionResult {
    return mutate((current, now) => {
      const configuration = current.configurations.find((candidate) => candidate.id === deviceId);

      if (!configuration) {
        throw new Error(`Unknown Loopwire device: ${deviceId}`);
      }

      const isInput = configuration.inputs.some((input) => input.id === endpointId);
      const outgoing = configuration.routes.filter((route) => route.from === endpointId);

      if (!isInput || outgoing.length === 0) {
        return setEndpointVolume(current, deviceId, endpointId, volume, now).state;
      }

      let next = current;
      for (const route of outgoing) {
        next = setRouteGain(next, deviceId, route.id, volume, now).state;
      }

      return next;
    });
  }

  /** Displayed source volume: gain of its first route, else configured endpoint volume. */
  function sourceVolume(configuration: LoopwireConfiguration, endpointId: string): number {
    const route = configuration.routes.find((candidate) => candidate.from === endpointId);

    if (route) {
      return route.gain;
    }

    const endpoint = [...configuration.inputs, ...configuration.outputs, ...configuration.monitors].find(
      (candidate) => candidate.id === endpointId
    );

    return endpoint?.volume ?? 1;
  }

  function setMuteWhenCapturing(deviceId: string, endpointId: string, muteWhenCapturing: boolean): DeviceActionResult {
    return mutate((current, now) => setEndpointMuteWhenCapturing(current, deviceId, endpointId, muteWhenCapturing, now).state);
  }

  return {
    state: { subscribe: state.subscribe },
    devices,
    selectedDevice,
    restore,
    snapshot,
    restoreSnapshot,
    createDevice,
    selectDevice,
    removeDevice,
    moveDevice,
    renameDevice,
    setDeviceEnabled,
    setDeviceMuted,
    setDeviceVolume,
    addSource,
    addBus,
    addMonitor,
    removeSource,
    removeBus,
    removeMonitor,
    addRoute,
    removeRoute,
    setSourceEnabled,
    setSourceVolume,
    sourceVolume,
    setMuteWhenCapturing
  };
}

export type DeviceStore = ReturnType<typeof createDeviceStore>;
