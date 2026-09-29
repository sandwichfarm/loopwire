<script setup>
import config from '../../../../packaging/repositories/opensuse-channel.json';
import { verifiedOpenSuseChannel } from '../../../site/src/lib/rpmChannel.mjs';
const channel = verifiedOpenSuseChannel(config);
const setupCommand = channel ? `sudo bash setup-opensuse-repository.sh --base-url '${channel.baseUrl}' --fingerprint ${channel.signingFingerprint}` : '';
</script>

# openSUSE repository

Loopwire's project-owned, third-party repository targets **openSUSE Tumbleweed on x86_64**. It requires one-time
setup; Loopwire is not supplied by the default openSUSE repositories through this channel. This is not an OBS project
or an openSUSE-maintained package. Leap and other architectures need their own validated packages; use the matching
option in the [installation guide](./install.md).

<div v-if="!channel" class="warning custom-block">
  <p class="custom-block-title">Public channel pending</p>
  <p>The repository implementation is available in the source tree, but its public URL and signing key have not been
  activated. Use the <a href="./install.html#opensuse-tumbleweed">signed openSUSE direct download</a> or the automatic
  installer. The setup command appears here only after production verification has been reviewed.</p>
</div>

<div v-else class="tip custom-block">
  <p class="custom-block-title">Verified public channel</p>
  <p>Repository: <code>{{ channel.baseUrl }}</code><br />
  OpenPGP fingerprint: <code>{{ channel.signingFingerprint }}</code><br />
  <a :href="channel.proofUrl">Public verification record</a>, recorded {{ channel.verifiedAt }}.</p>
</div>

## One-time setup

Use this procedure once the page displays a verified public channel. You need Bash, curl, Python 3, GnuPG, RPM,
Zypper, and sudo access. Download and inspect the setup helper first:

```bash
curl -fsSLo setup-opensuse-repository.sh \
  https://raw.githubusercontent.com/sandwichfarm/loopwire/master/scripts/setup-opensuse-repository.sh
less setup-opensuse-repository.sh
```

<div v-if="channel">
  <p>Run it with the verified URL and complete OpenPGP fingerprint:</p>
  <pre><code>{{ setupCommand }}</code></pre>
</div>

The helper accepts only Tumbleweed x86_64. It downloads the key over HTTPS and checks the complete fingerprint
**before** configuring the source or refreshing metadata. It writes `/etc/zypp/repos.d/loopwire.repo` and
`/etc/zypp/keys/loopwire-repository-FINGERPRINT.asc`. Repeating setup with the same inputs is safe; an unrelated
definition using that filename is an error. Other sources are preserved. Add `--dry-run` and omit `sudo` to preview
the target and managed paths without downloads or changes.

The repository alias is `loopwire`, its type is `rpm-md`, and `autorefresh=1` enables normal metadata refresh.
`gpgcheck=1`, `repo_gpgcheck=1`, and `pkg_gpgcheck=1` require signed metadata and signed RPMs. Priority stays at
`99`; setup does not change global solver settings or automatically switch package vendors.
The [libzypp configuration reference](https://manpages.opensuse.org/Tumbleweed/libzypp/zypp.conf.5.en.html) explains
these separate signature settings.

After successful setup, refresh the repository, compare any key prompt's full fingerprint with this page, and install:

```bash
sudo zypper refresh loopwire &&
sudo zypper install loopwire
```

The helper does not run either command for you or automatically accept a Zypper key prompt. Reject a mismatched
fingerprint. Confirm the candidate with `zypper info --repo loopwire loopwire` when needed. It must come from the
configured URL and match the expected package version and x86_64 architecture. Installation includes the desktop and
background/provider commands without enabling startup services or applying audio routes.

## Updates, reinstall, and vendor selection

To update only Loopwire after setup:

```bash
sudo zypper refresh loopwire &&
sudo zypper update loopwire
```

For normal distribution-wide Tumbleweed updates, follow openSUSE's system-upgrade procedure. Do not run a
distribution-wide vendor switch to install or update this one application.

Inspect installed identity and available versions before repairing or changing the package:

```bash
rpm -q --qf '%{NAME} %{VERSION}-%{RELEASE} %{ARCH} vendor=%{VENDOR}\n' loopwire
zypper search --details --repo loopwire --match-exact loopwire
```

To reinstall the same retained version, replace `VERSION-RELEASE` with the installed value:

```bash
sudo zypper install --force --no-allow-vendor-change --no-allow-arch-change \
  --from loopwire 'loopwire=VERSION-RELEASE'
```

Saved Loopwire configurations are outside package ownership and are preserved. The RPM vendor is a header field
carried from the authenticated release; it is separate from both repository origin and signing fingerprint. If an
existing package came from another vendor, review that change explicitly. Only when intentionally migrating that
package, use `sudo zypper install --allow-vendor-change --from loopwire loopwire`. Keep the normal global vendor
protection enabled. [libzypp vendor protection](https://opensuse.github.io/libzypp/pg_zypp-solv-vendorchange.html)
explains why switching repository URLs does not itself change a package's vendor.

## Earlier versions

Publishing an older recommended package set does not downgrade an installed newer version. After maintainers
recommend a rollback, choose the exact version listed by the search command above:

```bash
sudo zypper refresh loopwire &&
sudo zypper install --oldpackage --no-allow-vendor-change --no-allow-arch-change \
  --from loopwire 'loopwire=VERSION-RELEASE'
```

This permits a downgrade while preserving signature, dependency, vendor, and architecture checks. Do not substitute
a Fedora or Leap RPM. If dependency resolution fails on your Tumbleweed snapshot, stop and report it instead
of ignoring dependencies. See the [official Zypper reference](https://manpages.opensuse.org/Tumbleweed/zypper/zypper.8.en.html)
for exact-version installation and `--oldpackage` behavior.

## Remove the package or repository

Use `sudo zypper remove loopwire` to remove package-owned files while keeping saved configuration. Remove any startup
integration you enabled separately, using the [start-on-boot guide](./start-on-boot.md).

To stop using the repository, run the same inspected helper:

```bash
sudo bash setup-opensuse-repository.sh --remove
```

It removes the managed `.repo` file and its referenced Loopwire public-key file. It does not uninstall Loopwire,
alter other repositories, or erase keys already accepted into the RPM database or libzypp key cache. Inspect
`zypper repos --details` to confirm that alias `loopwire` is absent. Keys in shared databases need separate careful
cleanup by exact identity if required; do not remove a shared distro key or match only a short key ID.

## Tumbleweed compatibility and trust

Tumbleweed is rolling. A passing repository test proves the recorded snapshot and package set, not every future
snapshot. If a later snapshot fails installation, launch, provider checks, or the package lifecycle, maintainers must
withhold activation, publish the limitation, and repair the package or compatibility statement before rerunning the
complete clean-guest lifecycle. Report the `VERSION_ID` from `/etc/os-release`, exact package version, candidate
repository, and error output. [The compatibility policy](../developer/opensuse-repository.md#rolling-snapshot-policy)
describes that gate.

The OpenPGP repository key authenticates the distributed RPM and metadata. It is separate from the OpenSSL key that
authenticates direct GitHub Release checksums. The local-RPM `--allow-unsigned-rpm` exception belongs only to the
authenticated direct-download fallback; never add it or `--no-gpg-checks` to repository commands.

For a routine key change, verify the successor's full fingerprint through trusted project announcements before
rerunning setup with the new URL and fingerprint. For a compromised or revoked key, remove the repository immediately
and follow the incident notice. Publishing a revocation certificate does not update every existing client's key cache.

Zypper validates signatures, but a valid signature alone cannot distinguish replayed older metadata. Loopwire's
publication checks enforce a signed project verification deadline; client autorefresh does not enforce that custom
deadline. Report unexpected rollback, metadata-signature failures, checksum mismatches, or missing objects and retry
only after the repository is repaired. Do not disable TLS, signature, or dependency checks to continue.
