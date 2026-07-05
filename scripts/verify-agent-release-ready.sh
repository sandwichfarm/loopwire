#!/usr/bin/env bash
set -euo pipefail

repo=""
tag=""
git_head=""
public_key="packaging/release-signing-public.pem"
skip_local_gates="false"

usage() {
  cat <<'USAGE'
Verify repo-side release readiness before operator-only final ceremony.

Usage:
  verify-agent-release-ready.sh --repo OWNER/REPO --tag vX.Y.Z [options]

Options:
  --git-head SHA         Expected release/source commit, default current checkout HEAD
  --public-key FILE      Release public key, default packaging/release-signing-public.pem
  --skip-local-gates     Only verify offline release readiness and handoff rendering

This command is read-only. It does not set secrets, create tags, dispatch workflows, upload assets, launch VMs, or
mutate host audio. Passing means the repository-side automation is ready for the operator-deferred release ceremony;
strict final proof still requires published artifacts, Bunny deployment proof, final proof workflow success, and VM
evidence captured from operator-controlled hosts.
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
    --skip-local-gates)
      skip_local_gates="true"
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
reject_unsafe_value "$public_key" "public key"

echo "Agent-ready release check for ${repo}@${tag}"
echo "Expected release commit: ${git_head}"
echo

run_gate \
  "offline release readiness" \
  bash scripts/verify-release-readiness.sh --repo "$repo" --tag "$tag" \
    --public-key "$public_key" --skip-gh --skip-tag --skip-clean-git

echo "==> final release handoff rendering"
handoff="$(
  bash scripts/plan-final-release-handoff.sh --repo "$repo" --tag "$tag" \
    --git-head "$git_head" --public-key "$public_key"
)"
assert_handoff_contains "$handoff" "Operator-deferred after agent delivery"
assert_handoff_contains "$handoff" "bash scripts/setup-github-secrets.sh --write-env-template /secure/loopwire-release-secrets.env"
assert_handoff_contains "$handoff" "operator-deferred: replace <docs-deployment-run-id>"
assert_handoff_contains "$handoff" "operator-deferred: pass --release-private-key-file or --env-file"
echo "ok: final release handoff rendering"
printf '%s\n' "$handoff" | indent
echo

if [ "$skip_local_gates" != "true" ]; then
  run_gate "workflow contracts" bash scripts/verify-github-workflows.sh
  run_gate "documentation contracts" bash scripts/verify-docs.sh
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
