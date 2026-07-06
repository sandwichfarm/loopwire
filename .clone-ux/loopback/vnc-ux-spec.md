# Loopwire UX Specification (clean-room, from Loopback reference)

Source of truth: live exploration of Rogue Amoeba Loopback over `vnc:macbook-1`
(screen 3456×2234 px @2x = 1728×1117 pt). Screenshots in `./screenshots/`.
This is a clean-room spec: it captures structure, behavior, and quality — not
Loopback's brand assets, icons, or copy. All names below use loopwire vocabulary.

Loopwire term mapping used throughout:

| Reference concept        | Loopwire term (existing code)                  |
|--------------------------|------------------------------------------------|
| Virtual device           | `LoopwireConfiguration` ("device" in UI)       |
| Source (app/mic/etc.)    | `AudioEndpoint` role `input`                   |
| Output channels          | device channel bus (new concept, see below)    |
| Monitor                  | `AudioEndpoint` role `monitor`                 |
| Cable/wire               | `AudioRoute`                                   |

## 1. Product shape

One window. Two persistent regions plus one canvas:

1. **Device sidebar** (left, fixed ~265 pt) — list of virtual devices; create/remove.
2. **Device canvas** (rest) — a patch-bay editor for the selected device with three
   columns: **Sources → Output Channels → Monitors**, joined by drawn cables.
3. **Canvas footer bar** — `Delete` (acts on canvas selection, left) and
   `Hide/Show Monitors` (right).

There is no tab bar, no dashboard, no settings clutter in the main window.
App settings live in a tiny separate Settings window (theme + updates).
Menu bar is minimal: App, Edit, Window, Help — every device operation is done
in-window, not via menus.

## 2. Information architecture

```
Window
├─ Sidebar "Devices"
│  ├─ Header row: app glyph + "Devices"
│  ├─ Device row (repeats)
│  │  ├─ Name + On/Off toggle pill
│  │  ├─ Source-icon strip + source summary ("iTerm, MacBook Pro Microphone")
│  │  ├─ Live mini-meter (only while audio flows)
│  │  └─ Mute icon-button + volume slider + "100%" readout
│  └─ Footer: [+ New Virtual Device]  [– remove selected]
└─ Canvas (per selected device)
   ├─ Title row: device name + pencil (rename)
   ├─ Column headers with add buttons:
   │  "Sources / <summary>" (+ menu) · "Output Channels / N Channels" (+) · "Monitors / N Devices" (+ menu)
   ├─ Source cards (col 1), channel-bus blocks (col 2), monitor cards (col 3)
   ├─ Cables source-port → bus-port and bus-port → monitor-port
   └─ Footer: Delete (canvas selection) · Hide/Show Monitors
```

## 3. Primary flows (all verified on target)

### 3.1 First run / empty state
- Empty sidebar; canvas shows centered brand glyph + one instruction:
  “Create your first virtual audio device by clicking **'New Virtual Device'**.”
  (`00-initial.png`, `35-restored-empty.png`)

### 3.2 Create device
- Click `+ New Virtual Device` (sidebar footer).
- A device appears instantly with a default name ("Loopback Audio" pattern →
  loopwire should use "Loopwire Device" or similar), preselected, **name field
  already in edit mode** (full-width field, text selected, accent focus ring)
  so typing renames immediately; Enter/click-away commits (`01-new-device.png`).
- Default graph: one **Pass-Thru** source (2ch) + one **Channels 1 & 2** bus,
  auto-cabled 1→1, 2→2. Monitors column empty. Device is immediately usable.

### 3.3 Add sources
- `+` beside "Sources" opens a grouped popup menu (`03-sources-menu.png`):
  - `Select Application…` (file picker, first item, highlighted)
  - **Running Applications** (live app list with icons)
  - **Special Sources** (system audio buckets — loopwire equivalent: desktop
    audio, notifications, per-role streams as PipeWire exposes them)
  - **Audio Devices** (capture hardware)
- Choosing an item inserts a source card, **selected**, auto-cabled to the
  first bus (`04-source-iterm.png`, `07-source-mic.png`).
- Already-added sources disappear from the menu (`06-sources-menu-2.png`).
- Cards sort alphabetically, Pass-Thru last observed; mono devices render one
  channel row; stereo render two (`07-source-mic.png`).

### 3.4 Add output channels
- `+` beside "Output Channels" appends a bus block ("Channels 3 & 4"), and
  multichannel-capable sources (Pass-Thru) grow matching channels, auto-cabled
  3→3, 4→4 (`12-add-channels.png`). Channels past 2 have no (L)/(R) suffix.

### 3.5 Add monitors
- `+` beside "Monitors" opens a menu with **Audio Devices** (playback devices)
  (`08-monitors-menu.png`). Selection adds a monitor card wired bus→monitor
  1→1, 2→2 (`09-monitor-speakers.png`).

### 3.6 Per-card controls
- Every source/monitor card header has an **On/Off toggle pill**.
  Off = red pill, knob left; that card's cables desaturate to gray; rest of
  graph stays accent-colored (`16-passthru-off.png`).
- `Options` disclosure at card bottom expands in-place:
  - App source: `Mute when capturing` checkbox + volume slider + % readout
    (`10-source-options.png`).
  - Monitor: volume slider mirroring the real device volume (12% observed)
    (`11-monitor-options.png`). Changing it must change the actual device volume.

### 3.7 Device-level controls (sidebar row)
- Toggle pill enables/disables the whole virtual device.
- Speaker icon-button toggles device mute (icon turns red/muted)
  (`18-sidebar-mute.png`).
- Volume slider + numeric % readout.
- Mini level meter appears in the row while audio flows (`07-source-mic.png`).

### 3.8 Rename
- Pencil button after the title (or the create flow) swaps the title for a
  full-width text field with accent focus ring, current name selected
  (`27-rename-mode.png`). Enter commits; sidebar updates live (`28-renamed.png`).

### 3.9 Selection & deletion
- Click card ⇒ accent (teal) 2 pt border; footer `Delete` becomes enabled
  (`29-source-removed.png` shows selected mic + enabled Delete).
- `Delete` removes the selected source/monitor/bus **instantly, no dialog**;
  graph re-flows and summaries update (`30-source-delete.png`).
- Sidebar `–` removes the **selected device instantly, no dialog**
  (`34-device-delete-confirm.png` → `35-restored-empty.png`).
  ⚠ Loopwire decision: add an undo toast instead of copying the no-confirm
  behavior verbatim (safer, still fast).
- Selecting a sidebar row does NOT enable footer Delete (it is canvas-scoped).

### 3.10 Hide monitors
- `Hide Monitors` collapses column 3; column 2 header becomes
  "Output Channels / N Channels" and blocks dock to the right edge; button
  becomes `Show Monitors` with slashed-eye icon (`19-hide-monitors.png`).
  Purpose: simplify view when only capture matters.

### 3.11 Cabling
- Cables render as smooth S-curves between ports; port = small circle on card
  edge (right edge for outputs, left edge for monitor inputs).
- Cable color = accent; grouped cables run parallel without merging.
- NOT verified over VNC (drag timed out; click-select ambiguous):
  drag-port-to-port to create, click-cable + Delete to remove. Treat as the
  intended interaction, implement it, but do not claim Loopback parity.

### 3.12 App settings & menus
- Settings window (⌘,): **Appearance** (Match System / Light / Dark previews)
  and **Software Update** section (`20-preferences.png`).
- App menu: About, Check for Updates…, Settings…, License…, Permissions…,
  Services, Hide/Quit (`22-menu-loopback.png`). Loopwire: keep an equally
  minimal menu/shortcut surface (Settings ⌘,).

## 4. State model (per rendering)

Device: `on | off`, `muted`, `volume 0–100`, `name`, selected-in-sidebar.
Source card: `on | off`, `selected`, `options-expanded`, per-channel live level,
  `volume`, `muteWhenCapturing` (apps), mono/stereo/N-channel.
Bus block: `selected`, per-channel live level, channel labels (1 (L), 2 (R), 3, 4…).
Monitor card: `on | off`, `selected`, `options-expanded`, `volume` (bound to
  real device), per-channel live level.
Cable: `normal | dimmed` (endpoint card off) `| selected` (uncertain visual).
Global: monitors hidden?, device list, selection (sidebar) vs selection (canvas)
  are independent.

Empty states: no devices (§3.1); device with no monitors (column empty, no
placeholder text observed); source list never empty (Pass-Thru default, and it
can be deleted — canvas allows zero sources).

Error/warning states: none observed during exploration (no permission or
backend failures were triggered). Loopwire must design its own diagnostics
surface per AGENTS.md ("make failure states boring") — do not fake parity here.

## 5. Interaction model

- Single-click selects; controls (toggles, sliders, disclosures) act on first
  click without selecting the card first.
- All mutation is immediate — there is no Apply/Save. The graph IS the state.
  For loopwire this maps to transactional apply under the hood (routing engine
  preview→apply→verify) with UI optimism and rollback on failure.
- Keyboard: Enter commits rename; Esc cancels menus. Delete-key removal of
  canvas selection could not be confirmed over VNC; wire it to the same action
  as the footer Delete button.
- No context menus anywhere (right-click produced nothing, `17-context-menu.png`).
- No drag-reorder observed. No multi-select observed.

## 6. Accessibility expectations (for the rebuild; not verifiable over VNC)

- Sidebar is a listbox (`aria-selected` on rows); canvas cards are labelled
  groups; every port gets an accessible name ("iTerm channel 1 output port").
- Toggles are switches with visible On/Off text (Loopback prints the word in
  the pill — keep this; color is never the only signal, red/teal + label + knob
  position are redundant cues).
- Meters are `role="meter"` with `aria-valuenow`, polite updates suppressed.
- Focus ring: accent 2 pt ring, same as rename field treatment.
- All controls reachable by keyboard; menu popups are real menus with
  type-ahead. Slider keyboard step 1%, page-step 10%.
- Respect `prefers-reduced-motion`: no cable draw animations under it.

## 7. Quality bar notes (what makes the reference feel native)

- One accent hue for everything live/selected/interactive; gray for dormant.
- The word "calm" is structural: at rest a device shows 3 columns, ≤4 cards,
  short labels, generous spacing; complexity appears only in disclosures/menus.
- Summaries everywhere (sidebar row subtitle, column subtitles) keep counts
  visible without inspecting the graph.
- Everything reacts live (meters at 60 fps impression, toggles instant).
- Window resizes gracefully: columns keep left anchors, canvas scrolls
  vertically only; nothing reflows into overlap (`25-recover.png` shows the
  same layout in a small window with a vertical scrollbar).
