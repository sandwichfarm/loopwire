import { writable } from "svelte/store";

export type ThemeMode = "system" | "light" | "dark";

const themeStorageKey = "loopwire.theme.v1";

function parseThemeMode(value: string | null): ThemeMode {
  return value === "light" || value === "dark" ? value : "system";
}

export function createThemeService() {
  const mode = writable<ThemeMode>("system");

  function applyToDocument(next: ThemeMode): void {
    const root = document.documentElement;

    if (next === "system") {
      root.removeAttribute("data-theme");
    } else {
      root.setAttribute("data-theme", next);
    }
  }

  function restore(): void {
    const stored = parseThemeMode(localStorage.getItem(themeStorageKey));
    mode.set(stored);
    applyToDocument(stored);
  }

  function setMode(next: ThemeMode): void {
    mode.set(next);
    localStorage.setItem(themeStorageKey, next);
    applyToDocument(next);
  }

  return { mode, restore, setMode };
}

export type ThemeService = ReturnType<typeof createThemeService>;
