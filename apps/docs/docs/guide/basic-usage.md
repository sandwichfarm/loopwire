# Basic Usage

This is the shortest honest Loopwire walkthrough: create one virtual device, route a couple of sources into a stereo
bus, and monitor the result without claiming host behavior the selected backend cannot provide.

## Before you start

- Follow [Install](/guide/install).
- Start the desktop shell with `pnpm --filter @loopwire/desktop dev` or a packaged desktop build.
- If you are in browser preview, expect host audio mutations to stay in preview mode.

## 1. Create a device

Use **New Virtual Device** in the sidebar.

New devices start with a default route:

- **Pass-Thru**
- **Channels 1 & 2**
- channel 1 -> channel 1 and channel 2 -> channel 2 already wired

That gives you a visible stereo base immediately.

## 2. Add sources

Open the grouped `+` menu in **Sources** and add the inputs you want:

- running app streams when the selected backend can enumerate them,
- capture hardware such as a microphone,
- system sources,
- or another pass-through style source while you sketch the route.

Loopwire auto-cables new sources to the first output bus channel-for-channel.

## 3. Add outputs and monitors

In **Output Channels**, add a bus if the default stereo pair is not enough. The desktop shell currently offers:

- **Stereo Bus**
- **Mono Bus**
- **Quad Bus**

In **Monitors**, add a playback target such as headphones or speakers so you can hear the resulting mix.

## 4. Draw and remove routes

- Drag from an output port to a compatible input port to create a route.
- Click a cable to select it.
- Press `Delete`, or use the footer delete action, to remove the selected route or card.

Removing a source, bus, or monitor also removes the routes attached to it.

## 5. Tune the route state

Each card exposes an **Options** strip:

- source volume drives the gain of outgoing routes,
- app sources can use **Mute when capturing**,
- monitor volume is saved and applied on host apply.

The device itself carries On/Off, mute, and volume controls in the sidebar.

## 6. Understand preview versus live apply

Loopwire keeps the saved routing graph separate from the host audio graph.

Selecting a device or backend can run live only when preflight passes. Otherwise Loopwire stays in preview mode and
tells you why.

Common preview-only cases:

- browser preview instead of the Tauri shell,
- no backend selected yet,
- a backend detected as unavailable,
- PulseAudio one-source fan-out,
- native PipeWire or JACK routes that require non-100% gain on an unmuted edge.

## 7. Save, export, and inspect

Open **Settings** with `Ctrl+,` for the non-canvas surfaces:

- **Audio Backend** shows detected backends and the runtime activity ledger.
- **Transfer** exports the selected device as versioned JSON and imports pasted exports as a new device.
- **Diagnostics** lists backend capability reports.
- **Startup** manages desktop autostart and background restore when the current environment allows it.

## A practical first route

1. Create a new device.
2. Add **Browser** and **Studio Microphone** under **Sources**.
3. Keep **Channels 1 & 2** as the main bus.
4. Add **Headphones** in **Monitors**.
5. Confirm both sources feed the stereo bus and the bus feeds the monitor.

That path matches the current desktop screenshot and stays inside functionality already implemented today.
