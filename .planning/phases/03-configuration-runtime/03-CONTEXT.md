# Phase 3 Context: Configuration Runtime

**Status:** Complete
**Date:** 2026-07-03
**Requirements:** CONFIG-01, CONFIG-02, CONFIG-03, CONFIG-04, QUAL-01, DOCS-03

## Goal

Turn configuration switching from a selected UI state into a tested application-runtime transaction with explicit
apply, verify, and rollback semantics.

## Scope

- Add pure core operations for creating, editing, duplicating, deleting, exporting, importing, and migrating
  configurations.
- Add a backend-agnostic runtime transaction port that unloads the previous configuration, applies the selected
  configuration, verifies it, and rolls back on failure.
- Add startup re-apply planning so persisted selected configurations are verified when the app opens.
- Wire the desktop app to these operations with an app-local adapter that records transaction state.
- Update docs to explain what is implemented and where host backend mutation still begins later.

## Out of Scope

- No PipeWire, PulseAudio, JACK, or ALSA graph mutation in this phase.
- No persistent host-level audio configuration changes.
- No packaging or release claims.
- No proprietary Loopback code, assets, visual styling, or interaction copying.

## Architecture Layers

- Domain model: configuration CRUD, import/export validation, migration.
- Routing engine: transaction plan and apply/verify/rollback state machine.
- UI shell: calls core runtime services and persists returned state.
- Docs: user/developer description of current configuration runtime behavior.

## Verification Targets

- Unit tests for CRUD, import/export, migration, successful switch, failed apply rollback, failed verify rollback, and
  startup verification planning.
- Root validation: `pnpm check`.
- Script validation: `pnpm verify:scripts`.
- Tauri metadata check: `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml`.
- Host detector smoke: `pnpm detect:audio`.
- Whitespace check: `git diff --check`.
