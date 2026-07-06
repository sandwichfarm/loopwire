# One-shot prompt: rebuild the loopwire desktop UI

Copy everything below the line into the implementing agent's prompt.

---

You are rebuilding the desktop UI of **loopwire** (Linux virtual audio routing,
Svelte 5 + Tauri 2 + WebKitGTK, pnpm monorepo at repo root). The current UI —
a single 4,613-line `apps/desktop/src/App.svelte` with stacked toggle panels —
is cluttered and broken. Replace it with the sidebar + patch-bay UX specified
in the clean-room reference package at `.clone-ux/loopback/`. The target
quality bar is world-class native-app polish: calm density, one accent hue,
precise spacing, live feedback, zero modal friction.

## Read first, in this order (do not skip)

1. `AGENTS.md` (repo root) — architecture contract; it overrides everything.
2. `.clone-ux/loopback/vnc-ux-spec.md` — flows, interaction model, state model.
3. `.clone-ux/loopback/visual-system.md` — measurements, colors, type, spacing,
   cables, controls. Implement these values as CSS custom properties.
4. `.clone-ux/loopback/component-inventory.md` — the component tree, props,
   states. Use these names under `apps/desktop/src/lib/`.
5. `.clone-ux/loopback/implementation-plan.md` — phase order and verify steps.
   Execute phases 0→7 in order; commit per phase.
6. `.clone-ux/loopback/screenshots/README.md` — visual ground truth. When a
   layout decision is ambiguous, match the referenced screenshot's structure.

## What to build (summary — the docs are authoritative)

- `AppShell`: fixed 265pt device sidebar · scrollable canvas · pinned footer.
- Sidebar: device rows (name, On/Off pill, source summary + icon strip, mute +
  volume + %, live mini-meter), `+ New Virtual Device`, `–` remove (undo toast).
- Canvas per selected device: title + rename (auto-edit on create), three
  columns — **Sources / Output Channels / Monitors** — with header summaries
  and ⊕ actions (grouped popup menus for sources/monitors; instant bus add).
- Cards: 200pt wide, 7pt radius; source cards (ports right), bus blocks (ports
  both edges), monitor cards (mirrored, ports left); On/Off pills; expandable
  Options strips (app sources: mute-when-capturing + volume; monitors: volume
  bound to the real device).
- `CableLayer`: SVG bezier cables under cards; auto-cable on add (1→1, 2→2);
  drag port→port creates a route, click selects, Delete/footer-Delete removes;
  cables desaturate when an endpoint card is Off.
- Footer: `Delete` (enabled only with canvas selection) · `Hide/Show Monitors`
  (collapses column 3, header becomes "Output Channels / N Channels").
- Empty state: centered glyph + "Create your first virtual audio device…".
- Settings window (Ctrl+,): Appearance (Match System/Light/Dark) + Updates +
  the startup/restore/backend cards evicted from the current sidebar.

## Hard constraints

- **Clean room**: no reference brand assets, glyphs, or copy. Default device
  name is "Loopwire Device N". Draw/choose your own icons (no new deps unless
  justified per AGENTS.md — prefer inline SVG).
- **Architecture**: UI components never call backend adapters; go through the
  stores/application services. Domain state uses `@loopwire/core` types
  (`LoopwireConfiguration`, `AudioEndpoint` role `input|output|monitor`,
  `AudioRoute`). If output-channel buses need a domain entity, add it to
  `packages/core` with tests and a versioned persistence migration.
- **No fake success**: meters show silence when no level data exists; apply
  failures roll back optimistic UI with a typed-error toast. Never simulate
  host-owned audio state.
- **Divergences already decided** (do not copy the reference here): undo
  toasts instead of confirmation-free silent deletes; loopwire-designed
  hover/focus/motion per visual-system §11; loopwire-designed error surfaces.
- Single accent hue for everything live/selected/interactive; red only for
  Off/mute/destructive. Both themes via tokens; respect
  `prefers-reduced-motion`; full keyboard reachability and ARIA roles per
  vnc-ux-spec §6.
- Prefer deletion over compatibility shims: by the end, `App.svelte` is a thin
  shell mount (<200 lines) and dead panels/styles are gone.
- Update docs (README, `apps/docs`) in the same change that changes behavior.

## Verify before claiming done

1. `pnpm --filter @loopwire/desktop typecheck && pnpm --filter @loopwire/desktop test`
   after every phase; `pnpm check` at the end.
2. Launch the real app (`pnpm --filter @loopwire/desktop tauri:dev` or the
   repo's `verify:desktop-preview` / `verify:desktop-binary-launch` scripts)
   and screenshot: empty state, one device with 2 sources + monitor + expanded
   options, source Off, hide-monitors, rename mode, two devices, settings —
   compare each against the matching file in `.clone-ux/loopback/screenshots/`
   (structure/hierarchy/spacing parity, not pixel-identical branding).
3. Exercise add→cable→remove against a real PipeWire session where available
   (`pnpm detect:audio`); document capability gaps honestly if a backend
   surface (e.g. per-port level streaming) does not exist yet — render honest
   silence, and note it in the PR.
4. Keyboard-only walkthrough + both themes + a narrow-window resize (canvas
   scrolls vertically only; nothing overlaps).

Report at the end: files changed, phases completed, verification output,
screenshot comparisons, and any spec items intentionally deferred with reasons.
