---
id: SEED-003
status: sprouted
sprouted_into: v0.3 Seed Harvest (phases 13-17)
planted: 2026-07-07T13:56:16+02:00
planted_during: v0.2 Production Audio Routing (post-Phase-11 desktop UI rebuild)
trigger_when: when provider-backed restore or DSP live apply work resumes
scope: small-medium (settings cards + persistence, logic exists in git history)
---

# SEED-003: DSP/JACK provider settings UI in the desktop shell

## Why This Matters

The rebuilt Settings dialog dropped DSP provider command/timeout/frame-count and JACK provider delegate settings; DSP is preview-only in the desktop and JACK live apply targets pre-existing ports only. CLI/systemd flags cover restore, but desktop users cannot configure providers at all.

## When to Surface

**Trigger:** when provider-backed restore or DSP live apply work resumes

This seed will surface during `/gsd:new-milestone` when the milestone scope matches.

## Scope Estimate

**small-medium (settings cards + persistence, logic exists in git history)**

## Breadcrumbs

- apps/docs/docs/guide/start-on-boot.md 'does not expose ... provider settings yet (documented gap)'
- packages/audio-host/src/dsp-adapter.ts, jack-adapter.ts (provider contracts)
- git history: pre-rebuild App.svelte provider settings + localStorage keys
