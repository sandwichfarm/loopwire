#!/usr/bin/env bash
# The unprivileged guest user owns proof logs; sudo applies only to package and trust-store commands.
# shellcheck disable=SC2024
set -euo pipefail

target="${1:?target is required}"
package_target="${2:?package target is required}"
format="${3:?format is required}"
version="${4:?version is required}"
git_head="${5:?git head is required}"
kit_dir="${6:-$PWD}"
[ "$target" = opensuse-tumbleweed ] || { echo "unsupported openSUSE repository guest target" >&2; exit 2; }
[ "$package_target" = opensuse-tumbleweed ] && [ "$format" = rpm ]
[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(\+[0-9A-Za-z]+(\.[0-9A-Za-z]+)*)?$ ]]
[[ "$git_head" =~ ^[0-9a-f]{40}$ ]]
cd "$kit_dir"

proof_dir="$kit_dir/proof"
fixture_dir="$kit_dir/opensuse-repository-fixture"
release_dir="$kit_dir/release"
public_release_proof="$proof_dir/public-release"
base_url="https://127.0.0.1:8445/opensuse/tumbleweed/x86_64"
upgrade_version="${version}+zypperfixture1"
[[ "$version" != *+* ]] || upgrade_version="${version}.zypperfixture1"
baseline_package_version="${version}-1"
upgrade_package_version="${upgrade_version}-1"
baseline_package="loopwire-${baseline_package_version}.x86_64.rpm"
upgrade_package="loopwire-${upgrade_package_version}.x86_64.rpm"
mkdir -p "$proof_dir/packages" "$proof_dir/repositories" "$public_release_proof" "$fixture_dir"
exec > >(tee "$proof_dir/commands.log") 2>&1
set -x

cat /etc/os-release >"$proof_dir/os-release"
uname -a >"$proof_dir/uname.txt"
systemd-detect-virt --vm >"$proof_dir/virtualization.txt"
grep -Eq '^(kvm|qemu)$' "$proof_dir/virtualization.txt"
if rpm -q loopwire >/dev/null 2>&1; then
  echo 'clean guest already has Loopwire installed' >&2
  exit 1
fi
printf 'absent\n' >"$proof_dir/initial-package-status.txt"

# Authenticate the public GitHub Release before using its openSUSE RPM as repository input.
openssl dgst -sha256 -verify packaging/release-signing-public.pem \
  -signature "$release_dir/SHA256SUMS.sig" "$release_dir/SHA256SUMS"
python3 - "$release_dir" "$version" "$baseline_package" >"$proof_dir/public-release-validation.json" <<'PY'
import hashlib, json, pathlib, re, sys
root, version, rpm_name = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
selected = [rpm_name, "loopwire-linux-x86_64.tar.gz", "release-assets.json"]
entries = {}
for number, line in enumerate((root / "SHA256SUMS").read_text().splitlines(), 1):
    match = re.fullmatch(r"([0-9a-f]{64})  ([^/\\\s]+)", line)
    assert match and match.group(2) not in entries, f"invalid or duplicate SHA256SUMS entry at line {number}"
    entries[match.group(2)] = match.group(1)
for name in selected:
    assert name in entries, f"SHA256SUMS must contain exactly one {name} entry"
    data = (root / name).read_bytes()
    assert hashlib.sha256(data).hexdigest() == entries[name], f"signed checksum mismatch: {name}"
manifest = json.loads((root / "release-assets.json").read_text())
assert set(manifest) == {"schema", "release", "artifacts"} and manifest["schema"] == "loopwire.release-assets.v1"
release = manifest["release"]
assert set(release) == {"tag", "version", "gitHead"}
assert release["tag"] == f"v{version}" and release["version"] == version
assert re.fullmatch(r"[0-9a-f]{40}", release["gitHead"])
assert isinstance(manifest["artifacts"], list)
opensuse = [item for item in manifest["artifacts"] if isinstance(item, dict) and item.get("target") == "opensuse-tumbleweed"]
assert len(opensuse) == 1 and set(opensuse[0]) == {"name", "kind", "target", "architecture", "bytes", "sha256"}
rpm = opensuse[0]
assert (rpm["name"], rpm["kind"], rpm["target"], rpm["architecture"]) == (rpm_name, "native-rpm", "opensuse-tumbleweed", "x86_64")
assert rpm["bytes"] == (root / rpm_name).stat().st_size and rpm["sha256"] == entries[rpm_name]
portable = [item for item in manifest["artifacts"] if isinstance(item, dict)
            and item.get("name") == "loopwire-linux-x86_64.tar.gz"]
assert len(portable) == 1 and portable[0].get("kind") == "portable-archive"
assert portable[0].get("target") == "linux-generic" and portable[0].get("architecture") == "x86_64"
assert portable[0].get("bytes") == (root / selected[1]).stat().st_size and portable[0].get("sha256") == entries[selected[1]]
print(json.dumps({"status": "verified", "releaseGitHead": release["gitHead"],
                  "rpmSha256": entries[rpm_name], "tarSha256": entries[selected[1]],
                  "manifestSha256": entries[selected[2]]}, sort_keys=True))
PY
tar -xOf "$release_dir/loopwire-linux-x86_64.tar.gz" RELEASE >"$proof_dir/payload-release.txt"
python3 - "$proof_dir/payload-release.txt" "$version" <<'PY'
import pathlib, re, sys
values = {}
for line in pathlib.Path(sys.argv[1]).read_text().splitlines():
    assert "=" in line
    key, value = line.split("=", 1)
    assert key not in values
    values[key] = value
assert set(values) == {"name", "version", "arch", "source_date_epoch"}
assert values["name"] == "loopwire" and values["version"] == sys.argv[2] and values["arch"] == "x86_64"
assert re.fullmatch(r"[0-9]+", values["source_date_epoch"])
PY
public_release_git_head="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["releaseGitHead"])' "$proof_dir/public-release-validation.json")"
printf '%s\n' "$public_release_git_head" >"$proof_dir/public-release-git-head.txt"
for release_file in "$baseline_package" loopwire-linux-x86_64.tar.gz SHA256SUMS SHA256SUMS.sig release-assets.json; do
  cp "$release_dir/$release_file" "$public_release_proof/"
done
cp packaging/release-signing-public.pem "$public_release_proof/"
cp "$proof_dir/payload-release.txt" "$public_release_proof/RELEASE"
(cd "$release_dir" && sha256sum loopwire-linux-x86_64.tar.gz) >"$proof_dir/release-payload.sha256"

sudo zypper --non-interactive refresh
sudo zypper --non-interactive install --no-recommends \
  ca-certificates ca-certificates-mozilla cpio createrepo_c curl findutils gpg2 gzip nodejs openssl \
  python3 rpm-build tar xdotool xorg-x11-server-Xvfb

# Private fixture keys stay inside the disposable guest and are never copied into proof.
gnupg_home="$fixture_dir/gnupg"
mkdir -m 0700 "$gnupg_home"
gpg --homedir "$gnupg_home" --batch --pinentry-mode loopback --passphrase '' \
  --quick-generate-key 'Loopwire disposable openSUSE repository guest fixture' rsa3072 sign 0
fingerprint="$(gpg --homedir "$gnupg_home" --batch --with-colons --list-keys |
  awk -F: '$1 == "fpr" { print $10; exit }')"
[[ "$fingerprint" =~ ^[0-9A-F]{40}$ ]]
gpg --homedir "$gnupg_home" --batch --armor --export "$fingerprint" >"$proof_dir/repository-key.asc"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$fixture_dir/synthetic-release-key.pem"
openssl pkey -in "$fixture_dir/synthetic-release-key.pem" -pubout -out "$fixture_dir/synthetic-release-public.pem"
cp "$fixture_dir/synthetic-release-public.pem" "$proof_dir/synthetic-release-public.pem"

upgrade_release="$fixture_dir/upgrade-release"
mkdir -p "$upgrade_release"
SOURCE_DATE_EPOCH=0 bash scripts/build-rpm-package.sh --target opensuse-tumbleweed \
  --version "$upgrade_version" --arch x86_64 --release-dir "$release_dir" --output-dir "$upgrade_release"
[ -f "$upgrade_release/$upgrade_package" ]
[ "$(find "$upgrade_release" -maxdepth 1 -type f -name '*.rpm' | wc -l)" -eq 1 ]
upgrade_source_sha256="$(sha256sum "$upgrade_release/$upgrade_package" | awk '{ print $1 }')"
cp "$release_dir/loopwire-linux-x86_64.tar.gz" "$upgrade_release/"
python3 - "$upgrade_release" "$upgrade_version" "$upgrade_package" "$public_release_git_head" <<'PY'
import hashlib, json, pathlib, sys
root, version, rpm_name, revision = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
def artifact(name, kind, target):
    data = (root / name).read_bytes()
    return {"name": name, "kind": kind, "target": target, "architecture": "x86_64",
            "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
manifest = {"schema": "loopwire.release-assets.v1",
            "release": {"tag": f"v{version}", "version": version, "gitHead": revision},
            "artifacts": [artifact(rpm_name, "native-rpm", "opensuse-tumbleweed"),
                          artifact("loopwire-linux-x86_64.tar.gz", "portable-archive", "linux-generic")]}
(root / "release-assets.json").write_text(json.dumps(manifest, indent=2) + "\n")
PY
(
  cd "$upgrade_release"
  sha256sum "$upgrade_package" loopwire-linux-x86_64.tar.gz release-assets.json >SHA256SUMS
)
openssl dgst -sha256 -sign "$fixture_dir/synthetic-release-key.pem" \
  -out "$upgrade_release/SHA256SUMS.sig" "$upgrade_release/SHA256SUMS"
baseline_source_sha256="$(sha256sum "$release_dir/$baseline_package" | awk '{ print $1 }')"
printf 'baseline\t%s\t%s\nupgraded\t%s\t%s\n' \
  "$baseline_package" "$baseline_source_sha256" "$upgrade_package" "$upgrade_source_sha256" \
  >"$proof_dir/release-sources.tsv"

python3 scripts/rpm-repository.py build --target opensuse-tumbleweed-x86_64 \
  --release-dir "$release_dir" --version "$version" --output "$fixture_dir/initial" \
  --signing-key "$fingerprint" --gnupg-home "$gnupg_home"
python3 scripts/rpm-repository.py build --target opensuse-tumbleweed-x86_64 \
  --release-dir "$upgrade_release" --version "$upgrade_version" --output "$fixture_dir/upgraded" \
  --previous "$fixture_dir/initial" --signing-key "$fingerprint" --gnupg-home "$gnupg_home" \
  --release-public-key "$fixture_dir/synthetic-release-public.pem"
python3 scripts/rpm-repository.py rollback --target opensuse-tumbleweed-x86_64 \
  --repository "$fixture_dir/initial" --output "$fixture_dir/rolled-back" \
  --signing-key "$fingerprint" --gnupg-home "$gnupg_home"

for repository_stage in initial upgraded rolled-back; do
  python3 scripts/rpm-repository.py verify --target opensuse-tumbleweed-x86_64 \
    --repository "$fixture_dir/$repository_stage" --public-key "$proof_dir/repository-key.asc" \
    --fingerprint "$fingerprint" >"$proof_dir/repositories/${repository_stage}-verification.json"
  cp -a "$fixture_dir/$repository_stage" "$proof_dir/repositories/$repository_stage"
done
cp "$fixture_dir/initial/packages/$baseline_package" "$proof_dir/packages/"
cp "$fixture_dir/upgraded/packages/$upgrade_package" "$proof_dir/packages/"
baseline_rpm_sha256="$(sha256sum "$proof_dir/packages/$baseline_package" | awk '{ print $1 }')"
upgrade_rpm_sha256="$(sha256sum "$proof_dir/packages/$upgrade_package" | awk '{ print $1 }')"
printf 'baseline\t%s\t%s\nupgraded\t%s\t%s\n' \
  "$baseline_package" "$baseline_rpm_sha256" "$upgrade_package" "$upgrade_rpm_sha256" \
  >"$proof_dir/signed-packages.tsv"

fixture_rpmdb="/var/lib/loopwire-repository-proof-rpmdb"
sudo test ! -e "$fixture_rpmdb"
sudo install -d -m 0700 -o root -g root "$fixture_rpmdb"
# Tumbleweed's enforcing SELinux policy permits RPM database writes only under
# the system database label. The database remains isolated and is removed below.
sudo chcon --reference=/usr/lib/sysimage/rpm "$fixture_rpmdb"
sudo rpm --dbpath "$fixture_rpmdb" --initdb
sudo rpm --dbpath "$fixture_rpmdb" --import "$proof_dir/repository-key.asc"
sudo rpm --dbpath "$fixture_rpmdb" -Kv "$proof_dir/packages/$baseline_package" >"$proof_dir/packages/baseline-rpm-signature.txt"
sudo rpm --dbpath "$fixture_rpmdb" -Kv "$proof_dir/packages/$upgrade_package" >"$proof_dir/packages/upgraded-rpm-signature.txt"

# A guest-only CA exercises HTTPS trust without introducing a production credential.
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj '/CN=Loopwire disposable guest CA' \
  -keyout "$fixture_dir/ca-key.pem" -out "$fixture_dir/ca.crt" \
  -addext 'basicConstraints=critical,CA:TRUE' -addext 'keyUsage=critical,keyCertSign,cRLSign'
openssl req -newkey rsa:2048 -nodes -subj '/CN=127.0.0.1' \
  -keyout "$fixture_dir/tls-key.pem" -out "$fixture_dir/tls.csr"
printf 'subjectAltName=IP:127.0.0.1\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n' \
  >"$fixture_dir/tls.ext"
openssl x509 -req -in "$fixture_dir/tls.csr" -CA "$fixture_dir/ca.crt" -CAkey "$fixture_dir/ca-key.pem" \
  -CAcreateserial -days 1 -extfile "$fixture_dir/tls.ext" -out "$fixture_dir/tls.crt"
cp "$fixture_dir/ca.crt" "$proof_dir/tls-ca.crt"
cp "$fixture_dir/tls.crt" "$proof_dir/tls-server.crt"
sudo install -m 0644 "$fixture_dir/ca.crt" /etc/pki/trust/anchors/loopwire-guest-fixture.crt
sudo update-ca-certificates
mkdir -p "$fixture_dir/www/opensuse/tumbleweed"
ln -s "$fixture_dir/initial" "$fixture_dir/www/opensuse/tumbleweed/x86_64"
cat >"$fixture_dir/https-server.py" <<'PY'
import functools, http.server, ssl, sys
class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if "If-Modified-Since" in self.headers:
            del self.headers["If-Modified-Since"]
        super().do_GET()
class Server(http.server.ThreadingHTTPServer):
    def shutdown_request(self, request):
        request.settimeout(5)
        try: request.unwrap()
        except (OSError, ssl.SSLError): request.close()
server = Server(("127.0.0.1", 8445), functools.partial(Handler, directory=sys.argv[1]))
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(sys.argv[2], sys.argv[3])
server.socket = context.wrap_socket(server.socket, server_side=True)
server.serve_forever()
PY
python3 "$fixture_dir/https-server.py" "$fixture_dir/www" "$fixture_dir/tls.crt" "$fixture_dir/tls-key.pem" \
  >"$proof_dir/https-server.log" 2>&1 &
server_pid=$!
cleanup() { kill "$server_pid" 2>/dev/null || true; }
trap cleanup EXIT
for _attempt in $(seq 1 20); do
  if curl --fail --silent --show-error "$base_url/keys/$fingerprint.asc" >"$proof_dir/https-key.asc"; then break; fi
  sleep 1
done
cmp "$proof_dir/repository-key.asc" "$proof_dir/https-key.asc"

verify_public_stage() {
  local stage="$1"
  python3 scripts/verify-opensuse-public.py --repository "$fixture_dir/$stage" \
    --public-key "$proof_dir/repository-key.asc" --fingerprint "$fingerprint" \
    --base-url "$base_url" --ca-file "$fixture_dir/ca.crt" \
    | tee "$proof_dir/repositories/${stage}-public-verification.json"
}

verify_public_stage initial
sudo bash scripts/setup-opensuse-repository.sh --base-url "$base_url" --fingerprint "$fingerprint" \
  >"$proof_dir/bootstrap.log" 2>&1
cat /etc/zypp/repos.d/loopwire.repo >"$proof_dir/loopwire.repo"
cat "/etc/zypp/keys/loopwire-repository-$fingerprint.asc" >"$proof_dir/configured-repository-key.asc"
cmp "$proof_dir/repository-key.asc" "$proof_dir/configured-repository-key.asc"
sudo zypper --non-interactive --gpg-auto-import-keys refresh --force loopwire >"$proof_dir/bootstrap-refresh.log" 2>&1

smoke_installed() {
  local stage="$1" expected_version="$2" package_name="$3" stage_dir="$proof_dir/$1"
  mkdir -p "$stage_dir"
  rpm -q --qf '%{NAME}\t%{VERSION}-%{RELEASE}\t%{ARCH}\t%{VENDOR}\n' loopwire >"$stage_dir/package-metadata.tsv"
  [ "$(rpm -q --qf '%{VERSION}-%{RELEASE}' loopwire)" = "$expected_version" ]
  [ "$(rpm -q --qf '%{VENDOR}' loopwire)" = '(none)' ]
  zypper --no-refresh --xmlout search --installed-only --details --match-exact loopwire >"$stage_dir/zypper-search.xml"
  python3 - "$stage_dir/zypper-search.xml" "$expected_version" >"$stage_dir/zypper-origin.tsv" <<'PY'
import sys, xml.etree.ElementTree as ET
root, version = ET.parse(sys.argv[1]).getroot(), sys.argv[2]
items = [item for item in root.iter("solvable") if item.attrib.get("name") == "loopwire"]
assert len(items) == 1
item = items[0]
assert item.attrib.get("status") == "installed" and item.attrib.get("edition") == version
assert item.attrib.get("arch") == "x86_64" and item.attrib.get("repository") == "loopwire"
print("loopwire\t%s\tx86_64\tloopwire\t(none)" % version)
PY
  zypper --no-refresh info loopwire >"$stage_dir/zypper-info.txt"
  rpm -ql loopwire | sort >"$stage_dir/package-files.txt"
  while IFS= read -r installed_file; do
    if [ -f "$installed_file" ]; then sha256sum "$installed_file"; fi
  done <"$stage_dir/package-files.txt" >"$stage_dir/installed-files.sha256"
  printf '%s  %s\n' "$(sha256sum "$proof_dir/packages/$package_name" | awk '{ print $1 }')" "$package_name" \
    >"$stage_dir/signed-package.sha256"
  sudo rpm --dbpath "$fixture_rpmdb" -Kv "$proof_dir/packages/$package_name" >"$stage_dir/rpm-signature.txt"
  loopwire --background --help >"$stage_dir/background-help.txt"
  loopwire-dsp-provider --help >"$stage_dir/dsp-provider-help.txt"
  loopwire-jack-ports --help >"$stage_dir/jack-provider-help.txt"
  loopwire-detect-audio --pretty >"$stage_dir/detect-audio.json"
  ldd /usr/lib/loopwire/loopwire-gui >"$stage_dir/gui-ldd.txt"
  if grep -Fq 'not found' "$stage_dir/gui-ldd.txt"; then
    echo 'Loopwire GUI has an unresolved shared-library dependency' >&2
    exit 1
  fi
  local gui_status=0
  # shellcheck disable=SC2016
  timeout 35s bash -c '
    stage_dir="$1"; app_pid=""
    Xvfb :99 -screen 0 1280x720x24 -nolisten tcp >"$stage_dir/xvfb.log" 2>&1 &
    xvfb_pid=$!
    cleanup_gui() { [ -z "$app_pid" ] || kill "$app_pid" 2>/dev/null || true; kill "$xvfb_pid" 2>/dev/null || true; wait || true; }
    trap cleanup_gui EXIT
    sleep 1
    DISPLAY=:99 GDK_BACKEND=x11 WEBKIT_DISABLE_DMABUF_RENDERER=1 \
      /usr/lib/loopwire/loopwire-gui >"$stage_dir/gui-launch.log" 2>&1 &
    app_pid=$!
    for attempt in $(seq 1 20); do
      kill -0 "$app_pid" 2>/dev/null || exit 1
      if DISPLAY=:99 xdotool search --name "^(Loopwire|loopwire-gui)$" >"$stage_dir/gui-window-ids.txt" 2>/dev/null; then
        while read -r window_id; do DISPLAY=:99 xdotool getwindowname "$window_id"; done \
          <"$stage_dir/gui-window-ids.txt" >"$stage_dir/gui-window-names.txt"
        exit 0
      fi
      sleep 1
    done
    exit 124
  ' bash "$stage_dir" || gui_status=$?
  printf '%s\n' "$gui_status" >"$stage_dir/gui-launch-status.txt"
  [ "$gui_status" -eq 0 ] && [ -s "$stage_dir/gui-window-ids.txt" ]
  if grep -Eiq 'error while loading shared libraries|panic|protocol error|missing acquire timeline' \
      "$stage_dir/gui-launch.log"; then
    echo 'Loopwire GUI logged a fatal launch error' >&2
    exit 1
  fi
  printf '%s\t%s\tinstalled\n' "$stage" "$expected_version" >>"$proof_dir/lifecycle.tsv"
}

sudo zypper --non-interactive install --from loopwire --no-recommends "loopwire=$baseline_package_version" >"$proof_dir/install.log" 2>&1
smoke_installed install "$baseline_package_version" "$baseline_package"
sudo zypper --non-interactive install --from loopwire --force --no-allow-vendor-change --no-allow-arch-change \
  --no-recommends "loopwire=$baseline_package_version" >"$proof_dir/reinstall.log" 2>&1
smoke_installed reinstall "$baseline_package_version" "$baseline_package"
ln -sfn "$fixture_dir/upgraded" "$fixture_dir/www/opensuse/tumbleweed/x86_64"
verify_public_stage upgraded
sudo zypper --non-interactive --gpg-auto-import-keys refresh --force loopwire >"$proof_dir/upgrade-refresh.log" 2>&1
sudo zypper --non-interactive update --repo loopwire loopwire >"$proof_dir/upgrade.log" 2>&1
smoke_installed upgrade "$upgrade_package_version" "$upgrade_package"
ln -sfn "$fixture_dir/rolled-back" "$fixture_dir/www/opensuse/tumbleweed/x86_64"
verify_public_stage rolled-back
sudo zypper --non-interactive --gpg-auto-import-keys refresh --force loopwire >"$proof_dir/rollback-refresh.log" 2>&1
sudo zypper --non-interactive install --from loopwire --oldpackage --force \
  --no-allow-vendor-change --no-allow-arch-change --no-recommends \
  "loopwire=$baseline_package_version" >"$proof_dir/rollback.log" 2>&1
smoke_installed rollback "$baseline_package_version" "$baseline_package"
sudo zypper --non-interactive remove loopwire >"$proof_dir/remove.log" 2>&1
if rpm -q loopwire >/dev/null 2>&1; then
  echo 'Loopwire package remains installed after removal' >&2
  exit 1
fi
for removed_file in /usr/bin/loopwire /usr/bin/loopwire-dsp-provider /usr/bin/loopwire-jack-ports \
  /usr/bin/loopwire-detect-audio /usr/lib/loopwire /usr/share/applications/loopwire.desktop \
  /usr/share/icons/hicolor/scalable/apps/loopwire.svg; do
  test ! -e "$removed_file"
  printf '%s\tabsent\n' "$removed_file" >>"$proof_dir/removed-files.tsv"
done
printf 'remove\t%s\tabsent\n' "$baseline_package_version" >>"$proof_dir/lifecycle.tsv"
sudo rm -rf -- "$fixture_rpmdb"
test ! -e "$fixture_rpmdb"
sudo bash scripts/setup-opensuse-repository.sh --remove >"$proof_dir/source-removal.log" 2>&1
test ! -e /etc/zypp/repos.d/loopwire.repo
test ! -e "/etc/zypp/keys/loopwire-repository-$fingerprint.asc"
sudo zypper clean --all >"$proof_dir/source-removal-clean.log" 2>&1
zypper repos --details >"$proof_dir/source-removal-repositories.txt"
if grep -Eq '(^|[[:space:]|])loopwire([[:space:]|]|$)' "$proof_dir/source-removal-repositories.txt"; then
  echo 'Loopwire repository remains configured after removal' >&2
  exit 1
fi

snapshot="$(sed -n 's/^VERSION_ID="\{0,1\}\([^"[:space:]]*\)"\{0,1\}$/\1/p' /etc/os-release)"
[[ "$snapshot" =~ ^[0-9]{8}$ ]]
{
  printf 'schema\tloopwire.opensuse-repository-vm-proof.v1\n'
  printf 'target\t%s\n' "$target"
  printf 'snapshot\t%s\n' "$snapshot"
  printf 'git_head\t%s\n' "$git_head"
  printf 'version\t%s\n' "$version"
  printf 'upgrade_version\t%s\n' "$upgrade_version"
  printf 'baseline_package_version\t%s\n' "$baseline_package_version"
  printf 'upgrade_package_version\t%s\n' "$upgrade_package_version"
  printf 'fingerprint\t%s\n' "$fingerprint"
  printf 'base_url\t%s\n' "$base_url"
  printf 'payload_kind\tpublic-release-baseline-with-synthetic-upgrade\n'
  printf 'synthetic_upgrade\ttrue\n'
  printf 'public_release_git_head\t%s\n' "$public_release_git_head"
  printf 'baseline_source_sha256\t%s\n' "$baseline_source_sha256"
  printf 'upgrade_source_sha256\t%s\n' "$upgrade_source_sha256"
  printf 'baseline_rpm_sha256\t%s\n' "$baseline_rpm_sha256"
  printf 'upgrade_rpm_sha256\t%s\n' "$upgrade_rpm_sha256"
  printf 'verification_epoch\t%s\n' "$(date +%s)"
} >"$proof_dir/summary.tsv"
set +x
echo "openSUSE repository lifecycle proof passed: $target snapshot $snapshot"
