# Start on Boot

Loopwire should be available before users open recording, meeting, or broadcast tools.

The desktop app has user-scoped startup controls for opening the GUI and restoring audio in the background. It writes
only under `~/.config/autostart` and `~/.config/systemd/user`, and it can remove the same files again. It never writes
system files.

The installed tarball/package entrypoint and source checkout helpers both support user-scoped startup and background
restore. They are dry-run friendly and keep startup files user-scoped.

## Current Safe Path: Desktop App

For today's GUI app, use XDG desktop autostart. This starts Loopwire when the graphical session starts on desktops and
WMs that honor `~/.config/autostart/*.desktop`.

In the desktop shell, use the sidebar startup cards:

- **Open on boot** manages the XDG autostart entry that launches the GUI.
- **Restore on boot** manages a user systemd unit that runs the packaged `loopwire --background --mode live` launcher
  against the persisted state file.

Browser preview does not write startup files. It shows the paths and asks you to use the desktop shell.
Source-checkout Tauri runs do not install a background-capable GUI binary; use the source checkout CLI path below until
you test an installed package or set `LOOPWIRE_BACKGROUND_BINARY` to a compatible launcher.
The restore-on-boot status card stays readable when that launcher is missing: it reports the unit path, marks restore
as blocked, and disables only the unsafe enable action. If a unit already exists, the desktop can still remove it.

## CLI Fallback

Preview the entry:

```bash
bash scripts/manage-autostart.sh render --mode desktop --binary "$HOME/.local/bin/loopwire"
```

Install the entry:

```bash
bash scripts/manage-autostart.sh install --mode desktop --binary "$HOME/.local/bin/loopwire"
```

Check status:

```bash
bash scripts/manage-autostart.sh status --mode desktop
```

Remove it:

```bash
bash scripts/manage-autostart.sh uninstall --mode desktop
```

This path launches the app and the desktop shell restores the selected configuration through the same startup runtime
plan it uses after local state is loaded.

## Packaged Background Restore Path

Release tarballs install `loopwire` as a launcher. Normal invocations start the GUI. `loopwire --background` runs the
bundled restore engine from the installed support files:

```bash
loopwire --background \
  --state-file "${XDG_CONFIG_HOME:-$HOME/.config}/loopwire/state.json" \
  --mode preview \
  --pretty
```

Render a user-scoped systemd service for the installed launcher:

```bash
bash scripts/manage-autostart.sh render \
  --mode systemd \
  --binary "$HOME/.local/bin/loopwire" \
  --restore-mode preview
```

The generated packaged service shape is:

```ini
[Unit]
Description=Loopwire audio routing restore

[Service]
Type=simple
ExecStart="/home/me/.local/bin/loopwire" --background --state-file "%h/.config/loopwire/state.json" --mode preview
Restart=on-failure
RestartSec=2
```

Packaged background restore requires `node` on `PATH` because the release artifact bundles the same JavaScript
core/audio-host restore engine used by source checkouts.

The desktop shell resolves the packaged launcher from the installed GUI path before writing this service. It refuses to
install a background unit if it can only find the GUI binary, because `--background` belongs to the `loopwire` launcher.
The status check remains non-destructive when that launcher is missing, so users can see why enable is blocked instead
of getting a failed status check. The shell then writes the unit and a user-scoped
`default.target.wants/loopwire.service` link. It does not run `sudo` or modify `/etc/systemd`.

## Source Background Restore Path

The source checkout can also run a user-scoped systemd service that restores the persisted state file without opening the
UI. User-scoped startup avoids system daemons and keeps rollback simple.

The Tauri desktop shell writes the same serialized state to:

```bash
${XDG_CONFIG_HOME:-$HOME/.config}/loopwire/state.json
```

Preview the background restore transaction:

```bash
pnpm restore:background -- \
  --state-file "${XDG_CONFIG_HOME:-$HOME/.config}/loopwire/state.json" \
  --mode preview \
  --pretty
```

`--mode preview` validates the persisted state and runs dry-run backend adapters. `--mode live` is the explicit host
mutation path and should only be used after the selected backend and routes are correct.

For PulseAudio compatibility routes, background restore keeps normal switch verification strict but reports missing app
streams as pending until those apps launch. That lets Loopwire-owned sinks remain ready at login without claiming that an
app stream was already moved.

Live PulseAudio restore can also retry those pending routes for a bounded window without recreating the virtual sinks:

```bash
pnpm restore:background -- \
  --state-file "${XDG_CONFIG_HOME:-$HOME/.config}/loopwire/state.json" \
  --backend pulseaudio \
  --mode live \
  --retry-pending-ms 10000 \
  --retry-interval-ms 1000 \
  --pretty
```

Each retry refresh only moves and controls newly visible matching sink inputs, then verifies again. If apps are still
absent when the window closes, the JSON output keeps `pendingStreamRefresh.cleared` false instead of pretending the
streams were present.

For JACK restore, a persisted configuration can use deterministic Loopwire-owned ports only after a JACK provider
creates them. The background runner can call an explicit provider command before connecting those ports:

```bash
pnpm restore:background -- \
  --state-file "${XDG_CONFIG_HOME:-$HOME/.config}/loopwire/state.json" \
  --backend jack \
  --mode live \
  --jack-provider-command loopwire-jack-ports \
  --pretty
```

The provider command receives stable `ensure --configuration-id ... --requirement ... --port ...` arguments from the
runtime. Loopwire re-runs `jack_lsp` after the provider exits and still fails closed if the expected ports are missing.
Release artifacts install `loopwire-jack-ports`, a bundled provider wrapper that records those arguments in a
`loopwire.jack-ports.provision-plan` manifest and returns nonzero unless `LOOPWIRE_JACK_PORTS_DELEGATE` or
`--delegate-command` points at a live JACK client provider.

For graph-edge DSP restore, a provider command can own source capture and output injection while Loopwire owns the
configuration transaction, per-edge gain/mute math, and verification sequence:

```bash
pnpm restore:background -- \
  --state-file "${XDG_CONFIG_HOME:-$HOME/.config}/loopwire/state.json" \
  --backend dsp \
  --mode live \
  --dsp-provider-command loopwire-dsp-provider \
  --dsp-frame-count 480 \
  --pretty
```

The provider command receives `read-source` as stable arguments and returns JSON channel buffers on stdout. Loopwire
sends rendered output buffers to `write-output` and `verify-output` as JSON stdin. The source checkout and packaged
systemd helpers can pass the same `--backend dsp`, `--dsp-provider-command`, `--dsp-provider-timeout-ms`, and
`--dsp-frame-count` flags. Run `pnpm dsp:plan` first to inspect the bounded provider operations, then run
`pnpm dsp:verify` with the provider command before enabling boot restore. Release artifacts install
`loopwire-dsp-provider`, a bundled file-backed provider for contract smoke and local restore preflight. It stores
seeded source buffers and rendered output buffers under `LOOPWIRE_DSP_PROVIDER_DIR` or
`${XDG_STATE_HOME:-$HOME/.local/state}/loopwire/dsp-provider`; it is not a live PipeWire/JACK capture or playback
provider.

Seed every source your configuration routes before running execute-mode preflight:

```bash
loopwire-dsp-provider seed-source --source-id mic --channels 2 --frames 480 --value 1
loopwire-dsp-provider seed-source --source-id browser --channels 2 --frames 480 --value 0.25
```

Preview the service:

```bash
bash scripts/manage-autostart.sh render \
  --mode systemd \
  --source-dir "$PWD" \
  --state-file "${XDG_CONFIG_HOME:-$HOME/.config}/loopwire/state.json" \
  --restore-mode live \
  --dsp-provider-command loopwire-dsp-provider \
  --dsp-provider-timeout-ms 5000 \
  --dsp-frame-count 480
```

Dry-run enabling it:

```bash
bash scripts/manage-autostart.sh enable \
  --mode systemd \
  --source-dir "$PWD" \
  --state-file "${XDG_CONFIG_HOME:-$HOME/.config}/loopwire/state.json" \
  --restore-mode preview \
  --dry-run
```

The generated service shape is:

```ini
[Unit]
Description=Loopwire audio routing restore
After=graphical-session.target pipewire.service pipewire-pulse.service wireplumber.service
Wants=pipewire.service wireplumber.service

[Service]
Type=simple
ExecStart=pnpm --dir /path/to/loopwire restore:background -- --state-file %h/.config/loopwire/state.json --mode preview
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
```

For JACK boot restore, the helper appends the same `--jack-provider-command` and `--jack-provider-timeout-ms` flags to
the generated `ExecStart` line. For DSP provider restore, the helper appends `--backend dsp` plus the DSP provider
flags. Packaged services pass those flags after `loopwire --background`; source-checkout services pass them after
`pnpm restore:background --`, so both boot paths keep the same runtime contract. The packaged JACK wrapper is a
preflight/delegation surface, not a native JACK client creator.

The helper supports both the packaged launcher path through `--binary "$HOME/.local/bin/loopwire"` and the source
checkout path through `--source-dir "$PWD"`.

## Manual Systemd Commands

```bash
systemctl --user daemon-reload
systemctl --user enable --now loopwire.service
systemctl --user status loopwire.service
```

Startup work must always include a disable path:

```bash
systemctl --user disable --now loopwire.service
```

Prefer the helper over hand-written unit files so docs, tests, and packaging stay aligned.
