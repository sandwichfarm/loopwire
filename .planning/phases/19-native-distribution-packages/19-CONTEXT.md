# Phase 19 Context: Native Distribution Packages

**Issue:** https://github.com/sandwichfarm/loopwire/issues/10
**Date:** 2026-08-30

## Goal

Ship reviewable native package recipes for popular apt- and RPM-based Linux distributions, and prove each recipe by
installing, launching, inspecting, and uninstalling the resulting package inside a matching KVM guest.

## Target Matrix

| Target | Package | Guest image |
|--------|---------|-------------|
| Ubuntu 24.04 LTS x86_64 | deb | Official Ubuntu cloud image |
| Debian 13 stable x86_64 | deb | Official Debian generic cloud image |
| Fedora 44 x86_64 | rpm | Official Fedora Cloud image |
| openSUSE Tumbleweed x86_64 | rpm | Official openSUSE cloud image |

Arch/AUR and Nix remain existing package paths. This slice does not redefine them.

## Decisions

- Native packages consume the canonical checksum-bound release tarball; they do not package a second GUI-only payload.
- The portable GUI binary is built on a Debian 12 baseline before packaging, following the project's Tauri/glibc
  compatibility contract.
- Docker may supply QEMU tooling, but containers are not accepted as distro proof. Each result must report `kvm` or
  `qemu` from a separately booted guest.
- Official image URLs and immutable checksums live in a target manifest and are rechecked before every launch.
- Guest evidence is bound to the target, image checksum, package checksum, package metadata, and exact git commit.
- GUI launch proof requires an application-specific Loopwire X11 window, not merely a process that survives until
  timeout. Xvfb does not run a window manager, so mapped/visible classification is not used as the proof predicate.

## Proof Boundary

Each guest must build the target package from the canonical release tarball, install it through the native package
manager, prove installed metadata/files, run background/provider/backend-detection smokes, verify GUI linkage and a
Loopwire-named X11 window under Xvfb, uninstall the package, and prove all owned paths are removed.

The repository verifier must reject missing files, mismatched guest identity/version, image checksum drift, a stale or
extra package, wrong version/architecture, unresolved GUI libraries, absent window evidence, and incomplete uninstall.

## Safety

- SSH forwards bind to `127.0.0.1` only.
- Cloud-init keys and mutable disks stay below ignored `.vm/` state.
- No raw audio is collected.
- Package proof runs only read-only backend detection; it does not mutate a real audio graph.
- The locally built openSUSE RPM is installed with its expected unsigned-package override. Published signing remains a
  release ceremony concern.
