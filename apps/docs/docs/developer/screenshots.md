# Screenshots

The public site hero and docs home page use the current desktop capture from `assets/product-screenshot.png`. The
docs build serves a public copy at `/product-screenshot.png`.

## Contract

- The screenshot must show the current Loopwire desktop shell, not generic marketing art.
- The image must include the device sidebar, sources, visible routes, output channels, and monitors.
- Text must fit within the rendered image at desktop and mobile docs breakpoints.
- Alt text on the home page must describe the visible product state; do not hide the product screenshot from assistive
  technology.
- If the desktop UI changes meaningfully, refresh the screenshot in the same release.

## Refresh Procedure

1. Run the desktop browser preview and create a representative device with app, microphone, pass-through, output, and
   monitor cards.
2. Capture the full app at a 1440 by 900 desktop viewport as `assets/product-screenshot.png`.
3. Compare the image against the app for stale labels, removed controls, and unsupported backend claims.
4. Copy the approved bytes to the docs public screenshot path.
5. Run:

```bash
pnpm e2e:ui
pnpm verify:docs
pnpm build:web
```

## Acceptance

The screenshot is acceptable when it makes the product legible without implying unsupported live audio features. If the
app only supports dry-run host apply for a backend, the screenshot must not imply unattended production routing is fully
shipped.
