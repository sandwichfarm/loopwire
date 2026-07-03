# Audio Backends

Loopwire is designed around a backend contract instead of a single hardcoded audio server.

## Priority

1. PipeWire: reference backend and first real host integration target.
2. PulseAudio: direct native PulseAudio and PulseAudio-on-PipeWire compatibility path.
3. JACK: professional-audio bridge and session workflow support.
4. ALSA: hardware substrate and fallback diagnostics, not the primary routing UX.

## Selection Rules

- If one viable backend is available, Loopwire can select it automatically.
- If more than one viable backend is available, Loopwire must ask the user.
- If a previously selected backend is still available, Loopwire should keep it.
- If no viable backend is available, Loopwire must show diagnostics instead of pretending routing works.

The pure core package implements the selection rules. The `@loopwire/audio-host` package implements Linux host
detection through injected command runners, guarded native PipeWire and JACK link adapters, and a guarded `pactl`
virtual-sink runtime adapter.

In the Tauri desktop shell, Loopwire runs the same detector during startup through an allowlisted command bridge and
hydrates the Backend picker plus Diagnostics panel from those read-only probe results. The browser preview cannot
inspect the host, so it keeps packaged fallback candidates and says so in the status area.

## Current Detection Surface

| Backend | Read-only probes | Current claim |
|---------|------------------|---------------|
| PipeWire | `wpctl status`, `pw-cli --version`, fallback `pw-cli info 0` | Detects service, creates virtual sinks, and links ports |
| PulseAudio | `pactl info` | Detects native/compat servers; supports virtual sinks, stream moves, and stream controls |
| JACK | `jack_lsp`, `jack_lsp -p` | Detects service, lists ports, and connects existing ports |
| ALSA | `aplay -l` | Detects playback hardware visibility |

Run the detector from a source checkout:

```bash
pnpm detect:audio
```

This command does not create virtual devices or change host routes.

## Current Runtime Surface

`@loopwire/audio-host` includes a native PipeWire adapter that uses `pw-cli` and `pw-link`. It can:

- list PipeWire output ports as source candidates for the desktop source picker,
- list PipeWire input ports as host-backed output and physical monitor target candidates,
- create Loopwire-owned virtual output and monitor sinks with `pw-cli create-node adapter` when an output bus or
  monitor has no host `deviceName`,
- link configured existing PipeWire output ports to input ports when route endpoints include host `deviceName` values,
- link configured host-backed input ports into those Loopwire-owned virtual output sinks,
- disconnect configured route links when a route is muted,
- link configured output monitor ports to virtual monitor sink ports or existing physical monitor sink ports,
- verify configured links from `pw-link -l`,
- verify muted route links are disconnected,
- unlink only the configured PipeWire port pairs,
- destroy the selected configuration's Loopwire-owned virtual output and monitor sinks during unload or rollback,
- roll back links created before a later link fails,
- reject unsupported non-unity route gain before attempting host commands,
- run in dry-run mode by default.

This native PipeWire path does not yet apply route gain controls. Route mute is enforced by disconnecting the
configured existing link. Monitor routing can use a Loopwire-owned virtual monitor sink or an existing target sink
`deviceName`. Its route-control semantics are reported as link-only with mute support.

`@loopwire/audio-host` includes a native JACK adapter that uses `jack_lsp`, `jack_connect`, and `jack_disconnect`. It
can:

- list JACK output ports as source candidates for the desktop source picker,
- list JACK input ports as host-backed output and physical monitor target candidates,
- connect configured existing JACK output ports to input ports when route endpoints include host `deviceName` values,
- disconnect configured route connections when a route is muted,
- connect configured output monitor ports to existing physical monitor sink ports,
- verify configured connections from `jack_lsp -c`,
- verify muted route connections are disconnected,
- disconnect only the configured JACK port pairs,
- roll back connections created before a later connection fails,
- reject unsupported non-unity route gain before attempting host commands,
- run in dry-run mode by default.

This JACK path does not yet create virtual JACK ports or apply route gain controls. Route mute is enforced by
disconnecting the configured existing connection. Monitor routing requires an existing target sink `deviceName`.
Its route-control semantics are reported as link-only with mute support.

`@loopwire/audio-host` also includes a `pactl` runtime adapter for PulseAudio and PipeWire's PulseAudio compatibility
layer. It can:

- create one `module-null-sink` virtual sink per Loopwire output,
- create Loopwire-owned monitor sinks and link output monitor sources with `module-loopback`,
- move matching PulseAudio sink inputs into those Loopwire sinks,
- apply route gain and mute as PulseAudio sink-input volume/mute controls for matching streams,
- verify that expected Loopwire sinks exist,
- verify that expected monitor loopbacks exist,
- verify that currently present matching streams are routed to the expected Loopwire sink,
- verify volume and mute for currently present matching streams,
- fail normal switch verification when a configured route has no matching live stream, instead of reporting fake success,
- treat absent matching streams as pending during startup and background restore so virtual sinks can stay ready before apps launch,
- refresh pending stream routes during live source-checkout background restore without recreating virtual sinks,
- unload only modules whose `sink_name` matches the selected Loopwire configuration,
- roll back already-created module IDs if a later sink creation or stream control fails,
- restore moved streams plus their original volume and mute when a later stream route operation fails,
- run in dry-run mode by default.

Stream matching currently uses the input endpoint id and label as case-insensitive tokens against `pactl list
sink-inputs` metadata, such as `application.name` or `application.process.binary`. This is stream-level control, not
true per-edge matrix mixing: one source routed to multiple outputs still needs a proper graph backend. Monitor routing
uses Loopwire-owned monitor sinks by default, or a configured monitor `deviceName` as the target physical sink.
Its route-control semantics are reported as stream-level.

Backend detection reports `mixing.controlScope` so the desktop can distinguish true graph-edge controls from
stream-level or link-only degraded controls.
