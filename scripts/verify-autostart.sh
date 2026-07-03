#!/usr/bin/env bash
set -euo pipefail

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

assert_contains() {
  file="$1"
  expected="$2"

  if ! grep -Fq -- "$expected" "$file"; then
    echo "Expected $file to contain: $expected" >&2
    exit 1
  fi
}

desktop_render="$tmp_dir/desktop.render"
systemd_render="$tmp_dir/systemd.render"
source_systemd_render="$tmp_dir/source-systemd.render"
state_file="$tmp_dir/state.json"
restore_output="$tmp_dir/restore-output.json"

bash scripts/manage-autostart.sh render --mode desktop --binary /tmp/loopwire >"$desktop_render"
bash scripts/manage-autostart.sh render --mode systemd --binary /tmp/loopwire >"$systemd_render"
bash scripts/manage-autostart.sh render \
  --mode systemd \
  --source-dir /tmp/loopwire-source \
  --state-file "$state_file" \
  --restore-mode live \
  --retry-pending-ms 5000 \
  --retry-interval-ms 500 >"$source_systemd_render"

assert_contains "$desktop_render" "Exec=\"/tmp/loopwire\""
assert_contains "$systemd_render" "ExecStart=\"/tmp/loopwire\" --background"
assert_contains "$source_systemd_render" "ExecStart=pnpm --dir \"/tmp/loopwire-source\" restore:background"
assert_contains "$source_systemd_render" "--state-file \"$state_file\" --mode live"
assert_contains "$source_systemd_render" "--retry-pending-ms 5000 --retry-interval-ms 500"
if bash scripts/manage-autostart.sh render \
  --mode systemd \
  --source-dir /tmp/loopwire-source \
  --restore-mode preview \
  --retry-pending-ms 5000 >/dev/null 2>&1; then
  echo "manage-autostart accepted pending retry without live restore mode." >&2
  exit 1
fi

cat >"$state_file" <<'JSON'
{
  "version": 1,
  "selectedBackend": "pipewire",
  "activeConfigurationId": "studio",
  "hiddenMonitorIds": [],
  "configurations": [
    {
      "id": "studio",
      "name": "Studio",
      "description": "Restore smoke",
      "inputs": [
        { "id": "mic", "label": "Mic", "role": "input", "channels": 2 }
      ],
      "outputs": [
        { "id": "program", "label": "Program", "role": "output", "channels": 2 }
      ],
      "monitors": [],
      "routes": [
        { "id": "mic-program", "from": "mic", "to": "program", "gain": 1, "muted": false }
      ],
      "updatedAt": "2026-07-03T00:00:00.000Z"
    }
  ],
  "appliedAt": "2026-07-03T00:00:00.000Z"
}
JSON

pnpm restore:background -- --state-file "$state_file" --mode preview --pretty >"$restore_output"
assert_contains "$restore_output" '"status": "verified"'
assert_contains "$restore_output" '"backend": "pipewire"'
assert_contains "$restore_output" '"operations": ['
assert_contains "$restore_output" '"apply"'
assert_contains "$restore_output" '"verify"'

XDG_CONFIG_HOME="$tmp_dir/config" bash scripts/manage-autostart.sh install --mode desktop --binary /tmp/loopwire
desktop_file="$tmp_dir/config/autostart/loopwire.desktop"
[ -f "$desktop_file" ] || {
  echo "Desktop autostart file was not written." >&2
  exit 1
}
assert_contains "$desktop_file" "Name=Loopwire"
assert_contains "$desktop_file" "Exec=\"/tmp/loopwire\""

LOOPWIRE_SYSTEMD_USER_DIR="$tmp_dir/systemd" bash scripts/manage-autostart.sh install --mode systemd --binary /tmp/loopwire
systemd_file="$tmp_dir/systemd/loopwire.service"
[ -f "$systemd_file" ] || {
  echo "Systemd user unit was not written." >&2
  exit 1
}
assert_contains "$systemd_file" "Description=Loopwire audio routing restore"
assert_contains "$systemd_file" "ExecStart=\"/tmp/loopwire\" --background"

bash scripts/manage-autostart.sh enable --mode systemd --binary /tmp/loopwire --dry-run >/dev/null
bash scripts/manage-autostart.sh uninstall --mode desktop --binary /tmp/loopwire --dry-run >/dev/null

echo "Autostart helper verification passed."
