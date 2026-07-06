# Loopwire UI Rebuild Plan

Goal: replace the current single-page `apps/desktop/src/App.svelte` (4,613
lines, panel-toggle layout) with the sidebar + patch-bay canvas UX specified in
`vnc-ux-spec.md` / `visual-system.md` / `component-inventory.md`.

Stack reality (verified): Svelte 5.56 + Vite 8 + Tauri 2 (WebKitGTK), pnpm
workspace; domain types in `packages/core/src/types.ts`
(`LoopwireConfiguration`, `AudioEndpoint` role `input|output|monitor`,
`AudioRoute`); backends in `packages/audio-host` (PipeWire reference adapter,
JACK, DSP). Tests via vitest; `pnpm typecheck` = svelte-check. Per AGENTS.md:
no backend calls from components, no new dependencies without justification,
docs updated with behavior.

Each phase is independently shippable and reviewable. Keep PRs per phase.

## Phase 0 — Scaffolding & tokens (no behavior change)
1. Create `apps/desktop/src/lib/` with `tokens.css` (CSS custom properties from
   visual-system §2–§4: colors, type scale, spacing, radii, shadows; dark theme
   first, `@media (prefers-color-scheme)` + explicit `data-theme` override).
2. Add `stores/` (`deviceStore.ts`, `uiStore.ts`, `levelStore.ts`) that wrap
   the existing App.svelte state logic — pure TS, vitest-covered, using
   `@loopwire/core` types. No UI change yet.
3. Verify: `pnpm --filter @loopwire/desktop typecheck && test`.

## Phase 1 — Shell + sidebar
1. `AppShell` grid (265px sidebar / canvas / pinned footer),
   replacing App.svelte's `.workspace` layout.
2. `Sidebar` + `DeviceRow` + `SidebarFooter` per component-inventory. Map
   "configurations" list (current sidebar) → device rows: name, enable toggle,
   source summary line, volume/mute. Device create/remove wired to existing
   configuration actions; removal gets an undo toast (5s) instead of the
   reference's silent delete.
3. `EmptyState` for zero devices.
4. Migrate the current "boot/startup/restore" sidebar cards OUT of the sidebar
   into the Settings window (Phase 6) — the sidebar must contain only devices.
5. Verify: launch via `pnpm --filter @loopwire/desktop tauri:dev` (or
   `verify:desktop-preview`), screenshot vs `35-restored-empty.png` and
   `31-two-devices.png` structure.

## Phase 2 — Canvas columns & cards (static graph rendering)
1. `DeviceTitle` (+ rename flow incl. auto-edit on create).
2. `ColumnHeader` ×3 with live summaries; `SourceCard`, `BusBlock`,
   `MonitorCard`, `OptionsDisclosure`, `TogglePill`, `VolumeSlider`,
   `Checkbox`, `Meter` (static level 0 for now).
3. Render the selected device's endpoints/routes from `deviceStore`:
   `input` endpoints → column 1, channel buses → column 2, `monitor`
   endpoints → column 3. Bus concept: if `@loopwire/core` lacks an explicit
   bus entity, add `ChannelBus` to `packages/core` (id, index range, labels)
   with tests + migration for `PersistedStateV1`.
4. Column layout constraints per visual-system §1; vertical-only scroll.
5. Verify: typecheck/tests + visual diff against `12-add-channels.png`
   composition (structure, spacing, alignment).

## Phase 3 — Cable layer
1. `PortDot` anchor registration (bind element refs → measured centers,
   ResizeObserver + scroll listener).
2. `CableLayer` SVG under cards: bezier paths per visual-system §7; states
   live/dimmed (endpoint disabled) — derive from store, no local state.
3. Route mutations: drag port→port creates `AudioRoute` (provisional dashed
   cable while dragging, snap on compatible port, reject with shake/no-op on
   incompatible); click-cable select; Delete key + footer Delete remove.
4. Reduced-motion: skip provisional animations.
5. Verify: vitest for route-geometry helpers; manual drag/create/delete in
   `tauri:dev`; confirm rollback path when the routing engine rejects apply.

## Phase 4 — Add menus & graph editing
1. `PopupMenu` + `AddSourceMenu`/`AddMonitorMenu` grouped per spec §3.3/§3.5,
   sourced from `@loopwire/audio-host` enumeration (apps via PipeWire streams,
   capture/playback devices, system buckets). Filter already-added; pinned
   "Select Application…" only if a picker is feasible on Linux — otherwise
   omit (do not fake).
2. Add-source/monitor/bus actions with auto-cable + auto-select behavior
   (spec §3.3–§3.5); alphabetical source ordering, Pass-Thru pinned last.
3. Canvas selection model in `uiStore` (single selection; sidebar and canvas
   selections independent); footer `Delete` enablement.
4. `Hide/Show Monitors` collapse with header swap (spec §3.10).
5. Verify: end-to-end add→wire→remove on a real PipeWire session
   (`pnpm detect:audio`, `verify:runtime`); no UI-only success states.

## Phase 5 — Live audio feedback
1. `levelStore`: subscribe to per-port levels from audio-host (add a level
   stream to the PipeWire adapter if missing — backend work item; document
   capability gaps for JACK/others per architecture contract).
2. Wire `Meter` everywhere (cards, buses, monitors, sidebar mini-meter) with
   rAF-throttled smooth decay.
3. Device/source/monitor enable, mute, volume bound to engine with optimistic
   UI + typed-error rollback toasts.
4. Monitor volume binds to real device volume (both directions).
5. Verify: play test audio (`jack:verify` / dsp plan scripts), observe meters;
   kill backend mid-session → UI shows diagnostic, not fake state.

## Phase 6 — Settings window & chrome
1. `SettingsWindow` (Tauri secondary window or modal on WebKitGTK constraints —
   prefer real window; fall back documented): Appearance (Match System/Light/
   Dark) + Updates + relocated startup/restore/backend cards from Phase 1.4.
2. Keyboard map: Ctrl+, settings; Enter/Esc in rename; Delete on selection;
   full tab order per spec §6 a11y expectations.
3. Light theme pass using tokens; verify both themes.
4. Verify: `verify:desktop-binary-launch`, screenshots both themes.

## Phase 7 — Deletion of legacy UI & polish
1. Remove dead panels/styles from App.svelte until it is only the shell mount
   (<200 lines); delete unused CSS. Prefer deletion over shims (AGENTS.md).
2. Polish pass against visual-system §12 checklist: single accent audit,
   spacing audit at 1×/2× scale factors, truncation, focus rings,
   reduced-motion, keyboard-only walkthrough.
3. Docs: update README + `apps/docs` UI section in the same change.
4. Final verify: `pnpm check` (verify + lint + typecheck + test + build), plus
   manual parity review against the screenshot set in
   `.clone-ux/loopback/screenshots/` (compare states 00→35).

## Explicit non-goals / divergences (decided, do not re-litigate silently)
- No confirmation-free destructive deletes: loopwire uses undo toasts.
- No cloning of reference brand glyphs, app copy, or the "Loopback Audio"
  default name; default device name: "Loopwire Device N".
- Error/diagnostic surfaces are loopwire-designed (reference showed none).
- Hover/animation specifics are loopwire-designed within visual-system §11.

## Open questions for the implementing agent
1. Does `@loopwire/core` need `ChannelBus` (Phase 2.3) or can output channels
   derive from `LoopwireConfiguration` channel counts? Decide with tests.
2. Per-port level streaming support in the PipeWire adapter — scope it before
   Phase 5; if large, split into its own backend phase.
3. WebKitGTK secondary-window support for Settings — spike early (Phase 0/1)
   since commit history shows WebKitGTK launch-path sensitivity.
