# Phase 5 Result: VM Compatibility Matrix

**Completed:** 2026-07-03
**Requirements:** LINUX-01 support path, QUAL-03 support path

## Delivered

- Added `vm/targets.tsv` with 6 representative Linux VM targets:
  - Arch Linux / Hyprland / Wayland / PipeWire,
  - Fedora / KDE Plasma / Wayland / PipeWire,
  - Ubuntu LTS / GNOME / Wayland / PipeWire plus PulseAudio compatibility,
  - Debian stable / Xfce / X11 / PulseAudio,
  - NixOS / GNOME / Wayland / PipeWire,
  - Fedora / Sway / Wayland / PipeWire.
- Added `scripts/vm-matrix.sh` with:
  - list,
  - validate,
  - doctor,
  - plan,
  - render-cloud-init,
  - explicit dry-run launch.
- Added package scripts for VM list, plan, doctor, and validation.
- Added `.vm/` to `.gitignore` for generated VM state.
- Added the `VM Matrix` GitHub Actions workflow to validate metadata and shell syntax without booting VMs.
- Added VitePress docs for target coverage, launch policy, CI boundary, and required evidence.

## Boundaries

- The helper does not download distro images.
- The helper does not install QEMU or other host packages.
- The helper does not boot a VM unless the operator supplies an image and passes `--execute`.
- GitHub-hosted CI validates the matrix contract only; real desktop/audio VM runs need local or self-hosted KVM.

## Next Phase 5 Work

- Implement and test user-scoped start-on-boot.
- Harden release installer behavior and artifact checksum flow.
- Add AUR and Nix packaging smoke paths.
- Run actual VM target evidence once QEMU/KVM tooling is installed.
