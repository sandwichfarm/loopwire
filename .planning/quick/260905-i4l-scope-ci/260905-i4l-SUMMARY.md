---
status: complete
---

# CI follows the files it validates

Issue: [#41](https://github.com/sandwichfarm/loopwire/issues/41)
Implementation: `f9bc0d8` on `ci/41-scope-workflows`.

## Result

Application/native CI, AUR checks, web/docs validation and workflow contracts now have separate path policies.
Website and README PRs avoid native builds. Planning notes and screenshot proofs select no automatic workflow;
requirements metadata remains an explicit contract input. The existing VM policy is retained.

The impact helper reads each workflow's own paths and uses Git event ranges. For a shared-lockfile-only match it
compares reachable application/web importer, snapshot and package metadata. Web-only GSAP changes skip native
validation; shared and transitive changes select affected checks. Uncertain schemas/metadata/history run
conservatively. Ruby/YAML was already required by the repository; there are no new project dependencies/actions.

Docs deployment has web/build/deploy path filters and retains manual/tag runs, its production environment and
serialized concurrency. Its shared-lockfile trigger intentionally remains conservative because deployment installs
the workspace. Validation concurrency occurs after impact selection, avoiding cancellation by irrelevant lockfile
checks. Workflow-contract runs cancel superseded runs of their own lane.

The release audit now requires an actually successful workspace job and check step. A successful scope-only workflow
cannot count as full validation; absent/skipped/failed evidence prints a manual CI dispatch command. Legacy successful
CI remains accepted. Release and AUR publication workflows retain their independent validation gates.

## Changed files and simplifications

- `.github/workflows/ci.yml`: scoped triggers and guarded native validation; original validation steps retained.
- `.github/workflows/aur.yml`, `web.yml`, `workflow-checks.yml`: focused validation surfaces using existing actions.
- `.github/workflows/deploy-docs.yml`: scoped push inputs; corrected the folded condition's trailing newline.
- `scripts/ci-impact.rb`: Git/path/dependency impact decisions, with conservative fallback.
- `scripts/test-ci-impact.rb`, `test-ci-workflow-paths.rb`, `verify-github-workflows.sh`: routing and wiring regression gates.
- `scripts/verify-docs.sh`, `verify-packaging.sh`: three packaging README prose checks moved into docs validation.
- `scripts/audit-final-release-state.sh`, `verify-scripts.sh`: full-CI evidence guard and release-audit regressions.
- Developer CI/architecture/release documentation, unreleased notes and these GSD records: ownership and operator guidance.

No application, audio/backend, package recipe, release publication, branch protection or dependency changes.
The full local `pnpm check` entrypoint remains unchanged.

## Evidence

- 38 temporary-Git/lockfile scenarios pass, including peers/aliases, optional/transitive dependencies, moved base
  branches, initial pushes, renames/deletions, malformed input and unknown-schema fallback.
- 80 committed workflow path/event cases pass, plus job-output, concurrency and operator/deployment wiring checks.
- Actual PR #40 replay through the new policy: application `run=false`, AUR `run=false`, web `run=true`.
- Original native and AUR validation steps are equal as parsed YAML before/after the workflow split.
- 10 release-audit modes pass. The scope-only case failed before the fix because the old audit accepted it.
- The new job-evidence validator accepted real legacy metadata from CI run
  [33961080924](https://github.com/sandwichfarm/loopwire/actions/runs/33961080924).
- `pnpm verify:workflows`, `pnpm verify:requirements`, `pnpm verify:docs`, `pnpm verify:scripts`, and the 11 GitHub
  setup transport tests pass. Actionlint 1.7.12 validates all workflow files; Ruby/Bash syntax and whitespace checks pass.
- `pnpm lint`/typechecks, all 295 workspace tests, exact web-lane type/test commands, production web/docs builds and
  static-site verification pass.
- Review found the missing web requirements check; a failing policy regression was added before fixing the web lane.
  Targeted re-review approved the fix. The deployment condition now uses `>-` and has a whitespace regression guard.

## Limits and operator notes

At initial delivery, native/AUR builds were not rerun locally because their execution steps were unchanged. GitHub event routing is
covered by actual-revision replay and fixture tests; hosted runs will exercise the published workflow definitions.
This CI-definition change itself legitimately selects native/AUR checks. No release, deployment or merge was performed.
GitHub path-diff limits still apply, and globally required path-filtered checks need an appropriate aggregate policy.

## Native proof freshness correction

The full workspace job in [run 33964723801](https://github.com/sandwichfarm/loopwire/actions/runs/33964723801)
exposed a native snapshot freshness failure inherited from master. Comparing the verifier's critical inputs with
the recorded VM-tested commit `70eee4ec433bb7d967931357cf77bd0c28056a35` found only nine added lockfile lines for
the website's GSAP dependency. The application projection was identical; the web projection differed.

The snapshot verifier now delegates only the lockfile comparison to the existing application dependency projection.
The helper's explicit `--verify-lockfile` mode returns 0 for equal inputs, 1 for changed inputs and 2 for uncertainty,
and never writes GitHub workflow outputs. Every other critical-path comparison, snapshot check and ancestry check
is retained. The original proof files and tested commit are unchanged; this does not represent a new VM execution.
Standalone snapshot verification now explicitly requires the existing Ruby/YAML tooling.

Validation of the correction:

- The production snapshot check reproduced the original failure, then verified all four targets after the fix.
- The new 27-case suite runs the real verifier against isolated Git fixtures. The committed old verifier failed its
  GSAP case; the repaired verifier passes. Native/root/shared/transitive dependencies, global settings, unknown or
  malformed locks, missing history, source changes and corrupted/unrelated evidence remain rejected.
- Strict CLI cases verify exit codes and that absent/prefilled `GITHUB_OUTPUT` files remain untouched.
- Existing 38 impact scenarios and the expanded 84 workflow path/event cases pass. The native-proof test and verifier
  are explicit Workflow Contracts inputs, and the suite runs under `pnpm verify:workflows`.
- `pnpm verify:packaging` passes, including native fixture packages and the previously failing snapshot check.
- Node/Ruby syntax, actionlint and whitespace checks pass. A separate review found no path that accepts uncertainty.

The PR records the subsequent full workspace and hosted validation results. No application, recipe or dependency
versions changed, and no stored VM evidence was regenerated or relabeled.
