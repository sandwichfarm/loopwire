#!/usr/bin/env bash
set -euo pipefail

target=""
version=""
arch=""
release_dir=""
output_dir="dist/native-packages"
source_date_epoch="${SOURCE_DATE_EPOCH:-0}"

usage() {
  cat <<'USAGE'
Build a reproducible Loopwire .deb from the canonical release tarball.

Usage:
  build-deb-package.sh --target ubuntu-24.04|debian-13 --version VERSION \
    --arch x86_64|aarch64 --release-dir DIR [--output-dir DIR]

Requires dpkg-deb. The release directory must contain the architecture tarball and SHA256SUMS.
USAGE
}

fail() {
  echo "build-deb-package: $*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --) shift ;;
    --target) target="${2:?missing value for --target}"; shift 2 ;;
    --version) version="${2:?missing value for --version}"; shift 2 ;;
    --arch) arch="${2:?missing value for --arch}"; shift 2 ;;
    --release-dir) release_dir="${2:?missing value for --release-dir}"; shift 2 ;;
    --output-dir) output_dir="${2:?missing value for --output-dir}"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[ -n "$target" ] || fail "missing --target"
[ -n "$version" ] || fail "missing --version"
[ -n "$arch" ] || fail "missing --arch"
[ -n "$release_dir" ] || fail "missing --release-dir"
command -v dpkg-deb >/dev/null 2>&1 || fail "dpkg-deb is required"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required"

case "$version" in
  *[!0-9A-Za-z.+~_-]* | "" | *$'\n'* | *$'\r'*) fail "invalid version: $version" ;;
esac
case "$source_date_epoch" in
  *[!0-9]* | "") fail "SOURCE_DATE_EPOCH must be an integer" ;;
esac

case "$arch" in
  x86_64) release_arch="x86_64"; deb_arch="amd64" ;;
  aarch64) release_arch="aarch64"; deb_arch="arm64" ;;
  *) fail "unsupported architecture: $arch" ;;
esac

case "$target" in
  ubuntu-24.04)
    template="packaging/deb/ubuntu-24.04.control.in"
    package_version="${version}-1ubuntu24.04"
    ;;
  debian-13)
    template="packaging/deb/debian-13.control.in"
    package_version="${version}-1debian13"
    ;;
  *) fail "unsupported Debian-family target: $target" ;;
esac

asset="loopwire-linux-${release_arch}.tar.gz"
archive="${release_dir%/}/$asset"
checksums="${release_dir%/}/SHA256SUMS"
[ -f "$template" ] || fail "missing control template: $template"
[ -f "$archive" ] || fail "missing release archive: $archive"
[ -f "$checksums" ] || fail "missing release checksum manifest: $checksums"

entry_count="$(awk -v asset="$asset" '$2 == asset { count++ } END { print count + 0 }' "$checksums")"
[ "$entry_count" -eq 1 ] || fail "SHA256SUMS must contain exactly one entry for $asset"
(
  cd "$release_dir"
  awk -v asset="$asset" '$2 == asset { print }' SHA256SUMS | sha256sum --check --strict >/dev/null
) || fail "release archive checksum failed: $asset"

tmp_dir="$(mktemp -d)"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT

payload="$tmp_dir/payload"
package_root="$tmp_dir/package-root"
mkdir -p "$payload" "$package_root/DEBIAN" "$package_root/usr/bin" "$package_root/usr/lib/loopwire"
bash scripts/extract-safe-tar.sh --archive "$archive" --output-dir "$payload" --label "Loopwire release archive"

for launcher in loopwire loopwire-dsp-provider loopwire-jack-ports loopwire-detect-audio; do
  [ -x "$payload/$launcher" ] || fail "release archive is missing executable $launcher"
  install -m 0755 "$payload/$launcher" "$package_root/usr/bin/$launcher"
done
cp -a "$payload/libexec/loopwire/." "$package_root/usr/lib/loopwire/"
find "$package_root/usr/lib/loopwire" -type d -exec chmod 0755 {} +
find "$package_root/usr/lib/loopwire" -type f -exec chmod 0644 {} +
chmod 0755 "$package_root/usr/lib/loopwire/loopwire-gui"

install -Dm0644 packaging/common/loopwire.desktop \
  "$package_root/usr/share/applications/loopwire.desktop"
install -Dm0644 apps/desktop/src-tauri/icons/icon.svg \
  "$package_root/usr/share/icons/hicolor/scalable/apps/loopwire.svg"

installed_size="$(du -sk "$package_root/usr" | awk '{ print $1 }')"
sed \
  -e "s/@PACKAGE_VERSION@/${package_version}/g" \
  -e "s/@DEB_ARCH@/${deb_arch}/g" \
  -e "s/@INSTALLED_SIZE@/${installed_size}/g" \
  "$template" >"$package_root/DEBIAN/control"

find "$package_root" -print0 | xargs -0 touch -h -d "@${source_date_epoch}"
mkdir -p "$output_dir"
output="${output_dir%/}/loopwire_${package_version}_${deb_arch}.deb"
SOURCE_DATE_EPOCH="$source_date_epoch" dpkg-deb --root-owner-group --build "$package_root" "$output" >/dev/null
dpkg-deb --info "$output" >/dev/null
dpkg-deb --contents "$output" >"$tmp_dir/package-contents.txt"
grep -Fq './usr/bin/loopwire-detect-audio' "$tmp_dir/package-contents.txt" ||
  fail "built package is missing loopwire-detect-audio"

echo "Wrote $output"
