# Packaging

Loopwire package metadata is release-artifact-first. AUR, Nix, curl installer, and native distro packages consume
the same release artifacts:

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
manifest when a private key is provided.

`scripts/sign-release-artifacts.sh` signs `SHA256SUMS`; `scripts/verify-release-signature.sh` verifies
`SHA256SUMS.sig`. Keep the private key out of the repository. Commit only the public key once the real release key is
created. Use `pnpm release:prepare-key -- --private-key-out /secure/loopwire-release-private.pem` to generate and
verify the key pair without placing the private key under the repository.

## AUR

`packaging/aur/PKGBUILD.in` is a template for `loopwire-bin`. Replace:

- `@VERSION@`,
- `@SHA256_X86_64@`,
- `@SHA256_AARCH64@`.

The generated `PKGBUILD` must be tested with `makepkg` against published artifacts before any AUR submission.

For local release-shaped smoke, render the template against generated artifacts and build without installing:

```bash
pnpm verify:aur
```

That command uses `makepkg --nodeps` in a temp directory when `makepkg` is available. It does not install the package or
submit anything to AUR.

## Nix

`flake.nix` exposes `packages.<system>.loopwire-bin` and `packages.<system>.default` from
`packaging/nix/loopwire-bin.nix` for `x86_64-linux` and `aarch64-linux`. The default flake package intentionally uses
`nixpkgs.lib.fakeHash` until the first public release provides real artifact hashes.

After a release exists, use `lib.<system>.mkLoopwireBinPackage` with the published version and per-system hashes from
release metadata. Do not describe the flake package as release-ready until those hashes are real and `nix build` has
been run against published artifacts.

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
proves duplicate checksum entries and tampered package evidence are rejected. It uses local `dpkg-deb`/`rpmbuild`
when available and isolated Ubuntu/Fedora builder containers otherwise.

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
```

`verify:install` creates a local fake release artifact, signs and verifies `SHA256SUMS`, installs it into a temp prefix,
runs the installed binary, and confirms a tampered artifact is rejected. It does not touch system paths or the network.

`verify:release` creates release artifacts through `scripts/package-release.sh`, checks same-input reproducibility,
verifies multi-architecture checksum entries, signs the manifest, installs the generated host-architecture tarball
through `scripts/install.sh`, and proves `loopwire --background --help` works from the extracted and installed
launcher.

`verify:aur` renders the AUR template from generated local artifacts, runs `makepkg --nodeps` in a temp directory, and
checks the package archive contains `usr/bin/loopwire`, `usr/bin/loopwire-dsp-provider`, and
`usr/bin/loopwire-jack-ports`. It skips cleanly on hosts without `makepkg`.

`verify:packaging` statically checks that package metadata points at the same release artifact names as the installer
and that the flake exposes the binary package template without replacing fake hashes with unverified values. It also
renders a temporary Nix release package expression from checksum-bound fake artifacts and proves duplicate manifest
entries are rejected. It invokes the Nix verifier with `--render-only` against fake local artifacts, so it does not
replace real release-time `nix build` evidence. It also runs the native package reproducibility and proof-verifier
regressions; this still does not substitute for the matching-guest KVM run.
