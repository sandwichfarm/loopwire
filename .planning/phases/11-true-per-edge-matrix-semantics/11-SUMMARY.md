# Phase 11 Summary: True Per-Edge Matrix Semantics

## Completed

- Added `BackendMixingSemantics` to audio-host capability reports.
- Reported native PipeWire as link-only.
- Reported PulseAudio compatibility as stream-level.
- Reported unavailable/planned backends without claiming per-edge controls.
- Added desktop route-control semantics status for the selected backend.
- Added core regression coverage for one source targeting multiple outputs with independent gain/mute values.
- Updated docs and unreleased notes.

## Verification

- `pnpm --filter @loopwire/audio-host test` passed with 3 files and 27 tests.
- `pnpm --filter @loopwire/audio-host typecheck` passed.
- `pnpm --filter @loopwire/desktop typecheck` passed with 0 errors and 0 warnings.
- `pnpm check` passed.
- Playwright visual smoke passed at desktop and mobile viewports with semantics switching from PipeWire link-only to
  PulseAudio stream-level and no horizontal overflow.

## Remaining Risks

- Backend DSP or graph-edge gain/mute implementation remains planned.
- PulseAudio compatibility still applies controls at stream scope.
- Native PipeWire still links ports only.
