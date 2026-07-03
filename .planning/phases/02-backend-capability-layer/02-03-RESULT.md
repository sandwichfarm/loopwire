# Phase 2 Supplemental Result: Guarded pactl Stream Routing

**Completed:** 2026-07-03
**Requirements:** BACKEND-01, BACKEND-03, CONFIG-01 support path

## Delivered

- Extended `HostRuntimeConfiguration` with optional `inputs` and `routes`.
- Implemented sink-input move plans for non-muted routes.
- Added `pactl list sink-inputs` parsing and metadata token matching.
- Added `pactl move-sink-input` routing through the existing command runner.
- Added rollback of already-moved sink inputs on later move failure.
- Updated PulseAudio/PipeWire compatibility capability reports to mark `routeAudio` as implemented for this subset.
- Updated docs with the current stream-matching boundary.

## Boundaries

- Dry-run remains the default.
- Validation did not run live `pactl move-sink-input`.
- Stream matching is intentionally primitive: input endpoint id and label tokens against current sink-input metadata.
- Monitor routing and per-route gain/mute host apply remain incomplete.

## Next Work

- Design a proper app/source selector model for stable stream matching.
- Expose host apply mode in the desktop through an explicit consent UI.
- Add monitor routes and gain/mute support.
