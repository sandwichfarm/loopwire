import { get } from "svelte/store";
import { describe, expect, it } from "vitest";
import { createUiStore } from "./uiStore";

function manualStore() {
  const pending: Array<() => void> = [];
  const store = createUiStore({ scheduleDismiss: (dismiss) => pending.push(dismiss) });
  return { store, flush: () => pending.splice(0).forEach((dismiss) => dismiss()) };
}

describe("canvas selection", () => {
  it("selects endpoints and routes exclusively", () => {
    const { store } = manualStore();

    store.selectEndpoint("mic");
    expect(get(store.canvasSelection)).toEqual({ kind: "endpoint", endpointId: "mic" });
    expect(get(store.hasCanvasSelection)).toBe(true);

    store.selectRoute("mic-bus");
    expect(get(store.canvasSelection)).toEqual({ kind: "route", routeId: "mic-bus" });

    store.clearSelection();
    expect(get(store.hasCanvasSelection)).toBe(false);
  });

  it("prunes selections that no longer exist in the graph", () => {
    const { store } = manualStore();
    store.selectEndpoint("gone");
    store.pruneSelection(new Set(["mic"]), new Set());

    expect(get(store.canvasSelection)).toBeNull();

    store.selectRoute("kept");
    store.pruneSelection(new Set(), new Set(["kept"]));
    expect(get(store.canvasSelection)).toEqual({ kind: "route", routeId: "kept" });
  });
});

describe("monitors visibility + options", () => {
  it("toggles per-device monitor collapse", () => {
    const { store } = manualStore();

    store.toggleMonitorsHidden("device-1");
    expect(get(store.monitorsHiddenDevices).has("device-1")).toBe(true);

    store.toggleMonitorsHidden("device-1");
    expect(get(store.monitorsHiddenDevices).has("device-1")).toBe(false);
  });

  it("toggles per-endpoint options expansion", () => {
    const { store } = manualStore();

    store.toggleOptionsExpanded("mic");
    expect(get(store.expandedOptions).has("mic")).toBe(true);

    store.toggleOptionsExpanded("mic");
    expect(get(store.expandedOptions).has("mic")).toBe(false);
  });
});

describe("toasts", () => {
  it("pushes, auto-dismisses, and supports undo payloads", () => {
    const { store, flush } = manualStore();
    let undone = false;

    store.pushToast("undo", "Removed Loopwire Device 1.", () => {
      undone = true;
    });

    const toasts = get(store.toasts);
    expect(toasts).toHaveLength(1);
    expect(toasts[0]?.kind).toBe("undo");

    toasts[0]?.undo?.();
    expect(undone).toBe(true);

    flush();
    expect(get(store.toasts)).toHaveLength(0);
  });

  it("dismisses a toast by id", () => {
    const { store } = manualStore();
    const id = store.pushToast("error", "Could not add source.");

    store.dismissToast(id);
    expect(get(store.toasts)).toHaveLength(0);
  });
});
