# Phase 20 Verification: Auditable GitHub Release Artifacts

**Verdict:** Passed
**Issue:** https://github.com/sandwichfarm/loopwire/issues/12
**Pull request:** https://github.com/sandwichfarm/loopwire/pull/13
**Date:** 2026-08-30

## Requirement Audit

| Requirement | Evidence | Result |
|-------------|----------|--------|
| Existing valid version tag only | Tag validation, tag resolution, and detached checkout in `release.yml` | Passed |
| Tag-correct desktop bundles | Live Tauri build with ephemeral `0.1.0` config produced `Loopwire_0.1.0_amd64.AppImage` | Passed |
| Exact useful payload set | `release-asset-manifest.mjs` classifier and eight-payload fixture tests | Passed |
| Proven native package filenames | Real `--native-packages` staging built all four distro packages | Passed |
| AArch64 package safety | `--appimage-only` test rejects deb/RPM output and requires the versioned AppImage | Passed |
| Manifest and checksum integrity | Write, checksum, verify, tamper, missing, symlink, extra, and evidence tests | Passed |
| Same-tag rerun behavior | Remote asset reconciliation removes files outside the current signed inventory | Passed |
| Remote publication proof | Workflow downloads all assets and verifies inventory/checksums before both smoke stages | Passed |
| Documentation | README, release guide, packaging guide, unreleased notes, and `v0.1.0` alpha notes | Passed |
| Independent review | Correctness and threat audits reported no blocker; stale signature reuse was fixed and tested | Passed |

## Commands and Surfaces

```bash
pnpm verify:release
pnpm verify:workflows
pnpm verify:scripts
pnpm verify:docs
pnpm --filter @loopwire/docs build
pnpm check
```

Additional live local proof built the Tauri x86_64 AppImage with an ephemeral `0.1.0` configuration, ran real native
x86_64 release staging through the Ubuntu, Debian, Fedora, and openSUSE package containers, combined it with the
AArch64 portable/AppImage surfaces, and passed the eight-artifact manifest plus checksum verifier. GitHub CI run
`33336495082` passed the implementation commit on PR #13. The final PR head is also required to pass CI before merge.

## Intentionally Skipped

- No public `v0.1.0` tag or release was created.
- No release asset was uploaded outside the PR workflow.
- Live post-publication verification remains part of the protected tag workflow itself.
