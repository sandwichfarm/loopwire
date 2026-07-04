#!/usr/bin/env bash
set -euo pipefail

repo="${LOOPWIRE_GITHUB_REPO:-sandwichfarm/loopwire}"
tag="${LOOPWIRE_RELEASE_TAG:-}"
public_key="${LOOPWIRE_RELEASE_PUBLIC_KEY:-packaging/release-signing-public.pem}"
git_head="${LOOPWIRE_RELEASE_COMMIT:-}"
release_dir=""
release_evidence_dir="${LOOPWIRE_RELEASE_EVIDENCE_DIR:-}"
docs_base_url="${LOOPWIRE_DOCS_BASE_URL:-}"
docs_hostname="${BUNNY_PULL_ZONE_HOSTNAME:-}"
docs_remote_prefix="${BUNNY_REMOTE_PREFIX:-}"
vm_evidence_root="${LOOPWIRE_VM_EVIDENCE_ROOT:-.vm/evidence}"
support_matrix="${LOOPWIRE_SUPPORT_MATRIX:-apps/docs/docs/guide/support-matrix.md}"
dry_run="false"
plan_output=""

usage() {
  cat <<'USAGE'
Verify the full Loopwire final release proof surface.

Usage:
  verify-final-release-proof.sh --repo OWNER/REPO --tag vX.Y.Z --public-key FILE --git-head SHA \
    --release-evidence-dir DIR --docs-base-url URL [--vm-evidence-root DIR] [--support-matrix FILE] [--dry-run]
  verify-final-release-proof.sh --repo OWNER/REPO --tag vX.Y.Z --public-key FILE --git-head SHA \
    --release-evidence-dir DIR --docs-hostname HOST [--docs-remote-prefix PATH] [--vm-evidence-root DIR] \
    [--support-matrix FILE] [--dry-run]

Checks:
  - signed published release assets plus public release evidence archive,
  - deployed docs homepage and public /install.sh,
  - final release-evidence.json with published release, live docs, DSP plan, all VM targets, clean git, and no blockers,
  - matrix-wide dry-run VM launch plan paired to evidence-pull commands,
  - every target under vm/targets.tsv has VM evidence with installed-release smoke,
  - support matrix rows match target metadata and verified VM evidence,
  - docs contract still passes after support-matrix promotion.

Use --release-dir DIR for local signed release-directory proof instead of downloading from GitHub.
Use --dry-run to print the exact command plan without touching network, release assets, docs URLs, or VM evidence.
Use --plan-output FILE with --dry-run to also write that command plan to a handoff artifact.
USAGE
}

fail() {
  echo "verify-final-release-proof: $*" >&2
  exit 1
}

quote_command() {
  local quoted=()
  local arg

  for arg in "$@"; do
    quoted+=("$(printf '%q' "$arg")")
  done

  printf '%s\n' "${quoted[*]}"
}

emit_line() {
  local line="$1"

  printf '%s\n' "$line"
  [ -z "$plan_output" ] || printf '%s\n' "$line" >>"$plan_output"
}

run_step() {
  local label="$1"
  shift

  if [ "$dry_run" = "true" ]; then
    emit_line "dry-run: ${label}: $(quote_command "$@")"
    return
  fi

  "$@"
}

validate_release_tag() {
  local value="$1"
  local pattern='^v[0-9]+[.][0-9]+[.][0-9]+([.-][0-9A-Za-z][0-9A-Za-z.-]*)?$'

  [[ "$value" =~ $pattern ]] || fail "tag must be v-prefixed semver without path separators: $value"
}

validate_repo() {
  local value="$1"
  local pattern='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'

  [[ "$value" =~ $pattern ]] || fail "repository must use OWNER/REPO without URLs, spaces, or extra path segments: $value"
}

validate_git_head() {
  local value="$1"

  [[ "$value" =~ ^[0-9a-fA-F]{40}$ ]] || fail "git head must be a 40-character commit SHA: $value"
}

reject_unsafe_value() {
  local value="$1"
  local label="$2"

  case "$value" in
    *$'\n'* | *$'\r'*)
      fail "$label must be a single safe value"
      ;;
  esac
}

validate_docs_remote_prefix() {
  local value="$1"

  reject_unsafe_value "$value" "docs remote prefix"
  value="${value#/}"
  value="${value%/}"
  case "$value" in
    "." | ".." | ./* | ../* | */../* | */.. | */./* | */.)
      fail "docs remote prefix must not contain . or .. path segments"
      ;;
  esac
}

target_ids() {
  awk -F '\t' 'NF && $1 !~ /^#/ { print $1 }' vm/targets.tsv
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
      git_head="${2:?missing value for --git-head}"
      shift 2
      ;;
    --release-dir)
      release_dir="${2:?missing value for --release-dir}"
      shift 2
      ;;
    --release-evidence-dir)
      release_evidence_dir="${2:?missing value for --release-evidence-dir}"
      shift 2
      ;;
    --docs-base-url)
      docs_base_url="${2:?missing value for --docs-base-url}"
      shift 2
      ;;
    --docs-hostname)
      docs_hostname="${2:?missing value for --docs-hostname}"
      shift 2
      ;;
    --docs-remote-prefix)
      docs_remote_prefix="${2:?missing value for --docs-remote-prefix}"
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
    --dry-run)
      dry_run="true"
      shift
      ;;
    --plan-output)
      plan_output="${2:?missing value for --plan-output}"
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
[ -n "$tag" ] || fail "missing --tag vX.Y.Z"
[ -n "$public_key" ] || fail "missing --public-key FILE"
[ -n "$git_head" ] || fail "missing --git-head SHA"
[ -n "$release_evidence_dir" ] || fail "missing --release-evidence-dir DIR"
validate_repo "$repo"
validate_release_tag "$tag"
validate_git_head "$git_head"
reject_unsafe_value "$public_key" "public key path"
reject_unsafe_value "$release_evidence_dir" "release evidence directory"
reject_unsafe_value "$vm_evidence_root" "VM evidence root"
reject_unsafe_value "$support_matrix" "support matrix path"
if [ -n "$plan_output" ]; then
  reject_unsafe_value "$plan_output" "plan output path"
  [ "$dry_run" = "true" ] || fail "--plan-output requires --dry-run"
  : >"$plan_output" || fail "cannot write plan output: $plan_output"
fi

if [ -n "$docs_base_url" ] && [ -n "$docs_hostname" ]; then
  fail "use either --docs-base-url or --docs-hostname, not both"
fi
[ -n "$docs_base_url" ] || [ -n "$docs_hostname" ] || fail "missing --docs-base-url or --docs-hostname"

if [ -n "$docs_base_url" ]; then
  reject_unsafe_value "$docs_base_url" "docs base URL"
  case "$docs_base_url" in
    http://* | https://*) ;;
    *) fail "docs base URL must start with http:// or https://" ;;
  esac
else
  reject_unsafe_value "$docs_hostname" "docs hostname"
  case "$docs_hostname" in
    http://* | https://* | */*) fail "docs hostname must be a hostname, not a URL or path" ;;
  esac
  validate_docs_remote_prefix "$docs_remote_prefix"
fi

if [ "$dry_run" != "true" ]; then
  [ -f "$public_key" ] || fail "missing public key: $public_key"
  [ -d "$release_evidence_dir" ] || fail "missing release evidence directory: $release_evidence_dir"
  [ -d "$vm_evidence_root" ] || fail "missing VM evidence root: $vm_evidence_root"
  [ -s "$support_matrix" ] || fail "missing support matrix: $support_matrix"
fi

published_release=(
  bash scripts/verify-published-release.sh
  --repo "$repo"
  --tag "$tag"
  --public-key "$public_key"
  --git-head "$git_head"
  --require-release-evidence
)
if [ -n "$release_dir" ]; then
  published_release=(
    bash scripts/verify-published-release.sh
    --release-dir "$release_dir"
    --repo "$repo"
    --tag "$tag"
    --public-key "$public_key"
    --git-head "$git_head"
    --require-release-evidence
  )
fi
run_step "published release" "${published_release[@]}"

docs_live=(bash scripts/verify-docs-live.sh --expected-installer apps/docs/docs/public/install.sh)
if [ -n "$docs_base_url" ]; then
  docs_live+=(--base-url "$docs_base_url")
else
  docs_live+=(--hostname "$docs_hostname")
  [ -z "$docs_remote_prefix" ] || docs_live+=(--remote-prefix "$docs_remote_prefix")
fi
run_step "live docs" "${docs_live[@]}"

run_step "release evidence" \
  node scripts/verify-release-evidence.mjs \
  --evidence-dir "$release_evidence_dir" \
  --release-tag "$tag" \
  --repo "$repo" \
  --public-key "$public_key" \
  --git-head "$git_head" \
  --require-published-release \
  --require-live-docs \
  --require-vm-evidence \
  --require-all-vm-targets \
  --require-vm-launch-plan \
  --require-dsp-provider-plan \
  --require-no-release-blockers \
  --require-clean-git

while IFS= read -r target; do
  [ -n "$target" ] || continue
  run_step "VM evidence ${target}" \
    bash scripts/verify-vm-evidence.sh \
    --target "$target" \
    --evidence-dir "$vm_evidence_root/$target" \
    --require-published-release
done < <(target_ids)

run_step "support matrix" \
  node scripts/verify-support-matrix.mjs \
  --evidence-root "$vm_evidence_root" \
  --matrix "$support_matrix" \
  --require-published-release
run_step "docs contract" pnpm verify:docs

if [ "$dry_run" = "true" ]; then
  emit_line "Final release proof dry-run complete."
else
  echo "Final release proof verified for ${repo}@${tag}."
fi
