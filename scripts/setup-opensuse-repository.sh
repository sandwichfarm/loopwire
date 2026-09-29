#!/usr/bin/env bash
set -euo pipefail

base_url=""
fingerprint=""
install_root="/"
remove="false"
dry_run="false"

fail() { printf 'setup-opensuse-repository: %s\n' "$*" >&2; exit 1; }
usage() {
  cat <<'USAGE'
Configure Loopwire's signed project repository on openSUSE Tumbleweed x86_64.

Usage:
  sudo bash setup-opensuse-repository.sh --base-url HTTPS_URL --fingerprint OPENPGP_FINGERPRINT
  sudo bash setup-opensuse-repository.sh --remove
  bash setup-opensuse-repository.sh --base-url HTTPS_URL --fingerprint FINGERPRINT --dry-run

Options:
  --root DIR  Configure an offline filesystem tree instead of / (including its etc/os-release).

Obtain the URL and fingerprint from the verified Loopwire channel documentation.
Requires curl, GnuPG, Python 3, and RPM. Existing unrelated Zypper repositories are preserved.
This writes only the repository and pinned key files. Refresh and install are separate reviewed steps.
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
repo_file="${install_root%/}/etc/zypp/repos.d/loopwire.repo"
key_directory="${install_root%/}/etc/zypp/keys"
python3 - "$install_root" "$repo_file" "$key_directory" <<'PY'
import sys
from pathlib import Path
root = Path(sys.argv[1])
for name in sys.argv[2:]:
    path = Path(name)
    for part in (path, *path.parents):
        if part == root:
            break
        if part.is_symlink():
            sys.exit('setup-opensuse-repository: refusing symbolic links inside the target Zypper configuration tree')
        if not part.is_relative_to(root):
            sys.exit('setup-opensuse-repository: configuration path leaves the target root')
PY
owner_marker="# Managed by Loopwire openSUSE repository setup"
[ ! -L "$repo_file" ] || fail "refusing a symbolic-link repository file"
if [ -e "$repo_file" ] && ! head -n 1 "$repo_file" | grep -Fxq "$owner_marker"; then
  fail "loopwire.repo already exists and is not managed by this helper"
fi
if [ "$install_root" = / ] && [ "$dry_run" != true ] && [ "$EUID" -ne 0 ]; then
  fail "run with sudo to change system repository configuration, or use --dry-run"
fi

if [ "$remove" = true ]; then
  if [ "$dry_run" = true ]; then
    printf 'Would remove the managed Loopwire openSUSE repository and pinned key file.\n'
    exit 0
  fi
  if [ -f "$repo_file" ]; then
    key_name="$(sed -n 's|^gpgkey=file:///etc/zypp/keys/\(loopwire-repository-[A-F0-9]*\.asc\)$|\1|p' "$repo_file")"
    [[ "$key_name" =~ ^loopwire-repository-[A-F0-9]{40}\.asc$ ]] || fail "managed repository has an unexpected key path"
    rm -- "$repo_file"
    rm -f -- "$key_directory/$key_name"
  fi
  printf 'Loopwire openSUSE repository removed. Installed packages, RPM database keys, and other repositories are unchanged.\n'
  exit 0
fi

for command in curl gpg python3 rpm; do
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
    sys.exit('setup-opensuse-repository: base URL must be HTTPS without credentials, whitespace, query, or fragment')
print(value.rstrip('/'))
PY
)"
python3 - "${install_root%/}/etc/os-release" <<'PY'
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
if values.get('ID') != 'opensuse-tumbleweed':
    sys.exit('setup-opensuse-repository: supported system is openSUSE Tumbleweed')
PY
[ "$(rpm --eval '%{_arch}')" = x86_64 ] || fail "this channel currently supports x86_64 only"
key_name="loopwire-repository-${fingerprint}.asc"
[ ! -L "$key_directory/$key_name" ] || fail "refusing a symbolic-link key file"
if [ "$dry_run" = true ]; then
  printf 'Would verify %s/keys/%s.asc and configure Tumbleweed x86_64 with strict RPM and metadata signature checks.\n' \
    "$base_url" "$fingerprint"
  exit 0
fi

temporary="$(mktemp -d)"
key_temporary=""
repo_temporary=""
cleanup() {
  rm -rf -- "$temporary"
  [ -z "$key_temporary" ] || rm -f -- "$key_temporary"
  [ -z "$repo_temporary" ] || rm -f -- "$repo_temporary"
}
trap cleanup EXIT
mkdir -m 0700 "$temporary/gnupg"
curl --disable --fail --silent --show-error --proto '=https' --tlsv1.2 \
  --connect-timeout 10 --max-time 60 --output "$temporary/key.asc" "$base_url/keys/$fingerprint.asc"
actual="$(gpg --no-options --batch --homedir "$temporary/gnupg" --with-colons --show-keys "$temporary/key.asc" |
  awk -F: '$1 == "pub" { count++ } $1 == "fpr" && !seen { print $10; seen=1 } END { if (count != 1) exit 1 }')"
[ "$actual" = "$fingerprint" ] || fail "downloaded key does not match the expected fingerprint"
cat >"$temporary/loopwire.repo" <<EOF
$owner_marker
[loopwire]
name=Loopwire for openSUSE Tumbleweed - \$basearch
baseurl=$base_url
enabled=1
autorefresh=1
type=rpm-md
priority=99
gpgcheck=1
repo_gpgcheck=1
pkg_gpgcheck=1
gpgkey=file:///etc/zypp/keys/$key_name
EOF
mkdir -p "$key_directory" "$(dirname "$repo_file")"
key_temporary="$(mktemp "$key_directory/.loopwire-key.XXXXXX")"
repo_temporary="$(mktemp "$(dirname "$repo_file")/.loopwire-repo.XXXXXX")"
install -m 0644 "$temporary/key.asc" "$key_temporary"
install -m 0644 "$temporary/loopwire.repo" "$repo_temporary"
mv -fT -- "$key_temporary" "$key_directory/$key_name"
mv -fT -- "$repo_temporary" "$repo_file"
printf 'Configured the Loopwire openSUSE Tumbleweed repository with key %s.\n' "$fingerprint"
printf 'Next: sudo zypper refresh loopwire\n      sudo zypper install loopwire\n'
