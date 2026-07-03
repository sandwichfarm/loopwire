# Release Notes

Release notes are part of the release ceremony, not an afterthought.

## Release-note workflow

1. Keep active user-facing notes in `/release-notes/unreleased`.
2. Before tagging, create a versioned candidate page from the unreleased notes.
3. Include install-channel evidence, backend support changes, VM evidence, and known limitations.
4. Remove claims that are not backed by tests, VM evidence, package smoke, or release artifacts.
5. Start a fresh unreleased page immediately after tagging.
6. Run `pnpm verify:docs` and `pnpm build:docs`.

Versioned pages created before a GitHub Release must say they are release-candidate notes. Remove that qualifier only
when intentionally publishing the tag: `pnpm verify:release-readiness` and the GitHub release workflow reject
candidate/not-published wording before artifacts are attached to a public release.

## Template

```md
# vX.Y.Z

## Supported

- Install channels smoke-tested for this release.
- Backends and desktops with evidence.

## Changed

- User-visible changes.

## Fixed

- Bug fixes with issue or PR links.

## Known Limitations

- Unsupported or experimental paths.

## Verification

- CI run, VM targets, package smoke, and manual checks.
```

Release notes must be accurate even when that means saying a feature is planned or experimental.
