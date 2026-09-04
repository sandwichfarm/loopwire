#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version=""
source_archive=""

usage() {
  cat <<'USAGE'
Build and inspect the stable source-built Loopwire AUR package.

Usage:
  verify-aur-source-package.sh [--version VERSION] [--source-archive FILE]

The default version is the newest v-prefixed tag reachable from HEAD. When no
archive is supplied, the matching immutable GitHub tag archive is downloaded.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --) shift ;;
    --version) version="${2:?missing value for --version}"; shift 2 ;;
    --source-archive) source_archive="${2:?missing value for --source-archive}"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if ! command -v makepkg >/dev/null 2>&1; then
  echo "makepkg not found; source package verification requires an Arch Linux build environment." >&2
  exit 1
fi
command -v namcap >/dev/null 2>&1 || {
  echo "namcap not found; source package verification requires namcap." >&2
  exit 1
}

if [ -z "$version" ]; then
  tag="$(git -C "$root" describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null)" || {
    echo "No v-prefixed release tag is reachable from HEAD." >&2
    exit 1
  }
  version="${tag#v}"
else
  tag="v${version}"
fi
if [[ ! "$version" =~ ^[0-9]+([.][0-9]+)*$ ]]; then
  echo "Version must contain dot-separated integers: $version" >&2
  exit 2
fi

tmp_dir="$(mktemp -d -t loopwire-aur-source.XXXXXXXX)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

if [ -z "$source_archive" ]; then
  source_archive="$tmp_dir/loopwire-${version}.tar.gz"
  curl --fail --location --retry 3 --silent --show-error \
    "https://github.com/sandwichfarm/loopwire/archive/refs/tags/${tag}.tar.gz" \
    --output "$source_archive"
fi
if [ ! -f "$source_archive" ]; then
  echo "Source archive does not exist: $source_archive" >&2
  exit 1
fi

build_dir="$tmp_dir/build"
mkdir -p "$build_dir"
bash "$root/scripts/render-aur-pkgbuild.sh" \
  --package loopwire \
  --version "$version" \
  --pkgrel 1 \
  --source-archive "$source_archive" \
  --output "$build_dir/PKGBUILD" >/dev/null
cp "$source_archive" "$build_dir/loopwire-${version}.tar.gz"
cp "$root/packaging/aur/LICENSE-MIT" "$build_dir/LICENSE-MIT"

(
  cd "$build_dir"
  makepkg --force --nodeps --noconfirm --cleanbuild --clean
)

package_file="$(find "$build_dir" -maxdepth 1 -type f -name 'loopwire-*.pkg.tar.*' ! -name 'loopwire-debug-*' -print -quit)"
if [ -z "$package_file" ]; then
  echo "makepkg did not produce a loopwire package archive." >&2
  exit 1
fi

namcap_log="$tmp_dir/namcap.log"
namcap "$build_dir/PKGBUILD" "$package_file" | tee "$namcap_log"
if grep -Fq " E: " "$namcap_log"; then
  echo "namcap reported an error for the loopwire source package." >&2
  exit 1
fi

package_members="$tmp_dir/package-members.txt"
tar -tf "$package_file" >"$package_members"
for member in \
  usr/bin/loopwire \
  usr/bin/loopwire-dsp-provider \
  usr/bin/loopwire-jack-ports \
  usr/bin/loopwire-detect-audio \
  usr/lib/loopwire/loopwire-gui \
  usr/lib/loopwire/scripts/restore-background.mjs \
  usr/share/applications/loopwire.desktop \
  usr/share/icons/hicolor/scalable/apps/loopwire.svg; do
  grep -Fxq "$member" "$package_members" || {
    echo "AUR source package does not contain $member." >&2
    exit 1
  }
done

echo "AUR source package build passed for ${version}."
