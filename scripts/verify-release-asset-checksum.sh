#!/usr/bin/env bash
set -euo pipefail

release_dir=""
asset=""
public_key=""
label="release asset"

usage() {
  cat <<'USAGE'
Verify that one release asset is covered by signed SHA256SUMS.

Usage:
  verify-release-asset-checksum.sh --release-dir DIR --asset NAME --public-key FILE [--label NAME]

The release directory must contain the asset, SHA256SUMS, and SHA256SUMS.sig. The asset name must be a basename.
USAGE
}

fail() {
  echo "verify-release-asset-checksum: $*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --release-dir)
      release_dir="${2:?missing value for --release-dir}"
      shift 2
      ;;
    --asset)
      asset="${2:?missing value for --asset}"
      shift 2
      ;;
    --public-key)
      public_key="${2:?missing value for --public-key}"
      shift 2
      ;;
    --label)
      label="${2:?missing value for --label}"
      shift 2
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

[ -n "$release_dir" ] || fail "missing --release-dir DIR"
[ -n "$asset" ] || fail "missing --asset NAME"
[ -n "$public_key" ] || fail "missing --public-key FILE"

case "$asset" in
  "" | /* | *"/"* | *"\\"* | *".."* | *":"* | -* | .* | *$'\n'* | *$'\r'*)
    fail "${label} name must be a safe basename: $asset"
    ;;
esac

[ -d "$release_dir" ] || fail "missing release directory: $release_dir"
[ -f "$release_dir/$asset" ] || fail "missing ${label}: $release_dir/$asset"
[ -f "$release_dir/SHA256SUMS" ] || fail "missing SHA256SUMS in release directory: $release_dir"
[ -f "$release_dir/SHA256SUMS.sig" ] || fail "missing SHA256SUMS.sig in release directory: $release_dir"
[ -f "$public_key" ] || fail "missing public key: $public_key"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required"

bash scripts/verify-release-signature.sh \
  --release-dir "$release_dir" \
  --public-key "$public_key" >/dev/null

entry_count="$(awk -v asset="$asset" '$2 == asset { count++ } END { print count + 0 }' "$release_dir/SHA256SUMS")"
case "$entry_count" in
  1)
    ;;
  0)
    fail "SHA256SUMS is missing ${label} entry: $asset"
    ;;
  *)
    fail "SHA256SUMS has duplicate ${label} entries: $asset"
    ;;
esac

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

awk -v asset="$asset" '$2 == asset { print }' "$release_dir/SHA256SUMS" >"$tmp_dir/SHA256SUMS"
(
  cd "$release_dir"
  sha256sum --check "$tmp_dir/SHA256SUMS" >/dev/null
)

printf 'Verified signed checksum for %s: %s\n' "$label" "$asset"
