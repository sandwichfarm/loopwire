# Phase 2 Supplemental Result: Guarded pactl Monitor Loopbacks

**Completed:** 2026-07-03
**Requirements:** BACKEND-01, BACKEND-03, CONFIG-01 support path

## Delivered

- Added optional `monitors` to `HostRuntimeConfiguration`.
- Added deterministic Loopwire monitor sink names.
- Created monitor sinks with `module-null-sink`.
- Linked output monitor sources to monitor sinks with `module-loopback`.
- Verified configured monitor loopback modules by source and sink arguments.
- Updated unload matching so Loopwire-owned null sinks and loopback modules are removed without touching unrelated
  modules.
- Updated PulseAudio compatibility capability reports to mark monitor audio implemented for this subset.
- Updated docs and unreleased notes with the current monitor boundary.

## Boundaries

- Dry-run remains the default.
- Validation did not run live `pactl load-module module-loopback`.
- Monitor endpoints currently map to Loopwire-owned monitor sinks, not physical hardware outputs.
- Native graph routing and true per-edge mixing remain future backend work.

## Next Work

- Add physical monitor device binding and selection.
- Add explicit consent UI for live backend apply.
- Design native PipeWire graph apply/verify/rollback.
