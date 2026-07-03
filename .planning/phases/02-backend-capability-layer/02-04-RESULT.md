# Phase 2 Supplemental Result: Guarded pactl Sink-Input Controls

**Completed:** 2026-07-03
**Requirements:** BACKEND-01, BACKEND-03, CONFIG-01 support path

## Delivered

- Added optional route `gain` to the audio-host runtime configuration contract.
- Applied matching route gain through `pactl set-sink-input-volume`.
- Applied matching route mute through `pactl set-sink-input-mute`.
- Verified matching stream sink, volume, and mute state during runtime verification.
- Restored original stream sink, volume, and mute when a later stream operation fails.
- Extracted the pactl runtime context and operation helpers so host mutation logic is smaller and easier to review.
- Updated PulseAudio/PipeWire compatibility capability gaps and docs to describe stream-level controls accurately.

## Boundaries

- Dry-run remains the default.
- Validation did not run live `pactl set-sink-input-volume` or `pactl set-sink-input-mute`.
- Stream matching still uses endpoint id/label tokens against current `pactl list sink-inputs` metadata.
- Gain/mute support is stream-level, not true graph-level per-edge mixing.

## Next Work

- Build explicit user consent for live host apply mode.
- Add monitor route semantics.
- Add a graph-native backend for true per-edge mixing.
