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
ExecStart="/home/me/.local/bin/loopwire" --background
Restart=on-failure
RestartSec=2
```

Packaged background restore requires `node` on `PATH` because the release artifact bundles the same JavaScript
core/audio-host restore engine used by source checkouts.

The desktop shell resolves the packaged launcher from the installed GUI path before writing this service. It refuses to
install a background unit if it can only find the GUI binary, because `--background` belongs to the `loopwire` launcher.
The shell then writes the unit and a user-scoped `default.target.wants/loopwire.service` link. It does not run `sudo`
or modify `/etc/systemd`.

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

Preview the service:

```bash
bash scripts/manage-autostart.sh render \
  --mode systemd \
  --source-dir "$PWD" \
  --state-file "${XDG_CONFIG_HOME:-$HOME/.config}/loopwire/state.json" \
  --restore-mode preview
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
