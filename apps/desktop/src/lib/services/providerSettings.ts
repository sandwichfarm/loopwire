import { derived, writable, type Readable } from "svelte/store";
import type { BackendCandidate } from "@loopwire/core";

export type DspProviderMode = "live" | "file-backed";
export type JackProviderDelegateMode = "foreground" | "detached";

/** Legacy keys kept for compatibility with pre-rebuild saved provider settings. */
export const dspRestoreStorageKey = "loopwire.dsp-restore.v1";
export const jackRestoreStorageKey = "loopwire.jack-restore.v1";

/** Minimal storage port so unit tests run without a browser localStorage. */
export interface ProviderSettingsStorage {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
}

const noopStorage: ProviderSettingsStorage = {
  getItem: () => null,
  setItem: () => undefined,
  removeItem: () => undefined
};

function defaultStorage(): ProviderSettingsStorage {
  return typeof localStorage === "undefined" ? noopStorage : localStorage;
}

export function positiveIntegerText(value: string): boolean {
  return /^[1-9][0-9]*$/.test(value.trim());
}

export function positiveIntegerNumber(value: string, fallback: number): number {
  return positiveIntegerText(value) ? Number.parseInt(value.trim(), 10) : fallback;
}

export function nonNegativeIntegerText(value: string): boolean {
  return /^(0|[1-9][0-9]*)$/.test(value.trim());
}

export function nonNegativeIntegerNumber(value: string, fallback: number): number {
  return nonNegativeIntegerText(value) ? Number.parseInt(value.trim(), 10) : fallback;
}

/** Trimmed, numeric snapshot of the DSP provider settings for runtime use. */
export interface DspProviderSnapshot {
  readonly command: string;
  readonly mode: DspProviderMode;
  readonly timeoutMs: number;
  readonly frameCount?: number;
  readonly restoreReady: boolean;
}

/** Trimmed, numeric snapshot of the JACK provider settings for runtime use. */
export interface JackProviderSnapshot {
  readonly command: string;
  readonly timeoutMs: number;
  readonly delegateMode: JackProviderDelegateMode;
  readonly readyDelayMs: number;
  readonly args: readonly string[];
  readonly configured: boolean;
  readonly liveReady: boolean;
  readonly restoreReady: boolean;
}

/**
 * Adds (or replaces) the DSP Provider backend candidate. DSP has no host probe:
 * its availability is gated purely on saved live provider settings.
 */
export function withDspProviderCandidate(
  candidates: readonly BackendCandidate[],
  providerReady: boolean
): readonly BackendCandidate[] {
  const withoutDsp = candidates.filter((candidate) => candidate.kind !== "dsp");
  const dspCandidate: BackendCandidate = {
    kind: "dsp",
    displayName: "DSP Provider",
    availability: providerReady ? "available" : "unavailable",
    priority: 35,
    ...(providerReady
      ? {}
      : { reason: "Configure a live DSP provider command before selecting DSP restore." })
  };

  return [...withoutDsp, dspCandidate].sort((left, right) => left.priority - right.priority);
}

export function createProviderSettingsService(storage: ProviderSettingsStorage = defaultStorage()) {
  const dspCommand = writable("");
  const dspMode = writable<DspProviderMode>("live");
  const dspTimeoutMs = writable("5000");
  const dspFrameCount = writable("480");
  const jackCommand = writable("");
  const jackTimeoutMs = writable("5000");
  const jackDelegateMode = writable<JackProviderDelegateMode>("foreground");
  const jackReadyDelayMs = writable("250");

  const dspCommandConfigured = derived(dspCommand, (command) => command.trim().length > 0);
  const dspTimeoutValid = derived(dspTimeoutMs, positiveIntegerText);
  const dspFrameCountValid = derived(
    dspFrameCount,
    (frameCount) => frameCount.trim() === "" || positiveIntegerText(frameCount)
  );
  /** DSP restore/live apply requires a live provider command with valid numbers. */
  const dspRestoreProviderReady: Readable<boolean> = derived(
    [dspCommandConfigured, dspMode, dspTimeoutValid, dspFrameCountValid],
    ([configured, mode, timeoutValid, frameCountValid]) =>
      configured && mode === "live" && timeoutValid && frameCountValid
  );

  const jackCommandConfigured = derived(jackCommand, (command) => command.trim().length > 0);
  const jackTimeoutValid = derived(jackTimeoutMs, positiveIntegerText);
  const jackReadyDelayValid = derived(
    [jackDelegateMode, jackReadyDelayMs],
    ([delegateMode, readyDelay]) => delegateMode === "foreground" || nonNegativeIntegerText(readyDelay)
  );
  /** JACK restore tolerates a blank command (pre-existing ports); a saved command must be valid. */
  const jackRestoreProviderReady: Readable<boolean> = derived(
    [jackCommandConfigured, jackTimeoutValid, jackReadyDelayValid],
    ([configured, timeoutValid, readyDelayValid]) => !configured || (timeoutValid && readyDelayValid)
  );
  /** JACK live apply only uses the provider when a valid command is saved. */
  const jackLiveProviderReady: Readable<boolean> = derived(
    [jackCommandConfigured, jackTimeoutValid, jackReadyDelayValid],
    ([configured, timeoutValid, readyDelayValid]) => configured && timeoutValid && readyDelayValid
  );

  const dspSettingsMessage: Readable<string> = derived(
    [dspCommandConfigured, dspMode, dspTimeoutValid, dspFrameCountValid],
    ([configured, mode, timeoutValid, frameCountValid]) => {
      if (!configured) {
        return "DSP Provider appears after a live provider command is saved.";
      }

      if (mode !== "live") {
        return "File smoke providers stay blocked for live Restore on boot.";
      }

      if (!timeoutValid || !frameCountValid) {
        return "Timeout and frame count must be positive numbers.";
      }

      return "DSP Provider can be selected for provider-backed Restore on boot.";
    }
  );

  const jackSettingsMessage: Readable<string> = derived(
    [jackCommandConfigured, jackTimeoutValid, jackReadyDelayValid, jackDelegateMode],
    ([configured, timeoutValid, readyDelayValid, delegateMode]) => {
      if (!configured) {
        return "Leave blank to use pre-existing JACK ports during Restore on boot and live apply.";
      }

      if (!timeoutValid || !readyDelayValid) {
        return "Timeout must be positive; detached readiness delay must be zero or greater.";
      }

      if (delegateMode === "detached") {
        return "Restore on boot and live apply will keep the JACK provider delegate alive before verifying ports.";
      }

      return "Restore on boot and live apply will ask this provider to prepare Loopwire-owned JACK ports.";
    }
  );

  let currentDsp = { command: "", mode: "live" as DspProviderMode, timeoutMs: "5000", frameCount: "480" };
  let currentJack = {
    command: "",
    timeoutMs: "5000",
    delegateMode: "foreground" as JackProviderDelegateMode,
    readyDelayMs: "250"
  };

  dspCommand.subscribe((value) => (currentDsp = { ...currentDsp, command: value }));
  dspMode.subscribe((value) => (currentDsp = { ...currentDsp, mode: value }));
  dspTimeoutMs.subscribe((value) => (currentDsp = { ...currentDsp, timeoutMs: value }));
  dspFrameCount.subscribe((value) => (currentDsp = { ...currentDsp, frameCount: value }));
  jackCommand.subscribe((value) => (currentJack = { ...currentJack, command: value }));
  jackTimeoutMs.subscribe((value) => (currentJack = { ...currentJack, timeoutMs: value }));
  jackDelegateMode.subscribe((value) => (currentJack = { ...currentJack, delegateMode: value }));
  jackReadyDelayMs.subscribe((value) => (currentJack = { ...currentJack, readyDelayMs: value }));

  function restore(): void {
    restoreDsp();
    restoreJack();
  }

  function restoreDsp(): void {
    const raw = storage.getItem(dspRestoreStorageKey);

    if (!raw) {
      return;
    }

    try {
      const parsed: unknown = JSON.parse(raw);

      if (!parsed || typeof parsed !== "object") {
        return;
      }

      const settings = parsed as {
        readonly command?: unknown;
        readonly mode?: unknown;
        readonly timeoutMs?: unknown;
        readonly frameCount?: unknown;
      };

      dspCommand.set(typeof settings.command === "string" ? settings.command : "");
      dspMode.set(settings.mode === "file-backed" ? "file-backed" : "live");
      dspTimeoutMs.set(positiveIntegerText(String(settings.timeoutMs ?? "")) ? String(settings.timeoutMs) : "5000");
      dspFrameCount.set(
        settings.frameCount === "" || positiveIntegerText(String(settings.frameCount ?? ""))
          ? String(settings.frameCount ?? "480")
          : "480"
      );
    } catch {
      storage.removeItem(dspRestoreStorageKey);
    }
  }

  function restoreJack(): void {
    const raw = storage.getItem(jackRestoreStorageKey);

    if (!raw) {
      return;
    }

    try {
      const parsed: unknown = JSON.parse(raw);

      if (!parsed || typeof parsed !== "object") {
        return;
      }

      const settings = parsed as {
        readonly command?: unknown;
        readonly timeoutMs?: unknown;
        readonly delegateMode?: unknown;
        readonly readyDelayMs?: unknown;
      };

      jackCommand.set(typeof settings.command === "string" ? settings.command : "");
      jackTimeoutMs.set(positiveIntegerText(String(settings.timeoutMs ?? "")) ? String(settings.timeoutMs) : "5000");
      jackDelegateMode.set(settings.delegateMode === "detached" ? "detached" : "foreground");
      jackReadyDelayMs.set(
        nonNegativeIntegerText(String(settings.readyDelayMs ?? "")) ? String(settings.readyDelayMs) : "250"
      );
    } catch {
      storage.removeItem(jackRestoreStorageKey);
    }
  }

  function persistDsp(): void {
    storage.setItem(
      dspRestoreStorageKey,
      JSON.stringify({
        command: currentDsp.command,
        mode: currentDsp.mode,
        timeoutMs: currentDsp.timeoutMs,
        frameCount: currentDsp.frameCount
      })
    );
  }

  function persistJack(): void {
    storage.setItem(
      jackRestoreStorageKey,
      JSON.stringify({
        command: currentJack.command,
        timeoutMs: currentJack.timeoutMs,
        delegateMode: currentJack.delegateMode,
        readyDelayMs: currentJack.readyDelayMs
      })
    );
  }

  function setDspCommand(value: string): void {
    dspCommand.set(value);
    persistDsp();
  }

  function setDspMode(value: DspProviderMode): void {
    dspMode.set(value);
    persistDsp();
  }

  function setDspTimeout(value: string): void {
    dspTimeoutMs.set(value);
    persistDsp();
  }

  function setDspFrameCount(value: string): void {
    dspFrameCount.set(value);
    persistDsp();
  }

  function setJackCommand(value: string): void {
    jackCommand.set(value);
    persistJack();
  }

  function setJackTimeout(value: string): void {
    jackTimeoutMs.set(value);
    persistJack();
  }

  function setJackDelegateMode(value: JackProviderDelegateMode): void {
    jackDelegateMode.set(value);
    persistJack();
  }

  function setJackReadyDelay(value: string): void {
    jackReadyDelayMs.set(value);
    persistJack();
  }

  function dspSnapshot(): DspProviderSnapshot {
    const configured = currentDsp.command.trim().length > 0;
    const restoreReady =
      configured &&
      currentDsp.mode === "live" &&
      positiveIntegerText(currentDsp.timeoutMs) &&
      (currentDsp.frameCount.trim() === "" || positiveIntegerText(currentDsp.frameCount));

    return {
      command: currentDsp.command.trim(),
      mode: currentDsp.mode,
      timeoutMs: positiveIntegerNumber(currentDsp.timeoutMs, 5000),
      ...(currentDsp.frameCount.trim() !== ""
        ? { frameCount: positiveIntegerNumber(currentDsp.frameCount, 480) }
        : {}),
      restoreReady
    };
  }

  function jackSnapshot(): JackProviderSnapshot {
    const configured = currentJack.command.trim().length > 0;
    const timeoutValid = positiveIntegerText(currentJack.timeoutMs);
    const readyDelayValid =
      currentJack.delegateMode === "foreground" || nonNegativeIntegerText(currentJack.readyDelayMs);

    return {
      command: currentJack.command.trim(),
      timeoutMs: positiveIntegerNumber(currentJack.timeoutMs, 5000),
      delegateMode: currentJack.delegateMode,
      readyDelayMs: nonNegativeIntegerNumber(currentJack.readyDelayMs, 250),
      args: jackVirtualPortProviderArgs(currentJack.delegateMode, currentJack.readyDelayMs),
      configured,
      liveReady: configured && timeoutValid && readyDelayValid,
      restoreReady: !configured || (timeoutValid && readyDelayValid)
    };
  }

  return {
    dspCommand,
    dspMode,
    dspTimeoutMs,
    dspFrameCount,
    dspCommandConfigured,
    dspTimeoutValid,
    dspFrameCountValid,
    dspRestoreProviderReady,
    dspSettingsMessage,
    jackCommand,
    jackTimeoutMs,
    jackDelegateMode,
    jackReadyDelayMs,
    jackCommandConfigured,
    jackTimeoutValid,
    jackReadyDelayValid,
    jackRestoreProviderReady,
    jackLiveProviderReady,
    jackSettingsMessage,
    restore,
    setDspCommand,
    setDspMode,
    setDspTimeout,
    setDspFrameCount,
    setJackCommand,
    setJackTimeout,
    setJackDelegateMode,
    setJackReadyDelay,
    dspSnapshot,
    jackSnapshot
  };
}

/** Wrapper args that keep a detached JACK provider delegate alive before verification. */
export function jackVirtualPortProviderArgs(
  delegateMode: JackProviderDelegateMode,
  readyDelayMs: string
): readonly string[] {
  if (delegateMode !== "detached") {
    return [];
  }

  return ["--delegate-mode", "detached", "--ready-delay-ms", String(nonNegativeIntegerNumber(readyDelayMs, 250))];
}

export type ProviderSettingsService = ReturnType<typeof createProviderSettingsService>;
