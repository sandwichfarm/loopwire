# Phase 1: Walking Skeleton - Context

**Gathered:** 2026-07-03
**Status:** Ready for planning
**Mode:** Auto-generated from user objective and AGENTS.md

<domain>
## Phase Boundary

Create a runnable, tested foundation for Loopwire: workspace tooling, pure domain behavior, desktop UX shell,
VitePress docs/site, CI/CT/CD scaffolding, and deploy helper scripts.

This phase does not implement real audio graph mutation or claim packages are published.
</domain>

<decisions>
## Implementation Decisions

### Locked by User Objective

- Product direction is a Linux virtual audio routing app inspired by Loopback-level UX quality.
- World-class UX is the highest product priority.
- Support multiple desktop environments and window managers.
- Use native window chrome when available and provide custom chrome fallback.
- Support multiple audio backends with auto-detection and prompted selection when more than one is present.
- Persist the selected configuration and restore/apply it on startup.
- Support multiple configurations, instant selection, and hidden monitors.
- Provide curl installer, package-management path, VitePress docs, website, start-on-boot guidance, CI/CT/CD,
  Bunny.net website deployment, and secret setup helper.

### Agent Discretion for Phase 1

- Use pnpm, TypeScript, Svelte, Tauri 2, VitePress, and Vitest as the initial stack.
- Implement host-sensitive behavior as pure contracts and UI state in Phase 1; real backend mutation starts in Phase 2.
- Treat installer and deploy scripts as operational scaffolding until release artifacts and secrets exist.
</decisions>

<canonical_refs>
## Canonical References

- `AGENTS.md` — project operating contract and architecture rules.
- `.planning/PROJECT.md` — project context and active requirements.
- `.planning/REQUIREMENTS.md` — v1 requirement IDs and traceability.
- `.planning/ROADMAP.md` — milestone phases and Phase 1 success criteria.
- `.planning/research/ui-reference-notes.md` — workflow notes from user-provided UI references without copying assets.
</canonical_refs>

<specifics>
## Specific Ideas

- Build a desktop shell that shows three example configurations and makes the active one visually obvious.
- Show backend candidate selection with the same semantics the future host adapter must use.
- Persist active configuration through a versioned JSON state model.
- Use a striking but restrained audio-workstation aesthetic for the app and website.
</specifics>

<deferred>
## Deferred Ideas

- Real PipeWire graph mutation, virtual sink creation, JACK bridge behavior, AUR publication, signed release artifacts,
  and post-release smoke tests are deferred to later phases.
</deferred>
