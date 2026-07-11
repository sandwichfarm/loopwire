---
id: SEED-004
status: sprouted
sprouted_into: v0.3 Seed Harvest (phases 13-17)
planted: 2026-07-07T13:56:16+02:00
planted_during: v0.2 Production Audio Routing (post-Phase-11 desktop UI rebuild)
trigger_when: when planning pro-audio/advanced channel work (PRO-02)
scope: small (UI affordance) to medium (channel-layout UX)
---

# SEED-004: Multichannel bus creation (channel-count choice beyond stereo pairs)

## Why This Matters

The Output Channels ⊕ always appends a stereo bus; there is no way to build mono or >2-channel buses from the UI even though AudioEndpoint.channels and the PipeWire adapter's audio.position layouts already support 1-8 channels.

## When to Surface

**Trigger:** when planning pro-audio/advanced channel work (PRO-02)

This seed will surface during `/gsd:new-milestone` when the milestone scope matches.

## Scope Estimate

**small (UI affordance) to medium (channel-layout UX)**

## Breadcrumbs

- nextBusLabel in apps/desktop/src/lib/stores/deviceStore.ts (hardcoded pairs)
- audioPositionsForChannels in packages/audio-host/src/pipewire-adapter.ts
- .planning/REQUIREMENTS.md PRO-02
