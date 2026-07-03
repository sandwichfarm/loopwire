#!/usr/bin/env bash
set -euo pipefail

repo="${LOOPWIRE_GITHUB_REPO:-}"
tag="${LOOPWIRE_RELEASE_TAG:-}"
prefix=""
public_key="${LOOPWIRE_RELEASE_PUBLIC_KEY:-packaging/release-signing-public.pem}"
release_dir=""
release_source="github"

usage() {
  cat <<'USAGE'
Verify a published Loopwire GitHub Release.

Usage:
  verify-published-release.sh --repo OWNER/REPO --tag vX.Y.Z --public-key FILE [--prefix DIR]
  verify-published-release.sh --release-dir DIR --public-key FILE [--prefix DIR]

Downloads release assets with gh, verifies both canonical Linux tarballs are present in the signed SHA256SUMS manifest,
installs the host tarball from the downloaded release directory, and runs the installed binary. Use --release-dir for CI
smoke coverage of the same verification path without network or GitHub release access.
USAGE
}

fail() {
  echo "verify-published-release: $*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --)
      shift
      ;;
    --repo)
      repo="${2:-}"
      shift 2
      ;;
    --tag)
      tag="${2:-}"
      shift 2
      ;;
    --public-key)
      public_key="${2:-}"
      shift 2
      ;;
    --prefix)
      prefix="${2:-}"
      shift 2
      ;;
    --release-dir)
      release_dir="${2:-}"
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

[ -n "$release_dir" ] || [ -n "$repo" ] || fail "missing --repo OWNER/REPO or --release-dir DIR"
[ -n "$release_dir" ] || [ -n "$tag" ] || fail "missing --tag vX.Y.Z"
[ -f "$public_key" ] || fail "missing public key: $public_key"
command -v openssl >/dev/null 2>&1 || fail "openssl is required"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required"

required_assets=(
  "loopwire-linux-x86_64.tar.gz"
  "loopwire-linux-aarch64.tar.gz"
)

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

install_prefix="${prefix:-$tmp_dir/prefix}"
mkdir -p "$install_prefix"

if [ -n "$release_dir" ]; then
  release_source="directory"
  [ -d "$release_dir" ] || fail "release directory does not exist: $release_dir"
  release_dir="$(cd "$release_dir" && pwd -P)"
else
  command -v gh >/dev/null 2>&1 || fail "gh is required"
  release_dir="$tmp_dir/release"
  mkdir -p "$release_dir"
  gh release view "$tag" --repo "$repo" >/dev/null
  gh release download "$tag" --repo "$repo" --dir "$release_dir" --clobber
fi

shopt -s nullglob
tarballs=("$release_dir"/loopwire-linux-*.tar.gz)
shopt -u nullglob
[ "${#tarballs[@]}" -gt 0 ] || fail "release directory has no loopwire-linux-*.tar.gz assets: $release_dir"

for asset in "${required_assets[@]}"; do
  [ -f "$release_dir/$asset" ] || fail "release directory is missing required asset: $asset"
done

bash scripts/verify-release-signature.sh --release-dir "$release_dir" --public-key "$public_key" >/dev/null
for asset in "${required_assets[@]}"; do
  awk -v asset="$asset" '$2 == asset { found = 1 } END { exit found ? 0 : 1 }' "$release_dir/SHA256SUMS" \
    || fail "SHA256SUMS is missing required asset entry: $asset"
done
(
  cd "$release_dir"
  sha256sum --check SHA256SUMS >/dev/null
)
bash scripts/install.sh --base-url "file://$release_dir" --prefix "$install_prefix" --public-key "$public_key" >/dev/null

"$install_prefix/loopwire" >/dev/null
"$install_prefix/loopwire" --background --help | grep -F -- "--state-file" >/dev/null
if [ "$release_source" = "github" ]; then
  echo "Published release verification passed for $repo@$tag."
else
  echo "Published release verification passed for $release_dir."
fi
