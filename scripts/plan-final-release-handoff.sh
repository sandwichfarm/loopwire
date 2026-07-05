#!/usr/bin/env bash
set -euo pipefail

repo=""
tag=""
git_head=""
public_key="packaging/release-signing-public.pem"
release_private_key_file="<release-private-key-file>"
env_file=""
docs_deployment_run_id=""
docs_base_url=""
docs_hostname=""
docs_remote_prefix=""
release_evidence_asset=""
vm_evidence_asset=""
vm_image_root="/operator/images"
vm_start_port="2600"
vm_ssh_plan="dist/release/vm-ssh-plan.tsv"
vm_runbook="dist/release/vm-runbook.md"
support_matrix="apps/docs/docs/guide/support-matrix.md"
secret_list_file=""
public_key_explicit="false"
release_private_key_file_explicit="false"
docs_hostname_explicit="false"
docs_remote_prefix_explicit="false"

usage() {
  cat <<'USAGE'
Render the no-side-effect final release handoff plan.

Usage:
  plan-final-release-handoff.sh --repo OWNER/REPO --tag vX.Y.Z [options]

Options:
  --git-head SHA                    Expected release commit, default current HEAD
  --public-key FILE                 Release public key, default packaging/release-signing-public.pem
  --release-private-key-file FILE   Local release private key used by VM evidence asset prep
  --env-file FILE                   Local setup env file; reads safe handoff paths/host fields only
  --docs-deployment-run-id ID       Successful Deploy Docs workflow run id for final proof
  --docs-base-url URL               Live docs base URL override for final proof
  --docs-hostname HOST              Bunny pull-zone hostname for final proof
  --docs-remote-prefix PATH         Optional Bunny remote prefix
  --release-evidence-asset NAME     Optional release evidence asset override
  --vm-evidence-asset NAME          Optional VM evidence asset override
  --vm-image-root DIR               Operator VM image root, default /operator/images
  --vm-start-port PORT              SSH start port for rendered VM handoff, default 2600
  --vm-ssh-plan FILE                Rendered SSH collection plan, default dist/release/vm-ssh-plan.tsv
  --vm-runbook FILE                 Rendered VM runbook path, default dist/release/vm-runbook.md
  --support-matrix FILE             Support matrix path, default apps/docs/docs/guide/support-matrix.md
  --secret-list-file FILE           Names-only `gh secret list` artifact for readiness rehearsal

The script prints commands only. It does not set secrets, create tags, dispatch workflows, upload assets, or mutate host
audio. Missing docs deployment run id is rendered as a placeholder because it is only known after Deploy Docs completes.
Operator-only activities such as filling secrets, dispatching workflows, running VM guests, and uploading release
evidence are intentionally deferred until after the repository is agent-ready.
The env file accepts the same keys as scripts/setup-github-secrets.sh --env-file, but this handoff only consumes
LOOPWIRE_RELEASE_PRIVATE_KEY_FILE, LOOPWIRE_RELEASE_PUBLIC_KEY_FILE, BUNNY_PULL_ZONE_HOSTNAME, and BUNNY_REMOTE_PREFIX.
USAGE
}

fail() {
  echo "plan-final-release-handoff: $*" >&2
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

validate_tag() {
  local pattern='^v[0-9]+[.][0-9]+[.][0-9]+([.-][0-9A-Za-z][0-9A-Za-z.-]*)?$'
  [[ "$tag" =~ $pattern ]] || fail "release tag must be v-prefixed semver without path separators: $tag"
}

validate_git_head() {
  local pattern='^[0-9a-fA-F]{40}$'
  [[ "$git_head" =~ $pattern ]] || fail "git head must be a 40-character SHA: $git_head"
}

validate_docs_run_id() {
  [ -z "$docs_deployment_run_id" ] || [[ "$docs_deployment_run_id" =~ ^[0-9]+$ ]] ||
    fail "docs deployment run id must be numeric: $docs_deployment_run_id"
}

validate_port() {
  [[ "$vm_start_port" =~ ^[0-9]+$ ]] || fail "VM start port must be numeric: $vm_start_port"
  if [ "$vm_start_port" -lt 1 ] || [ "$vm_start_port" -gt 65535 ]; then
    fail "VM start port must be in 1..65535: $vm_start_port"
  fi
}

validate_repo_relative_output_path() {
  local value="$1"
  local label="$2"
  local normalized

  normalized="${value#./}"
  case "$normalized" in
    /* | ~* | *://* | "" | . | .. | ../* | */../* | */.. | */./* | */.)
      fail "$label must be a repo-relative output path without . or .. segments: $value"
      ;;
  esac
}

validate_optional_asset() {
  local kind="$1"
  local asset="$2"

  [ -z "$asset" ] || bash scripts/validate-release-asset-name.sh --kind "$kind" --tag "$tag" --asset "$asset" >/dev/null
}

strip_wrapping_quotes() {
  local value="$1"

  case "$value" in
    \"*\")
      value="${value#\"}"
      value="${value%\"}"
      ;;
    \'*\')
      value="${value#\'}"
      value="${value%\'}"
      ;;
  esac

  printf '%s\n' "$value"
}

assign_env_file_value() {
  local key="$1"
  local value="$2"

  reject_unsafe_value "$value" "env-file value for ${key}"

  case "$key" in
    LOOPWIRE_RELEASE_PRIVATE_KEY_FILE)
      [ "$release_private_key_file_explicit" = "true" ] || release_private_key_file="$value"
      ;;
    LOOPWIRE_RELEASE_PUBLIC_KEY_FILE)
      [ "$public_key_explicit" = "true" ] || public_key="$value"
      ;;
    BUNNY_PULL_ZONE_HOSTNAME)
      [ "$docs_hostname_explicit" = "true" ] || docs_hostname="$value"
      ;;
    BUNNY_REMOTE_PREFIX)
      [ "$docs_remote_prefix_explicit" = "true" ] || docs_remote_prefix="$value"
      ;;
    BUNNY_STORAGE_ZONE | BUNNY_ACCESS_KEY | BUNNY_STORAGE_ENDPOINT)
      ;;
    *)
      fail "unsupported key in --env-file: $key"
      ;;
  esac
}

load_env_file() {
  local line
  local line_no=0
  local key
  local value

  [ -f "$env_file" ] || fail "env file does not exist: $env_file"

  while IFS= read -r line || [ -n "$line" ]; do
    line_no=$((line_no + 1))
    line="${line%$'\r'}"

    case "$line" in
      "" | \#*)
        continue
        ;;
      export\ *)
        line="${line#export }"
        ;;
    esac

    case "$line" in
      *=*)
        key="${line%%=*}"
        value="${line#*=}"
        ;;
      *)
        fail "invalid --env-file line ${line_no}: expected KEY=VALUE"
        ;;
    esac

    case "$key" in
      *[!A-Z0-9_]* | "")
        fail "invalid --env-file key on line ${line_no}: $key"
        ;;
    esac

    value="$(strip_wrapping_quotes "$value")"
    assign_env_file_value "$key" "$value"
  done <"$env_file"
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

print_command() {
  printf '  %s\n' "$(shell_join "$@")"
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
      public_key_explicit="true"
      shift 2
      ;;
    --release-private-key-file)
      release_private_key_file="${2:?missing value for --release-private-key-file}"
      release_private_key_file_explicit="true"
      shift 2
      ;;
    --env-file)
      env_file="${2:?missing value for --env-file}"
      shift 2
      ;;
    --docs-deployment-run-id)
      docs_deployment_run_id="${2:?missing value for --docs-deployment-run-id}"
      shift 2
      ;;
    --docs-base-url)
      docs_base_url="${2:?missing value for --docs-base-url}"
      shift 2
      ;;
    --docs-hostname)
      docs_hostname="${2:?missing value for --docs-hostname}"
      docs_hostname_explicit="true"
      shift 2
      ;;
    --docs-remote-prefix)
      docs_remote_prefix="${2:?missing value for --docs-remote-prefix}"
      docs_remote_prefix_explicit="true"
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
    --vm-image-root)
      vm_image_root="${2:?missing value for --vm-image-root}"
      shift 2
      ;;
    --vm-start-port)
      vm_start_port="${2:?missing value for --vm-start-port}"
      shift 2
      ;;
    --vm-ssh-plan)
      vm_ssh_plan="${2:?missing value for --vm-ssh-plan}"
      shift 2
      ;;
    --vm-runbook)
      vm_runbook="${2:?missing value for --vm-runbook}"
      shift 2
      ;;
    --support-matrix)
      support_matrix="${2:?missing value for --support-matrix}"
      shift 2
      ;;
    --secret-list-file)
      secret_list_file="${2:?missing value for --secret-list-file}"
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

if [ -n "$env_file" ]; then
  load_env_file
fi

if [ -z "$git_head" ]; then
  git_head="$(git rev-parse HEAD 2>/dev/null || true)"
fi

validate_repo
validate_tag
validate_git_head
validate_docs_run_id
validate_port
validate_repo_relative_output_path "$vm_ssh_plan" "VM SSH plan"
validate_repo_relative_output_path "$vm_runbook" "VM runbook"
validate_optional_asset "release-evidence" "$release_evidence_asset"
validate_optional_asset "vm-evidence" "$vm_evidence_asset"

reject_unsafe_value "$public_key" "public key"
reject_unsafe_value "$release_private_key_file" "release private key"
reject_unsafe_value "$docs_base_url" "docs base URL"
reject_unsafe_value "$docs_hostname" "docs hostname"
reject_unsafe_value "$docs_remote_prefix" "docs remote prefix"
reject_unsafe_value "$vm_image_root" "VM image root"
reject_unsafe_value "$vm_ssh_plan" "VM SSH plan"
reject_unsafe_value "$vm_runbook" "VM runbook"
reject_unsafe_value "$support_matrix" "support matrix"
reject_unsafe_value "$secret_list_file" "secret-list file"

docs_run_id="${docs_deployment_run_id:-<docs-deployment-run-id>}"
release_evidence_asset="${release_evidence_asset:-loopwire-release-evidence-${tag}.tar.gz}"
vm_evidence_asset="${vm_evidence_asset:-loopwire-vm-evidence-${tag}.tar.gz}"

echo "Final release handoff plan for ${repo}@${tag}"
echo
echo "Operator-deferred after agent delivery:"
echo "- Fill the local release secret env file and set GitHub secrets; do not commit secret values."
echo "- Create or push the release tag only after strict readiness passes."
echo "- Dispatch release/docs/final-proof workflows from protected GitHub surfaces."
echo "- Run VM guests and upload signed evidence from operator-controlled hosts."
echo
echo "Create the no-value secret env template when needed:"
print_command bash scripts/setup-github-secrets.sh --write-env-template /secure/loopwire-release-secrets.env
echo
echo "1. Verify agent-ready release automation for this exact commit:"
print_command pnpm release:agent-ready -- --repo "$repo" --tag "$tag" \
  --git-head "$git_head" --public-key "$public_key" --require-hosted-checks
echo
echo "2. Verify required GitHub secrets are ready:"
secret_check=(bash scripts/setup-github-secrets.sh --repo "$repo" --check)
if [ -n "$env_file" ]; then
  secret_check+=(--env-file "$env_file")
fi
if [ -n "$secret_list_file" ]; then
  secret_check+=(--secret-list-file "$secret_list_file")
fi
print_command "${secret_check[@]}"
echo
echo "3. Run strict release readiness before tagging or dispatch:"
readiness=(pnpm verify:release-readiness -- --repo "$repo" --tag "$tag" --public-key "$public_key")
if [ -n "$secret_list_file" ]; then
  readiness+=(--secret-list-file "$secret_list_file")
fi
print_command "${readiness[@]}"
echo
echo "4. Create or push the reviewed release tag after readiness passes:"
print_command git tag -a "$tag" "$git_head" -m "Loopwire ${tag}"
print_command git push origin "refs/tags/${tag}"
echo
echo "5. Dispatch the GitHub Release workflow after the tag exists:"
print_command gh workflow run release.yml --repo "$repo" --ref "$tag" -f "tag=${tag}"
echo
echo "6. Dispatch docs deployment for the same release ref:"
print_command gh workflow run deploy-docs.yml --repo "$repo" --ref "$tag"
echo
echo "7. Download and verify docs deployment proof artifacts:"
fetch_docs_proof=(pnpm release:fetch-docs-proof -- --repo "$repo" --run-id "$docs_run_id" --git-head "$git_head")
if [ -n "$env_file" ]; then
  fetch_docs_proof+=(--env-file "$env_file")
fi
print_command "${fetch_docs_proof[@]}"
echo
echo "8. Render the operator VM evidence handoff:"
print_command pnpm vm:host-setup -- --all
print_command pnpm vm:doctor -- --all
print_command pnpm vm:render-ssh-plan -- --all --start-port "$vm_start_port" --output "$vm_ssh_plan"
print_command pnpm vm:render-runbook -- --all --image-root "$vm_image_root" --start-port "$vm_start_port" --output "$vm_runbook"
print_command pnpm vm:collect-matrix -- --plan "$vm_ssh_plan" --published-release-repo "$repo" \
  --published-release-tag "$tag" --release-public-key "$public_key" --require-published-release \
  --require-github-release-source --require-all-targets --execute
vm_prepare=(pnpm vm:prepare-release-evidence -- --tag "$tag" --repo "$repo" --all)
if [ -n "$env_file" ]; then
  vm_prepare+=(--env-file "$env_file")
  if [ "$release_private_key_file_explicit" = "true" ]; then
    vm_prepare+=(--private-key "$release_private_key_file")
  fi
  if [ "$public_key_explicit" = "true" ]; then
    vm_prepare+=(--public-key "$public_key")
  fi
else
  vm_prepare+=(--private-key "$release_private_key_file" --public-key "$public_key")
fi
print_command "${vm_prepare[@]}"
echo
echo "9. Dispatch final release proof after docs and VM evidence assets exist:"
final_proof=(gh workflow run final-release-proof.yml --repo "$repo" --ref "$tag" \
  -f "tag=${tag}" \
  -f "git_head=${git_head}" \
  -f "docs_deployment_run_id=${docs_run_id}" \
  -f "release_evidence_asset=${release_evidence_asset}" \
  -f "vm_evidence_asset=${vm_evidence_asset}")
if [ -n "$docs_base_url" ]; then
  final_proof+=(-f "docs_base_url=${docs_base_url}")
else
  [ -z "$docs_hostname" ] || final_proof+=(-f "docs_hostname=${docs_hostname}")
  [ -z "$docs_remote_prefix" ] || final_proof+=(-f "docs_remote_prefix=${docs_remote_prefix}")
fi
print_command "${final_proof[@]}"
echo
echo "10. Local dry-run of the final proof command plan:"
local_final=(pnpm verify:final-release -- --repo "$repo" --tag "$tag" --public-key "$public_key" \
  --git-head "$git_head" \
  --release-evidence-dir ".release-evidence/${tag}-published" \
  --docs-deployment-manifest "dist/docs-deployment/deployment-manifest.json" \
  --vm-evidence-root ".vm/evidence" \
  --support-matrix "$support_matrix" \
  --dry-run \
  --plan-output "dist/release/final-release-proof-plan.txt")
if [ -n "$docs_base_url" ]; then
  local_final+=(--docs-base-url "$docs_base_url")
else
  local_final+=(--docs-hostname "${docs_hostname:-<bunny-pull-zone-hostname>}")
  [ -z "$docs_remote_prefix" ] || local_final+=(--docs-remote-prefix "$docs_remote_prefix")
fi
print_command "${local_final[@]}"

if [ -z "$docs_deployment_run_id" ]; then
  docs_run_reminder="operator-deferred: replace <docs-deployment-run-id> with the successful "
  docs_run_reminder+="Deploy Docs workflow run id before steps 7 and 9."
  echo
  echo "$docs_run_reminder"
fi
if [ "$release_private_key_file" = "<release-private-key-file>" ]; then
  echo "operator-deferred: pass --release-private-key-file or --env-file before preparing signed VM evidence release assets."
fi
