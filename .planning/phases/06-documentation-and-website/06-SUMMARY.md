# Phase 6 Summary: Documentation and Website

## Completed

- Added public support matrix with host targets, audio backend status, install channels, and desktop integration status.
- Added troubleshooting guide for backend detection, stream matching, route controls, autostart, chrome, and installer
  signature failures.
- Added screenshot contract docs for `product-screenshot.svg`.
- Added release-note workflow docs and an unreleased release-note page.
- Updated VitePress nav/sidebar and homepage links.
- Added `scripts/verify-docs.sh`, `pnpm verify:docs`, and root `pnpm check` integration.
- Updated release docs so release ceremony includes docs verification and release-note updates.

## Verification

- `pnpm verify:docs` passed.
- `pnpm verify:scripts` passed with `scripts/verify-docs.sh`.
- `pnpm build:docs` passed.

## Remaining Risks

- The current docs screenshot is the existing SVG product image; it must be refreshed when the app UI meaningfully
  changes.
- Public release docs remain intentionally blocked on signed artifacts, a real release public key, and release workflow
  evidence.
