# Release

Loopwire releases are artifact-first. Every install channel must consume the same tarballs, `SHA256SUMS`, and
`SHA256SUMS.sig`.

## Local Artifact Smoke

```bash
pnpm verify:release
pnpm verify:docs
```

This creates temporary release artifacts with `scripts/package-release.sh`, verifies reproducible output for identical
input, signs and validates `SHA256SUMS`, installs the generated host-architecture tarball through `scripts/install.sh`,
and runs the installed binary from a temp prefix. The smoke also checks `loopwire --background --help` from the extracted
tarball and the installed prefix, proving the packaged restore entrypoint is present.
`verify:docs` confirms the public install, support, troubleshooting, screenshot, and release-note docs stay linked in
the VitePress navigation.

## Evidence Bundle

For release candidates and VM runs, collect an attachable evidence bundle:

```bash
pnpm collect:evidence -- --output-dir .release-evidence/v0.1.0 --profile full --release-tag v0.1.0
```

The collector writes command logs plus `release-evidence.json`, including git state, tool versions, command exit codes,
backend detection, Rust compile status, workflow parsing, release-readiness preflight state, and GSD milestone state.
The full profile records the strict publish preflight and published-release installer smoke as optional evidence, and
the manifest exposes parsed `release.findings` plus `release.blockers` from the readiness log. This lets a candidate
bundle show current blockers without failing evidence collection. Use `--profile quick` inside VM runs when a full
workspace check has already been captured separately.

For final release evidence after the GitHub Release exists, make published-release installer smoke mandatory:

```bash
pnpm collect:evidence -- \
  --output-dir .release-evidence/v0.1.0-published \
  --profile full \
  --release-tag v0.1.0 \
  --require-published-release
```

Preview the evidence command plan without running commands or writing files:

```bash
pnpm collect:evidence -- --list-commands --profile full --require-published-release
```

Parse an existing release-readiness log without rerunning release checks:

```bash
pnpm collect:evidence -- --summarize-release-readiness-log release-readiness-publish-preflight.log
```

For user-facing bug reports and compatibility triage, collect the smaller redacted support bundle instead:

```bash
pnpm collect:support -- --output-dir .support/$(date +%Y%m%d-%H%M%S) --profile quick
```

Use `--profile full` when the maintainer also needs `pnpm check` and Tauri Rust compile logs. The support bundle writes
`support-bundle.json`, `command-results.tsv`, `notes.md`, backend detection, host diagnostics, and autostart status.
It never uploads data automatically.

## Published Release Smoke

CI can exercise the same verifier against a local staged release directory before any GitHub Release exists:

```bash
bash scripts/verify-published-release.sh \
  --release-dir dist/release \
  --public-key packaging/release-signing-public.pem
```

The local directory mode requires both canonical Linux tarballs, verifies they are listed in `SHA256SUMS`, verifies
`SHA256SUMS.sig`, checks every checksum entry, installs the host tarball from that directory, and runs the installed
binary. `pnpm verify:scripts` covers this mode with a signed fake release, a missing-architecture rejection case, and a
tampered-asset rejection case.

After a tag workflow publishes assets, verify the release surface itself:

```bash
pnpm verify:published-release -- \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --public-key packaging/release-signing-public.pem
```

The script downloads release assets with `gh`, requires the `x86_64` and `aarch64` canonical tarballs, verifies the
signed manifest and checksum entries, installs from the downloaded asset directory, and runs the installed binary. This
must pass before docs or package templates claim a public release is installable.

## Artifact Contract

The curl installer and binary package templates expect these files in each GitHub Release:

- `loopwire-linux-x86_64.tar.gz`
- `loopwire-linux-aarch64.tar.gz`
- `SHA256SUMS`
- `SHA256SUMS.sig`

Tauri bundle outputs for AppImage, deb, and rpm are release attachments too, but package managers should still anchor on
the canonical tarballs unless a channel-specific package requires a native format.

Each canonical tarball contains a `loopwire` launcher plus installed support files under `libexec/loopwire/`:

- `loopwire` starts the GUI by default.
- `loopwire --background ...` runs the bundled background restore script.
- `libexec/loopwire/loopwire-gui` is the Tauri desktop binary.
- `libexec/loopwire/scripts/restore-background.mjs` and `libexec/loopwire/packages/*/dist` are the packaged restore
  engine.

The background launcher requires `node` on `PATH`. Package templates add it as a runtime dependency.

Each release tag must also have a versioned docs page at `apps/docs/docs/release-notes/<version>.md`. For tag `v0.1.0`,
the workflow expects `apps/docs/docs/release-notes/0.1.0.md`.

## GitHub Release Workflow

`.github/workflows/release.yml` runs on `v*` tag pushes or manual dispatch with an existing `v`-prefixed tag. The
workflow:

1. Builds Linux artifacts through a matrix for `x86_64` on `ubuntu-22.04` and `aarch64` on `ubuntu-22.04-arm`.
2. Uses Ubuntu 22.04-family runners so Linux builds keep an older supported glibc baseline.
3. Installs the current Tauri v2 Linux prerequisites, including WebKitGTK 4.1 development packages.
4. Runs `pnpm check` and `cargo check` on each architecture.
5. Builds Tauri Linux bundles on each architecture.
6. Requires versioned release notes for the tag and rejects release-candidate/not-published wording.
7. Stages architecture-specific release attachments with `scripts/stage-release-artifacts.sh`.
8. Installs each generated architecture tarball from its local release directory with signature verification.
9. Uploads the architecture artifacts to the publish job.
10. Regenerates one combined `SHA256SUMS` and `SHA256SUMS.sig` covering every staged release attachment.
11. Installs the generated host tarball from the combined local release directory with signature verification.
12. Creates or updates the GitHub Release with the generated artifacts and versioned release notes.
13. Downloads the published GitHub Release assets and runs a post-publish installer smoke.

The baseline follows Tauri's current Linux distribution guidance: build on the oldest supported base that provides
WebKitGTK 4.1, with Ubuntu 22.04 or Debian 12 as suitable examples.

The desktop package build sets `NO_STRIP=true` for Tauri bundling. Local Arch validation showed AppImage bundling can
fail when linuxdeploy's bundled `strip` cannot read newer `.relr.dyn` ELF sections, even though the application binary
compiled successfully.

## Release Readiness Preflight

Before pushing a release tag, run:

```bash
pnpm verify:release-readiness -- \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --public-key packaging/release-signing-public.pem
```

The preflight does not publish. It checks versioned release notes, rejects release-candidate/not-published wording,
validates the signing public key, checks local or remote tag visibility, verifies repository access, and confirms
required GitHub secrets for release and Bunny.net docs deployment.

## Workflow Contract

```bash
pnpm verify:workflows
```

The workflow contract parser validates CI, continuous host diagnostics, docs deployment, release publication, and VM
matrix workflow files. It checks the release workflow still requires versioned notes, signing secrets, generated and
published install smokes, and that VM/support-matrix changes trigger VM matrix validation.

## Signing Key Setup

Release signing uses OpenSSL to sign `SHA256SUMS`, not each artifact independently. Generate the key outside the repo,
commit only the public key, and store the private key as a GitHub secret:

```bash
pnpm release:prepare-key -- \
  --private-key-out /secure/loopwire-release-private.pem \
  --public-key-out packaging/release-signing-public.pem
bash scripts/setup-github-secrets.sh \
  --repo sandwichfarm/loopwire \
  --release-private-key-file /secure/loopwire-release-private.pem
```

`release:prepare-key` refuses to write the private key inside the repository, refuses to overwrite existing key files
unless `--force` is passed, derives the public key, and verifies the pair by signing and verifying a temporary
`SHA256SUMS` payload.

The release workflow requires `LOOPWIRE_RELEASE_PRIVATE_KEY`. The installer requires a trusted public key unless
`--skip-signature` is passed explicitly for local unsigned development artifacts.

Audit or preview the GitHub secret ceremony before setting anything:

```bash
bash scripts/setup-github-secrets.sh --print-required
bash scripts/setup-github-secrets.sh --repo sandwichfarm/loopwire --check
bash scripts/setup-github-secrets.sh \
  --repo sandwichfarm/loopwire \
  --storage-zone loopwire-docs \
  --access-key "$BUNNY_ACCESS_KEY" \
  --release-private-key-file /secure/loopwire-release-private.pem \
  --dry-run
```

`--check` reads secret names only. `--dry-run` validates inputs and prints secret names that would be set without
printing secret values or writing to GitHub.

## Boundaries

- The workflow now has a dedicated `ubuntu-22.04-arm` AArch64 lane, but public AArch64 proof still requires a tagged
  workflow run and published `loopwire-linux-aarch64.tar.gz` asset.
- Package templates must not be published until a tagged release has real checksums and package-build smoke evidence
  against those published artifacts.
- `packaging/release-signing-public.pem` still needs a real project release public key before public installer claims.
- The installer does not mutate system audio configuration.

## AUR Smoke

```bash
pnpm verify:aur
```

The AUR smoke renders `packaging/aur/PKGBUILD.in` against generated local artifacts, runs `makepkg --nodeps` in a temp
directory when `makepkg` is available, and checks the resulting package archive contains `usr/bin/loopwire`. It does not
install the package or submit anything to AUR.

## Documentation Ceremony

Before pushing a release tag:

1. Move the user-facing notes from `/release-notes/unreleased` into a versioned release-note page.
2. Start a fresh `/release-notes/unreleased` page with known follow-up work and unsupported claims.
3. Update support matrix rows when VM evidence changes.
4. Refresh `product-screenshot.svg` only from a current app build or a reviewed visual mock that matches the app.
5. Run `pnpm verify:docs` and `pnpm build:docs`.

Release notes must describe what is supported, what remains experimental, and which install channels were smoke-tested.

## Docs Deployment

The docs deployment workflow builds VitePress, uploads a docs artifact, and deploys to Bunny.net only on explicit
workflow dispatch, `main`, `master`, or `v*` tags. The deploy job is assigned to the `docs-production` GitHub
environment so repository protection rules can require manual review or protected branches.

If Bunny.net secrets are missing, the deploy job emits a notice and skips upload instead of failing unrelated CI.

Deployment uses `scripts/deploy-docs-bunny.sh`, which uploads raw files with Bunny Edge Storage's `PUT` endpoint and
the storage-zone password in the `AccessKey` header. The script defaults to `https://storage.bunnycdn.com`, and
`BUNNY_STORAGE_ENDPOINT` can point at a regional endpoint such as `https://ny.storage.bunnycdn.com` when the storage
zone is not in Bunny's default region.

Preview the upload plan without contacting Bunny.net:

```bash
pnpm build:docs
bash scripts/deploy-docs-bunny.sh \
  --dist apps/docs/docs/.vitepress/dist \
  --storage-zone loopwire-docs \
  --storage-endpoint ny.storage.bunnycdn.com \
  --dry-run
```

The GitHub secret helper can set or audit the deployment secrets:

```bash
bash scripts/setup-github-secrets.sh \
  --repo sandwichfarm/loopwire \
  --storage-zone loopwire-docs \
  --access-key "$BUNNY_ACCESS_KEY" \
  --storage-endpoint ny.storage.bunnycdn.com \
  --dry-run
```
