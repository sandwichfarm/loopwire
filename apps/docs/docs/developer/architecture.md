# Architecture

Loopwire uses clean architecture boundaries so the UI can be beautiful without becoming the source of truth for host
audio state.

## Layers

1. Domain model: configurations, endpoints, routes, monitors, backend choices, persistence, and errors.
2. Routing engine: validates changes and prepares apply, verify, and rollback plans.
3. Backend adapters: PipeWire, PulseAudio, JACK, ALSA, and compatibility bridges.
4. Platform integration: startup, packaging, portals, DBus, and desktop environment behavior.
5. UI shell: Svelte/Tauri surface that displays state and calls application services.
6. Docs/site: VitePress public documentation and release guidance.

## Current Walking Skeleton

The first slice implements the pure domain model, persistence rules, and UI shell. The second slice adds
`@loopwire/audio-host`, a read-only backend capability package with injected command execution and fake-runner tests.
The third slice adds configuration CRUD, versioned import/export, legacy persistence migration, startup re-apply, and
an app-runtime transaction port for unload, apply, verify, and rollback.
The fourth slice adds keyboard-accessible route gain/mute controls, on-demand backend diagnostics, responsive visual QA,
and guarded Tauri custom chrome actions. The desktop defaults to native decorations, but the custom chrome preference
is persisted and requests an undecorated Tauri window before showing Loopwire-owned drag, minimize, maximize/restore,
and close controls.

The first host mutation primitives now live in `@loopwire/audio-host`. A guarded native PipeWire adapter links existing
PipeWire ports through `pw-link`, creates Loopwire-owned virtual output and monitor sinks through `pw-cli create-node adapter`,
disconnects muted route links, verifies expected link presence and muted-link absence, unlinks configured pairs,
destroys selected virtual nodes, and rolls back created links or nodes on partial failure. A guarded `pactl`
adapter for PulseAudio and PipeWire's PulseAudio compatibility layer creates,
verifies, and removes Loopwire-owned null sinks, moves matching sink inputs into those sinks, applies matching stream
volume/mute controls, creates Loopwire monitor sinks, links output monitor sources through `module-loopback`, and can
target a configured physical monitor sink name. PulseAudio route verification now fails when a configured route has no
matching live stream during normal switches, so absent app streams cannot be reported as verified. Startup and
background restore use an explicit pending-stream mode so sinks can be prepared before apps launch without rolling back
the restored configuration. Source-checkout background restore can also refresh pending PulseAudio stream routes for a
bounded live window without recreating the Loopwire sinks. Neither path yet provides true per-edge matrix mixing for one
source routed to multiple outputs.

## Configuration Runtime

The core package owns configuration state and exposes pure operations for:

- create, edit, duplicate, and delete,
- export and import of a versioned `loopwire.configuration` JSON payload,
- safe restore from persisted state,
- migration from legacy persisted payloads,
- runtime switching through an injected adapter.

The desktop app currently injects an app-local runtime adapter. That adapter proves transaction ordering and rollback
behavior without mutating the host graph. The desktop can also inject selected host adapters in preview or live mode.
Live mode is session-local, requires the Tauri shell, and routes commands through an allowlisted bridge for `pactl`,
`pw-link`, `pw-cli`, `jack_lsp`, `jack_connect`, and `jack_disconnect`.

The desktop runs live-apply preflight before arming host mutation. The preflight catches static backend/configuration
mismatches that would fail before useful host work starts, including missing backend selection, non-unity native
PipeWire/JACK route gain, missing native source ports, and JACK virtual-port gaps. JACK deterministic port names come
from the shared audio-host requirement helper, keeping desktop blocker text aligned with the runtime adapter's
`jack_lsp` probe expectations.
The `pnpm jack:ports` command is the CLI surface for that same helper, so support scripts and pro-audio session
templates can inspect required JACK clients without touching the host graph. `pnpm jack:verify` adds the read-only
readiness check by comparing those requirements against live `jack_lsp` output or a saved port-list fixture. The native
JACK runtime can call an injected JACK virtual port provider for missing Loopwire-owned ports and then re-probe
`jack_lsp`, but the shipped desktop path does not yet bundle a real JACK client provider.

Route gain and mute edits are persisted as configuration changes. The PulseAudio compatibility adapter can apply them
to currently present matching sink inputs. Native PipeWire and JACK enforce route mute by disconnecting configured
existing graph edges, but still reject non-unity gain before host commands because plain link operations do not provide
per-edge gain.

`@loopwire/core` also includes a pure DSP mix planner, renderer, and cycle runner. It turns a configuration into
per-output contribution plans, applies per-edge gain and mute to planar `Float32Array` source buffers, sums active
routes without clamping float headroom, and reports missing source buffers. The cycle runner reads each source once
through an injected source port and writes rendered outputs through injected output ports, so future graph-edge DSP
adapters have a typed execution contract. `@loopwire/audio-host` wraps that contract with an injected DSP graph adapter
for dry-run planning, apply-mode render/write, verifier-driven output checks, clear-on-unload behavior, and
restore-on-rollback behavior. It also exposes a first-class configuration runtime adapter wrapper for the core
startup and switch transaction contract. The package also includes a command-backed DSP provider helper that maps
`read-source`, `write-output`, `verify-output`, and `clear-output` operations to a provider command, with rendered
buffers sent as JSON stdin for write and verify operations.
It does not yet connect live host capture streams to host playback or virtual device injection.

## Backend Contract Direction

Every backend adapter must eventually provide:

- detection and capability report,
- route-control semantics, including whether gain/mute are true graph-edge controls,
- diagnostics suitable for support,
- apply plan,
- verify plan,
- rollback plan,
- typed errors with next actions.

No UI component should call PipeWire, PulseAudio, JACK, ALSA, systemd, or shell commands directly.
Desktop route-control status and live-apply preflight consume detected backend mixing semantics instead of hardcoded
backend names, so graph-edge-capable adapters can unlock route gain without another UI contract change.

The Tauri command bridge is the only desktop live-command boundary. It rejects commands outside the explicit audio
allowlist, rejects argument shapes outside Loopwire's detector/runtime contract, and runs arguments without a shell.

Current read-only probes:

- PipeWire: `wpctl status`, `pw-cli --version`, fallback `pw-cli info 0`.
- PulseAudio: `pactl info`.
- JACK: `jack_lsp`.
- ALSA: `aplay -l`, `arecord -l`.

Current host mutation primitive:

- Native PipeWire: `pw-cli list-objects Node`, `pw-cli create-node adapter`, `pw-cli destroy`, `pw-link -o`,
  `pw-link -i`, `pw-link -l`, `pw-link <output-port> <input-port>`, and `pw-link -d <output-port> <input-port>`
  through an injected command runner.
- Native JACK: `jack_lsp`, `jack_lsp -c`, `jack_connect <output-port> <input-port>`, and
  `jack_disconnect <output-port> <input-port>` through an injected command runner.
- PulseAudio/PipeWire compatibility: `pactl load-module module-null-sink`, `pactl list short modules`,
  `pactl unload-module`, `pactl list short sinks`, `pactl list sink-inputs`, `pactl move-sink-input`,
  `pactl set-sink-input-volume`, `pactl set-sink-input-mute`, and `pactl load-module module-loopback` through an
  injected command runner.
