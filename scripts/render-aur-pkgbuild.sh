#!/usr/bin/env bash
set -euo pipefail

version=""
release_dir=""
output_path=""
template_path="packaging/aur/PKGBUILD.in"

usage() {
  cat <<'USAGE'
Render packaging/aur/PKGBUILD.in with concrete version, checksums, and optional local artifact URLs.

Usage:
  render-aur-pkgbuild.sh --version VERSION --release-dir DIR --output PATH

The release directory must contain:
  loopwire-linux-x86_64.tar.gz
  loopwire-linux-aarch64.tar.gz
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      version="${2:?missing value for --version}"
      shift 2
      ;;
    --release-dir)
      release_dir="${2:?missing value for --release-dir}"
      shift 2
      ;;
    --output)
      output_path="${2:?missing value for --output}"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$version" ] || [ -z "$release_dir" ] || [ -z "$output_path" ]; then
  usage >&2
  exit 2
fi

if [ ! -f "$template_path" ]; then
  echo "Missing template: $template_path" >&2
  exit 1
fi

release_dir="${release_dir%/}"
x86_asset="$release_dir/loopwire-linux-x86_64.tar.gz"
aarch64_asset="$release_dir/loopwire-linux-aarch64.tar.gz"

if [ ! -f "$x86_asset" ] || [ ! -f "$aarch64_asset" ]; then
  echo "Release directory must contain x86_64 and aarch64 tarballs: $release_dir" >&2
  exit 1
fi

x86_hash="$(sha256sum "$x86_asset" | awk '{ print $1 }')"
aarch64_hash="$(sha256sum "$aarch64_asset" | awk '{ print $1 }')"
release_dir_abs="$(cd "$release_dir" && pwd -P)"
tmp_output="$(mktemp)"
rendered_output="$(mktemp)"
cleanup() {
  rm -f "$tmp_output" "$rendered_output"
}
trap cleanup EXIT

sed \
  -e "s/@VERSION@/${version}/g" \
  -e "s/@SHA256_X86_64@/${x86_hash}/g" \
  -e "s/@SHA256_AARCH64@/${aarch64_hash}/g" \
  "$template_path" >"$tmp_output"

awk -v release_dir="$release_dir_abs" '
  /^source_x86_64=/ {
    print "source_x86_64=(\"loopwire-linux-x86_64.tar.gz::file://" release_dir "/loopwire-linux-x86_64.tar.gz\")"
    next
  }
  /^source_aarch64=/ {
    print "source_aarch64=(\"loopwire-linux-aarch64.tar.gz::file://" release_dir "/loopwire-linux-aarch64.tar.gz\")"
    next
  }
  { print }
' "$tmp_output" >"$rendered_output"

mkdir -p "$(dirname "$output_path")"
cp "$rendered_output" "$output_path"
echo "Rendered $output_path"
