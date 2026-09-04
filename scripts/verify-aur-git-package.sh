#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version=""
default_branch=""

usage() {
  cat <<'USAGE'
Build and inspect the rolling loopwire-git AUR package.

Usage:
  verify-aur-git-package.sh [--version VERSION] [--default-branch BRANCH]

VERSION seeds PKGBUILD before makepkg refreshes it through pkgver(). By default
it is derived from the newest tagged commit reachable from the default branch.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --) shift ;;
    --version) version="${2:?missing value for --version}"; shift 2 ;;
    --default-branch) default_branch="${2:?missing value for --default-branch}"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v makepkg >/dev/null 2>&1 || {
  echo "makepkg not found; loopwire-git verification requires Arch Linux." >&2
  exit 1
}
command -v namcap >/dev/null 2>&1 || {
  echo "namcap not found; loopwire-git verification requires namcap." >&2
  exit 1
}

if [ -z "$default_branch" ]; then
  default_branch="$(git -C "$root" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"
  default_branch="${default_branch#origin/}"
fi
git check-ref-format --branch "$default_branch" >/dev/null 2>&1 || {
  echo "Could not resolve a valid default branch; pass --default-branch." >&2
  exit 2
}
if [ -z "$version" ]; then
  version="$(
    git -C "$root" describe --long --tags --abbrev=7 "origin/$default_branch" 2>/dev/null |
      sed 's/^v//;s/\([^-]*-g\)/r\1/;s/-/./g'
  )"
fi
if [[ ! "$version" =~ ^[0-9]+([.][0-9]+)*[.]r[0-9]+[.]g[0-9a-f]+$ ]]; then
  echo "loopwire-git version must look like 1.2.3.r4.gabcdef0: $version" >&2
  exit 2
fi

tmp_dir="$(mktemp -d -t loopwire-aur-git.XXXXXXXX)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

build_dir="$tmp_dir/build"
mkdir -p "$build_dir"
bash "$root/scripts/render-aur-pkgbuild.sh" \
  --package loopwire-git \
  --version "$version" \
  --default-branch "$default_branch" \
  --pkgrel 1 \
  --output "$build_dir/PKGBUILD" >/dev/null
cp "$root/packaging/aur/LICENSE-MIT" "$build_dir/LICENSE-MIT"

(
  cd "$build_dir"
  makepkg --force --nodeps --noconfirm --cleanbuild --clean
)

actual_version="$(awk -F= '$1 == "pkgver" { print $2; exit }' "$build_dir/PKGBUILD")"
if [[ ! "$actual_version" =~ ^[0-9]+([.][0-9]+)*[.]r[0-9]+[.]g[0-9a-f]+$ ]]; then
  echo "makepkg did not write a valid VCS pkgver: $actual_version" >&2
  exit 1
fi
package_file="$(find "$build_dir" -maxdepth 1 -type f -name 'loopwire-git-*.pkg.tar.*' ! -name 'loopwire-git-debug-*' -print -quit)"
if [ -z "$package_file" ]; then
  echo "makepkg did not produce a loopwire-git package archive." >&2
  exit 1
fi

namcap_log="$tmp_dir/namcap.log"
namcap "$build_dir/PKGBUILD" "$package_file" | tee "$namcap_log"
if grep -Fq " E: " "$namcap_log"; then
  echo "namcap reported an error for loopwire-git." >&2
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
  usr/share/icons/hicolor/scalable/apps/loopwire.svg \
  usr/share/licenses/loopwire-git/LICENSE-MIT; do
  grep -Fxq "$member" "$package_members" || {
    echo "loopwire-git package does not contain $member." >&2
    exit 1
  }
done

echo "AUR loopwire-git package build passed for ${actual_version}."
