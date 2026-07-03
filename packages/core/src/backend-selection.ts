import type { AudioBackendKind, BackendCandidate, BackendDecision } from "./types.js";

export function selectBackend(
  candidates: readonly BackendCandidate[],
  preferred?: AudioBackendKind
): BackendDecision {
  const available = candidates
    .filter((candidate) => candidate.availability === "available")
    .toSorted((left, right) => left.priority - right.priority);

  if (available.length === 0) {
    return {
      mode: "none",
      reason: "No supported Linux audio backend is currently available."
    };
  }

  const preferredCandidate = available.find((candidate) => candidate.kind === preferred);
  if (preferredCandidate) {
    return {
      mode: "auto",
      backend: preferredCandidate,
      reason: "The previously selected backend is still available."
    };
  }

  if (available.length === 1) {
    const backend = requireFirst(available);
    return {
      mode: "auto",
      backend,
      reason: "Exactly one supported audio backend is available."
    };
  }

  return {
    mode: "prompt",
    candidates: available,
    reason: "Multiple supported audio backends are available. The user must choose one."
  };
}

export function getBackendCandidate(
  candidates: readonly BackendCandidate[],
  kind: AudioBackendKind
): BackendCandidate | undefined {
  return candidates.find((candidate) => candidate.kind === kind);
}

function requireFirst<T>(items: readonly T[]): T {
  const [first] = items;
  if (first === undefined) {
    throw new Error("Expected at least one item.");
  }

  return first;
}
