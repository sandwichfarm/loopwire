# Phase 4 Context: World-Class Desktop UX

**Status:** Complete
**Date:** 2026-07-03
**Requirements:** UX-01, UX-02, UX-03, UX-04, LINUX-01, QUAL-01

## Goal

Make the desktop shell feel like a production routing workspace instead of a static mock: polished, keyboard-accessible,
diagnostic-aware, and honest about backend limitations.

## Scope

- Add keyboard-accessible route controls for gain and mute state.
- Keep route edits in pure core configuration state and persistence.
- Make custom chrome buttons call Tauri window APIs when available and fail gracefully in browser/dev mode.
- Add a diagnostics panel that hides backend clutter by default and provides next actions when opened.
- Improve responsive layout and visual QA evidence for desktop and mobile.

## Out of Scope

- No host audio graph mutation.
- No real app/source capture from PipeWire yet.
- No new UI dependency or icon package.
- No packaging/startup changes.

## Design Direction

Refined routing console: dense, dark, low-glare, high-contrast accents, stable geometry, compact controls, clear
operator state. The app should feel like a serious creative utility for people who repeatedly switch routing setups.

## Verification Targets

- Core tests for route gain/mute edits.
- Workspace validation with `pnpm check`.
- Tauri metadata check with `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml`.
- Playwright desktop and mobile smoke for rendering, route control interaction, diagnostics toggle, custom chrome
  fallback, and horizontal overflow.
