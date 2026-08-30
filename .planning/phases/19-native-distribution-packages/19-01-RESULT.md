# Phase 19 Result: Native Distribution Packages and Matching-Guest Proof

**Status:** Complete
**Issue:** https://github.com/sandwichfarm/loopwire/issues/10
**Tested commit:** `70eee4ec433bb7d967931357cf77bd0c28056a35`
**Date:** 2026-08-30

## Delivered

- Target-specific deb controls for Ubuntu 24.04 and Debian 13.
- Target-specific RPM specs for Fedora 44 and openSUSE Tumbleweed.
- Deterministic checksum-bound deb/RPM builders, target-container release orchestration, and a Debian 12 portable GUI
  build.
- Full package payload: GUI, background restore, DSP provider, JACK provider, backend detector, desktop entry, and icon.
- Release staging which replaces GUI-only Tauri deb/RPM attachments with the full x86_64 packages.
- Official-image manifest, Docker-contained QEMU tooling, KVM runner, loopback-only pinned SSH, guest smoke, strict raw
  verifier, review-safe proof promotion, and CI snapshot verification.

## Matching-Guest Results

| Target | Observed guest | Package | SHA-256 |
|--------|----------------|---------|---------|
| Ubuntu 24.04 | Ubuntu 24.04.4 LTS | `loopwire_0.1.0-1ubuntu24.04_amd64.deb` | `b3e4498dc70d6a28e80b9ae30bd8e31d69f81017805e37561e926ff053141ad4` |
| Debian 13 | Debian GNU/Linux 13 (trixie) | `loopwire_0.1.0-1debian13_amd64.deb` | `dd4002cac5460d1de53eebaf2aab2eacd73f3407203599402f99b76d1e2031b2` |
| Fedora 44 | Fedora Linux 44 (Cloud Edition) | `loopwire-0.1.0-1.fc44.x86_64.rpm` | `ed22ec8b40a46080816bf355f5b6f3e35eb73ac2adf08b1e07cdea8d2a1f2cc7` |
| openSUSE Tumbleweed | openSUSE Tumbleweed 20260829 | `loopwire-0.1.0-1.x86_64.rpm` | `c346be372708a23e4de7eb8d0e3eda3d482deed1dcc9bba4bad727bb9fe680f0` |

Every guest reported `kvm`, matched its manifest OS identity, installed exact version/architecture metadata, exposed the
expected files, ran all packaged CLI helpers, produced backend-detection JSON, resolved every GUI shared library,
created a Loopwire X11 window under Xvfb, and removed all package-owned paths.

## Proof Surfaces

- Raw proof: `.vm/native-packages/evidence/<target>/70eee4ec433bb7d967931357cf77bd0c28056a35/` (ignored).
- Review snapshot: `vm/native-package-proof/<target>/` (committed and CI-checked).
- Full raw verifier: `pnpm verify:native-vm-proof -- --git-head 70eee4ec433bb7d967931357cf77bd0c28056a35`.
- Snapshot verifier: `pnpm verify:native-package-proof-snapshot`.

## Remaining Boundary

The packages are not published. Public install claims remain blocked on the protected tagged release workflow, signed
combined manifest, and post-publish install proof. Native package proof does not promote desktop/audio-stack support
rows because these headless guests intentionally validate packaging rather than live host audio mutation.
