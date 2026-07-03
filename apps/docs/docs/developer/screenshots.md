# Screenshots

The docs home page uses `apps/docs/docs/public/product-screenshot.svg`.

## Contract

- The screenshot must show the current Loopwire desktop shell, not generic marketing art.
- The image must include configurations, backend status, routes, outputs, and monitors.
- Text must fit within the rendered image at desktop and mobile docs breakpoints.
- Alt text on the home page must describe the visible product state.
- If the desktop UI changes meaningfully, refresh the screenshot in the same release.

## Refresh Procedure

1. Build or run the current desktop UI.
2. Capture a clean first-screen product state at a desktop viewport.
3. Compare the image against the app for stale labels, removed controls, and unsupported backend claims.
4. Replace `product-screenshot.svg` only after the image reflects current UI behavior.
5. Run:

```bash
pnpm verify:docs
pnpm build:docs
```

## Acceptance

The screenshot is acceptable when it makes the product legible without implying unsupported live audio features. If the
app only supports dry-run host apply for a backend, the screenshot must not imply unattended production routing is fully
shipped.
