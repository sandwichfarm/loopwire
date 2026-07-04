#!/usr/bin/env bash
set -euo pipefail

configuration=""
frame_count="16"

usage() {
  cat <<'USAGE'
Collect read-only command-backed DSP provider plan evidence.

Usage:
  collect-dsp-provider-plan.sh --configuration FILE [--frame-count N]

The script builds the core/audio-host packages quietly, then prints only the DSP provider plan TSV.
It never passes --execute to the provider planner.
USAGE
}

fail() {
  echo "collect-dsp-provider-plan: $*" >&2
  exit 1
}

reject_unsafe_path() {
  local value="$1"
  local label="$2"

  case "$value" in
    "" | /* | *$'\n'* | *$'\r'* | *".."*)
      fail "$label must be a relative path without parent traversal"
      ;;
  esac
}

validate_frame_count() {
  local value="$1"

  [[ "$value" =~ ^[1-9][0-9]*$ ]] || fail "frame count must be a positive integer"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --configuration)
      configuration="${2:?missing value for --configuration}"
      shift 2
      ;;
    --frame-count)
      frame_count="${2:?missing value for --frame-count}"
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

reject_unsafe_path "$configuration" "configuration"
validate_frame_count "$frame_count"

pnpm --filter @loopwire/core build >/dev/null 2>&1 || fail "failed to build @loopwire/core"
pnpm --filter @loopwire/audio-host build >/dev/null 2>&1 || fail "failed to build @loopwire/audio-host"
node scripts/describe-dsp-provider.mjs \
  --configuration "$configuration" \
  --frame-count "$frame_count" \
  --format tsv
