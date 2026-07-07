---
id: SEED-001
status: dormant
planted: 2026-07-07T13:56:16+02:00
planted_during: v0.2 Production Audio Routing (post-Phase-11 desktop UI rebuild)
trigger_when: when planning UI test infrastructure or an e2e/quality milestone
scope: medium (test infra + a few core flows)
---

# SEED-001: Automated GUI end-to-end tests with input injection

## Why This Matters

Adapter and service paths are unit- and live-host-verified, but nobody can drive the real Tauri/WebKitGTK window in CI or agent sessions (no Wayland input injection available). Regressions like 'card selection never sticks' shipped because only the browser preview was click-tested. Real end-to-end coverage needs tauri-driver/WebDriver or ydotool-based injection plus a headless-compositor recipe.

## When to Surface

**Trigger:** when planning UI test infrastructure or an e2e/quality milestone

This seed will surface during `/gsd:new-milestone` when the milestone scope matches.

## Scope Estimate

**medium (test infra + a few core flows)**

## Breadcrumbs

- apps/desktop/src/lib/components/AppShell.svelte (selection/apply wiring)
- scripts/verify-desktop-binary-launch.sh (launch smoke, no interaction)
- AGENTS.md UI interaction-test requirement
