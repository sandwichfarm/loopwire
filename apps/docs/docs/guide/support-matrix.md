# Support Matrix

This matrix separates detection, local validation, and public support. A working source checkout is not the same thing
as a published package or a live audio-routing guarantee.

## Status Vocabulary

| Status | Meaning |
|--------|---------|
| Verified | Covered by local automated validation in this repo. |
| Manual VM | Covered by a VM target and ready for operator-run guest evidence. |
| Planned | Designed in the contract but not implemented or validated yet. |
| Unsupported | Intentionally not a target for this milestone. |

## Host Targets

Target metadata is stored in `vm/targets.tsv` and validated by `pnpm verify:vm`, which also renders and checks
cloud-init handoffs for every target.
Rows marked `Verified` must have a passing target evidence bundle under `.vm/evidence/<target>`.
Rows with passing evidence must be promoted to `Verified`; otherwise they stay `Manual VM`.
Use `scripts/collect-vm-evidence-ssh.sh` after a VM is reachable over SSH to run guest validation, copy the target
bundle back, and verify it locally before changing a row to `Verified`. Guest evidence includes a redacted support
bundle plus a desktop launch smoke so maintainers can inspect backend diagnostics without relying only on screenshot or
pass/fail status. It also includes `environment.json`, which must match the target distro, desktop/session, audio
stack, and architecture before a row can be promoted. The matching `detect-audio.json` must also report the target
audio backend as available, so a JACK or PulseAudio row cannot be promoted with only generic Linux evidence.
Direct SSH collection keeps guest and copied-back output target-scoped: custom `--remote-output-dir` and
`--local-output-dir` values must include the target id as a path segment and cannot contain parent traversal.
After evidence verifies, promote the row with `pnpm vm:promote-evidence -- --target <target>`. Use `--dry-run` first
to preview the docs change without editing the matrix. For final release support claims, pass
`--require-published-release --release-tag <tag>` so promotion also proves the guest installed and ran the signed
published artifact for the exact release.
Custom verifier `--evidence-root` and `--matrix` paths are local artifacts only: the support-matrix verifier rejects
root/home placeholders, parent/current-directory traversal, URL syntax, glob metacharacters, symlinks, and existing
paths with the wrong file or directory type before reading the matrix or scanning copied-back VM evidence.
Run `pnpm vm:host-plan` for cross-distro host setup hints and target-specific image, cloud-init, launch, and evidence
handoff commands.
Run `pnpm vm:render-ssh-plan -- --all --output .vm/ssh-targets.tsv` to generate the multi-guest TSV consumed by
`pnpm vm:collect-matrix`.

| Target | Desktop/session | Audio stack | Current status |
|--------|-----------------|-------------|----------------|
| `arch-hyprland-pipewire` | Hyprland on Wayland | PipeWire/WirePlumber | Manual VM |
| `fedora-kde-pipewire` | KDE Plasma on Wayland | PipeWire/WirePlumber | Manual VM |
| `fedora-kde-jack` | KDE Plasma on Wayland | JACK | Manual VM |
| `ubuntu-gnome-pipewire` | GNOME on Wayland | PipeWire/PulseAudio compatibility | Manual VM |
| `ubuntu-gnome-pipewire-aarch64` | GNOME on Wayland | PipeWire/PulseAudio compatibility | Manual VM |
| `debian-xfce-pulseaudio` | Xfce on X11 | PulseAudio | Manual VM |
| `nixos-gnome-pipewire` | GNOME on Wayland | PipeWire/WirePlumber | Manual VM |
| `fedora-sway-pipewire` | Sway on Wayland | PipeWire/WirePlumber | Manual VM |
| `opensuse-kde-pipewire` | KDE Plasma on Wayland | PipeWire/WirePlumber | Manual VM |

## Audio Backends

| Backend | Detection | Host mutation | Notes |
|---------|-----------|---------------|-------|
| PipeWire native | Verified probes and port listing | Virtual sinks, routes, mute, monitor links | Per-edge gain planned. |
| PulseAudio compatibility | Verified read-only probes | Verified with fake runners | Sinks, monitors, routes; one output per source. |
| Native PulseAudio | Verified read-only probes | Same `pactl` adapter path | Needs manual VM proof on a non-PipeWire PulseAudio host. |
| JACK | Verified probes and port listing | Existing-port routes, route mute, and monitor links | Virtual ports and gain still planned. |
| ALSA | Playback/capture hardware detection | Not a routing backend | Used for diagnostics and hardware visibility. |

Host adapters are dry-run by default. Live apply is session-local and requires the desktop `Host apply` control plus
the Tauri shell command bridge.

## Install Channels

| Channel | Current validation | Public status |
|---------|--------------------|---------------|
| Source checkout | `pnpm check` | Supported for contributors. |
| Signed curl installer | Local verification plus live `/install.sh` byte comparison | Published for 0.1.0 at `loopwire.app`. |
| AppImage | Published-artifact and Tauri bundle smoke | Published for 0.1.0 on GitHub Releases. |
| Ubuntu 24.04 / Debian 13 deb | Verified in matching KVM guests at commit `70eee4e`; review snapshot in `vm/native-package-proof/` | Published as direct downloads; no APT repository. |
| Fedora 44 / openSUSE Tumbleweed RPM | Verified in matching KVM guests at commit `70eee4e`; review snapshot in `vm/native-package-proof/` | Published as direct downloads; no COPR/OBS repository. |
| AUR `loopwire` | Tagged source build through `pnpm verify:aur:source` | Published for 0.1.0. |
| AUR `loopwire-bin` | Signed release-artifact build through `pnpm verify:aur` | Published for 0.1.0. |
| Nix flake package template | `pnpm verify:packaging` | Blocked on real release hashes and Nix build proof. |

The flake package output is `packages.<system>.loopwire-bin`; it uses fake hashes until published artifacts exist.

Native package verification is narrower than audio-backend support. The committed snapshot proves that each official,
checksum-pinned guest built and installed its target package, ran the packaged background/provider/backend commands,
resolved GUI libraries, created a Loopwire X11 window under Xvfb, and removed all package-owned files. It does not
promote any host-audio backend row or claim that the packages have been published.

## Desktop Integration

| Area | Current behavior |
|------|------------------|
| Window chrome | Native chrome by default; custom mode persists and requests an undecorated Tauri window with Loopwire controls. |
| Autostart | XDG desktop autostart can be installed and removed with `scripts/manage-autostart.sh`. |
| Background restore | Source checkout and packaged user-scoped systemd restore paths are verified locally. |
| Screenshots | `assets/product-screenshot.png` is the canonical desktop capture; refresh the docs public copy through the screenshot procedure. |
