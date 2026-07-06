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
entrypoint for packaged user systemd restore, `loopwire-dsp-provider` for bundled file-backed DSP preflight, and
`loopwire-jack-ports` for JACK virtual-port restore preflight. The JACK wrapper records the requested ports and exits
nonzero unless `LOOPWIRE_JACK_PORTS_DELEGATE` or `--delegate-command` points at a live JACK client provider. Delegates
that must keep a JACK client running can use `LOOPWIRE_JACK_PORTS_DELEGATE_MODE=detached` or the first-class
`--jack-provider-delegate-mode detached` restore setting, after which restore still checks `jack_lsp` before connecting
routes. Source checkouts can also render a user systemd unit with
`--source-dir "$PWD"` that runs `pnpm restore:background` against the Tauri-written state file. For live PulseAudio
source restores, add `--retry-pending-ms` and `--retry-interval-ms` to refresh late-starting app streams. For JACK
restore, add `--jack-provider-command` so the generated service can create deterministic Loopwire-owned ports before
connecting them.

The curl installer reports whether `node` is available after installation. The GUI launcher can start without Node.js,
but packaged `loopwire --background`, `loopwire-dsp-provider`, and `loopwire-jack-ports` require `node` on `PATH`.
Install the distro `nodejs` package before enabling Restore on boot from a raw tarball install. AUR and Nix package
paths declare or wrap that dependency for you.

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

After signed release artifacts exist, render the concrete Nix package expression from the published checksum manifest:

```bash
pnpm nix:render-release -- \
  --version 0.1.0 \
  --release-dir dist/release \
  --public-key packaging/release-signing-public.pem \
  --output dist/release/loopwire-bin-release.nix
```

This converts the signed tarball checksums into Nix SRI hashes, but it is still not a release claim until `nix build`
passes on a Nix-enabled host against published artifacts.

On a Nix-enabled host, run the build-proof command:

```bash
pnpm verify:nix-release -- \
  --version 0.1.0 \
  --release-dir dist/release \
  --public-key packaging/release-signing-public.pem
```

For final release proof, bind the proof to the published GitHub Release instead of a local directory:

```bash
pnpm verify:nix-release -- \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --public-key packaging/release-signing-public.pem
```

Non-Nix CI and local machines may use `--skip-build-if-missing-nix` only to check wiring. Release evidence and final
release proof must not use that skip as Nix package proof.

These channels are not published yet. Do not submit AUR metadata or expose a release-ready Nix package until versioned
artifacts and real checksums exist.
