# Phase 5 Verification: Release Workflow and Artifact Checksums

**Date:** 2026-07-03
**Status:** Passed for local release artifact generation and installer round-trip

## Release Artifact Evidence

- `pnpm verify:release` passed.
- The verifier generated `loopwire-linux-x86_64.tar.gz` through `scripts/package-release.sh`.
- Re-running the packager with identical input produced the same SHA-256 hash.
- `SHA256SUMS` contained exactly one host-architecture entry after repeated packaging.
- `SHA256SUMS` also contained a secondary architecture entry.
- `sha256sum --check SHA256SUMS` passed.
- The generated tarball contained an executable `loopwire`.
- `scripts/install.sh --base-url file://...` installed the generated artifact into a temporary prefix.
- The installed binary executed and printed the expected smoke output.
- The release verifier stages fake AppImage/deb/rpm bundle files through `scripts/stage-release-artifacts.sh` and
  verifies `SHA256SUMS` for every staged attachment.

## Workflow Evidence

- `.github/workflows/release.yml` uses:
  - `push` tags matching `v*`,
  - manual dispatch with a required existing `v`-prefixed tag,
  - `permissions: contents: write`,
  - Ubuntu 22.04 release runner,
  - Tauri Linux prerequisite installation,
  - `pnpm check`,
  - `cargo check`,
  - Tauri bundle build,
  - local installer smoke before `gh release create` or `gh release upload`.

## Remaining Risk

The workflow has not run on GitHub yet, and no release has been published. The current release ceremony still needs
signatures, AArch64 build coverage, native bundle smoke, and package-manager builds from published artifacts.

## Local Bundle Follow-Up

- `pnpm --filter @loopwire/desktop tauri:build` initially failed because AppImage bundling could not find a configured
  square icon.
- Registering the existing square PNG/SVG icons in `tauri.conf.json` fixed the icon failure.
- AppImage bundling then failed on this Arch host because linuxdeploy's bundled `strip` could not read newer `.relr.dyn`
  ELF sections.
- `NO_STRIP=true pnpm --filter @loopwire/desktop exec tauri build --ci --bundles appimage` passed and produced
  `Loopwire_0.0.0_amd64.AppImage`.
- `pnpm --filter @loopwire/desktop tauri:build` passed and produced:
  - `Loopwire_0.0.0_amd64.AppImage`,
  - `Loopwire_0.0.0_amd64.deb`,
  - `Loopwire-0.0.0-1.x86_64.rpm`.
- A local simulation of the release workflow packaging step passed with the real compiled Tauri binary:
  - generated `loopwire-linux-x86_64.tar.gz`,
  - copied AppImage/deb/rpm bundles,
  - regenerated `SHA256SUMS`,
  - verified all four artifacts with `sha256sum --check`,
  - installed the generated tarball into a temporary prefix.
