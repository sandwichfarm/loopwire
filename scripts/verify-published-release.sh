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

usage() {
  cat <<'USAGE'
Verify a published Loopwire GitHub Release.

Usage:
  verify-published-release.sh --repo OWNER/REPO --tag vX.Y.Z --public-key FILE [--prefix DIR] [--git-head SHA] [--require-release-evidence]
  verify-published-release.sh --release-dir DIR --public-key FILE [--prefix DIR] [--tag vX.Y.Z] [--git-head SHA] [--require-release-evidence]

Downloads release assets with gh, verifies canonical assets are present in the signed SHA256SUMS manifest, installs the
host tarball from the downloaded release directory, and runs the installed binary. Use --release-dir for CI smoke coverage
of the same verification path without network or GitHub release access. Add --require-release-evidence to require, verify,
and checksum-bind the loopwire-release-evidence-<tag>.tar.gz release asset.
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
command -v openssl >/dev/null 2>&1 || fail "openssl is required"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required"

required_assets=(
  "loopwire-linux-x86_64.tar.gz"
  "loopwire-linux-aarch64.tar.gz"
)

require_checksum_entry() {
  local asset="$1"

  awk -v asset="$asset" '$2 == asset { found = 1 } END { exit found ? 0 : 1 }' "$release_dir/SHA256SUMS" \
    || fail "SHA256SUMS is missing required asset entry: $asset"
}

resolve_release_evidence_archive() {
  local archive
  local matches

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
  validate_release_evidence_archive_members "$archive"
  tar -xzf "$archive" -C "$evidence_extract_dir"

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

validate_release_evidence_archive_members() {
  local archive="$1"
  local listing="$tmp_dir/release-evidence-tar-list.txt"
  local entry
  local part
  local -a parts=()

  tar -tzf "$archive" >"$listing" || fail "failed to list release evidence archive: $(basename "$archive")"
  [ -s "$listing" ] || fail "release evidence archive is empty: $(basename "$archive")"

  while IFS= read -r entry; do
    [ -n "$entry" ] || fail "release evidence archive contains an empty path"
    case "$entry" in
      /*)
        fail "release evidence archive contains an absolute path: $entry"
        ;;
    esac

    IFS="/" read -r -a parts <<<"$entry"
    for part in "${parts[@]}"; do
      [ "$part" != ".." ] || fail "release evidence archive contains a parent path component: $entry"
    done
  done <"$listing"
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

"$install_prefix/loopwire" >/dev/null
"$install_prefix/loopwire" --background --help | grep -F -- "--state-file" >/dev/null
if [ "$release_source" = "github" ]; then
  echo "Published release verification passed for $repo@$tag."
else
  echo "Published release verification passed for $release_dir."
fi
