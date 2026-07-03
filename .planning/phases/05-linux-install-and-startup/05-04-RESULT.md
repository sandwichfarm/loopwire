# Phase 5 Result: Release Workflow and Artifact Checksums

**Completed:** 2026-07-03
**Requirements:** LINUX-03 support path, LINUX-04 support path, QUAL-03, QUAL-05 support path

## Delivered

- Added `scripts/package-release.sh` for reproducible release tarball generation.
- Added `scripts/stage-release-artifacts.sh` for tarball, native bundle, and checksum staging.
- Added `scripts/verify-release-artifacts.sh` to test package generation, checksum updates, installer round-trip, and
  executable smoke.
- Added `pnpm verify:release` and folded it into the root `pnpm check` gate.
- Updated CI to run the full `pnpm check` surface.
- Added `.github/workflows/release.yml` for `v*` tag and manual existing-tag release publication.
- Fixed Tauri bundle icon configuration and made Tauri bundling use `NO_STRIP=true`.
- Added release documentation and package README updates.

## Boundaries

- The release workflow was syntax/local-logic validated only; no GitHub Release was created.
- No public artifacts were published.
- The workflow currently packages the runner architecture only.
- Native bundles were built locally but not installed or launched.
- No signature scheme exists yet, so docs and planning still avoid claiming signed release artifacts.

## Next Phase 5 Work

- Add artifact signatures and installer verification for those signatures.
- Add AArch64 release builds through native runners or QEMU.
- Add install/run smoke for actual Tauri AppImage, deb, and rpm outputs.
- Verify AUR and Nix package builds from a real published release.
