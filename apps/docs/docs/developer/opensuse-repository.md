# Signed openSUSE repository operations

This runbook is for maintainers publishing and recovering Loopwire's third-party Tumbleweed channel. Development
tooling and isolated guest evidence do not establish production availability. Provisioning the origin, signing key,
protected environment, first public publication, and reviewed activation remain human operations. The checked-in
channel stays `pending` until that public proof exists; signed direct downloads remain available.

## Scope and provider decision

The only initial target is **openSUSE Tumbleweed x86_64**. Its canonical repository URL ends in
`/opensuse/tumbleweed/x86_64`. The command-line target selector is `opensuse-tumbleweed-x86_64`; the public channel
record uses `target: "opensuse-tumbleweed"`. Leap and ARM64 need separate package and clean-guest validation.

The project selected project-owned hosting after comparing it with Open Build Service (OBS):

OBS separates build, signing, and publishing services; an integration would need to track that provider workflow and
its output identity. See the [official OBS architecture](https://openbuildservice.org/help/manuals/obs-user-guide/cha-obs-architecture).

| Requirement | OBS | Project-owned repository |
| --- | --- | --- |
| Release identity | A provider build would need its own project, build, and exact-output provenance. | Authenticate the existing GitHub Release RPM and sign a staged copy; retain source and distributed hashes. |
| Signing and ownership | Provider project and signing operations require provisioned ownership and their own trust procedure. | A dedicated OpenPGP identity signs RPMs and metadata under the protected project environment. |
| Promotion and recovery | Requires a provider-specific publication/proof implementation. | Reuse verified SSH/POSIX publication, revision checks, immutable retention, and recovery journals. |
| Rolling compatibility | Provider build success alone would not prove the installed Loopwire lifecycle. | Require the recorded Tumbleweed snapshot and complete clean-guest install/upgrade/rollback proof. |

This is a project decision about the implemented proof and release flow, not a claim that OBS cannot host Loopwire.
No OBS project is provisioned or advertised by this change. Project-owned hosting preserves the authenticated release
payload and known publication contract at the cost of operating HTTPS, SSH access, signing recovery, monitoring, and
storage. Revisit OBS only with a separate provider integration and equivalent exact-output/client evidence.

## Trust, layout, and provisioning

The generator first verifies `SHA256SUMS.sig` using the existing OpenSSL release key, then the exact openSUSE RPM's
checksum and target identity. It signs only a staged copy with the repository OpenPGP key; the GitHub Release input
stays unchanged. The manifest records both hashes because adding an embedded RPM signature changes the distributed
bytes. Zypper must verify both signed `repodata/repomd.xml` and the RPM's embedded signature.

The public tree contains fingerprint-named keys, immutable RPMs, checksum-named metadata, `repomd.xml`, its detached
signature, and the repository manifest. Provision an HTTPS origin with a valid public certificate, Python 3, and
restricted SSH access. Keep staging and public files on one POSIX filesystem. Serve **`ROOT/public` only**. For this
target, public objects live below `ROOT/public/opensuse/tumbleweed/x86_64`, while private state and snapshots live below
`ROOT/channels/opensuse-tumbleweed-x86_64`. Fedora retains its separate namespace and state.

Do not expose locks, journals, snapshots, private keys, or SSH credentials to HTTP. Back up private state and snapshots.
Existing directory permissions must allow the HTTP service to traverse the public tree and its ancestors; the
publisher preserves pre-provisioned directory modes. The existing website upload surface does not establish the
required atomic rename and revision-check contract, so package publication uses SSH/POSIX hosting separately.

Mutable `repomd.xml`, its signature, the current manifest, and missing-object responses require `no-store` or mandatory
revalidation. RPMs, fingerprint-named public keys, and checksum-named metadata can have a one-year immutable cache
policy. Never cache a missing mutable file through a publication. Use the repository Nginx example as the starting
point and verify actual public headers.

Create a dedicated OpenPGP identity offline. Record the complete uppercase 40-character fingerprint, expiry,
custodian, backup, and revocation-certificate location. Keep recovery material outside CI and never send the private
key to the origin. Configure the protected GitHub environment **`packages-production`**:

| Kind | Name | Purpose |
| --- | --- | --- |
| Repository variable | `OPENSUSE_REPOSITORY_ENABLED` | Enables protected publication only after provisioning. |
| Variable | `OPENSUSE_REPOSITORY_URL` | Canonical HTTPS target URL ending in `/opensuse/tumbleweed/x86_64`. |
| Variable | `OPENSUSE_REPOSITORY_HOST` | Restricted SSH `USER@HOST`. |
| Variable | `OPENSUSE_REPOSITORY_ROOT` | Absolute private origin root, whose `public` child is served. |
| Variable | `OPENSUSE_SIGNING_FINGERPRINT` | Complete uppercase OpenPGP fingerprint. |
| Optional variable | `OPENSUSE_SSH_PORT` | SSH port, default 22. |
| Secret | `OPENSUSE_SSH_PRIVATE_KEY` | Restricted publishing identity. |
| Secret | `OPENSUSE_SSH_KNOWN_HOSTS` | Host-key pins obtained through a trusted channel. |
| Secret | `OPENSUSE_SIGNING_KEY` | ASCII-armored private signing export. |
| Optional secret | `OPENSUSE_SIGNING_PASSPHRASE` | Passphrase for that export. |

Restrict environment branches/tags to reviewed inputs and apply the environment's human approval policy. Keep the
enable variable false until every input is ready. Enabling writes does not activate the website. Monitor publication
and refresh failures, TLS/signing expiry, project verification deadlines, origin drift, and storage growth.

## Build, verify, and publish

Use a reviewed checkout and authenticated published stable release files. Set `RPM_FPR` to the full OpenPGP
fingerprint and `RPM_GNUPG_HOME` to its protected local GnuPG home. These are operator staging commands:

The input directory must contain the openSUSE RPM, `loopwire-linux-x86_64.tar.gz`, `release-assets.json`, `SHA256SUMS`,
and `SHA256SUMS.sig`. The signed asset manifest binds the release tag, full source commit, archive, and exact native
RPM hashes. Any other release assets present must also match that authenticated inventory. A checksum-only RPM
directory is insufficient for this target's source/build provenance checks.

```bash
python3 scripts/rpm-repository.py build --target opensuse-tumbleweed-x86_64 \
  --release-dir dist/release --version 0.1.0 --output dist/opensuse-repository \
  --signing-key "$RPM_FPR" --gnupg-home "$RPM_GNUPG_HOME" \
  --release-public-key packaging/release-signing-public.pem
python3 scripts/rpm-repository.py verify --target opensuse-tumbleweed-x86_64 \
  --repository dist/opensuse-repository --public-key rpm-public.asc --fingerprint "$RPM_FPR"
```

Local tools include Python 3, RPM/rpmsign, `createrepo_c`, GnuPG, and OpenSSL. Actual Zypper acceptance is a separate
matching-distribution test. `--previous DIR` retains older objects/packages. `--passphrase-file FILE` supplies a private
passphrase file. `--date EPOCH` controls reproducible fixtures; production uses current time. A 30-day signed project
verification deadline is enforced by Loopwire's verifier and publisher. Zypper does not enforce that custom tag, and
`autorefresh=1` is not an anti-replay guarantee. Refresh metadata before the deadline and monitor the origin.

Use **Publish openSUSE Repository** for protected production publication, refresh, and rollback. Tagged release
integration runs only after GitHub Release publication and when `OPENSUSE_REPOSITORY_ENABLED=true`. An openSUSE failure
does not retract the existing GitHub Release or mutate the Fedora/APT channel. Repair and retry the target job.

The publisher's `fetch`, `publish`, and `recover` operations require the explicit openSUSE selector. In these examples,
`RPM_ROOT` and `RPM_HOST` are the provisioned origin root/host, and `RPM_REVISION` is the verified current revision:

```bash
python3 scripts/publish-rpm-repository.py fetch --target opensuse-tumbleweed-x86_64 \
  --root "$RPM_ROOT" --output dist/opensuse-previous \
  --public-key rpm-public.asc --fingerprint "$RPM_FPR" \
  --ssh "$RPM_HOST" --identity-file rpm-ssh-key --known-hosts rpm-known-hosts
python3 scripts/publish-rpm-repository.py publish --target opensuse-tumbleweed-x86_64 \
  --repository dist/opensuse-repository --root "$RPM_ROOT" \
  --public-key rpm-public.asc --fingerprint "$RPM_FPR" --expected-revision "$RPM_REVISION" \
  --ssh "$RPM_HOST" --identity-file rpm-ssh-key --known-hosts rpm-known-hosts --dry-run
```

Initial publication skips fetch and uses an empty expected revision. For later publication, build using the fetched
snapshot as `--previous`, review the dry-run output, and repeat without `--dry-run`. Add `--ssh-port PORT` if needed.
A lock serializes this target's writers; compare-and-swap rejects a stale expected revision. Refetch and rebuild after
a conflict instead of overriding it. Immutable collisions are rejected.

Immutable objects are installed first. Promotion writes the new detached metadata signature and atomically replaces
`repomd.xml`. The pair is not a single filesystem operation: during the bounded signature/metadata mismatch a client
must fail verification and retry, never treat incomplete state as successful installation. Existing complete package
objects remain available. Require successful refresh, correct source/candidate selection, and a real authenticated
package install when checking Zypper behavior.

## Recovery, retention, and rollback

An interrupted promotion retains an exact recovery journal. Inspect and resume it with the same target, key, and SSH
arguments using `recover --dry-run`, then repeat without `--dry-run`. Fetch is blocked while recovery is pending.
For a journal whose project deadline has passed, `recover --allow-expired` is an explicit operator exception that
finishes only that authentic transition and requires immediate fetch, fresh signing, and publication. Ordinary
publication never accepts an expired candidate. Fetch can authenticate expired snapshots at their signed creation
time for recovery; that does not prove current client usability.

Version 1 retains immutable RPMs, key files, checksum-named metadata, and private snapshots indefinitely. There is no
automatic garbage collection. Any deletion policy needs a separate design for cached clients, manifest references,
rollback availability, and incident evidence. Do not edit generated state to bypass retention or revision checks.

Fetch a known-good snapshot with `fetch --revision SHA` and re-sign its package set with fresh metadata:

```bash
python3 scripts/rpm-repository.py rollback --target opensuse-tumbleweed-x86_64 \
  --repository dist/opensuse-known-good --output dist/opensuse-rollback \
  --signing-key "$RPM_FPR" --gnupg-home "$RPM_GNUPG_HOME"
```

Verify and publish against the current revision, then repeat public verification. Existing newer installations need
an explicit client downgrade: `sudo zypper install --oldpackage --no-allow-vendor-change --no-allow-arch-change --from loopwire 'loopwire=VERSION-RELEASE'`.
The [user guide](../guide/opensuse-repository.md#earlier-versions) covers exact-version selection and dependency errors.

## Key rotation and revocation

Generate a successor key offline and announce its full fingerprint through trusted project channels. The conservative
rotation path uses a fresh origin root/HTTPS prefix and authenticated release inputs signed by the successor. Test
clean setup, existing-client migration, install/reinstall/upgrade/downgrade, and removal before production. Clients
rerun the inspected bootstrap with the reviewed new URL and key; package updates do not silently grant a new signer
trust. Keep the old prefix during the announced migration period only while its key remains trustworthy.

Fingerprint-named public key objects are immutable. Extending expiry or changing subkeys changes bytes and cannot
overwrite the same URL; use the successor-key procedure. Old snapshots still require their original trust anchor.
The bootstrap removes only its managed files; keys accepted by RPM/libzypp require separate exact-identity review.

For compromise, disable publication/refresh, remove the private CI export, publish the revocation and incident notice,
and return the public channel record to pending. Clients must remove the old source and bootstrap an independently
verified replacement; a revocation certificate alone does not repair cached keyrings. Preserve incident evidence and
recover only from authenticated release inputs or independently known-good snapshots.

## Rolling snapshot policy

Record Tumbleweed's `/etc/os-release` `VERSION_ID`, the checksum-pinned guest image identity, package version, Zypper
and RPM versions, signer, repository origin/vendor, and source/distributed hashes in each proof. One passing snapshot
does not imply future rolling compatibility. Before widening a compatibility claim, repeat the complete lifecycle on
the intended newer snapshot using the same authenticated release inputs and a fresh isolated VM.

Use a reviewed target-manifest override through `LOOPWIRE_NATIVE_VM_TARGETS` for the newer official image and its
verified SHA-256. Use a distinct `LOOPWIRE_OPENSUSE_VM_ROOT` so old evidence is preserved. Run both `run-opensuse-repo`
and `verify-opensuse-repo` against the new snapshot; retain the manifest and logs with the evidence.

**A failed newer-snapshot run blocks activation.** If a public channel is already advertised, set its record to pending,
deploy the fallback instructions, and pause publication while investigating. File the exact failure and snapshot,
repair the package or explicitly narrow the compatibility declaration, then rerun the full clean-guest lifecycle.
Do not reclassify a failed mandatory check as a skip or reuse an older passing screenshot. Escalate unresolved
dependency, GUI, provider, signing, or vendor behavior before restoring an availability claim.

## Public verification and final activation

After publication, compare every production HTTPS byte against the signed candidate:

```bash
python3 scripts/verify-opensuse-public.py \
  --repository dist/opensuse-repository --public-key rpm-public.asc --fingerprint "$RPM_FPR" \
  --base-url "$OPENSUSE_URL" --proof-url "$OPENSUSE_PROOF_URL" --output dist/opensuse-channel.json
```

The checker must validate the local signed chain, HTTPS responses without redirects, exact hashes/sizes, and target
identity. Fixture CAs, synthetic upgrades, and local SSH rehearsals prove development behavior only.

The workflow artifact `loopwire-opensuse-publication-RUN_ID` contains the publication report, repository manifest, and
`opensuse-channel.json`. **Final activation is a human operation:** review that successful protected run and the
initial production clean-client lifecycle, including the actual snapshot, URL, signer, RPM provenance, and versions.
Copy the emitted record to `packaging/repositories/opensuse-channel.json` in a reviewed commit and deploy the website.
Do not set `status` alone or paste fixture proof into production configuration.

A verified schema-version-1 record requires the openSUSE target, HTTPS `baseUrl`, full uppercase fingerprint, lowercase
64-character `revision`, ISO `verifiedAt`, and project GitHub Actions `proofUrl`. Snapshot and package-hash evidence
live in the repository/VM proof manifests. Missing or invalid fields keep the existing signed direct-download command.
Only a complete reviewed record changes the openSUSE tab to `sudo zypper install loopwire` with a separate setup link.

## Development verification

Run shared RPM protocol/publication/public-proof tests, the openSUSE bootstrap/workflow checks, channel tests, docs,
and site/browser gates. Real Zypper tests must reject unsigned/changed metadata and RPMs, wrong signers, and incomplete
promotion. The clean KVM lifecycle uses:

```bash
bash scripts/native-package-vm.sh run-opensuse-repo \
  --target opensuse-tumbleweed --version 0.1.0 --release-dir dist/release
bash scripts/native-package-vm.sh verify-opensuse-repo --target opensuse-tumbleweed
node --test apps/site/src/lib/opensuseChannel.test.mjs
```

Require setup, install, reinstall, synthetic upgrade, explicit rollback/downgrade, package removal, and source removal,
with candidate/origin/vendor and signature evidence plus the installed GUI and provider checks. Synthetic revisions
reuse authenticated release payloads; they are not newly published application releases or public availability proof.
This lifecycle does not promote openSUSE desktop-session or live audio-backend support.
