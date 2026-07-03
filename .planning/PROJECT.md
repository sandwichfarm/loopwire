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

(None yet. The project is greenfield.)

### Active

- [ ] Ship production audio routing with native PipeWire graph support and explicit live-apply consent.
- [ ] Bind monitors to physical output devices without losing the reversible Loopwire-owned monitor path.
- [ ] Support true per-edge mixing semantics rather than stream-level sink-input controls only.
- [ ] Prove release artifacts through published install smoke and VM evidence.

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

## Current Milestone: v0.2 Production Audio Routing

**Goal:** Move from a verified foundation to credible production audio routing by closing the remaining backend gaps.

**Target features:**
- Physical monitor device binding.
- Native PipeWire existing-port apply, verify, and rollback.
- Explicit live backend apply consent in the desktop.
- True per-edge mixing semantics.
- Published release and VM proof.

---
*Last updated: 2026-07-03 after starting v0.2 production routing*
