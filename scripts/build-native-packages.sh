#!/usr/bin/env bash
set -euo pipefail

target="all"
version=""
arch="x86_64"
release_dir=""
output_dir="dist/native-packages"
source_date_epoch="${SOURCE_DATE_EPOCH:-0}"

usage() {
  cat <<'USAGE'
Build Loopwire native packages with each target distribution's own package toolchain.

Usage:
  build-native-packages.sh --version VERSION --release-dir DIR [--target TARGET|all]
    [--arch x86_64] [--output-dir DIR]

Targets: ubuntu-24.04, debian-13, fedora-44, opensuse-tumbleweed, all.
Requires Docker. The target containers receive the repository and canonical release directory read-only; only the
output directory is writable.
USAGE
}

fail() {
  echo "build-native-packages: $*" >&2
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

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.+~_-][0-9A-Za-z.+~_-]+)?$ ]] ||
  fail "--version must be SemVer-compatible package text"
[ "$arch" = "x86_64" ] || fail "native distro packages are currently verified only for x86_64"
[ -d "$release_dir" ] || fail "release directory does not exist: $release_dir"
[ -f "$release_dir/loopwire-linux-x86_64.tar.gz" ] || fail "canonical release tarball is missing"
[ -f "$release_dir/SHA256SUMS" ] || fail "release checksum manifest is missing"
case "$source_date_epoch" in *[!0-9]* | "") fail "SOURCE_DATE_EPOCH must be an integer" ;; esac
case "$target" in
  all | ubuntu-24.04 | debian-13 | fedora-44 | opensuse-tumbleweed) ;;
  *) fail "unsupported target: $target" ;;
esac
command -v docker >/dev/null 2>&1 || fail "docker is required"
docker info >/dev/null 2>&1 || fail "docker daemon is unavailable"

root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$root" ] || fail "run from inside the Loopwire git repository"
release_dir="$(realpath "$release_dir")"
mkdir -p "$output_dir"
output_dir="$(realpath "$output_dir")"

build_target() {
  local selected="$1" image family
  case "$selected" in
    ubuntu-24.04) image="ubuntu:24.04"; family="apt" ;;
    debian-13) image="debian:13"; family="apt" ;;
    fedora-44) image="fedora:44"; family="dnf" ;;
    opensuse-tumbleweed) image="opensuse/tumbleweed"; family="zypper" ;;
  esac

  docker run --rm \
    -e HOST_UID="$(id -u)" \
    -e HOST_GID="$(id -g)" \
    -e LOOPWIRE_PACKAGE_ARCH="$arch" \
    -e LOOPWIRE_PACKAGE_FAMILY="$family" \
    -e LOOPWIRE_PACKAGE_TARGET="$selected" \
    -e LOOPWIRE_PACKAGE_VERSION="$version" \
    -e SOURCE_DATE_EPOCH="$source_date_epoch" \
    -v "$root:/src:ro" \
    -v "$release_dir:/release:ro" \
    -v "$output_dir:/out" \
    -w /src \
    "$image" bash -lc '
      set -euo pipefail
      case "$LOOPWIRE_PACKAGE_FAMILY" in
        apt)
          apt-get update >/dev/null
          DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends dpkg-dev xz-utils >/dev/null
          bash scripts/build-deb-package.sh \
            --target "$LOOPWIRE_PACKAGE_TARGET" \
            --version "$LOOPWIRE_PACKAGE_VERSION" \
            --arch "$LOOPWIRE_PACKAGE_ARCH" \
            --release-dir /release \
            --output-dir /out >/dev/null
          ;;
        dnf)
          dnf install -y rpm-build tar gzip findutils >/dev/null
          bash scripts/build-rpm-package.sh \
            --target "$LOOPWIRE_PACKAGE_TARGET" \
            --version "$LOOPWIRE_PACKAGE_VERSION" \
            --arch "$LOOPWIRE_PACKAGE_ARCH" \
            --release-dir /release \
            --output-dir /out >/dev/null
          ;;
        zypper)
          zypper --non-interactive install rpm-build tar gzip findutils >/dev/null
          bash scripts/build-rpm-package.sh \
            --target "$LOOPWIRE_PACKAGE_TARGET" \
            --version "$LOOPWIRE_PACKAGE_VERSION" \
            --arch "$LOOPWIRE_PACKAGE_ARCH" \
            --release-dir /release \
            --output-dir /out >/dev/null
          ;;
      esac
      chown -R "$HOST_UID:$HOST_GID" /out
    '
  echo "Built native package with $selected toolchain."
}

if [ "$target" = "all" ]; then
  for selected in ubuntu-24.04 debian-13 fedora-44 opensuse-tumbleweed; do
    build_target "$selected"
  done
else
  build_target "$target"
fi
