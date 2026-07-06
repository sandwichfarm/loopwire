import { invoke } from "@tauri-apps/api/core";
import type { StatePersistencePort } from "../stores/deviceStore";

const storageKey = "loopwire.state.v1";

export function hasTauriRuntime(): boolean {
  return typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;
}

/**
 * Persists Loopwire state to localStorage always, and to the desktop state
 * file when running inside the Tauri shell. Desktop reads win over the
 * browser copy so the state file stays the source of truth.
 */
export function createStatePersistence(onError?: (message: string) => void): StatePersistencePort {
  return {
    async load() {
      const browserRaw = localStorage.getItem(storageKey);

      if (!hasTauriRuntime()) {
        return browserRaw;
      }

      try {
        const desktopRaw = await invoke<string>("read_state");
        return desktopRaw || browserRaw;
      } catch (error) {
        onError?.(error instanceof Error ? error.message : "Could not read the desktop state file.");
        return browserRaw;
      }
    },
    save(raw) {
      localStorage.setItem(storageKey, raw);

      if (!hasTauriRuntime()) {
        return;
      }

      invoke<string>("write_state", { raw }).catch((error: unknown) => {
        onError?.(error instanceof Error ? error.message : "Could not write the desktop state file.");
      });
    }
  };
}
