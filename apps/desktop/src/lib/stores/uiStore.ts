import { derived, get, writable, type Readable } from "svelte/store";

export type CanvasSelection =
  | { readonly kind: "endpoint"; readonly endpointId: string }
  | { readonly kind: "route"; readonly routeId: string };

export type ToastKind = "info" | "error" | "undo";

export interface Toast {
  readonly id: number;
  readonly kind: ToastKind;
  readonly message: string;
  readonly undo?: () => void;
}

export interface UiStoreOptions {
  /** Toast auto-dismiss delay; injectable for tests. */
  readonly toastDurationMs?: number;
  readonly scheduleDismiss?: (dismiss: () => void, delayMs: number) => void;
}

const defaultToastDurationMs = 5000;

export function createUiStore(options: UiStoreOptions = {}) {
  const toastDurationMs = options.toastDurationMs ?? defaultToastDurationMs;
  const scheduleDismiss =
    options.scheduleDismiss ?? ((dismiss: () => void, delayMs: number) => void setTimeout(dismiss, delayMs));

  const canvasSelection = writable<CanvasSelection | null>(null);
  const monitorsHiddenDevices = writable<ReadonlySet<string>>(new Set());
  const expandedOptions = writable<ReadonlySet<string>>(new Set());
  const renameEditing = writable(false);
  const settingsOpen = writable(false);
  const toasts = writable<readonly Toast[]>([]);

  let toastSequence = 0;

  const hasCanvasSelection: Readable<boolean> = derived(canvasSelection, (selection) => selection !== null);

  function selectEndpoint(endpointId: string): void {
    canvasSelection.set({ kind: "endpoint", endpointId });
  }

  function selectRoute(routeId: string): void {
    canvasSelection.set({ kind: "route", routeId });
  }

  function clearSelection(): void {
    canvasSelection.set(null);
  }

  function pruneSelection(validEndpointIds: ReadonlySet<string>, validRouteIds: ReadonlySet<string>): void {
    const selection = get(canvasSelection);

    if (!selection) {
      return;
    }

    if (selection.kind === "endpoint" && !validEndpointIds.has(selection.endpointId)) {
      canvasSelection.set(null);
    }

    if (selection.kind === "route" && !validRouteIds.has(selection.routeId)) {
      canvasSelection.set(null);
    }
  }

  function monitorsHidden(deviceId: string, hidden: readonly string[] | ReadonlySet<string>): boolean {
    const set = hidden instanceof Set ? hidden : new Set(hidden);
    return set.has(deviceId);
  }

  function toggleMonitorsHidden(deviceId: string): void {
    monitorsHiddenDevices.update((current) => {
      const next = new Set(current);

      if (next.has(deviceId)) {
        next.delete(deviceId);
      } else {
        next.add(deviceId);
      }

      return next;
    });
  }

  function toggleOptionsExpanded(endpointId: string): void {
    expandedOptions.update((current) => {
      const next = new Set(current);

      if (next.has(endpointId)) {
        next.delete(endpointId);
      } else {
        next.add(endpointId);
      }

      return next;
    });
  }

  function beginRename(): void {
    renameEditing.set(true);
  }

  function endRename(): void {
    renameEditing.set(false);
  }

  function dismissToast(id: number): void {
    toasts.update((current) => current.filter((toast) => toast.id !== id));
  }

  function pushToast(kind: ToastKind, message: string, undo?: () => void): number {
    const id = ++toastSequence;
    toasts.update((current) => [...current, { id, kind, message, ...(undo ? { undo } : {}) }]);
    scheduleDismiss(() => dismissToast(id), toastDurationMs);
    return id;
  }

  return {
    canvasSelection: { subscribe: canvasSelection.subscribe },
    hasCanvasSelection,
    monitorsHiddenDevices: { subscribe: monitorsHiddenDevices.subscribe },
    expandedOptions: { subscribe: expandedOptions.subscribe },
    renameEditing: { subscribe: renameEditing.subscribe },
    settingsOpen,
    toasts: { subscribe: toasts.subscribe },
    selectEndpoint,
    selectRoute,
    clearSelection,
    pruneSelection,
    monitorsHidden,
    toggleMonitorsHidden,
    toggleOptionsExpanded,
    beginRename,
    endRename,
    pushToast,
    dismissToast
  };
}

export type UiStore = ReturnType<typeof createUiStore>;
