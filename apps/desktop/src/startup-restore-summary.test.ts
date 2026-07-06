import { describe, expect, it } from "vitest";
import { describeStartupRestoreSummary } from "./startup-restore-summary";

const configuration = { name: "Podcast mix" };

describe("describeStartupRestoreSummary", () => {
  it("names the active configuration and selected backend when boot restore is enabled", () => {
    expect(
      describeStartupRestoreSummary({
        configuration,
        selectedBackendName: "PipeWire",
        selectedBackendAvailable: true,
        enabled: true,
        available: true
      })
    ).toEqual({
      tone: "ready",
      title: "Podcast mix restores on boot",
      message: "Loopwire will reapply this configuration with PipeWire through the user-scoped background service."
    });
  });

  it("keeps disabled restore explicit without implying failure", () => {
    expect(
      describeStartupRestoreSummary({
        configuration,
        selectedBackendName: "JACK",
        selectedBackendAvailable: true,
        enabled: false,
        available: true
      })
    ).toEqual({
      tone: "setup",
      title: "Podcast mix is ready for boot restore",
      message: "Enable Restore on boot to reapply this configuration with JACK when your user session starts."
    });
  });

  it("asks for a saved backend before live boot restore", () => {
    expect(
      describeStartupRestoreSummary({
        configuration,
        selectedBackendName: "None selected",
        selectedBackendAvailable: false,
        enabled: false,
        available: true
      })
    ).toEqual({
      tone: "setup",
      title: "Podcast mix is saved",
      message: "Select an audio backend before enabling live restore on boot."
    });
  });

  it("keeps the selected configuration visible when the background launcher is blocked", () => {
    expect(
      describeStartupRestoreSummary({
        configuration,
        selectedBackendName: "PipeWire",
        selectedBackendAvailable: true,
        enabled: false,
        available: false
      })
    ).toEqual({
      tone: "blocked",
      title: "Restore helper unavailable",
      message:
        "Podcast mix is still saved, but Loopwire cannot enable boot restore until the background launcher is available."
    });
  });

  it("blocks enabling restore when the saved backend is no longer detected", () => {
    expect(
      describeStartupRestoreSummary({
        configuration,
        selectedBackendName: "JACK",
        selectedBackendAvailable: false,
        enabled: false,
        available: true
      })
    ).toEqual({
      tone: "blocked",
      title: "JACK is not detected",
      message:
        "Podcast mix is still saved, but Loopwire will not enable boot restore until JACK is detected again or you choose an available backend."
    });
  });

  it("blocks DSP restore until provider settings are ready", () => {
    expect(
      describeStartupRestoreSummary({
        configuration,
        selectedBackendName: "DSP Provider",
        selectedBackendAvailable: true,
        requiresProviderSettings: true,
        providerSettingsReady: false,
        enabled: false,
        available: true
      })
    ).toEqual({
      tone: "blocked",
      title: "DSP Provider settings needed",
      message:
        "Podcast mix is still saved, but Restore on boot needs a live DSP provider command before " +
        "Loopwire can enable background restore."
    });
  });
});
