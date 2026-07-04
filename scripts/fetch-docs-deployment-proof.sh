#!/usr/bin/env bash
set -euo pipefail

repo=""
run_id=""
git_head=""
docs_artifact="loopwire-docs"
manifest_artifact="loopwire-docs-deployment"
docs_dist="apps/docs/docs/.vitepress/dist"
manifest_path="dist/docs-deployment/deployment-manifest.json"

usage() {
  cat <<'USAGE'
Download and verify Deploy Docs proof artifacts from a GitHub Actions run.

Usage:
  fetch-docs-deployment-proof.sh --repo OWNER/REPO --run-id ID --git-head SHA [options]

Options:
  --docs-artifact NAME        Docs dist artifact, default loopwire-docs
  --manifest-artifact NAME    Docs deployment manifest artifact, default loopwire-docs-deployment
  --docs-dist DIR             Output docs dist directory, default apps/docs/docs/.vitepress/dist
  --manifest FILE             Output deployment manifest, default dist/docs-deployment/deployment-manifest.json

The command downloads artifacts into the local checkout and verifies that the deployment manifest is non-dry-run proof
for the expected commit and downloaded docs bytes. It does not deploy docs or mutate GitHub.
USAGE
}

fail() {
  echo "fetch-docs-deployment-proof: $*" >&2
  exit 1
}

reject_unsafe_value() {
  local value="$1"
  local label="$2"

  case "$value" in
    *$'\n'* | *$'\r'*)
      fail "$label must not contain newlines"
      ;;
  esac
}

validate_repo() {
  local pattern='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
  [[ "$repo" =~ $pattern ]] || fail "repository must use OWNER/REPO without URLs, spaces, or extra path segments: $repo"
}

validate_run_id() {
  [[ "$run_id" =~ ^[0-9]+$ ]] || fail "run id must be numeric: $run_id"
}

validate_git_head() {
  [[ "$git_head" =~ ^[0-9a-fA-F]{40}$ ]] || fail "git head must be a 40-character SHA: $git_head"
}

validate_output_path() {
  local value="$1"
  local label="$2"

  [ -n "$value" ] || fail "$label must not be empty"
  case "$value" in
    / | . | .. | ./*/.. | ../* | */../* | */..)
      fail "$label is not a safe output path: $value"
      ;;
  esac
}

indent() {
  sed 's/^/    /'
}

download_artifact() {
  local label="$1"
  local artifact="$2"
  local output_dir="$3"
  local output

  if output="$(gh run download "$run_id" --repo "$repo" --name "$artifact" --dir "$output_dir" 2>&1)"; then
    [ -z "$output" ] || printf '%s\n' "$output"
    return
  fi

  echo "failed to download ${label} artifact '${artifact}' from run ${run_id}" >&2
  [ -z "$output" ] || printf '%s\n' "$output" | indent >&2
  return 1
}

normalize_manifest_location() {
  local download_dir="$1"
  local found=""

  if [ -s "$manifest_path" ]; then
    return
  fi

  found="$(find "$download_dir" -type f -name deployment-manifest.json | sort | head -1)"
  [ -n "$found" ] || fail "deployment manifest artifact did not contain deployment-manifest.json"

  mkdir -p "$(dirname "$manifest_path")"
  mv "$found" "$manifest_path"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --)
      shift
      ;;
    --repo)
      repo="${2:?missing value for --repo}"
      shift 2
      ;;
    --run-id)
      run_id="${2:?missing value for --run-id}"
      shift 2
      ;;
    --git-head)
      git_head="${2:?missing value for --git-head}"
      shift 2
      ;;
    --docs-artifact)
      docs_artifact="${2:?missing value for --docs-artifact}"
      shift 2
      ;;
    --manifest-artifact)
      manifest_artifact="${2:?missing value for --manifest-artifact}"
      shift 2
      ;;
    --docs-dist)
      docs_dist="${2:?missing value for --docs-dist}"
      shift 2
      ;;
    --manifest)
      manifest_path="${2:?missing value for --manifest}"
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

[ -n "$repo" ] || fail "missing --repo OWNER/REPO"
[ -n "$run_id" ] || fail "missing --run-id ID"
[ -n "$git_head" ] || fail "missing --git-head SHA"

validate_repo
validate_run_id
validate_git_head
reject_unsafe_value "$docs_artifact" "docs artifact"
reject_unsafe_value "$manifest_artifact" "manifest artifact"
reject_unsafe_value "$docs_dist" "docs dist"
reject_unsafe_value "$manifest_path" "manifest path"
validate_output_path "$docs_dist" "docs dist"
validate_output_path "$manifest_path" "manifest path"

command -v gh >/dev/null 2>&1 || fail "gh is required to download workflow artifacts"
command -v node >/dev/null 2>&1 || fail "node is required to verify deployment manifests"

mkdir -p "$docs_dist" "$(dirname "$manifest_path")"
rm -rf "$docs_dist"
rm -f "$manifest_path"
mkdir -p "$docs_dist"

manifest_download_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$manifest_download_dir"
}
trap cleanup EXIT

download_artifact "docs dist" "$docs_artifact" "$docs_dist"
download_artifact "docs deployment manifest" "$manifest_artifact" "$manifest_download_dir"
normalize_manifest_location "$manifest_download_dir"

node scripts/verify-docs-deployment-manifest.mjs \
  --manifest "$manifest_path" \
  --dist "$docs_dist" \
  --git-head "$git_head" \
  --expected-dry-run false

echo "Docs deployment proof ready:"
echo "  docs dist: $docs_dist"
echo "  deployment manifest: $manifest_path"
