# Phase 2 Summary: Backend Capability Layer

## Completed

- Added `@loopwire/audio-host`, initially as a read-only host detection package for Linux audio backends.
- Implemented injected command execution with timeout/missing-command handling.
- Implemented detectors for PipeWire, PulseAudio/PipeWire compatibility, JACK, and ALSA.
- Added typed backend capability reports, operations state, diagnostics, command probes, and core-compatible candidates.
- Added fake-runner coverage for available, missing, fallback, compatibility, unavailable, and redaction cases.
- Added `pnpm detect:audio` and `scripts/detect-audio-backends.mjs`.
- Updated CT diagnostics to include detector JSON and redact sensitive local fields.
- Updated docs and README for the current backend detection contract.
- Fixed TypeScript package output directories so core and audio-host builds emit package-local `dist/` output.
- Added a supplemental guarded `pactl` virtual-sink runtime adapter for PulseAudio and PipeWire compatibility. It is
  dry-run by default and covers create, verify, unload, and rollback for Loopwire-owned null sinks.
- Added a supplemental guarded stream-routing primitive that moves matching `pactl` sink inputs into Loopwire virtual
  sinks and rolls moved streams back if a later move fails.
- Added guarded sink-input volume/mute apply and verification for matching routed streams, with rollback to original
  sink, volume, and mute if a later stream operation fails.
- Added guarded Loopwire-owned monitor sinks and `module-loopback` links from output monitor sources to configured
  monitor sinks, with module verification and rollback.

## Verification

- `pnpm check` passed.
- `pnpm --filter @loopwire/audio-host test` passed for backend detection and virtual-sink runtime coverage.
- `pnpm --filter @loopwire/audio-host test` and typecheck passed for stream move, volume/mute apply, verification, and
  rollback coverage.
- `pnpm --filter @loopwire/audio-host test` and typecheck passed for monitor sink creation, loopback verification, and
  rollback coverage.
- Full validation passed after the supplemental sink-input control work: `pnpm check`, `pnpm detect:audio`,
  `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml`, workflow YAML parse, GSD state queries, and graph
  reindex with persistence.
- `pnpm detect:audio` passed with PipeWire, PulseAudio compatibility, and ALSA available on this host.
- `bash scripts/ct-host-check.sh` passed.
- `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml` passed.
- Workflow YAML parse and `git diff --check` passed.

## Remaining Risks

- Full routing is still incomplete. Physical monitor device binding and true per-edge matrix mixing beyond sink-input
  controls remain planned.
- JACK is modeled and tested but unavailable on this host because `jack_lsp` is missing.
- `actionlint` is unavailable locally.
