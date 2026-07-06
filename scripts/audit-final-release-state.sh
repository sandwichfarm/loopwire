#!/usr/bin/env bash
set -euo pipefail

repo=""
tag=""
expected_git_head=""
public_key="packaging/release-signing-public.pem"
public_key_explicit="false"
env_file=""
secret_list_file=""
docs_deployment_run_id=""
docs_deployment_manifest="${LOOPWIRE_DOCS_DEPLOYMENT_MANIFEST:-dist/docs-deployment/deployment-manifest.json}"
docs_dist="${LOOPWIRE_DOCS_DIST:-apps/docs/docs/.vitepress/dist}"
vm_evidence_root=".vm/evidence"
vm_start_port="2600"
support_matrix="apps/docs/docs/guide/support-matrix.md"
release_evidence_asset=""
vm_evidence_asset=""
skip_gh="false"
latest_docs_deployment_run_id=""
docs_deployment_run_selection_failed="false"
docs_deployment_artifact_verification_failed="false"

usage() {
  cat <<'USAGE'
Audit final release readiness without mutating GitHub, Bunny.net, VM guests, or host audio.

Usage:
  audit-final-release-state.sh --repo OWNER/REPO --tag vX.Y.Z [options]

Options:
  --public-key FILE           Release public key, default packaging/release-signing-public.pem
  --git-head SHA              Expected release/source commit, default current checkout HEAD
  --env-file FILE             Local setup env file for final handoff paths/host fields
  --secret-list-file FILE     Names-only `gh secret list` artifact for deterministic secret checks
  --docs-deployment-run-id ID Verify this Deploy Docs run instead of the latest run
  --docs-deployment-manifest FILE
                              Docs deployment manifest, default dist/docs-deployment/deployment-manifest.json
  --docs-dist DIR             Built docs dist directory, default apps/docs/docs/.vitepress/dist
  --vm-evidence-root DIR      VM evidence root, default .vm/evidence
  --vm-start-port PORT        SSH start port for VM evidence collection handoffs, default 2600
  --support-matrix FILE       Support matrix path, default apps/docs/docs/guide/support-matrix.md
  --release-evidence-asset NAME
                              Release evidence archive asset override
  --vm-evidence-asset NAME    VM evidence archive asset override
  --skip-gh                   Skip live GitHub release/workflow lookups

The command is read-only. It exits nonzero while any required final release proof surface is missing or unverifiable.
Custom local path values may be absolute or relative, but they must not contain parent traversal, URL syntax, glob
metacharacters, root/home expansion, symlinks, or an existing path with the wrong file/directory type.
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

validate_vm_start_port() {
  [[ "$vm_start_port" =~ ^[0-9]+$ ]] || fail "VM start port must be numeric: $vm_start_port"
  if [ "$vm_start_port" -lt 1 ] || [ "$vm_start_port" -gt 65535 ]; then
    fail "VM start port must be in 1..65535: $vm_start_port"
  fi
}

validate_docs_deployment_run_id() {
  [ -z "$docs_deployment_run_id" ] || [[ "$docs_deployment_run_id" =~ ^[0-9]+$ ]] ||
    fail "docs deployment run id must be numeric: $docs_deployment_run_id"
}

validate_optional_asset() {
  local kind="$1"
  local asset="$2"

  [ -z "$asset" ] || bash scripts/validate-release-asset-name.sh --kind "$kind" --tag "$tag" --asset "$asset" >/dev/null
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

validate_local_path() {
  local value="$1"
  local label="$2"
  local expected_type="$3"
  local normalized

  reject_unsafe_value "$value" "$label"
  normalized="${value#./}"

  [ -n "$normalized" ] || fail "$label must not be empty"
  case "$normalized" in
    "/" | "~" | "~/"* | *://* | *'*'* | *'?'* | *'['* | *']'*)
      fail "$label must not be root, home-expanded, URL-like, or contain glob metacharacters"
      ;;
  esac

  case "/$normalized/" in
    */../* | */./*)
      fail "$label must not contain . or .. path segments"
      ;;
  esac

  [ ! -L "$value" ] || fail "$label must not be a symlink"
  if [ -e "$value" ]; then
    case "$expected_type" in
      file)
        [ -f "$value" ] || fail "$label must be a file when it exists"
        ;;
      dir)
        [ -d "$value" ] || fail "$label must be a directory when it exists"
        ;;
      *)
        fail "unknown local path type for $label: $expected_type"
        ;;
    esac
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

select_docs_deployment_run_id() {
  local selected_run_id

  if [ -n "$docs_deployment_run_id" ]; then
    latest_docs_deployment_run_id="$docs_deployment_run_id"
    echo "using explicit Deploy Docs workflow run: $docs_deployment_run_id"
    return 0
  fi

  if [ -n "$latest_docs_deployment_run_id" ]; then
    echo "using selected Deploy Docs workflow run: $latest_docs_deployment_run_id"
    return 0
  fi

  if [ "$skip_gh" = "true" ]; then
    echo "skipped: live GitHub lookup disabled"
    return 0
  fi

  selected_run_id="$(
    bash scripts/select-docs-deployment-run.sh \
      --repo "$repo" \
      --git-head "$expected_git_head"
  )" || {
    docs_deployment_run_selection_failed="true"
    return 1
  }

  latest_docs_deployment_run_id="$selected_run_id"
  docs_deployment_run_selection_failed="false"
  echo "selected Deploy Docs workflow run: $latest_docs_deployment_run_id"
}

docs_deployment_run_id_hint() {
  local selected_run_id

  if [ "$docs_deployment_artifact_verification_failed" = "true" ]; then
    echo "<docs-deployment-run-id>"
    return
  fi

  if [ -n "$docs_deployment_run_id" ]; then
    echo "$docs_deployment_run_id"
    return
  fi

  if [ -n "$latest_docs_deployment_run_id" ]; then
    echo "$latest_docs_deployment_run_id"
    return
  fi

  if [ "$skip_gh" = "true" ]; then
    echo "<docs-deployment-run-id>"
    return
  fi

  if [ "$docs_deployment_run_selection_failed" = "true" ]; then
    echo "<docs-deployment-run-id>"
    return
  fi

  selected_run_id="$(
    bash scripts/select-docs-deployment-run.sh \
      --repo "$repo" \
      --git-head "$expected_git_head" 2>/dev/null || true
  )"
  if [[ "$selected_run_id" =~ ^[0-9]+$ ]]; then
    echo "$selected_run_id"
    return
  fi

  echo "<docs-deployment-run-id>"
}

workflow_run_id_from_json() {
  local output="$1"

  node - "$output" <<'NODE' 2>/dev/null || true
const raw = process.argv[2];
const parsed = JSON.parse(raw);
const run = Array.isArray(parsed) ? parsed[0] : parsed;
if (run && Number.isInteger(run.databaseId)) {
  console.log(String(run.databaseId));
}
NODE
}

report_docs_deployment_artifact_hint() {
  local run_id="$1"
  local artifacts

  if [ "$skip_gh" = "true" ]; then
    return
  fi

  [[ "$run_id" =~ ^[0-9]+$ ]] || return

  artifacts="$(gh api "repos/${repo}/actions/runs/${run_id}/artifacts" --jq '.artifacts[].name' 2>/dev/null || true)"
  if [ -z "$artifacts" ]; then
    echo "Deploy Docs artifacts visible: none or unavailable from GitHub API" >&2
    return
  fi

  echo "Deploy Docs artifacts visible:" >&2
  printf '%s\n' "$artifacts" | indent >&2
  if ! printf '%s\n' "$artifacts" | grep -Fxq "loopwire-docs-deployment"; then
    echo "missing workflow artifact: loopwire-docs-deployment" >&2
    echo "likely cause: Deploy Docs skipped Bunny.net deployment because required Bunny secrets are absent." >&2
  fi
}

verify_docs_deployment_run_artifacts() {
  local run_id="$1"
  local artifacts
  local missing=0

  if [ "$skip_gh" = "true" ]; then
    echo "skipped: live GitHub lookup disabled"
    return 0
  fi

  [[ "$run_id" =~ ^[0-9]+$ ]] || {
    echo "missing: no Deploy Docs run id available for artifact verification" >&2
    return 1
  }

  if ! artifacts="$(gh api "repos/${repo}/actions/runs/${run_id}/artifacts" --jq '.artifacts[].name' 2>&1)"; then
    echo "unable to inspect Deploy Docs artifacts for run ${run_id}: ${artifacts}" >&2
    return 1
  fi

  if [ -z "$artifacts" ]; then
    echo "Deploy Docs artifacts visible for run ${run_id}: none" >&2
    return 1
  fi

  echo "Deploy Docs artifacts visible for run ${run_id}:"
  printf '%s\n' "$artifacts" | indent

  if ! printf '%s\n' "$artifacts" | grep -Fxq "loopwire-docs"; then
    echo "missing workflow artifact: loopwire-docs" >&2
    missing=1
  fi
  if ! printf '%s\n' "$artifacts" | grep -Fxq "loopwire-docs-deployment"; then
    echo "missing workflow artifact: loopwire-docs-deployment" >&2
    echo "likely cause: Deploy Docs skipped Bunny.net deployment because required Bunny secrets are absent." >&2
    missing=1
  fi

  [ "$missing" -eq 0 ] || return 1
  echo "Deploy Docs run ${run_id} exposes required proof artifacts"
}

check_docs_deployment_manifest() {
  local run_id
  local fetch_command

  if [ ! -s "$docs_deployment_manifest" ]; then
    run_id="$(docs_deployment_run_id_hint)"
    echo "missing: docs deployment manifest: $docs_deployment_manifest" >&2
    report_docs_deployment_artifact_hint "$run_id"
    fetch_command=(pnpm release:fetch-docs-proof -- --repo "$repo" --run-id "$run_id" --git-head "$expected_git_head")
    if [ -n "$env_file" ]; then
      fetch_command+=(--env-file "$env_file")
    fi
    echo "next: fetch and verify Deploy Docs proof artifacts:" >&2
    printf '  %s\n' "$(shell_join "${fetch_command[@]}")" >&2
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

download_release_asset_or_explain() {
  local asset="$1"
  local label="$2"
  local output

  if ! output="$(
    gh release download "$tag" \
      --repo "$repo" \
      --dir "$tmp_dir" \
      --pattern "$asset" \
      --clobber 2>&1
  )"; then
    echo "missing: $label: $asset" >&2
    [ -z "$output" ] || printf '%s\n' "$output" >&2
    return 1
  fi

  if [ ! -s "$tmp_dir/$asset" ]; then
    echo "missing: $label: $asset" >&2
    return 1
  fi
}

check_published_vm_evidence_archive() {
  local asset="$vm_evidence_asset"
  local tmp_dir
  local vm_evidence_root

  if [ "$skip_gh" = "true" ]; then
    echo "skipped: live GitHub lookup disabled"
    return 0
  fi

  command -v gh >/dev/null 2>&1 || {
    echo "missing: gh is required to download the VM evidence release asset" >&2
    return 1
  }

  tmp_dir="$(mktemp -d)"
  cleanup_vm_archive() {
    rm -rf "$tmp_dir"
  }
  trap cleanup_vm_archive RETURN

  download_release_asset_or_explain "SHA256SUMS" "VM evidence archive checksum" || return 1
  download_release_asset_or_explain "SHA256SUMS.sig" "VM evidence archive checksum signature" || return 1
  download_release_asset_or_explain "$asset" "VM evidence archive asset" || return 1

  bash scripts/verify-release-asset-checksum.sh \
    --release-dir "$tmp_dir" \
    --asset "$asset" \
    --public-key "$public_key" \
    --label "VM evidence archive"

  bash scripts/extract-safe-tar.sh \
    --archive "$tmp_dir/$asset" \
    --output-dir "$tmp_dir/extracted" \
    --label "VM evidence archive" >/dev/null

  vm_evidence_root="$tmp_dir/extracted"
  if [ -d "$vm_evidence_root/.vm/evidence" ]; then
    vm_evidence_root="$vm_evidence_root/.vm/evidence"
  elif [ -d "$vm_evidence_root/vm-evidence" ]; then
    vm_evidence_root="$vm_evidence_root/vm-evidence"
  fi

  node scripts/verify-vm-evidence-archive-manifest.mjs \
    --manifest "$vm_evidence_root/manifest.json" \
    --tag "$tag" \
    --targets-file vm/targets.tsv \
    --require-all-targets \
    --evidence-root "$vm_evidence_root" \
    --verify-bundles \
    --require-published-release
}

check_release_tag_ref() {
  if [ "$skip_gh" = "true" ]; then
    echo "skipped: live GitHub lookup disabled"
    return 0
  fi

  bash scripts/verify-release-tag-ref.sh \
    --repo "$repo" \
    --tag "$tag" \
    --git-head "$expected_git_head"
}

check_published_release_evidence_archive() {
  local asset="$release_evidence_asset"
  local tmp_dir
  local evidence_root
  local evidence_dir=""
  local evidence_dirs=()

  if [ "$skip_gh" = "true" ]; then
    echo "skipped: live GitHub lookup disabled"
    return 0
  fi

  command -v gh >/dev/null 2>&1 || {
    echo "missing: gh is required to download the release evidence asset" >&2
    return 1
  }

  tmp_dir="$(mktemp -d)"
  cleanup_release_archive() {
    rm -rf "$tmp_dir"
  }
  trap cleanup_release_archive RETURN

  download_release_asset_or_explain "SHA256SUMS" "release evidence archive checksum" || return 1
  download_release_asset_or_explain "SHA256SUMS.sig" "release evidence archive checksum signature" || return 1
  download_release_asset_or_explain "$asset" "release evidence archive asset" || return 1

  bash scripts/verify-release-asset-checksum.sh \
    --release-dir "$tmp_dir" \
    --asset "$asset" \
    --public-key "$public_key" \
    --label "release evidence archive"

  bash scripts/extract-safe-tar.sh \
    --archive "$tmp_dir/$asset" \
    --output-dir "$tmp_dir/extracted" \
    --label "release evidence archive" >/dev/null

  evidence_root="$tmp_dir/extracted"
  if [ -f "$evidence_root/$tag/release-evidence.json" ]; then
    evidence_dir="$evidence_root/$tag"
  elif [ -f "$evidence_root/release-evidence.json" ]; then
    evidence_dir="$evidence_root"
  else
    while IFS= read -r candidate; do
      evidence_dirs+=("$candidate")
    done < <(find "$evidence_root" -mindepth 1 -maxdepth 1 -type d | sort)

    if [ "${#evidence_dirs[@]}" -eq 1 ] && [ -f "${evidence_dirs[0]}/release-evidence.json" ]; then
      evidence_dir="${evidence_dirs[0]}"
    else
      echo "release evidence archive must contain release-evidence.json or exactly one top-level evidence directory" >&2
      return 1
    fi
  fi

  node scripts/verify-release-evidence.mjs \
    --evidence-dir "$evidence_dir" \
    --public-key "$public_key" \
    --release-tag "$tag" \
    --repo "$repo" \
    --git-head "$expected_git_head" \
    --require-published-release \
    --require-dsp-provider-plan \
    --require-jack-provider-plan \
    --require-no-release-blockers
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

  if ! validation="$(node - "$label" "$expected_head" "$tag" "$output" <<'NODE' 2>&1
const [label, expectedHead, expectedTag, raw] = process.argv.slice(2);
let parsed;

try {
  parsed = JSON.parse(raw);
} catch (error) {
  console.error(`${label} did not return JSON: ${error.message}`);
  process.exit(1);
}

const runDescription = Array.isArray(parsed) ? "commit-scoped run" : "selected run";
const completedDescription = Array.isArray(parsed)
  ? "commit-scoped completed run"
  : "selected completed run";
const runs = Array.isArray(parsed) ? parsed : [parsed];
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
  console.error(`${label} ${runDescription} is not completed: ${run.status ?? "unknown"}.`);
  process.exit(1);
}

if (run.conclusion !== "success") {
  console.error(`${label} ${completedDescription} did not succeed: ${run.conclusion ?? "unknown"}.`);
  process.exit(1);
}

if (run.headSha !== expectedHead) {
  console.error(
    `${label} ${runDescription} is for ${run.headSha ?? "unknown"}, not expected commit ${expectedHead}.`
  );
  process.exit(1);
}

if (label === "commit-scoped Final Release Proof workflow run") {
  const expectedTitle = `Final Release Proof ${expectedTag} @ ${expectedHead}`;
  if (run.displayTitle !== expectedTitle) {
    console.error(
      `${label} ${runDescription} is titled ${run.displayTitle ?? "unknown"}, not ${expectedTitle}.`
    );
    process.exit(1);
  }
}

const fields = [
  run.databaseId ? `databaseId=${run.databaseId}` : null,
  run.headSha ? `headSha=${run.headSha}` : null,
  run.displayTitle ? `displayTitle=${run.displayTitle}` : null,
  run.url ? `url=${run.url}` : null
].filter(Boolean);
console.log(`${runDescription} verified: ${fields.join(" ")}`);
NODE
  )"; then
    echo "blocked: $label" >&2
    [ -z "$validation" ] || printf '%s\n' "$validation" | indent >&2
    [ -z "$output" ] || printf '%s\n' "$output" | indent >&2
    echo >&2
    return 1
  fi

  echo "ok: $label"
  if [ "$label" = "commit-scoped Deploy Docs workflow run" ] || [ "$label" = "Deploy Docs workflow run" ]; then
    latest_docs_deployment_run_id="$(workflow_run_id_from_json "$output")"
  fi
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
      public_key_explicit="true"
      shift 2
      ;;
    --git-head)
      expected_git_head="${2:?missing value for --git-head}"
      shift 2
      ;;
    --env-file)
      env_file="${2:?missing value for --env-file}"
      shift 2
      ;;
    --secret-list-file)
      secret_list_file="${2:?missing value for --secret-list-file}"
      shift 2
      ;;
    --docs-deployment-run-id)
      docs_deployment_run_id="${2:?missing value for --docs-deployment-run-id}"
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
    --vm-start-port)
      vm_start_port="${2:?missing value for --vm-start-port}"
      shift 2
      ;;
    --support-matrix)
      support_matrix="${2:?missing value for --support-matrix}"
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
validate_optional_asset "release-evidence" "$release_evidence_asset"
validate_optional_asset "vm-evidence" "$vm_evidence_asset"
release_evidence_asset="${release_evidence_asset:-loopwire-release-evidence-${tag}.tar.gz}"
vm_evidence_asset="${vm_evidence_asset:-loopwire-vm-evidence-${tag}.tar.gz}"
reject_unsafe_value "$public_key" "public key"
reject_unsafe_value "$expected_git_head" "git head"
[ -z "$env_file" ] || validate_local_path "$env_file" "env file" file
[ -z "$secret_list_file" ] || validate_local_path "$secret_list_file" "secret-list file" file
reject_unsafe_value "$docs_deployment_run_id" "docs deployment run id"
validate_local_path "$docs_deployment_manifest" "docs deployment manifest" file
validate_local_path "$docs_dist" "docs dist" dir
validate_local_path "$vm_evidence_root" "VM evidence root" dir
reject_unsafe_value "$vm_start_port" "VM start port"
validate_local_path "$support_matrix" "support matrix" file
validate_docs_deployment_run_id
validate_vm_start_port

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

run_gate \
  "release tag ref" \
  check_release_tag_ref || failed=1

run_gate \
  "published release evidence archive asset" \
  check_published_release_evidence_archive || failed=1

run_gate \
  "published VM evidence archive asset" \
  check_published_vm_evidence_archive || failed=1

run_workflow_probe \
  "commit-scoped CI workflow run" \
  "$expected_git_head" \
  gh run list --repo "$repo" --workflow ci.yml --commit "$expected_git_head" --limit 1 \
    --json databaseId,status,conclusion,headBranch,headSha,createdAt,url || failed=1

if [ -z "$docs_deployment_run_id" ]; then
  echo "==> verified Deploy Docs artifact run selection"
  if select_docs_deployment_run_id; then
    echo "ok: verified Deploy Docs artifact run selection"
    echo
  else
    echo "blocked: verified Deploy Docs artifact run selection" >&2
    echo >&2
    failed=1
  fi
fi

docs_artifact_run_id="$docs_deployment_run_id"
if [ -z "$docs_artifact_run_id" ]; then
  docs_artifact_run_id="$latest_docs_deployment_run_id"
fi
if [ -n "$docs_artifact_run_id" ]; then
  echo "==> verified Deploy Docs proof artifacts"
  if verify_docs_deployment_run_artifacts "$docs_artifact_run_id"; then
    docs_deployment_artifact_verification_failed="false"
    echo "ok: verified Deploy Docs proof artifacts"
    echo
  else
    docs_deployment_artifact_verification_failed="true"
    echo "blocked: verified Deploy Docs proof artifacts" >&2
    echo >&2
    failed=1
  fi
elif [ "$skip_gh" != "true" ]; then
  echo "==> verified Deploy Docs proof artifacts"
  echo "blocked: verified Deploy Docs proof artifacts" >&2
  echo "missing: no artifact-bearing Deploy Docs run id selected" >&2
  echo >&2
  docs_deployment_artifact_verification_failed="true"
  failed=1
fi

docs_workflow_label="commit-scoped Deploy Docs workflow run"
docs_workflow_probe=(gh run list --repo "$repo" --workflow deploy-docs.yml --commit "$expected_git_head" --limit 1 \
  --json databaseId,status,conclusion,headBranch,headSha,createdAt,url)
if [ -n "$docs_deployment_run_id" ]; then
  docs_workflow_label="Deploy Docs workflow run"
  docs_workflow_probe=(gh run view "$docs_deployment_run_id" --repo "$repo" \
    --json databaseId,status,conclusion,headBranch,headSha,createdAt,url)
elif [ -n "$latest_docs_deployment_run_id" ]; then
  docs_workflow_label="Deploy Docs workflow run"
  docs_workflow_probe=(gh run view "$latest_docs_deployment_run_id" --repo "$repo" \
    --json databaseId,status,conclusion,headBranch,headSha,createdAt,url)
elif [ "$skip_gh" != "true" ]; then
  docs_workflow_probe=(bash -c 'echo "artifact-aware Deploy Docs run selection did not produce a run id" >&2; exit 1')
fi
run_workflow_probe \
  "$docs_workflow_label" \
  "$expected_git_head" \
  "${docs_workflow_probe[@]}" || failed=1

run_gate \
  "docs deployment manifest" \
  check_docs_deployment_manifest || failed=1

run_workflow_probe \
  "commit-scoped Final Release Proof workflow run" \
  "$expected_git_head" \
  gh run list --repo "$repo" --workflow final-release-proof.yml --commit "$expected_git_head" --limit 1 \
    --json databaseId,status,conclusion,headBranch,headSha,displayTitle,createdAt,url || failed=1

run_vm_evidence_gate \
  "published-release-bound VM evidence" \
  bash scripts/vm-matrix.sh evidence-status --all --evidence-root "$vm_evidence_root" \
    --start-port "$vm_start_port" \
    --require-published-release --release-tag "$tag" || failed=1

run_gate \
  "support matrix published-release claims" \
  node scripts/verify-support-matrix.mjs --matrix "$support_matrix" \
    --evidence-root "$vm_evidence_root" \
    --require-published-release --release-tag "$tag" || failed=1

handoff_plan=(bash scripts/plan-final-release-handoff.sh --repo "$repo" --tag "$tag" \
  --git-head "$expected_git_head" \
  --vm-start-port "$vm_start_port" \
  --vm-evidence-root "$vm_evidence_root" \
  --support-matrix "$support_matrix" \
  --release-evidence-asset "$release_evidence_asset" \
  --vm-evidence-asset "$vm_evidence_asset")
if [ -z "$env_file" ] || [ "$public_key_explicit" = "true" ]; then
  handoff_plan+=(--public-key "$public_key")
fi
if [ -n "$env_file" ]; then
  handoff_plan+=(--env-file "$env_file")
fi
if [ -n "$latest_docs_deployment_run_id" ] && [ "$docs_deployment_artifact_verification_failed" != "true" ]; then
  handoff_plan+=(--docs-deployment-run-id "$latest_docs_deployment_run_id")
fi
run_gate \
  "local final release handoff plan" \
  "${handoff_plan[@]}" || failed=1

if [ "$failed" -ne 0 ]; then
  echo "Final release status: blocked" >&2
  exit 1
fi

echo "Final release status: ready"
