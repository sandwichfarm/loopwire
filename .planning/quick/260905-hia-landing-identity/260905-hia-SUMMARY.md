---
status: complete
---

# Loopwire landing-page identity

Issue: [#39](https://github.com/sandwichfarm/loopwire/issues/39)
PR: [#40](https://github.com/sandwichfarm/loopwire/pull/40)
Implementation and screenshot commit: `6e84a9a`
Base: merged #38, `4c1fc48`

## Result

The root page now uses a flat Sora wordmark, an original interlocking loop-path mark, dark ink and nine mineral
palettes. The existing product screenshot is integrated into the hero without added framing; the crop emphasizes
routing and links to the full image. Capability cards, stacked panels, pills, shadows, glow, and redundant hero copy
were removed. Installation requirements use a disclosure control while all nine commands stay directly accessible.

GSAP responds to pointer movement and clicks, transitions the palette when an install tab is selected, and gives
successful copying a distinct finite pulse. Pointer/click/copy motion stops under reduced motion; palettes change
immediately. Idle canvas draw counts stay stable. The visibility boundary stops drawing and restores interactions.
The implementation bounds paths, samples and pixel density and removes listeners/tweens on teardown.

The PR body embeds desktop, mobile, Ubuntu palette and copy-response screenshot proofs using immutable raw GitHub
URLs. Each embedded URL was fetched successfully and its PNG bytes matched the committed local proof.

## Changed files and simplifications

- `apps/site/src/pages/index.astro`: compact composition, integrated preview, plain accessible controls and animation hooks.
- `apps/site/src/layouts/SiteLayout.astro`: lean mineral/color/type rules; removed decorative backgrounds and panel tokens.
- `apps/site/src/lib/signalField.ts`: bounded, event-driven GSAP field and palette lifecycle.
- `apps/site/public/loopwire-mark.svg`, `apps/site/public/fonts/`: original loop mark and locally served Sora with its OFL license.
- `apps/site/package.json`, `pnpm-lock.yaml`: exactly pinned GSAP 3.15.0, explicitly requested and version/age checked.
- `scripts/e2e-site-install.mjs`: installation regressions, animation pixel/color/draw checks, accessibility and reproducible proof capture.
- `scripts/verify-static-site.mjs`: current identity/background contract instead of removed capability-card content.
- `apps/docs/docs/developer/landing-page.md`, `apps/docs/docs/developer/e2e.md`,
  `apps/docs/docs/release-notes/unreleased.md`: design decisions, dependency tradeoff, font attribution and test instructions.
- This plan, summary, `proofs/`, and `.planning/STATE.md`: durable acceptance and review evidence.

No installer, audio/backend, desktop app, package recipe, or original screenshot changes.

## Validation

- The existing #38 browser suite passed before the redesign. The new static identity gate failed against the old page.
- `pnpm lint`: workspace typechecks passed; Svelte reported zero errors and warnings.
- `pnpm test`: all 295 TypeScript tests passed.
- `pnpm build`: production builds for the workspaces and combined static site passed.
- `pnpm verify:docs`, `pnpm verify:site`, `node --check scripts/e2e-site-install.mjs`, and `git diff --check` passed.
- `pnpm e2e:site --screenshots ...` passed on Chromium: all commands still match the install guide; all nine palettes
  are distinct; keyboard focus, copying/failure recovery, no-JavaScript and unavailable-canvas fallbacks work.
- Browser checks confirmed Sora actually loaded and the key layout/control elements have no borders, corner radii,
  shadows or filters. All tab views fit 320, 390, 768 and 1440px widths without page overflow.
- Motion tests compare actual canvas pixels, computed background colors and intercepted real draw calls. Pointer,
  click, copy, palette interpolation, idle draw stability and live reduced-motion behavior passed. Visibility was
  simulated at the document boundary; drawing stopped and resumed correctly.
- Removing the successful-copy hook from the built test artifact made the canvas regression fail. Restoring the
  original artifact returned all checks to green; the combined bundle matches the unmodified build output.
- Independent visual/code review passed. Final visual verdict: 96/100 against the user constraints.
- PR #40 is open and all four embedded screenshot URLs serve the exact committed PNGs.

## Remaining limits

Automated browser execution used Chromium. Other browser engines and physical mobile devices were not exercised.
No live audio, installer or native-package tests were repeated because those paths did not change. Screenshots show
individual animation frames; pixel/color tests supply the interactive evidence. No production deployment or merge
was performed.
