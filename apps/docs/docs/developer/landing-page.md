# Landing-page design

The root page uses a signal-path identity: a geometric wordmark, two intersecting loops, dark ink on mineral
colors, and fine routed lines. Sora is the shared wordmark and interface typeface. The product preview belongs to
the hero composition; it has no added frame, shadow, or rounded shell. It is cropped to emphasize routing and links
to the full application screenshot.

## Design rules

- Use typography and spacing to establish hierarchy. Avoid ornamental panels, pills, glows and shadows.
- Reserve strokes for the original loop mark, background paths, selected-tab indicator and keyboard focus.
- Keep installation commands visible. Put extended requirements behind the native disclosure control.
- Keep the automatic installer and all platform/source commands from the install guide in sync.
- Keep metadata and no-JavaScript installation access intact.

## Motion

`apps/site/src/lib/signalField.ts` owns the decorative canvas and palette. GSAP animates plain state objects;
rendering is coalesced through a requested animation frame. There are 24 paths with 72 samples each, and backing
resolution is capped at 1.5 device pixels per CSS pixel. There is no idle drawing loop.

Pointer movement bends nearby paths. A click sends a brief traveling displacement. Successful clipboard completion
sends a separate, slightly stronger pulse; a delayed or failed copy cannot acknowledge the wrong selected tab.
Each installation tab selects a distinct mineral background and ink accent through a short color transition.
The pattern remains static for reduced motion, while palette changes happen immediately. Preference changes are
handled live. Hidden documents stop their motion, and unload removes listeners and tweens. Animation is local and
does not need a network service.

GSAP **3.15.0** is pinned in the site package and lockfile. It was explicitly requested for this design, verified
against the registry on September 5, 2026, and had been published on April 13, 2026. The tradeoff is an additional
client bundle in return for reusable pointer tweens, coordinated color/pulse motion and interruption control.
See the official [quickTo documentation](https://gsap.com/docs/v3/GSAP/gsap.quickTo()/) for the reusable tween API.

## Font asset

`apps/site/public/fonts/sora-latin-variable.woff2` is the locally served Sora Latin variable font, weights 100–800.
It comes from the [Google Fonts Sora distribution](https://fonts.google.com/specimen/Sora), v17, with the original
SIL Open Font License retained in `OFL-Sora.txt`. Source font URL:
[versioned WOFF2](https://fonts.gstatic.com/s/sora/v17/xMQbuFFYT72XzQUpDg.woff2).
The build never fetches fonts, and the page makes no external font requests.

## Verification and screenshot proofs

Run `pnpm build:web`, `pnpm verify:site`, and `pnpm e2e:site` with the existing system Playwright setup described in
[the browser-test guide](./e2e.md). The suite checks actual canvas pixels and computed background colors, including
pointer/click/copy responses, transitions, idle stability, live reduced-motion changes and an unavailable canvas.
It also checks the loaded font, absence of decorative framing, command copying, keyboard focus, no-JavaScript
fallback, and layouts from 320px to 1440px.

Use `pnpm e2e:site --screenshots <output-directory>` to produce desktop, mobile, Ubuntu palette and successful-copy
proofs. Screenshots use the real page and clipboard API. The copy screenshot captures the finite pulse in progress,
so its line positions vary slightly between runs. Commit review proofs with the task record and embed their raw
GitHub URLs in the PR body. A static screenshot alone does not prove interactive motion; retain the test results too.
