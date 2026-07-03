# Phase 3 Verification: Configuration Runtime

**Date:** 2026-07-03
**Status:** Passed

## Automated Gates

- `pnpm --filter @loopwire/core test` passed before UI wiring: 4 files, 23 tests.
- `pnpm --filter @loopwire/core typecheck` passed.
- `pnpm --filter @loopwire/desktop typecheck` passed.
- `pnpm --filter @loopwire/desktop build` passed.
- `pnpm check` passed after all changes: workspace typecheck, tests, docs build, core/audio builds, and desktop build.
- `pnpm verify:scripts` passed.
- `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml` passed.
- `ruby -e 'require "yaml"; Dir[".github/workflows/*.yml"].each { |path| YAML.load_file(path); puts path }'` passed.
- `git diff --check` passed.

## Runtime and Host Evidence

- `pnpm detect:audio` passed and reported:
  - PipeWire available, version 1.6.7.
  - PulseAudio compatibility available on PipeWire 1.6.7.
  - ALSA available.
  - JACK unavailable because `jack_lsp` is missing.
- `bash scripts/ct-host-check.sh` passed and produced redacted host diagnostics.

## Browser Evidence

- Vite dev server ran at `http://127.0.0.1:5174/`.
- Playwright desktop smoke at 1440x900 passed:
  - duplicate configuration action worked,
  - export panel opened,
  - exported JSON contained `loopwire.configuration`,
  - horizontal overflow was 0.
- Playwright mobile smoke at 390x844 passed:
  - app rendered without page errors,
  - horizontal overflow was 0,
  - responsive status strips wrapped without overlap.
- Screenshots were captured under `/tmp/loopwire-ui-verify/desktop.png` and `/tmp/loopwire-ui-verify/mobile.png`.

## Skipped Checks

- `actionlint` was not installed on this host; workflow validation used Ruby YAML parsing.
- `nix` was not installed on this host; the flake was not evaluated.

## Remaining Risk

The configuration runtime uses an app-local adapter. It proves transaction ordering, rollback, persistence, and UI
behavior, but it does not mutate PipeWire, PulseAudio, JACK, or ALSA. Real host graph application remains a backend
adapter phase.
