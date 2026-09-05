<script setup>
import config from '../../../../packaging/repositories/fedora-channel.json';
import { verifiedFedoraChannel } from '../../../site/src/lib/rpmChannel.mjs';
const channel = verifiedFedoraChannel(config);
const setupCommand = channel ? `sudo bash setup-fedora-repository.sh --base-url '${channel.baseUrl}' --fingerprint ${channel.signingFingerprint}` : '';
const repoDefinition = channel ? `[loopwire]
name=Loopwire for Fedora 44 - $basearch
baseurl=${channel.baseUrl}
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-loopwire-${channel.signingFingerprint}
metadata_expire=6h
skip_if_unavailable=False` : '';
</script>

# Fedora repository

Loopwire's third-party Fedora repository targets **Fedora 44 on x86_64**. It requires one-time setup because Loopwire
is not included in Fedora's default repositories. Other Fedora releases and architectures should use the matching
option in the [installation guide](./install.md).

<div v-if="!channel" class="warning custom-block">
  <p class="custom-block-title">Public channel pending</p>
  <p>The repository implementation is available in the source tree, but its public URL and signing key have not been
  activated. Use the <a href="./install.html#fedora-44">signed Fedora direct download</a> or the automatic installer.
  The setup command will appear here only after the production repository passes public verification.</p>
</div>

<div v-else class="tip custom-block">
  <p class="custom-block-title">Verified public channel</p>
  <p>Repository: <code>{{ channel.baseUrl }}</code><br />
  OpenPGP fingerprint: <code>{{ channel.signingFingerprint }}</code><br />
  <a :href="channel.proofUrl">Public verification record</a>, recorded {{ channel.verifiedAt }}.</p>
</div>

## One-time setup

The following procedure applies once this page displays a verified public channel. You need Bash, curl, GnuPG, RPM,
DNF, and sudo access. Download and inspect the small setup helper first:

```bash
curl -fsSLo setup-fedora-repository.sh \
  https://raw.githubusercontent.com/sandwichfarm/loopwire/master/scripts/setup-fedora-repository.sh
less setup-fedora-repository.sh
```

<div v-if="channel">
  <p>Run the helper with the published URL and complete signing fingerprint:</p>
  <pre><code>{{ setupCommand }}</code></pre>
  <p>It writes an equivalent repository definition:</p>
  <pre><code>{{ repoDefinition }}</code></pre>
</div>

The helper accepts only Fedora 44 on x86_64. It downloads the OpenPGP public key over HTTPS, verifies the complete
fingerprint, and writes only `/etc/yum.repos.d/loopwire.repo` plus the fingerprint-named key under
`/etc/pki/rpm-gpg/`. Repeating setup with the same inputs is safe. An unrelated `loopwire.repo` or a symbolic link in
either managed path is an error; other DNF sources are preserved. Add `--dry-run` and omit `sudo` to preview the
target, URL, key fingerprint, and managed paths without downloads or changes.

The generated `.repo` file keeps `gpgcheck=1`, `repo_gpgcheck=1`, and `sslverify=1`. DNF verifies the RPM signature and the
detached signature on repository metadata. Do not add `--nogpgcheck`, disable either setting, or copy the local-RPM
signature exception from the direct-download path into this repository path.

After successful setup, refresh metadata and install:

```bash
sudo dnf makecache --refresh &&
sudo dnf install loopwire
```

The setup helper does not install Loopwire. Inspect `dnf repoquery --info --repo=loopwire loopwire` before installation
when you need to confirm the candidate version and repository. Fedora 44's DNF5 can exit successfully after reporting
a bad repository-metadata signature and excluding the source, so require an actual Loopwire package record and no GPG
verification error in the output. The package includes the desktop application and background/provider commands
without enabling startup services or applying audio routes during installation.

## Update and reinstall

DNF can update Loopwire with the rest of the system. To update only Loopwire:

```bash
sudo dnf upgrade --refresh loopwire
```

To repair files owned by the installed package without changing versions:

```bash
sudo dnf reinstall loopwire
```

Saved routing configurations are outside package ownership and are preserved.

## Earlier versions

List versions retained in the repository with `dnf --showduplicates list loopwire`. DNF does not automatically follow
a repository rollback to an older build. When maintainers recommend rollback, either select the next lower retained
version or name the exact Fedora package version:

```bash
sudo dnf downgrade loopwire
# Or replace VERSION-RELEASE with an exact retained value, such as 0.1.0-1.fc44:
sudo dnf install loopwire-VERSION-RELEASE.x86_64
```

Do not install an RPM built for another Fedora release or architecture. Ask for recovery guidance if the required
version is absent instead of disabling signature checks.

## Remove Loopwire or the repository

Uninstall the application with `sudo dnf remove loopwire`. DNF removes package-owned files and leaves saved Loopwire
configurations intact. Remove startup integration separately if you enabled it through the
[start-on-boot guide](./start-on-boot.md).

To stop receiving repository updates, use the same inspected helper:

```bash
sudo bash setup-fedora-repository.sh --remove &&
sudo dnf clean metadata
```

This removes only the managed Loopwire `.repo` file and its scoped public-key file. It does not uninstall Loopwire,
change Fedora's repositories, or remove keys already accepted into the RPM database. Without the `.repo` file, that
key no longer authorizes a Loopwire source. Manually provisioned definitions and keys require matching manual cleanup.

## Trust, key changes, and troubleshooting

The repository OpenPGP key signs the Fedora RPM and repository metadata. It is separate from the OpenSSL release key
that authenticates checksums for direct GitHub Release downloads. The scoped `.repo` configuration does not grant the
Loopwire key authority over other repositories.

`metadata_expire=6h` asks DNF to refetch metadata after six hours; it is a cache setting, not a signed expiry check.
DNF verifies that metadata was signed by the trusted key, but that signature alone cannot detect replay of older,
correctly signed metadata. Loopwire's publication verifier enforces a custom signed verification deadline and the
project monitors the HTTPS origin. Stop and report an unexpected version rollback rather than forcing installation.

- **Wrong or changed fingerprint:** stop and compare this page's fingerprint with the project's announced key change.
  Rerun the inspected helper only after the successor fingerprint is confirmed through a trusted project channel.
- **Revoked or compromised key:** disable or remove the repository immediately. Do not accept new metadata from that
  key. Follow the incident notice to verify and bootstrap a replacement repository explicitly.
- **Bad RPM or metadata signature:** stop the install, run `sudo dnf clean metadata`, retry a refresh, and report the
  exact DNF error. Do not disable `gpgcheck`, `repo_gpgcheck`, or TLS verification.
- **Stale or unavailable metadata:** run `sudo dnf clean metadata` and retry. `skip_if_unavailable=False` makes a
  missing or invalid Loopwire repository visible instead of silently continuing with stale assumptions.
- **Unsupported Fedora release or architecture:** use the [installation guide](./install.md). Editing `$releasever` or
  forcing another repository path does not make its package compatible.

Useful diagnostics are `rpm -E %fedora`, `uname -m`, `dnf repolist --enabled`,
`dnf repoquery --info --repo=loopwire loopwire`, and the DNF error text. Redact usernames and private URLs. Never send
private keys, environment variables, or audio recordings.
