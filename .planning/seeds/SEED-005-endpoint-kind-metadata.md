---
id: SEED-005
status: sprouted
sprouted_into: v0.3 Seed Harvest (phases 13-17)
planted: 2026-07-07T13:56:16+02:00
planted_during: v0.2 Production Audio Routing (post-Phase-11 desktop UI rebuild)
trigger_when: when extending source enumeration or the domain schema next
scope: small (schema field + enumeration plumbing + UI mapping)
---

# SEED-005: Endpoint kind metadata for icons, menus, and options

## Why This Matters

Source icons and the mute-when-capturing affordance rely on label/deviceName regex heuristics (mic/i etc.) because AudioEndpoint has no kind field (app stream vs capture hardware vs system source vs pass-thru). Real kind metadata from enumeration would make icons, menu grouping, and per-kind options reliable.

## When to Surface

**Trigger:** when extending source enumeration or the domain schema next

This seed will surface during `/gsd:new-milestone` when the milestone scope matches.

## Scope Estimate

**small (schema field + enumeration plumbing + UI mapping)**

## Breadcrumbs

- sourceIcon/isAppSource heuristics in apps/desktop/src/lib/components/DeviceCanvas.svelte
- sidebarSourceIcon in AppShell.svelte
- sourceCategory in apps/desktop/src/lib/services/hostCatalog.ts
