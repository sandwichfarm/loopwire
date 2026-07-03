# Phase 2 Supplemental Verification: Guarded pactl Sink-Input Controls

**Date:** 2026-07-03
**Status:** Passed for fake-runner stream control behavior

## Evidence

- `pnpm --filter @loopwire/audio-host test` passed with 14 tests.
- `pnpm --filter @loopwire/audio-host typecheck` passed.
- Line-length check passed for touched audio-host files.
- `pnpm check` passed across scripts, autostart, install, release, packaging, VM validation, lint, typecheck, tests,
  docs build, core build, audio-host build, and desktop Vite build.
- `pnpm detect:audio` passed and reported PulseAudio compatibility with `createVirtualDevice`, `routeAudio`, `apply`,
  `verify`, and `rollback` implemented; remaining gaps are monitor routing and true per-edge mixing beyond sink-input
  controls.
- `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml` passed.
- Workflow YAML parsed with Ruby for all workflow files.
- `gsd-sdk query init.milestone-op` and `gsd-sdk query roadmap.analyze` passed; roadmap reports Phase 2 with 4 plans.
- `mcp__codebase_memory_mcp.index_repository` passed in fast mode with persistence enabled.
- Code graph sanity check reports `createPactlVirtualSinkRuntimeAdapter` at 15 lines and `routeConfiguredSinkInputs`
  at cyclomatic complexity 7.
- The focused tests verify:
  - matching sink inputs move to the Loopwire virtual sink,
  - route gain applies as `set-sink-input-volume`,
  - route mute applies as `set-sink-input-mute`,
  - a later stream-operation failure restores original mute, volume, and sink,
  - route verification fails when host volume or mute differs from the route.

## Remaining Risk

No live `pactl` stream-control command was run during validation. That remains intentional until the desktop/runtime path
has explicit user consent and a visible rollback surface.
