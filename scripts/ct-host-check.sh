#!/usr/bin/env bash
set -euo pipefail

echo "Loopwire host audio diagnostics"
echo "date=$(date -Is)"
echo "kernel=$(uname -srmo)"
echo "desktop=${XDG_CURRENT_DESKTOP:-unknown}"
echo "session=${XDG_SESSION_TYPE:-unknown}"
echo "wayland=${WAYLAND_DISPLAY:-none}"
echo

check_command() {
  name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    echo "${name}=present"
  else
    echo "${name}=missing"
  fi
}

redact_diagnostics() {
  sed -E \
    -e 's/[[:alnum:]_.%+-]+@[[:alnum:]_.-]+/<user@host>/g' \
    -e 's#/run/user/[0-9]+#/run/user/<uid>#g' \
    -e 's/pid:[0-9]+/pid:<redacted>/g' \
    -e 's/cookie:[0-9]+/cookie:<redacted>/g' \
    -e 's/^Cookie: .*/Cookie: <redacted>/' \
    -e 's/^User Name: .*/User Name: <user>/' \
    -e 's/^Host Name: .*/Host Name: <host>/'
}

check_command pw-cli
check_command wpctl
check_command pactl
check_command jack_lsp
check_command aplay
check_command systemctl
echo

echo "Loopwire backend detector:"
if command -v pnpm >/dev/null 2>&1 && command -v node >/dev/null 2>&1; then
  pnpm --filter @loopwire/audio-host build >/dev/null
  node scripts/detect-audio-backends.mjs --pretty
else
  echo "skipped=pnpm or node missing"
fi
echo

if command -v systemctl >/dev/null 2>&1; then
  echo "User service state:"
  systemctl --user --no-pager --type=service --state=running 2>/dev/null | sed -n '1,40p' | redact_diagnostics || true
  echo
fi

if command -v wpctl >/dev/null 2>&1; then
  echo "WirePlumber status:"
  wpctl status 2>/dev/null | sed -n '1,80p' | redact_diagnostics || true
  echo
fi

if command -v pactl >/dev/null 2>&1; then
  echo "PulseAudio server:"
  pactl info 2>/dev/null | sed -n '1,40p' | redact_diagnostics || true
  echo
fi

if command -v jack_lsp >/dev/null 2>&1; then
  echo "JACK ports:"
  jack_lsp 2>/dev/null | sed -n '1,40p' | redact_diagnostics || true
  echo
fi

echo "Diagnostics complete."
