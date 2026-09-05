# Install

Install or upgrade Loopwire with one command:

```bash
curl -fsSL https://loopwire.app/install.sh | bash
```

Loopwire `v0.1.0` is published for early testers. Run the installer as your regular user. It names each step,
prints the selected package-manager command before running it, and asks before package-manager changes. It does
not enable startup services or change audio routing. Read [the installer](https://loopwire.app/install.sh) before running it if you
want to inspect what it does.

The release downloader needs Bash, curl, OpenSSL, and standard GNU tools including `awk`, `sha256sum`, and `tar`.
Minimal images may need these prerequisites installed first. Missing tools produce a named-step error before the
installer changes an existing installation.

## Automatic platform selection

| Platform | Default installation path |
| --- | --- |
| Ubuntu 24.04, x86_64 | Signed release deb through APT |
| Debian 13, x86_64 | Signed release deb through APT |
| Fedora 44, x86_64 | Signed release RPM through DNF |
| openSUSE Tumbleweed, x86_64 | Signed release RPM through Zypper |
| Arch Linux, x86_64 or ARM64 | `loopwire-bin` through an existing yay or paru; portable fallback without a helper |
| NixOS | Release-bound Nix package in your user profile |
| Other Linux or unmatched native target | Signed portable archive for x86_64 or ARM64 |

Automatic preserves an existing portable installation when its launcher and support directory are present under
`~/.local`: it upgrades that copy in place so an old command on `PATH` cannot shadow a new system package. An explicit
switch to native/AUR/Nix stops with migration guidance while that portable copy exists; the installer does not delete it.
On NixOS, reconcile the old portable launcher before installing through Nix, since a generic portable binary is not
supported there.

Native package selection is limited to the published distro versions. Portable fallback is not a claim that every
Linux distribution has compatible runtime libraries. Non-Linux systems and unsupported architectures are rejected.

The VitePress public asset and `/install.sh` in the combined website are byte-for-byte copies of `scripts/install.sh`.
The default release downloader verifies `SHA256SUMS.sig` using the embedded release public key, then checks the selected
artifact checksum before installation. AUR and Nix use their existing package verification paths. No separate key
file or source checkout is needed. For a private/local release, pass `--public-key FILE`; `--skip-signature` is limited
to explicitly unsigned portable development installs.

Preview the selected path without downloads or writes:

```bash
curl -fsSL https://loopwire.app/install.sh | bash -s -- --dry-run
```

Run the same automatic command again to install the current release or upgrade an existing installation. Package
managers own their installed files; portable installs replace owned files and support data, including obsolete
files from earlier versions. Failed download or verification leaves the installed copy intact. Keep your old
version tag if you need to reinstall a previous portable release with `--version vX.Y.Z`.

Use `--yes` only when you want unattended package-manager changes. It requires root or usable noninteractive sudo;
normal interactive installs read confirmation from the terminal even when the script is piped into Bash. The
installer never adds package repositories, installs AUR helpers, or edits shell configuration.

## Arch User Repository

With an existing yay helper:

```bash
yay -S --needed loopwire-bin
```

With paru, replace `yay` with `paru`. Without a helper, Automatic uses a portable archive. The AUR stable source-built
`loopwire`, prebuilt `loopwire-bin`, and rolling `loopwire-git` variants conflict because they install the same commands;
install only one. To build the stable tagged source package manually:

```bash
git clone https://aur.archlinux.org/loopwire.git
cd loopwire
makepkg -si
```

## Native packages

Automatic performs the download and verification steps for you. For manual installation, run the matching block
below together in an empty directory. Commands are connected with `&&` so failed downloads or checks stop the install.
These are direct `v0.1.0` downloads, not distro repositories. Use Automatic to select the latest available release.

The RPM files have no embedded RPM signature. The commands authenticate the download using the signed SHA-256
manifest first, then permit this local RPM for that install; repository dependency checks remain enabled.

### Ubuntu 24.04

x86_64 only.

```bash
curl -fSLO https://github.com/sandwichfarm/loopwire/releases/download/v0.1.0/loopwire_0.1.0-1ubuntu24.04_amd64.deb &&
curl -fSLO https://github.com/sandwichfarm/loopwire/releases/download/v0.1.0/SHA256SUMS &&
curl -fSLO https://github.com/sandwichfarm/loopwire/releases/download/v0.1.0/SHA256SUMS.sig &&
curl -fsSL https://raw.githubusercontent.com/sandwichfarm/loopwire/7e0c6b17a5b12efc9f62df9a314781ad9fbb20ec/packaging/release-signing-public.pem -o loopwire-release-key.pem &&
openssl dgst -sha256 -verify loopwire-release-key.pem -signature SHA256SUMS.sig SHA256SUMS &&
sha256sum --check --ignore-missing SHA256SUMS &&
sudo apt install ./loopwire_0.1.0-1ubuntu24.04_amd64.deb
```

[Repository work to shorten this setup](https://github.com/sandwichfarm/loopwire/issues/35) tracks signed metadata,
release publication, clean-guest install/upgrade verification, and updated instructions.

### Debian 13

x86_64 only.

```bash
curl -fSLO https://github.com/sandwichfarm/loopwire/releases/download/v0.1.0/loopwire_0.1.0-1debian13_amd64.deb &&
curl -fSLO https://github.com/sandwichfarm/loopwire/releases/download/v0.1.0/SHA256SUMS &&
curl -fSLO https://github.com/sandwichfarm/loopwire/releases/download/v0.1.0/SHA256SUMS.sig &&
curl -fsSL https://raw.githubusercontent.com/sandwichfarm/loopwire/7e0c6b17a5b12efc9f62df9a314781ad9fbb20ec/packaging/release-signing-public.pem -o loopwire-release-key.pem &&
openssl dgst -sha256 -verify loopwire-release-key.pem -signature SHA256SUMS.sig SHA256SUMS &&
sha256sum --check --ignore-missing SHA256SUMS &&
sudo apt install ./loopwire_0.1.0-1debian13_amd64.deb
```

[Repository work to shorten this setup](https://github.com/sandwichfarm/loopwire/issues/35) tracks signed metadata,
release publication, clean-guest install/upgrade verification, and updated instructions.

### Fedora 44

x86_64 only.

```bash
curl -fSLO https://github.com/sandwichfarm/loopwire/releases/download/v0.1.0/loopwire-0.1.0-1.fc44.x86_64.rpm &&
curl -fSLO https://github.com/sandwichfarm/loopwire/releases/download/v0.1.0/SHA256SUMS &&
curl -fSLO https://github.com/sandwichfarm/loopwire/releases/download/v0.1.0/SHA256SUMS.sig &&
curl -fsSL https://raw.githubusercontent.com/sandwichfarm/loopwire/7e0c6b17a5b12efc9f62df9a314781ad9fbb20ec/packaging/release-signing-public.pem -o loopwire-release-key.pem &&
openssl dgst -sha256 -verify loopwire-release-key.pem -signature SHA256SUMS.sig SHA256SUMS &&
sha256sum --check --ignore-missing SHA256SUMS &&
sudo dnf --setopt=localpkg_gpgcheck=0 install ./loopwire-0.1.0-1.fc44.x86_64.rpm
```

[Repository work to shorten this setup](https://github.com/sandwichfarm/loopwire/issues/36) tracks signed metadata,
release publication, clean-guest install/upgrade verification, and updated instructions.

### openSUSE Tumbleweed

x86_64 only.

```bash
curl -fSLO https://github.com/sandwichfarm/loopwire/releases/download/v0.1.0/loopwire-0.1.0-1.x86_64.rpm &&
curl -fSLO https://github.com/sandwichfarm/loopwire/releases/download/v0.1.0/SHA256SUMS &&
curl -fSLO https://github.com/sandwichfarm/loopwire/releases/download/v0.1.0/SHA256SUMS.sig &&
curl -fsSL https://raw.githubusercontent.com/sandwichfarm/loopwire/7e0c6b17a5b12efc9f62df9a314781ad9fbb20ec/packaging/release-signing-public.pem -o loopwire-release-key.pem &&
openssl dgst -sha256 -verify loopwire-release-key.pem -signature SHA256SUMS.sig SHA256SUMS &&
sha256sum --check --ignore-missing SHA256SUMS &&
sudo zypper install --allow-unsigned-rpm ./loopwire-0.1.0-1.x86_64.rpm
```

[Repository work to shorten this setup](https://github.com/sandwichfarm/loopwire/issues/37) tracks signed metadata,
release publication, clean-guest install/upgrade verification, and updated instructions.

## Nix / NixOS

With Nix already installed, add the release-bound package to your user profile:

```bash
nix --extra-experimental-features "nix-command flakes" profile install github:sandwichfarm/loopwire#loopwire-bin
```

This enables the required experimental features for this command only. Use Automatic for repeated installs and
upgrades; it detects an existing matching profile entry. On another Linux distribution with Nix installed, choose
Nix explicitly with `curl -fsSL https://loopwire.app/install.sh | bash -s -- --method nix`.
For declarative NixOS setups, add the package to your configuration rather than managing the same package twice.
The flake pins the release version: `--version` applies to native/portable downloads and is rejected for Nix.
If a matching package already uses a different pinned flake reference, the installer stops without changing your
profile; inspect `nix profile list` and intentionally reconcile that entry before switching references.

## Portable Linux

Choose the user-scoped archive on a compatible glibc desktop:

```bash
curl -fsSL https://loopwire.app/install.sh | bash -s -- --method portable
```

Commands are installed under `~/.local/bin` and support files under `~/.local/lib/loopwire`. If the bin directory is
not on `PATH`, launch `~/.local/bin/loopwire`; the installer prints guidance without editing your shell files.
The GUI requires GTK 3 and WebKitGTK 4.1 runtime libraries. The portable path does not install missing system
libraries. Use the Nix path on NixOS instead of a generic Linux executable.

Pass `--prefix DIR` to choose a different bin directory (support files go in its sibling `lib/loopwire`). A custom
prefix or release `--base-url` selects the portable path by default for compatibility with local release tests.
Reruns replace the owned commands and support files without duplicating them or changing your saved routing state.

## Source install

```bash
git clone https://github.com/sandwichfarm/loopwire
cd loopwire
pnpm install
pnpm check
```

This contributor path needs Node.js 22.12+, pnpm 11.3+, and the development prerequisites documented in the
[developer guide](../developer/architecture.md). It installs workspace dependencies and verifies the project;
launch the development shell with `pnpm --filter @loopwire/desktop dev`.

## Installer verification

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
- `packaging/aur/loopwire-git/PKGBUILD.in` for the rolling default-branch source build.
- `flake.nix` exposes `packages.<system>.loopwire-bin` from `packaging/nix/loopwire-bin.nix`, pinned to the signed
  `v0.1.0` release hashes for `x86_64-linux` and `aarch64-linux`.
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

The AUR recipes are published as separate package bases. The default Nix package is now release-bound for `v0.1.0`,
but fresh local non-skipped build proof currently covers only `x86_64-linux`; do not describe `aarch64-linux` as
locally verified until it gets its own native proof run.
