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
tarball and the installed prefix, proving the packaged restore entrypoint is present. Installer smokes also reject
signed artifacts whose tar members contain unsafe absolute or parent-traversing paths before extraction.
`verify:docs` confirms the public install, support, troubleshooting, screenshot, and release-note docs stay linked in
the VitePress navigation.

## Evidence Bundle

For release candidates and VM runs, collect an attachable evidence bundle:

```bash
pnpm collect:evidence -- --output-dir .release-evidence/v0.1.0 --profile full --release-tag v0.1.0
```

The collector writes command logs plus `release-evidence.json`, including git state, tool versions, command exit codes,
backend detection, Rust compile status, workflow parsing, release-readiness preflight state, and GSD milestone state.
The full profile records read-only DSP provider plan evidence as required evidence, and records the strict publish
preflight, published-release installer smoke, and VM bundle verification as optional evidence. The manifest exposes
parsed `release.findings` plus `release.blockers` from the readiness log. This lets a candidate bundle show current
blockers without failing evidence collection. Use `--profile quick` inside VM runs when a full workspace check has
already been captured separately.

For final release evidence after the GitHub Release, docs deployment, and VM bundles exist, make published-release
installer smoke, live docs smoke, and all VM evidence mandatory:

```bash
pnpm collect:evidence -- \
  --output-dir .release-evidence/v0.1.0-published \
  --profile full \
  --release-tag v0.1.0 \
  --require-published-release \
  --require-live-docs \
  --docs-hostname "$BUNNY_PULL_ZONE_HOSTNAME" \
  --require-vm-evidence \
  --require-dsp-provider-plan \
  --vm-target all \
  --vm-evidence-dir '.vm/evidence/{target}'
```

The live docs command runs `scripts/verify-docs-live.sh` against the pull-zone URL, verifies the deployed homepage and
`/install.sh`, and compares the deployed installer with `apps/docs/docs/public/install.sh`.

The VM evidence command expands `--vm-target all` from `vm/targets.tsv` and runs `scripts/verify-vm-evidence.sh`
against each selected bundle. When `--require-published-release` is also present, every VM verifier requires
`published-release-smoke.log` and the successful `published-release-smoke` command ledger row from the guest.
Every evidence bundle also records `vm-launch-plan.tsv` from
`bash scripts/vm-matrix.sh render-launch-plan --all`, so the release archive carries the operator handoff for every
declared VM target, deterministic SSH port, dry-run launch command, and paired evidence-pull command.
The DSP provider plan command runs `scripts/collect-dsp-provider-plan.sh` against
`scripts/fixtures/dsp-provider-configuration.json` without `--execute`, records the expected read-source, write-output,
and verify-output operation rows, and binds the configuration path plus frame count in `release-evidence.json`. It proves
the release still exposes the provider contract without mutating host audio. Release tarballs must also expose
`loopwire-dsp-provider` beside `loopwire`; the provider is file-backed smoke infrastructure, not live backend capture.

The tag release workflow collects the published-release portion automatically after `gh release create` or upload
finishes. It runs `pnpm collect:evidence` with `--require-published-release --require-dsp-provider-plan`, verifies the
bundle with `pnpm verify:release-evidence`, writes `loopwire-release-evidence-<tag>.tar.gz` into the release directory,
regenerates the signed `SHA256SUMS` manifest so the evidence archive is checksummed, uploads the archive plus updated
manifest files to the GitHub Release, and uploads a matching `loopwire-release-evidence-<tag>` workflow artifact. VM
evidence remains operator-collected because GitHub-hosted runners do not provide the declared desktop/audio VM matrix.

The evidence collector and verifier enforce the same v-prefixed semver tag rule as the release workflow. A path-like
tag such as `v0.1.0/preview` is rejected before command planning, manifest acceptance, or archive attachment.
Release proof commands also require repository identity in `OWNER/REPO` form; URLs, spaces, or extra path segments are
rejected before GitHub access or evidence verification.

Preview the evidence command plan without running commands or writing files:

```bash
pnpm collect:evidence -- --list-commands --profile full --require-published-release --require-vm-evidence --vm-target all
```

Verify an already collected final evidence bundle before attaching it to a release or PR:

```bash
pnpm verify:release-evidence -- \
  --evidence-dir .release-evidence/v0.1.0-published \
  --public-key packaging/release-signing-public.pem \
  --git-head "$(git rev-parse HEAD)" \
  --require-published-release \
  --require-live-docs \
  --require-vm-evidence \
  --require-all-vm-targets \
  --require-vm-launch-plan \
  --require-dsp-provider-plan \
  --require-no-release-blockers \
  --require-clean-git
```

The verifier checks `release-evidence.json`, validates git source metadata (`git.head`, `git.origin`, and
`git.statusShort`), proves required commands succeeded, and requires non-empty command logs. Add `--git-head` for final
release bundles that must match the resolved release tag commit. Add `--require-clean-git` for final release bundles
that must prove the evidence came from a clean checkout.
The verifier rejects command log paths that escape the evidence directory or resolve through symlinks. Required VM
evidence must name known `vm/targets.tsv` target ids exactly once, keep each `evidenceDir` relative and target-scoped,
and show the matching
`bash scripts/verify-vm-evidence.sh --target ... --evidence-dir ...` command row. With `--require-all-vm-targets`, the
same check also rejects evidence that misses any target from `vm/targets.tsv`.
With `--require-vm-launch-plan`, the verifier also requires a successful `vm-launch-plan` command row, validates the
`vm-launch-plan.tsv` header and one row for every target, and checks that each row pairs the rendered
`scripts/vm-matrix.sh launch` command with the matching `scripts/collect-vm-evidence-ssh.sh --execute` command.
With `--require-dsp-provider-plan`, the verifier also requires a successful `dsp-provider-plan` command row that invokes
`bash scripts/collect-dsp-provider-plan.sh` in read-only mode and validates `dsp-provider-plan.tsv` contains
read-source, write-output, and verify-output rows for the manifest-bound frame count and configuration. The row
targets, labels, and channel counts must match the configured routed sources and outputs, so unrelated placeholder DSP
rows cannot satisfy final release proof.
When `--require-live-docs` is present, the verifier requires a successful `docs-live-smoke` command row that executed
`bash scripts/verify-docs-live.sh` against the public installer and the same deployed docs base URL or hostname plus
remote prefix recorded in `release-evidence.json`.
When `--require-published-release` is present, the verifier requires a successful `published-release-smoke` command row
that executed `bash scripts/verify-published-release.sh` with the same repo, tag, and public key recorded in
`release-evidence.json`. Pass `--public-key` for final release bundles so the manifest must match the same signing
public key used to verify the release assets. Pass `--git-head` so the evidence manifest must match the tag commit the
release workflow checked out. Those rows are tokenized and must invoke the expected script directly, so an echo command
that only prints the expected verifier path and flags is rejected. Published-release evidence rows must not include
`--release-dir`; local staged release directories are valid for pre-publish smoke tests, but they cannot satisfy final
published-release evidence.

After the GitHub Release exists, Bunny.net docs are live, and all VM bundles have been copied back and promoted, run the
single final proof gate:

```bash
pnpm verify:final-release -- \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --public-key packaging/release-signing-public.pem \
  --git-head "$(git rev-parse refs/tags/v0.1.0^{commit})" \
  --release-evidence-dir .release-evidence/v0.1.0-published \
  --docs-hostname "$BUNNY_PULL_ZONE_HOSTNAME" \
  --docs-remote-prefix "$BUNNY_REMOTE_PREFIX" \
  --vm-evidence-root .vm/evidence \
  --support-matrix apps/docs/docs/guide/support-matrix.md
```

This wrapper runs the published-release verifier with the public evidence archive gate, the live docs smoke, strict
final release-evidence verification, every target-specific VM evidence verifier with installed-release smoke,
support-matrix verification with installed-release smoke required for `Verified` rows, read-only DSP provider plan
evidence, and the docs contract. Use `--dry-run` first to print the exact command plan without touching network,
release assets, docs URLs, or VM evidence. Add `--plan-output dist/release/final-release-proof-plan.txt` to dry-run
mode when you need a durable handoff artifact for release review or CI logs. Plan output paths must stay under
`dist/release/`; the verifier rejects absolute paths and `.` or `..` traversal before writing the file. The dry-run
handoff also prints the `pnpm vm:prepare-release-evidence` command plan, including the VM evidence archive packaging
step, signed `SHA256SUMS` refresh, signed-checksum verification, and matching `gh release upload --clobber` command,
so the operator can attach `loopwire-vm-evidence-<tag>.tar.gz` before running the manual final proof workflow.

The manual final release proof workflow defaults to `loopwire-release-evidence-<tag>.tar.gz` and
`loopwire-vm-evidence-<tag>.tar.gz`. If custom asset inputs are supplied, they are validated with
`scripts/validate-release-asset-name.sh` before `gh release download`: names must be basename-only `.tar.gz` assets,
must match the selected release tag and evidence kind, and must not contain traversal, URL syntax, or glob
metacharacters.

To render the complete no-side-effect operator handoff before dispatching workflows:

```bash
pnpm release:handoff -- \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --git-head "$(git rev-parse HEAD)" \
  --docs-hostname "$BUNNY_PULL_ZONE_HOSTNAME" \
  --docs-remote-prefix "$BUNNY_REMOTE_PREFIX" \
  --release-private-key-file /secure/loopwire-release-private.pem
```

The handoff prints the required secret check, strict release readiness command, Release workflow dispatch, Deploy Docs
workflow dispatch, VM SSH plan/runbook/evidence commands, VM evidence asset preparation command, final proof workflow
dispatch, and local final-proof dry-run. It does not set secrets, create tags, dispatch workflows, upload VM evidence,
or mutate host audio. If the Deploy Docs run id is not known yet, the final proof command includes
`<docs-deployment-run-id>` and prints a blocker reminder.

To audit the current final-release state from one read-only command:

```bash
pnpm release:status -- \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --git-head "$(git rev-parse refs/tags/v0.1.0^{commit})"
```

The status command checks required GitHub secrets, the GitHub Release object and required release assets, completed
successful Deploy Docs and Final Release Proof workflow runs, published-release-bound VM evidence, support-matrix
claims, and the local handoff plan. It exits nonzero until every final proof surface is present. Draft releases,
prereleases, mismatched release tags, and releases missing canonical tarballs, signed checksums, release evidence, or
VM evidence archives are blockers. Empty, failed, cancelled, or still-running workflow lists are release blockers, even
when the GitHub API call itself succeeds. The workflow run `headSha` must match `--git-head`, which defaults to the
current checkout when omitted, so a successful docs or proof run for an older commit cannot satisfy final status. Use
`--secret-list-file release-secret-names.tsv` to replay a saved names-only secret audit, or `--skip-gh` when you only
want local evidence checks.

Parse an existing release-readiness log without rerunning release checks:

```bash
pnpm collect:evidence -- --summarize-release-readiness-log release-readiness-publish-preflight.log
```

For user-facing bug reports and compatibility triage, collect the smaller redacted support bundle instead:

```bash
pnpm collect:support -- --output-dir .support/$(date +%Y%m%d-%H%M%S) --profile quick
```

Use `--profile full` when the maintainer also needs `pnpm check` and Tauri shell verification logs. The support bundle
writes `support-bundle.json`, `command-results.tsv`, `notes.md`, backend detection, host diagnostics, and autostart
status. The manifest also summarizes `detect-audio.json` as `audio.backends`, including availability, route-control
scope, per-edge gain/mute flags, diagnostics, and known gaps. When `--configuration` or `--state-file` is provided, it
also writes `jack-port-requirements.json` and summarizes read-only JACK readiness as `jack` in the manifest, including
matched and missing ports for each requirement. It never uploads data automatically.

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
  --public-key packaging/release-signing-public.pem \
  --require-release-evidence
```

The script downloads release assets with `gh`, requires the `x86_64` and `aarch64` canonical tarballs, verifies the
signed manifest and checksum entries, optionally requires `loopwire-release-evidence-<tag>.tar.gz` to be listed in the
signed `SHA256SUMS` manifest, verifies that evidence archive against the expected `release.tag` and repository,
public key, rejects unsafe archive paths before extraction, rejects link members before extraction, rejects unsafe
manifest command log paths during evidence verification, installs from the downloaded asset directory, and runs the
installed binary. This must pass before docs or package templates claim a public release is installable.
When local `--release-dir` verification omits `--tag`, the verifier derives the expected tag from the single evidence
archive filename and rejects any mismatch with `release-evidence.json`.

## Artifact Contract

The curl installer and binary package templates expect these files in each GitHub Release:

- `loopwire-linux-x86_64.tar.gz`
- `loopwire-linux-aarch64.tar.gz`
- `SHA256SUMS`
- `SHA256SUMS.sig`
- `loopwire-release-evidence-<tag>.tar.gz` for completed tag releases

Tauri bundle outputs for AppImage, deb, and rpm are release attachments too, but package managers should still anchor on
the canonical tarballs unless a channel-specific package requires a native format.

The public docs asset `apps/docs/docs/public/install.sh` is kept byte-for-byte synchronized with `scripts/install.sh`.
That makes `https://loopwire.app/install.sh` deployable through the VitePress/Bunny.net docs pipeline without creating a
second installer contract. Do not advertise the curl command as live until the published release verifier passes against
signed GitHub Release assets.

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

`.github/workflows/release.yml` runs on `v*` tag pushes or manual dispatch with an existing `v`-prefixed semver tag. The
workflow:

1. Resolves the release tag from the push ref or manual input, rejects non-semver or path-like tag names, and checks
   out that tag in detached mode before any build or publish work.
2. Builds Linux artifacts through a matrix for `x86_64` on `ubuntu-22.04` and `aarch64` on `ubuntu-22.04-arm`.
3. Uses Ubuntu 22.04-family runners so Linux builds keep an older supported glibc baseline.
4. Installs the current Tauri v2 Linux prerequisites, including WebKitGTK 4.1 development packages.
5. Runs `pnpm check`, including `pnpm verify:tauri`, on each architecture.
6. Builds Tauri Linux bundles on each architecture.
7. Requires versioned release notes for the tag, checks the tag points at the detached checkout, and rejects
   release-candidate/not-published wording.
8. Stages architecture-specific release attachments with `scripts/stage-release-artifacts.sh`.
9. Installs each generated architecture tarball from its local release directory with signature verification.
10. Uploads the architecture artifacts to the publish job.
11. Regenerates one combined `SHA256SUMS` and `SHA256SUMS.sig` covering every staged release attachment.
12. Installs the generated host tarball from the combined local release directory with signature verification.
13. Creates or updates the GitHub Release with the generated artifacts and versioned release notes.
14. Downloads the published GitHub Release assets and runs a post-publish installer smoke.
15. Collects and verifies published-release evidence.
16. Regenerates and re-signs `SHA256SUMS` so `loopwire-release-evidence-<tag>.tar.gz` is part of the signed manifest.
17. Uploads the evidence archive plus updated `SHA256SUMS` and `SHA256SUMS.sig`, then verifies the published release
    with `--require-release-evidence`.

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

The preflight does not publish. It requires a v-prefixed semver release tag without path separators, checks versioned
release notes, rejects release-candidate/not-published wording, verifies that the public docs `/install.sh` asset
matches the canonical installer, verifies that `pnpm verify:docs-deployment` is present and wired into the docs deploy
workflow, verifies that `pnpm verify:final-release`, `pnpm vm:package-evidence`, and the final release proof workflow
are wired, validates the signing public key, requires a clean git checkout, checks that the local or remote tag resolves
to the current checkout commit, verifies repository access, and confirms required GitHub secrets for release and
Bunny.net docs deployment. Candidate evidence collection passes `--skip-clean-git` because it is allowed to record
in-progress source state without claiming final release readiness.

## Workflow Contract

```bash
pnpm verify:workflows
```

The workflow contract parser validates CI, continuous host diagnostics, docs deployment, release publication, and VM
matrix workflow files. It checks the release workflow still checks out the resolved tag before build/publish work,
keeps tag verification enabled in the release-readiness step, requires versioned notes, signing secrets, generated and
published install smokes, and confirms VM/support-matrix changes trigger VM matrix validation.

## Final Release Proof Workflow

After the GitHub Release exists, docs are deployed, and every VM target has operator-run evidence with installed-release
smoke, run the manual `Final Release Proof` workflow. It requires the release tag, expected tag commit, and either a
live docs base URL or Bunny pull-zone hostname. By default it downloads these release assets:

- `loopwire-release-evidence-<tag>.tar.gz`, produced by the release workflow.
- `loopwire-vm-evidence-<tag>.tar.gz`, produced by the operator after collecting all VM target bundles.

The VM evidence archive must contain either target directories at its root, `.vm/evidence/<target>` directories, or a
`vm-evidence/<target>` root. The workflow checks out the exact tag commit, downloads the signed `SHA256SUMS` manifest,
downloads both archives from the GitHub Release, verifies each archive is listed in the signed checksum manifest with
`scripts/verify-release-asset-checksum.sh`, validates both downloaded tarballs with `scripts/extract-safe-tar.sh`
before extraction, verifies live docs and `/install.sh`, runs `scripts/verify-final-release-proof.sh`, requires every
VM target bundle to include published-release smoke, verifies support-matrix promotion rules, and reruns
`pnpm verify:docs`. The composed `scripts/verify-final-release-proof.sh` step must not pass `--release-dir`; by this
stage all release proof comes from GitHub Release downloads, signed checksum verification, live docs evidence, and
operator-collected VM evidence.

After collecting and verifying every VM target bundle, create the archive for the GitHub Release:

```bash
pnpm vm:package-evidence -- \
  --tag v0.1.0 \
  --evidence-root .vm/evidence \
  --all \
  --require-published-release \
  --output dist/release/loopwire-vm-evidence-v0.1.0.tar.gz
```

The packager re-runs
`scripts/verify-vm-evidence.sh --require-published-release --release-tag <tag> --require-github-release-source` for
each selected target before writing `vm-evidence/<target>` entries into the archive. The final proof also runs
`scripts/verify-published-release.sh --require-github-release-source`, so a local `--release-dir` smoke cannot satisfy
public release proof. Each VM bundle must include `published-release.json` matching the release tag and GitHub release
source, in addition to a successful `published-release-smoke` ledger row.
After writing, it validates the archive with
`scripts/extract-safe-tar.sh` so unsafe paths or link members are caught before the tarball is attached to a release.
Prepare the archive as a signed release asset with the release private key:

```bash
pnpm vm:prepare-release-evidence -- \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --release-dir dist/release \
  --private-key "$LOOPWIRE_RELEASE_PRIVATE_KEY_FILE" \
  --public-key packaging/release-signing-public.pem \
  --evidence-root .vm/evidence \
  --all
```

The helper reruns the packager, regenerates and re-signs `SHA256SUMS`, verifies
`loopwire-vm-evidence-<tag>.tar.gz` with `scripts/verify-release-asset-checksum.sh`, and prints the exact
`gh release upload --clobber` command for the archive plus refreshed manifest files. Final proof can then prove the VM
evidence archive is a signed release asset before extraction.

This workflow is intentionally `workflow_dispatch` only. It should fail until the public release, live Bunny.net docs,
release evidence archive, and VM evidence archive all exist.

## Signing Key Setup

Release signing uses OpenSSL to sign `SHA256SUMS`, not each artifact independently. Generate the key outside the repo,
commit only the public key, and store the private key as a GitHub secret:

```bash
pnpm release:prepare-key -- \
  --private-key-out /secure/loopwire-release-private.pem \
  --public-key-out packaging/release-signing-public.pem
bash scripts/setup-github-secrets.sh \
  --repo sandwichfarm/loopwire \
  --release-private-key-file /secure/loopwire-release-private.pem \
  --release-public-key-file packaging/release-signing-public.pem
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
bash scripts/setup-github-secrets.sh --repo sandwichfarm/loopwire --check --scope deploy
bash scripts/setup-github-secrets.sh \
  --repo sandwichfarm/loopwire \
  --check \
  --secret-list-file release-secret-names.tsv
bash scripts/setup-github-secrets.sh \
  --repo sandwichfarm/loopwire \
  --storage-zone loopwire-docs \
  --access-key "$BUNNY_ACCESS_KEY" \
  --pull-zone-hostname docs.example.test \
  --release-private-key-file /secure/loopwire-release-private.pem \
  --release-public-key-file packaging/release-signing-public.pem \
  --dry-run
```

`--check` reads secret names only. The default `--scope final` checks all final-proof secrets. Use
`--check --scope deploy` to verify only the Bunny.net upload pair before the final release-signing and live-docs
secrets are available. `--secret-list-file` accepts saved `gh secret list` output for deterministic release rehearsal;
the artifact may contain secret names and metadata columns, but never secret values. `--dry-run` validates inputs and
prints secret names that would be set without printing secret values or writing to GitHub. When
`--release-public-key-file` is supplied, the helper parses the private key, parses the public key, derives the public
key from the private key, and fails before any secret write if the pair does not match. If the GitHub CLI cannot read
repository secret names, `--check` and the release readiness preflight fail with the underlying `gh secret list` error
instead of reporting those secrets as missing.
When required secrets are missing, `--check` prints next-step commands with placeholders rather than values. If
only Bunny.net storage or live-docs secrets are missing, it prints only the Bunny setup command; if only
`LOOPWIRE_RELEASE_PRIVATE_KEY` is missing, it prints only the release signing command. `BUNNY_PULL_ZONE_HOSTNAME` is
required for final proof because the docs deployment must run post-upload live smoke against the served pull-zone URL.
If storage credentials are already configured and only the hostname is missing, set it without re-entering storage
credentials:

```bash
bash scripts/setup-github-secrets.sh \
  --repo sandwichfarm/loopwire \
  --pull-zone-hostname docs.example.test
```

The helper rejects Bunny values that would fail deployment: storage zones cannot contain slashes, storage endpoints
cannot contain newlines, pull-zone hostnames must be hostnames rather than URLs or paths, and remote prefixes cannot
contain `.` or `..` path segments.

`pnpm verify:release-readiness` also prints no-value next steps for the remaining blocker classes. With Bunny secrets
missing it points back to `scripts/setup-github-secrets.sh`; with the release tag missing it prints the guarded
`git tag -a <tag> -m "Loopwire <tag>"` and `git push origin <tag>` commands, explicitly after required secrets are
configured and readiness passes.

## Boundaries

- The workflow now has a dedicated `ubuntu-22.04-arm` AArch64 lane, but public AArch64 proof still requires a tagged
  workflow run and published `loopwire-linux-aarch64.tar.gz` asset.
- Package templates must not be published until a tagged release has real checksums and package-build smoke evidence
  against those published artifacts.
- `packaging/release-signing-public.pem` contains the project release public key, and the live `sandwichfarm/loopwire`
  repository has the matching `LOOPWIRE_RELEASE_PRIVATE_KEY` secret. Public installer claims still require Bunny
  deployment secrets plus a tagged release workflow run.
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
zone is not in Bunny's default region. `BUNNY_REMOTE_PREFIX` can deploy the site under a path inside the storage zone,
which is useful when one zone serves multiple preview or product directories. The helper rejects unsafe `.` or `..`
remote-prefix segments before upload planning.

Preview the upload plan without contacting Bunny.net:

```bash
pnpm build:docs
bash scripts/deploy-docs-bunny.sh \
  --dist apps/docs/docs/.vitepress/dist \
  --storage-zone loopwire-docs \
  --storage-endpoint ny.storage.bunnycdn.com \
  --remote-prefix loopwire \
  --deployment-manifest dist/docs-deployment/deployment-manifest.json \
  --dry-run
```

The deploy helper fails closed if the built dist omits `index.html` or `install.sh`; the dry-run should include
`install.sh`, which is the public curl installer endpoint once the docs site is deployed. When a deployment manifest is
requested, the helper writes a non-secret `loopwire.docs-deployment.v1` JSON file listing the deployed relative paths,
remote paths, SHA-256 checksums, storage endpoint, storage zone, remote prefix, dry-run/live mode, source git head, and
file count. The docs workflow verifies the manifest with `pnpm verify:docs-deployment` before uploading it as the
`loopwire-docs-deployment` artifact after a Bunny.net deploy. The verifier compares the manifest to the built dist file
inventory, rejects checksum drift, checks the remote-prefix mapping, rejects source git head drift, and rejects
secret-like manifest keys.
When `BUNNY_PULL_ZONE_HOSTNAME` is configured, the deploy workflow also runs
`scripts/verify-docs-live.sh --hostname "$BUNNY_PULL_ZONE_HOSTNAME" --remote-prefix "$BUNNY_REMOTE_PREFIX"` after
upload. That smoke fetches the deployed homepage and `/install.sh` from the same pull-zone prefix used for upload,
checks the installer parses as shell, and compares it with the local public installer.

Final release proof must be tied to the same deployment run. Pass the deploy-docs workflow run id that uploaded
`loopwire-docs-deployment`; the proof workflow downloads that artifact, rebuilds docs from the release commit, and
verifies `deployment-manifest.json` against the rebuilt VitePress dist and the requested release git head before
accepting the live-docs smoke:

```bash
gh workflow run final-release-proof.yml \
  --repo sandwichfarm/loopwire \
  -f tag=v0.1.0 \
  -f git_head=<release-tag-commit-sha> \
  -f docs_deployment_run_id=<deploy-docs-run-id>
```

If `docs_base_url` is omitted, the workflow uses the required `BUNNY_PULL_ZONE_HOSTNAME` repository secret. If
`docs_remote_prefix` is omitted, it uses `BUNNY_REMOTE_PREFIX` when that optional secret exists. Pass `docs_hostname`
or `docs_remote_prefix` only to override the stored Bunny pull-zone target for a specific proof run.

The GitHub secret helper can set or audit the deployment secrets:

```bash
bash scripts/setup-github-secrets.sh \
  --repo sandwichfarm/loopwire \
  --storage-zone loopwire-docs \
  --access-key "$BUNNY_ACCESS_KEY" \
  --pull-zone-hostname docs.example.test \
  --storage-endpoint ny.storage.bunnycdn.com \
  --remote-prefix loopwire \
  --dry-run
```
