#!/usr/bin/env bash
set -euo pipefail

repo=""
run_id=""
git_head=""
label="workflow run"

usage() {
  cat <<'USAGE'
Verify a GitHub Actions workflow run is successful for the expected commit.

Usage:
  verify-workflow-run.sh --repo OWNER/REPO --run-id ID --git-head SHA [--label TEXT]

The command is read-only. It fails unless the selected run is completed, successful, and its headSha matches
--git-head. Use it before downloading proof artifacts from a workflow run.
USAGE
}

fail() {
  echo "verify-workflow-run: $*" >&2
  exit 1
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

reject_unsafe_label() {
  case "$label" in
    *$'\n'* | *$'\r'*)
      fail "label must be a single line"
      ;;
  esac
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

[ -n "$repo" ] || fail "missing --repo OWNER/REPO"
[ -n "$run_id" ] || fail "missing --run-id ID"
[ -n "$git_head" ] || fail "missing --git-head SHA"

validate_repo
validate_run_id
validate_git_head
reject_unsafe_label
command -v gh >/dev/null 2>&1 || fail "gh is required to inspect workflow runs"
command -v node >/dev/null 2>&1 || fail "node is required to validate workflow run JSON"

if ! run_json="$(
  gh run view "$run_id" \
    --repo "$repo" \
    --json databaseId,status,conclusion,headSha,displayTitle,url 2>&1
)"; then
  fail "unable to inspect ${label} ${run_id}: ${run_json}"
fi

node - "$label" "$git_head" "$run_json" <<'NODE'
const [label, expectedHead, raw] = process.argv.slice(2);
let run;

try {
  run = JSON.parse(raw);
} catch (error) {
  console.error(`${label} did not return JSON: ${error.message}`);
  process.exit(1);
}

if (run.status !== "completed") {
  console.error(`${label} is not completed: ${run.status ?? "unknown"}.`);
  process.exit(1);
}

if (run.conclusion !== "success") {
  console.error(`${label} did not succeed: ${run.conclusion ?? "unknown"}.`);
  process.exit(1);
}

if (run.headSha !== expectedHead) {
  console.error(`${label} is for ${run.headSha ?? "unknown"}, not expected commit ${expectedHead}.`);
  process.exit(1);
}

const fields = [
  run.databaseId ? `databaseId=${run.databaseId}` : null,
  run.headSha ? `headSha=${run.headSha}` : null,
  run.displayTitle ? `displayTitle=${run.displayTitle}` : null,
  run.url ? `url=${run.url}` : null
].filter(Boolean);
console.log(`${label} verified: ${fields.join(" ")}`);
NODE
