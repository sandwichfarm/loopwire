# Phase 11 Context: True Per-Edge Matrix Semantics

## Goal

Make route-control semantics explicit so Loopwire can support true per-edge gain/mute in the model while backends report
when they degrade to stream-level or link-only behavior.

## Constraints

- Do not imply PulseAudio compatibility can apply independent controls to two edges of the same stream.
- Do not imply native PipeWire link routing can apply gain/mute through `pw-link`.
- Keep backend capability reports machine-readable for diagnostics and UI messaging.

## Inputs

- Core `AudioRoute` already stores per-route gain and mute.
- PulseAudio compatibility applies controls to whole matching sink inputs.
- Native PipeWire currently links ports only.

## Acceptance

- Core tests cover one source routed to multiple outputs with independent route controls.
- Backend capability reports include route-control semantics.
- Desktop shows selected-backend degraded route-control behavior.
- Docs explain stream-level and link-only limitations without hiding the UX control.
