# Packaging

Loopwire binary package metadata is release-artifact-first. `loopwire-bin`, Nix, the curl installer, and native
distro packages consume the same release artifacts, while the unsuffixed AUR `loopwire` recipe compiles the immutable
tagged source archive:

- `loopwire-linux-x86_64.tar.gz`
- `loopwire-linux-aarch64.tar.gz`
- `SHA256SUMS`
- `SHA256SUMS.sig`

Do not publish package metadata with placeholder versions or checksums. These files are templates until the release
workflow emits real artifacts.

`scripts/package-release.sh` is the canonical tarball producer. It writes `loopwire-linux-${arch}.tar.gz` and updates
`SHA256SUMS` with reproducible tar metadata controlled by `SOURCE_DATE_EPOCH`. The tarball contains a launcher at
`loopwire`, a file-backed DSP provider launcher at `loopwire-dsp-provider`, a fail-closed JACK virtual-port provider
wrapper at `loopwire-jack-ports`, a read-only backend detector at `loopwire-detect-audio`, the Tauri GUI binary at
`libexec/loopwire/loopwire-gui`, and bundled background
restore/provider assets under `libexec/loopwire/scripts` and `libexec/loopwire/packages`.

`scripts/stage-release-artifacts.sh` is the canonical release attachment staging command. It packages the binary
tarball, copies the Tauri AppImage, and on x86_64 `--native-packages` replaces Tauri's GUI-only deb/rpm bundles with
the repository-owned packages described below. It rewrites `SHA256SUMS` for every staged attachment and signs the
manifest when a private key is provided. Release AArch64 jobs use `--appimage-only`, because no AArch64 deb/RPM path
has matching package proof yet.

`scripts/sign-release-artifacts.sh` signs `SHA256SUMS`; `scripts/verify-release-signature.sh` verifies
`SHA256SUMS.sig`. Keep the private key out of the repository. Commit only the public key once the real release key is
created. Use `pnpm release:prepare-key -- --private-key-out /secure/loopwire-release-private.pem` to generate and
verify the key pair without placing the private key under the repository.

## AUR

The stable and rolling AUR recipes are deliberately separate:

- `packaging/aur/loopwire/PKGBUILD.in` builds the immutable tagged source archive and owns the exact `loopwire`
  package base.
- `packaging/aur/loopwire-bin/PKGBUILD.in` consumes the signed architecture-specific release tarballs and owns
  `loopwire-bin`.
- `packaging/aur/loopwire-git/PKGBUILD.in` builds the current default branch, derives `pkgver` from Git history, and
  owns `loopwire-git`.

The source template replaces `@VERSION@`, `@PKGREL@`, and `@SHA256_SOURCE@`. The binary template replaces
`@VERSION@`, `@PKGREL@`, `@SHA256_X86_64@`, and `@SHA256_AARCH64@`. The recipes declare conflicts/provides so only
one variant can own the installed `loopwire` files. The VCS recipe uses `SKIP` only for its moving Git source; the
packager-supplied MIT license remains checksum-bound.

Every generated `PKGBUILD` must be tested with `makepkg` against its published tag or release artifacts before AUR
submission.

For local release-shaped smoke, render the template against generated artifacts and build without installing:

```bash
pnpm verify:aur
pnpm verify:aur:source -- --version 0.1.0
pnpm verify:aur:git
```

`verify:aur` builds the binary recipe and checks stable plus VCS source metadata. `verify:aur:source` and
`verify:aur:git` perform the heavier stable-tag and rolling-branch compilations. None installs or submits a package.
The VCS build intentionally runs without any AUR key. Its key-bearing publication path revalidates and pushes only
the reviewed `PKGBUILD`, `.SRCINFO`, and license metadata; it never executes the moving branch source.

Publish from a clean Arch checkout with the AUR key loaded or available for an interactive passphrase prompt:

```bash
pnpm deploy:aur -- --package loopwire --tag v0.1.0 --key ~/.ssh/aur
pnpm deploy:aur -- --package loopwire-bin --tag v0.1.0 --key ~/.ssh/aur
pnpm deploy:aur -- --package loopwire-git --tag v0.1.0 --key ~/.ssh/aur
```

The helper downloads checksum-bound stable inputs, builds and inspects stable packages, generates `.SRCINFO`, and
increments `pkgrel` when same-version metadata changes. It commits `PKGBUILD`, `.SRCINFO`, and `LICENSE-MIT`, then
pushes the package-aligned AUR Git repo and verifies the remote commit. `.github/workflows/publish-aur.yml` exposes the same path as an
environment-protected
manual dispatch after its dedicated `AUR_SSH_PRIVATE_KEY` secret is configured. The workflow pins the AUR Ed25519 host
key in `packaging/aur/known_hosts`; verify any future key rotation against the official AUR homepage before updating it.

## Nix

`flake.nix` exposes `packages.<system>.loopwire-bin` and `packages.<system>.default` from
`packaging/nix/loopwire-bin.nix` for `x86_64-linux` and `aarch64-linux`. The default flake package is pinned to the
signed `v0.1.0` release tarball hashes for both systems.
`flake.lock` pins the nixpkgs revision used to evaluate and build those outputs.

Use `lib.<system>.mkLoopwireBinPackage` when a newer release exists and you need to inject a different published
version/hash set. Fresh local proof in this repository only covers `x86_64-linux` via a non-skipped `nix build`
against published artifacts; `aarch64-linux` still needs native proof before that host is described as verified.

Render a reviewable Nix package expression from a signed release directory:

```bash
pnpm nix:render-release -- \
  --version 0.1.0 \
  --release-dir dist/release \
  --public-key packaging/release-signing-public.pem \
  --output dist/release/loopwire-bin-release.nix
```

The renderer reads the canonical tarball entries from `SHA256SUMS`, verifies the asset checksums, optionally verifies
`SHA256SUMS.sig` through the project public key, converts the hashes to Nix SRI form, and fails on missing or duplicate
manifest entries. The output is still not publication proof until a Nix-enabled host runs `nix build` against published
artifacts.

Run the full Nix package proof on a Nix-enabled host:

```bash
pnpm verify:nix-release -- \
  --version 0.1.0 \
  --release-dir dist/release \
  --public-key packaging/release-signing-public.pem
```

For final release proof, prefer the published GitHub Release coordinates so the verifier downloads the same signed
assets that users and package metadata will consume:

```bash
pnpm verify:nix-release -- \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --public-key packaging/release-signing-public.pem
```

On non-Nix hosts, release-readiness wiring can be checked without claiming build proof:

```bash
pnpm verify:nix-release -- \
  --version 0.1.0 \
  --release-dir dist/release \
  --skip-build-if-missing-nix
```

The skip flag is only for local or CI wiring checks on hosts without `nix`. Final release proof and release evidence
still require the non-skipped command to run successfully.

For fake-artifact metadata smokes, use render-only mode:

```bash
pnpm verify:nix-release -- \
  --version 0.1.0 \
  --release-dir dist/release \
  --render-only
```

Render-only mode proves manifest parsing and expression generation. It never proves the package builds.

## Signed Fedora repository

The project-owned Fedora channel serves only Fedora 44 x86_64. It reuses the native Fedora recipe below, verifies the
exact RPM against the OpenSSL-signed GitHub Release checksum manifest, signs a staging copy with a dedicated OpenPGP
repository key, and generates signed DNF metadata. The original GitHub Release asset stays unchanged. This path was
selected over COPR to preserve exact release-artifact control, atomic promotion, indefinite retention, and local/CI
proof; maintainers accept responsibility for the SSH/POSIX origin and signing-key lifecycle.

Build and verify a candidate with the pinned RPM tools image or the equivalent host tools:

```bash
python3 scripts/rpm-repository.py build \
  --release-dir dist/release --version 0.1.0 --output dist/rpm-repository \
  --signing-key "$RPM_FPR" --gnupg-home "$RPM_GNUPG_HOME" \
  --release-public-key packaging/release-signing-public.pem
python3 scripts/rpm-repository.py verify \
  --repository dist/rpm-repository --public-key rpm-public.asc --fingerprint "$RPM_FPR"
```

The public target is `/fedora/44/x86_64/`. Package RPMs, fingerprint-named public keys, checksum-named metadata, and
private snapshots are retained. The SSH publisher installs immutable objects first, writes the new detached
`repomd.xml.asc`, and atomically replaces `repomd.xml` as the metadata commit point. Compare-and-swap revision checks,
a server lock, and a recovery journal prevent stale or incomplete promotion from being treated as success.

Production publication uses `.github/workflows/publish-fedora.yml` and the protected `packages-production`
environment. `FEDORA_REPOSITORY_ENABLED` remains false until the origin, SSH host pins, dedicated signing identity,
approval policy, and public verification are ready. The checked-in `packaging/repositories/fedora-channel.json`
therefore remains pending and the homepage keeps the existing signed direct-download command.

The client helper writes only `/etc/yum.repos.d/loopwire.repo` and a fingerprint-named public key under
`/etc/pki/rpm-gpg/`. It keeps `gpgcheck=1` and `repo_gpgcheck=1`; repository installation never uses the local-RPM
signature exception:

```bash
sudo bash scripts/setup-fedora-repository.sh \
  --base-url 'https://HOST/fedora/44/x86_64' --fingerprint "$RPM_FPR"
sudo dnf makecache --refresh
sudo dnf install loopwire
```

These commands are illustrative until the channel record is verified. User instructions must take the URL and full
fingerprint from the [gated Fedora repository guide](../apps/docs/docs/guide/fedora-repository.md), not a source-tree
placeholder. See the [maintainer runbook](../apps/docs/docs/developer/fedora-repository.md) for the provider decision,
production layout, protected configuration, publication/recovery, rollback, caching, key rotation, and activation.

## Signed openSUSE repository

The project-owned openSUSE channel targets Tumbleweed x86_64 at `/opensuse/tumbleweed/x86_64/`. It authenticates the
existing release RPM with the project's OpenSSL-signed checksum manifest, signs a staged copy with a dedicated
OpenPGP repository key, and publishes authenticated RPM metadata. The original GitHub Release file stays unchanged;
the manifest records source and distributed hashes. This approach was selected over OBS to preserve the current
release identity and publication/recovery proof. It does not provision or advertise an OBS project.

The input directory needs the signed release checksum manifest plus `release-assets.json`, the x86_64 portable
archive, and the exact openSUSE RPM. Their authenticated inventory binds the release tag, full source commit, and
source/build hashes; a lone RPM and checksum entry do not satisfy the openSUSE provenance contract.

Use the explicit command-line target for the shared repository generator and publisher:

```bash
python3 scripts/rpm-repository.py build --target opensuse-tumbleweed-x86_64 \
  --release-dir dist/release --version 0.1.0 --output dist/opensuse-repository \
  --signing-key "$RPM_FPR" --gnupg-home "$RPM_GNUPG_HOME" \
  --release-public-key packaging/release-signing-public.pem
python3 scripts/rpm-repository.py verify --target opensuse-tumbleweed-x86_64 \
  --repository dist/opensuse-repository --public-key rpm-public.asc --fingerprint "$RPM_FPR"
```

The publisher keeps this target's private state under `ROOT/channels/opensuse-tumbleweed-x86_64` and its served
objects under `ROOT/public/opensuse/tumbleweed/x86_64`. The protected workflow uses `OPENSUSE_REPOSITORY_ENABLED` and
the `packages-production` environment. Origin, signing key, credentials, public proof, and first activation remain
human operations. The checked-in `packaging/repositories/opensuse-channel.json` stays pending until its reviewed
production proof record exists.

The helper writes only the managed Zypper source and fingerprint-named key, verifies the complete fingerprint before
refresh, and preserves `gpgcheck=1`, `repo_gpgcheck=1`, `pkg_gpgcheck=1`, priority 99, and normal vendor protection.
User instructions come from the [gated openSUSE guide](../apps/docs/docs/guide/opensuse-repository.md). The
[operator runbook](../apps/docs/docs/developer/opensuse-repository.md) covers publishing, rollback, retained snapshots,
rotation, removal, and the required newer-snapshot compatibility rerun. A failed newer Tumbleweed snapshot blocks
activation; one passing snapshot does not establish support for all future rolling updates.

## Native deb and RPM packages

The native package recipes install the complete canonical payload: GUI, background restore, DSP and JACK provider
wrappers, backend detector, desktop entry, and icon.

| Target | Recipe | Output |
|--------|--------|--------|
| Ubuntu 24.04 LTS x86_64 | `packaging/deb/ubuntu-24.04.control.in` | `loopwire_<version>-1ubuntu24.04_amd64.deb` |
| Debian 13 stable x86_64 | `packaging/deb/debian-13.control.in` | `loopwire_<version>-1debian13_amd64.deb` |
| Fedora 44 x86_64 | `packaging/rpm/fedora-44.spec.in` | `loopwire-<version>-1.fc44.x86_64.rpm` |
| openSUSE Tumbleweed x86_64 | `packaging/rpm/opensuse-tumbleweed.spec.in` | `loopwire-<version>-1.x86_64.rpm` |

Build from an already generated canonical release directory:

```bash
pnpm package:deb -- --target ubuntu-24.04 --version 0.1.0 --arch x86_64 \
  --release-dir dist/release --output-dir dist/native-packages
pnpm package:deb -- --target debian-13 --version 0.1.0 --arch x86_64 \
  --release-dir dist/release --output-dir dist/native-packages
pnpm package:rpm -- --target fedora-44 --version 0.1.0 --arch x86_64 \
  --release-dir dist/release --output-dir dist/native-packages
pnpm package:rpm -- --target opensuse-tumbleweed --version 0.1.0 --arch x86_64 \
  --release-dir dist/release --output-dir dist/native-packages
```

`pnpm verify:native-packaging` builds every recipe twice, requires byte-identical output, checks package metadata, and
proves duplicate checksum entries and tampered package evidence are rejected. It uses local `dpkg-deb` when available
and always runs RPM reproducibility through the matching Fedora/openSUSE toolchain. Use
`pnpm package:native` to build all four release attachments through those same target containers; this avoids
host-RPM-version differences in release output.

Matching-guest proof is a separate, stronger gate:

```bash
pnpm build:portable-linux -- --output .vm/native-packages/release/loopwire
# Generate the canonical tarball/checksum with scripts/package-release.sh, then:
pnpm vm:native-packages -- run-all \
  --version 0.1.0 \
  --release-dir .vm/native-packages/release
```

`packaging/vm/native-package-targets.tsv` pins each official cloud-image URL and checksum. The runner verifies that
checksum, boots a separate KVM guest, binds SSH to loopback, builds and installs through the guest package manager,
requires a Loopwire-named X11 window under Xvfb, runs packaged CLI/backend smokes, uninstalls, and stores raw proof under
ignored `.vm/native-packages/evidence/<target>/<commit>/`. Containers provide QEMU binaries only; they do not count as
guest proof. `pnpm verify:native-vm-proof -- --git-head <commit>` rechecks all four proof directories.

The first complete matrix passed at commit `70eee4ec433bb7d967931357cf77bd0c28056a35`. A review-safe, CI-checked subset
is committed under `vm/native-package-proof/`; the raw packages, VM disks, console output, and full command logs remain
ignored beneath `.vm/`. Recreate the snapshot only from fully verified raw evidence:

```bash
pnpm vm:promote-native-package-proof -- \
  --git-head 70eee4ec433bb7d967931357cf77bd0c28056a35
pnpm verify:native-package-proof-snapshot
```

The snapshot verifier also compares every package/runtime/proof-critical path against the tested commit. The release
stager calls it before building native attachments, so a later package, desktop runtime, release payload, image
manifest, guest smoke, or raw-verifier change blocks release until the four-guest proof is refreshed. Documentation and
snapshot-promotion tooling may advance independently because they do not change the package exercised by the guests.

## Smoke

Run:

```bash
pnpm verify:install
pnpm verify:release
pnpm verify:aur
pnpm verify:nix-release -- --version 0.1.0 --release-dir dist/release --render-only
pnpm verify:packaging
bash scripts/with-rpm-tools.sh --container python3 scripts/test-rpm-repository.py
node --test apps/site/src/lib/rpmChannel.test.mjs
```

`verify:install` creates a local fake release artifact, signs and verifies `SHA256SUMS`, installs it into a temp prefix,
runs the installed binary, and confirms a tampered artifact is rejected. It does not touch system paths or the network.

`verify:release` creates release artifacts through `scripts/package-release.sh`, checks same-input reproducibility,
verifies multi-architecture checksum entries, signs the manifest, installs the generated host-architecture tarball
through `scripts/install.sh`, and proves `loopwire --background --help` works from the extracted and installed
launcher.

`verify:aur` renders both AUR templates, runs a `makepkg --nodeps` binary-package build, checks the package archive,
and validates source-package `.SRCINFO`. It skips cleanly on hosts without `makepkg`. `verify:aur:source` separately
builds the tagged source recipe and checks the complete runtime, desktop entry, and icon.

`verify:packaging` statically checks that package metadata points at the same release artifact names as the installer
and that the flake keeps the signed `v0.1.0` SRI hashes wired while render-only metadata smokes stay separate from real
release proof. It also renders a temporary Nix release package expression from checksum-bound fake artifacts and proves
duplicate manifest entries are rejected. It invokes the Nix verifier with `--render-only` against fake local artifacts,
so it does not replace real release-time `nix build` evidence. It also runs the native package reproducibility and
proof-verifier regressions; this still does not substitute for the matching-guest KVM run.
