# Phase 5 Verification: VM Compatibility Matrix

**Date:** 2026-07-03
**Status:** Passed for metadata, scripts, docs, and CI guard

## VM Matrix Evidence

- `bash scripts/vm-matrix.sh validate` passed with 6 VM targets.
- `bash scripts/vm-matrix.sh list` printed Arch, Fedora, Ubuntu LTS, Debian stable, NixOS, Hyprland, KDE Plasma,
  GNOME, Xfce, Sway, Wayland, X11, PipeWire, and PulseAudio coverage.
- `pnpm vm:plan --target arch-hyprland-pipewire` printed host prerequisites, guest bootstrap, guest validation, and
  evidence requirements.
- `bash scripts/vm-matrix.sh render-cloud-init --target arch-hyprland-pipewire --output /tmp/loopwire-vm-cloud-init`
  rendered `user-data`, `meta-data`, and `guest-commands.sh`.
- `bash scripts/vm-matrix.sh doctor || true` reported:
  - `qemu-system-x86_64=missing`,
  - `qemu-img=missing`,
  - `ssh=present`,
  - `cloud-localds=missing-optional`,
  - `kvm=available`.

## Project Gates

- `pnpm verify:vm` passed.
- `pnpm verify:scripts` passed and now includes `scripts/vm-matrix.sh`.
- `pnpm check` passed after docs, package scripts, and workflow changes.
- `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml` passed.
- `pnpm detect:audio` passed and reported PipeWire 1.6.7, PulseAudio compatibility on PipeWire 1.6.7, ALSA available,
  and JACK unavailable because `jack_lsp` is missing.
- Workflow YAML parsed with Ruby `YAML.load_file`, including `.github/workflows/vm-matrix.yml`.
- `git diff --check` passed.

## Skipped Checks

- No VM was launched because QEMU tooling is not installed on this host.
- `actionlint` was not installed; workflow validation used Ruby YAML parsing.
- `nix` was not installed; the flake was not evaluated.

## Remaining Risk

The VM matrix is a validation harness, not validation evidence from every target. The next step is to run the matrix on
a workstation or self-hosted runner with QEMU/KVM and attach per-target evidence.
