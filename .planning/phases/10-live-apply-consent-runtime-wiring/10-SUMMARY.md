# Phase 10 Summary: Live Apply Consent and Runtime Wiring

## Completed

- Added a browser-safe audio-host runtime export that excludes the Node command runner.
- Added a constrained Tauri command bridge for `pactl` and `pw-link`.
- Wired desktop runtime operations to selected host adapters.
- Added a `Host apply` control with preview and session-local live-armed states.
- Kept startup verification in preview mode.
- Made browser/dev live apply fail closed without host mutation.
- Documented the command boundary, preview mode, and remaining backend gaps.

## Verification

- `pnpm --filter @loopwire/desktop typecheck` passed.
- `pnpm --filter @loopwire/audio-host typecheck` passed.
- `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml` passed.
- `pnpm check` passed.
- Playwright visual smoke passed at desktop and mobile viewports with `Host apply` visible, toggleable, fail-closed in
  browser preview, and without horizontal overflow.

## Remaining Risks

- No live host mutation was performed during validation.
- JACK and ALSA remain diagnostics-only.
- Native PipeWire virtual nodes and gain/mute controls remain planned.
