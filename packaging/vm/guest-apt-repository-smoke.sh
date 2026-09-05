#!/usr/bin/env bash
# The unprivileged guest user owns proof logs; sudo applies only to the package commands.
# shellcheck disable=SC2024
set -euo pipefail

target="${1:?target is required}"
package_target="${2:?package target is required}"
format="${3:?format is required}"
version="${4:?version is required}"
git_head="${5:?git head is required}"
kit_dir="${6:-$PWD}"
case "$target" in ubuntu-24.04 | debian-13) ;; *) echo "unsupported APT guest target" >&2; exit 2 ;; esac
[ "$package_target" = "$target" ] && [ "$format" = deb ]
[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(\+[0-9A-Za-z]+(\.[0-9A-Za-z]+)*)?$ ]]
[[ "$git_head" =~ ^[0-9a-f]{40}$ ]]
cd "$kit_dir"
proof_dir="$kit_dir/proof"
fixture_dir="$kit_dir/apt-fixture"
base_url="https://127.0.0.1:8443"
upgrade_version="${version}+aptfixture1"
[[ "$version" != *+* ]] || upgrade_version="${version}.aptfixture1"
case "$target" in
  ubuntu-24.04) suffix=1ubuntu24.04 ;;
  debian-13) suffix=1debian13 ;;
esac
baseline_package_version="${version}-${suffix}"
upgrade_package_version="${upgrade_version}-${suffix}"
mkdir -p "$proof_dir/packages" "$proof_dir/repositories" "$fixture_dir"
exec > >(tee "$proof_dir/commands.log") 2>&1
set -x

cat /etc/os-release >"$proof_dir/os-release"
uname -a >"$proof_dir/uname.txt"
systemd-detect-virt --vm >"$proof_dir/virtualization.txt"
grep -Eq '^(kvm|qemu)$' "$proof_dir/virtualization.txt"
if dpkg-query -W -f='${Status}' loopwire 2>/dev/null | grep -qx 'install ok installed'; then
  echo 'clean guest already has Loopwire installed' >&2
  exit 1
fi
printf 'absent\n' >"$proof_dir/initial-package-status.txt"
(
  cd "$kit_dir/release"
  sha256sum --check --strict SHA256SUMS >/dev/null
  sha256sum loopwire-linux-x86_64.tar.gz
) >"$proof_dir/release-payload.sha256"
tar -xOf "$kit_dir/release/loopwire-linux-x86_64.tar.gz" RELEASE >"$proof_dir/payload-release.txt"

sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  apt-utils ca-certificates curl dpkg-dev gnupg gpgv nodejs openssl python3 xdotool xz-utils xvfb

# Signing material is generated inside this disposable guest and never copied into evidence.
gnupg_home="$fixture_dir/gnupg"
mkdir -m 0700 "$gnupg_home"
gpg --homedir "$gnupg_home" --batch --pinentry-mode loopback --passphrase '' \
  --quick-generate-key 'Loopwire disposable APT guest fixture' ed25519 sign 0
fingerprint="$(gpg --homedir "$gnupg_home" --batch --with-colons --list-keys | awk -F: '$1 == "fpr" { print $10; exit }')"
[[ "$fingerprint" =~ ^[0-9A-F]{40}$ ]]
gpg --homedir "$gnupg_home" --batch --armor --export "$fingerprint" >"$proof_dir/repository-key.asc"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$fixture_dir/release-key.pem"
openssl pkey -in "$fixture_dir/release-key.pem" -pubout -out "$fixture_dir/release-public.pem"
cp "$fixture_dir/release-public.pem" "$proof_dir/release-public.pem"

build_fixture_release() {
  local fixture_version="$1" destination="$2" package_distro
  mkdir -p "$destination"
  for package_distro in ubuntu-24.04 debian-13; do
    SOURCE_DATE_EPOCH=0 bash scripts/build-deb-package.sh --target "$package_distro" \
      --version "$fixture_version" --arch x86_64 --release-dir "$kit_dir/release" --output-dir "$destination"
  done
  (cd "$destination" && sha256sum ./*.deb | sed 's|  ./|  |' >SHA256SUMS)
  openssl dgst -sha256 -sign "$fixture_dir/release-key.pem" -out "$destination/SHA256SUMS.sig" "$destination/SHA256SUMS"
  cp "$destination/loopwire_${fixture_version}-${suffix}_amd64.deb" "$proof_dir/packages/"
}

build_fixture_release "$version" "$fixture_dir/baseline-release"
build_fixture_release "$upgrade_version" "$fixture_dir/upgrade-release"
python3 scripts/apt-repository.py build --release-dir "$fixture_dir/baseline-release" --version "$version" \
  --output "$fixture_dir/initial" --signing-key "$fingerprint" --gnupg-home "$gnupg_home" \
  --release-public-key "$fixture_dir/release-public.pem"
python3 scripts/apt-repository.py build --release-dir "$fixture_dir/upgrade-release" --version "$upgrade_version" \
  --output "$fixture_dir/upgraded" --previous "$fixture_dir/initial" --signing-key "$fingerprint" \
  --gnupg-home "$gnupg_home" --release-public-key "$fixture_dir/release-public.pem"
python3 scripts/apt-repository.py rollback --repository "$fixture_dir/initial" --output "$fixture_dir/rolled-back" \
  --signing-key "$fingerprint" --gnupg-home "$gnupg_home"

for repository_stage in initial upgraded rolled-back; do
  python3 scripts/apt-repository.py verify --repository "$fixture_dir/$repository_stage" \
    --public-key "$proof_dir/repository-key.asc" --fingerprint "$fingerprint" \
    >"$proof_dir/repositories/${repository_stage}-verification.json"
  cp -a "$fixture_dir/$repository_stage" "$proof_dir/repositories/$repository_stage"
done

# A guest-only CA exercises real TLS verification; no production trust is imported.
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj '/CN=Loopwire disposable guest CA' \
  -keyout "$fixture_dir/ca-key.pem" -out "$fixture_dir/ca.crt" \
  -addext 'basicConstraints=critical,CA:TRUE' -addext 'keyUsage=critical,keyCertSign,cRLSign'
openssl req -newkey rsa:2048 -nodes -subj '/CN=127.0.0.1' \
  -keyout "$fixture_dir/tls-key.pem" -out "$fixture_dir/tls.csr"
printf 'subjectAltName=IP:127.0.0.1\nbasicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n' >"$fixture_dir/tls.ext"
openssl x509 -req -in "$fixture_dir/tls.csr" -CA "$fixture_dir/ca.crt" -CAkey "$fixture_dir/ca-key.pem" \
  -CAcreateserial -days 1 -extfile "$fixture_dir/tls.ext" -out "$fixture_dir/tls.crt"
cp "$fixture_dir/ca.crt" "$proof_dir/tls-ca.crt"
cp "$fixture_dir/tls.crt" "$proof_dir/tls-server.crt"
sudo install -m 0644 "$fixture_dir/ca.crt" /usr/local/share/ca-certificates/loopwire-guest-fixture.crt
sudo update-ca-certificates
mkdir -p "$fixture_dir/www"
ln -s "$fixture_dir/initial" "$fixture_dir/www/repository"
cat >"$fixture_dir/https-server.py" <<'PY'
import functools
import http.server
import ssl
import sys
class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        # Fixture revisions may share a filesystem timestamp to the second.
        # Always deliver their signed bytes when APT refreshes the source.
        if "If-Modified-Since" in self.headers:
            del self.headers["If-Modified-Since"]
        super().do_GET()
server = http.server.ThreadingHTTPServer(("127.0.0.1", 8443), functools.partial(Handler, directory=sys.argv[1]))
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(sys.argv[2], sys.argv[3])
server.socket = context.wrap_socket(server.socket, server_side=True)
server.serve_forever()
PY
python3 "$fixture_dir/https-server.py" "$fixture_dir/www/repository" "$fixture_dir/tls.crt" "$fixture_dir/tls-key.pem" \
  >"$proof_dir/https-server.log" 2>&1 &
server_pid=$!
cleanup() { kill "$server_pid" 2>/dev/null || true; }
trap cleanup EXIT
for _attempt in $(seq 1 20); do
  if curl --fail --silent --show-error "$base_url/keys/$fingerprint.asc" >"$proof_dir/https-key.asc"; then break; fi
  sleep 1
done
cmp "$proof_dir/repository-key.asc" "$proof_dir/https-key.asc"
python3 scripts/verify-apt-public.py --repository "$fixture_dir/initial" --public-key "$proof_dir/repository-key.asc" \
  --fingerprint "$fingerprint" --base-url "$base_url" --ca-file "$fixture_dir/ca.crt" \
  | tee "$proof_dir/repositories/initial-public-verification.json"
sudo bash scripts/setup-apt-repository.sh --base-url "$base_url" --fingerprint "$fingerprint" \
  >"$proof_dir/bootstrap.log" 2>&1
cat /etc/apt/sources.list.d/loopwire.sources >"$proof_dir/loopwire.sources"
sudo apt-get update >"$proof_dir/bootstrap-update.log" 2>&1

smoke_installed() {
  local stage="$1" expected_version="$2" stage_dir="$proof_dir/$1"
  mkdir -p "$stage_dir"
  dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\t${Status}\n' loopwire >"$stage_dir/package-metadata.tsv"
  [ "$(dpkg-query -W -f='${Version}' loopwire)" = "$expected_version" ]
  dpkg -L loopwire | sort >"$stage_dir/package-files.txt"
  while IFS= read -r installed_file; do
    if [ -f "$installed_file" ]; then sha256sum "$installed_file"; fi
  done <"$stage_dir/package-files.txt" >"$stage_dir/installed-files.sha256"
  apt-cache policy loopwire >"$stage_dir/apt-policy.txt"
  grep -Fq "$base_url" "$stage_dir/apt-policy.txt"
  loopwire --background --help >"$stage_dir/background-help.txt"
  loopwire-dsp-provider --help >"$stage_dir/dsp-provider-help.txt"
  loopwire-jack-ports --help >"$stage_dir/jack-provider-help.txt"
  loopwire-detect-audio --pretty >"$stage_dir/detect-audio.json"
  ldd /usr/lib/loopwire/loopwire-gui >"$stage_dir/gui-ldd.txt"
  if grep -Fq 'not found' "$stage_dir/gui-ldd.txt"; then
    echo 'Installed GUI has unresolved shared libraries' >&2
    return 1
  fi
  local gui_status=0
  # Runtime process/window variables must expand in the child shell.
  # shellcheck disable=SC2016
  timeout 35s bash -c '
    stage_dir="$1"
    app_pid=""
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
  [ "$gui_status" -eq 0 ]
  [ -s "$stage_dir/gui-window-ids.txt" ]
  if grep -Eiq 'error while loading shared libraries|panic|protocol error|missing acquire timeline' "$stage_dir/gui-launch.log"; then
    echo 'Installed GUI reported a startup failure' >&2
    return 1
  fi
  printf '%s\t%s\tinstalled\n' "$stage" "$expected_version" >>"$proof_dir/lifecycle.tsv"
}

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "loopwire=$baseline_package_version" >"$proof_dir/install.log" 2>&1
smoke_installed install "$baseline_package_version"
sudo DEBIAN_FRONTEND=noninteractive apt-get install --reinstall -y "loopwire=$baseline_package_version" >"$proof_dir/reinstall.log" 2>&1
smoke_installed reinstall "$baseline_package_version"
ln -sfn "$fixture_dir/upgraded" "$fixture_dir/www/repository"
python3 scripts/verify-apt-public.py --repository "$fixture_dir/upgraded" --public-key "$proof_dir/repository-key.asc" \
  --fingerprint "$fingerprint" --base-url "$base_url" --ca-file "$fixture_dir/ca.crt" \
  | tee "$proof_dir/repositories/upgraded-public-verification.json"
sudo apt-get update >"$proof_dir/upgrade-update.log" 2>&1
sudo DEBIAN_FRONTEND=noninteractive apt-get install --only-upgrade -y loopwire >"$proof_dir/upgrade.log" 2>&1
smoke_installed upgrade "$upgrade_package_version"
ln -sfn "$fixture_dir/rolled-back" "$fixture_dir/www/repository"
python3 scripts/verify-apt-public.py --repository "$fixture_dir/rolled-back" --public-key "$proof_dir/repository-key.asc" \
  --fingerprint "$fingerprint" --base-url "$base_url" --ca-file "$fixture_dir/ca.crt" \
  | tee "$proof_dir/repositories/rolled-back-public-verification.json"
sudo apt-get update >"$proof_dir/rollback-update.log" 2>&1
sudo DEBIAN_FRONTEND=noninteractive apt-get install --allow-downgrades -y "loopwire=$baseline_package_version" >"$proof_dir/rollback.log" 2>&1
smoke_installed rollback "$baseline_package_version"
sudo DEBIAN_FRONTEND=noninteractive apt-get remove -y loopwire >"$proof_dir/remove.log" 2>&1
if dpkg-query -W loopwire >/dev/null 2>&1; then
  echo 'Loopwire remains registered after removal' >&2
  exit 1
fi
for removed_file in /usr/bin/loopwire /usr/bin/loopwire-dsp-provider /usr/bin/loopwire-jack-ports \
  /usr/bin/loopwire-detect-audio /usr/lib/loopwire /usr/share/applications/loopwire.desktop \
  /usr/share/icons/hicolor/scalable/apps/loopwire.svg; do
  test ! -e "$removed_file"
  printf '%s\tabsent\n' "$removed_file" >>"$proof_dir/removed-files.tsv"
done
printf 'remove\t%s\tabsent\n' "$baseline_package_version" >>"$proof_dir/lifecycle.tsv"
sudo bash scripts/setup-apt-repository.sh --remove >"$proof_dir/source-removal.log" 2>&1
test ! -e /etc/apt/sources.list.d/loopwire.sources
test ! -e "/etc/apt/keyrings/loopwire-$fingerprint.asc"
sudo apt-get update >"$proof_dir/source-removal-update.log" 2>&1
apt-cache policy loopwire >"$proof_dir/source-removal-policy.txt"
if grep -Fq "$base_url" "$proof_dir/source-removal-policy.txt"; then
  echo 'APT still lists the removed repository' >&2
  exit 1
fi
cat >"$proof_dir/summary.tsv" <<SUMMARY
schema	loopwire.apt-repository-vm-proof.v1
target	$target
git_head	$git_head
version	$version
upgrade_version	$upgrade_version
baseline_package_version	$baseline_package_version
upgrade_package_version	$upgrade_package_version
fingerprint	$fingerprint
base_url	$base_url
payload_kind	cached-release-lifecycle-fixture
verification_epoch	$(date +%s)
SUMMARY
set +x
echo "APT repository lifecycle proof passed: $target"
