# Loopwire Component Inventory

Every component needed to rebuild the reference UX, with props/states/behavior.
Names are proposals for `apps/desktop/src/lib/` Svelte 5 components. Visual
values live in `visual-system.md`; flows in `vnc-ux-spec.md`.

## Layout shells

### `AppShell`
- Slots: `sidebar`, `canvas`, `footer`.
- Grid: `265px 1fr` columns; footer row pinned; canvas cell `overflow-y: auto`.
- Handles empty-device-list state (renders `EmptyState` in canvas).

### `Sidebar`
- Props: `devices: DeviceSummary[]`, `selectedId`, callbacks.
- Children: `SidebarHeader`, `DeviceRow*`, `SidebarFooter`.
- Keyboard: listbox semantics, ↑/↓ moves selection.

### `SidebarFooter`
- `+ New Virtual Device` (text+plus icon button, left), `–` remove
  (icon button, right; disabled when no device selected).
- Remove is instant; show undo toast (loopwire divergence, see spec §3.9).

### `CanvasFooter`
- `Delete` button: `disabled` unless canvas selection exists; trash glyph.
- `MonitorsVisibilityButton`: eye / eye-slash + label `Hide Monitors` /
  `Show Monitors`.

## Sidebar pieces

### `DeviceRow`
- Props: `name`, `enabled`, `muted`, `volume`, `sources: {icon,label}[]`,
  `level` (nullable), `selected`.
- States: default, selected (accent tint), device-off (dim content).
- Contains: `TogglePill`, `SourceIconStrip`, `MiniMeter` (auto-hides at
  silence), `MuteButton`, `VolumeSlider`.
- Click anywhere non-control selects device.

## Canvas pieces

### `DeviceTitle`
- Static: h1 + pencil `IconButton`.
- Editing: `RenameField` — full-width text input, accent ring, select-all on
  entry; Enter/blur commits, Esc reverts. Also auto-entered right after device
  creation.

### `ColumnHeader`
- Props: `title`, `subtitle`, `addAction: 'menu' | 'instant' | 'none'`.
- Subtitle patterns: Sources → "1 App, 1 Device, Pass-Thru";
  Output Channels → "4 Channels"; Monitors → "1 Device".
- `AddButton` (circled plus, optional chevron) anchors `AddSourceMenu` /
  `AddMonitorMenu` or fires add-bus instantly.

### `SourceCard`
- Props: `title`, `icon`, `enabled`, `selected`, `channels: Channel[]`,
  `options: SourceOptions`, `optionsExpanded`.
- Channel: `{ index, label /* "1 (L)" | "3" */, level, portId }`.
- Regions: header (`TogglePill`), body (icon 40pt + `ChannelRow*`),
  `OptionsDisclosure`.
- States: on, off (cables gray — cable layer reads card state), selected
  (accent border), options expanded/collapsed.
- Variants: app source (real icon, options = MuteWhenCapturing + volume),
  hardware source (glyph icon, options = volume; mono → 1 row),
  pass-thru source (own glyph, channel count follows bus count).

### `BusBlock` ("Channels 1 & 2")
- Props: `title`, `channels: {label, level, inPortId, outPortId}[]`, `selected`.
- Header without toggle. Ports on both edges.
- Selectable/deletable like cards.

### `MonitorCard`
- Mirror of `SourceCard`: ports left, meter, right-aligned labels; options =
  volume slider **bound to host device volume**; toggle in header.

### `PortDot`
- Props: `direction: 'in'|'out'`, `active`, `cardEdge`.
- Ø7pt circle; exposes anchor position to the cable layer; drag handle for
  cable creation (pointer events, see `CableLayer`).

### `CableLayer`
- One SVG absolutely positioned under cards, spanning the canvas scroll area.
- Renders `Cable[]`: `{ id, fromPort, toPort, state: 'live'|'dimmed'|'selected' }`.
- Path: horizontal-tangent cubic bezier; recompute on layout/scroll/resize
  (ResizeObserver + measured port anchors).
- Interactions: click near path (≤6pt hit slop) selects; drag from `PortDot`
  draws a provisional cable, drop on compatible port creates route; Delete
  removes selected. (Interaction not verified on reference — implement per
  spec §3.11.)

### `EmptyState`
- Brand glyph 56pt + instruction line with bold action name.
- Variants: no-devices (canvas-wide). (Monitors-empty shows nothing — keep.)

## Controls (shared)

### `TogglePill`
- Props: `on`, `disabled`, `label /* On|Off */`.
- On: outline accent, label-left, knob-right. Off: red fill, label-right,
  knob-left. Role=switch, text is part of the control.

### `VolumeSlider`
- Props: `value 0–100`, `showReadout`, `compact`.
- Accent fill left of knob; readout right, fixed-width digits.
- Keyboard ±1, PgUp/PgDn ±10.

### `Meter`
- Props: `level 0–1`, `size: 'card'|'bus'|'mini'`.
- Smooth decay; renders track when silent; `role=meter`.

### `MuteButton`
- Icon-button speaker / speaker-slash(red). `aria-pressed`.

### `IconButton`
- Bare glyph button: pencil, trash, plus, minus, eye, chevron.

### `Checkbox`
- Accent square + label ("Mute when capturing").

### `OptionsDisclosure`
- Chevron + "Options"; expands in place, pushes card height.

### `PopupMenu`
- Sections with dim headers + separators; items `{icon,label,disabled}`;
  filters out already-added ids; first-item pinned action
  ("Select Application…"). Esc closes; type-ahead.
- Used by `AddSourceMenu` (Applications pinned action / Running Applications /
  System Sources / Capture Devices) and `AddMonitorMenu` (Playback Devices).
  Group names use loopwire/PipeWire vocabulary, not the reference's copy.

### `Button`
- Footer-style small filled button, optional glyph, `disabled` at 40% opacity.

## Windows

### `SettingsWindow`
- Sections: Appearance (`ThemePicker`: Match System / Light / Dark preview
  tiles, radio semantics) + Updates (checkbox + explanatory caption + button).
- Small fixed window (~430×330pt), opened with ⌘,/Ctrl+,.

## State containers (non-visual)

- `deviceStore`: devices, selection, per-device graph (sources, buses,
  monitors, routes) — maps to `LoopwireConfiguration`/`AudioEndpoint`/
  `AudioRoute` in `@loopwire/core`.
- `levelStore`: per-port levels streamed from audio host; throttled to
  animation frames.
- `uiStore`: canvas selection, monitors-hidden, options-expansion, rename
  editing, toasts.

## Prop/state matrix quick reference

| Component     | default | hover* | selected | disabled/off | active/audio | empty |
|---------------|---------|--------|----------|--------------|--------------|-------|
| DeviceRow     | ✓       | design | tint     | dim + red mute| mini-meter  | –     |
| SourceCard    | ✓       | design | border   | red pill, gray cables | meters | – |
| BusBlock      | ✓       | design | border   | –            | meters       | –     |
| MonitorCard   | ✓       | design | border   | red pill     | meters       | –     |
| Cable         | accent  | design | thicker  | gray         | =live        | –     |
| TogglePill    | on      | design | –        | off=red      | –            | –     |
| Delete button | dim     | design | –        | enabled on selection | –    | –     |
| Canvas        | graph   | –      | –        | –            | –            | glyph+hint |

*hover/focus states were not capturable over VNC; design them consistently
(lighten glyphs, ring on focus) rather than inventing per-component looks.
