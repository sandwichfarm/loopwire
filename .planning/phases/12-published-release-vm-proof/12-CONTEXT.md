# Phase 12 Context: Published Release and VM Proof

## Goal

Prove release claims from published artifacts and VM evidence, not from local source assumptions.

## Constraints

- Do not publish a GitHub Release without an explicit version/tag/signing-key decision.
- Do not claim installability until assets are downloaded from the release surface and installed with signature checks.
- Do not claim VM coverage until a target captures install, launch, backend detection, and screenshot evidence.

## Current State

- The release workflow can publish signed artifacts on `v*` tags.
- The release workflow already downloads published assets and runs a post-publish install smoke.
- VM target metadata and cloud-init rendering exist, but no live VM evidence has been captured in this turn.
- `packaging/release-signing-public.pem` is still a placeholder path until a real public key is committed.

## Acceptance

- A reusable published-release verifier exists for local and VM proof.
- A tagged release has versioned release notes and real signing material.
- Published assets are downloaded and installed with signature verification.
- At least one VM target records install, launch, backend detection, and screenshot evidence.
