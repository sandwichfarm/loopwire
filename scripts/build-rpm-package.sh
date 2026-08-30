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
Build a reproducible Loopwire RPM from the canonical release tarball.

Usage:
  build-rpm-package.sh --target fedora-44|opensuse-tumbleweed --version VERSION \
    --arch x86_64|aarch64 --release-dir DIR [--output-dir DIR]

Requires rpmbuild and rpm. The release directory must contain the architecture tarball and SHA256SUMS.
USAGE
}

fail() {
  echo "build-rpm-package: $*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
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
command -v rpmbuild >/dev/null 2>&1 || fail "rpmbuild is required"
command -v rpm >/dev/null 2>&1 || fail "rpm is required"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required"

case "$version" in
  *[!0-9A-Za-z.+~_-]* | "" | *$'\n'* | *$'\r'*) fail "invalid version: $version" ;;
esac
case "$source_date_epoch" in
  *[!0-9]* | "") fail "SOURCE_DATE_EPOCH must be an integer" ;;
esac
case "$arch" in
  x86_64) release_arch="x86_64"; rpm_arch="x86_64" ;;
  aarch64) release_arch="aarch64"; rpm_arch="aarch64" ;;
  *) fail "unsupported architecture: $arch" ;;
esac
case "$target" in
  fedora-44) template="packaging/rpm/fedora-44.spec.in" ;;
  opensuse-tumbleweed) template="packaging/rpm/opensuse-tumbleweed.spec.in" ;;
  *) fail "unsupported RPM target: $target" ;;
esac

asset="loopwire-linux-${release_arch}.tar.gz"
archive="${release_dir%/}/$asset"
checksums="${release_dir%/}/SHA256SUMS"
[ -f "$template" ] || fail "missing RPM spec template: $template"
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

mkdir -p "$tmp_dir/preflight"
bash scripts/extract-safe-tar.sh \
  --archive "$archive" \
  --output-dir "$tmp_dir/preflight" \
  --label "Loopwire release archive" >/dev/null

topdir="$tmp_dir/rpmbuild"
mkdir -p "$topdir"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
cp "$archive" "$topdir/SOURCES/$asset"
cp packaging/common/loopwire.desktop "$topdir/SOURCES/loopwire.desktop"
cp apps/desktop/src-tauri/icons/icon.svg "$topdir/SOURCES/loopwire.svg"

rendered_spec="$topdir/SPECS/loopwire.spec"
sed \
  -e "s/@VERSION@/${version}/g" \
  -e "s/@RELEASE_ARCH@/${release_arch}/g" \
  -e "s/@RPM_ARCH@/${rpm_arch}/g" \
  "$template" >"$rendered_spec"

SOURCE_DATE_EPOCH="$source_date_epoch" rpmbuild \
  --define "_topdir $topdir" \
  --define "_source_date_epoch $source_date_epoch" \
  --define "use_source_date_epoch_as_buildtime 1" \
  -bb "$rendered_spec" >/dev/null

mapfile -t packages < <(find "$topdir/RPMS" -type f -name '*.rpm' | sort)
[ "${#packages[@]}" -eq 1 ] || fail "expected exactly one built RPM, found ${#packages[@]}"
mkdir -p "$output_dir"
output="${output_dir%/}/$(basename "${packages[0]}")"
cp "${packages[0]}" "$output"
rpm -qp "$output" >/dev/null
rpm -qlp "$output" | grep -Fxq '/usr/bin/loopwire-detect-audio' ||
  fail "built package is missing /usr/bin/loopwire-detect-audio"

echo "Wrote $output"
