#!/usr/bin/env bash
set -euo pipefail

repo=""
tag=""
public_key="packaging/release-signing-public.pem"
secret_list_file=""
vm_evidence_root=".vm/evidence"
support_matrix="apps/docs/docs/guide/support-matrix.md"
skip_gh="false"

usage() {
  cat <<'USAGE'
Audit final release readiness without mutating GitHub, Bunny.net, VM guests, or host audio.

Usage:
  audit-final-release-state.sh --repo OWNER/REPO --tag vX.Y.Z [options]

Options:
  --public-key FILE           Release public key, default packaging/release-signing-public.pem
  --secret-list-file FILE     Names-only `gh secret list` artifact for deterministic secret checks
  --vm-evidence-root DIR      VM evidence root, default .vm/evidence
  --support-matrix FILE       Support matrix path, default apps/docs/docs/guide/support-matrix.md
  --skip-gh                   Skip live GitHub release/workflow lookups

The command is read-only. It exits nonzero while any required final release proof surface is missing or unverifiable.
USAGE
}

fail() {
  echo "audit-final-release-state: $*" >&2
  exit 2
}

validate_repo() {
  local pattern='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
  [[ "$repo" =~ $pattern ]] || fail "repository must use OWNER/REPO without URLs, spaces, or extra path segments: $repo"
}

validate_tag() {
  local pattern='^v[0-9]+[.][0-9]+[.][0-9]+([.-][0-9A-Za-z][0-9A-Za-z.-]*)?$'
  [[ "$tag" =~ $pattern ]] || fail "release tag must be v-prefixed semver without path separators: $tag"
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

indent() {
  sed 's/^/    /'
}

run_gate() {
  local label="$1"
  shift
  local output

  echo "==> $label"
  if output="$("$@" 2>&1)"; then
    echo "ok: $label"
    [ -z "$output" ] || printf '%s\n' "$output" | indent
    echo
    return 0
  fi

  echo "blocked: $label" >&2
  [ -z "$output" ] || printf '%s\n' "$output" | indent >&2
  echo >&2
  return 1
}

run_gh_probe() {
  local label="$1"
  shift

  if [ "$skip_gh" = "true" ]; then
    echo "==> $label"
    echo "skipped: live GitHub lookup disabled"
    echo
    return 0
  fi

  run_gate "$label" "$@"
}

run_workflow_probe() {
  local label="$1"
  shift
  local output
  local validation

  if [ "$skip_gh" = "true" ]; then
    echo "==> $label"
    echo "skipped: live GitHub lookup disabled"
    echo
    return 0
  fi

  echo "==> $label"
  if ! output="$("$@" 2>&1)"; then
    echo "blocked: $label" >&2
    [ -z "$output" ] || printf '%s\n' "$output" | indent >&2
    echo >&2
    return 1
  fi

  if ! validation="$(node - "$label" "$output" <<'NODE' 2>&1
const [label, raw] = process.argv.slice(2);
let runs;

try {
  runs = JSON.parse(raw);
} catch (error) {
  console.error(`${label} did not return JSON: ${error.message}`);
  process.exit(1);
}

if (!Array.isArray(runs)) {
  console.error(`${label} did not return a workflow run array.`);
  process.exit(1);
}

if (runs.length === 0) {
  console.error(`${label} did not return any workflow runs.`);
  process.exit(1);
}

const run = runs[0] ?? {};
if (run.status !== "completed") {
  console.error(`${label} latest run is not completed: ${run.status ?? "unknown"}.`);
  process.exit(1);
}

if (run.conclusion !== "success") {
  console.error(`${label} latest completed run did not succeed: ${run.conclusion ?? "unknown"}.`);
  process.exit(1);
}

const fields = [
  run.databaseId ? `databaseId=${run.databaseId}` : null,
  run.headSha ? `headSha=${run.headSha}` : null,
  run.url ? `url=${run.url}` : null
].filter(Boolean);
console.log(`latest run verified: ${fields.join(" ")}`);
NODE
  )"; then
    echo "blocked: $label" >&2
    [ -z "$validation" ] || printf '%s\n' "$validation" | indent >&2
    [ -z "$output" ] || printf '%s\n' "$output" | indent >&2
    echo >&2
    return 1
  fi

  echo "ok: $label"
  [ -z "$validation" ] || printf '%s\n' "$validation" | indent
  [ -z "$output" ] || printf '%s\n' "$output" | indent
  echo
}

run_vm_evidence_gate() {
  local label="$1"
  shift
  local output

  echo "==> $label"
  if ! output="$("$@" 2>&1)"; then
    echo "blocked: $label" >&2
    [ -z "$output" ] || printf '%s\n' "$output" | indent >&2
    echo >&2
    return 1
  fi

  if ! printf '%s\n' "$output" | grep -E 'summary=checked:[0-9]+ verified:[0-9]+ missing:0 invalid:0$' >/dev/null; then
    echo "blocked: $label" >&2
    printf '%s\n' "$output" | indent >&2
    echo >&2
    return 1
  fi

  echo "ok: $label"
  printf '%s\n' "$output" | indent
  echo
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
    --tag)
      tag="${2:?missing value for --tag}"
      shift 2
      ;;
    --public-key)
      public_key="${2:?missing value for --public-key}"
      shift 2
      ;;
    --secret-list-file)
      secret_list_file="${2:?missing value for --secret-list-file}"
      shift 2
      ;;
    --vm-evidence-root)
      vm_evidence_root="${2:?missing value for --vm-evidence-root}"
      shift 2
      ;;
    --support-matrix)
      support_matrix="${2:?missing value for --support-matrix}"
      shift 2
      ;;
    --skip-gh)
      skip_gh="true"
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

[ -n "$repo" ] || fail "missing --repo OWNER/REPO"
[ -n "$tag" ] || fail "missing --tag vX.Y.Z"
validate_repo
validate_tag
reject_unsafe_value "$public_key" "public key"
reject_unsafe_value "$secret_list_file" "secret-list file"
reject_unsafe_value "$vm_evidence_root" "VM evidence root"
reject_unsafe_value "$support_matrix" "support matrix"

failed=0
head_sha="$(git rev-parse HEAD 2>/dev/null || true)"

echo "Final release status for ${repo}@${tag}"
[ -z "$head_sha" ] || echo "Current checkout: ${head_sha}"
echo

secret_check=(bash scripts/setup-github-secrets.sh --repo "$repo" --check)
if [ -n "$secret_list_file" ]; then
  secret_check+=(--secret-list-file "$secret_list_file")
fi
run_gate "required GitHub secrets" "${secret_check[@]}" || failed=1

run_gh_probe \
  "GitHub Release object" \
  gh release view "$tag" --repo "$repo" --json tagName,url,targetCommitish,isDraft,isPrerelease || failed=1

run_workflow_probe \
  "latest Deploy Docs workflow run" \
  gh run list --repo "$repo" --workflow deploy-docs.yml --limit 1 \
    --json databaseId,status,conclusion,headBranch,headSha,createdAt,url || failed=1

run_workflow_probe \
  "latest Final Release Proof workflow run" \
  gh run list --repo "$repo" --workflow final-release-proof.yml --limit 1 \
    --json databaseId,status,conclusion,headBranch,headSha,createdAt,url || failed=1

run_vm_evidence_gate \
  "published-release-bound VM evidence" \
  bash scripts/vm-matrix.sh evidence-status --all --evidence-root "$vm_evidence_root" \
    --require-published-release --release-tag "$tag" || failed=1

run_gate \
  "support matrix published-release claims" \
  node scripts/verify-support-matrix.mjs --matrix "$support_matrix" \
    --require-published-release --release-tag "$tag" || failed=1

run_gate \
  "local final release handoff plan" \
  bash scripts/plan-final-release-handoff.sh --repo "$repo" --tag "$tag" \
    --git-head "${head_sha:-0000000000000000000000000000000000000000}" \
    --public-key "$public_key" || failed=1

if [ "$failed" -ne 0 ]; then
  echo "Final release status: blocked" >&2
  exit 1
fi

echo "Final release status: ready"
