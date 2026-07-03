# Phase 2 Supplemental Verification: Guarded pactl Stream Routing

**Date:** 2026-07-03
**Status:** Passed for fake-runner stream routing behavior

## Evidence

- `pnpm --filter @loopwire/audio-host test` passed with 13 tests.
- `pnpm --filter @loopwire/audio-host typecheck` passed.
- The new stream-routing tests verify:
  - matching sink inputs move to the Loopwire virtual sink,
  - muted routes do not move streams,
  - a later move failure restores already-moved streams to their original sink,
  - route verification fails when a matching stream is on the wrong sink.

## Remaining Risk

No live `pactl move-sink-input` command was run during validation. That remains intentional until the desktop/runtime
path has explicit user consent and a visible rollback surface.
