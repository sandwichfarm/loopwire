# Phase 7 Summary: CI/CT/CD and Release Ceremony

## Completed

- Added CI concurrency and timeout controls.
- Added Tauri Linux dependency install and `cargo check` to CI.
- Added CT concurrency, timeout, and redacted host-diagnostics artifact upload.
- Added docs contract verification to docs build/deploy jobs.
- Changed Bunny.net deployment to use protected refs, the `docs-production` environment, and secret-safe deploy
  skipping.
- Required versioned release notes for every release tag.
- Updated release publish to use versioned notes instead of generated notes.
- Added post-publish install smoke by downloading GitHub Release assets and running the installer against them.
- Updated release docs with release-note, docs deployment, and post-publish smoke ceremony.

## Verification

- Workflow action tags were checked live with `git ls-remote`.
- Workflow YAML parsed successfully.
- `pnpm check` passed.
- `pnpm detect:audio` passed.
- `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml` passed.
- GSD queries passed.

## Remaining Risks

- No GitHub workflow has run yet.
- `actionlint` and `zizmor` are unavailable locally.
- Release workflow remains intentionally blocked until versioned release notes and a real release signing key exist.
- Bunny.net deployment remains intentionally skipped until deployment secrets and environment protection are configured.
