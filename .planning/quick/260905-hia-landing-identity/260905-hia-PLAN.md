---
status: ready_for_pr
---

# A compact signal-path identity for Loopwire

## Intent and design

Create an editorial, minimal landing page using warm mineral backgrounds, dark ink, geometric Sora typography,
plain text controls and fine routed lines. Integrate the existing product screenshot into the hero grid without
an enclosing panel. Remove the capability cards, stacked card shells, pills, glows, shadows and ornamental labels.
Use an original loop-path mark with a tightly spaced wordmark for a coherent audio-routing identity.

## Execution and cleanup plan

1. Lock the merged #38 install interactions with the existing browser suite. Keep commands unchanged.
2. Replace the root layout and styles; self-host a licensed variable font and retain attribution. GSAP 3.15.0 is
   explicitly requested, checked against the registry (released April 13, 2026), and pinned with the lockfile.
3. Add a bounded signal-field canvas driven by GSAP. Pointer motion deforms paths, clicks send a subtle pulse,
   install-tab selection transitions the background palette, and successful copying triggers a distinct response.
   Reduced-motion users get immediate color changes with static linework. Pause/clean up animation offscreen.
4. Verify keyboard/copy/no-JS behavior, motion states, responsive layout, metadata, docs and builds. Review screenshots
   against the user constraints; persist visual verdicts before each further visual edit.
5. Update design/testing/release docs, commit, push and open a PR with screenshot proofs embedded in its body.

## Boundaries and proof

Website and documentation only; no installer/audio/package behavior changes. No new dependencies beyond requested
GSAP; the font is a licensed local asset. Screenshot proofs will be committed under this quick-task directory and
embedded using immutable GitHub raw URLs so reviewers can inspect them without local files or CI artifact access.
Desktop/mobile proofs plus alternate-tab and copy-reaction states are required before completion.
