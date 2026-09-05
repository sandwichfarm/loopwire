#!/usr/bin/env bash
set -euo pipefail

base_url=""
fingerprint=""
install_root="/"
remove="false"
dry_run="false"

fail() { printf 'setup-apt-repository: %s\n' "$*" >&2; exit 1; }
usage() {
  cat <<'USAGE'
Configure Loopwire's signed APT repository on Ubuntu 24.04 or Debian 13 (amd64).

Usage:
  sudo bash setup-apt-repository.sh --base-url HTTPS_URL --fingerprint OPENPGP_FINGERPRINT
  sudo bash setup-apt-repository.sh --remove
  bash setup-apt-repository.sh --base-url HTTPS_URL --fingerprint FINGERPRINT --dry-run

Options:
  --root DIR  Configure an offline filesystem tree instead of / (including its etc/os-release).

Obtain the URL and fingerprint from the verified Loopwire channel documentation.
Requires curl, GnuPG, Python 3, and dpkg. Existing unrelated APT sources are preserved.
This only writes the source/keyring configuration. Run apt update and apt install yourself afterward.
USAGE
}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --base-url) base_url="${2:?missing --base-url value}"; shift 2 ;;
    --fingerprint) fingerprint="${2:?missing --fingerprint value}"; shift 2 ;;
    --root) install_root="${2:?missing --root value}"; shift 2 ;;
    --remove) remove="true"; shift ;;
    --dry-run) dry_run="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown option: $1" ;;
  esac
done

install_root="$(realpath -e "$install_root")"
[ -d "$install_root" ] || fail "root must be an existing directory"
source_file="${install_root%/}/etc/apt/sources.list.d/loopwire.sources"
key_directory="${install_root%/}/etc/apt/keyrings"
python3 - "$install_root" "$source_file" "$key_directory" <<'PY'
import sys
from pathlib import Path
root = Path(sys.argv[1])
for name in sys.argv[2:]:
    path = Path(name)
    for part in (path, *path.parents):
        if part == root:
            break
        if part.is_symlink():
            sys.exit('setup-apt-repository: refusing symbolic links inside the target APT configuration tree')
        if not part.is_relative_to(root):
            sys.exit('setup-apt-repository: APT configuration path leaves the target root')
PY
owner_marker="# Managed by Loopwire APT repository setup"
[ ! -L "$source_file" ] || fail "refusing a symbolic-link source file"
if [ -e "$source_file" ] && ! head -n 1 "$source_file" | grep -Fxq "$owner_marker"; then
  fail "loopwire.sources already exists and is not managed by this helper"
fi
if [ "$install_root" = / ] && [ "$dry_run" != true ] && [ "$EUID" -ne 0 ]; then
  fail "run with sudo to change /etc/apt, or use --dry-run"
fi

if [ "$remove" = true ]; then
  if [ "$dry_run" = true ]; then
    printf 'Would remove the managed Loopwire APT source and its keyring.\n'
    exit 0
  fi
  if [ -f "$source_file" ]; then
    key_name="$(sed -n 's|^Signed-By: /etc/apt/keyrings/\(loopwire-[A-F0-9]*\.asc\)$|\1|p' "$source_file")"
    [[ "$key_name" =~ ^loopwire-[A-F0-9]{40}\.asc$ ]] || fail "managed source has an unexpected keyring path"
    rm -- "$source_file"
    rm -f -- "$key_directory/$key_name"
  fi
  printf 'Loopwire APT source removed. Installed packages and other sources are unchanged.\n'
  exit 0
fi

for command in curl gpg python3 dpkg; do
  command -v "$command" >/dev/null 2>&1 || fail "$command is required"
done
fingerprint="${fingerprint^^}"
[[ "$fingerprint" =~ ^[A-F0-9]{40}$ ]] || fail "provide a complete 40-character OpenPGP fingerprint"
base_url="$(python3 - "$base_url" <<'PY'
import sys
from urllib.parse import urlsplit
value = sys.argv[1]
try:
    url = urlsplit(value)
    valid = (url.scheme == 'https' and url.hostname and not url.username and not url.password
             and not any(char in value for char in "\\'\"`$<>?#")
             and all(32 < ord(char) < 127 for char in value))
    if not valid:
        raise ValueError('invalid URL')
    if url.port is not None and not 1 <= url.port <= 65535:
        raise ValueError('invalid port')
except ValueError:
    sys.exit('setup-apt-repository: base URL must be HTTPS without credentials, whitespace, query, or fragment')
print(value.rstrip('/'))
PY
)"

# Read os-release as data; do not execute a file supplied through --root.
suite="$(python3 - "${install_root%/}/etc/os-release" <<'PY'
import shlex
import sys
from pathlib import Path
values = {}
for line in Path(sys.argv[1]).read_text().splitlines():
    if '=' in line and not line.lstrip().startswith('#'):
        key, value = line.split('=', 1)
        fields = shlex.split(value)
        if len(fields) == 1:
            values[key] = fields[0]
suite = {('ubuntu', '24.04'): 'ubuntu-24.04', ('debian', '13'): 'debian-13'}.get(
    (values.get('ID'), values.get('VERSION_ID')))
if not suite:
    sys.exit('setup-apt-repository: supported systems are Ubuntu 24.04 and Debian 13')
print(suite)
PY
)"
[ "$(dpkg --print-architecture)" = amd64 ] || fail "this channel currently supports amd64 only"
key_name="loopwire-${fingerprint}.asc"
[ ! -L "$key_directory/$key_name" ] || fail "refusing a symbolic-link keyring"
if [ "$dry_run" = true ]; then
  printf 'Would verify %s/keys/%s.asc and configure suite %s with a scoped Signed-By keyring.\n' \
    "$base_url" "$fingerprint" "$suite"
  exit 0
fi

temporary="$(mktemp -d)"
key_temporary=""
source_temporary=""
cleanup() {
  rm -rf -- "$temporary"
  [ -z "$key_temporary" ] || rm -f -- "$key_temporary"
  [ -z "$source_temporary" ] || rm -f -- "$source_temporary"
}
trap cleanup EXIT
mkdir -m 0700 "$temporary/gnupg"
curl --disable --fail --silent --show-error --proto '=https' --tlsv1.2 \
  --connect-timeout 10 --max-time 60 --output "$temporary/key.asc" "$base_url/keys/$fingerprint.asc"
actual="$(gpg --no-options --batch --homedir "$temporary/gnupg" --with-colons --show-keys "$temporary/key.asc" |
  awk -F: '$1 == "pub" { count++ } $1 == "fpr" && !seen { print $10; seen=1 } END { if (count != 1) exit 1 }')"
[ "$actual" = "$fingerprint" ] || fail "downloaded key does not match the expected fingerprint"
cat >"$temporary/loopwire.sources" <<EOF
$owner_marker
Types: deb
URIs: $base_url
Suites: $suite
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/$key_name
EOF

mkdir -p "$key_directory" "$(dirname "$source_file")"
key_temporary="$(mktemp "$key_directory/.loopwire-key.XXXXXX")"
source_temporary="$(mktemp "$(dirname "$source_file")/.loopwire-source.XXXXXX")"
install -m 0644 "$temporary/key.asc" "$key_temporary"
install -m 0644 "$temporary/loopwire.sources" "$source_temporary"
mv -fT -- "$key_temporary" "$key_directory/$key_name"
mv -fT -- "$source_temporary" "$source_file"
printf 'Configured Loopwire APT suite %s with key %s.\n' "$suite" "$fingerprint"
printf 'Next: sudo apt update\n      sudo apt install loopwire\n'
