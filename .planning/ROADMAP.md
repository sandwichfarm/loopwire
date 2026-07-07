# Roadmap: Loopwire

## Milestones

- [x] **v0.1: Walking Skeleton and Product Contract** - 7 phases, 26 requirements
- [ ] **v0.2: Production Audio Routing** - 5 phases, 8 requirements

---

## Active Milestone: v0.2 Production Audio Routing

**Goal:** Close the gap between a verified foundation and a real production-grade Linux virtual audio router.

**Branch:** `master` until the first remote/default branch policy is established.

**Hard constraints:**
- Keep host audio mutation guarded, explicit, verifiable, and reversible.
- Do not claim public release availability until published artifacts are installed from the release surface.
- Do not run live audio mutation during automated validation.
- Keep docs current about unsupported backend gaps.

## v0.2 Phases

- [x] **Phase 8: Physical Monitor Device Binding** — persist monitor target sink names and route monitor loopbacks to
  physical host sinks when configured.
- [x] **Phase 9: Native PipeWire Graph Adapter** — implement native PipeWire link apply, verify, rollback, and
  diagnostics for existing graph ports.
- [x] **Phase 10: Live Apply Consent and Runtime Wiring** — connect desktop backend selection to guarded host adapters.
- [x] **Phase 11: True Per-Edge Matrix Semantics** — represent and verify per-edge routing beyond stream-level controls.
- [ ] **Phase 12: Published Release and VM Proof** — prove install, launch, docs, and backend behavior from real
  release and VM surfaces.

## Phase Details

### Phase 8: Physical Monitor Device Binding
**Goal:** Monitors can target physical host sinks while preserving Loopwire-owned fallback monitor sinks.
**Depends on:** Phase 2
**Requirements:** ROUTE-01
**Success Criteria:**
  1. Monitor endpoints persist an optional physical host sink name.
  2. Desktop users can edit monitor target sink names.
  3. The pactl adapter links monitor loopbacks directly to physical sink names when configured.
  4. Verification fails when a configured physical monitor target sink is unavailable.
  5. Rollback/unload removes Loopwire-owned loopbacks without unloading physical sinks.
**Plans:** 1 plan
  - [x] 08-01-PLAN.md — monitor endpoint device names, UI editing, pactl physical target loopbacks, and verification
**UI hint:** yes

### Phase 9: Native PipeWire Graph Adapter
**Goal:** PipeWire stops being detection-only and becomes a real routing backend.
**Depends on:** Phase 8
**Requirements:** ROUTE-04
**Success Criteria:**
  1. PipeWire adapter can connect configured routes between existing graph ports through a guarded command boundary.
  2. Adapter verifies expected graph links.
  3. Adapter unlinks only configured graph links.
  4. Adapter rolls back created links on partial failure.
  5. Unsupported virtual-node creation, monitor routing, and gain/mute controls are explicit gaps.
**Plans:** 1 plan
  - [x] 09-01-PLAN.md — guarded `pw-link` existing-port routing, verification, unload, and rollback
**UI hint:** no

### Phase 10: Live Apply Consent and Runtime Wiring
**Goal:** The desktop can use real host adapters through explicit user consent and visible rollback state.
**Depends on:** Phase 9
**Requirements:** ROUTE-02, ROUTE-03
**Success Criteria:**
  1. User must explicitly opt into live backend apply.
  2. Backend selection routes runtime operations to the selected host adapter.
  3. Failure states show what changed, what rolled back, and what remains untouched.
  4. Startup restore can verify without mutating when consent has not been granted.
**Plans:** 1 plan
  - [x] 10-01-PLAN.md — host-apply consent, selected backend adapter routing, and Tauri audio command bridge
**UI hint:** yes

### Phase 11: True Per-Edge Matrix Semantics
**Goal:** Loopwire can model per-edge gain/mute when one source routes to multiple outputs.
**Depends on:** Phase 10
**Requirements:** ROUTE-05
**Success Criteria:**
  1. Core route model distinguishes stream-level controls from graph-edge controls.
  2. Backends report whether they support true per-edge controls.
  3. UI communicates degraded stream-level behavior when a backend cannot support per-edge routing.
  4. Tests cover one-source-to-multiple-output routing semantics.
**Plans:** 1 plan
  - [x] 11-01-PLAN.md — backend mixing semantics, desktop degraded-control messaging, and split-source regression
**UI hint:** yes

### Phase 12: Published Release and VM Proof
**Goal:** Release claims are proven from published artifacts and real Linux compatibility evidence.
**Depends on:** Phase 11
**Requirements:** SHIP-01, SHIP-02, SHIP-03
**Success Criteria:**
  1. A tagged GitHub Release publishes signed artifacts and versioned release notes.
  2. Installer smoke downloads from the published release surface and verifies signatures.
  3. At least one VM target records install, launch, backend detection, and screenshot evidence.
  4. Docs, support matrix, and release notes match the verified artifacts.
**Plans:** 1 plan
  - [x] 12-01-PLAN.md — published-release readiness, evidence collection, VM proof gates, and secret-helper audit
**UI hint:** no

## Completed Milestone: v0.1 Walking Skeleton and Product Contract

**Goal:** Establish the runnable, tested, documented foundation for a Linux virtual audio routing app with world-class UX
as the non-negotiable product bar.

**Branch:** `master` until the first remote/default branch policy is established.

**Hard constraints:**
- Do not copy proprietary Loopback code, assets, name usage, visual styling, or trade dress.
- Do not claim real audio routing until host backend apply/verify/rollback works.
- Do not add package or release claims without install-from-artifact proof.
- Keep domain logic pure and backend-agnostic.
- Keep docs current and explicit about unimplemented areas.

## Phases

- [x] **Phase 1: Walking Skeleton** — create reproducible workspace, core domain semantics, desktop UX shell,
  VitePress site/docs, CI/deploy scaffolding, and validation gates.
- [x] **Phase 2: Backend Capability Layer** — implement real PipeWire detection first, with PulseAudio/JACK/ALSA
  candidate detection and backend contract tests.
- [x] **Phase 3: Configuration Runtime** — implement create/edit/delete configurations, fast unload/apply switching,
  persistence migrations, and startup re-apply.
- [x] **Phase 4: World-Class Desktop UX** — refine the app into a production-grade routing workspace with native/custom
  chrome behavior, accessibility, diagnostics, and visual QA.
- [x] **Phase 5: Linux Install and Startup** — implement curl installer, start-on-boot flow, AUR metadata, Nix flake,
  and package smoke tests.
- [x] **Phase 6: Documentation and Website** — complete VitePress docs/site, screenshot pipeline, support matrix,
  troubleshooting, and release-note workflow.
- [x] **Phase 7: CI/CT/CD and Release Ceremony** — harden CI, add continuous host tests, release workflow, Bunny.net
  deployment, artifact checksums, and post-release smoke tests.

## Phase Details

### Phase 1: Walking Skeleton
**Goal:** A fresh contributor can install dependencies, run tests, build the app shell, build docs, inspect the roadmap,
and see the first product-quality UX direction.
**Depends on:** none
**Requirements:** UX-01, UX-02, UX-03, BACKEND-02, BACKEND-03, CONFIG-02, CONFIG-03, CONFIG-04, DOCS-01, DOCS-02,
QUAL-01, QUAL-02, QUAL-04, QUAL-05
**Success Criteria:**
  1. pnpm workspace installs from lockfile and has root validation commands.
  2. Pure core package models backend selection, configuration switching, hidden monitors, and persisted active config.
  3. Unit tests cover backend selection, configuration switching, monitor hiding, and persistence fallback.
  4. Desktop UI shell builds and shows configuration switching, backend choice, monitor hiding, and chrome mode.
  5. VitePress docs/site builds and includes above-the-fold product page with screenshot and install guidance.
  6. GitHub workflows exist for CI, continuous host-test entry point, and Bunny.net docs deployment.
  7. Scripts exist for install entry point, host CT diagnostics, and GitHub secret setup.
**Plans:** 1 plan
  - [x] 01-01-PLAN.md — bootstrap workspace, core, UX shell, docs/site, CI/deploy scripts, and validation
**UI hint:** yes

### Phase 2: Backend Capability Layer
**Goal:** Real host backend detection establishes credible support breadth without pretending routing has shipped.
**Depends on:** Phase 1
**Requirements:** BACKEND-01, BACKEND-02, BACKEND-03, BACKEND-04, BACKEND-05
**Success Criteria:**
  1. PipeWire detection reads real host state through stable APIs or isolated command adapters.
  2. PulseAudio, JACK, and ALSA detection produce candidate records with typed capability gaps.
  3. Backend contract tests run against fakes and host diagnostics can be collected safely.
  4. Settings can switch backend selection and persistence stores the choice.
**Plans:** 5 plans
  - [x] 02-01-PLAN.md — read-only PipeWire/PulseAudio/JACK/ALSA capability detection and diagnostics
  - [x] 02-02-PLAN.md — guarded pactl virtual-sink create, verify, unload, and rollback adapter
  - [x] 02-03-PLAN.md — guarded pactl sink-input stream routing and move rollback
  - [x] 02-04-PLAN.md — guarded pactl sink-input volume/mute apply and rollback
  - [x] 02-05-PLAN.md — guarded pactl monitor sink and loopback routing
**UI hint:** yes

### Phase 3: Configuration Runtime
**Goal:** Configuration switching is real application behavior with apply/verify/rollback semantics behind the UI.
**Depends on:** Phase 2
**Requirements:** CONFIG-01, CONFIG-02, CONFIG-03, CONFIG-04
**Success Criteria:**
  1. User can create, edit, duplicate, delete, export, and import configurations.
  2. Selecting a configuration unloads the active plan and applies the selected plan transactionally.
  3. Startup restores the last selected configuration and verifies host state.
  4. Persistence migrations are tested.
**Plans:** 1 plan
  - [x] 03-01-PLAN.md — configuration CRUD, import/export, migrations, runtime transactions, and startup verification
**UI hint:** yes

### Phase 4: World-Class Desktop UX
**Goal:** The desktop app feels like a high-end creative tool instead of a raw Linux control panel.
**Depends on:** Phase 3
**Requirements:** UX-01, UX-02, UX-03, UX-04, LINUX-01
**Success Criteria:**
  1. Native chrome is used where it works, and custom chrome fallback exposes close/minimize/drag controls.
  2. Graph editing, backend settings, monitor visibility, and diagnostics are keyboard-accessible.
  3. Visual QA screenshots pass desktop and mobile-size smoke checks for docs/site previews.
  4. Errors provide next actions and do not expose backend clutter by default.
**Plans:** 1 plan
  - [x] 04-01-PLAN.md — route controls, diagnostics, custom chrome fallback, responsive polish, and visual QA
**UI hint:** yes

### Phase 5: Linux Install and Startup
**Goal:** Users can install Loopwire and make it start on boot without memorizing launch commands.
**Depends on:** Phase 4
**Requirements:** LINUX-01, LINUX-02, LINUX-03, LINUX-04, QUAL-03
**Success Criteria:**
  1. curl installer downloads signed release artifacts and verifies checksums.
  2. AUR and Nix packaging paths build from the same release artifacts.
  3. User-scoped systemd autostart is documented, reversible, and tested.
  4. Installer never mutates system audio config without explicit user action.
**Plans:** 6 plans
  - [x] 05-01-PLAN.md — VM compatibility matrix for distro, DE/WM, session, package manager, and audio-server coverage
  - [x] 05-02-PLAN.md — user-scoped startup helper for XDG desktop autostart and future systemd restore
  - [x] 05-03-PLAN.md — local release-artifact installer smoke and AUR/Nix package metadata templates
  - [x] 05-04-PLAN.md — reproducible release tarball/checksum generation and protected release workflow
  - [x] 05-05-PLAN.md — local AUR PKGBUILD rendering and makepkg package smoke from generated artifacts
  - [x] 05-06-PLAN.md — signed release manifest verification in installer, release staging, and workflow
**UI hint:** no

### Phase 6: Documentation and Website
**Goal:** Public docs explain what works, what is experimental, how to install, and how to troubleshoot.
**Depends on:** Phase 5
**Requirements:** DOCS-01, DOCS-02, DOCS-03, DOCS-04
**Success Criteria:**
  1. VitePress docs cover install, start-on-boot, backend support, architecture, troubleshooting, and release notes.
  2. Product screenshot pipeline reflects the real app UI.
  3. Support matrix is explicit about distros, DE/WM, session managers, and audio backends.
  4. Release docs update in the release workflow.
**Plans:** 1 plan
  - [x] 06-01-PLAN.md — support matrix, troubleshooting, screenshot contract, release notes, and docs verification
**UI hint:** yes

### Phase 7: CI/CT/CD and Release Ceremony
**Goal:** The project can ship safely through protected workflows with real validation evidence.
**Depends on:** Phase 6
**Requirements:** QUAL-02, QUAL-03, QUAL-04, QUAL-05
**Success Criteria:**
  1. CI gates install, typecheck, tests, app build, docs build, and scripts.
  2. CT can run host audio diagnostics on Linux machines with supported backends.
  3. CD deploys VitePress output to Bunny.net only with required secrets and protected refs.
  4. Release workflow creates checksums and requires post-release install smoke evidence.
**Plans:** 1 plan
  - [x] 07-01-PLAN.md — CI crate checks, CT artifacts, docs deploy guard, release notes, and post-publish smoke
**UI hint:** no

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Walking Skeleton | v0.1 | 1/1 | Complete | 2026-07-03 |
| 2. Backend Capability Layer | v0.1 | 5/5 | Complete | 2026-07-03 |
| 3. Configuration Runtime | v0.1 | 1/1 | Complete | 2026-07-03 |
| 4. World-Class Desktop UX | v0.1 | 1/1 | Complete | 2026-07-03 |
| 5. Linux Install and Startup | v0.1 | 6/6 | Complete | 2026-07-03 |
| 6. Documentation and Website | v0.1 | 1/1 | Complete | 2026-07-03 |
| 7. CI/CT/CD and Release Ceremony | v0.1 | 1/1 | Complete | 2026-07-03 |
| 8. Physical Monitor Device Binding | v0.2 | 1/1 | Complete | 2026-07-03 |
| 9. Native PipeWire Graph Adapter | v0.2 | 1/1 | Complete | 2026-07-03 |
| 10. Live Apply Consent and Runtime Wiring | v0.2 | 1/1 | Complete | 2026-07-03 |
| 11. True Per-Edge Matrix Semantics | v0.2 | 1/1 | Complete | 2026-07-03 |
| 12. Published Release and VM Proof | v0.2 | 1/1 | In Progress | - |

---
*Roadmap defined: 2026-07-03*
*Last updated: 2026-07-03 after desktop backend detection and Phase 12 evidence gating*

## Backlog

### Phase 999.1: Apply device and source volume/mute on the host (BACKLOG)

**Goal:** [Captured for future planning] Source volume (route gains), device volume, and device mute are configured-only today; non-unity gains even block native live apply. Apply volume on Loopwire-owned nodes (pw-cli set-param / wpctl on virtual sinks) and hot-apply volume edits, then drop the unity-gain preflight blocker for backends that support it. Needs a Tauri bridge allowlist addition.
**Requirements:** TBD
**Plans:** 0 plans

Plans:
- [ ] TBD (promote with /gsd:review-backlog when ready)

### Phase 999.2: Per-port level stream and live meters (BACKLOG)

**Goal:** [Captured for future planning] All meters render silence because no adapter provides per-port levels. Add a PipeWire level-monitoring path feeding the desktop levelStore (cards, buses, monitors, sidebar mini-meter) with rAF-throttled smooth decay.
**Requirements:** TBD
**Plans:** 0 plans

Plans:
- [ ] TBD (promote with /gsd:review-backlog when ready)

### Phase 999.3: Enforce mute-when-capturing on the host (BACKLOG)

**Goal:** [Captured for future planning] The app-source "Mute when capturing" checkbox stores domain state but no adapter mutes the app's normal output while Loopwire captures it.
**Requirements:** TBD
**Plans:** 0 plans

Plans:
- [ ] TBD (promote with /gsd:review-backlog when ready)

### Phase 999.4: Re-apply host state when device removal is undone (BACKLOG)

**Goal:** [Captured for future planning] The undo toast restores Loopwire state but not the host graph; the device must be re-selected/toggled to bring its nodes back. Undo should re-run the apply transaction for the restored device when it was live.
**Requirements:** TBD
**Plans:** 0 plans

Plans:
- [ ] TBD (promote with /gsd:review-backlog when ready)

### Phase 999.5: PipeWire pending-stream retry for absent app sources (BACKLOG)

**Goal:** [Captured for future planning] Cabling an app that is not currently playing skips/fails its links with no retry when the stream appears. Mirror the PulseAudio pending-stream refresh for native PipeWire so late-starting apps get linked.
**Requirements:** TBD
**Plans:** 0 plans

Plans:
- [ ] TBD (promote with /gsd:review-backlog when ready)

### Phase 999.6: Honor explicit monitor cables on JACK and PulseAudio (BACKLOG)

**Goal:** [Captured for future planning] Native PipeWire plans monitor links from explicit bus-to-monitor routes; JACK still connects all output-monitor pairs and PulseAudio tolerates but ignores per-cable monitor routing. Bring both to parity or document a hard capability gap per backend contract.
**Requirements:** TBD
**Plans:** 0 plans

Plans:
- [ ] TBD (promote with /gsd:review-backlog when ready)

### Phase 999.7: Startup sweep for orphaned Loopwire host nodes (BACKLOG)

**Goal:** [Captured for future planning] Live-device tracking is session-local; a crash without unload leaves loopwire_* nodes lingering (object.linger). On startup, detect Loopwire-owned nodes that do not match the applied device and offer/perform cleanup.
**Requirements:** TBD
**Plans:** 0 plans

Plans:
- [ ] TBD (promote with /gsd:review-backlog when ready)

### Phase 999.8: Keyboard-selectable cables (BACKLOG)

**Goal:** [Captured for future planning] Cables can only be selected by mouse click; keyboard users cannot select or delete a route without deleting an endpoint. Add focusable cable selection (or a route list surface) per the accessibility bar in vnc-ux-spec section 6.
**Requirements:** TBD
**Plans:** 0 plans

Plans:
- [ ] TBD (promote with /gsd:review-backlog when ready)

### Phase 999.9: Refresh docs product screenshot to the rebuilt UI (BACKLOG)

**Goal:** [Captured for future planning] apps/docs/docs/public/product-screenshot.svg still shows the pre-rebuild stacked-panel UI; regenerate from the sidebar + patch-bay shell.
**Requirements:** TBD
**Plans:** 0 plans

Plans:
- [ ] TBD (promote with /gsd:review-backlog when ready)
