# Install

Loopwire is not released yet. The current install path is for contributors and early testers working from source.

## Source Install

```bash
git clone https://github.com/sandwichfarm/loopwire
cd loopwire
pnpm install
pnpm check
```

## Planned Release Installer

The release installer is scaffolded and locally smoke-tested in `scripts/install.sh`. Once signed release artifacts
exist, the public entry point will follow this shape:

```bash
curl -fsSL https://loopwire.app/install.sh | bash
```

The VitePress public asset at `/install.sh` is a byte-for-byte copy of `scripts/install.sh`, so the docs site can serve
the same installer once Bunny.net deployment is enabled. It is not a release claim until signed GitHub Release assets,
`SHA256SUMS`, `SHA256SUMS.sig`, and the release public key exist.

The installer must detect OS and architecture, download a release artifact, verify signed checksums, and avoid
persistent system changes unless the user explicitly opts in.

Current installer verification:

```bash
pnpm verify:install
pnpm verify:release
pnpm verify:aur
```

`verify:install` creates a local fake release, signs `SHA256SUMS`, verifies `SHA256SUMS.sig`, installs into a temporary
prefix, runs the installed binary, and confirms tampered or unsafe archive artifacts are rejected. `verify:release`
uses the release packager itself, confirms same-input artifact reproducibility, checks multi-architecture checksum
entries, and then round-trips the signed generated artifact through the installer. `verify:aur` renders the AUR
template from local generated artifacts and runs `makepkg` in a temp directory when available. These commands do not
touch system paths or the network.

## Startup Helper

Source checkouts can preview and install user-scoped startup entries:

```bash
pnpm autostart:status
bash scripts/manage-autostart.sh install --mode desktop --binary "$HOME/.local/bin/loopwire"
pnpm restore:background -- --state-file "${XDG_CONFIG_HOME:-$HOME/.config}/loopwire/state.json" --mode preview
```

The desktop mode writes `~/.config/autostart/loopwire.desktop`. Release tarballs install a `loopwire --background`
entrypoint for packaged user systemd restore and `loopwire-dsp-provider` for bundled file-backed DSP preflight.
Source checkouts can also render a user systemd unit with
`--source-dir "$PWD"` that runs `pnpm restore:background` against the Tauri-written state file. For live PulseAudio
source restores, add `--retry-pending-ms` and `--retry-interval-ms` to refresh late-starting app streams. For JACK
restore, add `--jack-provider-command` so the generated service can create deterministic Loopwire-owned ports before
connecting them.

## Package Channels

Package metadata templates now exist under `packaging/`:

- `packaging/aur/PKGBUILD.in` for future AUR `loopwire-bin`.
- `flake.nix` exposes `packages.<system>.loopwire-bin` from `packaging/nix/loopwire-bin.nix`, currently with fake
  hashes until the first public release provides real artifact hashes.
- AppImage, deb, and rpm artifacts through Tauri bundling.

Run the metadata smoke:

```bash
pnpm verify:packaging
```

These channels are not published yet. Do not submit AUR metadata or expose a release-ready Nix package until versioned
artifacts and real checksums exist.
