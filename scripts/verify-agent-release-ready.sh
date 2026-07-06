#!/usr/bin/env bash
set -euo pipefail

repo=""
tag=""
git_head=""
public_key="packaging/release-signing-public.pem"
skip_local_gates="false"
require_hosted_checks="false"
require_docs_deployment_artifacts="false"
allow_dirty="false"
allow_head_mismatch="false"
dsp_configuration="scripts/fixtures/dsp-provider-configuration.json"
dsp_frame_count="16"
release_evidence_asset=""
vm_evidence_asset=""

usage() {
  cat <<'USAGE'
Verify repo-side release readiness before operator-only final ceremony.

Usage:
  verify-agent-release-ready.sh --repo OWNER/REPO --tag vX.Y.Z [options]

Options:
  --git-head SHA         Expected release/source commit, default current checkout HEAD
  --public-key FILE      Release public key, default packaging/release-signing-public.pem
  --dsp-configuration FILE
                         Release DSP proof topology, default scripts/fixtures/dsp-provider-configuration.json
  --dsp-frame-count N    Source frame count for read-only DSP provider planning, default 16
  --release-evidence-asset NAME
                         Expected release evidence archive asset, default loopwire-release-evidence-<tag>.tar.gz
  --vm-evidence-asset NAME
                         Expected VM evidence archive asset, default loopwire-vm-evidence-<tag>.tar.gz
  --skip-local-gates     Only verify offline release readiness and handoff rendering
  --require-hosted-checks
                         Require commit-scoped CI and Deploy Docs workflow runs to be successful for --git-head
  --require-docs-deployment-artifacts
                         Require a successful Deploy Docs run for --git-head to expose docs proof artifacts
  --allow-dirty          Permit a dirty checkout for local rehearsal; strict handoff checks require a clean tree
  --allow-head-mismatch  Permit current checkout HEAD to differ from --git-head for offline fixture rehearsal

This command is read-only. It does not set secrets, create tags, dispatch workflows, upload assets, launch VMs, or
mutate host audio. Passing means the repository-side automation is ready for the operator-deferred release ceremony.
By default it requires a clean checkout at exactly --git-head so the rendered handoff matches the pushed commit.
Strict final proof still requires published artifacts, Bunny deployment proof, final proof workflow success, and VM
evidence captured from operator-controlled hosts. Hosted checks are optional because they require GitHub API access.
Use --require-docs-deployment-artifacts after Deploy Docs has run with Bunny secrets configured; before that operator
step, a successful Deploy Docs workflow may only expose the build artifact.
USAGE
}

fail() {
  echo "verify-agent-release-ready: $*" >&2
  exit 1
}

validate_repo() {
  local pattern='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
  [[ "$repo" =~ $pattern ]] || fail "repository must use OWNER/REPO without URLs, spaces, or extra path segments: $repo"
}

validate_tag() {
  local pattern='^v[0-9]+[.][0-9]+[.][0-9]+([.-][0-9A-Za-z][0-9A-Za-z.-]*)?$'
  [[ "$tag" =~ $pattern ]] || fail "release tag must be v-prefixed semver without path separators: $tag"
}

validate_git_head() {
  local pattern='^[0-9a-fA-F]{40}$'
  [[ "$git_head" =~ $pattern ]] || fail "git head must be a 40-character SHA: $git_head"
}

validate_current_checkout_head() {
  local current_head

  current_head="$(git rev-parse HEAD 2>/dev/null || true)"
  [ -n "$current_head" ] || fail "unable to resolve current git HEAD"
  if [ "$current_head" != "$git_head" ]; then
    fail "current checkout HEAD $current_head does not match --git-head $git_head; checkout the target commit or pass --allow-head-mismatch for fixture rehearsal"
  fi
}

validate_positive_integer() {
  local value="$1"
  local label="$2"

  [[ "$value" =~ ^[1-9][0-9]*$ ]] || fail "$label must be a positive integer"
}

validate_optional_asset() {
  local kind="$1"
  local asset="$2"

  [ -z "$asset" ] || bash scripts/validate-release-asset-name.sh --kind "$kind" --tag "$tag" --asset "$asset" >/dev/null
}

validate_relative_path() {
  local value="$1"
  local label="$2"

  reject_unsafe_value "$value" "$label"
  case "$value" in
    "" | /* | ~ | ~/* | *"://"* | *"*"* | *"?"* | *"["* | *"]"*)
      fail "$label must be a relative path without glob, URL, root, or home syntax"
      ;;
  esac

  IFS='/' read -r -a parts <<<"$value"
  for part in "${parts[@]}"; do
    if [ "$part" = "." ] || [ "$part" = ".." ]; then
      fail "$label must not contain . or .. path segments"
    fi
  done
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

assert_handoff_contains() {
  local handoff="$1"
  local needle="$2"

  printf '%s\n' "$handoff" | grep -F -- "$needle" >/dev/null ||
    fail "release handoff is missing expected content: $needle"
}

run_hosted_workflow_probe() {
  local label="$1"
  local workflow="$2"
  local output
  local validation

  echo "==> $label"
  if ! output="$(
    gh run list --repo "$repo" --workflow "$workflow" --commit "$git_head" --limit 1 \
      --json databaseId,status,conclusion,headSha,url 2>&1
  )"; then
    echo "blocked: $label" >&2
    [ -z "$output" ] || printf '%s\n' "$output" | indent >&2
    echo >&2
    return 1
  fi

  if ! validation="$(node - "$label" "$git_head" "$output" <<'NODE' 2>&1
const [label, expectedHead, raw] = process.argv.slice(2);
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
  console.error(`${label} commit-scoped run is not completed: ${run.status ?? "unknown"}.`);
  process.exit(1);
}

if (run.conclusion !== "success") {
  console.error(`${label} commit-scoped completed run did not succeed: ${run.conclusion ?? "unknown"}.`);
  process.exit(1);
}

if (run.headSha !== expectedHead) {
  console.error(`${label} commit-scoped run is for ${run.headSha ?? "unknown"}, not ${expectedHead}.`);
  process.exit(1);
}

const fields = [
  run.databaseId ? `databaseId=${run.databaseId}` : null,
  run.headSha ? `headSha=${run.headSha}` : null,
  run.url ? `url=${run.url}` : null
].filter(Boolean);
console.log(`commit-scoped run verified: ${fields.join(" ")}`);
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
    --git-head)
      git_head="${2:?missing value for --git-head}"
      shift 2
      ;;
    --public-key)
      public_key="${2:?missing value for --public-key}"
      shift 2
      ;;
    --dsp-configuration)
      dsp_configuration="${2:?missing value for --dsp-configuration}"
      shift 2
      ;;
    --dsp-frame-count)
      dsp_frame_count="${2:?missing value for --dsp-frame-count}"
      shift 2
      ;;
    --release-evidence-asset)
      release_evidence_asset="${2:?missing value for --release-evidence-asset}"
      shift 2
      ;;
    --vm-evidence-asset)
      vm_evidence_asset="${2:?missing value for --vm-evidence-asset}"
      shift 2
      ;;
    --skip-local-gates)
      skip_local_gates="true"
      shift
      ;;
    --require-hosted-checks)
      require_hosted_checks="true"
      shift
      ;;
    --require-docs-deployment-artifacts)
      require_docs_deployment_artifacts="true"
      shift
      ;;
    --allow-dirty)
      allow_dirty="true"
      shift
      ;;
    --allow-head-mismatch)
      allow_head_mismatch="true"
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
if [ -z "$git_head" ]; then
  git_head="$(git rev-parse HEAD 2>/dev/null || true)"
fi

validate_repo
validate_tag
validate_git_head
validate_optional_asset "release-evidence" "$release_evidence_asset"
validate_optional_asset "vm-evidence" "$vm_evidence_asset"
if [ "$allow_head_mismatch" != "true" ]; then
  validate_current_checkout_head
fi
reject_unsafe_value "$public_key" "public key"
validate_relative_path "$dsp_configuration" "DSP configuration"
validate_positive_integer "$dsp_frame_count" "DSP frame count"
release_evidence_asset="${release_evidence_asset:-loopwire-release-evidence-${tag}.tar.gz}"
vm_evidence_asset="${vm_evidence_asset:-loopwire-vm-evidence-${tag}.tar.gz}"

echo "Agent-ready release check for ${repo}@${tag}"
echo "Expected release commit: ${git_head}"
echo

release_readiness_args=(
  --repo "$repo"
  --tag "$tag"
  --public-key "$public_key"
  --skip-gh
  --skip-tag
)
if [ "$allow_dirty" = "true" ]; then
  release_readiness_args+=(--skip-clean-git)
fi

run_gate \
  "offline release readiness" \
  bash scripts/verify-release-readiness.sh "${release_readiness_args[@]}"

echo "==> final release handoff rendering"
handoff_args=(--repo "$repo" --tag "$tag" --git-head "$git_head" --public-key "$public_key")
handoff_args+=(--release-evidence-asset "$release_evidence_asset")
handoff_args+=(--vm-evidence-asset "$vm_evidence_asset")
handoff="$(
  bash scripts/plan-final-release-handoff.sh "${handoff_args[@]}"
)"
assert_handoff_contains "$handoff" "Operator-deferred after agent delivery"
assert_handoff_contains "$handoff" "bash scripts/setup-github-secrets.sh --write-env-template /secure/loopwire-release-secrets.env"
assert_handoff_contains "$handoff" "operator-deferred: run the docs_deployment_run_id selection command"
assert_handoff_contains "$handoff" "operator-deferred: pass --release-private-key-file or --env-file"
assert_handoff_contains "$handoff" "-f release_evidence_asset=${release_evidence_asset}"
assert_handoff_contains "$handoff" "-f vm_evidence_asset=${vm_evidence_asset}"
assert_handoff_contains "$handoff" "--release-evidence-asset ${release_evidence_asset}"
assert_handoff_contains "$handoff" "--vm-evidence-asset ${vm_evidence_asset}"
echo "ok: final release handoff rendering"
printf '%s\n' "$handoff" | indent
echo

if [ "$require_hosted_checks" = "true" ]; then
  run_hosted_workflow_probe "commit-scoped hosted CI workflow run" ci.yml
  run_hosted_workflow_probe "commit-scoped hosted Deploy Docs workflow run" deploy-docs.yml
else
  echo "skipped: hosted workflow checks (--require-hosted-checks not set)"
  echo
fi

if [ "$require_docs_deployment_artifacts" = "true" ]; then
  run_gate \
    "artifact-bearing hosted Deploy Docs run" \
    bash scripts/select-docs-deployment-run.sh --repo "$repo" --git-head "$git_head"
else
  echo "skipped: docs deployment artifact check (--require-docs-deployment-artifacts not set)"
  echo
fi

if [ "$skip_local_gates" != "true" ]; then
  run_gate "workflow contracts" bash scripts/verify-github-workflows.sh
  run_gate "documentation contracts" bash scripts/verify-docs.sh
  run_gate \
    "DSP provider graph-edge plan" \
    bash scripts/collect-dsp-provider-plan.sh --configuration "$dsp_configuration" --frame-count "$dsp_frame_count"
  run_gate "VM matrix metadata and cloud-init" bash scripts/vm-matrix.sh validate
  run_gate "VM cloud-init rendering" bash scripts/vm-matrix.sh verify-cloud-init
  run_gate "packaging metadata" bash scripts/verify-packaging.sh
  run_gate "local release artifact smoke" bash scripts/verify-release-artifacts.sh
else
  echo "skipped: local repo gates (--skip-local-gates)"
  echo
fi

cat <<EOF
Agent-ready release status: ready for operator-deferred ceremony

Operator-deferred remains:
- Fill and set GitHub secrets from an uncommitted local env file.
- Create and push ${tag} only after strict readiness passes.
- Dispatch protected release/docs/final-proof workflows.
- Run VM guests and upload signed release plus VM evidence assets.
- Re-run strict final proof from published GitHub Release and Bunny.net surfaces.
EOF
