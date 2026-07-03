# Phase 5 Verification: Signed Release Manifest Verification

**Date:** 2026-07-03
**Status:** Passed for local signed release smoke

## Evidence

- `pnpm verify:install` passed:
  - generated a temporary RSA private/public key pair,
  - signed `SHA256SUMS`,
  - installed from a local `file://` release directory with `--public-key`,
  - executed the installed binary,
  - rejected a tampered artifact while the signed checksum manifest remained valid.
- `pnpm verify:release` passed:
  - generated reproducible release tarballs,
  - verified multi-architecture checksum entries,
  - signed and verified `SHA256SUMS`,
  - installed the generated host tarball through the strict installer,
  - staged native bundle attachments and verified the staged signed manifest.
- `pnpm verify:scripts` passed with the new signing scripts included.

## Remaining Risk

The project still needs a real release public key committed to `packaging/release-signing-public.pem` before public
installer claims. The release workflow has not run on GitHub with a real signing secret yet.
