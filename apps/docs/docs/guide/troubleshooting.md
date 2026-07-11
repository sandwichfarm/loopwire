# Troubleshooting

Start with commands that only read state. Do not mutate host audio until the app exposes an explicit apply path.

## Backend Does Not Appear

Run:

```bash
pnpm detect:audio
```

Check the unavailable backend's diagnostic message. Common causes:

- `wpctl` or `pw-cli` missing: PipeWire tools are not installed or not on `PATH`.
- `pactl info` fails: PulseAudio compatibility is not running.
- `jack_lsp` missing: JACK tooling is not installed, so JACK stays unavailable.
- `aplay -l` has no cards: ALSA playback devices are not visible to the session.
- `arecord -l` has no cards: ALSA capture devices are not visible to the session.

## PulseAudio Compatibility Is Available But Streams Do Not Move

The guarded adapter matches streams by endpoint id and label tokens against `pactl list sink-inputs` metadata. If a
stream label does not appear in `application.name`, `application.process.binary`, or nearby metadata, it will not match.

Useful read-only inspection:

```bash
pactl list sink-inputs
```

Current limitation: this is stream-level control. It is not true per-edge matrix mixing for one source routed to
multiple outputs.

## Native PipeWire Route Does Not Link

The native PipeWire adapter links existing source ports into host-backed outputs or Loopwire-owned virtual output
sinks. Each routed input endpoint must have a host `deviceName` that matches a visible `pw-link` output port prefix.
Outputs and monitors can use a host `deviceName`, or they can omit it so Loopwire creates a virtual PipeWire sink with
`pw-cli create-node adapter`.

In the desktop shell, choose a detected PipeWire target from the output picker for host-backed outputs. When adding that
output, Loopwire only creates default routes from existing sources that also have host device names.

Useful read-only inspection:

```bash
pw-link -o
pw-link -i
pw-link -l
```

If a route is muted, native PipeWire apply disconnects the configured link and verification fails if that link is still
connected. If a route has a non-unity gain value, native PipeWire apply fails before touching the host graph. Use the
PulseAudio compatibility adapter for stream-level gain until true per-edge PipeWire gain controls are implemented.

## Native JACK Route Does Not Connect

The native JACK adapter connects existing ports. Each routed input and output endpoint can use a host `deviceName` that
matches a visible `jack_lsp` port prefix. App-owned endpoints can omit `deviceName` only when another Loopwire-owned
JACK client has already created the deterministic ports:

- input source: `loopwire_<configuration>_input_<input>`
- output bus: `loopwire_<configuration>_<output>`
- monitor target: `loopwire_<configuration>_monitor_<monitor>`

The names are lowercased, sanitized, and truncated to 80 characters.

Useful read-only inspection:

```bash
jack_lsp
jack_lsp -c
```

In the desktop shell, choose a detected JACK target from the output picker for host-backed outputs. App-only endpoints
can pass the static preflight, but live apply still fails closed unless the matching JACK ports already exist.

If a route is muted, native JACK apply disconnects the configured connection and verification fails if that connection
is still present. Non-unity route gain fails before host commands. Missing route or monitor ports fail after read-only
`jack_lsp` inspection and before any `jack_connect` mutation.

## Live Host Apply Fails Closed

Live host apply only runs inside the Tauri desktop shell and only after `Host apply` is set to `Live armed`.

The command bridge allows:

```bash
pactl
pw-link
```

If the app is running as a browser dev preview, live apply fails without touching host audio. Use `Preview` mode for UI
validation.

For JACK, Host apply can use a saved JACK provider command to prepare Loopwire-owned deterministic ports before route
connections. If that provider exits successfully but the expected ports are still missing, live apply still fails closed
after the follow-up `jack_lsp` probe.

## Route Gain Or Mute Looks Wrong

For matching PulseAudio sink inputs, Loopwire's adapter applies route gain as `set-sink-input-volume` and route mute as
`set-sink-input-mute`. Verification fails if a present matching stream has unexpected volume or mute state.
Verification also fails when a configured route has no matching live stream, because an absent app stream cannot prove
that routing was applied.

During startup or source-checkout background restore, PulseAudio may instead report `Pending matching PulseAudio
stream(s)` for apps that are not running yet. Pending means the Loopwire sinks were prepared, not that those app streams
have already been moved.

If source-checkout background restore runs live with `--retry-pending-ms`, Loopwire refreshes matching PulseAudio
streams that appear during that window without unloading and recreating the virtual sinks. The JSON
`pendingStreamRefresh` field records each retry and whether the pending routes cleared.

For native PipeWire and JACK, route mute means disconnecting the configured graph edge. It is edge-specific, but it is
not a gain stage or mixer node.

If another mixer changes the same stream after Loopwire applies it, run verification again and inspect the conflicting
tool. Do not assume the persisted route changed until the configuration file or UI state confirms it changed.

## Monitor Audio Does Not Reach Headphones

If the monitor has a `Host sink` value, it must match a current PulseAudio/PipeWire compatibility sink name.

Read available sink names without changing the host graph:

```bash
pactl list short sinks
```

If the target sink is missing, verification fails with `Missing monitor target sink(s)`. Clear the field to route the
monitor into a Loopwire-owned monitor sink instead.

## Autostart Did Not Launch

Check the installed desktop autostart entry:

```bash
bash scripts/manage-autostart.sh status --mode desktop
```

For future systemd mode, read user service state:

```bash
systemctl --user status loopwire.service
journalctl --user -u loopwire.service --no-pager
```

If the desktop **Restore audio in background** action reports that it cannot locate the background restore launcher, the app is
running from a GUI binary that does not own `--background`. Install the packaged `loopwire` launcher, set
`LOOPWIRE_BACKGROUND_BINARY` to a compatible launcher, or use the source-checkout systemd path documented in
[Start on Boot](/guide/start-on-boot).

## Window Controls Look Wrong

Loopwire uses native chrome where the desktop environment provides it and custom chrome when the window manager needs a
fallback. In the desktop shell, the **Chrome** segmented control shows **Native** for the preferred system titlebar and
**Fallback** for Loopwire-owned controls. Switching to **Fallback** asks Tauri for an undecorated window, persists that
preference, and shows Loopwire-owned drag, minimize, maximize/restore, and close controls. Browser preview can show the
fallback controls, but cannot change platform window decorations.

If close, maximize/restore, or minimize controls are missing, capture the desktop environment, session type, compositor,
the selected chrome mode, and a screenshot, then compare against the VM matrix target that most closely matches the
machine.

## Installer Fails Signature Verification

Do not bypass signature checks for public artifacts. For local unsigned development artifacts, pass `--skip-signature`
only when the artifact source is a local temp directory you control.

Check:

```bash
sha256sum -c SHA256SUMS
openssl dgst -sha256 -verify packaging/release-signing-public.pem -signature SHA256SUMS.sig SHA256SUMS
```

## What To Attach To A Bug Report

Start with a redacted support bundle:

```bash
pnpm collect:support -- --output-dir .support/$(date +%Y%m%d-%H%M%S) --profile quick
```

For JACK reports tied to a saved configuration export, include read-only port readiness:

```bash
pnpm collect:support -- --output-dir .support/jack-case --configuration exported-loopwire-config.json
```

For DSP-provider restore or per-edge gain reports tied to a saved configuration export, include the read-only provider
operation plan:

```bash
pnpm collect:support -- \
  --output-dir .support/dsp-case \
  --configuration exported-loopwire-config.json \
  --include-dsp-provider-plan
```

For JACK-provider reports tied to missing deterministic Loopwire-owned ports, include the read-only provider plan. This
does not run `loopwire-jack-ports`, the configured provider command, or `jack_lsp`; it only records what Loopwire would
ask a provider to prepare.

```bash
pnpm collect:support -- \
  --output-dir .support/jack-provider-case \
  --configuration exported-loopwire-config.json \
  --include-jack-provider-plan
```

Review the generated directory before sharing it. The collector redacts local user, host, home directory, runtime uid
paths, process ids, cookies, and email-like values, but you should still remove anything private before attaching it.

Attach:

- `support-bundle.json`.
- `detect-audio.json`.
- `jack-provider-plan.json` when JACK provider plan collection was requested.
- `dsp-provider-plan.json` when DSP provider plan collection was requested.
- `ct-host-check.log`.
- `autostart-status.log`.
- Distro, desktop environment, session type, and audio stack.
- Install channel and artifact version.
- Screenshot for UI issues.
- Exact route/configuration steps that reproduce the issue.

`support-bundle.json` includes an `audio.backends` summary with backend availability, route-control scope, per-edge
gain/mute support, diagnostics, and known gaps. That summary is the fastest way to tell whether a report came from
PipeWire, PulseAudio compatibility, JACK, or ALSA diagnostics-only mode without reading every raw command log first.
When a configuration or state file is provided, the manifest also includes `jack.status` and
`jack-port-requirements.json` with read-only JACK readiness results.
When `--include-jack-provider-plan` is provided, it includes `jackProvider.status` and `jack-provider-plan.json` with
the deterministic Loopwire-owned JACK requirements Loopwire would ask a provider to prepare. The collector does not run
the provider command.
When `--include-dsp-provider-plan` is provided, it also includes `dspProvider.status` and `dsp-provider-plan.json`
with the read-only source/output operations Loopwire would ask a DSP provider to perform. The collector does not run
provider execute mode.
