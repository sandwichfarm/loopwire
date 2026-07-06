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
pnpm verify:nix-release -- --version 0.1.0 --release-dir dist/release --skip-build-if-missing-nix
pnpm verify:nix-release -- --repo sandwichfarm/loopwire --tag v0.1.0 --public-key packaging/release-signing-public.pem
pnpm vm:list
pnpm vm:plan
```

## Current Status

### Desktop UI

The desktop shell is a sidebar + patch-bay editor:

- a fixed **Devices** sidebar lists virtual devices with an On/Off pill, source summary, mute button, and volume
  slider; **New Virtual Device** creates a device with a default Pass-Thru → Channels 1 & 2 graph, and removal shows
  an undo toast instead of a confirmation dialog,
- the canvas renders the selected device as three columns — **Sources**, **Output Channels**, **Monitors** — with
  200px cards, per-channel meters, and bezier cables drawn between ports,
- sources and monitors are added from grouped ⊕ menus backed by host enumeration in the desktop shell (sample entries
  in browser preview); output channel buses are added instantly,
- new sources/monitors auto-cable (1→1, 2→2); dragging port-to-port creates a route, clicking a cable selects it, and
  Delete (key or footer button) removes the selection,
- cards expose On/Off pills and an expandable Options strip (source volume drives outgoing route gains;
  app sources add a mute-when-capturing checkbox; monitor volume is configured state applied on host apply),
- **Hide Monitors** collapses the third column; renaming auto-opens on create; the UI ships light and dark themes,
  respects `prefers-reduced-motion`, and keeps full keyboard operability,
- Settings (`Ctrl+,`) holds Appearance, the audio backend picker, the automatic host-apply status, startup
  integration, and update policy — the main window stays devices-only.
- Selecting a device applies its configuration through the saved backend immediately (unload→apply→verify with
  rollback) whenever the switch preflight passes; otherwise the switch runs in preview and reports why.
- Sidebar devices reorder with click-and-drag.

Meters render their silent track until a per-port level stream exists in the audio host layer (documented capability
gap): Loopwire never simulates host-owned audio state.

### Host integration

Host audio graph changes run through guarded adapters with preflight checks: device selection applies live through the
saved backend when preflight passes and falls back to preview (with the reason) when it does not. The current code can:

- detect PipeWire, PulseAudio, JACK, and ALSA availability through read-only probes,
- list PipeWire and JACK source/target ports plus PulseAudio-compatible streams/sinks for desktop pickers,
- add detected PipeWire/JACK target ports as host-backed outputs for native link routes,
- connect and disconnect existing JACK ports when route endpoints include host device names,
- hydrate the Settings backend picker from host probes when running in Tauri and fall back to preview candidates in the
  browser,
- create, rename, and delete devices (configurations) and their sources, buses, monitors, and routes,
- switch devices through an app-runtime unload/apply/verify/rollback transaction with live-apply preflight checks,
- restore the selected configuration on startup and re-verify it in the app runtime,
- collect a redacted support bundle with backend detection, host diagnostics, autostart status, and a command ledger.

Configuration export/import and the on-demand diagnostics panel were removed from the rebuilt desktop UI; their
domain/CLI paths (`packages/core` persistence, support-bundle and verification scripts) remain available.

PipeWire live apply can create Loopwire-owned virtual output and monitor sinks, create virtual source nodes for
unbound sources such as Pass-Thru (a sink applications play into whose monitor feeds the buses), link source ports,
disconnect muted links, preserve muted route gain values, and target existing host-backed outputs or physical monitor
sinks. JACK live apply is limited to existing-port `jack_connect`/`jack_disconnect` routes, muted route disconnects
that can preserve muted gain values, and existing physical monitor sinks. PulseAudio compatibility live apply covers
Loopwire-owned null sinks, monitor loopbacks, and matched stream controls; active one-source fan-out remains blocked,
but muted saved fan-out routes do not prevent the active stream route from applying.
Command-backed DSP providers can be inspected with `pnpm dsp:plan` and explicitly exercised with `pnpm dsp:verify`
before they are wired into background restore. Release artifacts install `loopwire-dsp-provider`, a bundled file-backed
provider for local preflight and restore-contract smoke. It persists seeded source buffers and rendered outputs, but it
does not yet capture or inject live PipeWire/JACK audio streams.

Cross-system validation is tracked in `vm/targets.tsv` and operated through `scripts/vm-matrix.sh`. It currently covers
manual VM targets for Arch, Fedora, Ubuntu LTS, Debian stable, NixOS, Hyprland, KDE Plasma, GNOME, Xfce, Sway, Wayland,
X11, PipeWire, PulseAudio, and JACK.

User-scoped startup can be managed from the desktop Settings window (`Ctrl+,`). **Start with desktop session** manages
the GUI autostart entry, and **Restore audio in background** manages a user systemd unit for packaged background
restore. The CLI fallback is
`scripts/manage-autostart.sh`; source-checkout systemd restore is rendered and tested through `pnpm restore:background`.
Release tarballs and package templates install a `loopwire --background` entrypoint for packaged background restore.
They also install `loopwire-dsp-provider` for provider-backed DSP restore preflight and `loopwire-jack-ports` for
JACK virtual-port restore preflight. The JACK wrapper records the exact provision plan and fails closed unless
`LOOPWIRE_JACK_PORTS_DELEGATE` or `--delegate-command` points at a live JACK client provider. Long-running JACK
provider delegates can opt into detached mode with `LOOPWIRE_JACK_PORTS_DELEGATE_MODE=detached` or the saved
`--jack-provider-delegate-mode detached` Restore on boot setting; Loopwire still re-probes `jack_lsp` before treating
those ports as real.

Installer and package metadata smoke tests are local-only for now: `verify:install` builds a fake release artifact and
proves checksum rejection, while `verify:packaging` checks that AUR and flake package templates point at the same
artifact names. The docs site carries `/install.sh` as a synced public copy of `scripts/install.sh`, but the curl
installer is not advertised as live until signed GitHub Release assets exist. The flake package still uses fake hashes
until published artifacts provide real release hashes; `pnpm nix:render-release` renders the concrete Nix expression
from checksum-bound release artifacts, while `pnpm verify:nix-release` runs the real Nix build when `nix` is available.
For final release proof, `verify:nix-release` can download the signed assets from `--repo` and `--tag` before running
`nix build`. The `--skip-build-if-missing-nix` flag is only a wiring check and is not release proof.

## GSD

Project planning lives under `.planning/`. Start with `.planning/ROADMAP.md` and `.planning/REQUIREMENTS.md`.
