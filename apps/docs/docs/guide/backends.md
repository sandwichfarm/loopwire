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
| ALSA | `aplay -l`, `arecord -l` | Detects playback and capture hardware visibility for diagnostics |

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
- connect pre-existing Loopwire-owned JACK route ports when app endpoints omit host `deviceName` values,
- disconnect configured route connections when a route is muted,
- connect configured output monitor ports to existing physical monitor sink ports,
- connect configured output monitor ports to pre-existing Loopwire-owned monitor target ports,
- verify configured connections from `jack_lsp -c`,
- verify muted route connections are disconnected,
- disconnect only the configured JACK port pairs,
- roll back connections created before a later connection fails,
- reject unsupported non-unity route gain before attempting host commands,
- fail closed before `jack_connect` when required host or Loopwire-owned JACK ports are missing,
- run in dry-run mode by default.

This JACK path does not yet ship a default virtual JACK port creator or apply route gain controls. Route mute is
enforced by disconnecting the configured existing connection. Route inputs, route outputs, monitor source outputs, and
monitor targets can reference existing JACK ports through `deviceName`, or they can omit `deviceName` only when
matching Loopwire-owned JACK ports already exist under the deterministic `loopwire_<configuration>...` names. The
audio-host runtime can now call an injected JACK virtual port provider for missing Loopwire-owned ports, then re-read
`jack_lsp` before connecting; it still fails closed when the provider does not make those ports appear. Missing ports
are reported after the read-only `jack_lsp` probe and before any graph mutation. The same audio-host helper describes
and verifies the deterministic Loopwire-owned client names and suggested channel ports, so scripts, support bundles,
runtime failures, and the command-backed provider arguments stay aligned on the expected repair target. The desktop live-apply preflight is
stricter: it requires JACK endpoints to be explicitly bound to existing ports before arming, so users see the repair
action before a host apply attempt. Its route-control semantics are reported as link-only with mute support.

For automation or pro-audio session templates, run:

```bash
pnpm jack:ports -- --configuration exported-loopwire-config.json --format tsv
pnpm jack:verify -- --configuration exported-loopwire-config.json
```

The command is read-only. It accepts a Loopwire configuration export or persisted state file and prints the configured
JACK clients plus any deterministic Loopwire-owned clients that must already be created by an external JACK client.
`pnpm jack:verify` is also read-only: it compares those requirements against `jack_lsp` output and exits nonzero when
ports are missing. JSON and TSV output include matched and missing ports for each requirement. For support bundles or
CI-style checks without a live JACK server, pass
`--ports-file captured-jack-lsp.txt` to verify against a saved newline-delimited port list.

The ALSA path is read-only diagnostics. It lists playback hardware with `aplay -l` and capture hardware with
`arecord -l` so users can see whether the kernel/session can see devices before choosing a graph-capable backend.
Loopwire does not create ALSA virtual devices, move streams, or apply routes through ALSA.

`@loopwire/audio-host` also includes a `pactl` runtime adapter for PulseAudio and PipeWire's PulseAudio compatibility
layer. It can:

- create one `module-null-sink` virtual sink per Loopwire output,
- create Loopwire-owned monitor sinks and link output monitor sources with `module-loopback`,
- move matching PulseAudio sink inputs into those Loopwire sinks,
- apply route gain and mute as PulseAudio sink-input volume/mute controls for matching streams,
- reject configurations that route one source to multiple outputs before moving any stream,
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
true per-edge matrix mixing: one source routed to multiple outputs still needs a proper graph backend, so the PulseAudio
adapter fails closed before host mutation when it sees source fan-out. Monitor routing uses Loopwire-owned monitor sinks
by default, or a configured monitor `deviceName` as the target physical sink.
Its route-control semantics are reported as stream-level, and detection/support bundles expose `one output per source`
as a known PulseAudio gap.

Backend detection reports `mixing.controlScope` so the desktop can distinguish true graph-edge controls from
stream-level, link-only, or unavailable controls. The desktop consumes detected backend mixing semantics instead of
hardcoding backend names, so a future backend report with graph-edge gain support can unlock route gain editing and
live-apply preflight without a UI rewrite. ALSA reports unavailable controls because it is diagnostics-only.

The core package now has a pure DSP mix planner, renderer, and cycle runner for graph-edge behavior. It can render
per-route gain and mute into output buffers from supplied `Float32Array` source channels, including one source routed
to multiple outputs. The cycle runner reads each source once through an injected source port, writes rendered outputs
through injected output ports, and can fail closed before writes when required source buffers are missing. That proves
the per-edge mix math and adapter-facing execution contract. The audio-host package now includes an injected DSP graph adapter
that can dry-run source/output plans, render and write buffers through supplied ports, verify rendered outputs
through a supplied verifier, clear outputs during unload, and restore the rollback configuration through the core
switch transaction contract. It also ships a first-class configuration runtime adapter wrapper for startup re-apply and
configuration switch transactions.

`@loopwire/audio-host` also exposes a command-backed DSP provider helper for future live host integrations. The helper
calls a provider command with stable `read-source`, `write-output`, `verify-output`, and `clear-output` operations.
`read-source` returns JSON channel buffers on stdout, while rendered output buffers are passed to `write-output` and
`verify-output` as JSON stdin so provider implementations do not need unsafe shell argument payloads. This is still a
provider contract: live backend DSP still needs a host adapter that can capture source streams and inject the rendered
outputs into PipeWire or JACK.

Before enabling a DSP provider for boot restore, inspect and smoke-test its bounded contract:

```bash
pnpm dsp:plan -- --configuration exported-loopwire-config.json --frame-count 480 --format tsv
pnpm dsp:verify -- \
  --configuration exported-loopwire-config.json \
  --provider-command loopwire-dsp-provider \
  --frame-count 480 \
  --pretty
```

`pnpm dsp:plan` is read-only and prints the `read-source`, `write-output`, and `verify-output` operations Loopwire
will need for a configuration. `pnpm dsp:verify` is explicit execute mode: it calls the provider, writes rendered
output buffers, verifies them, and exits nonzero if provider apply or verification fails.
