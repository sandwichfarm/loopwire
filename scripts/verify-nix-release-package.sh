#!/usr/bin/env bash
set -euo pipefail

version=""
repo="${LOOPWIRE_GITHUB_REPO:-}"
tag="${LOOPWIRE_RELEASE_TAG:-}"
release_dir=""
public_key=""
skip_missing_nix="false"
render_only="false"

usage() {
  cat <<'USAGE'
Verify the Loopwire Nix binary package against a release directory.

Usage:
  verify-nix-release-package.sh --version VERSION --release-dir DIR [--public-key FILE]
  verify-nix-release-package.sh --repo OWNER/REPO --tag vX.Y.Z --public-key FILE
  verify-nix-release-package.sh --version VERSION --release-dir DIR --skip-build-if-missing-nix
  verify-nix-release-package.sh --version VERSION --release-dir DIR --render-only

This command renders a concrete Nix package expression from SHA256SUMS, then runs nix build when nix is available.
Without --skip-build-if-missing-nix, a host without nix fails closed.
Use --render-only only for metadata smoke tests with local fake artifacts.
When --repo and --tag are used, release assets are downloaded from GitHub with gh before rendering.
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
    --repo)
      repo="${2:?missing value for --repo}"
      shift 2
      ;;
    --tag)
      tag="${2:?missing value for --tag}"
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

[ -n "$release_dir" ] || [ -n "$repo" ] || fail "missing --release-dir DIR or --repo OWNER/REPO"
if [ -n "$release_dir" ] && [ -n "$repo" ]; then
  fail "use either --release-dir or --repo/--tag, not both"
fi
if [ -n "$repo" ]; then
  [ -n "$tag" ] || fail "missing --tag vX.Y.Z"
  [ -n "$public_key" ] || fail "missing --public-key FILE for published release verification"
  repo_pattern='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
  if [[ ! "$repo" =~ $repo_pattern ]]; then
    fail "repository must use OWNER/REPO without URLs, spaces, or extra path segments: $repo"
  fi
  tag_pattern='^v[0-9]+[.][0-9]+[.][0-9]+([.-][0-9A-Za-z][0-9A-Za-z.-]*)?$'
  [[ "$tag" =~ $tag_pattern ]] || fail "tag must be v-prefixed semver without path separators: $tag"
  [ -n "$version" ] || version="${tag#v}"
fi
[ -n "$version" ] || fail "missing --version VERSION"
if [ -n "$release_dir" ]; then
  [ -d "$release_dir" ] || fail "missing release directory: $release_dir"
fi

project_root="$(pwd -P)"
tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

if [ -n "$repo" ]; then
  command -v gh >/dev/null 2>&1 || fail "gh is required to download release assets"
  release_dir="$tmp_dir/release"
  mkdir -p "$release_dir"
  gh release view "$tag" --repo "$repo" >/dev/null
  gh release download "$tag" --repo "$repo" --dir "$release_dir" --clobber
fi

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
