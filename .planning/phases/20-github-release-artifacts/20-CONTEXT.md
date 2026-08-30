# Phase 20 Context: GitHub Release Artifacts

**Issue:** https://github.com/sandwichfarm/loopwire/issues/12
**Date:** 2026-08-30

## Goal

Make the existing protected GitHub Release workflow publish an explicit, useful, auditable artifact set for each
version tag without creating a second publisher or relying on filenames that silently carry the wrong version.

## Useful Artifact Contract

- Canonical portable tarballs for x86_64 and AArch64.
- Version-matched AppImages for x86_64 and AArch64.
- Full-payload native packages for Ubuntu 24.04, Debian 13, Fedora 44, and openSUSE Tumbleweed on x86_64.
- Deterministic `release-assets.json` with role, target, architecture, byte size, and SHA-256 for every payload.
- Signed `SHA256SUMS` and `SHA256SUMS.sig` covering the manifest and every payload.
- Tag-bound release evidence added after initial publication, followed by a regenerated manifest and signature.

## Decisions

- Treat `v0.1.0` as the first public alpha and label the release-facing documentation accordingly.
- Keep `.github/workflows/release.yml` as the sole publisher.
- Keep public release creation tag-driven; manual dispatch may only target an existing version tag.
- Override Tauri's build configuration with the tag version rather than mutating tracked source versions.
- Publish only the AArch64 AppImage and portable tarball until AArch64 native packages have their own proof.
- Fail on unknown, extra, missing, linked, duplicated, or mis-versioned payloads before publication.
- Do not create a tag or public release while implementing this phase.
