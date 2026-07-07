# End-to-End UI Tests

Loopwire ships a repeatable end-to-end harness that drives the real UI through
its core flows and asserts DOM outcomes. It has two layers with different host
requirements; neither is part of `pnpm check` because both depend on local
host state (browsers, WebDriver, a display session).

## Browser harness: `pnpm e2e:ui`

```sh
pnpm e2e:ui            # builds the frontend, serves dist/, drives headless Chromium
pnpm e2e:ui -- --skip-build --port 5299
```

`scripts/e2e-desktop-ui.mjs` builds `apps/desktop`, serves `dist/` on a strict
local port (default `5199`; it never kills an existing listener), launches the
system Playwright Chromium headless, and walks the flows below, printing a
pass/fail table and exiting non-zero on any failure:

- empty state renders with no devices
- create device: auto-rename commits, default Pass-Thru graph renders 2 cables
- add a source from the ⊕ menu: cable count grows by the source's channels
- toggle a source Off: its cables pick up the `dimmed` class
- select a card: footer **Delete** enables; Delete removes the card and cables
- **Hide Monitors** collapses the monitors column and restores on toggle
- reload restores state from `localStorage` (`loopwire.state.v1`)
- drag-reorder moves a sidebar device row

### Honest preview scope

The browser harness runs the frontend **without the Tauri bridge**, so it
asserts preview-mode behavior only. It makes no host-apply claims: nothing in
this suite proves PipeWire nodes or links were created. The first assertion
explicitly checks that no Tauri bridge is present so the suite cannot silently
pretend to be the desktop shell.

Requirements: system-wide Playwright (`/usr/lib/node_modules`) with its cached
Chromium, or any environment where `require("playwright")` resolves.

## Real-shell WebDriver smoke: `pnpm e2e:shell`

```sh
pnpm --filter @loopwire/desktop tauri:build   # once, to produce the binary
pnpm e2e:shell
```

`scripts/e2e-desktop-shell.mjs` launches the built Tauri binary through
`tauri-driver` + `WebKitWebDriver`, then asserts the window title, that the
Tauri bridge is live (proving this is the real shell, not the preview), and
that the app shell DOM rendered. The smoke is deliberately read-only: the real
shell applies configuration to the live PipeWire graph and mutates persisted
app state, so interactive flows stay in the browser harness.

### Host requirements (the WebKitWebDriver gap)

The real-shell path only runs where all of these exist:

- `WebKitWebDriver` from the distro webkit2gtk package (no sudo install is
  performed; if your host lacks it, only the browser harness runs)
- `tauri-driver` (`cargo install tauri-driver --locked`)
- a display session (`WAYLAND_DISPLAY` or `DISPLAY`) — WebKitGTK cannot run
  headless without a compositor, and the smoke opens a real window briefly

The script checks each precondition and refuses to fake a result when one is
missing.
