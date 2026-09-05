# CI by affected files

Automatic validation is split by the inputs it checks. A website or documentation PR no longer starts Tauri checks
or Arch package builds. The full local `pnpm check` command remains available and unchanged.

## Workflow ownership

| Workflow | Automatic inputs | Work performed |
| --- | --- | --- |
| CI | Desktop/core/audio source, runtime and packaging scripts/data, app build configuration | Existing full workspace, native and packaging checks |
| AUR Checks | On PRs: AUR recipes, license, renderer/verifiers and their workflow. On default-branch pushes: also rolling-package application/build inputs | Existing stable and rolling source-package builds |
| Web and Docs | Site/docs sources, product screenshot, README files, web scripts, relevant dependency/config inputs | Web/docs types, documentation requirements/contracts, docs tests and production static build |
| Workflow Contracts | Workflow definitions, routing helpers/tests, automation/requirements verifiers and docs/GitHub setup automation | Workflow policy, requirements, GitHub setup tests and isolated automation fixtures |
| VM Matrix | Existing VM metadata/scripts and support-matrix documentation | VM metadata and handoff checks |
| Deploy Docs | Default-branch changes to website/docs build or deployment inputs | Existing protected static-site build and Bunny deployment |

The exact policies live beside the `pull_request` and `push` triggers in each workflow. There is no second list of
path ownership in the selector. Root README and packaging README edits select web validation; packaging README prose
assertions now belong to the docs verifier. Ordinary planning notes, screenshot proofs, agent instructions and
browser scratch files select no automatic workflow. `.planning/REQUIREMENTS.md` is an explicit contract input.

AUR verification on a PR uses the current recipes/tools but downloads tagged/default-branch application source.
It does not compile PR application edits, so those edits alone do not select AUR on PRs. After merging application
changes, default-branch push validation also exercises the rolling package. Application edits still receive the
native workspace checks on the PR itself.

## Shared dependencies

A shared `pnpm-lock.yaml` edit can start a short impact-check job. Before the application, AUR or web validation
job starts, `scripts/ci-impact.rb` reads that workflow's own event paths. If the lockfile is the only matching file,
it compares the relevant pnpm v9 dependency graph between the two revisions:

- Application: root tools, the desktop importer and packages workspaces, including workspace links.
- Web: root tools, site and docs importers, including their workspace links.
- Each projection includes reachable snapshots, peer-qualified/aliased versions, optional dependencies, package
  resolution metadata and shared lock settings.

A web-only GSAP change therefore skips native work. An application dependency selects application checks; a shared
TypeScript/Vitest or transitive dependency selects every affected surface. Formatting or unreachable lock entries
do not force a rebuild. Unknown schemas, unsupported references/metadata, missing Git history or an unreadable
lockfile run validation conservatively and print a warning.

The parser uses Ruby's existing YAML support and standard library, with no new action or package dependency.
Current workflow patterns use literal paths, `*`, `**` and ordered `!` exclusions. More elaborate patterns need a
matching helper/test update; unsupported syntax conservatively runs validation instead of silently skipping it.

Deploy Docs retains a conservative shared-lockfile trigger because both deployment jobs install the workspace.
Its existing workflow-wide cancellation/production serialization is preserved. Workflows with an impact selector
apply concurrency only to selected validation jobs, so an unrelated lockfile check cannot cancel an active relevant build.

## Events and required checks

PR comparisons use the merge base with the PR head, matching GitHub's cumulative PR semantics. Default-branch
pushes compare the supplied before/after commits. Renames are treated as removal plus addition, and initial pushes
inspect all current files. Adding a docs-only commit to a PR that already changes application code still validates
the whole PR; this is not a last-commit-only shortcut.

Manual runs remain explicit overrides. Scheduled diagnostics and release/operator workflows retain their existing
entrypoints. Release-tag deployments still run: GitHub does not apply path filters to tag pushes.

Release auditing still requires an executed full workspace check, not merely a successful impact-check workflow.
It inspects the successful CI run's `Validate workspace` job and `Run workspace checks` step. A skipped, missing or
failed job/step is rejected. If a future release commit was filtered out, deliberately run CI at that release ref:

```sh
gh workflow run ci.yml --repo sandwichfarm/loopwire --ref <release-tag>
```

Wait for the run to finish before repeating the release audit. Existing successful legacy CI runs still qualify.
The Release workflow continues to run the full `pnpm check` independently; path filtering does not bypass it.

No branch protection or rulesets were changed. The live repository had neither configured when this change was
prepared. If protection is added, do not require every path-filtered workflow unconditionally: GitHub can leave
an absent required check pending. Use an appropriate always-reporting aggregate policy if a universal required
check is desired. See [GitHub's path-filter and diff documentation](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#onpushpull_requestpull_request_targetpathspaths-ignore)
for skipped-check behavior and hosted diff-size limits.

## Verification

`pnpm verify:workflows` runs the YAML/workflow contracts and the two routing suites:

```sh
ruby scripts/test-ci-impact.rb
ruby scripts/test-ci-workflow-paths.rb
```

The first uses temporary Git repositories and real event-shaped payloads to exercise dependency changes, moving
base branches, initial pushes, deletions/renames and conservative fallbacks. The second checks the committed YAML's
path/event routing, helper outputs, job guards, concurrency, retained operator entrypoints and web-only setup.

The actual changes from merged PR #40 were replayed through the selector: native application work was false,
AUR work was false, and web validation was true. This CI-scoping PR itself changes native/AUR workflow definitions,
so those validations are expected to run for its review.
