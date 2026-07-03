#!/usr/bin/env bash
set -euo pipefail

release_dir=""
private_key_file=""

usage() {
  cat <<'USAGE'
Sign a Loopwire release SHA256SUMS file.

Usage:
  sign-release-artifacts.sh --release-dir DIR --private-key FILE

Writes:
  DIR/SHA256SUMS.sig
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --release-dir)
      release_dir="${2:?missing value for --release-dir}"
      shift 2
      ;;
    --private-key)
      private_key_file="${2:?missing value for --private-key}"
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

if [ -z "$release_dir" ] || [ -z "$private_key_file" ]; then
  usage >&2
  exit 2
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "OpenSSL is required to sign release artifacts." >&2
  exit 1
fi

if [ ! -f "$release_dir/SHA256SUMS" ]; then
  echo "Missing SHA256SUMS in release directory: $release_dir" >&2
  exit 1
fi

if [ ! -f "$private_key_file" ]; then
  echo "Release private key does not exist: $private_key_file" >&2
  exit 1
fi

openssl dgst -sha256 \
  -sign "$private_key_file" \
  -out "$release_dir/SHA256SUMS.sig" \
  "$release_dir/SHA256SUMS"

echo "Signed $release_dir/SHA256SUMS"
