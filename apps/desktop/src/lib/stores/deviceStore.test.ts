import { get } from "svelte/store";
import { describe, expect, it } from "vitest";
import { createDeviceStore, channelLabel, nextBusLabel, nextDeviceName } from "./deviceStore";

function storeWithDevice() {
  const store = createDeviceStore();
  const { result, deviceId } = store.createDevice();

  expect(result.ok).toBe(true);
  if (!deviceId) {
    throw new Error("device was not created");
  }

  return { store, deviceId };
}

describe("nextDeviceName", () => {
  it("starts at Loopwire Device 1 and fills gaps", () => {
    expect(nextDeviceName([])).toBe("Loopwire Device 1");

    const taken = (name: string) =>
      ({ id: name, name, description: "", inputs: [], outputs: [], monitors: [], routes: [], updatedAt: "" }) as never;

    expect(nextDeviceName([taken("Loopwire Device 1"), taken("Loopwire Device 3")])).toBe("Loopwire Device 2");
    expect(nextDeviceName([taken("Custom Mix")])).toBe("Loopwire Device 1");
  });
});

describe("nextBusLabel / channelLabel", () => {
  it("labels buses by cumulative channel index", () => {
    expect(nextBusLabel([])).toEqual({ label: "Channels 1 & 2", startChannel: 1 });
    expect(nextBusLabel([{ id: "a", label: "", role: "output", channels: 2 }])).toEqual({
      label: "Channels 3 & 4",
      startChannel: 3
    });
  });

  it("labels mono buses with a single channel number", () => {
    expect(nextBusLabel([], 1)).toEqual({ label: "Channel 1", startChannel: 1 });
    expect(nextBusLabel([{ id: "a", label: "", role: "output", channels: 2 }], 1)).toEqual({
      label: "Channel 3",
      startChannel: 3
    });
  });

  it("labels quad buses with a channel range", () => {
    expect(nextBusLabel([], 4)).toEqual({ label: "Channels 1–4", startChannel: 1 });
    expect(nextBusLabel([{ id: "a", label: "", role: "output", channels: 2 }], 4)).toEqual({
      label: "Channels 3–6",
      startChannel: 3
    });
  });

  it("keeps the cumulative start channel across mixed-width buses", () => {
    const outputs = [
      { id: "a", label: "", role: "output" as const, channels: 1 },
      { id: "b", label: "", role: "output" as const, channels: 4 }
    ];

    expect(nextBusLabel(outputs)).toEqual({ label: "Channels 6 & 7", startChannel: 6 });
  });

  it("suffixes (L)/(R) only on the first stereo pair", () => {
    expect(channelLabel(1)).toBe("1 (L)");
    expect(channelLabel(2)).toBe("2 (R)");
    expect(channelLabel(3)).toBe("3");
  });
});

describe("createDevice", () => {
  it("creates the default graph: Pass-Thru wired to Channels 1 & 2", () => {
    const { store, deviceId } = storeWithDevice();
    const device = get(store.selectedDevice);

    expect(device?.id).toBe(deviceId);
    expect(device?.name).toBe("Loopwire Device 1");
    expect(device?.inputs.map((input) => input.label)).toEqual(["Pass-Thru"]);
    expect(device?.outputs.map((output) => output.label)).toEqual(["Channels 1 & 2"]);
    expect(device?.routes).toHaveLength(1);
    expect(device?.routes[0]).toMatchObject({ from: "pass-thru", to: "channels-1-2" });
  });

  it("stamps the default Pass-Thru source with kind pass-thru", () => {
    const { store } = storeWithDevice();
    const device = get(store.selectedDevice);

    expect(device?.inputs[0]?.kind).toBe("pass-thru");
  });

  it("numbers subsequent devices", () => {
    const { store } = storeWithDevice();
    store.createDevice();

    expect(get(store.devices).map((device) => device.name)).toEqual(["Loopwire Device 1", "Loopwire Device 2"]);
  });
});

describe("removeDevice + undo snapshot", () => {
  it("removes to empty and restores through a snapshot", () => {
    const { store, deviceId } = storeWithDevice();
    const snapshot = store.snapshot();

    const { result, removed } = store.removeDevice(deviceId);

    expect(result.ok).toBe(true);
    expect(removed?.name).toBe("Loopwire Device 1");
    expect(get(store.devices)).toHaveLength(0);
    expect(get(store.selectedDevice)).toBeUndefined();

    store.restoreSnapshot(snapshot);

    expect(get(store.devices)).toHaveLength(1);
    expect(get(store.selectedDevice)?.id).toBe(deviceId);
  });
});

describe("graph editing", () => {
  it("adds a bus with the next channel label and no auto-routes", () => {
    const { store, deviceId } = storeWithDevice();
    const result = store.addBus(deviceId);

    expect(result.ok).toBe(true);
    const device = get(store.selectedDevice);
    expect(device?.outputs.map((output) => output.label)).toEqual(["Channels 1 & 2", "Channels 3 & 4"]);
    expect(device?.routes).toHaveLength(1);
  });

  it("adds mono and quad buses with channel-count-aware labels and cumulative start channels", () => {
    const { store, deviceId } = storeWithDevice();

    expect(store.addBus(deviceId, 4).ok).toBe(true);
    expect(store.addBus(deviceId, 1).ok).toBe(true);

    const device = get(store.selectedDevice);
    expect(device?.outputs.map((output) => output.label)).toEqual(["Channels 1 & 2", "Channels 3–6", "Channel 7"]);
    expect(device?.outputs.map((output) => output.channels)).toEqual([2, 4, 1]);
  });

  it("appends the new bus last so the canvas can auto-select it", () => {
    const { store, deviceId } = storeWithDevice();

    expect(store.addBus(deviceId, 4).ok).toBe(true);

    const device = get(store.selectedDevice);
    const appended = device?.outputs.at(-1);
    expect(appended?.label).toBe("Channels 3–6");
    expect(appended?.channels).toBe(4);
  });

  it("adds a monitor auto-cabled from every bus", () => {
    const { store, deviceId } = storeWithDevice();
    store.addBus(deviceId);
    const result = store.addMonitor(deviceId, { label: "Desk Speakers" });

    expect(result.ok).toBe(true);
    const device = get(store.selectedDevice);
    const monitor = device?.monitors[0];
    expect(monitor?.label).toBe("Desk Speakers");
    expect(device?.routes.filter((route) => route.to === monitor?.id)).toHaveLength(2);
  });

  it("adds a source auto-cabled to the first bus", () => {
    const { store, deviceId } = storeWithDevice();
    const result = store.addSource(deviceId, { label: "Browser", channels: 2 });

    expect(result.ok).toBe(true);
    const device = get(store.selectedDevice);
    expect(device?.inputs.some((input) => input.label === "Browser")).toBe(true);
    expect(device?.routes.some((route) => route.from === "browser" && route.to === "channels-1-2")).toBe(true);
  });

  it("carries the candidate kind onto the added source", () => {
    const { store, deviceId } = storeWithDevice();
    const result = store.addSource(deviceId, { label: "Browser", channels: 2, kind: "app" });

    expect(result.ok).toBe(true);
    const device = get(store.selectedDevice);
    expect(device?.inputs.find((input) => input.label === "Browser")?.kind).toBe("app");
  });

  it("returns a typed error instead of throwing on invalid edits", () => {
    const { store, deviceId } = storeWithDevice();
    const duplicate = store.addSource(deviceId, { label: "Pass-Thru" });

    expect(duplicate.ok).toBe(false);
    if (!duplicate.ok) {
      expect(duplicate.message).toMatch(/already exists/);
    }
  });

  it("routes source volume into every outgoing route gain", () => {
    const { store, deviceId } = storeWithDevice();
    const result = store.setSourceVolume(deviceId, "pass-thru", 0.4);

    expect(result.ok).toBe(true);
    const device = get(store.selectedDevice)!;
    expect(device.routes.every((route) => route.gain === 0.4)).toBe(true);
    expect(store.sourceVolume(device, "pass-thru")).toBe(0.4);
  });

  it("stores monitor volume as configured endpoint volume", () => {
    const { store, deviceId } = storeWithDevice();
    store.addMonitor(deviceId, { label: "Desk Speakers" });
    const monitorId = get(store.selectedDevice)!.monitors[0]!.id;

    const result = store.setSourceVolume(deviceId, monitorId, 0.12);

    expect(result.ok).toBe(true);
    const device = get(store.selectedDevice)!;
    expect(device.monitors[0]?.volume).toBe(0.12);
  });

  it("keeps state unchanged when a mutation fails", () => {
    const { store, deviceId } = storeWithDevice();
    const before = store.snapshot();

    const failed = store.removeBus(deviceId, "channels-1-2");

    expect(failed.ok).toBe(false);
    expect(store.snapshot()).toEqual(before);
  });
});
