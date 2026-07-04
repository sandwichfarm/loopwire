#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_file="${LOOPWIRE_VM_TARGETS:-$root/vm/targets.tsv}"

plan_file=""
local_root=".vm/evidence"
remote_repo="loopwire"
remote_output_root=".vm/evidence"
published_release_dir=""
published_release_repo=""
published_release_tag=""
release_public_key=""
require_published_release="false"
require_all_targets="false"
operator_note=""
execute="false"

usage() {
  cat <<'USAGE'
Collect Loopwire VM evidence for multiple reachable guests from a TSV plan.

Usage:
  collect-vm-matrix-evidence.sh --plan FILE [options]

Plan schema, tab-separated. Use "-" or an empty cell for defaults:
  target  host  port  user  identity  desktop_port  screenshot_command  local_output_dir

Options:
  --plan FILE                      TSV plan with one guest per row.
  --local-root DIR                 Default local evidence root. Defaults to .vm/evidence.
  --remote-repo DIR                Remote Loopwire checkout. Defaults to loopwire.
  --remote-output-root DIR         Remote evidence root. Defaults to .vm/evidence.
  --published-release-dir DIR      Guest-visible signed release directory for installed-release smoke.
  --published-release-repo REPO    GitHub repository for installed-release smoke.
  --published-release-tag TAG      Release tag for installed-release smoke.
  --release-public-key FILE        Guest-visible release public key for signature verification.
  --require-published-release      Require installed-release smoke in every guest evidence bundle.
  --require-all-targets            Require the plan to cover every target from vm/targets.tsv.
  --note TEXT                      Append operator context to each guest notes.md.
  --execute                        Run each SSH collector. Default is dry-run.

Local output directories may be absolute or relative, but must contain the target id as a path segment and must not
contain parent traversal. Dry-run prints the exact collect-vm-evidence-ssh.sh command for every row without touching
guests or writing evidence.
USAGE
}

fail() {
  echo "collect-vm-matrix-evidence: $*" >&2
  exit 1
}

known_target() {
  local id="$1"
  [ -f "$target_file" ] || fail "missing target file: $target_file"
  awk -F '\t' -v id="$id" '$1 == id { found = 1 } END { exit found ? 0 : 1 }' "$target_file"
}

validate_tcp_port() {
  local port="$1"
  local label="$2"

  case "$port" in
    "" | *[!0-9]*)
      fail "$label must be a number from 1 to 65535"
      ;;
  esac

  if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    fail "$label must be a number from 1 to 65535"
  fi
}

validate_local_output_dir() {
  local path="$1"
  local target="$2"

  [ -n "$path" ] || fail "local_output_dir for $target must not be empty"

  case "$path" in
    *$'\n'* | *$'\r'*)
      fail "local_output_dir for $target must be a single path"
      ;;
    .. | ../* | */.. | */../*)
      fail "local_output_dir for $target must not contain parent traversal"
      ;;
  esac

  if ! path_contains_segment "$path" "$target"; then
    fail "local_output_dir for $target must include the target id as a path segment"
  fi
}

path_contains_segment() {
  local path="$1"
  local expected="$2"
  local segment
  local IFS='/'
  local -a segments

  read -r -a segments <<<"$path"
  for segment in "${segments[@]}"; do
    if [ "$segment" = "$expected" ]; then
      return 0
    fi
  done

  return 1
}

cell_or_empty() {
  case "${1:-}" in
    "" | "-")
      printf ''
      ;;
    *)
      printf '%s' "$1"
      ;;
  esac
}

default_cell() {
  local value
  value="$(cell_or_empty "${1:-}")"
  if [ -n "$value" ]; then
    printf '%s' "$value"
  else
    printf '%s' "$2"
  fi
}

print_command() {
  printf '  '
  printf '%q ' "$@"
  printf '\n'
}

build_collect_command() {
  local target="$1"
  local host="$2"
  local port="$3"
  local user="$4"
  local identity="$5"
  local desktop_port="$6"
  local screenshot_command="$7"
  local local_output_dir="$8"
  local remote_output_dir="$9"

  collect_cmd=(
    bash scripts/collect-vm-evidence-ssh.sh
    --target "$target"
    --host "$host"
    --port "$port"
    --user "$user"
    --remote-repo "$remote_repo"
    --remote-output-dir "$remote_output_dir"
    --local-output-dir "$local_output_dir"
  )

  if [ -n "$identity" ]; then
    collect_cmd+=(--identity "$identity")
  fi

  if [ -n "$desktop_port" ]; then
    collect_cmd+=(--desktop-port "$desktop_port")
  fi

  if [ -n "$screenshot_command" ]; then
    collect_cmd+=(--screenshot-command "$screenshot_command")
  fi

  if [ -n "$published_release_dir" ]; then
    collect_cmd+=(--published-release-dir "$published_release_dir" --published-release-tag "$published_release_tag")
  fi

  if [ -n "$published_release_repo" ]; then
    collect_cmd+=(--published-release-repo "$published_release_repo" --published-release-tag "$published_release_tag")
  fi

  if [ -n "$release_public_key" ]; then
    collect_cmd+=(--release-public-key "$release_public_key")
  fi

  if [ "$require_published_release" = "true" ]; then
    collect_cmd+=(--require-published-release)
  fi

  if [ -n "$operator_note" ]; then
    collect_cmd+=(--note "$operator_note")
  fi

  if [ "$execute" = "true" ]; then
    collect_cmd+=(--execute)
  fi
}

validate_plan_file() {
  local row_count=0
  local seen_targets=""
  local target
  local host
  local port
  local user
  local identity
  local desktop_port
  local screenshot_command
  local local_output_dir
  local extra
  local missing_targets
  local expected_target

  while IFS=$'\t' read -r target host port user identity desktop_port screenshot_command local_output_dir extra \
    || [ -n "${target:-}${host:-}${port:-}${user:-}${identity:-}${desktop_port:-}${screenshot_command:-}${local_output_dir:-}${extra:-}" ]; do
    target="${target%$'\r'}"

    case "$target" in
      "" | \#*)
        continue
        ;;
    esac

    [ -z "${extra:-}" ] || fail "too many columns for target $target"

    known_target "$target" || fail "unknown VM target: $target"
    if printf '%s' "$seen_targets" | grep -Fx -- "$target" >/dev/null; then
      fail "duplicate target in plan: $target"
    fi
    seen_targets+="$target"$'\n'

    host="$(cell_or_empty "${host:-}")"
    [ -n "$host" ] || fail "missing host for target $target"

    port="$(default_cell "${port:-}" "2222")"
    desktop_port="$(cell_or_empty "${desktop_port:-}")"
    local_output_dir="$(default_cell "${local_output_dir:-}" "$local_root/$target")"

    validate_tcp_port "$port" "port for $target"
    if [ -n "$desktop_port" ]; then
      validate_tcp_port "$desktop_port" "desktop_port for $target"
    fi
    validate_local_output_dir "$local_output_dir" "$target"
    row_count=$((row_count + 1))
  done <"$plan_file"

  [ "$row_count" -gt 0 ] || fail "plan has no target rows"

  if [ "$require_all_targets" = "true" ]; then
    missing_targets=""
    while IFS= read -r expected_target; do
      [ -n "$expected_target" ] || continue
      if ! printf '%s' "$seen_targets" | grep -Fx -- "$expected_target" >/dev/null; then
        missing_targets+="$expected_target "
      fi
    done < <(awk -F '\t' 'NF && $1 !~ /^#/ { print $1 }' "$target_file")

    [ -z "$missing_targets" ] || fail "plan is missing VM target(s): ${missing_targets% }"
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --)
      shift
      ;;
    --plan)
      plan_file="${2:-}"
      shift 2
      ;;
    --local-root)
      local_root="${2:-}"
      shift 2
      ;;
    --remote-repo)
      remote_repo="${2:-}"
      shift 2
      ;;
    --remote-output-root)
      remote_output_root="${2:-}"
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
    --require-all-targets)
      require_all_targets="true"
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

[ -n "$plan_file" ] || fail "missing --plan"
[ -f "$plan_file" ] || fail "missing plan file: $plan_file"

if [ -n "$published_release_dir" ] && [ -n "$published_release_repo" ]; then
  fail "use either --published-release-dir or --published-release-repo, not both"
fi

if [ -n "$published_release_tag" ] && [ -z "$published_release_dir" ] && [ -z "$published_release_repo" ]; then
  fail "--published-release-tag requires --published-release-dir or --published-release-repo"
fi

if [ "$require_published_release" = "true" ] && [ -z "$published_release_dir" ] && [ -z "$published_release_repo" ]; then
  fail "--require-published-release requires --published-release-dir or --published-release-repo"
fi

if [ -n "$published_release_dir" ] || [ -n "$published_release_repo" ]; then
  [ -n "$release_public_key" ] || fail "published release smoke requires --release-public-key"
  if [ -z "$published_release_tag" ]; then
    fail "published release smoke requires --published-release-tag"
  fi
fi

validate_plan_file

echo "VM matrix evidence plan: $plan_file"
echo "Mode: $([ "$execute" = "true" ] && echo execute || echo dry-run)"
echo "Require all targets: $require_all_targets"
echo

row_count=0
seen_targets=""

while IFS=$'\t' read -r target host port user identity desktop_port screenshot_command local_output_dir extra \
  || [ -n "${target:-}${host:-}${port:-}${user:-}${identity:-}${desktop_port:-}${screenshot_command:-}${local_output_dir:-}${extra:-}" ]; do
  target="${target%$'\r'}"

  case "$target" in
    "" | \#*)
      continue
      ;;
  esac

  [ -z "${extra:-}" ] || fail "too many columns for target $target"

  known_target "$target" || fail "unknown VM target: $target"
  if printf '%s' "$seen_targets" | grep -Fx -- "$target" >/dev/null; then
    fail "duplicate target in plan: $target"
  fi
  seen_targets+="$target"$'\n'

  host="$(cell_or_empty "${host:-}")"
  [ -n "$host" ] || fail "missing host for target $target"

  port="$(default_cell "${port:-}" "2222")"
  user="$(default_cell "${user:-}" "loopwire")"
  identity="$(cell_or_empty "${identity:-}")"
  desktop_port="$(cell_or_empty "${desktop_port:-}")"
  screenshot_command="$(cell_or_empty "${screenshot_command:-}")"
  local_output_dir="$(default_cell "${local_output_dir:-}" "$local_root/$target")"
  remote_output_dir="$remote_output_root/$target"

  validate_tcp_port "$port" "port for $target"
  if [ -n "$desktop_port" ]; then
    validate_tcp_port "$desktop_port" "desktop_port for $target"
  fi
  validate_local_output_dir "$local_output_dir" "$target"

  row_count=$((row_count + 1))
  build_collect_command \
    "$target" \
    "$host" \
    "$port" \
    "$user" \
    "$identity" \
    "$desktop_port" \
    "$screenshot_command" \
    "$local_output_dir" \
    "$remote_output_dir"

  echo "Target: $target"
  echo "Guest: $user@$host:$port"
  echo "Local evidence: $local_output_dir"
  echo "Remote evidence: $remote_repo/$remote_output_dir"
  echo "Collector command:"
  print_command "${collect_cmd[@]}"
  echo

  if [ "$execute" = "true" ]; then
    "${collect_cmd[@]}"
    echo
  fi
done <"$plan_file"

[ "$row_count" -gt 0 ] || fail "plan has no target rows"

if [ "$execute" = "true" ]; then
  echo "Verified VM evidence for $row_count target(s)."
else
  echo "Dry run complete for $row_count target(s). Add --execute to run against guests."
fi
