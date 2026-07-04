import type { BackendDecision } from "@loopwire/core";

export type BackendChoiceCalloutTone = "prompt" | "ready" | "blocked";

export interface BackendChoiceCallout {
  readonly tone: BackendChoiceCalloutTone;
  readonly title: string;
  readonly message: string;
  readonly action: string;
}

export function describeBackendChoiceCallout(
  decision: BackendDecision,
  selectedBackendName: string
): BackendChoiceCallout {
  if (decision.mode === "prompt") {
    const names = decision.candidates.map((candidate) => candidate.displayName).join(", ");
    return {
      tone: "prompt",
      title: "Choose an audio backend",
      message: `${names} are available. Pick the backend Loopwire should use for live apply and startup restore.`,
      action: "Select a backend below to save the choice."
    };
  }

  if (decision.mode === "none") {
    return {
      tone: "blocked",
      title: "No supported backend detected",
      message: "Loopwire is staying in preview mode until a Linux audio backend probe succeeds.",
      action: "Open diagnostics for probe results and setup guidance."
    };
  }

  if (selectedBackendName !== "None selected") {
    return {
      tone: "ready",
      title: `${selectedBackendName} is selected`,
      message: "This backend choice is saved with your Loopwire state and reused by startup restore.",
      action: "Switching backend later will disarm live apply until preview verification passes."
    };
  }

  return {
    tone: "ready",
    title: `${decision.backend.displayName} selected automatically`,
    message: "Only one supported backend is available, so Loopwire can continue without asking.",
    action: "You can still change the backend from settings when another backend becomes available."
  };
}
