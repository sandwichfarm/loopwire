#!/usr/bin/env bash
set -euo pipefail

repo=""
run_id=""
git_head=""
docs_artifact="loopwire-docs"
manifest_artifact="loopwire-docs-deployment"
docs_dist="apps/docs/docs/.vitepress/dist"
manifest_path="dist/docs-deployment/deployment-manifest.json"
env_file=""

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
  --env-file FILE             Local release secret env file to preserve in Bunny secret recovery hints

The command downloads artifacts into the local checkout and verifies that the deployment manifest is non-dry-run proof
for the expected commit and downloaded docs bytes. It does not deploy docs or mutate GitHub.
Custom --docs-dist and --manifest outputs must be repo-relative, non-symlink local artifacts without . or .. segments,
URL syntax, home expansion, or glob metacharacters. Existing output paths must match the expected file/directory type
before the helper removes or rewrites proof locations. Custom --env-file paths may be absolute or relative local files,
but they reject the same traversal, URL, glob, symlink, and wrong-type cases before recovery commands are rendered.
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
  local expected_type="$3"
  local normalized

  [ -n "$value" ] || fail "$label must not be empty"
  reject_unsafe_value "$value" "$label"
  normalized="${value#./}"
  case "$normalized" in
    /* | ~* | *://* | "" | *'*'* | *'?'* | *'['* | *']'*)
      fail "$label must be a repo-relative local path without home expansion, URL syntax, or glob metacharacters: $value"
      ;;
  esac

  case "/$normalized/" in
    */../* | */./*)
      fail "$label must not contain . or .. path segments: $value"
      ;;
  esac

  [ ! -L "$value" ] || fail "$label must not be a symlink: $value"
  if [ "$expected_type" = "file" ]; then
    if [ -e "$value" ] && [ ! -f "$value" ]; then
      fail "$label must be a file when it exists: $value"
    fi
  elif [ "$expected_type" = "directory" ]; then
    if [ -e "$value" ] && [ ! -d "$value" ]; then
      fail "$label must be a directory when it exists: $value"
    fi
  else
    fail "unknown expected type for $label: $expected_type"
  fi
}

validate_local_file_path() {
  local value="$1"
  local label="$2"
  local normalized

  [ -n "$value" ] || fail "$label must not be empty"
  reject_unsafe_value "$value" "$label"
  normalized="${value#./}"

  case "$normalized" in
    "/" | "~" | "~/"* | *://* | "" | *'*'* | *'?'* | *'['* | *']'*)
      fail "$label must not be root, home-expanded, URL-like, empty, or contain glob metacharacters: $value"
      ;;
  esac

  case "/$normalized/" in
    */../* | */./*)
      fail "$label must not contain . or .. path segments: $value"
      ;;
  esac

  [ ! -L "$value" ] || fail "$label must not be a symlink: $value"
  if [ -e "$value" ] && [ ! -f "$value" ]; then
    fail "$label must be a file when it exists: $value"
  fi
}

indent() {
  sed 's/^/    /'
}

shell_join() {
  local out=""
  local arg

  for arg in "$@"; do
    if [ -n "$out" ]; then
      out+=" "
    fi
    printf -v out '%s%q' "$out" "$arg"
  done

  printf '%s\n' "$out"
}

list_run_artifacts() {
  gh api "repos/${repo}/actions/runs/${run_id}/artifacts" --jq '.artifacts[].name' 2>/dev/null || true
}

report_missing_deployment_artifact() {
  local artifacts

  artifacts="$(list_run_artifacts)"
  echo "missing: docs deployment manifest artifact: $manifest_artifact" >&2
  if [ -n "$artifacts" ]; then
    echo "found artifact(s):" >&2
    printf '%s\n' "$artifacts" | indent >&2
  else
    echo "found artifact(s): none or unavailable from GitHub API" >&2
  fi
  echo "likely cause: Deploy Docs did not run the Bunny.net deployment step, so it did not upload deployment proof." >&2
  echo "next: configure required Bunny.net GitHub secrets, rerun Deploy Docs, then rerun this helper:" >&2
  if [ -n "$env_file" ]; then
    printf '  %s\n' "$(shell_join bash scripts/setup-github-secrets.sh --repo "$repo" --scope deploy --env-file "$env_file")" >&2
  else
    echo "  bash scripts/setup-github-secrets.sh --repo $repo --scope deploy --storage-zone <zone> --access-key <key>" >&2
    echo "  # Or load Bunny values from a local uncommitted env file:" >&2
    echo "  bash scripts/setup-github-secrets.sh --repo $repo --scope deploy --env-file <secret-env-file>" >&2
  fi
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
  if [ "$label" = "docs deployment manifest" ]; then
    report_missing_deployment_artifact
  fi
  return 1
}

normalize_manifest_location() {
  local download_dir="$1"
  local destination="$2"
  local found=""

  if [ -s "$destination" ]; then
    return
  fi

  found="$(find "$download_dir" -type f -name deployment-manifest.json | sort | head -1)"
  [ -n "$found" ] || fail "deployment manifest artifact did not contain deployment-manifest.json"

  mkdir -p "$(dirname "$destination")"
  mv "$found" "$destination"
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
    --env-file)
      env_file="${2:?missing value for --env-file}"
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
validate_output_path "$docs_dist" "docs dist" "directory"
validate_output_path "$manifest_path" "manifest path" "file"
if [ -n "$env_file" ]; then
  validate_local_file_path "$env_file" "env file"
fi

command -v gh >/dev/null 2>&1 || fail "gh is required to download workflow artifacts"
command -v node >/dev/null 2>&1 || fail "node is required to verify deployment manifests"

stage_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$stage_dir"
}
trap cleanup EXIT

staged_docs_dist="$stage_dir/docs-dist"
manifest_download_dir="$stage_dir/manifest-artifact"
staged_manifest_path="$stage_dir/deployment-manifest.json"
mkdir -p "$staged_docs_dist" "$manifest_download_dir"

download_artifact "docs dist" "$docs_artifact" "$staged_docs_dist"
download_artifact "docs deployment manifest" "$manifest_artifact" "$manifest_download_dir"
normalize_manifest_location "$manifest_download_dir" "$staged_manifest_path"

node scripts/verify-docs-deployment-manifest.mjs \
  --manifest "$staged_manifest_path" \
  --dist "$staged_docs_dist" \
  --git-head "$git_head" \
  --expected-dry-run false

mkdir -p "$(dirname "$docs_dist")" "$(dirname "$manifest_path")"
rm -rf "$docs_dist"
rm -f "$manifest_path"
mv "$staged_docs_dist" "$docs_dist"
mv "$staged_manifest_path" "$manifest_path"

node scripts/verify-docs-deployment-manifest.mjs \
  --manifest "$manifest_path" \
  --dist "$docs_dist" \
  --git-head "$git_head" \
  --expected-dry-run false

echo "Docs deployment proof ready:"
echo "  docs dist: $docs_dist"
echo "  deployment manifest: $manifest_path"
