# Devices

Loopwire presents each routing workspace as a **virtual audio device**. A device contains sources, output channel
buses, monitors, and the cables (routes) between them, plus device-level enable/mute/volume state and the timestamp of
the last verified app-runtime apply. (In the domain model and persisted state these are still called
*configurations*.)

## The Desktop UI

The main window has two regions:

- The **Devices sidebar** lists every virtual device with its name, an On/Off pill, a summary of its sources, a mute
  button, and a volume slider. `+ New Virtual Device` creates a device; the `–` button removes the selected one and
  shows an undo toast for five seconds instead of asking for confirmation.
- The **canvas** is a patch-bay editor for the selected device with three columns: **Sources**, **Output Channels**,
  and **Monitors**. Cards are wired with cables drawn between port dots on their edges.

From the canvas you can:

- rename the device (pencil button, or automatically right after creating it; Enter commits, Esc cancels),
- add a source from the grouped ⊕ menu beside *Sources* (running app streams, system sources, and capture devices as
  the selected backend exposes them) — it is auto-cabled to the first bus and selected,
- append an output channel bus instantly with the ⊕ beside *Output Channels*,
- add a monitor from the ⊕ menu beside *Monitors* (playback devices) — it is auto-cabled from every bus,
- drag from an output port to a compatible input port to create a route (source → bus, or bus → monitor),
- click a cable to select its route and press Delete (or use the footer **Delete** button) to remove it,
- select any card and delete it the same way; removing an endpoint prunes its routes,
- toggle any source or monitor On/Off from its pill — its cables desaturate while it is off,
- expand a card's **Options** strip: source volume (which drives the gain of every route leaving the source), a
  *Mute when capturing* checkbox on app sources, and monitor volume (configured state, applied on host apply),
- collapse the Monitors column with **Hide Monitors** in the footer.

New devices start with a default graph: a stereo **Pass-Thru** source wired 1→1, 2→2 into a **Channels 1 & 2** bus.
Devices are named `Loopwire Device N` by default.

Every mutation is saved to Loopwire state immediately. Host audio changes only through the explicit apply path
described below. Meters render silent tracks until the audio host layer provides per-port levels — Loopwire does not
simulate levels it cannot observe.

App settings live in a separate Settings dialog (`Ctrl+,`): appearance/theme, the audio backend picker, the
preview/live host-apply control with its runtime activity ledger, startup integration, and update policy.

## Safety Rules

- Removing a device is undoable from its toast; the device list may be empty (the canvas shows a create hint).
- Invalid persisted state falls back to an empty state instead of corrupting saved devices.
- Legacy persisted payloads (schema v0/v1) are migrated into the current schema; migrations are covered by core tests.
- Failed apply or verify operations roll back to the previous app-runtime configuration.
- Failed edits (duplicate names, invalid routes, removing the last bus) leave state untouched and surface a typed
  error toast.
- Every device keeps at least one output bus.
- Editing a device while live apply is armed disarms it back to preview; re-arm in Settings to verify the change
  against the host.

## Host Audio Boundary

The PulseAudio compatibility adapter can create Loopwire-owned sinks, move matching streams, apply stream-level
volume/mute, and create monitor loopbacks through guarded `pactl` calls. Direct host mutation still belongs behind an
explicit apply path; dry-run and fake-runner tests remain the default verification surface. Because PulseAudio controls
whole sink-input streams, it can route each source to only one output at a time; the adapter and preflight reject
multiple routes from the same source.

Native PipeWire can create Loopwire-owned virtual output and monitor sinks, link existing source ports into those
sinks, disconnect muted route edges, and route to physical monitor sink targets. JACK can link existing host ports or
pre-existing Loopwire-owned JACK ports, disconnect muted route edges, and route to physical or Loopwire-owned monitor
targets. JACK virtual port creation and true mixer-style gain remain planned backend work.

Settings exposes the **Host apply** control. *Preview* mode runs selected backend adapters without mutating the host.
*Live (armed)* mode is session-local and routes commands through the Tauri command bridge, which only allows `pactl`,
`pw-cli`, `pw-link`, `jack_lsp`, `jack_connect`, and `jack_disconnect` without invoking a shell.

Before live mode can be armed — and again before every live device switch — Loopwire runs a static preflight against
the selected backend and configuration. It blocks known-failing live applies such as no selected backend, a backend
that detection reports unavailable, PulseAudio fan-out routes, native PipeWire/JACK routes with non-100% gain (set the
source volume back to 100% to clear this), and missing host source ports for native PipeWire routes. Blockers surface
as error toasts and in the backend status line. Preflight consumes detected backend mixing semantics: PulseAudio
compatibility is stream-level, native PipeWire and JACK are link-only, and ALSA route controls are unavailable because
the ALSA path is diagnostics-only.

JACK live apply also requires every routed source, routed output, monitor source, and monitor target to resolve to a
JACK port before arming. For unbound JACK endpoints the runtime adapter probes deterministic Loopwire-owned client
names such as `loopwire_<configuration>_<endpoint>`. The required port list is available for automation with
`pnpm jack:ports -- --configuration exported-loopwire-config.json --format tsv`; after creating the external JACK
clients, run `pnpm jack:verify -- --configuration exported-loopwire-config.json` to confirm the port set is ready.

Changing the selected backend runs a backend-change transaction in preview mode and disarms any previous live-apply
session. Loopwire commits the new backend as the saved startup-restore choice
only after the active configuration verifies against it, and the backend picker and host-apply
controls stay disabled while a backend-change transaction is in flight.
Automatic single-backend selection uses the same transaction path during startup detection, so a lone detected backend
is not persisted until the active configuration verifies against it.
Device (configuration) switches are serialized by token, so
stale async switch results cannot replace the state of a newer selection. After startup restore, a backend change, or
a device switch, the Settings backend card shows a runtime activity ledger with the exact unload,
apply, verify, and rollback operations that ran.

## Monitors

**Hide Monitors** collapses the Monitors column for the current device so capture-focused work shows only Sources and
Output Channels; the buses dock to the right edge and the button becomes **Show Monitors**. Hiding is a view state —
monitors, their host sink bindings, and their cables are preserved and reappear on **Show Monitors**.

Monitors added from the playback-device menu keep the host sink name they were created from, so supported backend
adapters can route monitor audio to that physical output on apply. Manual host-binding overrides are not part of the
rebuilt UI yet; export the state file and edit `deviceName` if you need an unlisted sink (tracked as a UI gap).

## Persistence & Export Format

Devices persist in schema v2, which adds optional device controls (`enabled`, `muted`, `volume`) and endpoint controls
(`enabled`, `volume`, `muteWhenCapturing`) plus output→monitor routes on top of schema v1. Older payloads migrate
forward automatically.

Configuration exports use a versioned JSON wrapper (import/export currently has no UI surface; the format remains
supported by `@loopwire/core` and the CLI scripts):

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
output ids (or run from an output to a monitor).
