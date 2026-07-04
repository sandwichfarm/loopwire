# Phase 5 Summary: Linux Install and Startup

## Completed

- Added VM target metadata for distro, desktop, session, package manager, and audio-server coverage.
- Added `scripts/vm-matrix.sh` with metadata validation, local prerequisite doctor, target plans, cloud-init rendering,
  and dry-run QEMU launch policy.
- Added user-scoped startup helper support for XDG desktop autostart and future systemd user services.
- Added local installer smoke for signed `SHA256SUMS`, signature verification, temp-prefix install, binary execution,
  checksum failure, and tampered-artifact rejection.
- Added release packaging, staging, checksum, signature, and installer round-trip scripts.
- Added AUR PKGBUILD rendering and local `makepkg --nodeps` package smoke when `makepkg` is available.
- Added Nix package metadata template and packaging metadata smoke.
- Added GitHub release workflow scaffolding for Tauri bundles, signed checksums, installer smoke, and release upload.

## Verification

- `pnpm verify:vm` passed.
- `pnpm verify:autostart` passed.
- `pnpm verify:install` passed with temporary signing keys and tamper rejection.
- `pnpm verify:release` passed with reproducible package generation and installer round-trip.
- `pnpm verify:packaging` passed for AUR/Nix metadata.
- `pnpm verify:aur` passed on the Arch host with `makepkg`.
- `pnpm check` passed after the Phase 5 scripts were included in the root validation chain.

## Remaining Risks

- Public release artifacts do not exist yet.
- A real release public key is now committed, and the matching private key is stored as the release GitHub secret for
  `sandwichfarm/loopwire`; Bunny deployment secrets, tag/release proof, and published-artifact smoke are still required
  before public publishing.
- AArch64 artifacts need a dedicated runner or QEMU lane before public multi-arch support claims.
- Nix metadata exists, but Nix build proof still needs a Nix-enabled host or VM target.
- VM target execution is intentionally manual/operator-owned; the repo validates target metadata, not full VM boots.
