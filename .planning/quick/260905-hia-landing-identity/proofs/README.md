# Landing-page review proofs

Generated from the combined production web build with:

```sh
pnpm build:web
PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium pnpm e2e:site --screenshots .planning/quick/260905-hia-landing-identity/proofs
```

| Image | Viewport | State |
| --- | --- | --- |
| `desktop.png` | 1440 × 1000 | Automatic tab, idle signal field |
| `mobile.png` | 390 × 844 | Automatic tab; full-page capture |
| `ubuntu-palette.png` | 1440 × 1000 | Ubuntu selected; completed mineral/terracotta transition; full-page capture |
| `copy-response.png` | 1440 × 1000 | Automatic command copied through the real Clipboard API; finite pulse in progress |

These are actual Chromium screenshots, without compositing or post-processing. The copy pulse is captured during
animation, so its exact line positions can vary between runs. The product preview uses the existing application
screenshot and links to its full version. Automated pixel/color tests cover the interactions that still images
cannot demonstrate, including motion reduction, idle stability and a visibility-boundary simulation.
