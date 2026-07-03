#!/usr/bin/env bash
set -euo pipefail

command="${1:-}"
mode="desktop"
binary="${LOOPWIRE_BINARY:-$HOME/.local/bin/loopwire}"
dry_run="false"
background_args="${LOOPWIRE_BACKGROUND_ARGS:---background}"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
autostart_dir="${LOOPWIRE_XDG_AUTOSTART_DIR:-$config_home/autostart}"
systemd_dir="${LOOPWIRE_SYSTEMD_USER_DIR:-$config_home/systemd/user}"
source_dir="${LOOPWIRE_SOURCE_DIR:-}"
state_file="${LOOPWIRE_STATE_FILE:-$config_home/loopwire/state.json}"
restore_mode="${LOOPWIRE_RESTORE_MODE:-preview}"
retry_pending_ms="${LOOPWIRE_RESTORE_RETRY_PENDING_MS:-0}"
retry_interval_ms="${LOOPWIRE_RESTORE_RETRY_INTERVAL_MS:-1000}"

usage() {
  cat <<'USAGE'
Manage Loopwire user-scoped startup.

Usage:
  manage-autostart.sh render [--mode desktop|systemd] [--binary PATH] [--source-dir DIR]
  manage-autostart.sh install [--mode desktop|systemd] [--binary PATH] [--source-dir DIR] [--dry-run]
  manage-autostart.sh enable [--mode desktop|systemd] [--binary PATH] [--source-dir DIR] [--dry-run]
  manage-autostart.sh disable [--mode desktop|systemd] [--dry-run]
  manage-autostart.sh uninstall [--mode desktop|systemd] [--dry-run]
  manage-autostart.sh status [--mode desktop|systemd]

Modes:
  desktop   XDG autostart entry for graphical desktop sessions. This launches the GUI app.
  systemd   User systemd unit for background restore. Uses --source-dir when supplied,
            otherwise uses LOOPWIRE_BACKGROUND_ARGS with the installed binary.

Environment:
  LOOPWIRE_BINARY              Binary path, default ~/.local/bin/loopwire
  LOOPWIRE_BACKGROUND_ARGS     Args for systemd mode, default --background
  LOOPWIRE_SOURCE_DIR          Source checkout for pnpm restore:background systemd units
  LOOPWIRE_STATE_FILE          Persisted state path, default ~/.config/loopwire/state.json
  LOOPWIRE_RESTORE_MODE        Background restore mode, preview or live, default preview
  LOOPWIRE_RESTORE_RETRY_PENDING_MS
                               Live PulseAudio pending-stream refresh window, default 0
  LOOPWIRE_RESTORE_RETRY_INTERVAL_MS
                               Live PulseAudio pending-stream refresh interval, default 1000
  LOOPWIRE_XDG_AUTOSTART_DIR   Override XDG autostart directory
  LOOPWIRE_SYSTEMD_USER_DIR    Override systemd user unit directory

No system-wide files are modified. Use --dry-run to print write/service actions.
USAGE
}

fail() {
  echo "manage-autostart: $*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    render | install | enable | disable | uninstall | status)
      command="$1"
      shift
      ;;
    --mode)
      mode="${2:?missing value for --mode}"
      shift 2
      ;;
    --binary)
      binary="${2:?missing value for --binary}"
      shift 2
      ;;
    --source-dir)
      source_dir="${2:?missing value for --source-dir}"
      shift 2
      ;;
    --state-file)
      state_file="${2:?missing value for --state-file}"
      shift 2
      ;;
    --restore-mode)
      restore_mode="${2:?missing value for --restore-mode}"
      shift 2
      ;;
    --retry-pending-ms)
      retry_pending_ms="${2:?missing value for --retry-pending-ms}"
      shift 2
      ;;
    --retry-interval-ms)
      retry_interval_ms="${2:?missing value for --retry-interval-ms}"
      shift 2
      ;;
    --dry-run)
      dry_run="true"
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

[ -n "$command" ] || {
  usage >&2
  exit 2
}

case "$mode" in
  desktop | systemd)
    ;;
  *)
    fail "unsupported mode: $mode"
    ;;
esac

case "$restore_mode" in
  preview | live)
    ;;
  *)
    fail "unsupported restore mode: $restore_mode"
    ;;
esac

[[ "$retry_pending_ms" =~ ^[0-9]+$ ]] || fail "--retry-pending-ms must be a non-negative integer"
[[ "$retry_interval_ms" =~ ^[1-9][0-9]*$ ]] || fail "--retry-interval-ms must be greater than zero"
if [ "$retry_pending_ms" != "0" ] && [ "$restore_mode" != "live" ]; then
  fail "--retry-pending-ms requires --restore-mode live"
fi

desktop_entry_path="${autostart_dir}/loopwire.desktop"
systemd_unit_path="${systemd_dir}/loopwire.service"

reject_unsafe_path() {
  value="$1"

  case "$value" in
    *$'\n'* | *$'\r'*)
      fail "path must not contain newlines"
      ;;
  esac
}

desktop_exec() {
  reject_unsafe_path "$binary"
  printf '"%s"' "$binary"
}

systemd_exec() {
  if [ -n "$source_dir" ]; then
    reject_unsafe_path "$source_dir"
    reject_unsafe_path "$state_file"
    printf 'pnpm --dir "%s" restore:background -- --state-file "%s" --mode %s' \
      "$source_dir" \
      "$state_file" \
      "$restore_mode"
    if [ "$retry_pending_ms" != "0" ]; then
      printf ' --retry-pending-ms %s --retry-interval-ms %s' "$retry_pending_ms" "$retry_interval_ms"
    fi
    return
  fi

  reject_unsafe_path "$binary"
  printf '"%s"' "$binary"

  if [ -n "$background_args" ]; then
    printf ' %s' "$background_args"
  fi
}

render_desktop() {
  cat <<EOF
[Desktop Entry]
Type=Application
Name=Loopwire
Comment=Start Loopwire when your desktop session starts
Exec=$(desktop_exec)
Terminal=false
Categories=Audio;Utility;
X-GNOME-Autostart-enabled=true
EOF
}

render_systemd() {
  cat <<EOF
[Unit]
Description=Loopwire audio routing restore
After=graphical-session.target pipewire.service pipewire-pulse.service wireplumber.service
Wants=pipewire.service wireplumber.service

[Service]
Type=simple
ExecStart=$(systemd_exec)
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
EOF
}

render_unit() {
  case "$mode" in
    desktop)
      render_desktop
      ;;
    systemd)
      render_systemd
      ;;
  esac
}

target_path() {
  case "$mode" in
    desktop)
      printf '%s\n' "$desktop_entry_path"
      ;;
    systemd)
      printf '%s\n' "$systemd_unit_path"
      ;;
  esac
}

write_unit() {
  target="$(target_path)"

  if [ "$dry_run" = "true" ]; then
    echo "Would write $target:"
    render_unit
    return
  fi

  mkdir -p "$(dirname "$target")"
  render_unit >"$target"
  chmod 0644 "$target"
  echo "Installed $target"
}

enable_unit() {
  if [ "$mode" = "desktop" ]; then
    write_unit
    echo "Desktop autostart is enabled when the session honors XDG autostart entries."
    return
  fi

  if [ "$dry_run" = "true" ]; then
    write_unit
    echo "Would run: systemctl --user daemon-reload"
    echo "Would run: systemctl --user enable --now loopwire.service"
    return
  fi

  command -v systemctl >/dev/null 2>&1 || fail "systemctl is required for systemd mode"
  write_unit
  systemctl --user daemon-reload
  systemctl --user enable --now loopwire.service
}

disable_unit() {
  if [ "$mode" = "desktop" ]; then
    uninstall_unit
    return
  fi

  if [ "$dry_run" = "true" ]; then
    echo "Would run: systemctl --user disable --now loopwire.service"
    echo "Would run: systemctl --user daemon-reload"
    return
  fi

  command -v systemctl >/dev/null 2>&1 || fail "systemctl is required for systemd mode"
  systemctl --user disable --now loopwire.service || true
  systemctl --user daemon-reload
}

uninstall_unit() {
  target="$(target_path)"

  if [ "$dry_run" = "true" ]; then
    echo "Would remove $target"
    return
  fi

  if [ "$mode" = "systemd" ] && command -v systemctl >/dev/null 2>&1; then
    systemctl --user disable --now loopwire.service || true
  fi

  rm -f "$target"

  if [ "$mode" = "systemd" ] && command -v systemctl >/dev/null 2>&1; then
    systemctl --user daemon-reload
  fi

  echo "Removed $target"
}

status_unit() {
  target="$(target_path)"

  if [ -f "$target" ]; then
    echo "${mode}=installed"
    echo "path=$target"
  else
    echo "${mode}=not-installed"
    echo "path=$target"
  fi

  if [ "$mode" = "systemd" ] && command -v systemctl >/dev/null 2>&1; then
    echo "systemd-enabled=$(systemctl --user is-enabled loopwire.service 2>/dev/null || true)"
    echo "systemd-active=$(systemctl --user is-active loopwire.service 2>/dev/null || true)"
  fi
}

case "$command" in
  render)
    render_unit
    ;;
  install)
    write_unit
    ;;
  enable)
    enable_unit
    ;;
  disable)
    disable_unit
    ;;
  uninstall)
    uninstall_unit
    ;;
  status)
    status_unit
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
