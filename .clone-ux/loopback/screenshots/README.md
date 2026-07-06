# Screenshot evidence index

Captured over `agent-vnc headless vnc:macbook-1` (3456×2234 @2x). All states
were created and then fully reverted; the target ended in its original empty
state (`35`). A macOS "screen is being controlled" banner overlays the top of
many shots — ignore it, it is not part of the app.

| File | Proves |
|------|--------|
| 00-initial.png | Empty state: sidebar + centered glyph/instruction; `+ New Virtual Device` footer |
| 01-new-device.png | Device creation: default graph (Pass-Thru → Channels 1&2, auto-cabled), name field auto-editing, sidebar row appears |
| 02-renamed.png | Committed title row w/ pencil icon; straight cables at equal row heights |
| 03-sources-menu.png | Sources ⊕ menu grouping: Select Application… / Running Applications / Special Sources / Audio Devices |
| 04-source-iterm.png | App source added: auto-selected (accent border), auto-cabled 1→1 2→2, sidebar summary updates |
| 05-source-mic.png | (miss) menu closed without adding — click coords shifted between openings |
| 06-sources-menu-2.png | Reopened menu: already-added app (iTerm) removed from list |
| 07-source-mic.png | Mono hardware source: single "1 (L)" row, live meter activity, sidebar mini-meter + icon strip |
| 08-monitors-menu.png | Monitors ⊕ menu: Audio Devices group (playback devices) |
| 09-monitor-speakers.png | Monitor card added: mirrored layout (ports left), Monitors "1 Device" summary |
| 10-source-options.png | App source Options expanded: "Mute when capturing" + volume 100%; card ordering (alpha, Pass-Thru last) |
| 11-monitor-options.png | Monitor Options: volume slider reflecting real device volume (12%) |
| 12-add-channels.png | Output Channels ⊕: "Channels 3 & 4" block, Pass-Thru grows to 4ch auto-cabled, cable fan-out geometry |
| 13-wire-selected.png | Cable click: ambiguous selection visual (uncertainty documented) |
| 14-wire-deleted.png | Delete key on cable: no removal (interaction unverified over VNC) |
| 15-after-drag-timeout.png | Port drag attempt timed out with no state change (graph intact) |
| 16-passthru-off.png | Source Off state: red "Off" pill, that card's cables desaturate gray, others stay accent |
| 17-context-menu.png | Right-click on card: no context menu exists |
| 18-sidebar-mute.png | Device mute: sidebar speaker icon red/muted state |
| 19-hide-monitors.png | Hide Monitors: column 3 collapsed, header becomes "Output Channels / 4 Channels", button → "Show Monitors" |
| 20-preferences.png | Settings window: Appearance (Match System/Light/Dark) + Software Update |
| 21-menubar.png | Menu bar reveal: App/Edit/Window/Help only; window traffic lights |
| 22-menu-loopback.png | App menu contents incl. Settings… ⌘, License…, Permissions… |
| 23-menu-edit.png | (miss) Edit menu did not open |
| 24-rename-edit.png | (detour) app hidden, desktop visible — no app info |
| 25-recover.png | Windowed (non-fullscreen) layout: same 3 columns compressed + vertical scrollbar → resize behavior |
| 26-rename-mode.png | Window restored to full size (pre-rename) |
| 27-rename-mode.png | Rename mode: full-width field, accent focus ring, select-all |
| 28-renamed.png | Rename committed ("Demo Mix") in title + sidebar |
| 29-source-removed.png | Card selection state + footer Delete enabled with canvas selection |
| 30-source-delete.png | Source deleted instantly (no dialog); graph/summaries reflow; Delete disabled again |
| 31-two-devices.png | Two devices in sidebar; new device default graph; second row styling |
| 32-select-first.png | Sidebar selection: accent row tint, canvas swaps to selected device |
| 33-delete-confirm.png | Sidebar selection does NOT enable footer Delete (canvas-scoped) |
| 34-device-delete-confirm.png | Sidebar "–" deletes device instantly, no confirmation |
| 35-restored-empty.png | Target restored to original empty state (cleanup proof) |
