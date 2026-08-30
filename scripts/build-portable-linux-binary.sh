#!/usr/bin/env bash
set -euo pipefail

output="dist/portable/loopwire"
image_tag="loopwire-portable-build:bookworm"

usage() {
  cat <<'USAGE'
Build the Loopwire GUI binary on the Debian 12 glibc baseline recommended for Tauri Linux compatibility.

Usage:
  build-portable-linux-binary.sh [--output FILE] [--image-tag TAG]

Requires Docker with BuildKit. The repository is copied into an isolated multi-stage build; host toolchains and
node_modules are not used.
USAGE
}

fail() {
  echo "build-portable-linux-binary: $*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --output) output="${2:?missing value for --output}"; shift 2 ;;
    --image-tag) image_tag="${2:?missing value for --image-tag}"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

command -v docker >/dev/null 2>&1 || fail "docker is required"
case "$output" in
  "" | / | */ | *$'\n'* | *$'\r'*) fail "--output must name a file" ;;
esac

tmp_dir="$(mktemp -d)"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT

DOCKER_BUILDKIT=1 docker build \
  --file packaging/vm/Dockerfile.portable-build \
  --target export \
  --tag "$image_tag" \
  --output "type=local,dest=$tmp_dir/export" \
  .

[ -x "$tmp_dir/export/loopwire" ] || fail "Docker build did not export an executable Loopwire binary"
mkdir -p "$(dirname "$output")"
install -m 0755 "$tmp_dir/export/loopwire" "$output"
file "$output" | grep -Fq 'ELF 64-bit' || fail "exported binary is not a 64-bit Linux ELF"

echo "Wrote portable Loopwire binary: $output"
