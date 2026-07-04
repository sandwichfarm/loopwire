#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_file="${LOOPWIRE_VM_TARGETS:-$root/vm/targets.tsv}"

target=""
host=""
user="loopwire"
port="2222"
identity_file=""
remote_repo="loopwire"
remote_output_dir=""
local_output_dir=""
screenshot_command=""
desktop_port=""
published_release_dir=""
published_release_repo=""
published_release_tag=""
release_public_key=""
require_published_release="false"
operator_note=""
execute="false"

usage() {
  cat <<'USAGE'
Collect Loopwire VM evidence from a reachable guest over SSH.

Usage:
  collect-vm-evidence-ssh.sh --target TARGET --host HOST [options]

Options:
  --user USER                       SSH user. Defaults to loopwire.
  --port PORT                       SSH port. Defaults to 2222.
  --identity FILE                   SSH private key path.
  --remote-repo DIR                 Remote Loopwire checkout. Defaults to loopwire.
  --remote-output-dir DIR           Remote evidence dir. Defaults to .vm/evidence/TARGET.
  --local-output-dir DIR            Local evidence dir. Defaults to .vm/evidence/TARGET.
  --screenshot-command CMD          Guest screenshot command for collect-vm-evidence.sh.
  --desktop-port PORT               Guest desktop launch smoke port for collect-vm-evidence.sh.
  --published-release-dir DIR       Guest-visible signed release directory for installed-release smoke.
  --published-release-repo REPO     GitHub repository for installed-release smoke.
  --published-release-tag TAG       GitHub release tag for installed-release smoke.
  --release-public-key FILE         Guest-visible release public key for signature verification.
  --require-published-release       Require installed-release smoke in guest evidence verification.
  --note TEXT                       Append operator context to guest notes.md.
  --execute                         Run SSH/SCP and verify local evidence. Default is dry-run.

Dry-run prints the exact SSH, SCP, and verifier commands without writing files or touching the guest.
USAGE
}

fail() {
  echo "collect-vm-evidence-ssh: $*" >&2
  exit 1
}

validate_tcp_port() {
  port="$1"
  label="$2"

  case "$port" in
    "" | *[!0-9]*)
      fail "$label must be a number from 1 to 65535"
      ;;
  esac

  if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    fail "$label must be a number from 1 to 65535"
  fi
}

quote_cmd() {
  printf '%q' "$1"
}

print_command() {
  printf '  '
  printf '%q ' "$@"
  printf '\n'
}

known_target() {
  local id="$1"
  [ -f "$target_file" ] || fail "missing target file: $target_file"
  awk -F '\t' -v id="$id" '$1 == id { found = 1 } END { exit found ? 0 : 1 }' "$target_file"
}

remote_evidence_path() {
  case "$remote_output_dir" in
    /*)
      printf '%s\n' "$remote_output_dir"
      ;;
    *)
      printf '%s/%s\n' "$remote_repo" "$remote_output_dir"
      ;;
  esac
}

ssh_target() {
  printf '%s@%s\n' "$user" "$host"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --)
      shift
      ;;
    --target)
      target="${2:-}"
      shift 2
      ;;
    --host)
      host="${2:-}"
      shift 2
      ;;
    --user)
      user="${2:-}"
      shift 2
      ;;
    --port)
      port="${2:-}"
      shift 2
      ;;
    --identity)
      identity_file="${2:-}"
      shift 2
      ;;
    --remote-repo)
      remote_repo="${2:-}"
      shift 2
      ;;
    --remote-output-dir)
      remote_output_dir="${2:-}"
      shift 2
      ;;
    --local-output-dir)
      local_output_dir="${2:-}"
      shift 2
      ;;
    --screenshot-command)
      screenshot_command="${2:-}"
      shift 2
      ;;
    --desktop-port)
      desktop_port="${2:-}"
      shift 2
      ;;
    --published-release-dir)
      published_release_dir="${2:-}"
      shift 2
      ;;
    --published-release-repo)
      published_release_repo="${2:-}"
      shift 2
      ;;
    --published-release-tag)
      published_release_tag="${2:-}"
      shift 2
      ;;
    --release-public-key)
      release_public_key="${2:-}"
      shift 2
      ;;
    --require-published-release)
      require_published_release="true"
      shift
      ;;
    --note)
      operator_note="${2:-}"
      shift 2
      ;;
    --execute)
      execute="true"
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

[ -n "$target" ] || fail "missing --target"
[ -n "$host" ] || fail "missing --host"
known_target "$target" || fail "unknown VM target: $target"
validate_tcp_port "$port" "--port"
if [ -n "$desktop_port" ]; then
  validate_tcp_port "$desktop_port" "--desktop-port"
fi

if [ -n "$published_release_dir" ] && [ -n "$published_release_repo" ]; then
  fail "use either --published-release-dir or --published-release-repo, not both"
fi

if [ "$require_published_release" = "true" ] && [ -z "$published_release_dir" ] && [ -z "$published_release_repo" ]; then
  fail "--require-published-release requires --published-release-dir or --published-release-repo"
fi

if [ -n "$published_release_dir" ] || [ -n "$published_release_repo" ]; then
  [ -n "$release_public_key" ] || fail "published release smoke requires --release-public-key"
  if [ -n "$published_release_repo" ] && [ -z "$published_release_tag" ]; then
    fail "--published-release-repo requires --published-release-tag"
  fi
fi

remote_output_dir="${remote_output_dir:-.vm/evidence/$target}"
local_output_dir="${local_output_dir:-.vm/evidence/$target}"

ssh_args=(-p "$port" -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
scp_args=(-P "$port" -o BatchMode=yes -o StrictHostKeyChecking=accept-new)

if [ -n "$identity_file" ]; then
  ssh_args+=(-i "$identity_file")
  scp_args+=(-i "$identity_file")
fi

collector_args=(--target "$target" --output-dir "$remote_output_dir")

if [ -n "$screenshot_command" ]; then
  collector_args+=(--screenshot-command "$screenshot_command")
fi

if [ -n "$desktop_port" ]; then
  collector_args+=(--desktop-port "$desktop_port")
fi

if [ -n "$published_release_dir" ]; then
  collector_args+=(--published-release-dir "$published_release_dir")
fi

if [ -n "$published_release_repo" ]; then
  collector_args+=(--published-release-repo "$published_release_repo" --published-release-tag "$published_release_tag")
fi

if [ -n "$release_public_key" ]; then
  collector_args+=(--release-public-key "$release_public_key")
fi

if [ "$require_published_release" = "true" ]; then
  collector_args+=(--require-published-release)
fi

if [ -n "$operator_note" ]; then
  collector_args+=(--note "$operator_note")
fi

remote_command="cd $(quote_cmd "$remote_repo") && bash scripts/collect-vm-evidence.sh"
for arg in "${collector_args[@]}"; do
  remote_command+=" $(quote_cmd "$arg")"
done

scp_source="$(ssh_target):$(remote_evidence_path)/."
verify_command=(bash scripts/verify-vm-evidence.sh --target "$target" --evidence-dir "$local_output_dir")
if [ "$require_published_release" = "true" ]; then
  verify_command+=(--require-published-release)
fi

echo "Target: $target"
echo "Guest: $(ssh_target)"
echo "Remote evidence: $(remote_evidence_path)"
echo "Local evidence: $local_output_dir"
echo
echo "SSH collector command:"
print_command ssh "${ssh_args[@]}" "$(ssh_target)" "$remote_command"
echo "SCP evidence command:"
print_command scp "${scp_args[@]}" -r "$scp_source" "$local_output_dir/"
echo "Local verifier command:"
print_command "${verify_command[@]}"

if [ "$execute" != "true" ]; then
  echo
  echo "Dry run complete. Add --execute to run against the guest."
  exit 0
fi

command -v ssh >/dev/null 2>&1 || fail "ssh is required"
command -v scp >/dev/null 2>&1 || fail "scp is required"

mkdir -p "$local_output_dir"
ssh "${ssh_args[@]}" "$(ssh_target)" "$remote_command"
scp "${scp_args[@]}" -r "$scp_source" "$local_output_dir/"
"${verify_command[@]}"
echo "Verified VM evidence under $local_output_dir."
