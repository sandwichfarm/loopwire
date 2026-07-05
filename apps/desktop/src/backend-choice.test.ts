import { describe, expect, it } from "vitest";
import type { BackendCandidate } from "@loopwire/core";
import { describeBackendChoiceCallout } from "./backend-choice";

const pipewire: BackendCandidate = {
  kind: "pipewire",
  displayName: "PipeWire",
  availability: "available",
  priority: 10
};

const jack: BackendCandidate = {
  kind: "jack",
  displayName: "JACK",
  availability: "available",
  priority: 30
};

describe("describeBackendChoiceCallout", () => {
  it("turns multi-backend prompt mode into an explicit user action", () => {
    expect(
      describeBackendChoiceCallout(
        {
          mode: "prompt",
          candidates: [pipewire, jack],
          reason: "Multiple supported audio backends are available. The user must choose one."
        },
        "None selected"
      )
    ).toEqual({
      tone: "prompt",
      title: "Choose an audio backend",
      message: "PipeWire, JACK are available. Pick the backend Loopwire should use for live apply and startup restore.",
      action: "Select a backend below to save the choice."
    });
  });

  it("keeps unavailable detection in a blocked callout", () => {
    expect(
      describeBackendChoiceCallout(
        {
          mode: "none",
          reason: "No supported Linux audio backend is currently available."
        },
        "None selected"
      )
    ).toMatchObject({
      tone: "blocked",
      title: "No supported backend detected"
    });
  });

  it("names a stale saved backend when the user must choose another available backend", () => {
    expect(
      describeBackendChoiceCallout(
        {
          mode: "prompt",
          candidates: [pipewire, jack],
          reason: "Multiple supported audio backends are available. The user must choose one."
        },
        "PulseAudio",
        false
      )
    ).toEqual({
      tone: "prompt",
      title: "PulseAudio is not detected",
      message:
        "PipeWire, JACK are available. Pick a new backend before Loopwire saves live apply and startup restore again.",
      action: "Select an available backend below to replace the stale saved choice."
    });
  });

  it("describes saved and auto-selected backends separately", () => {
    expect(
      describeBackendChoiceCallout(
        {
          mode: "auto",
          backend: jack,
          reason: "The previously selected backend is still available."
        },
        "JACK"
      )
    ).toMatchObject({
      tone: "ready",
      title: "JACK is selected"
    });

    expect(
      describeBackendChoiceCallout(
        {
          mode: "auto",
          backend: pipewire,
          reason: "Exactly one supported audio backend is available."
        },
        "None selected"
      )
    ).toMatchObject({
      tone: "ready",
      title: "PipeWire selected automatically"
    });
  });
});
