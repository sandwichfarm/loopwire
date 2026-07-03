#!/usr/bin/env bash
set -euo pipefail

release_dir=""
public_key_file=""

usage() {
  cat <<'USAGE'
Verify a Loopwire release SHA256SUMS signature.

Usage:
  verify-release-signature.sh --release-dir DIR --public-key FILE
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --release-dir)
      release_dir="${2:?missing value for --release-dir}"
      shift 2
      ;;
    --public-key)
      public_key_file="${2:?missing value for --public-key}"
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

if [ -z "$release_dir" ] || [ -z "$public_key_file" ]; then
  usage >&2
  exit 2
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "OpenSSL is required to verify release signatures." >&2
  exit 1
fi

if [ ! -f "$release_dir/SHA256SUMS" ]; then
  echo "Missing SHA256SUMS in release directory: $release_dir" >&2
  exit 1
fi

if [ ! -f "$release_dir/SHA256SUMS.sig" ]; then
  echo "Missing SHA256SUMS.sig in release directory: $release_dir" >&2
  exit 1
fi

if [ ! -f "$public_key_file" ]; then
  echo "Release public key does not exist: $public_key_file" >&2
  exit 1
fi

openssl dgst -sha256 \
  -verify "$public_key_file" \
  -signature "$release_dir/SHA256SUMS.sig" \
  "$release_dir/SHA256SUMS"
