<script setup>
import config from '../../../../packaging/repositories/apt-channel.json';
import { verifiedAptChannel } from '../../../site/src/lib/aptChannel.mjs';
const channel = verifiedAptChannel(config);
const setupCommand = channel ? `sudo bash setup-apt-repository.sh --base-url '${channel.baseUrl}' --fingerprint ${channel.signingFingerprint}` : '';
</script>

# APT repository

Loopwire's APT channel targets **Ubuntu 24.04 and Debian 13 on x86_64 (`amd64`)**. It is a project repository that
requires one-time setup; Loopwire is not included in either distribution's default repositories. Other releases,
derivatives, and ARM64 should use the matching options in the [installation guide](./install.md).

<div v-if="!channel" class="warning custom-block">
  <p class="custom-block-title">Public channel pending</p>
  <p>The repository tooling is available in the source tree. A public repository URL and signing key have not been activated.
  Use the <a href="./install.html#ubuntu-24-04">Ubuntu</a> or <a href="./install.html#debian-13">Debian</a> signed direct
  downloads, or the automatic installer. The setup command will appear here after public verification.</p>
</div>

<div v-else class="tip custom-block">
  <p class="custom-block-title">Verified public channel</p>
  <p>Repository: <code>{{ channel.baseUrl }}</code><br />
  OpenPGP fingerprint: <code>{{ channel.signingFingerprint }}</code><br />
  <a :href="channel.proofUrl">Public verification record</a>, recorded {{ channel.verifiedAt }}.</p>
</div>

## One-time setup

The following procedure applies once this page displays a verified public channel. You need Bash, curl, GnuPG,
Python 3, and `dpkg`, plus sudo access to configure APT. Download and inspect the small setup helper first:

```bash
curl -fsSLo setup-apt-repository.sh \
  https://raw.githubusercontent.com/sandwichfarm/loopwire/master/scripts/setup-apt-repository.sh
less setup-apt-repository.sh
```

<div v-if="channel">
  <p>Run the helper with the published URL and full signing fingerprint:</p>
  <pre><code>{{ setupCommand }}</code></pre>
</div>

The helper detects the exact distribution version and architecture, downloads the repository's OpenPGP key over
HTTPS, and checks its full fingerprint before making changes. It writes only the Loopwire source and scoped
keyring. An existing unrelated source with the same filename is an error; other APT sources are preserved.
Add `--dry-run` and omit `sudo` to preview the selected suite and paths without downloads or changes.

After successful setup, refresh package metadata and install:

```bash
sudo apt update &&
sudo apt install loopwire
```

The setup helper does not run either command for you. Confirm `apt update` succeeds for the Loopwire source before
installing. `apt-cache policy loopwire` shows the candidate version and repository URL; the URL should match the
verified channel above. The package includes the desktop application and background/provider commands, without
enabling startup services or applying audio routes during installation.

## Updates and reinstall

APT can update Loopwire alongside your other packages. To update only Loopwire:

```bash
sudo apt update &&
sudo apt install --only-upgrade loopwire
```

To repair package-owned files at the installed version, first find the exact version with
`dpkg-query -W -f='${Version}\n' loopwire`, then run `sudo apt install --reinstall loopwire=VERSION` with that value.
Saved routing configurations are outside package ownership and are preserved.

## Earlier versions

Use `apt-cache policy loopwire` to inspect available versions. Repository rollback changes the recommended package
set, but APT will not automatically downgrade a newer installed version. If a maintainer recommends rollback,
replace `VERSION` with the exact distro-specific version and opt into it:

```bash
sudo apt update &&
sudo apt-get install --allow-downgrades loopwire=VERSION
```

Keep the distro suffix: an Ubuntu package is not interchangeable with the Debian package. Older downloads are
retained for recovery; the active package index determines which versions APT can select. Ask for recovery guidance
if the required version is absent, rather than bypassing package authentication.

## Remove Loopwire or the repository

Uninstall the application with `sudo apt remove loopwire`. APT removes package-owned files and leaves your saved
configuration intact. Remove any startup integration you explicitly enabled using the
[start-on-boot guide](./start-on-boot.md).

To stop receiving Loopwire repository updates, use the same inspected helper:

```bash
sudo bash setup-apt-repository.sh --remove &&
sudo apt update
```

This removes the managed `loopwire.sources` file and its referenced Loopwire keyring. It does not uninstall Loopwire
or affect other repositories. Manually provisioned source files require manual removal of the matching source and
keyring. Do not remove shared distro keyrings.

## Trust and troubleshooting

APT checks signed repository metadata, which binds package indexes and their package checksums. The repository
OpenPGP key is separate from the OpenSSL key used to verify direct GitHub Release downloads. The setup uses a
per-source `Signed-By` keyring; it does not grant Loopwire's key authority over other repositories.

- **Wrong or changed fingerprint:** stop and compare this page's fingerprint with the project's announced key
  change. Rerun the inspected setup helper with the new full fingerprint only after that change is confirmed.
- **Expired metadata:** check the system clock, retry `sudo apt update`, and report the error if it persists.
  Repository metadata expires after 30 days and should be refreshed by the project before then.
- **Invalid signature, checksum mismatch, or missing file:** stop the install, retry metadata refresh, and report
  the failing URL and APT error. Do not disable authentication, TLS validation, or expiry checks.
- **Unsupported distribution or architecture:** use the [installation guide](./install.md). Changing a suite name
  to force a different distro package does not make that package compatible.

Diagnostics need the distro version, architecture, `apt-cache policy loopwire`, and the APT error text. Redact local
usernames and private URLs; never include audio recordings or private keys.
