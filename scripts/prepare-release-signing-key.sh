#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
private_key_out=""
public_key_out="$root/packaging/release-signing-public.pem"
force="false"

usage() {
  cat <<'USAGE'
Prepare Loopwire release signing keys.

Usage:
  prepare-release-signing-key.sh --private-key-out FILE [--public-key-out FILE] [--force]

This script generates a 3072-bit RSA private key, derives the public key, verifies that the pair can sign
SHA256SUMS-style data, and prints the GitHub secret setup command. It never uploads secrets.

Safety:
  - The private key output path is required.
  - The private key must be outside the repository.
  - Existing key files are not overwritten unless --force is passed.
  - Commit only the public key. Keep the private key out of git.
USAGE
}

fail() {
  echo "prepare-release-signing-key: $*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --)
      shift
      ;;
    --private-key-out)
      private_key_out="${2:-}"
      shift 2
      ;;
    --public-key-out)
      public_key_out="${2:-}"
      shift 2
      ;;
    --force)
      force="true"
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

[ -n "$private_key_out" ] || {
  usage >&2
  exit 2
}
command -v openssl >/dev/null 2>&1 || fail "openssl is required"

canonical_path() {
  local path="$1"
  local dir
  local base

  dir="$(dirname "$path")"
  base="$(basename "$path")"
  mkdir -p "$dir"
  printf '%s/%s\n' "$(cd "$dir" && pwd -P)" "$base"
}

private_key_path="$(canonical_path "$private_key_out")"
public_key_path="$(canonical_path "$public_key_out")"

case "$private_key_path" in
  "$root" | "$root"/*)
    fail "private key must be outside the repository: $private_key_path"
    ;;
esac

for output in "$private_key_path" "$public_key_path"; do
  if [ -e "$output" ] && [ "$force" != "true" ]; then
    fail "refusing to overwrite existing file without --force: $output"
  fi
done

umask 077
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out "$private_key_path" >/dev/null 2>&1
openssl pkey -in "$private_key_path" -pubout -out "$public_key_path" >/dev/null 2>&1
chmod 0600 "$private_key_path"
chmod 0644 "$public_key_path"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
printf '%s\n' "loopwire release signing smoke" >"$tmp_dir/SHA256SUMS"
openssl dgst -sha256 -sign "$private_key_path" -out "$tmp_dir/SHA256SUMS.sig" "$tmp_dir/SHA256SUMS"
openssl dgst -sha256 -verify "$public_key_path" -signature "$tmp_dir/SHA256SUMS.sig" "$tmp_dir/SHA256SUMS" \
  >/dev/null

cat <<EOF
Release signing key pair prepared.

Private key: $private_key_path
Public key:  $public_key_path

Next steps:
  1. Commit only the public key: $public_key_path
  2. Store final-proof GitHub secrets from local values; do not print or commit secret values:
     bash scripts/setup-github-secrets.sh --repo OWNER/REPO --scope final \\
       --storage-zone <zone> --access-key <key> --pull-zone-hostname <host> \\
       --release-private-key-file "$private_key_path" \\
       --release-public-key-file "$public_key_path"
     # Or create, fill, and load the local no-value env template:
     bash scripts/setup-github-secrets.sh --write-env-template <secret-env-file>
     bash scripts/setup-github-secrets.sh --repo OWNER/REPO --scope final --env-file <secret-env-file>
  3. Re-run release readiness:
     pnpm verify:release-readiness -- --repo OWNER/REPO --tag v0.1.0 --public-key "$public_key_path"
EOF
