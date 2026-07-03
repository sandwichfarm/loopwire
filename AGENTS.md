# AGENTS.md

## Project Intent

Loopwire is a Linux virtual audio routing application inspired by the workflow quality of Rogue Amoeba Loopback.
The goal is not to copy proprietary code, assets, names, or trade dress. The goal is to build a native Linux tool
that makes virtual devices, app capture, routing, monitoring, and persistence understandable and reliable.

This is a greenfield project. Treat this file as the operating contract until stronger project-local decisions exist.

Primary reader: a future coding agent or maintainer landing cold in this repo.

Post-read action: plan, implement, validate, and ship Loopwire work without weakening architecture, reproducibility,
Linux support, testability, documentation, or release discipline.

## Product Goals

- Provide a polished Linux UX for creating virtual audio devices and routing audio between apps, microphones,
  monitors, outputs, and recording/broadcast tools.
- Prefer real Linux audio primitives over fragile UI-only fakery.
- Support PipeWire first, because it is the modern Linux desktop audio graph.
- Keep a credible compatibility path for PulseAudio, JACK, ALSA-only systems, and professional audio workflows.
- Make routing state inspectable, recoverable, exportable, and safe to apply.
- Make failure states boring: missing permissions, absent session managers, backend crashes, and device changes must
  produce clear diagnostics and rollback paths.

## Non-Goals

- Do not clone proprietary Loopback code, assets, brand styling, icons, copy, or exact interaction details.
- Do not depend on one desktop environment, compositor, distribution, package manager, or session manager.
- Do not hide backend limitations behind fake UI success states.
- Do not ship features that cannot be reproduced, tested, documented, and released through the project workflow.

## Operating Principles

- Keep architecture explicit. Every feature belongs to a named layer with one-way dependencies.
- Prefer deletion and replacement over compatibility shims when the project is still pre-stable.
- No new dependency without a current-version check, a maintenance reason, and a documented tradeoff.
- No new global state unless it is the actual domain state model or a platform-owned resource.
- No backend-specific behavior in UI components.
- No UI-only simulation of host-owned audio state.
- Verify against real system surfaces when behavior depends on PipeWire, PulseAudio, JACK, ALSA, portals, permissions,
  or packaging.
- Update docs in the same change that updates behavior.
- Keep pull requests small enough to review and revert.

## Architecture Contract

Use a clean architecture shape with strict dependency direction:

1. Domain model
   - Virtual devices, sources, sinks, channels, routes, taps, monitors, presets, errors, and diagnostics.
   - Pure logic only. No PipeWire, GTK, Qt, Tauri, Electron, DBus, filesystem, network, or shell calls.
   - Must be unit-testable without Linux audio installed.

2. Routing engine
   - Validates graph changes, computes apply plans, detects conflicts, and produces rollback plans.
   - Talks to audio backends only through ports/interfaces.
   - Owns transactional semantics: preview, apply, verify, rollback.

3. Audio backend adapters
   - PipeWire adapter is the reference backend.
   - PulseAudio, JACK, ALSA, and compatibility adapters must implement the same backend contract or explicitly document
     why a capability is unavailable.
   - Backend adapters may call host APIs, DBus, CLI tools, native libraries, or service managers. They must translate
     all failures into typed project errors.

4. Platform integration
   - Distro packaging, autostart, systemd user services, desktop portals, permissions, udev, and session-manager
     integration live here.
   - Must not leak into domain logic or UI state.

5. Persistence and config
   - Stores user routing graphs, presets, preferences, migration state, and diagnostics snapshots.
   - Config formats must be versioned and migration-tested.
   - Prefer human-readable export formats for support and bug reports.

6. UI and interaction shell
   - Presents the domain graph and backend diagnostics.
   - Calls application services, not backend adapters directly.
   - Must handle degraded backend capability without pretending unsupported actions worked.

7. CLI and automation surface
   - Exposes scriptable inspection, export/import, diagnostics, and apply/rollback workflows.
   - Must use the same application services as the UI.

Any module that violates these dependency rules needs either a refactor before merge or a short ADR explaining why.

## Audio Backend Support

PipeWire is the first-class target:

- Support WirePlumber and common PipeWire session-manager setups.
- Detect graph nodes, streams, monitors, metadata, default devices, channel layouts, and permissions.
- Prefer libpipewire or stable APIs over scraping CLI output when feasible.
- CLI output may be used for diagnostics, smoke tests, or fallback paths, but parsing must be isolated and tested.

PulseAudio compatibility:

- Support systems using PulseAudio directly where practical.
- Treat PulseAudio under PipeWire separately from native PulseAudio when behavior differs.
- Document missing capabilities clearly.

JACK and pro-audio:

- Preserve compatibility with JACK workflows where feasible.
- Avoid assumptions that desktop audio and pro-audio graphs are equivalent.
- Test routing behavior under common JACK bridge configurations before claiming support.

ALSA:

- Treat ALSA as the hardware substrate and fallback layer, not as the primary UX target.
- Do not require fragile per-machine ALSA config edits for normal app behavior.

Linux distribution breadth:

- Maintain install and runtime notes for Arch, Fedora, Debian, Ubuntu, and Nix/NixOS once packaging exists.
- Avoid distro-specific hardcoding in core behavior.
- Package-manager commands belong in docs, scripts, or packaging modules, not product logic.

## GSD Workflow

Use GSD for non-trivial work.

Required flow:

1. Capture intent
   - Create or update a GitHub issue for user-visible work, architecture changes, backend support, packaging, release,
     or CI/CD changes.
   - Link relevant docs, logs, screenshots, failing commands, and acceptance criteria.

2. Plan the slice
   - Write the smallest vertical slice that can be built, tested, documented, and reviewed.
   - Identify affected architecture layers.
   - Identify required verification before implementation starts.

3. Execute narrowly
   - One branch per issue or coherent slice.
   - Keep each PR focused on one behavior change or one structural cleanup.
   - Do not combine cleanup, feature work, packaging, and UI redesign in one PR unless the issue explicitly requires it.

4. Verify
   - Run targeted tests first.
   - Run broader gates before PR readiness.
   - Capture real-system evidence for audio/backend/platform claims.

5. Document and ship
   - Update README, user docs, developer docs, release notes, and migration notes as applicable.
   - PR description must include validation evidence and known gaps.

GSD artifacts should be committed when they are durable project knowledge. Do not commit private scratch notes,
secrets, machine-local paths, or temporary logs.

## Branching and GitHub Strategy

Use minimal-conflict branching:

- Base feature branches from the current default branch.
- Branch name format: `type/issue-short-topic`, for example `feature/42-pipewire-graph`.
- Keep branches short-lived.
- Rebase or merge from default before review if the branch is stale.
- Do not rewrite other people's branches.
- Do not stack branches unless a dependency chain is intentional and documented.

Issue strategy:

- Every user-facing feature, backend capability, packaging target, release process change, and CI gate gets an issue.
- Issues should state the problem, acceptance criteria, validation surface, and docs impact.
- Close issues from PRs only when acceptance criteria are actually met.

PR strategy:

- PRs must list changed architecture layers.
- PRs must list commands run and results.
- PRs must list docs updated or explain why docs were not needed.
- PRs must list unsupported Linux/audio environments if the change touches platform behavior.
- Prefer reviewable diffs over broad rewrites.

Commit messages:

- Use intent-first commit messages.
- For meaningful changes, include trailers such as `Constraint:`, `Rejected:`, `Confidence:`, `Scope-risk:`,
  `Tested:`, and `Not-tested:` when they add useful future context.

## Reproducibility

Every contributor should be able to recreate the development and release environment.

Required practices:

- Commit lockfiles for every package manager used by the repo.
- Pin toolchains through the project-standard mechanism once chosen.
- Prefer declarative dev environments such as Nix, mise, asdf, devcontainers, or distro package manifests.
- Keep generated code deterministic.
- Keep test fixtures deterministic and small.
- Document required host services for integration tests.
- Provide a single documented bootstrap command once tooling exists.
- Provide a single documented local validation command once tooling exists.

If a command depends on local hardware, desktop session, audio server, or distribution state, document that explicitly.

## Testing Strategy

Build tests around confidence surfaces, not arbitrary coverage numbers.

Required test layers:

- Domain unit tests for routing graph validation, channel mapping, presets, migrations, and error classification.
- Property tests for graph invariants, serialization, import/export, route planning, and migration round trips.
- Backend contract tests that every backend adapter must pass.
- Fake backend tests for failure modes, permission errors, disappearing devices, and rollback behavior.
- PipeWire integration tests on Linux runners or controlled containers where feasible.
- Manual host validation for behavior that cannot be reliably virtualized.
- UI interaction tests for core flows once the UI exists.
- Accessibility tests for keyboard, screen-reader labels, contrast, focus order, and reduced-motion behavior.
- Packaging smoke tests for each supported package format.

Before cleanup/refactor work:

- Write a cleanup plan.
- Lock current behavior with regression tests when behavior is not already protected.
- Prefer deleting dead code over rearranging it.

Before claiming backend support:

- Prove detection, apply, verify, failure reporting, and rollback.
- Save the exact commands, logs, or screenshots needed for PR review.

## Maintainability

- Keep modules small and purpose-specific.
- Keep public interfaces documented.
- Keep error types structured and actionable.
- Prefer typed data and explicit state machines over stringly-typed status flags.
- Avoid hidden background behavior. Long-running operations need status, cancellation, and recovery.
- Centralize capability detection. Do not scatter distro/audio-server checks through the codebase.
- Centralize diagnostics collection. Support bundles must be redactable and useful.
- Remove obsolete paths when replacing behavior.
- Add ADRs for decisions that future maintainers are likely to revisit.

## Documentation Requirements

Docs must be current on every release.

Maintain at least these documentation surfaces once the project has content:

- README: what Loopwire is, status, install, quick start, support matrix, and safety notes.
- User guide: routing concepts, virtual devices, monitoring, presets, troubleshooting, and limitations.
- Developer guide: architecture, setup, test commands, backend contracts, and release process.
- Support matrix: distro, audio server, session manager, desktop environment, package format, and known gaps.
- Changelog or release notes: user-visible changes, breaking changes, migrations, and known issues.
- ADRs: major architecture, backend, packaging, or release decisions.

Documentation rules:

- Do not document unimplemented features as available.
- Mark experimental support clearly.
- Every release PR must update docs or explicitly state why no docs changed.
- Keep troubleshooting grounded in real commands and observed failure modes.
- Avoid stale path references in long-lived prose unless the path is the thing being documented.

## Build and Release Ceremony

Release work is a product feature, not an afterthought.

Before the first public release, define:

- Supported install formats.
- Versioning policy.
- Stability labels.
- Upgrade and migration policy.
- Signing and checksum policy.
- Release artifact retention.
- Rollback guidance.

Every release must include:

- Clean working tree.
- Changelog or release notes.
- Version bump through the project-standard mechanism.
- Full local validation or documented equivalent CI evidence.
- Packaging smoke tests.
- Artifact checksums.
- Signed artifacts when signing infrastructure exists.
- Git tag.
- GitHub release notes.
- Post-release install test from published artifacts, not local build output.

Never claim a release is complete until the published artifact has been installed and smoke-tested.

## CI, CT, and CD

Use CI/CD only where it provides reliable signal.

Required CI gates once tooling exists:

- Formatting.
- Linting.
- Type checking or compiler warnings as errors.
- Unit tests.
- Property tests for routing, serialization, and migrations.
- Backend contract tests with fake adapters.
- Documentation checks.
- Packaging build checks.
- Security/dependency audit where the ecosystem supports it.

Continuous testing:

- Run heavier integration tests on scheduled jobs, release branches, or labeled PRs.
- Use Linux matrix coverage for representative distributions when feasible.
- Separate deterministic CI tests from host-dependent manual validation.

Continuous deployment:

- Do not auto-publish from arbitrary branches.
- Publish only from protected release workflows.
- Require version, changelog, artifact, checksum, and smoke-test evidence.
- Keep secrets scoped to release jobs.

Avoid CI theater:

- Do not add slow jobs that fail randomly and teach contributors to ignore CI.
- Do not block every PR on scarce hardware tests unless the PR changes that surface.
- Do not run release jobs when branch protection already owns validation unless the release needs that signal.

## Security and Safety

Loopwire touches user audio, app streams, and desktop session state. Treat that as sensitive.

- Never log raw audio.
- Never upload diagnostics automatically.
- Redact usernames, paths, device serials, app titles, and environment variables from support bundles when possible.
- Ask before making persistent host-level changes outside the app's owned config paths.
- Prefer user-scoped services over system services.
- Use least privilege for portals, DBus, native helpers, and packaging scripts.
- Make rollback paths visible before applying persistent routing or service changes.

## UX Quality Bar

Linux audio is already hard. The UI must reduce complexity, not expose backend clutter by default.

- Show the audio graph clearly.
- Make drag/drop or connect/disconnect operations reversible.
- Separate "configured", "applying", "verified", "degraded", and "failed" states.
- Explain failures with a next action.
- Preserve keyboard accessibility.
- Preserve screen-reader labels and focus order.
- Use platform conventions where they help, but do not let toolkit defaults produce a confusing workflow.
- Do not use backend jargon as primary user-facing copy unless the user is in an advanced diagnostics view.

## Validation Checklist

Before finalizing any non-trivial change, confirm:

- The change belongs to the intended architecture layer.
- Behavior is covered by the narrowest useful automated tests.
- Host/audio behavior was verified on the real surface when applicable.
- Docs were updated or explicitly judged unnecessary.
- CI gates pass or failures are unrelated and documented.
- No unimplemented feature was documented as done.
- No proprietary Loopback material was copied.
- Release notes or changelog were updated when user-visible behavior changed.

## Agent Stop Condition

Stop only when:

- The requested slice is implemented or the requested document is written.
- The relevant validation has run and results are known.
- Remaining risks are explicit.
- The final response lists changed files, simplifications made, validation evidence, and skipped checks.
