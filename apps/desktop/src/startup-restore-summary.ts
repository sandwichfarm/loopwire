import type { LoopwireConfiguration } from "@loopwire/core";

export type StartupRestoreSummaryTone = "ready" | "setup" | "blocked";

export interface StartupRestoreSummaryInput {
  readonly configuration: Pick<LoopwireConfiguration, "name">;
  readonly selectedBackendName: string;
  readonly selectedBackendAvailable: boolean;
  readonly requiresProviderSettings?: boolean;
  readonly providerSettingsReady?: boolean;
  readonly enabled: boolean;
  readonly available: boolean;
}

export interface StartupRestoreSummary {
  readonly tone: StartupRestoreSummaryTone;
  readonly title: string;
  readonly message: string;
}

export function describeStartupRestoreSummary(input: StartupRestoreSummaryInput): StartupRestoreSummary {
  const configurationName = input.configuration.name;
  const backendName = normalizeBackendName(input.selectedBackendName);

  if (!input.available) {
    return {
      tone: "blocked",
      title: "Restore helper unavailable",
      message: `${configurationName} is still saved, but Loopwire cannot enable boot restore until the background launcher is available.`
    };
  }

  if (!backendName) {
    return {
      tone: "setup",
      title: `${configurationName} is saved`,
      message: "Select an audio backend before enabling live restore on boot."
    };
  }

  if (!input.selectedBackendAvailable) {
    return {
      tone: "blocked",
      title: `${backendName} is not detected`,
      message: `${configurationName} is still saved, but Loopwire will not enable boot restore until ${backendName} is detected again or you choose an available backend.`
    };
  }

  if (input.requiresProviderSettings && !input.providerSettingsReady) {
    return {
      tone: "blocked",
      title: `${backendName} settings needed`,
      message:
        `${configurationName} is still saved, but Restore on boot needs a live DSP provider command before ` +
        "Loopwire can enable background restore."
    };
  }

  if (!input.enabled) {
    return {
      tone: "setup",
      title: `${configurationName} is ready for boot restore`,
      message: `Enable Restore on boot to reapply this configuration with ${backendName} when your user session starts.`
    };
  }

  return {
    tone: "ready",
    title: `${configurationName} restores on boot`,
    message: `Loopwire will reapply this configuration with ${backendName} through the user-scoped background service.`
  };
}

function normalizeBackendName(selectedBackendName: string): string {
  return selectedBackendName === "None selected" ? "" : selectedBackendName;
}
