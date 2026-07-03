# Phase 9 Summary: Native PipeWire Graph Adapter

## Completed

- Added a dry-run-by-default `createPipeWireGraphRuntimeAdapter`.
- Planned native routes from endpoint `deviceName` values against `pw-link -o` and `pw-link -i` port lists.
- Linked matching PipeWire port pairs with `pw-link`.
- Verified expected links from `pw-link -l`.
- Unlinked only configured route pairs during unload/rollback.
- Rolled back already-created links when a later link operation failed.
- Rejected non-unity route gain before attempting host commands.
- Updated backend detection to report native PipeWire route apply, verify, and rollback as implemented.
- Updated docs and release notes to keep virtual nodes, monitor routing, gain/mute, and live desktop apply as gaps.

## Verification

- `pnpm --filter @loopwire/audio-host test` passed with 3 files and 27 tests.
- `pnpm --filter @loopwire/audio-host typecheck` passed.
- `pnpm check`, `pnpm detect:audio`, Rust `cargo check`, workflow YAML parse, GSD queries, and `git diff --check`
  passed after docs and planning updates.

## Remaining Risks

- Native PipeWire virtual-node creation is not implemented.
- Native PipeWire monitor routing is not implemented.
- Native PipeWire gain/mute controls are not implemented.
- No live `pw-link` mutation was performed.
