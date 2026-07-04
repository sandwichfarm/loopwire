# Loopwire

Loopwire is a greenfield Linux virtual audio routing app. It aims for a world-class desktop UX while staying honest
about the host audio graph: PipeWire first, with clear compatibility paths for PulseAudio, JACK, ALSA, and mixed setups.

This repository currently contains the first product skeleton: pure domain logic, a Svelte/Tauri desktop UI shell,
read-only Linux backend detection and port enumeration, app-runtime configuration transactions, VitePress docs/site,
CI/deploy workflow scaffolding, and GSD planning artifacts.

## Development

```bash
pnpm install
pnpm check
```

Useful commands:

```bash
pnpm --filter @loopwire/core test
pnpm detect:audio
pnpm collect:support -- --output-dir .support/$(date +%Y%m%d-%H%M%S) --profile quick
pnpm jack:ports -- --configuration exported-loopwire-config.json --format tsv
pnpm jack:verify -- --configuration exported-loopwire-config.json
pnpm --filter @loopwire/desktop dev
pnpm --filter @loopwire/docs docs:dev
pnpm verify:scripts
pnpm verify:autostart
pnpm verify:install
pnpm verify:packaging
pnpm nix:render-release -- --version 0.1.0 --release-dir dist/release --output dist/release/loopwire-bin-release.nix
pnpm vm:list
pnpm vm:plan
```

## Current Status

Host audio graph changes are guarded behind preview-by-default adapters and a user-armed live apply control. The current
code can:

- detect PipeWire, PulseAudio, JACK, and ALSA availability through read-only probes,
- list PipeWire and JACK source/target ports plus PulseAudio-compatible streams/sinks for desktop pickers,
- add detected PipeWire/JACK target ports as host-backed outputs for native link routes,
- connect and disconnect existing JACK ports when route endpoints include host device names,
- hydrate the desktop Backend picker from host probes when running in Tauri and fall back to preview candidates in the
  browser,
- create, edit, duplicate, delete, export, and import named configurations,
- switch configurations through an app-runtime unload/apply/verify/rollback transaction,
- restore the selected configuration on startup and re-verify it in the app runtime,
- edit route gain and mute state from keyboard-accessible controls,
- open backend diagnostics on demand without exposing backend clutter by default,
- collect a redacted support bundle with backend detection, host diagnostics, autostart status, and a command ledger.

PipeWire live apply can create Loopwire-owned virtual output and monitor sinks, link existing source ports into them,
disconnect muted links, and target existing host-backed outputs or physical monitor sinks. JACK live apply is limited
to existing-port `jack_connect`/`jack_disconnect` routes and existing physical monitor sinks. PulseAudio compatibility
live apply covers Loopwire-owned null sinks, monitor loopbacks, and matched stream controls.
Command-backed DSP providers can be inspected with `pnpm dsp:plan` and explicitly exercised with `pnpm dsp:verify`
before they are wired into background restore. Release artifacts install `loopwire-dsp-provider`, a bundled file-backed
provider for local preflight and restore-contract smoke. It persists seeded source buffers and rendered outputs, but it
does not yet capture or inject live PipeWire/JACK audio streams.

Cross-system validation is tracked in `vm/targets.tsv` and operated through `scripts/vm-matrix.sh`. It currently covers
manual VM targets for Arch, Fedora, Ubuntu LTS, Debian stable, NixOS, Hyprland, KDE Plasma, GNOME, Xfce, Sway, Wayland,
X11, PipeWire, PulseAudio, and JACK.

User-scoped startup can be managed from the desktop sidebar. **Open on boot** manages the GUI autostart entry, and
**Restore on boot** manages a user systemd unit for packaged background restore. The CLI fallback is
`scripts/manage-autostart.sh`; source-checkout systemd restore is rendered and tested through `pnpm restore:background`.
Release tarballs and package templates install a `loopwire --background` entrypoint for packaged background restore.
They also install `loopwire-dsp-provider` for provider-backed DSP restore preflight and `loopwire-jack-ports` for
JACK virtual-port restore preflight. The JACK wrapper records the exact provision plan and fails closed unless
`LOOPWIRE_JACK_PORTS_DELEGATE` or `--delegate-command` points at a live JACK client provider.

Installer and package metadata smoke tests are local-only for now: `verify:install` builds a fake release artifact and
proves checksum rejection, while `verify:packaging` checks that AUR and flake package templates point at the same
artifact names. The docs site carries `/install.sh` as a synced public copy of `scripts/install.sh`, but the curl
installer is not advertised as live until signed GitHub Release assets exist. The flake package still uses fake hashes
until published artifacts provide real release hashes; `pnpm nix:render-release` renders the concrete Nix expression
from checksum-bound release artifacts, but `nix build` proof must still come from a Nix-enabled host.

## GSD

Project planning lives under `.planning/`. Start with `.planning/ROADMAP.md` and `.planning/REQUIREMENTS.md`.
