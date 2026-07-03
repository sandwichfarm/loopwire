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
is persisted and requests an undecorated Tauri window before showing Loopwire-owned drag, minimize, and close controls.

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
`pw-link`, and `pw-cli`.

The desktop runs live-apply preflight before arming host mutation. The preflight catches static backend/configuration
mismatches that would fail before useful host work starts, including missing backend selection, non-unity native
PipeWire/JACK route gain, missing native source ports, and JACK virtual-port gaps.

Route gain and mute edits are persisted as configuration changes. The PulseAudio compatibility adapter can apply them
to currently present matching sink inputs. Native PipeWire and JACK enforce route mute by disconnecting configured
existing graph edges, but still reject non-unity gain before host commands because plain link operations do not provide
per-edge gain.

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

The Tauri command bridge is the only desktop live-command boundary. It rejects commands outside the explicit audio
allowlist and runs arguments without a shell.

Current read-only probes:

- PipeWire: `wpctl status`, `pw-cli --version`, fallback `pw-cli info 0`.
- PulseAudio: `pactl info`.
- JACK: `jack_lsp`.
- ALSA: `aplay -l`.

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
