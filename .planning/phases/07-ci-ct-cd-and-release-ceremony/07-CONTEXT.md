# Phase 7 Context: CI/CT/CD and Release Ceremony

Loopwire needs enough automation to keep the greenfield project honest without pretending hosted CI can validate every
Linux desktop/audio combination. CI should prove source health. CT should collect redacted host diagnostics. CD should
deploy docs only through explicit gates. Release automation should prove artifacts before and after GitHub publication.

## Inputs

- Existing GitHub Actions workflows.
- Local validation commands wired through `pnpm check`.
- Release artifact, installer, signing, AUR, packaging, VM, and docs verification scripts.
- GitHub Actions workflow syntax docs for `permissions`, `workflow_dispatch`, `concurrency`, and environments.

## Constraints

- No live GitHub run exists yet because this is a greenfield local checkout.
- Do not rely on unavailable local tools such as `actionlint` or `zizmor`.
- Do not inspect GitHub secrets in workflow `if` expressions.
- Keep release publishing blocked until versioned release notes and signing keys exist.
