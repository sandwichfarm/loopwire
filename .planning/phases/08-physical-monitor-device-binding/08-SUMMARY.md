# Phase 8 Summary: Physical Monitor Device Binding

## Completed

- Added optional `deviceName` to `AudioEndpoint`.
- Persisted monitor device names through state restore and configuration import/export.
- Added desktop monitor host-sink editing with persisted configuration updates.
- Added optional `deviceName` to audio-host runtime endpoints.
- Updated pactl monitor loopback planning to target physical sink names when configured.
- Kept Loopwire-owned monitor sink creation for monitors without a physical target.
- Added verification for missing physical monitor target sinks.
- Updated unload matching so physical monitor loopbacks unload without touching physical sinks or unrelated loopbacks.

## Verification

- `pnpm --filter @loopwire/core test` passed with 28 tests.
- `pnpm --filter @loopwire/core typecheck` passed.
- `pnpm --filter @loopwire/audio-host test` passed with 20 tests.
- `pnpm --filter @loopwire/audio-host typecheck` passed.
- `pnpm --filter @loopwire/desktop typecheck` passed.
- `pnpm check`, `pnpm detect:audio`, Rust `cargo check`, workflow YAML parse, GSD queries, line-length checks, and
  `git diff --check` passed.
- Playwright visual smoke passed at desktop and mobile viewports with the monitor `Host sink` input visible, editable,
  and without horizontal overflow.

## Remaining Risks

- The UI currently accepts a host sink name as text; physical sink enumeration and selection remain future work.
- No live `pactl` mutation was run.
