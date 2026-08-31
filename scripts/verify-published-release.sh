#!/usr/bin/env bash
set -euo pipefail

repo="${LOOPWIRE_GITHUB_REPO:-}"
tag="${LOOPWIRE_RELEASE_TAG:-}"
prefix=""
public_key="${LOOPWIRE_RELEASE_PUBLIC_KEY:-packaging/release-signing-public.pem}"
git_head="${LOOPWIRE_RELEASE_COMMIT:-}"
release_dir=""
release_source="github"
require_release_evidence="false"
require_github_release_source="false"
release_evidence_asset=""
gui_startup_probe_seconds="${LOOPWIRE_GUI_STARTUP_PROBE_SECONDS:-5}"

usage() {
  cat <<'USAGE'
Verify a published Loopwire GitHub Release.

Usage:
  verify-published-release.sh --repo OWNER/REPO --tag vX.Y.Z --public-key FILE [--prefix DIR] [--git-head SHA] [--require-release-evidence] [--release-evidence-asset NAME] [--require-github-release-source]
  verify-published-release.sh --release-dir DIR --public-key FILE [--prefix DIR] [--tag vX.Y.Z] [--git-head SHA] [--require-release-evidence] [--release-evidence-asset NAME]

Downloads release assets with gh, verifies canonical assets are present in the signed SHA256SUMS manifest, installs the
host tarball from the downloaded release directory, and runs the installed binary. Use --release-dir for CI smoke coverage
of the same verification path without network or GitHub release access. Add --require-release-evidence to require, verify,
checksum-bind, and final-proof-check the loopwire-release-evidence-<tag>.tar.gz release asset, including read-only DSP
and JACK provider plan proof. Add --require-github-release-source to fail if a local --release-dir is supplied for final
public proof. Use --release-evidence-asset NAME when final proof uses a valid tag-bound non-default release evidence
archive name.
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
    --git-head)
      git_head="${2:-}"
      shift 2
      ;;
    --release-dir)
      release_dir="${2:-}"
      shift 2
      ;;
    --require-release-evidence)
      require_release_evidence="true"
      shift
      ;;
    --release-evidence-asset)
      release_evidence_asset="${2:-}"
      shift 2
      ;;
    --require-github-release-source)
      require_github_release_source="true"
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

[ -n "$release_dir" ] || [ -n "$repo" ] || fail "missing --repo OWNER/REPO or --release-dir DIR"
[ -n "$release_dir" ] || [ -n "$tag" ] || fail "missing --tag vX.Y.Z"
if [[ ! "$gui_startup_probe_seconds" =~ ^[1-9][0-9]*$ ]]; then
  fail "LOOPWIRE_GUI_STARTUP_PROBE_SECONDS must be a positive integer"
fi
if [ "$require_github_release_source" = "true" ] && [ -n "$release_dir" ]; then
  fail "--require-github-release-source cannot be used with --release-dir"
fi
if [ -n "$repo" ]; then
  repo_pattern='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
  if [[ ! "$repo" =~ $repo_pattern ]]; then
    fail "repository must use OWNER/REPO without URLs, spaces, or extra path segments: $repo"
  fi
fi
[ -f "$public_key" ] || fail "missing public key: $public_key"
if [ -n "$git_head" ] && [[ ! "$git_head" =~ ^[0-9a-fA-F]{40}$ ]]; then
  fail "git head must be a 40-character commit SHA: $git_head"
fi
if [ -n "$release_evidence_asset" ]; then
  [ -n "$tag" ] || fail "--release-evidence-asset requires --tag"
  release_evidence_asset="$(
    bash scripts/validate-release-asset-name.sh \
      --kind release-evidence \
      --tag "$tag" \
      --asset "$release_evidence_asset"
  )"
fi
command -v openssl >/dev/null 2>&1 || fail "openssl is required"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required"

required_assets=(
  "loopwire-linux-x86_64.tar.gz"
  "loopwire-linux-aarch64.tar.gz"
)

require_checksum_entry() {
  local asset="$1"
  local entry_count

  entry_count="$(awk -v asset="$asset" '$2 == asset { count++ } END { print count + 0 }' "$release_dir/SHA256SUMS")"
  case "$entry_count" in
    1)
      ;;
    0)
      fail "SHA256SUMS is missing required asset entry: $asset"
      ;;
    *)
      fail "SHA256SUMS has duplicate required asset entries: $asset"
      ;;
  esac
}

resolve_release_evidence_archive() {
  local archive
  local matches

  if [ -n "$release_evidence_asset" ]; then
    archive="$release_dir/$release_evidence_asset"
    [ -f "$archive" ] || fail "release directory is missing required evidence asset: $(basename "$archive")"
    printf '%s\n' "$archive"
    return
  fi

  if [ -n "$tag" ]; then
    archive="$release_dir/loopwire-release-evidence-${tag}.tar.gz"
    [ -f "$archive" ] || fail "release directory is missing required evidence asset: $(basename "$archive")"
    printf '%s\n' "$archive"
    return
  fi

  shopt -s nullglob
  matches=("$release_dir"/loopwire-release-evidence-*.tar.gz)
  shopt -u nullglob
  [ "${#matches[@]}" -eq 1 ] || fail "expected exactly one loopwire-release-evidence-*.tar.gz asset; found ${#matches[@]}"
  printf '%s\n' "${matches[0]}"
}

verify_release_evidence_archive() {
  local archive="$1"
  local evidence_extract_dir="$tmp_dir/release-evidence"
  local evidence_tag="$tag"
  local evidence_dir=""
  local evidence_dirs=()
  local verifier_args=()

  command -v node >/dev/null 2>&1 || fail "node is required for release evidence verification"
  command -v tar >/dev/null 2>&1 || fail "tar is required for release evidence verification"

  mkdir -p "$evidence_extract_dir"
  bash scripts/extract-safe-tar.sh \
    --archive "$archive" \
    --output-dir "$evidence_extract_dir" \
    --label "release evidence archive" >/dev/null

  if [ -n "$tag" ] && [ -d "$evidence_extract_dir/$tag" ]; then
    evidence_dir="$evidence_extract_dir/$tag"
  elif [ -f "$evidence_extract_dir/release-evidence.json" ]; then
    evidence_dir="$evidence_extract_dir"
  else
    while IFS= read -r candidate; do
      evidence_dirs+=("$candidate")
    done < <(find "$evidence_extract_dir" -mindepth 1 -maxdepth 1 -type d | sort)

    [ "${#evidence_dirs[@]}" -eq 1 ] \
      || fail "release evidence archive must contain release-evidence.json or exactly one top-level evidence directory"
    evidence_dir="${evidence_dirs[0]}"
  fi

  verifier_args=(
    --evidence-dir "$evidence_dir"
    --public-key "$public_key"
    --require-published-release
    --require-dsp-provider-plan
    --require-jack-provider-plan
    --require-no-release-blockers
  )
  if [ -z "$evidence_tag" ]; then
    evidence_tag="$(release_evidence_tag_from_archive "$archive")"
  fi
  verifier_args+=(--release-tag "$evidence_tag")
  [ -z "$repo" ] || verifier_args+=(--repo "$repo")
  [ -z "$git_head" ] || verifier_args+=(--git-head "$git_head")
  node scripts/verify-release-evidence.mjs "${verifier_args[@]}" >/dev/null
}

release_evidence_tag_from_archive() {
  local archive="$1"
  local name
  local archive_tag

  name="$(basename "$archive")"
  archive_tag="${name#loopwire-release-evidence-}"
  archive_tag="${archive_tag%.tar.gz}"

  if [[ ! "$archive_tag" =~ ^v[0-9]+[.][0-9]+[.][0-9]+([.-][0-9A-Za-z][0-9A-Za-z.-]*)?$ ]]; then
    fail "release evidence archive name must contain a v-prefixed semver tag: $name"
  fi

  printf '%s\n' "$archive_tag"
}

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

release_evidence_archive=""
if [ "$require_release_evidence" = "true" ]; then
  release_evidence_archive="$(resolve_release_evidence_archive)"
fi

bash scripts/verify-release-signature.sh --release-dir "$release_dir" --public-key "$public_key" >/dev/null
for asset in "${required_assets[@]}"; do
  require_checksum_entry "$asset"
done
if [ -n "$release_evidence_archive" ]; then
  require_checksum_entry "$(basename "$release_evidence_archive")"
fi
(
  cd "$release_dir"
  sha256sum --check SHA256SUMS >/dev/null
)
if [ -n "$release_evidence_archive" ]; then
  verify_release_evidence_archive "$release_evidence_archive"
fi
bash scripts/install.sh --base-url "file://$release_dir" --prefix "$install_prefix" --public-key "$public_key" >/dev/null

command -v timeout >/dev/null 2>&1 || fail "timeout is required for the bounded GUI startup probe"
set +e
timeout --signal=TERM --kill-after=2s "${gui_startup_probe_seconds}s" \
  "$install_prefix/loopwire" >/dev/null 2>&1
gui_startup_status="$?"
set -e
case "$gui_startup_status" in
  0 | 124)
    ;;
  *)
    fail "installed GUI startup probe failed with exit code $gui_startup_status"
    ;;
esac
"$install_prefix/loopwire" --background --help | grep -F -- "--state-file" >/dev/null
if [ "$release_source" = "github" ]; then
  echo "Published release verification passed for $repo@$tag."
else
  echo "Published release verification passed for $release_dir."
fi
