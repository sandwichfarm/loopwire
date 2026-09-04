# Install

Loopwire 0.1.0 is published for early testers. Arch users can choose the stable source-built `loopwire` package or
the prebuilt `loopwire-bin` package; contributors can still work directly from a source checkout.

## Arch User Repository

Build the stable tagged source package:

```bash
git clone https://aur.archlinux.org/loopwire.git
cd loopwire
makepkg -si
```

For the faster prebuilt release-artifact package, use the separate `loopwire-bin` package base instead. The variants
conflict because they install the same commands; do not install both at once. A future live-VCS package, if added,
will use the `loopwire-git` name.

## Source Install

```bash
git clone https://github.com/sandwichfarm/loopwire
cd loopwire
pnpm install
pnpm check
```

## Signed Release Installer

The public installer is deployed from `scripts/install.sh` and installs the signed `v0.1.0` release artifacts:

```bash
curl -fsSL https://loopwire.app/install.sh | bash
```

The VitePress public asset and live `/install.sh` are byte-for-byte copies of `scripts/install.sh`. The installer
requires the published `SHA256SUMS`, `SHA256SUMS.sig`, and release public key before extracting an artifact.

The installer must detect OS and architecture, download a release artifact, verify signed checksums, and avoid
persistent system changes unless the user explicitly opts in.

Current installer verification:

```bash
pnpm verify:install
pnpm verify:release
pnpm verify:aur
pnpm verify:native-packaging
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
but packaged `loopwire --background`, `loopwire-dsp-provider`, `loopwire-jack-ports`, and `loopwire-detect-audio`
require `node` on `PATH`.
Install the distro `nodejs` package before enabling Restore on boot from a raw tarball install. AUR and Nix package
paths declare or wrap that dependency for you.

## Package Channels

Package metadata templates now exist under `packaging/`:

- `packaging/aur/loopwire/PKGBUILD.in` for stable tagged source builds.
- `packaging/aur/loopwire-bin/PKGBUILD.in` for signed prebuilt release artifacts.
- `flake.nix` exposes `packages.<system>.loopwire-bin` from `packaging/nix/loopwire-bin.nix`, currently with fake
  hashes until the first public release provides real artifact hashes.
- Repository-owned deb recipes for Ubuntu 24.04 and Debian 13, plus RPM recipes for Fedora 44 and openSUSE
  Tumbleweed. They package the full canonical release payload rather than Tauri's GUI-only bundle.
- AppImage through Tauri bundling.

Run the metadata smoke:

```bash
pnpm verify:packaging
```

The AppImages and native deb/RPM files are published as direct downloads on the `v0.1.0` GitHub Release. They are not
yet served through an APT, DNF/COPR, or OBS repository. Their matching-guest proof command boots official,
checksum-pinned cloud images under KVM and stores local evidence without changing host audio:

```bash
pnpm vm:native-packages -- run-all --version 0.1.0 --release-dir .vm/native-packages/release
```

See `packaging/README.md` for release-tarball creation, host prerequisites, exact target names, and evidence paths.
The review-safe proof snapshot for commit `70eee4e` is under `vm/native-package-proof/`; it backs the published
direct-download native packages without claiming that a distro package repository exists.

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

The AUR recipes are published as separate package bases. The Nix package remains a template; do not expose it as
release-ready until real hashes and non-skipped Nix build proof exist.
