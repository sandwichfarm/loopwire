# Loopwire Visual System (measured from Loopback reference)

All measurements taken from 2× Retina screenshots (3456×2234 px) and quoted in
**logical pt** (px ÷ 2). Treat values as ±2 pt estimates; colors are sampled
approximations, not extracted constants. Where a value could not be measured,
it says so. Use loopwire's own brand assets — never the reference's glyphs.

## 1. Window structure

| Region              | Size / position                                        |
|---------------------|--------------------------------------------------------|
| Sidebar             | fixed width ≈ **265 pt**, full height, left            |
| Sidebar header row  | height ≈ **38 pt**, hairline divider below             |
| Canvas              | remainder; content top-padding ≈ 20 pt                 |
| Canvas footer bar   | height ≈ **40 pt**, hairline divider above             |
| Canvas columns      | 3 equal-feel columns; card left edges at ≈ 285 pt, 898 pt, 1511 pt on a 1728 pt window; column content width **200 pt** |

Resize behavior: sidebar fixed; columns keep order and left-anchor rhythm;
canvas scrolls **vertically only** (scrollbar overlays right edge of canvas,
inside the footer-bar bounds); footer stays pinned. Minimum usable width fits
all three columns; no horizontal scroll observed.

## 2. Color roles (dark theme sampled; app also ships Light + Match System)

| Role                        | Approx value        |
|-----------------------------|---------------------|
| Canvas background           | `#1B1D1E`           |
| Sidebar background          | `#242729`           |
| Card body                   | `#2A2D2F`           |
| Card header bar / bus header| `#3F4446`           |
| Options strip (card footer) | `#232628`           |
| Hairline borders/dividers   | `#000` at ~20–30% α |
| Primary text                | `#F2F3F3`           |
| Secondary text (subtitles)  | `#9CA1A3`           |
| Disabled/section headers in menus | `#8A8F91`     |
| **Accent (single hue)**     | teal ≈ `#45C4C0`    |
| Accent fill on meters/wires | same teal, track `#4A4F52` |
| Destructive / Off state     | red ≈ `#E5484D`     |
| Selection row tint (sidebar)| teal at ~25–35% α over row |
| Menu/popup background       | `#2E3133` + shadow  |

Rules:
- **One accent hue** carries: live meters, cables, selection borders, sidebar
  selection, focus rings, slider fills, On-pill outline+label. Nothing else is
  colored except the red Off/mute/destructive accents and real app icons.
- Disabled/dormant = desaturate to grays, never change layout.
- Light theme not captured (system was dark) — derive by inverting neutrals,
  keeping the same accent.

## 3. Typography (system UI font; loopwire: system stack / Inter)

| Use                          | Size / weight (est.)      |
|------------------------------|---------------------------|
| Canvas device title          | 17–18 pt bold             |
| Sidebar header "Devices"     | 13 pt bold                |
| Column headers               | 13 pt semibold            |
| Column subtitles / summaries | 11 pt regular, secondary  |
| Card header title            | 12 pt semibold            |
| Channel labels, options text | 11 pt regular             |
| Toggle pill label (On/Off)   | 9–10 pt semibold          |
| Volume % readout             | 11 pt regular             |
| Empty-state instruction      | 13 pt regular, bold spans |

Text truncates with ellipsis mid-card-header ("MacBook Pro Micr…"); titles
never wrap.

## 4. Spacing scale

Observed rhythm ≈ 4/8/12/16/20:
- Card internal padding: 10–12 pt; header bar padding-x 10 pt.
- Vertical gap between cards in a column: **16 pt**.
- Channel rows: height ≈ **20 pt**, 4 pt gap.
- Column header → first card: ≈ 40 pt.
- Sidebar row padding: 12 pt x, 10 pt y; elements inside on an 8 pt grid.
- Footer bar buttons inset 12 pt from edges.

## 5. Cards, blocks, rows

**Source / monitor card** (`04-source-iterm.png`, `09-monitor-speakers.png`)
- Width 200 pt; auto height = header 26 pt + body (icon + N channel rows) +
  options strip 24 pt.
- Corner radius ≈ **7 pt**; 1 px hairline border (darker); subtle drop shadow
  (y≈1–2 pt, blur≈4–6 pt, ~35% black) lifting card off canvas.
- Header bar: title left, toggle pill right; slightly lighter than body.
- Body: 40 pt icon left (app icon, or neutral circle glyph for devices);
  channel rows right of icon: right-aligned label "1 (L)" → meter → port dot
  on the card's right edge.
- Monitor card is the **mirror**: port dots on left edge, then meter, then
  label right-aligned to card's right; options below.
- Options strip: chevron `>`/`v` + "Options"; expanding pushes card taller,
  content indented, never overlays.

**Channel-bus block** ("Channels 1 & 2") (`12-add-channels.png`)
- Same width/radius/shadow; header is title-only (no toggle).
- Rows: input port (left edge) → "Channel 1 (L)" → meter → output port (right
  edge). Ports on both edges since it bridges both cable stages.

**Sidebar device row** (`28-renamed.png`, `18-sidebar-mute.png`)
- Name (bold 13 pt) + toggle pill right-aligned.
- Second line: up-to-~3 small (16 pt) source icons + comma-joined source names
  (secondary color, wraps to 2 lines max).
- Live mini-meter: small rounded bar, top-right under the pill, only visible
  with signal.
- Third line: mute speaker icon-button (red when muted) + slider + "100%".
- Selected row: full-row accent tint block (no rounded inset observed).

## 6. Controls

**Toggle pill** — capsule ≈ 43×18 pt. On: dark capsule, teal 1 px outline,
teal "On" text left, white knob right. Off: red capsule fill, white "Off" text
right, white knob left. Instant flip, no intermediate animation observed.

**Slider** — 3 pt track, radius full; filled left segment accent, rest
`#4A4F52`; knob white circle Ø 11 pt; numeric % readout right (fixed width so
digits don't shift layout).

**Meter** — rounded-rect track ≈ 74×6 pt (cards) / 80×6 pt (bus). Fill grows
left→right in accent; dormant = track only. Sidebar mini-meter ≈ 40×5 pt.
Update feel: continuous, ~30–60 fps, decay smoothing (exact ballistics not
measurable over VNC — implement peak-hold-free smooth decay).

**Icon buttons** — bare glyphs (pencil, speaker, ⊕, ⊖) at 14–16 pt, secondary
color, accentless until hover (hover not capturable over VNC — design one:
lighten to primary).

**⊕ add buttons** — 16 pt circled-plus next to column headers; the Sources and
Monitors ones open menus (with a tiny chevron beside), the Output Channels one
acts immediately.

**Footer buttons** — small rounded-rect (radius 6 pt, height 24 pt) filled
`#3A3E40`; `Delete` has trash glyph and is disabled (40% opacity) without a
canvas selection. `Hide/Show Monitors` has eye/eye-slash glyph, right-aligned.

**Popup menu** (`03-sources-menu.png`) — radius 8 pt, dark panel with strong
shadow; item height ≈ 22 pt; 16 pt icons; section headers in dimmed text with
hairline separators; first item can carry a persistent accent-highlighted
state; items remove themselves once added.

**Text field (rename)** (`27-rename-mode.png`) — full-canvas-width, height
≈ 30 pt, radius 6 pt, accent 2 pt ring, selected text in accent highlight.

**Checkbox** — 14 pt rounded-square, accent fill + white check when on.

## 7. Cables & ports

- Port: Ø ≈ 7 pt circle, track-gray fill, accent ring when its cable is live.
- Cable: 2 pt stroke, accent; **cubic-bezier S-curve** — leaves the port
  horizontally, control points ≈ 40% of horizontal distance; parallel cables
  offset a few pt and never merge (`12-add-channels.png` shows 8 cables
  fanning cleanly).
- Dimmed cable (card Off): same geometry, gray `#6A7072` (`16-passthru-off.png`).
- Straight-line case: when source row and bus row are at the same y, the cable
  is drawn straight (`02-renamed.png`).
- Layering: cables render **under** cards.

## 8. Selection & focus

- Canvas card selected: 2 pt accent border wrapping the whole card
  (`29-source-removed.png`) — border sits outside the card hairline, radius
  follows card.
- Newly added items are auto-selected.
- Sidebar selection: row tint (independent of canvas selection).
- Rename field: accent ring (§6).
- Cable selection visual: uncertain (see spec §3.11) — proposed: brighten +
  thicken to 3 pt.

## 9. Icon style

- Real app icons for app sources (loopwire: desktop-file icons from the host).
- Neutral filled-circle glyphs for hardware (mic glyph, speaker glyph) in
  gray — 40 pt in cards, 16 pt in sidebar/menus.
- UI glyphs are thin-stroke template icons (pencil, trash, eye, plus, speaker).
- Loopwire must draw its own glyph set (or use an open set like Lucide) — do
  not copy the reference's Pass-Thru brand mark; loopwire's Pass-Thru glyph
  should be its own loop/wire motif.

## 10. Elevation & effects

- Cards: soft shadow (see §5) + hairline; menus/popovers: bigger shadow
  (blur ≈ 24 pt) + 1 px light inner border; Settings window is a separate
  small window with standard chrome.
- No blur/vibrancy inside the main window (flat panels).
- Empty state: centered 56 pt brand glyph + 2-line instruction, bold command
  name (`00-initial.png`).

## 11. Motion (mostly unverifiable over VNC — design intent)

- State flips (toggles, selection, meter colors): instant (<100 ms).
- Options disclosure: fast expand, ~150 ms ease-out.
- Column collapse (Hide Monitors) re-layout: appears immediate in captures;
  loopwire: 200 ms ease-in-out re-flow, cables re-drawing along.
- Menus: native-instant.
- Under `prefers-reduced-motion`: everything instant.

## 12. Density summary

At rest, a two-source device shows ~12 interactive elements total. Nothing
scrolls horizontally. One accent color. Card widths and column x-anchors are
constant regardless of content, so the eye can scan columns. This restraint is
the core of the reference's quality — treat every addition beyond this
inventory as scope to justify.
