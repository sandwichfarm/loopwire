# Configurations

Loopwire configurations are named routing workspaces. They contain inputs, outputs, monitors, routes, metadata, and the
timestamp of the last verified app-runtime apply.

## Current Capabilities

From the desktop shell you can:

- create a new configuration,
- edit the active configuration name and notes,
- add a source from the desktop source picker and route it to the active output,
- add an output bus from the desktop output picker and route existing sources to it,
- add a monitor endpoint from the desktop monitor picker,
- add or remove individual route edges between existing sources and outputs,
- remove sources, outputs, and monitors from the active configuration,
- manually bind source and output endpoints to host port names when backend enumeration misses an unusual setup,
- duplicate the active configuration,
- delete the active configuration after switching to a fallback,
- export the active configuration as versioned JSON,
- import a versioned Loopwire configuration JSON payload,
- switch configurations through unload, apply, verify, and rollback steps,
- adjust route gain and mute state with keyboard-operable controls.

Startup restore loads the last selected configuration from local persistence and re-applies it through the same runtime
verification path.

## Safety Rules

- Loopwire keeps at least one configuration.
- Invalid persisted state falls back to defaults instead of corrupting saved configurations.
- Invalid imports are rejected without changing the current state.
- Legacy persisted payloads are migrated into the current schema in core tests.
- Failed apply or verify operations roll back to the previous app-runtime configuration.
- Configuration switches are serialized in the desktop shell. While unload, apply, verify, or rollback is in flight,
  configuration actions are disabled and stale async switch results cannot replace the latest selected configuration.
- Route edits update the saved configuration immediately, but they do not change host audio yet.
- The source picker can list detected PipeWire output ports, JACK output ports, or PulseAudio-compatible running app
  streams in the desktop shell and falls back to static candidates when stream enumeration is unavailable.
- Source picker additions update the saved app-runtime configuration immediately. Host audio follows only when the
  selected backend can apply that route and live apply is explicitly armed.
- Output picker additions update the saved app-runtime configuration immediately and create default routes from existing
  sources to the new bus. For native PipeWire/JACK host outputs, only existing sources with host `deviceName` values are
  auto-routed, so app-only demo inputs do not become impossible native links.
- Monitor picker additions update the saved app-runtime configuration immediately. Monitor host routing still follows
  selected backend capability and explicit live apply.
- Route edits update the saved app-runtime configuration immediately. The route lane can create one edge per
  source/output pair, remove individual edges, and keep per-edge gain/mute state independent.
- Removing an input or output prunes the routes that referenced it. Loopwire keeps at least one output in every
  configuration, and removing a monitor also clears any hidden-monitor marker for that monitor in that configuration.
- Source and output cards include manual host binding fields. Use them when a PipeWire/JACK port or PulseAudio stream
  token exists on the host but was not listed by the picker. Clearing the field returns the endpoint to app-runtime-only
  preview behavior.
- The monitor target picker lists detected PipeWire input ports, JACK input ports, and PulseAudio-compatible playback
  sinks in the desktop shell and keeps a manual sink-name override for backend gaps or unusual host setups.

## Host Audio Boundary

The PulseAudio compatibility adapter can create Loopwire-owned sinks, move matching streams, apply stream-level
volume/mute, and create monitor loopbacks through guarded `pactl` calls. Direct host mutation still belongs behind an
explicit apply path; dry-run and fake-runner tests remain the default verification surface. Because PulseAudio controls
whole sink-input streams, it can route each source to only one output at a time. The adapter and desktop preflight reject
multiple routes from the same source instead of moving one stream through several outputs where only the final move would
win.

Native PipeWire can create Loopwire-owned virtual output and monitor sinks, link existing source ports into those
sinks, disconnect muted route edges, and route to physical monitor sink targets. JACK can link existing host ports or
pre-existing Loopwire-owned JACK ports, disconnect muted route edges, and route to physical or Loopwire-owned monitor
targets. JACK virtual port creation and true mixer-style gain remain planned backend work.

The desktop exposes a `Host apply` control. `Preview` mode runs selected backend adapters without mutating the host.
`Live armed` mode is session-local and routes commands through the Tauri command bridge, which only allows `pactl`,
`pw-cli`, `pw-link`, `jack_lsp`, `jack_connect`, and `jack_disconnect` without invoking a shell.
Editing the active configuration disarms live apply and returns the session to preview mode, because source, output,
monitor, route, gain, mute, host-binding, and metadata edits are saved first in Loopwire state. Re-arm live apply after
the edit when you want the changed configuration verified on the host.
Changing the selected backend runs a backend-change transaction in preview mode and disarms any previous live-apply
session, so backend changes cannot silently carry a live mutation state across audio systems. Loopwire commits the new
backend as the saved startup-restore choice only after the active configuration verifies against it. Backend selection,
host-apply arming, and configuration switching controls stay disabled while a backend-change transaction is in flight,
and stale backend results are ignored if a newer selection starts first.
Automatic single-backend selection uses the same transaction path during startup detection, so a lone detected backend
is not persisted until the active configuration verifies against it.
After startup restore, a backend change, or a configuration click, the desktop shows a runtime activity ledger with the
exact operations that ran, including the exact unload, apply, verify, and rollback operations when the transaction
includes them, so switch behavior is inspectable instead of being reduced to a single status line.

Before live mode can be armed, the desktop runs a static preflight against the selected backend and configuration. It
blocks known-failing live applies such as no selected backend, a selected backend that current detection reports as
unavailable, PulseAudio routes that fan one source out to multiple outputs, native PipeWire/JACK routes with non-100%
gain, and missing host source ports for native PipeWire routes.
The visible preflight strip and the actual configuration-switch guard both consume the same detected backend capability
report, so a future graph-edge-capable backend report unlocks live switching without a mismatch between the UI and the
runtime guard.
JACK live apply also requires every routed source, routed output, monitor source, and monitor target to be bound to an
existing JACK port before arming, because Loopwire does not create JACK client ports yet.
For unbound JACK endpoints, the blocker includes the deterministic Loopwire-owned client name that the runtime adapter
would probe, such as `loopwire_<configuration>_<endpoint>`, so the required external JACK client/port binding is
visible before any host command runs.
The same list is available for automation with
`pnpm jack:ports -- --configuration exported-loopwire-config.json --format tsv`.
After creating the external JACK clients, run
`pnpm jack:verify -- --configuration exported-loopwire-config.json` to confirm the port set is ready before arming live
apply.
When more than one issue is present, the preflight strip lists every blocker so the configuration can be fixed without
trial-and-error. Native backend preflight names the affected routes, sources, outputs, and monitors instead of only
describing the blocker category.
For native PipeWire or JACK, the preflight strip also offers a `Reset gains` action when non-100% route gains are the
blocking issue, bringing all affected routes back to 100% without touching host audio.
When a native PipeWire or JACK backend is selected, route gain sliders become read-only because those backends are
link-only today; mute stays available and `Reset gains` remains the repair path for older configurations.

The desktop also exposes selected-backend route-control semantics from detected backend mixing semantics. PulseAudio compatibility is
stream-level, native PipeWire and JACK are link-only with route mute support, ALSA route controls are unavailable, and
true graph-edge gain remains a backend capability gap until a live DSP backend reports graph-edge gain support.

## Monitors

Monitors can be hidden without deleting them. Monitor visibility is scoped to the active configuration, so hiding
`Headphones` in one workspace does not hide a `Headphones` monitor in another workspace. A monitor can also carry an
optional host sink name so supported backend adapters can route monitor audio to a physical output.
Hidden monitors are removed from the main monitor grid and listed in a recovery tray with `Show` actions plus a
`Show all` action when more than one monitor is hidden, so hiding monitors reduces visual noise without forcing the
user to recreate host sink bindings later.

In the current desktop UI, native PipeWire/JACK target ports also appear in the output picker as host-backed outputs.
Use the monitor's `Host sink` selector to choose a detected PipeWire input port, JACK input port, PulseAudio-compatible
playback sink, or a manual sink name when the target is not listed. If the field is empty, native PipeWire and the
PulseAudio compatibility adapter keep using a Loopwire-owned monitor sink.

## Export Format

Configuration exports use a versioned JSON wrapper:

```json
{
  "kind": "loopwire.configuration",
  "version": 1,
  "configuration": {
    "id": "studio",
    "name": "Studio",
    "description": "Mic, browser, and monitor mix for focused recording.",
    "inputs": [
      { "id": "mic", "label": "Studio Mic", "role": "input", "channels": 2 }
    ],
    "outputs": [
      { "id": "recorder", "label": "Recorder Bus", "role": "output", "channels": 2 }
    ],
    "monitors": [],
    "routes": [
      { "id": "mic-recorder", "from": "mic", "to": "recorder", "gain": 0.86, "muted": false }
    ],
    "updatedAt": "2026-07-03T12:00:00.000Z"
  }
}
```

A valid imported configuration must include at least one output, and any routes must reference existing input and
output ids.
