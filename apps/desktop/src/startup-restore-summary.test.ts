import { describe, expect, it } from "vitest";
import { describeStartupRestoreSummary } from "./startup-restore-summary";

const configuration = { name: "Podcast mix" };

describe("describeStartupRestoreSummary", () => {
  it("names the active configuration and selected backend when boot restore is enabled", () => {
    expect(
      describeStartupRestoreSummary({
        configuration,
        selectedBackendName: "PipeWire",
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
});
