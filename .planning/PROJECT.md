# Loopwire

## What This Is

Loopwire is a Linux virtual audio routing application for people who need reliable app capture, virtual devices,
monitoring, presets, and startup persistence without wrestling with raw audio-server tooling.

It is inspired by the workflow quality of Rogue Amoeba Loopback, but it must not copy proprietary code, assets, copy,
branding, or trade dress.

## Core Value

World-class UX for real Linux audio routing: configuration changes must be understandable, reversible, persistent, and
verified against the host audio graph.

## Requirements

### Validated

- [x] Production audio routing with native PipeWire graph support; device selection applies live with preflight and rollback (v0.2, phases 8-11 + UI rebuild).
- [x] Monitors bind to physical output devices while keeping the reversible Loopwire-owned monitor path (v0.2 Phase 8).
- [x] True per-edge mixing semantics rather than stream-level sink-input controls only (v0.2 Phase 11).

### Active

- [ ] Prove release artifacts through published install smoke and VM evidence (v0.2 Phase 12; blocked on signing/publishing infrastructure).
- [ ] Endpoint kind metadata drives icons, menu grouping, and per-kind options instead of label heuristics (SEED-005).
- [ ] Buses can be created with a chosen channel count, not only stereo pairs (SEED-004).
- [ ] Export/import, backend diagnostics, and manual host bindings return to the rebuilt UI (SEED-002).
- [ ] DSP/JACK provider settings are configurable from the desktop Settings dialog (SEED-003).
- [ ] A repeatable end-to-end harness drives the real UI and asserts host behavior (SEED-001).

### Out of Scope

- Proprietary Loopback code, assets, name usage, or visual copying — legal and product-integrity boundary.
- Fake host audio behavior in the UI — backend state must come from actual supported host surfaces.
- System-level changes without an explicit rollback path — Linux audio and startup integration affect daily-use systems.

## Context

The project starts as a pnpm TypeScript workspace with a pure core package, a Svelte desktop UI surface, a Tauri 2 shell
path for native Linux integration, and a VitePress docs/site app.

PipeWire is the reference backend. PulseAudio, JACK, and ALSA remain first-class compatibility concerns, but backend
claims require detection, apply, verify, diagnostics, and rollback evidence.

## Constraints

- **Architecture**: Domain logic stays pure and backend-agnostic so it can be tested without Linux audio installed.
- **UX**: Above all else, the user experience must feel polished, direct, and trustworthy.
- **Compatibility**: Avoid distro, desktop environment, window manager, session manager, and audio-server hardcoding.
- **Release**: Published artifacts must be installed and smoke-tested before a release is considered complete.
- **Docs**: Docs must be current on every release and must not present unimplemented features as shipped.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Use pnpm workspace | Fast reproducible TypeScript monorepo with lockfile support | Pending |
| Use Svelte for app UI | Small reactive UI layer suitable for desktop surfaces | Pending |
| Use Tauri 2 shell path | Native Linux desktop integration without bundling a full browser runtime | Pending |
| Use VitePress for docs/site | Explicit user requirement and strong static deployment path | Pending |
| Keep PipeWire as reference backend | Modern Linux desktop audio graph and best first target | Pending |

## Current Milestone: v0.3 Seed Harvest

**Goal:** Complete the five planted seeds from the UI rebuild: reliable endpoint metadata, multichannel buses, restored power-user surfaces, provider settings, and a real end-to-end test harness.

**Target features:**
- Endpoint kind metadata (app/capture/system/pass-thru) flowing from enumeration into icons, menus, and options (SEED-005).
- Bus creation with a chosen channel count (SEED-004).
- Restored export/import UI, backend diagnostics surface, and manual host-binding fields (SEED-002).
- DSP/JACK provider settings in the Settings dialog wired into restore and live apply (SEED-003).
- Automated end-to-end harness that drives the real UI (SEED-001).

**Carried forward:** v0.2 Phase 12 (published release + VM proof) stays open until signing/publishing infrastructure is available.

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? -> Move to Out of Scope with reason
2. Requirements validated? -> Move to Validated with phase reference
3. New requirements emerged? -> Add to Active
4. Decisions to log? -> Add to Key Decisions
5. "What This Is" still accurate? -> Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check - still the right priority?
3. Audit Out of Scope - reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-07-06 after starting v0.3 Seed Harvest*
