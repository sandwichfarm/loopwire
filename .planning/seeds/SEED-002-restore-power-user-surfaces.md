---
id: SEED-002
status: dormant
planted: 2026-07-07T13:56:16+02:00
planted_during: v0.2 Production Audio Routing (post-Phase-11 desktop UI rebuild)
trigger_when: when planning a settings/power-user milestone or when a user asks for any of these
scope: medium (three self-contained settings surfaces)
---

# SEED-002: Restore export/import UI, diagnostics panel, and manual host-binding fields

## Why This Matters

The UI rebuild removed configuration export/import, the backend diagnostics panel, and manual host-binding fields (documented deferrals). Domain and CLI paths still exist, but unlisted sinks now require editing the state file by hand and probe results are only visible via detection notes. These were shipped, documented features before the rebuild.

## When to Surface

**Trigger:** when planning a settings/power-user milestone or when a user asks for any of these

This seed will surface during `/gsd:new-milestone` when the milestone scope matches.

## Scope Estimate

**medium (three self-contained settings surfaces)**

## Breadcrumbs

- packages/core/src/persistence.ts (export/import format still supported)
- setEndpointDeviceName in packages/core/src/configuration.ts (unused by UI)
- apps/docs/docs/guide/configurations.md 'tracked as a UI gap' note
