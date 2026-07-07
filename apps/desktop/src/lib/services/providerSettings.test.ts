import { describe, expect, it } from "vitest";
import { get } from "svelte/store";
import type { BackendCandidate } from "@loopwire/core";
import {
  createProviderSettingsService,
  dspRestoreStorageKey,
  jackRestoreStorageKey,
  jackVirtualPortProviderArgs,
  nonNegativeIntegerText,
  positiveIntegerText,
  withDspProviderCandidate,
  type ProviderSettingsStorage
} from "./providerSettings";

function createFakeStorage(initial: Record<string, string> = {}): ProviderSettingsStorage & {
  readonly data: Map<string, string>;
} {
  const data = new Map(Object.entries(initial));

  return {
    data,
    getItem: (key) => data.get(key) ?? null,
    setItem: (key, value) => void data.set(key, value),
    removeItem: (key) => void data.delete(key)
  };
}

describe("integer text validation", () => {
  it("accepts positive integers only for positiveIntegerText", () => {
    expect(positiveIntegerText("5000")).toBe(true);
    expect(positiveIntegerText(" 480 ")).toBe(true);
    expect(positiveIntegerText("0")).toBe(false);
    expect(positiveIntegerText("-1")).toBe(false);
    expect(positiveIntegerText("12.5")).toBe(false);
    expect(positiveIntegerText("")).toBe(false);
  });

  it("accepts zero for nonNegativeIntegerText", () => {
    expect(nonNegativeIntegerText("0")).toBe(true);
    expect(nonNegativeIntegerText("250")).toBe(true);
    expect(nonNegativeIntegerText("-1")).toBe(false);
    expect(nonNegativeIntegerText("01")).toBe(false);
  });
});

describe("DSP provider readiness", () => {
  it("is not ready without a command", () => {
    const service = createProviderSettingsService(createFakeStorage());

    expect(get(service.dspRestoreProviderReady)).toBe(false);
    expect(get(service.dspSettingsMessage)).toContain("appears after a live provider command is saved");
  });

  it("is ready with a live command and valid numbers", () => {
    const service = createProviderSettingsService(createFakeStorage());

    service.setDspCommand("loopwire-live-dsp-provider");

    expect(get(service.dspRestoreProviderReady)).toBe(true);
    expect(get(service.dspSettingsMessage)).toContain("can be selected for provider-backed Restore on boot");
  });

  it("blocks file-backed mode for restore readiness", () => {
    const service = createProviderSettingsService(createFakeStorage());

    service.setDspCommand("loopwire-live-dsp-provider");
    service.setDspMode("file-backed");

    expect(get(service.dspRestoreProviderReady)).toBe(false);
    expect(get(service.dspSettingsMessage)).toContain("File smoke providers stay blocked");
  });

  it("blocks invalid timeout or frame count but allows an empty frame count", () => {
    const service = createProviderSettingsService(createFakeStorage());

    service.setDspCommand("loopwire-live-dsp-provider");
    service.setDspTimeout("nope");
    expect(get(service.dspRestoreProviderReady)).toBe(false);

    service.setDspTimeout("5000");
    service.setDspFrameCount("-2");
    expect(get(service.dspRestoreProviderReady)).toBe(false);

    service.setDspFrameCount("");
    expect(get(service.dspRestoreProviderReady)).toBe(true);
  });

  it("exposes a trimmed numeric snapshot with an optional frame count", () => {
    const service = createProviderSettingsService(createFakeStorage());

    service.setDspCommand("  loopwire-live-dsp-provider  ");
    service.setDspTimeout("2500");
    service.setDspFrameCount("");

    expect(service.dspSnapshot()).toEqual({
      command: "loopwire-live-dsp-provider",
      mode: "live",
      timeoutMs: 2500,
      restoreReady: true
    });
  });
});

describe("JACK provider readiness", () => {
  it("treats a blank command as restore-ready but not live-ready", () => {
    const service = createProviderSettingsService(createFakeStorage());

    expect(get(service.jackRestoreProviderReady)).toBe(true);
    expect(get(service.jackLiveProviderReady)).toBe(false);
    expect(get(service.jackSettingsMessage)).toContain("Leave blank to use pre-existing JACK ports");
  });

  it("requires a valid timeout when a command is saved", () => {
    const service = createProviderSettingsService(createFakeStorage());

    service.setJackCommand("loopwire-jack-ports");
    service.setJackTimeout("abc");

    expect(get(service.jackRestoreProviderReady)).toBe(false);
    expect(get(service.jackLiveProviderReady)).toBe(false);
    expect(get(service.jackSettingsMessage)).toContain("Timeout must be positive");
  });

  it("only validates the readiness delay in detached mode", () => {
    const service = createProviderSettingsService(createFakeStorage());

    service.setJackCommand("loopwire-jack-ports");
    service.setJackReadyDelay("nope");
    expect(get(service.jackLiveProviderReady)).toBe(true);

    service.setJackDelegateMode("detached");
    expect(get(service.jackLiveProviderReady)).toBe(false);

    service.setJackReadyDelay("0");
    expect(get(service.jackLiveProviderReady)).toBe(true);
    expect(get(service.jackSettingsMessage)).toContain("keep the JACK provider delegate alive");
  });

  it("adds detached wrapper args to the snapshot", () => {
    const service = createProviderSettingsService(createFakeStorage());

    service.setJackCommand("loopwire-jack-ports");
    expect(service.jackSnapshot().args).toEqual([]);

    service.setJackDelegateMode("detached");
    service.setJackReadyDelay("750");
    expect(service.jackSnapshot()).toMatchObject({
      command: "loopwire-jack-ports",
      timeoutMs: 5000,
      delegateMode: "detached",
      readyDelayMs: 750,
      args: ["--delegate-mode", "detached", "--ready-delay-ms", "750"],
      configured: true,
      liveReady: true,
      restoreReady: true
    });
  });
});

describe("persistence under the legacy storage keys", () => {
  it("persists DSP settings to loopwire.dsp-restore.v1", () => {
    const storage = createFakeStorage();
    const service = createProviderSettingsService(storage);

    service.setDspCommand("loopwire-live-dsp-provider");
    service.setDspMode("file-backed");
    service.setDspTimeout("2500");
    service.setDspFrameCount("960");

    expect(JSON.parse(storage.data.get(dspRestoreStorageKey) ?? "{}")).toEqual({
      command: "loopwire-live-dsp-provider",
      mode: "file-backed",
      timeoutMs: "2500",
      frameCount: "960"
    });
  });

  it("persists JACK settings to loopwire.jack-restore.v1", () => {
    const storage = createFakeStorage();
    const service = createProviderSettingsService(storage);

    service.setJackCommand("loopwire-jack-ports");
    service.setJackDelegateMode("detached");
    service.setJackReadyDelay("750");

    expect(JSON.parse(storage.data.get(jackRestoreStorageKey) ?? "{}")).toEqual({
      command: "loopwire-jack-ports",
      timeoutMs: "5000",
      delegateMode: "detached",
      readyDelayMs: "750"
    });
  });

  it("restores pre-rebuild saved settings", () => {
    const storage = createFakeStorage({
      [dspRestoreStorageKey]: JSON.stringify({
        command: "loopwire-live-dsp-provider",
        mode: "live",
        timeoutMs: "2500",
        frameCount: "960"
      }),
      [jackRestoreStorageKey]: JSON.stringify({
        command: "loopwire-jack-ports",
        timeoutMs: "7000",
        delegateMode: "detached",
        readyDelayMs: "750"
      })
    });
    const service = createProviderSettingsService(storage);

    service.restore();

    expect(get(service.dspCommand)).toBe("loopwire-live-dsp-provider");
    expect(get(service.dspTimeoutMs)).toBe("2500");
    expect(get(service.dspFrameCount)).toBe("960");
    expect(get(service.dspRestoreProviderReady)).toBe(true);
    expect(get(service.jackCommand)).toBe("loopwire-jack-ports");
    expect(get(service.jackTimeoutMs)).toBe("7000");
    expect(get(service.jackDelegateMode)).toBe("detached");
    expect(get(service.jackReadyDelayMs)).toBe("750");
    expect(get(service.jackLiveProviderReady)).toBe(true);
  });

  it("falls back to defaults for invalid stored values", () => {
    const storage = createFakeStorage({
      [dspRestoreStorageKey]: JSON.stringify({ command: 42, mode: "weird", timeoutMs: "-3", frameCount: "abc" }),
      [jackRestoreStorageKey]: JSON.stringify({ command: "loopwire-jack-ports", timeoutMs: "0", readyDelayMs: "-1" })
    });
    const service = createProviderSettingsService(storage);

    service.restore();

    expect(get(service.dspCommand)).toBe("");
    expect(get(service.dspMode)).toBe("live");
    expect(get(service.dspTimeoutMs)).toBe("5000");
    expect(get(service.dspFrameCount)).toBe("480");
    expect(get(service.jackTimeoutMs)).toBe("5000");
    expect(get(service.jackDelegateMode)).toBe("foreground");
    expect(get(service.jackReadyDelayMs)).toBe("250");
  });

  it("removes unparsable stored payloads", () => {
    const storage = createFakeStorage({
      [dspRestoreStorageKey]: "{not json",
      [jackRestoreStorageKey]: "{not json"
    });
    const service = createProviderSettingsService(storage);

    service.restore();

    expect(storage.data.has(dspRestoreStorageKey)).toBe(false);
    expect(storage.data.has(jackRestoreStorageKey)).toBe(false);
  });
});

describe("jackVirtualPortProviderArgs", () => {
  it("is empty in foreground mode", () => {
    expect(jackVirtualPortProviderArgs("foreground", "750")).toEqual([]);
  });

  it("carries the readiness delay in detached mode with a fallback", () => {
    expect(jackVirtualPortProviderArgs("detached", "750")).toEqual([
      "--delegate-mode",
      "detached",
      "--ready-delay-ms",
      "750"
    ]);
    expect(jackVirtualPortProviderArgs("detached", "nope")).toEqual([
      "--delegate-mode",
      "detached",
      "--ready-delay-ms",
      "250"
    ]);
  });
});

describe("withDspProviderCandidate", () => {
  const detected: readonly BackendCandidate[] = [
    { kind: "pipewire", displayName: "PipeWire", availability: "available", priority: 10 },
    { kind: "jack", displayName: "JACK", availability: "unavailable", priority: 30, reason: "JACK bridge not detected" },
    { kind: "alsa", displayName: "ALSA", availability: "unavailable", priority: 40, reason: "diagnostics only" }
  ];

  it("adds an unavailable DSP candidate with a setup reason when the provider is not ready", () => {
    const candidates = withDspProviderCandidate(detected, false);
    const dsp = candidates.find((candidate) => candidate.kind === "dsp");

    expect(dsp?.availability).toBe("unavailable");
    expect(dsp?.reason).toContain("Configure a live DSP provider command");
  });

  it("marks DSP available and keeps candidates sorted by priority when ready", () => {
    const candidates = withDspProviderCandidate(detected, true);

    expect(candidates.map((candidate) => candidate.kind)).toEqual(["pipewire", "jack", "dsp", "alsa"]);
    expect(candidates.find((candidate) => candidate.kind === "dsp")?.availability).toBe("available");
  });

  it("replaces a pre-existing DSP candidate instead of duplicating it", () => {
    const withDsp = withDspProviderCandidate([...detected, ...withDspProviderCandidate([], false)], true);

    expect(withDsp.filter((candidate) => candidate.kind === "dsp")).toHaveLength(1);
    expect(withDsp.find((candidate) => candidate.kind === "dsp")?.availability).toBe("available");
  });
});
