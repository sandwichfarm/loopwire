# Phase 19 Verification: Native Distribution Packages

**Verdict:** Passed
**Evidence commit:** `70eee4ec433bb7d967931357cf77bd0c28056a35`
**Date:** 2026-08-30

## Requirement Audit

| Requirement | Evidence | Result |
|-------------|----------|--------|
| Package scripts/config for each distro | `packaging/deb/`, `packaging/rpm/`, `scripts/build-*-package.sh` | Passed |
| Canonical payload/checksum binding | Builders validate one exact `SHA256SUMS` entry and safe extraction | Passed |
| Reproducible packages | `pnpm verify:native-packaging` builds every recipe twice and compares bytes | Passed |
| Ubuntu matching VM | `vm/native-package-proof/ubuntu-24.04/` | Passed |
| Debian matching VM | `vm/native-package-proof/debian-13/` | Passed |
| Fedora matching VM | `vm/native-package-proof/fedora-44/` | Passed |
| openSUSE matching VM | `vm/native-package-proof/opensuse-tumbleweed/` | Passed |
| Install/runtime/GUI/uninstall proof | Per-target summary, metadata/files, detector, ldd, X11 window, uninstall | Passed |
| Official image provenance | Per-target `image.tsv` URL and matching expected/actual digest | Passed |
| Exact commit/package binding | Per-target `summary.tsv`, `git-head.txt`, `package.sha256` | Passed |

## Commands

```bash
pnpm verify:native-packaging
pnpm verify:native-vm-proof -- --git-head 70eee4ec433bb7d967931357cf77bd0c28056a35
pnpm verify:native-package-proof-snapshot
pnpm verify:release
pnpm check
```

The final `pnpm check` and hosted PR checks are recorded after the proof snapshot commit so they cover the final review
surface rather than only the tested implementation ancestor.
