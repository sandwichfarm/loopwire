# Phase 5 Verification: Release Artifact and Package Smoke

**Date:** 2026-07-03
**Status:** Passed for local installer and package metadata smoke

## Installer Evidence

- `pnpm verify:install` passed.
- The verifier created a local `loopwire-linux-x86_64.tar.gz` fake release artifact.
- The verifier generated `SHA256SUMS`, ran `scripts/install.sh --base-url file://...`, installed into a temporary prefix,
  and executed the installed `loopwire` binary.
- The verifier confirmed the installer rejects a bad checksum.
- `bash scripts/install.sh --dry-run --base-url file:///tmp/loopwire-release-test --prefix /tmp/loopwire-prefix` passed
  without modifying files.

## Package Evidence

- `pnpm verify:packaging` passed.
- AUR metadata template references:
  - `loopwire-linux-x86_64.tar.gz`,
  - `loopwire-linux-aarch64.tar.gz`,
  - `install -Dm755 loopwire`.
- Nix package template references:
  - `loopwire-linux-x86_64.tar.gz`,
  - `loopwire-linux-aarch64.tar.gz`,
  - `install -Dm755 loopwire`.

## Project Gates

- `pnpm check` passed and now includes:
  - `pnpm verify:scripts`,
  - `pnpm verify:autostart`,
  - `pnpm verify:install`,
  - `pnpm verify:packaging`,
  - `pnpm verify:vm`,
  - workspace typechecks,
  - tests,
  - builds.
- `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml` passed.
- `pnpm detect:audio` passed and reported PipeWire 1.6.7, PulseAudio compatibility on PipeWire 1.6.7, ALSA available,
  and JACK unavailable because `jack_lsp` is missing.
- Workflow YAML parsed with Ruby `YAML.load_file`.
- `git diff --check` passed.

## Remaining Risk

No public release artifacts exist yet. AUR and Nix package files are templates only and must not be published until the
release workflow emits real artifacts and checksums, and package builds are smoke-tested against those artifacts.
