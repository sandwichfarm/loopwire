# Signed APT repository operations

This runbook is for maintainers preparing, publishing, or recovering Loopwire's APT channel. Development of the
channel is separate from public activation. The checked-in channel record starts `pending`: provisioning the server,
signing identity, protected GitHub environment, and first public publication remain human operations. Keep the
existing direct-download instructions working until those operations and public verification are complete.

## Scope and trust boundary

The channel serves `main`/`amd64` in two independent suites: `ubuntu-24.04` and `debian-13`. It packages the existing
native release payload; no UI or audio-backend behavior belongs in this layer. Stable `X.Y.Z` versions, optionally
with `+build` metadata, are accepted. Prereleases and cross-distro substitutions are rejected.

Two signatures have different jobs:

1. The existing project **OpenSSL release key** authenticates `SHA256SUMS.sig` over `SHA256SUMS`. The generator checks
   the exact Ubuntu and Debian artifacts against that manifest and their internal package metadata before indexing.
2. A separate **OpenPGP APT key** signs the clear-signed `InRelease`. APT authenticates metadata and follows its SHA-256
   hashes through `Packages` to each deb. Clients trust that key only for the Loopwire source through `Signed-By`.

The web root contains public packages, indexes, signed release metadata, and public keys. Private signing material,
publication state, retained snapshots, locks, and transaction staging must never be served over HTTP.

## Human provisioning

Provision a project-owned HTTPS host with a valid public certificate and an SSH account restricted to the repository
storage root. The host needs Python 3 and POSIX filesystem semantics; GnuPG runs on the publishing runner. Put staging
and the public root on the same filesystem so rename is atomic. Serve **`ROOT/public` only**, disable directory
listing, and deny sibling `ROOT/snapshots` and publication state. Back up private snapshots and state independently.

The SSH approach is deliberate: the existing Bunny PUT upload surface does not establish an atomic replacement
contract for repository metadata. The ordinary website deployment remains separate.

Configure HTTP caching so clients cannot receive a new index behind stale release metadata:

- `InRelease`, `Release`, and ordinary `Packages`/compressed indexes: `Cache-Control: no-store` or
  equivalent mandatory revalidation.
- Content-addressed `by-hash` indexes and immutable package pool paths: long cache lifetime with `immutable`.
- Public keys and the current manifest: revalidate. Do not cache failures for paths that will soon be published.

Create a dedicated OpenPGP signing identity on a trusted machine. Record its complete 40-character fingerprint,
expiration, custodian, backup, and revocation-certificate location. Keep the offline recovery copy and revocation
certificate separate from CI secrets. Do not reuse the OpenSSL release key. Export an ASCII-armored public key for
verification and a private export solely for the protected publishing environment.

Configure the GitHub environment **`packages-production`**, restrict its permitted branches/tags to reviewed release
inputs, and apply its human approval policy. The workflow validates required configuration before remote writes.

| Kind | Name | Purpose |
| --- | --- | --- |
| Repository variable | `APT_REPOSITORY_ENABLED` | Set to `true` to call APT publication after a successful tagged GitHub Release publication. Leave disabled until provisioned. |
| Variable | `APT_REPOSITORY_URL` | Canonical public HTTPS URL, without credentials, query, or fragment. |
| Variable | `APT_REPOSITORY_HOST` | SSH `USER@HOST` for the publication account. |
| Variable | `APT_REPOSITORY_ROOT` | Absolute private storage root; HTTP serves its `public` child. |
| Variable | `APT_SIGNING_FINGERPRINT` | Full uppercase OpenPGP fingerprint. |
| Optional variable | `APT_SSH_PORT` | SSH port when not 22. |
| Secret | `APT_SSH_PRIVATE_KEY` | Restricted SSH identity for publication. |
| Secret | `APT_SSH_KNOWN_HOSTS` | Host-key pins obtained through a trusted channel. |
| Secret | `APT_SIGNING_KEY` | Dedicated ASCII-armored OpenPGP private signing key. |
| Optional secret | `APT_SIGNING_PASSPHRASE` | Passphrase for that private export. |

The enabled variable gates manual and scheduled runs as well as release-triggered publication. Leave it disabled
until all production inputs are ready; enabling it permits those workflows to write the repository. It does not
activate the public website's install commands.

Do not generate trusted SSH pins from an unauthenticated scan in the publishing job. Configure monitoring for failed
publication/refresh runs, certificate expiry, signing-key expiry, and metadata approaching its 30-day expiry.

## Build and verify a candidate

Use a reviewed checkout and a directory containing published stable GitHub Release artifacts, `SHA256SUMS`, and
`SHA256SUMS.sig`. Set `APT_FPR` to the full signing fingerprint and `APT_GNUPG_HOME` to a protected GnuPG home containing
that key. The following paths are operator-chosen local staging directories; never expose the GnuPG home to HTTP.
Local generation needs Python 3, `dpkg-deb`, `dpkg`, GnuPG (`gpg` and `gpgv`), and OpenSSL. The protected Ubuntu runner
provides these tools; other development hosts can use the pinned APT tools container described below.

```bash
python3 scripts/apt-repository.py build \
  --release-dir dist/release --version 0.1.0 --output dist/apt-candidate \
  --signing-key "$APT_FPR" --gnupg-home "$APT_GNUPG_HOME"
python3 scripts/apt-repository.py verify \
  --repository dist/apt-candidate --public-key apt-public.asc --fingerprint "$APT_FPR"
```

The default release verifier uses `packaging/release-signing-public.pem`; `--release-public-key FILE` selects an
explicit alternative for isolated fixtures. Production must retain the project trust anchor. Use `--previous DIR`
when advancing an existing repository so old pool objects and by-hash indexes remain available. Supply
`--passphrase-file FILE` when the signing key needs one; keep it private and delete temporary key material after use.

`--date EPOCH` and `--valid-for-days 30` control signed timestamps. Fixed dates are for reproducible fixtures; normal
publication uses fresh dates. The verifier accepts `--now EPOCH` for expiry tests. Never publish already expired
metadata or turn off client expiry checks.

## Publish, refresh, and recover

Prefer the protected **Publish APT Repository** workflow. It supports manual `publish`, `refresh`, and `rollback`,
and weekly refresh. Tagged release publication calls it only after the GitHub Release has been published and only
when `APT_REPOSITORY_ENABLED=true`. It downloads and checks published release inputs instead of trusting an arbitrary
local build directory. An APT failure does not undo the existing GitHub Release; repair it and retry the APT job.
For a manual run, use the default branch: choose `publish` with an existing stable `tag`, `refresh` with no release
input, or `rollback` with the retained 64-character `revision`. The weekly run selects refresh automatically.

For a reviewed local rehearsal, the same publisher can operate without SSH. For production, supply all SSH identity
and host-key arguments. In these examples `APT_ROOT`, `APT_HOST`, and `APT_REVISION` name the provisioned root, host, and
the current manifest revision. Set `APT_REVISION=empty` for an initial publication only.

```bash
python3 scripts/publish-package-repository.py fetch \
  --root "$APT_ROOT" --output dist/apt-previous \
  --public-key apt-public.asc --fingerprint "$APT_FPR" \
  --ssh "$APT_HOST" --identity-file apt-ssh-key --known-hosts apt-known-hosts
python3 scripts/publish-package-repository.py publish \
  --repository dist/apt-candidate --root "$APT_ROOT" \
  --public-key apt-public.asc --fingerprint "$APT_FPR" --expected-revision "$APT_REVISION" \
  --ssh "$APT_HOST" --identity-file apt-ssh-key --known-hosts apt-known-hosts --dry-run
```

Read the dry-run result, then repeat publication without `--dry-run`. Add `--ssh-port PORT` if needed. Initial
publication skips `fetch`; subsequent publication builds with the fetched repository as `--previous`. The expected
revision provides compare-and-swap protection: a conflicting publisher must refetch and rebuild, not force a stale
candidate over the current channel. A lock serializes publication on the server.
Take `APT_REVISION` from the verified `fetch` JSON result. Fetching an empty root exits with code 3; a pending
transaction blocks fetch until recovery. Private state files are diagnostics, not a replacement for verified fetch.
Fetch verifies snapshots at their original signed creation time so expired but authentic snapshots remain usable for
refresh and rollback. Successful fetch alone does not prove current client usability; publication and public
verification also require metadata that is valid now.

Immutable package and by-hash objects are installed first; existing paths with different content are rejected.
Each suite's `InRelease` rename is its commit point. Clients must see either the previous complete suite or the next
complete suite. Ubuntu and Debian may transition at different instants; there is no cross-suite atomicity claim.
Interrupted promotion retains recovery state. Recover using the pending candidate's key before retrying a failed
publication, then inspect the current revision and verify served metadata:

```bash
python3 scripts/publish-package-repository.py recover \
  --root "$APT_ROOT" --public-key apt-public.asc --fingerprint "$APT_FPR" \
  --ssh "$APT_HOST" --identity-file apt-ssh-key --known-hosts apt-known-hosts
```

Recovery verifies the pending snapshot at the current time before resuming its exact journal. If a transaction has
remained pending beyond metadata expiry, inspect it with `recover --allow-expired --dry-run`. The explicit
`--allow-expired` recovery option validates its signature and hash chain at its original signed creation time,
finishes only that journal, and returns `requiresRefresh: true`. Use it only for an operator-reviewed expired
transaction, then immediately fetch, re-sign, and publish fresh metadata. Clients still reject expired metadata;
the option does not disable APT expiry checks. The workflow does not apply this override automatically. Do not change
the clock or edit public files and transaction state by hand to bypass a conflict.

Refresh republishes the same package set with a new signed date and 30-day validity. It does not rebuild the
application or manufacture a new application release. Run it manually after missed schedules and verify both suites.
GitHub schedules can be delayed or disabled, so the weekly job is not the expiry monitor.

## Retention and rollback

Version 1 retains immutable package pool paths, by-hash indexes, and publication snapshots indefinitely. This keeps
old signed metadata and rollback references resolvable. There is no automatic garbage collection. Monitor storage
growth; a future deletion policy needs an explicit design covering metadata validity, cache lifetime, active clients,
and recovery retention before any objects are removed.

Select a known-good snapshot revision and fetch it using `fetch --revision SHA`. Rollback signs that snapshot's
package set with **fresh** metadata; copying old expired `InRelease` files is not a valid rollback:

```bash
python3 scripts/apt-repository.py rollback \
  --repository dist/apt-known-good --output dist/apt-rollback \
  --signing-key "$APT_FPR" --gnupg-home "$APT_GNUPG_HOME"
python3 scripts/apt-repository.py verify \
  --repository dist/apt-rollback --public-key apt-public.asc --fingerprint "$APT_FPR"
```

Publish the rollback candidate against the **current** revision, then run public verification. Previously installed
newer packages remain installed: clients must explicitly choose the distro-specific version with
`sudo apt-get install --allow-downgrades loopwire=VERSION`. Communicate that command and the reason for rollback;
the [user guide](../guide/apt-repository.md#earlier-versions) explains the client steps.

## Signing-key rotation and revocation

Treat a routine key change as a coordinated release operation. Generate the successor identity offline, publish its
full fingerprint through trusted project channels, and retain both keys' public material and historical snapshots.
Clients need the updated scoped keyring **before** they accept metadata signed only by the successor. The bootstrap
helper can replace its managed source with the newly verified key; ordinary package upgrades do not silently change
the trust anchor. Test the transition on both clean and existing-client guests, including rollback, before production.

The conservative version 1 rotation path uses a **new repository root and HTTPS prefix**. Build a fresh candidate
from authenticated release files under the successor key without `--previous`, publish and verify that prefix, then
update the protected environment and client setup to the new URL/fingerprint. Leave the old prefix and key available
for the announced migration window if the old key remains trustworthy. Existing clients rerun the helper to replace
their source. A fetched old snapshot still requires its old key; `build --previous` and `rollback` accept snapshots
signed by their current signer, so they cannot silently re-sign old-key history as a new trust identity.

The fingerprint-named public key file is immutable too: changing its expiry or subkeys changes its bytes and cannot
overwrite that URL in place. Use the reviewed successor-key procedure. Publishing itself can accept a new signer,
but that does not establish client trust or migrate old snapshots. The current single-key bootstrap provides no
unattended cross-signing or automatic rotation. Keep the public record `pending` during any unverified transition,
then review a new public verification record before reactivating instructions.

If the key is compromised, disable publication and refresh immediately, remove its private export from CI, publish
the revocation certificate and an incident notice through trusted channels, and take the affected channel out of
service. A revocation certificate alone does not update existing local keyrings. Direct clients to remove the old
managed source/keyring, inspect the announced replacement fingerprint, and bootstrap the replacement explicitly.
Verify package provenance independently before republishing with a new key; re-signing compromised content does not
repair it. Preserve private evidence and recover only from known-good snapshots or authenticated release inputs.

## Public verification and final activation

Local signing tests and isolated VM fixtures establish development behavior. They do not prove that users can reach
the production repository. After initial publication, verify the actual HTTPS-served bytes against the candidate:

```bash
python3 scripts/verify-apt-public.py \
  --repository dist/apt-candidate --public-key apt-public.asc --fingerprint "$APT_FPR" \
  --base-url "$APT_URL" --proof-url "$APT_PROOF_URL" --output dist/apt-channel.json
```

`APT_URL` is the canonical production URL and `APT_PROOF_URL` is that successful GitHub Actions run's URL. The checker
validates the local signed chain, fetches every manifest file over HTTPS without redirects, compares exact hashes and
sizes, and emits a verified record only on success. `--ca-file FILE` is for isolated HTTPS test CAs; it is not public
production proof. Do not create a production activation record from a fixture server or a synthetic package upgrade.

The workflow uploads `loopwire-apt-publication-RUN_ID` with `apt-channel.json`, `publication.json`, and
`repository-manifest.json`. **Final activation is a human operation:** inspect the successful run, review the URL,
signing fingerprint, revision, timestamp, and package versions, complete initial public clean-client installation
checks, then copy its `apt-channel.json` into `packaging/repositories/apt-channel.json` in a reviewed commit. Build and
deploy the website from that commit. Do not hand-edit `status` alone or place operator credentials in this file.

The schema is version 1. A pending record has null URL, fingerprint, revision, verification timestamp, and proof URL.
A verified record needs an HTTPS base URL, 40 uppercase hex fingerprint characters, a 64 lowercase hex revision,
an ISO timestamp, and the project GitHub Actions run URL. The homepage and user setup page validate every field;
missing or invalid data retains manual installation commands. On activation, Ubuntu and Debian tabs show
`sudo apt install loopwire` and link separately to one-time setup. Automatic, other distributions, and direct
download instructions remain available.

## Development evidence

Run generator, bootstrap, publisher, public-checker, and channel-gating tests, plus workflow, docs, and site checks.
For example, `bash scripts/with-apt-tools.sh --container python3 scripts/test-apt-repository.py` runs signing and real
APT checks inside the pinned Debian 13 tools image. The wrapper mounts the repository read-only and keeps test
temporary writes inside the container, without requiring a developer's host distro to install APT. It does not
replace the separate clean-guest lifecycle runs or their real GUI/provider evidence.
The package lifecycle harness has dedicated modes:

```bash
pnpm vm:native-packages -- run-apt --target ubuntu-24.04 --version 0.1.0 --release-dir dist/release
pnpm vm:native-packages -- run-apt --target debian-13 --version 0.1.0 --release-dir dist/release
pnpm vm:native-packages -- verify-apt --target ubuntu-24.04
pnpm vm:native-packages -- verify-apt --target debian-13
```

These boot fresh checksum-pinned distro guests, use HTTPS APT with scoped trust, and exercise package installation,
reinstall, upgrade, downgrade/rollback, and removal. The container regression suite separately proves rejection of
untrusted or broken repository state. Record exact
versions, source URLs, key fingerprint, candidate selection, signature results, GUI launch, and provider-command
checks. A synthetic `+aptfixture1` upgrade reuses the authenticated `0.1.0` payload to test lifecycle behavior; label
it as fixture evidence, never as a newly released application or public production proof. A package lifecycle pass
does not promote desktop-session or live audio-backend support claims.
