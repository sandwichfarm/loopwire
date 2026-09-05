# Signed Fedora repository operations

This runbook covers development, publication, and recovery for Loopwire's third-party Fedora channel. Tooling can be
tested without production access, but the checked-in channel record starts `pending`. Provisioning the origin and
signing identity, configuring the protected GitHub environment, completing the first public publication, and
reviewing its clean-client proof remain human operations. Keep the signed direct-download path available until those
steps are complete.

## Scope and provider decision

Version 1 serves one target: **Fedora 44, x86_64**, at a canonical HTTPS base such as
`https://HOST/fedora/44/x86_64`. It uses the existing Fedora package recipe and authenticated GitHub Release input;
no UI or audio-backend behavior belongs in this layer.

The project chose a project-owned repository after comparing it with COPR:

| Requirement | COPR | Project-owned repository |
| --- | --- | --- |
| Release artifact control | COPR builds provider output from submitted inputs; its RPM would need separate build-ID and exact-output proof. | The generator verifies the existing signed release manifest and exact Fedora RPM, then signs a staged copy without changing the GitHub Release. |
| Signing | Provider-managed package signing reduces private-key custody, but signed-metadata and stable-promotion behavior remain provider policy. | One dedicated project OpenPGP identity signs the distributed RPM and repository metadata under the protected environment. |
| Fedora target | COPR chroots can target supported Fedora releases, subject to service lifecycle. | The generator rejects every target except the tested Fedora 44 x86_64 contract. |
| Promotion and proof | Async build completion and repository visibility need provider-specific polling and build records. | A complete candidate is verified locally, published with compare-and-swap protection, and checked byte-for-byte over public HTTPS. |
| Retention and rollback | Build retention and project state depend on provider policy and configuration. | Immutable packages, keys, content metadata, and signed snapshots remain under project control; rollback republishes a retained package set with fresh metadata. |

Project-owned hosting gives release artifact control, atomic promotion, explicit retention, and the same local/CI proof
surface as the existing release flow. It also keeps Fedora-specific proof independent from any future openSUSE channel.
The tradeoff is operational responsibility for the HTTPS origin, SSH access, OpenPGP recovery, caching, monitoring,
and storage growth.

## Trust and repository layout

The generator verifies the existing OpenSSL signature on `SHA256SUMS` and the input RPM checksum before staging it.
It then signs or re-signs only the staged RPM with the dedicated repository OpenPGP key. The GitHub Release artifact
is never rewritten. DNF validates two related signatures:

1. `gpgcheck=1` validates the distributed RPM's embedded OpenPGP signature.
2. `repo_gpgcheck=1` validates `repodata/repomd.xml.asc`, which authenticates checksums for the retained metadata and
   package index.

The public target root contains:

```text
fedora/44/x86_64/
├── keys/FINGERPRINT.asc
├── packages/loopwire-VERSION-1.fc44.x86_64.rpm
├── repodata/repomd.xml
├── repodata/repomd.xml.asc
├── repodata/CHECKSUM-primary.xml.gz
└── repository-manifest.json
```

The manifest uses `loopwire.rpm-repository.v1` with schema version 1 and target
`{"distribution":"fedora","release":"44","architecture":"x86_64"}`. Its revision is the lowercase SHA-256 of the
canonical JSON excluding the `revision` field. It records the signing fingerprint, creation time, project verification
deadline, source/distributed RPM hashes, packages, and every public file. Do not hand-edit generated repository state.

## Human provisioning

Provision a project-owned HTTPS host with a valid public certificate and an SSH account restricted to the private
repository root. The host needs Python 3 and POSIX filesystem semantics. Put transaction staging and the public tree
on the same filesystem so `repomd.xml` replacement is atomic. Serve **`ROOT/public` only**; keep `ROOT/snapshots`,
`ROOT/state`, locks, incoming transactions, SSH identities, and private signing material outside the web root. Back up
private snapshots and state independently.

The project-owned SSH/POSIX origin is required because the existing website upload surface does not provide the
compare-and-swap, retention, or atomic metadata-pointer contract. The ordinary website deployment remains separate.
Configure caching by object role:

- `repodata/repomd.xml`, its detached signature, `repository-manifest.json`, and all HTTP 404 responses: `no-store` or
  mandatory revalidation.
- RPMs, public key files, and checksum-named metadata objects: a one-year immutable policy.
- Never cache an absent mutable object that a publication or recovery operation will create.

Create a dedicated OpenPGP identity offline. Record the full 40-character uppercase fingerprint, expiration,
custodian, encrypted backup, and revocation-certificate location. Keep recovery material outside CI. Do not reuse the
OpenSSL release key or export the private repository key to the origin.

Configure the GitHub environment **`packages-production`**, restrict it to reviewed release/default-branch inputs,
and apply its human approval policy. `.github/workflows/publish-fedora.yml` validates these settings before remote
writes:

| Kind | Name | Purpose |
| --- | --- | --- |
| Repository variable | `FEDORA_REPOSITORY_ENABLED` | Set to `true` only after provisioning to permit protected publication. |
| Variable | `FEDORA_REPOSITORY_URL` | Exact public HTTPS target URL ending in `/fedora/44/x86_64`, without credentials, query, or fragment. |
| Variable | `FEDORA_REPOSITORY_HOST` | Restricted SSH `USER@HOST` used by the publisher. |
| Variable | `FEDORA_REPOSITORY_ROOT` | Absolute private origin root; HTTP maps its `public` child as the document root. |
| Variable | `FEDORA_SIGNING_FINGERPRINT` | Complete 40-character uppercase OpenPGP fingerprint. |
| Optional variable | `FEDORA_SSH_PORT` | SSH port when it is not 22. |
| Secret | `FEDORA_SSH_PRIVATE_KEY` | Restricted SSH identity for publication. |
| Secret | `FEDORA_SSH_KNOWN_HOSTS` | Host-key pins obtained through a trusted channel. |
| Secret | `FEDORA_SIGNING_KEY` | Dedicated ASCII-armored OpenPGP private signing key. |
| Optional secret | `FEDORA_SIGNING_PASSPHRASE` | Passphrase for that private export. |

Leave the enable variable false until every production value, secret, and protection rule is ready. Enabling
publication permits protected repository writes; it does not activate the website's short DNF command. Do not
generate SSH host pins from an unauthenticated scan inside the publishing job. Monitor failed publications, origin
drift, TLS expiry, signing-key expiry, the project metadata verification deadline, and storage growth.

## Build and verify a candidate

Use a reviewed checkout plus a directory containing the published Fedora RPM, `SHA256SUMS`, and `SHA256SUMS.sig`.
`RPM_FPR` is the complete OpenPGP fingerprint and `RPM_GNUPG_HOME` is a protected GnuPG home containing its private
key. Local generation needs Python 3, RPM tools including `rpmsign`, `createrepo_c`, GnuPG, and OpenSSL.

```bash
python3 scripts/rpm-repository.py build \
  --release-dir dist/release --version 0.1.0 --output dist/rpm-repository \
  --signing-key "$RPM_FPR" --gnupg-home "$RPM_GNUPG_HOME" \
  --release-public-key packaging/release-signing-public.pem
python3 scripts/rpm-repository.py verify \
  --repository dist/rpm-repository \
  --public-key rpm-public.asc --fingerprint "$RPM_FPR"
```

The verifier rejects a missing or invalid RPM signature, wrong signer, changed RPM bytes, unsigned or changed
metadata, unexpected target/version/architecture, unlisted files, and a passed project verification deadline.
Production uses stable `X.Y.Z` versions and the project release trust anchor. `--release-public-key FILE` exists for
explicit fixture trust anchors; do not replace the production anchor with fixture material.

Use `--previous DIR` to retain objects and older packages from the current repository. `--passphrase-file FILE`
supports a protected signing-key passphrase. `--date EPOCH` is for deterministic fixtures; production uses current
time. The custom signed `loopwire-valid-until` deadline is 30 days by default, and `--valid-for-days` accepts only 1
through 90. Loopwire's verifier and publishing workflow enforce it; DNF does not understand this project tag or
provide APT-style signed `Valid-Until` enforcement. The public monitor must not rely on scheduled GitHub runs happening
exactly on time. DNF's client `metadata_expire=6h` setting only controls cache refresh frequency.

An explicit `--date` fixes createrepo timestamps plus RPM and metadata signature creation times. Byte-identical output
also depends on the pinned Fedora tool versions, identical key material, and a deterministic OpenPGP algorithm. When
`--previous` already contains the same version with the same authenticated source-release hash, the generator reuses
that signed RPM instead of manufacturing different signed bytes for an unchanged release input.

## Publish, fetch, and recover

Use the protected **Publish Fedora Repository** workflow for production publication, refresh, or rollback. Tagged
release integration must run only after GitHub Release publication succeeds and `FEDORA_REPOSITORY_ENABLED=true`.
The workflow downloads and verifies published release inputs rather than trusting an arbitrary runner directory. A
Fedora publication failure leaves the GitHub Release and previous repository revision intact; repair the failure and
retry this channel. Its weekly schedule refreshes signed metadata without inventing a new application release; delayed
or disabled schedules still require external expiry monitoring.

The publisher supports local rehearsal and SSH operation. For production, provide all SSH identity and host-key
arguments. Here `RPM_ROOT`, `RPM_HOST`, and `RPM_REVISION` refer to the provisioned private root, restricted SSH host,
and currently verified manifest revision. Use `empty` only for the first publication.

```bash
python3 scripts/publish-rpm-repository.py fetch \
  --root "$RPM_ROOT" --output dist/rpm-previous \
  --public-key rpm-public.asc --fingerprint "$RPM_FPR" \
  --ssh "$RPM_HOST" --identity-file rpm-ssh-key --known-hosts rpm-known-hosts
python3 scripts/publish-rpm-repository.py publish \
  --repository dist/rpm-repository --root "$RPM_ROOT" \
  --public-key rpm-public.asc --fingerprint "$RPM_FPR" --expected-revision "$RPM_REVISION" \
  --ssh "$RPM_HOST" --identity-file rpm-ssh-key --known-hosts rpm-known-hosts --dry-run
```

Read the dry-run result, then repeat without `--dry-run`. Add `--ssh-port PORT` when required. Take the current
revision from verified `fetch` output. A conflicting writer must fetch and rebuild against the latest revision; do not
force stale state over it. Server locking serializes publication and the operation is repeat-safe for an already
committed revision.

The publisher installs immutable RPM, key, and checksum-named metadata objects first. Existing immutable paths with
different bytes are rejected. It writes `repodata/repomd.xml.asc` before atomically replacing
`repodata/repomd.xml`, which is the metadata commit point. A client in the brief interval between those two writes may
see a signature/metadata mismatch and fail closed; it never accepts unauthenticated metadata. Retry after publication
completes. Fedora 44 DNF5 may report the bad signature, exclude the repository, and still return exit code 0 from
`dnf repoquery`; lifecycle and monitoring checks must reject the verification diagnostic and require the expected
Loopwire package result instead of trusting process status alone. A future protocol would need a versioned target URL
to eliminate even that fail-closed window.

An interrupted promotion preserves a recovery journal. Inspect and resume the exact pending revision:

```bash
python3 scripts/publish-rpm-repository.py recover \
  --root "$RPM_ROOT" --public-key rpm-public.asc --fingerprint "$RPM_FPR" \
  --ssh "$RPM_HOST" --identity-file rpm-ssh-key --known-hosts rpm-known-hosts --dry-run
```

Repeat without `--dry-run` after review. `--allow-expired` is limited to an operator-reviewed journal whose project
verification deadline passed: it can finish only that authenticated transition, then requires an immediate fetch,
fresh re-sign, and publication. It does not disable project verification for ordinary candidates. DNF signature checks
alone may accept replayed older correctly signed metadata, which is why immediate refresh plus HTTPS/origin monitoring
remain required. Never edit public metadata, snapshots, or state by hand to bypass a conflict.

## Retention and rollback

Version 1 retains RPMs, key files, checksum-named metadata, and signed snapshots indefinitely. There is no automatic
garbage collection. Monitor storage growth; any deletion policy needs a separate design covering cached clients,
manifest references, rollback availability, and incident evidence.

Fetch a retained revision with `fetch --revision SHA`. Project policy requires rollback to generate fresh signed
metadata for that known-good package set. Copying an old `repomd.xml` whose project verification deadline passed would
be replay, even though DNF may still accept its valid signature:

```bash
python3 scripts/rpm-repository.py rollback \
  --repository dist/rpm-known-good --output dist/rpm-rollback \
  --signing-key "$RPM_FPR" --gnupg-home "$RPM_GNUPG_HOME"
python3 scripts/rpm-repository.py verify \
  --repository dist/rpm-rollback --public-key rpm-public.asc --fingerprint "$RPM_FPR"
```

Publish the rollback candidate against the current revision and repeat public verification. Installed newer packages
do not downgrade automatically. Communicate either `sudo dnf downgrade loopwire` or the exact retained
`sudo dnf install loopwire-VERSION-RELEASE.x86_64` command; the
[user guide](../guide/fedora-repository.md#earlier-versions)
explains both choices.

## Key rotation and revocation

Treat routine key rotation as a coordinated release. Generate the successor offline, announce its complete
fingerprint through trusted channels, and test clean-client setup, existing-client migration, upgrade, reinstall, and
rollback. The conservative path uses a new HTTPS repository prefix signed only by the successor. Existing clients
rerun the setup helper with the reviewed new URL and fingerprint; package upgrades do not silently grant trust to a
new key. Keep the old prefix available during an announced migration window only while its key remains trustworthy.

The fingerprint-named public key object is immutable. Do not overwrite it after an expiration/subkey change. A
fetched old snapshot still requires its original key, and re-signing unverified historical bytes does not establish
their provenance.

For compromise, disable publication immediately, remove the private export from CI, publish the revocation and
incident notice through trusted channels, and mark `packaging/repositories/fedora-channel.json` pending. Existing
clients must remove the old repository/key file and bootstrap the reviewed replacement explicitly. Preserve evidence
and recover only from authenticated release inputs or known-good snapshots.

## Public verification and final activation

After publication, verify every production HTTPS byte against the signed local candidate:

```bash
python3 scripts/verify-rpm-public.py \
  --repository dist/rpm-repository --public-key rpm-public.asc --fingerprint "$RPM_FPR" \
  --base-url "$FEDORA_URL" --proof-url "$FEDORA_PROOF_URL" --output dist/fedora-channel.json
```

The checker validates the local trust chain, fetches the production repository over HTTPS without redirects, compares
exact hashes and sizes, and emits a verified record only on success. A fixture CA or synthetic upgrade is development
evidence, never production proof.

The workflow artifact `loopwire-fedora-publication-RUN_ID` contains `fedora-channel.json`, `publication.json`, and
`repository-manifest.json`. **Final activation is a human operation:** review the successful protected run, public
URL, target, signing fingerprint, revision, timestamp, and lifecycle evidence. Then copy the emitted channel record to
`packaging/repositories/fedora-channel.json` in a reviewed commit and deploy the website from that commit. Do not edit
`status` alone or place credentials in the channel file.

A verified version 1 record requires `target: "fedora-44"`, an HTTPS base URL, a 40-character uppercase fingerprint,
a 64-character lowercase revision, an ISO timestamp, and a project GitHub Actions run URL. Missing or malformed data
keeps the homepage on the signed direct-download command. A valid record changes only the Fedora tab to
`sudo dnf install loopwire` and a separate one-time setup link. Automatic installation and other platform options
remain available.

## Development and guest evidence

Run the generator, publisher, bootstrap, public-checker, channel-gate, workflow, documentation, and site tests. The
pinned Fedora tools image gives non-Fedora hosts the RPM toolchain without changing host package state:

```bash
bash scripts/with-rpm-tools.sh --container python3 scripts/test-rpm-repository.py
python3 scripts/test-fedora-bootstrap.py
python3 scripts/test-publish-rpm-repository.py
python3 scripts/test-rpm-public.py
node --test apps/site/src/lib/rpmChannel.test.mjs
```

Use the dedicated Fedora 44 guest lifecycle modes for stronger evidence:

```bash
bash scripts/native-package-vm.sh run-fedora-repo \
  --target fedora-44 --version 0.1.0 --release-dir dist/release
bash scripts/native-package-vm.sh verify-fedora-repo --target fedora-44
```

The clean, checksum-pinned guest must exercise repository setup, install, reinstall, synthetic upgrade, explicit
downgrade/rollback, removal, and repository removal. Record the target, repository origin, exact versions, package and
metadata signer, public URL, signature results, GUI/provider smokes, and command logs. Synthetic fixture releases
exercise lifecycle behavior with authenticated existing payloads; they do not create a public application release,
prove production reachability, or promote Fedora desktop/audio support.
