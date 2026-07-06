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
source_jack_systemd_render="$tmp_dir/source-jack-systemd.render"
packaged_jack_systemd_render="$tmp_dir/packaged-jack-systemd.render"
source_dsp_systemd_render="$tmp_dir/source-dsp-systemd.render"
packaged_dsp_systemd_render="$tmp_dir/packaged-dsp-systemd.render"
state_file="$tmp_dir/state.json"
restore_output="$tmp_dir/restore-output.json"
dsp_restore_output="$tmp_dir/dsp-restore-output.json"
dsp_reject_output="$tmp_dir/dsp-reject-output.txt"
dsp_provider="$tmp_dir/dsp-provider.sh"
dsp_provider_log="$tmp_dir/dsp-provider.log"

bash scripts/manage-autostart.sh --help | grep -F -- "LOOPWIRE_DSP_PROVIDER_MODE" >/dev/null || {
  echo "manage-autostart help is missing DSP provider mode." >&2
  exit 1
}

bash scripts/manage-autostart.sh render --mode desktop --binary /tmp/loopwire >"$desktop_render"
bash scripts/manage-autostart.sh render --mode systemd --binary /tmp/loopwire >"$systemd_render"
bash scripts/manage-autostart.sh render \
  --mode systemd \
  --source-dir /tmp/loopwire-source \
  --state-file "$state_file" \
  --restore-mode live \
  --retry-pending-ms 5000 \
  --retry-interval-ms 500 >"$source_systemd_render"
bash scripts/manage-autostart.sh render \
  --mode systemd \
  --source-dir /tmp/loopwire-source \
  --state-file "$state_file" \
  --restore-mode live \
  --jack-provider-command loopwire-jack-ports \
  --jack-provider-timeout-ms 7000 \
  --jack-provider-delegate-mode detached \
  --jack-provider-ready-delay-ms 750 >"$source_jack_systemd_render"
bash scripts/manage-autostart.sh render \
  --mode systemd \
  --binary /tmp/loopwire \
  --state-file "$state_file" \
  --restore-mode live \
  --jack-provider-command loopwire-jack-ports \
  --jack-provider-timeout-ms 7000 \
  --jack-provider-delegate-mode detached \
  --jack-provider-ready-delay-ms 750 >"$packaged_jack_systemd_render"
bash scripts/manage-autostart.sh render \
  --mode systemd \
  --source-dir /tmp/loopwire-source \
  --state-file "$state_file" \
  --restore-mode live \
  --dsp-provider-command loopwire-dsp-provider \
  --dsp-provider-timeout-ms 7000 \
  --dsp-provider-mode live \
  --dsp-frame-count 2 >"$source_dsp_systemd_render"
bash scripts/manage-autostart.sh render \
  --mode systemd \
  --binary /tmp/loopwire \
  --state-file "$state_file" \
  --restore-mode live \
  --dsp-provider-command loopwire-dsp-provider \
  --dsp-provider-timeout-ms 7000 \
  --dsp-provider-mode live \
  --dsp-frame-count 2 >"$packaged_dsp_systemd_render"

assert_contains "$desktop_render" "Exec=\"/tmp/loopwire\""
assert_contains "$systemd_render" "ExecStart=\"/tmp/loopwire\" --background --state-file"
assert_contains "$source_systemd_render" "ExecStart=pnpm --dir \"/tmp/loopwire-source\" restore:background"
assert_contains "$source_systemd_render" "--state-file \"$state_file\" --mode live"
assert_contains "$source_systemd_render" "--retry-pending-ms 5000 --retry-interval-ms 500"
assert_contains "$source_jack_systemd_render" "--jack-provider-command \"loopwire-jack-ports\" --jack-provider-timeout-ms 7000"
assert_contains "$source_jack_systemd_render" "--jack-provider-delegate-mode detached --jack-provider-ready-delay-ms 750"
assert_contains "$packaged_jack_systemd_render" "ExecStart=\"/tmp/loopwire\" --background --state-file \"$state_file\" --mode live"
assert_contains "$packaged_jack_systemd_render" "--jack-provider-command \"loopwire-jack-ports\" --jack-provider-timeout-ms 7000"
assert_contains "$packaged_jack_systemd_render" "--jack-provider-delegate-mode detached --jack-provider-ready-delay-ms 750"
assert_contains "$source_dsp_systemd_render" "ExecStart=pnpm --dir \"/tmp/loopwire-source\" restore:background"
assert_contains "$source_dsp_systemd_render" "--backend dsp --dsp-provider-command \"loopwire-dsp-provider\""
assert_contains "$source_dsp_systemd_render" "--dsp-provider-timeout-ms 7000 --dsp-provider-mode live --dsp-frame-count 2"
assert_contains "$packaged_dsp_systemd_render" "ExecStart=\"/tmp/loopwire\" --background --state-file \"$state_file\" --mode live"
assert_contains "$packaged_dsp_systemd_render" "--backend dsp --dsp-provider-command \"loopwire-dsp-provider\""
assert_contains "$packaged_dsp_systemd_render" "--dsp-provider-timeout-ms 7000 --dsp-provider-mode live --dsp-frame-count 2"
if bash scripts/manage-autostart.sh render \
  --mode systemd \
  --source-dir /tmp/loopwire-source \
  --restore-mode preview \
  --retry-pending-ms 5000 >/dev/null 2>&1; then
  echo "manage-autostart accepted pending retry without live restore mode." >&2
  exit 1
fi
if bash scripts/manage-autostart.sh render \
  --mode systemd \
  --source-dir /tmp/loopwire-source \
  --jack-provider-timeout-ms 0 >/dev/null 2>&1; then
  echo "manage-autostart accepted invalid JACK provider timeout." >&2
  exit 1
fi
if bash scripts/manage-autostart.sh render \
  --mode systemd \
  --source-dir /tmp/loopwire-source \
  --jack-provider-delegate-mode detached >/dev/null 2>&1; then
  echo "manage-autostart accepted detached JACK provider mode without a provider command." >&2
  exit 1
fi
if bash scripts/manage-autostart.sh render \
  --mode systemd \
  --source-dir /tmp/loopwire-source \
  --jack-provider-command loopwire-jack-ports \
  --jack-provider-delegate-mode foreground \
  --jack-provider-ready-delay-ms 750 >/dev/null 2>&1; then
  echo "manage-autostart accepted JACK provider readiness delay without detached mode." >&2
  exit 1
fi
if bash scripts/manage-autostart.sh render \
  --mode systemd \
  --source-dir /tmp/loopwire-source \
  --dsp-provider-timeout-ms 0 >/dev/null 2>&1; then
  echo "manage-autostart accepted invalid DSP provider timeout." >&2
  exit 1
fi
if bash scripts/manage-autostart.sh render \
  --mode systemd \
  --source-dir /tmp/loopwire-source \
  --dsp-frame-count 2 >/dev/null 2>&1; then
  echo "manage-autostart accepted DSP frame count without DSP provider command." >&2
  exit 1
fi
if bash scripts/manage-autostart.sh render \
  --mode systemd \
  --source-dir /tmp/loopwire-source \
  --restore-mode live \
  --dsp-provider-command loopwire-dsp-provider >/dev/null 2>&1; then
  echo "manage-autostart accepted live DSP provider without explicit live provider mode." >&2
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

node - "$state_file" <<'NODE'
const fs = require("node:fs");
const path = process.argv[2];
const state = JSON.parse(fs.readFileSync(path, "utf8"));
state.selectedBackend = "dsp";
fs.writeFileSync(path, `${JSON.stringify(state, null, 2)}\n`);
NODE
if pnpm restore:background -- \
  --state-file "$state_file" \
  --mode live \
  --pretty >"$dsp_reject_output" 2>&1; then
  echo "restore background accepted persisted DSP live restore without provider command." >&2
  exit 1
fi
assert_contains "$dsp_reject_output" "DSP background restore requires --dsp-provider-command"

cat >"$dsp_provider" <<SH
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >>"$dsp_provider_log"
case "\$1" in
  capabilities)
    capabilities='{"ok":true,"providerKind":"verify-live","supportsLiveGraph":true'
    capabilities+=',"operations":["read-source","write-output","verify-output","clear-output"]}'
    printf '%s\n' "\$capabilities"
    ;;
  read-source)
    printf '{"channels":[[1,1],[1,1]]}\n'
    ;;
  write-output | verify-output)
    cat >/dev/null
    printf '{"ok":true}\n'
    ;;
  clear-output)
    printf 'cleared\n'
    ;;
  *)
    echo "unexpected operation: \$1" >&2
    exit 2
    ;;
esac
SH
chmod +x "$dsp_provider"
pnpm restore:background -- \
  --state-file "$state_file" \
  --backend dsp \
  --mode live \
  --dsp-provider-command "$dsp_provider" \
  --dsp-provider-mode live \
  --dsp-frame-count 2 \
  --pretty >"$dsp_restore_output"
assert_contains "$dsp_restore_output" '"status": "verified"'
assert_contains "$dsp_restore_output" '"backend": "dsp"'
assert_contains "$dsp_restore_output" '"dspProviderCommand":'
assert_contains "$dsp_restore_output" '"supportsLiveGraph": true'
assert_contains "$dsp_provider_log" "capabilities"
assert_contains "$dsp_provider_log" "read-source --source-id mic --channels 2 --frames 2"
assert_contains "$dsp_provider_log" "write-output --output-id program --channels 2 --frames 2 --peak 1"
assert_contains "$dsp_provider_log" "verify-output --output-id program --channels 2 --frames 2 --peak 1"

cat >"$dsp_provider" <<SH
#!/usr/bin/env bash
set -euo pipefail
case "\$1" in
  capabilities)
    capabilities='{"ok":true,"providerKind":"incomplete-live","supportsLiveGraph":true'
    capabilities+=',"operations":["read-source","write-output","verify-output"]}'
    printf '%s\n' "\$capabilities"
    ;;
  *)
    echo "unexpected operation: \$1" >&2
    exit 2
    ;;
esac
SH
chmod +x "$dsp_provider"
if pnpm restore:background -- \
  --state-file "$state_file" \
  --backend dsp \
  --mode live \
  --dsp-provider-command "$dsp_provider" \
  --dsp-provider-mode live \
  --dsp-frame-count 2 \
  --pretty >"$dsp_reject_output" 2>&1; then
  echo "restore background accepted a live DSP provider without clear-output." >&2
  exit 1
fi
assert_contains "$dsp_reject_output" "missing required operation(s): clear-output"

cat >"$dsp_provider" <<SH
#!/usr/bin/env bash
set -euo pipefail
case "\$1" in
  capabilities)
    printf '{"ok":true,"providerKind":"file-backed","supportsLiveGraph":false}\n'
    ;;
  *)
    echo "unexpected operation: \$1" >&2
    exit 2
    ;;
esac
SH
chmod +x "$dsp_provider"
if pnpm restore:background -- \
  --state-file "$state_file" \
  --backend dsp \
  --mode live \
  --dsp-provider-command "$dsp_provider" \
  --dsp-provider-mode live \
  --dsp-frame-count 2 \
  --pretty >"$dsp_reject_output" 2>&1; then
  echo "restore background accepted a DSP provider that does not declare live graph support." >&2
  exit 1
fi
assert_contains "$dsp_reject_output" "supportsLiveGraph=true"

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
assert_contains "$systemd_file" "ExecStart=\"/tmp/loopwire\" --background --state-file"

bash scripts/manage-autostart.sh enable --mode systemd --binary /tmp/loopwire --dry-run >/dev/null
bash scripts/manage-autostart.sh uninstall --mode desktop --binary /tmp/loopwire --dry-run >/dev/null

echo "Autostart helper verification passed."
