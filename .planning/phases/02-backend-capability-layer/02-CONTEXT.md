# Phase 2: Backend Capability Layer - Context

**Gathered:** 2026-07-03
**Status:** Ready for planning
**Mode:** Auto-generated (discuss skipped via workflow.skip_discuss)

<domain>
## Phase Boundary

Real host backend detection establishes credible support breadth without pretending routing has shipped.

This phase must detect PipeWire, PulseAudio, JACK, and ALSA candidates through read-only host checks, translate findings
into typed capability reports, and keep those checks isolated from the pure domain and UI layers.
</domain>

<decisions>
## Implementation Decisions

### Locked by AGENTS.md and Roadmap

- PipeWire is the reference backend.
- PulseAudio, JACK, and ALSA must be modeled as compatibility paths, not ignored.
- Backend adapters may call host APIs, CLI tools, native libraries, or services, but failures must become typed project
  errors/capability gaps.
- UI components must not call shell commands.
- Do not claim real audio routing until apply, verify, and rollback exist.

### Agent Discretion

- Implement read-only detection in a separate workspace package so the pure core model stays host-independent.
- Use injected command runners for tests and a Node runner for local/CI diagnostics.
- Prefer stable command surfaces available on common Linux systems: `wpctl`, `pw-cli`, `pactl`, `jack_lsp`, and `aplay`.
- Treat missing tools, inactive services, and no hardware devices as structured diagnostics, not crashes.
</decisions>

<code_context>
## Existing Code Insights

- `@loopwire/core` owns pure backend decisioning and persistence.
- `@loopwire/desktop` currently shows static backend candidates and must not call host commands directly.
- `scripts/ct-host-check.sh` already runs read-only host diagnostics and can consume a JSON report.
- VitePress docs already include a backend support page that should be updated with current detection semantics.
</code_context>

<specifics>
## Specific Ideas

- Add `@loopwire/audio-host` with `detectAudioBackends(runner)`.
- Return both core-compatible `BackendCandidate[]` and richer per-backend capability reports.
- Include diagnostics for command presence, command exit, version/server strings, and known capability gaps.
- Add a CLI script that prints JSON for CI/CT and local manual verification.
</specifics>

<deferred>
## Deferred Ideas

- Virtual device creation, route mutation, rollback, and Tauri command integration are deferred to Phase 3+.
- libpipewire native bindings are deferred until the CLI-backed read-only contract proves the shape.
</deferred>
