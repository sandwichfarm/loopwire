#!/usr/bin/env bash
set -euo pipefail

binary=""
duration="5s"

usage() {
  cat <<'USAGE'
Verify that the packaged Loopwire desktop binary starts and remains alive.

Usage:
  verify-desktop-binary-launch.sh --binary FILE [--duration DURATION]

The smoke unsets WEBKIT_DISABLE_DMABUF_RENDERER before launch so the binary must apply its own Linux WebKitGTK
fallback. It passes only when the process remains alive until the timeout and no known Wayland/WebKitGTK protocol-crash
signature appears in output.
USAGE
}

fail() {
  echo "verify-desktop-binary-launch: $*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --binary)
      binary="${2:-}"
      shift 2
      ;;
    --duration)
      duration="${2:-}"
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

[ -n "$binary" ] || fail "missing --binary"
[ -f "$binary" ] || fail "missing binary: $binary"
[ -x "$binary" ] || fail "binary is not executable: $binary"

case "$duration" in
  "" | -* | *[!0-9smhd.]*)
    fail "--duration must be a positive timeout value accepted by timeout, for example 5s"
    ;;
esac

log_file="$(mktemp)"
trap 'rm -f "$log_file"' EXIT

set +e
env -u WEBKIT_DISABLE_DMABUF_RENDERER timeout "$duration" "$binary" >"$log_file" 2>&1
status="$?"
set -e

cat "$log_file"

if grep -E "Missing acquire timeline|Gdk-Message: .*Error 71|Protocol error.*Wayland display" "$log_file" \
  >/dev/null; then
  fail "desktop binary hit a known WebKitGTK/Wayland protocol crash"
fi

if [ "$status" -ne 124 ]; then
  fail "desktop binary exited before $duration with status $status"
fi

echo "Desktop binary launch smoke passed: $binary stayed alive for $duration without GDK Error 71."
