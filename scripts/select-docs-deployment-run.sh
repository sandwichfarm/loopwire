#!/usr/bin/env bash
set -euo pipefail

repo=""
git_head=""
workflow="deploy-docs.yml"
docs_artifact="loopwire-docs"
manifest_artifact="loopwire-docs-deployment"
limit="20"

usage() {
  cat <<'USAGE'
Select a successful Deploy Docs workflow run for a release commit.

Usage:
  select-docs-deployment-run.sh --repo OWNER/REPO --git-head SHA [options]

Options:
  --workflow NAME             Workflow file/name, default deploy-docs.yml
  --docs-artifact NAME        Docs dist artifact, default loopwire-docs
  --manifest-artifact NAME    Deployment manifest artifact, default loopwire-docs-deployment
  --limit N                   Number of commit-scoped runs to inspect, default 20

The command is read-only. It prints the selected GitHub Actions run id to stdout and diagnostics to stderr.
It fails unless a completed, successful run for --git-head exposes both docs proof artifacts.
USAGE
}

fail() {
  echo "select-docs-deployment-run: $*" >&2
  exit 1
}

validate_repo() {
  local pattern='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'

  [[ "$repo" =~ $pattern ]] || fail "repository must use OWNER/REPO without URLs, spaces, or extra path segments: $repo"
}

validate_git_head() {
  [[ "$git_head" =~ ^[0-9a-fA-F]{40}$ ]] || fail "git head must be a 40-character SHA: $git_head"
}

validate_limit() {
  [[ "$limit" =~ ^[0-9]+$ ]] || fail "limit must be numeric: $limit"
  if [ "$limit" -lt 1 ] || [ "$limit" -gt 100 ]; then
    fail "limit must be in 1..100: $limit"
  fi
}

reject_unsafe_value() {
  local value="$1"
  local label="$2"

  [ -n "$value" ] || fail "$label must not be empty"
  case "$value" in
    *$'\n'* | *$'\r'*)
      fail "$label must be a single line"
      ;;
  esac
}

indent() {
  sed 's/^/    /'
}

has_artifact() {
  local artifact="$1"

  printf '%s\n' "$artifact_names" | grep -Fx -- "$artifact" >/dev/null
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
    --git-head)
      git_head="${2:?missing value for --git-head}"
      shift 2
      ;;
    --workflow)
      workflow="${2:?missing value for --workflow}"
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
    --limit)
      limit="${2:?missing value for --limit}"
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
[ -n "$git_head" ] || fail "missing --git-head SHA"

validate_repo
validate_git_head
validate_limit
reject_unsafe_value "$workflow" "workflow"
reject_unsafe_value "$docs_artifact" "docs artifact"
reject_unsafe_value "$manifest_artifact" "manifest artifact"

command -v gh >/dev/null 2>&1 || fail "gh is required to inspect workflow runs"
command -v node >/dev/null 2>&1 || fail "node is required to filter workflow run JSON"

if ! runs_json="$(
  gh run list \
    --repo "$repo" \
    --workflow "$workflow" \
    --commit "$git_head" \
    --limit "$limit" \
    --json databaseId,status,conclusion,headSha,displayTitle,url 2>&1
)"; then
  fail "unable to list ${workflow} runs for ${git_head}: ${runs_json}"
fi

candidates="$(
  node - "$git_head" "$runs_json" <<'NODE'
const [expectedHead, raw] = process.argv.slice(2);
let runs;

try {
  runs = JSON.parse(raw);
} catch (error) {
  console.error(`workflow run list did not return JSON: ${error.message}`);
  process.exit(1);
}

if (!Array.isArray(runs)) {
  console.error("workflow run list did not return an array");
  process.exit(1);
}

for (const run of runs) {
  if (
    run?.databaseId &&
    run.status === "completed" &&
    run.conclusion === "success" &&
    run.headSha === expectedHead
  ) {
    console.log(run.databaseId);
  }
}
NODE
)"

if [ -z "$candidates" ]; then
  echo "checked workflow: $workflow" >&2
  echo "checked commit: $git_head" >&2
  fail "no completed successful Deploy Docs run found for the expected commit"
fi

checked=0
while IFS= read -r candidate_run_id; do
  [ -n "$candidate_run_id" ] || continue
  checked=$((checked + 1))
  if ! artifact_names="$(
    gh api "repos/${repo}/actions/runs/${candidate_run_id}/artifacts" \
      --jq '.artifacts[].name' 2>&1
  )"; then
    fail "unable to inspect artifacts for ${workflow} run ${candidate_run_id}: ${artifact_names}"
  fi

  if has_artifact "$docs_artifact" && has_artifact "$manifest_artifact"; then
    echo "selected Deploy Docs workflow run ${candidate_run_id} for ${git_head}" >&2
    printf '%s\n' "$candidate_run_id"
    exit 0
  fi

  echo "Deploy Docs artifacts visible for run ${candidate_run_id}:" >&2
  printf '%s\n' "$artifact_names" | indent >&2
  if ! has_artifact "$docs_artifact"; then
    echo "missing workflow artifact: $docs_artifact" >&2
  fi
  if ! has_artifact "$manifest_artifact"; then
    echo "missing workflow artifact: $manifest_artifact" >&2
    if [ "$manifest_artifact" = "loopwire-docs-deployment" ]; then
      echo "likely cause: Deploy Docs skipped Bunny.net deployment because required Bunny secrets are absent." >&2
    fi
  fi
  echo "skipped Deploy Docs run ${candidate_run_id}: missing ${docs_artifact} or ${manifest_artifact}" >&2
done <<<"$candidates"

echo "checked successful commit-scoped run(s): $checked" >&2
fail "no successful Deploy Docs run for ${git_head} exposed both ${docs_artifact} and ${manifest_artifact}"
