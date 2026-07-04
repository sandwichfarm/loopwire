#!/usr/bin/env bash
set -euo pipefail

version=""
release_dir=""
public_key=""
skip_missing_nix="false"
render_only="false"

usage() {
  cat <<'USAGE'
Verify the Loopwire Nix binary package against a release directory.

Usage:
  verify-nix-release-package.sh --version VERSION --release-dir DIR [--public-key FILE]
  verify-nix-release-package.sh --version VERSION --release-dir DIR --skip-build-if-missing-nix
  verify-nix-release-package.sh --version VERSION --release-dir DIR --render-only

This command renders a concrete Nix package expression from SHA256SUMS, then runs nix build when nix is available.
Without --skip-build-if-missing-nix, a host without nix fails closed.
Use --render-only only for metadata smoke tests with local fake artifacts.
USAGE
}

fail() {
  echo "verify-nix-release-package: $*" >&2
  exit 1
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
    --public-key)
      public_key="${2:?missing value for --public-key}"
      shift 2
      ;;
    --skip-build-if-missing-nix)
      skip_missing_nix="true"
      shift
      ;;
    --render-only)
      render_only="true"
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

[ -n "$version" ] || fail "missing --version VERSION"
[ -n "$release_dir" ] || fail "missing --release-dir DIR"
[ -d "$release_dir" ] || fail "missing release directory: $release_dir"

project_root="$(pwd -P)"
tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

rendered_package="$tmp_dir/loopwire-bin-release.nix"
render_args=(
  --version "$version"
  --release-dir "$release_dir"
  --output "$rendered_package"
)
if [ -n "$public_key" ]; then
  render_args+=(--public-key "$public_key")
fi

bash scripts/render-nix-release-package.sh "${render_args[@]}" >/dev/null

if [ "$render_only" = "true" ]; then
  echo "Nix release package render-only check passed for Loopwire $version."
  exit 0
fi

if ! command -v nix >/dev/null 2>&1; then
  if [ "$skip_missing_nix" = "true" ]; then
    echo "skipped: nix is not available; Nix package render step passed for Loopwire $version."
    exit 0
  fi
  fail "nix is required for build proof; rerun with --skip-build-if-missing-nix only for wiring checks"
fi

nix build \
  -f "$rendered_package" \
  --arg loopwireSrc "$project_root" \
  --no-link

echo "Nix release package build passed for Loopwire $version."
