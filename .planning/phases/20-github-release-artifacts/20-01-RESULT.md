# Phase 20 Result: Auditable GitHub Release Artifacts

**Status:** Complete
**Issue:** https://github.com/sandwichfarm/loopwire/issues/12
**Pull request:** https://github.com/sandwichfarm/loopwire/pull/13
**Implementation commit:** `631abe1c249665e7938b3aa69d11b26fc548752e`
**Date:** 2026-08-30

## Delivered

- One tag-driven GitHub Release publisher for existing version tags, with tag-aware run names and concurrency.
- Tag-versioned Tauri AppImages for x86_64 and AArch64.
- Portable x86_64 and AArch64 tarballs plus the four proof-backed x86_64 Ubuntu, Debian, Fedora, and openSUSE packages.
- Deliberate exclusion of GUI-only AArch64 deb/RPM bundles until equivalent native package proof exists.
- Deterministic `release-assets.json` inventory bound to the tag and commit, with role, target, architecture, size, and
  SHA-256 for every payload.
- Exact signed-checksum coverage, stale remote asset reconciliation for same-tag reruns, and remote re-verification
  before and after tag-bound evidence is uploaded.
- Fail-closed tests for missing, extra, linked, duplicated, mis-versioned, and tampered artifacts.
- Release documentation identifying `v0.1.0` as Loopwire's first public alpha.

## Artifact Contract

The base release contains exactly eight payloads: two portable archives, two AppImages, two deb packages, and two RPM
packages. The verified release-evidence archive becomes the ninth payload after initial publication. The JSON inventory
is transport metadata covered by `SHA256SUMS` and its signature.

## Remaining Boundary

No tag or public GitHub Release was created. The first live publication proof belongs to the protected `v0.1.0` alpha
tag workflow and must verify the downloaded GitHub assets before the release is considered complete.
