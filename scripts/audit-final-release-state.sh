#!/usr/bin/env bash
set -euo pipefail

repo=""
tag=""
expected_git_head=""
public_key="packaging/release-signing-public.pem"
secret_list_file=""
docs_deployment_manifest="${LOOPWIRE_DOCS_DEPLOYMENT_MANIFEST:-dist/docs-deployment/deployment-manifest.json}"
docs_dist="${LOOPWIRE_DOCS_DIST:-apps/docs/docs/.vitepress/dist}"
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
  --git-head SHA              Expected release/source commit, default current checkout HEAD
  --secret-list-file FILE     Names-only `gh secret list` artifact for deterministic secret checks
  --docs-deployment-manifest FILE
                              Docs deployment manifest, default dist/docs-deployment/deployment-manifest.json
  --docs-dist DIR             Built docs dist directory, default apps/docs/docs/.vitepress/dist
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

validate_git_head() {
  local pattern='^[0-9a-fA-F]{40}$'
  [[ "$expected_git_head" =~ $pattern ]] || fail "git head must be a 40-character SHA: $expected_git_head"
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

check_public_key() {
  if [ ! -s "$public_key" ]; then
    echo "missing: release signing public key: $public_key" >&2
    return 1
  fi

  if ! openssl pkey -pubin -in "$public_key" -noout >/dev/null 2>&1; then
    echo "invalid: release signing public key: $public_key" >&2
    return 1
  fi

  echo "ok: release signing public key parses: $public_key"
}

docs_deployment_run_id_hint() {
  local output

  if [ "$skip_gh" = "true" ]; then
    echo "<docs-deployment-run-id>"
    return
  fi

  output="$(gh run list --repo "$repo" --workflow deploy-docs.yml --limit 1 --json databaseId 2>/dev/null || true)"
  if [ -z "$output" ]; then
    echo "<docs-deployment-run-id>"
    return
  fi

  node - "$output" <<'NODE' 2>/dev/null || printf '%s\n' "<docs-deployment-run-id>"
const raw = process.argv[2];
const runs = JSON.parse(raw);
const run = Array.isArray(runs) ? runs[0] : null;
if (run && Number.isInteger(run.databaseId)) {
  console.log(String(run.databaseId));
} else {
  console.log("<docs-deployment-run-id>");
}
NODE
}

check_docs_deployment_manifest() {
  local run_id

  if [ ! -s "$docs_deployment_manifest" ]; then
    run_id="$(docs_deployment_run_id_hint)"
    echo "missing: docs deployment manifest: $docs_deployment_manifest" >&2
    echo "next: fetch and verify Deploy Docs proof artifacts:" >&2
    echo "  pnpm release:fetch-docs-proof -- --repo $repo --run-id $run_id --git-head $expected_git_head" >&2
    echo "note: the Deploy Docs run must include the loopwire-docs-deployment artifact; configure Bunny secrets if it is absent." >&2
    return 1
  fi

  node scripts/verify-docs-deployment-manifest.mjs \
    --manifest "$docs_deployment_manifest" \
    --dist "$docs_dist" \
    --git-head "$expected_git_head" \
    --expected-dry-run false
}

run_release_probe() {
  local label="$1"
  local expected_tag="$2"
  shift 2
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

  if ! validation="$(node - "$label" "$expected_tag" "$output" <<'NODE' 2>&1
const [label, expectedTag, raw] = process.argv.slice(2);
let release;

try {
  release = JSON.parse(raw);
} catch (error) {
  console.error(`${label} did not return JSON: ${error.message}`);
  process.exit(1);
}

if (!release || typeof release !== "object" || Array.isArray(release)) {
  console.error(`${label} did not return a release object.`);
  process.exit(1);
}

if (release.tagName !== expectedTag) {
  console.error(`${label} returned tag ${release.tagName ?? "unknown"}, not ${expectedTag}.`);
  process.exit(1);
}

if (release.isDraft === true) {
  console.error(`${label} is still a draft release.`);
  process.exit(1);
}

if (release.isPrerelease === true) {
  console.error(`${label} is still marked prerelease.`);
  process.exit(1);
}

if (typeof release.url !== "string" || release.url.length === 0) {
  console.error(`${label} did not include a release URL.`);
  process.exit(1);
}

if (!Array.isArray(release.assets)) {
  console.error(`${label} did not include an assets array.`);
  process.exit(1);
}

const expectedAssets = [
  "loopwire-linux-x86_64.tar.gz",
  "loopwire-linux-aarch64.tar.gz",
  "SHA256SUMS",
  "SHA256SUMS.sig",
  `loopwire-release-evidence-${expectedTag}.tar.gz`,
  `loopwire-vm-evidence-${expectedTag}.tar.gz`
];
const assetNames = new Set(
  release.assets
    .map((asset) => asset?.name)
    .filter((name) => typeof name === "string" && name.length > 0)
);
const missing = expectedAssets.filter((name) => !assetNames.has(name));

if (missing.length > 0) {
  console.error(`${label} is missing required asset(s): ${missing.join(", ")}.`);
  process.exit(1);
}

console.log(`release verified: ${release.tagName} ${release.url} assets=${expectedAssets.length}`);
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

run_workflow_probe() {
  local label="$1"
  local expected_head="$2"
  shift 2
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

  if ! validation="$(node - "$label" "$expected_head" "$output" <<'NODE' 2>&1
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
  console.error(`${label} latest run is not completed: ${run.status ?? "unknown"}.`);
  process.exit(1);
}

if (run.conclusion !== "success") {
  console.error(`${label} latest completed run did not succeed: ${run.conclusion ?? "unknown"}.`);
  process.exit(1);
}

if (run.headSha !== expectedHead) {
  console.error(
    `${label} latest run is for ${run.headSha ?? "unknown"}, not expected commit ${expectedHead}.`
  );
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
    --git-head)
      expected_git_head="${2:?missing value for --git-head}"
      shift 2
      ;;
    --secret-list-file)
      secret_list_file="${2:?missing value for --secret-list-file}"
      shift 2
      ;;
    --docs-deployment-manifest)
      docs_deployment_manifest="${2:?missing value for --docs-deployment-manifest}"
      shift 2
      ;;
    --docs-dist)
      docs_dist="${2:?missing value for --docs-dist}"
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
reject_unsafe_value "$expected_git_head" "git head"
reject_unsafe_value "$secret_list_file" "secret-list file"
reject_unsafe_value "$docs_deployment_manifest" "docs deployment manifest"
reject_unsafe_value "$docs_dist" "docs dist"
reject_unsafe_value "$vm_evidence_root" "VM evidence root"
reject_unsafe_value "$support_matrix" "support matrix"

failed=0
head_sha="$(git rev-parse HEAD 2>/dev/null || true)"
if [ -z "$expected_git_head" ]; then
  expected_git_head="$head_sha"
fi
[ -n "$expected_git_head" ] || fail "missing --git-head SHA outside a git checkout"
validate_git_head

echo "Final release status for ${repo}@${tag}"
[ -z "$head_sha" ] || echo "Current checkout: ${head_sha}"
echo "Expected release commit: ${expected_git_head}"
echo

secret_check=(bash scripts/setup-github-secrets.sh --repo "$repo" --check)
if [ -n "$secret_list_file" ]; then
  secret_check+=(--secret-list-file "$secret_list_file")
fi
run_gate "required GitHub secrets" "${secret_check[@]}" || failed=1

run_gate "release signing public key" check_public_key || failed=1

run_release_probe \
  "GitHub Release object" \
  "$tag" \
  gh release view "$tag" --repo "$repo" \
    --json tagName,url,targetCommitish,isDraft,isPrerelease,assets || failed=1

run_workflow_probe \
  "latest Deploy Docs workflow run" \
  "$expected_git_head" \
  gh run list --repo "$repo" --workflow deploy-docs.yml --limit 1 \
    --json databaseId,status,conclusion,headBranch,headSha,createdAt,url || failed=1

run_gate \
  "docs deployment manifest" \
  check_docs_deployment_manifest || failed=1

run_workflow_probe \
  "latest Final Release Proof workflow run" \
  "$expected_git_head" \
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
    --git-head "$expected_git_head" \
    --public-key "$public_key" || failed=1

if [ "$failed" -ne 0 ]; then
  echo "Final release status: blocked" >&2
  exit 1
fi

echo "Final release status: ready"
