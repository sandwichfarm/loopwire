# Phase 5 Verification: AUR Local Package Smoke

**Date:** 2026-07-03
**Status:** Passed on this Arch host

## Evidence

- `pnpm verify:aur` passed.
- The verifier generated x86_64 and aarch64 release tarballs through `scripts/package-release.sh`.
- `scripts/render-aur-pkgbuild.sh` rendered `packaging/aur/PKGBUILD.in` with concrete version, checksums, and local
  `file://` sources.
- `makepkg --force --nodeps --noconfirm --cleanbuild --clean` completed in a temporary directory.
- The generated `loopwire-bin` package archive contained `usr/bin/loopwire`.

## Remaining Risk

This is not a published-artifact test. AUR submission still requires a tagged GitHub Release, real checksums, and a
package build from the public URLs that users will consume.
