# Phase 5 Verification: Linux Install and Startup

**Date:** 2026-07-03
**Status:** Passed for local install/startup/package smoke

## Evidence

- `pnpm verify:vm` validated 6 VM targets.
- `pnpm verify:autostart` installed and removed XDG desktop autostart and rendered systemd user unit output in a temp
  directory.
- `pnpm verify:install` installed a signed local release artifact into a temp prefix, ran the installed binary, and
  rejected a tampered artifact.
- `pnpm verify:release` generated release artifacts, reproduced the same checksum for identical input, signed
  `SHA256SUMS`, verified bundle checksums, and round-tripped the artifact through the installer.
- `pnpm verify:packaging` validated package metadata templates.
- `pnpm verify:aur` rendered the PKGBUILD and built a package archive containing `usr/bin/loopwire`.
- `pnpm check` passed with Phase 5 validation in the root check chain.

## Skipped

- No public GitHub Release was created.
- No VM was booted.
- No Nix build ran locally because `nix` is unavailable on this host.
- No system audio configuration was mutated.
