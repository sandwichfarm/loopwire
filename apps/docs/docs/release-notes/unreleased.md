# Unreleased

These notes describe source-tree progress. They are not a public release announcement.

## Supported In Source

- Contributor source install with `pnpm install` and `pnpm check`.
- Backend detection for PipeWire, PulseAudio compatibility, JACK availability, and ALSA playback/capture visibility.
- ALSA capability detection now probes both `aplay -l` and `arecord -l`, keeps partial playback/capture visibility
  available for diagnostics, and reports route controls as unavailable instead of planned routing support.
- PipeWire source and monitor target pickers can list read-only `pw-link` output/input ports in the desktop shell.
- JACK source and monitor target pickers can list read-only `jack_lsp -p` output/input ports in the desktop shell.
- Dry-run-by-default native PipeWire adapter for linking, verifying, unlinking, and rolling back existing `pw-link`
  ports configured by endpoint host device names.
- Native PipeWire can now create Loopwire-owned virtual output sinks with `pw-cli create-node adapter`, link
  host-backed source ports into them, and destroy those nodes during unload or rollback.
- Native PipeWire can now create Loopwire-owned virtual monitor sinks with `pw-cli create-node adapter`, link output
  monitor ports into them, and destroy those nodes during unload or rollback.
- Native PipeWire route mute now disconnects configured existing links and verification fails if muted links remain
  connected.
- Native PipeWire monitor routing can link output monitor ports to existing physical monitor sink ports.
- Dry-run-by-default native JACK adapter for connecting, verifying, disconnecting, and rolling back existing
  `jack_connect` port routes configured by endpoint host device names.
- Native JACK can resolve app endpoints without host `deviceName` values to deterministic Loopwire-owned JACK port
  names and connect them when those ports already exist.
- Native JACK route mute now disconnects configured existing connections and verification fails if muted connections
  remain connected.
- Dry-run-by-default PulseAudio compatibility adapter for Loopwire null sinks, matched stream moves, and stream-level
  volume/mute controls.
- PulseAudio compatibility now rejects one-source-to-many-output routes before any host mutation, matching its
  stream-level control boundary instead of letting the final stream move silently win.
- PulseAudio compatibility now ignores muted saved fan-out routes when an active route for the same source exists, so
  inactive routing ideas can stay in a configuration without blocking the active stream route.
- PulseAudio backend detection and support-bundle summaries now expose `one output per source` as a known gap, matching
  the runtime and desktop preflight boundary.
- Support bundles can now include read-only DSP provider plan summaries with `--include-dsp-provider-plan`, writing
  `dsp-provider-plan.json` and `support-bundle.json` `dspProvider` metadata without running provider execute mode.
- VM evidence verification now checks the nested support-bundle command ledger, so failed `detect-audio`,
  `ct-host-check`, or `autostart-status` diagnostics cannot pass as VM support proof.
- PulseAudio compatibility verification now fails when a configured route has no matching live stream, instead of
  reporting fake success for an absent app stream.
- PulseAudio startup and background restore now keep absent matching streams pending until those apps launch, without
  weakening normal switch verification.
- Source-checkout PulseAudio background restore can retry pending app-stream routes for a bounded live window without
  recreating the virtual sinks.
- Release tarballs now package a `loopwire --background` launcher with bundled restore assets under
  `libexec/loopwire/`, and package templates install those support files.
- The curl installer now reports whether `node` is available after install, warning raw tarball users before they enable
  Restore on boot or bundled provider commands without the Node.js runtime.
- Loopwire-owned monitor sinks and `module-loopback` links from output monitor sources to those monitor sinks.
- Optional monitor host sink names for routing monitor loopbacks directly to physical PulseAudio-compatible sinks.
- Desktop monitor cards can list detected PipeWire input ports or PulseAudio-compatible playback sinks for physical
  monitor targets, with a manual sink-name override for uncommon host setups.
- Desktop source picker can list detected PipeWire output ports, JACK output ports, or PulseAudio-compatible running
  app streams and keeps static fallback sources when backend stream enumeration is unavailable.
- Desktop output picker can add detected PipeWire/JACK target ports as host-backed outputs and only auto-route existing
  host-backed sources into those native targets.
- Desktop host-apply control with preview mode and session-local live apply routed through an allowlisted Tauri bridge
  for `pactl`, `pw-cli`, `pw-link`, `jack_lsp`, `jack_connect`, and `jack_disconnect`.
- The Tauri host-command bridge now validates command arguments against Loopwire's detector/runtime contract before
  running any live audio command.
- Desktop startup backend detection through the allowlisted Tauri bridge for `pw-cli`, `wpctl`, `pactl`, `jack_lsp`,
  `aplay`, and `arecord`; browser preview keeps packaged fallback candidates.
- First-run backend selection now prompts when multiple detected backends are available instead of treating PipeWire as
  an already persisted choice.
- The desktop backend chooser now renders a first-run callout that names multiple detected backend candidates, keeps
  live apply in preview, and asks the user to save the backend for startup restore.
- The backend chooser now names the stale saved backend when that backend disappears and multiple other backends are
  available, so users know they are replacing a previous startup-restore choice.
- Desktop backend selection now has a dedicated chooser panel that shows selected, available, and unavailable backends,
  explains that the choice is persisted for startup restore, and keeps the active workspace ahead of the sidebar on
  mobile.
- Changing the selected backend now runs a backend-change transaction in preview mode, disarms live host apply, and
  commits the backend as the saved startup-restore choice only after the active configuration verifies.
- Backend-change transactions now keep backend, host-apply, and configuration-switch controls disabled while verification
  is in flight, and stale backend verification results are ignored when a newer selection starts first.
- Automatic single-backend selection now uses the same backend-change transaction path before persisting the detected
  backend for startup restore.
- Editing the active configuration now disarms live apply and tells the user to re-arm before verifying the edited
  routes, endpoints, host bindings, or metadata on the host.
- Background restore now tells users to open Settings > Audio backend and save a verified backend when boot restore
  finds multiple backends or a saved backend is unavailable, instead of failing with a terse backend name.
- The desktop Restore on boot card now blocks new enablement when the saved backend is no longer detected, while keeping
  the selected configuration visible and still allowing an existing restore unit to be disabled.
- Background restore now explains how to recover when the persisted state file is missing, unreadable, corrupt, or
  incompatible: open Loopwire, choose the desired configuration, and enable Restore on boot again.
- Configuration switching and startup restore now show a runtime activity ledger with unload, apply, verify, and
  rollback entries from the actual runtime plan.
- Backend route-control semantics report whether controls are graph-edge, stream-level, link-only, or unavailable.
- Desktop route-control status, route gain locking, live-apply preflight, and the configuration-switch guard now
  consume detected backend mixing semantics instead of hardcoded backend names, so graph-edge-capable reports can
  unlock per-route gain when a live DSP backend exists without a UI/runtime mismatch.
- Desktop live-apply preflight and the configuration-switch guard now block the selected backend when current backend
  detection reports it unavailable, so persisted backend choices cannot arm live apply after that audio system
  disappears.
- Desktop status shows degraded route-control behavior for selected backends, and now names native PipeWire/JACK route
  mute as implemented link disconnect behavior while keeping route gain marked as planned.
- Desktop live-apply preflight now lists every blocker when a configuration has multiple issues, instead of showing
  only the first blocker plus a count.
- Refused live configuration switches now copy every preflight blocker into the runtime activity ledger as failed
  verification evidence, so the failed switch remains actionable after the click.
- The docs home page product screenshot now has descriptive alt text instead of being hidden as decoration, keeping the
  above-the-fold product preview available to assistive technology.
- The final release handoff now prints the operator command that sets final-scope GitHub secrets from the filled local
  env file before the read-only secret audit, without printing or committing secret values.
- Native-backend live-apply preflight now names routes blocked by non-100% gain and provides a `Reset gains` action
  that restores affected routes to 100% without touching host audio.
- Native-backend non-100% gain blockers now explain both repair paths: reset affected route gains to 100%, or switch
  to a graph-edge/DSP-capable backend when one is available.
- Native PipeWire/JACK live apply now allows muted routes to retain saved non-100% gain values, because those native
  adapters disconnect muted links/connections instead of applying route gain.
- Native PipeWire/JACK route gain sliders now lock when those link-only backends are selected, while route mute and
  `Reset gains` remain available.
- Native-backend live-apply preflight now names missing PipeWire source bindings so the next repair is explicit.
- Native JACK apply now probes existing deterministic Loopwire-owned port names for app-only route inputs, route
  outputs, and monitor paths, then fails before `jack_connect` when those ports are missing.
- Desktop JACK live-apply preflight now blocks unbound JACK route and monitor endpoints before arming, so missing
  JACK port bindings are repairable without a failed host mutation attempt.
- Native JACK port requirements now come from a shared audio-host helper that exposes the deterministic Loopwire-owned
  client names and suggested channel ports used by the runtime adapter.
- Native JACK runtime failures, `pnpm jack:verify`, and support bundles now use the same readiness matcher, including
  matched and missing ports for each requirement.
- Native JACK apply can now call an injected JACK virtual port provider for missing Loopwire-owned ports and re-probe
  `jack_lsp` before connecting. Release artifacts now include `loopwire-jack-ports`, a provider wrapper that records
  the provision plan and fails closed unless delegated to a live JACK client provider.
- Background restore now accepts `--jack-provider-command`, which wraps that command as the injected JACK virtual port
  provider and passes stable `ensure --configuration-id ... --requirement ... --port ...` arguments.
- The autostart helper now renders background systemd units with `--state-file`, `--mode`, retry options, and
  `--jack-provider-command` so source-checkout and packaged boot restore use the same runtime contract.
- `@loopwire/core` now has a pure DSP mix planner/renderer plus an injected source/output cycle runner that applies
  per-edge gain and mute to supplied source buffers, including one source routed to multiple outputs, without claiming
  live host DSP insertion yet.
- `@loopwire/audio-host` now has an injected DSP graph adapter that dry-runs source/output plans, renders and writes
  buffers through supplied ports, verifies rendered outputs through a supplied verifier, clears outputs during unload,
  restores the rollback configuration through the core switch transaction contract, and exposes a first-class configuration runtime adapter wrapper
  for startup re-apply without touching live PipeWire or JACK state.
- `@loopwire/audio-host` now also exposes a command-backed DSP provider helper with stable `read-source`,
  `write-output`, `verify-output`, and `clear-output` operations. Source buffers are read as JSON stdout, and rendered
  output buffers are sent as JSON stdin for provider write and verify commands.
- Command-backed DSP verification now fails closed when `verify-output` exits successfully but emits no JSON result, so
  live provider integrations must explicitly prove rendered output comparison instead of relying on exit code alone.
- Command-backed DSP provider writes, verifies, and clears are now scoped by configuration id, preventing stale rendered
  output from one configuration from satisfying another configuration that reuses the same output id.
- Background restore now supports explicit `--backend dsp` with `--dsp-provider-command`, and release artifacts now
  install `loopwire-dsp-provider`, a bundled file-backed provider for local preflight and restore-contract smoke. It
  does not yet capture or inject live PipeWire/JACK streams. Live DSP restore now requires `--dsp-provider-mode live`,
  and restore now probes provider `capabilities` for `supportsLiveGraph:true`, so file-backed preflight cannot be
  mistaken for a live audio provider.
- Persisted `selectedBackend: "dsp"` state now survives core restore, and source-checkout background restore rejects
  live DSP startup until an explicit `--dsp-provider-command` and live provider mode are supplied after backend
  resolution.
- Live DSP provider preflight now also requires the provider `capabilities.operations` list to include `read-source`,
  `write-output`, `verify-output`, and `clear-output`, so restore cannot arm against a provider that cannot verify or
  roll back Loopwire-owned outputs.
- `pnpm dsp:plan` and `pnpm dsp:verify` now describe and exercise the command-backed DSP provider contract before a
  user enables provider-backed boot restore. `pnpm dsp:verify -- --require-live-capability` now probes provider
  `capabilities` and fails unless the provider declares `supportsLiveGraph:true`.
- `pnpm dsp:verify` now clears rendered provider outputs after execute-mode verification and fails if cleanup fails,
  so live-provider preflight covers the same `clear-output` path startup restore depends on.
- `pnpm jack:ports` can print JACK port requirements from a configuration export or persisted state as JSON or TSV,
  giving pro-audio users a read-only session-template handoff.
- `pnpm jack:verify` can compare those JACK requirements against live `jack_lsp` output or a saved port-list fixture
  before users arm native JACK live apply.
- Support bundles can include read-only JACK readiness by passing a Loopwire configuration export or persisted state,
  writing `jack-port-requirements.json` and a parsed `jack` manifest summary.
- Desktop live-apply preflight rules are now covered by focused regression tests, including no-backend, ALSA,
  PulseAudio, native PipeWire, native JACK blocker behavior, and selected-backend capability lookup for the
  configuration-switch guard.
- `pnpm verify:desktop-preview` can build the desktop app, start a Vite preview, drive system Chromium through CDP,
  capture desktop/mobile screenshots, and verify the hidden-monitor recovery tray has no horizontal overflow.
- Configuration CRUD, source-picker additions, output-bus additions, monitor additions, import/export, persistence
  migration, and startup re-apply through the app runtime contract.
- Desktop configuration switching is now serialized so in-flight switch, create, duplicate, import, and delete actions
  cannot let stale async runtime results replace the latest selected configuration.
- Desktop route lane now creates and removes individual source-to-output edges, while preserving one route per
  source/output pair and independent per-edge gain/mute state.
- Desktop source, output, and monitor cards now support endpoint removal. Source/output removal prunes dependent routes,
  monitor removal clears hidden-monitor state, and the last output remains protected.
- Desktop source and output cards now support manual host binding fields for PipeWire/JACK ports or PulseAudio stream
  tokens that are not listed by backend enumeration.
- Monitor visibility is now scoped per configuration, so hiding a monitor in one workspace does not hide same-id
  monitors in other workspaces.
- Hidden monitor cards now move into a compact recovery tray with `Show` actions instead of staying dimmed in the main
  monitor grid.
- The hidden monitor recovery tray now adds `Show all` when multiple monitors are hidden in the active configuration.
- Desktop custom chrome now persists as a preference and requests an undecorated Tauri window before showing
  Loopwire-owned drag, minimize, maximize/restore, and close controls; the chrome setting is now a native-first
  segmented control with explicit fallback-mode copy.
- Desktop chrome now defaults to Auto: Loopwire prefers desktop or window-manager decorations in the desktop shell and
  shows fallback controls when decoration control is unavailable.
- Desktop settings now groups audio backend selection, host-apply arming, window chrome, and restore-on-boot controls
  in one operational panel instead of scattering persistent preferences across the routing toolbar.
- The public docs product screenshot now reflects the Settings panel, so the homepage preview matches the current
  desktop shell instead of the older topbar-only backend/chrome controls.
- Desktop sidebar start-on-boot control for XDG autostart status, enable, and disable, plus CLI helper fallback.
- Desktop sidebar restore-on-boot control for a user-scoped systemd unit that runs packaged background restore without
  opening the GUI.
- Desktop restore-on-boot now resolves the packaged `loopwire` launcher from `loopwire-gui` before writing systemd
  units, and refuses to install a broken GUI-binary `--background` unit when the launcher is missing.
- Restore-on-boot status now stays readable when the packaged background launcher is missing or fails
  `loopwire --background --help`, marks the action blocked, and still allows removal of an already-installed user unit.
- Restore-on-boot now names the active configuration and saved backend in the desktop sidebar before writing the
  user-scoped background service.
- Source-checkout background restore runner reads the Tauri-written state file and verifies the selected configuration
  through dry-run or explicit live backend adapters.
- Local release artifact packaging, checksum signing, installer smoke, AUR package smoke, and VM target metadata
  validation.
- Published-release verification can now run against a local signed release directory in CI and rejects tampered
  tarballs before the live GitHub Release smoke path is available.
- Release workflow now has x86_64 and AArch64 Linux build lanes, with a single publish job that signs one combined
  `SHA256SUMS` manifest before creating or updating the GitHub Release.
- Release workflow manual dispatch now checks out the resolved tag in detached mode before build and publish work, so a
  manual release cannot package the default branch for a different tag.
- Release workflow readiness now keeps tag verification enabled after the detached checkout, so the build lane also
  checks that the selected tag points at the checked-out source.
- Release workflow and readiness checks now reject non-semver or path-like release tags before deriving release-note,
  evidence-directory, or archive paths from the tag.
- Release evidence collection and verification now enforce the same tag rule, rejecting path-like manifest or expected
  tags before final release evidence can pass.
- Release readiness, published-release verification, and release evidence tools now reject repository values that are
  URLs or extra path segments instead of plain `OWNER/REPO`.
- Release evidence bundles now record the offline release-readiness check and the strict publish preflight log
  separately, so current external blockers can be attached without failing rehearsal evidence collection.
- Release evidence manifests now expose parsed `release.findings` and `release.blockers` from the readiness log, plus a
  log-summary mode for checking preflight blockers without rerunning release checks.
- Release signing key preparation helper that refuses repo-local private keys and verifies the generated key pair before
  printing the GitHub secret setup command.
- GitHub secret checks now fail with the underlying `gh secret list` error when repository secret names cannot be read,
  instead of misreporting API or auth failures as missing release/deploy secrets.
- GitHub secret checks now support `--scope deploy` for Bunny.net upload readiness separately from the default strict
  final-proof scope.
- The GitHub secret helper now enforces scope-complete inputs before set or dry-run output: deploy scope requires the
  Bunny.net upload pair, while final scope also requires the pull-zone hostname plus matching release private/public
  key files before any `gh secret set` call can run.
- GitHub secret checks and release readiness now accept a names-only `--secret-list-file` artifact, so final-proof
  secret blockers can be replayed deterministically without a live `gh secret list` call or any secret values.
- The repo now includes `scripts/fixtures/github-secret-list-final.tsv`, a names-only final-proof secret-list fixture
  that `verify:scripts` runs through `setup-github-secrets.sh --check --scope final` to keep offline release handoff
  rehearsal value-free and reproducible.
- New `pnpm release:handoff` renders the no-side-effect release operator plan, including secret checks, workflow
  dispatch commands, docs deployment proof download, VM evidence collection, VM evidence asset prep, and final-proof
  dry-run commands.
- `pnpm release:handoff` and `pnpm release:status` can now read the local release secret env file for safe handoff
  fields, while ignoring Bunny storage credentials so access keys do not appear in rendered command plans.
- `pnpm release:handoff` now preserves that env file in the rendered secret-check, docs proof fetch, and VM evidence
  asset-prep commands, so operators do not have to copy env-derived release key paths into separate flags unless they
  are intentionally overriding them.
- `pnpm release:handoff` now starts with an `Operator-deferred after agent delivery` section and prints the
  `--write-env-template /secure/loopwire-release-secrets.env` command, separating repo-ready automation from later
  operator-only secret entry, workflow dispatch, VM execution, and signed evidence upload.
- New `pnpm release:agent-ready` verifies repo-side release readiness and handoff rendering without secrets or GitHub
  mutations, then reminds operators that strict final proof still requires published release assets, Bunny deployment
  proof, final-proof workflow success, and VM evidence from operator-controlled hosts.
- `pnpm release:agent-ready` now includes the read-only DSP provider graph-edge plan in its default local gates, so
  release handoff cannot skip the current gain/mute proof surface by accident.
- `pnpm release:agent-ready -- --require-hosted-checks` now filters hosted CI and Deploy Docs workflow lookups by the
  exact release commit before the operator-deferred ceremony continues, so newer unrelated runs cannot mask the target
  SHA's proof state.
- `pnpm release:agent-ready` now requires a clean checkout by default, keeping the rendered handoff tied to the exact
  `--git-head`; local development rehearsals must opt into `--allow-dirty`.
- `pnpm release:agent-ready` now also requires the current checkout `HEAD` to equal `--git-head` by default; fixture
  rehearsals that intentionally use a synthetic SHA must opt into `--allow-head-mismatch`.
- `pnpm release:agent-ready --help` now describes hosted checks as commit-scoped, matching the enforced
  `--require-hosted-checks` behavior.
- `pnpm release:agent-ready -- --require-docs-deployment-artifacts` can now require the commit-scoped Deploy Docs run
  to expose both docs proof artifacts (`loopwire-docs` plus `loopwire-docs-deployment`) after Bunny deployment secrets
  are configured.
- New `pnpm release:fetch-docs-proof` downloads the Deploy Docs `loopwire-docs` and
  `loopwire-docs-deployment` artifacts, then verifies the non-dry-run manifest against the expected commit before
  `pnpm release:status` consumes it.
- `pnpm release:fetch-docs-proof` now stages downloads and manifest verification before replacing local proof paths, so
  a missing deployment artifact cannot leave partial docs proof behind.
- `pnpm release:fetch-docs-proof` now accepts `--env-file` for missing-deployment-artifact recovery hints, preserving
  the same local secret-file setup path without reading or printing secret values.
- `pnpm release:fetch-docs-proof` now rejects unsafe docs dist, deployment manifest, and env-file paths before it
  rewrites local proof outputs or renders Bunny secret recovery commands, including traversal, URL syntax, glob syntax,
  symlinks, and existing paths with the wrong artifact type.
- New `pnpm release:select-docs-run` finds a completed successful Deploy Docs run for the expected commit that exposes
  both docs proof artifacts, and `pnpm release:handoff` now reuses that selected run id across docs proof fetch, final
  proof dispatch, and final status instead of asking operators to manually replace a placeholder.
- `pnpm release:status` now uses the same artifact-aware Deploy Docs run selector when no run id is pinned, so missing
  manifest recovery and the embedded handoff cannot use a workflow run that lacks the docs proof artifacts.
- `pnpm release:status --docs-deployment-run-id` now verifies that the pinned Deploy Docs run exposes both docs proof
  artifacts before reusing that id in missing-manifest recovery or the embedded final handoff.
- `pnpm release:handoff` now rejects absolute or parent-traversal VM handoff output paths before rendering VM SSH plan
  and runbook commands.
- VM evidence asset preparation now rejects unsafe custom `--release-dir` values before dry-run or execution, including
  parent traversal, URL syntax, glob metacharacters, symlinks, and file paths that could redirect checksum regeneration.
- VM evidence asset preparation now rejects unsafe env-file, private-key, public-key, and evidence-root paths before
  reading local release artifacts or rendering the signed VM evidence handoff.
- Final release proof dry-runs now reject unsafe local `--release-dir` values before rendering a signed-release proof
  plan, including traversal, root/home-expanded paths, URL syntax, glob metacharacters, symlinks, and file paths.
- Final release proof now validates local public-key, release-evidence, docs deployment manifest, VM evidence root, and
  support-matrix paths before dry-run rendering or execution, rejecting traversal, URL-like values, glob syntax,
  symlinks, and wrong artifact types before reading proof claims.
- `pnpm release:status` now preserves `--env-file` in its generated `pnpm release:fetch-docs-proof` recovery command
  when the docs deployment manifest is missing.
- `pnpm release:status` now rejects unsafe local env-file, secret-list, docs, VM evidence, and support-matrix paths
  before auditing final proof surfaces, including traversal, root/home-expanded paths, URL syntax, glob metacharacters,
  symlinks, and wrong existing file/directory types.
- `pnpm release:status --env-file` now keeps the default release public-key path implicit in its embedded VM evidence
  asset-prep handoff, while still rendering `--public-key` when the operator supplies that override explicitly.
- `pnpm release:status` now filters CI, Deploy Docs, and Final Release Proof workflow lookups by the expected release
  commit before final release status can pass, keeping release handoff tied to the same hosted proof surfaces used on
  pushes and final-proof dispatches.
- New `pnpm release:status` audits the remaining final proof surfaces from one read-only command and exits nonzero
  until GitHub secrets, a non-draft/non-prerelease release with required assets, completed successful workflow runs for
  the expected commit, a parseable release signing public key, non-dry-run docs deployment manifest proof, VM evidence,
  and support-matrix proof are present.
- Release readiness now rejects local or remote release tags that do not point at the current checkout commit, preventing
  stale tag preflights from looking publishable.
- Release readiness now requires a clean git checkout by default, while release evidence collection opts out with
  `--skip-clean-git` for its offline readiness command so work-in-progress evidence can still record its source state.
- Docs deployment now uses a reusable Bunny.net upload helper with dry-run verification, checksum headers, and optional
  regional storage endpoint support through `BUNNY_STORAGE_ENDPOINT`.
- The docs deployment workflow and GitHub secret helper now pass optional `BUNNY_REMOTE_PREFIX` through to Bunny.net
  uploads for storage zones that serve multiple paths.
- The Bunny.net docs deploy helper can now write a non-secret `loopwire.docs-deployment.v1` manifest, and the docs
  deploy workflow uploads it as the `loopwire-docs-deployment` artifact after successful Bunny uploads.
- New `pnpm verify:docs-deployment` verifies that deployment manifest against the built docs dist before artifact
  upload, including file inventory, SHA-256 checksums, remote-prefix paths, and secret-like key rejection.
- Docs deployment manifests now record the source git head, and final release proof rejects manifests that do not match
  the requested release commit.
- Release readiness now fails if the docs deployment manifest verifier is missing, unparsable, absent from
  `package.json`, or not wired into the docs deploy workflow before the manifest artifact upload.
- Release readiness now fails if the final release proof workflow, `pnpm verify:final-release`,
  `pnpm vm:package-evidence`, or `pnpm vm:prepare-release-evidence` wiring disappears before the release handoff.
- The v0.1.0 release notes are now publication-ready copy, and agent-ready release checks no longer use
  `--allow-candidate-notes`, so candidate wording cannot slip back into the tag handoff.
- Release evidence collection no longer uses `--allow-candidate-notes` for its offline readiness command, so evidence
  bundles also fail if versioned notes regress to candidate-only wording.
- The GitHub secret helper now rejects Bunny storage zones, endpoints, pull-zone hostnames, and remote prefixes that
  would later fail the docs deploy or live-smoke helpers.
- The GitHub secret helper can now validate the release private key against the release public key before dry-run or
  secret writes, rejecting invalid or mismatched signing material.
- The GitHub secret helper now writes secrets through the current `gh secret set` stdin contract, avoiding the removed
  `--body-file` flag while keeping secret values out of command arguments and logs.
- The GitHub secret helper check now prints no-value next steps when required release/docs secrets are missing and
  explains when the docs workflow can upload to Bunny.net but will skip live-docs smoke.
- The GitHub secret helper check now scopes missing-secret next steps to the actual missing class, so a repository that
  already has `LOOPWIRE_RELEASE_PRIVATE_KEY` but lacks Bunny.net secrets no longer gets release-key reset guidance.
- The GitHub secret helper check is now split into smaller required-secret, optional-secret, missing-class, and
  next-step helpers while preserving the same no-value check output.
- Release readiness now prints no-value next steps for missing Bunny secrets and missing release tags, including the
  guarded `git tag -a <tag>` and `git push origin <tag>` commands only after required secrets are configured.
- Release readiness and the GitHub secret helper now require `BUNNY_PULL_ZONE_HOSTNAME` for final proof, because the
  published release ceremony must prove the live docs deployment and public installer from the Bunny pull-zone URL.
  The helper can set that hostname by itself when Bunny storage credentials are already configured.
- `scripts/setup-github-secrets.sh --check --scope deploy` now has regression coverage for the optional
  `BUNNY_PULL_ZONE_HOSTNAME` path, proving deploy-scope checks report post-upload live-smoke readiness without requiring
  the release signing secret.
- The Bunny.net docs deploy helper now fails closed when the built dist omits `index.html` or the public `install.sh`,
  and rejects unsafe remote-prefix path segments before upload planning.
- The docs deployment workflow now runs a live pull-zone smoke with `scripts/verify-docs-live.sh` when
  `BUNNY_PULL_ZONE_HOSTNAME` is configured, verifying the deployed homepage and public installer after upload.
- The docs deployment live smoke now forwards `BUNNY_REMOTE_PREFIX`, so prefixed Bunny.net deployments verify the same
  path that received the uploaded VitePress site.
- Published release verification now rejects release directories missing either canonical Linux tarball
  (`loopwire-linux-x86_64.tar.gz` or `loopwire-linux-aarch64.tar.gz`) before a release can be called installable.
- Release evidence collection can now include published-release installer smoke as optional full-profile evidence, or
  require it with `--require-published-release` for final release proof after GitHub assets exist.
- Final release evidence verification now rejects fake `published-release-smoke` rows unless they executed
  `scripts/verify-published-release.sh` with the manifest repo, tag, and public key.
- Final release evidence verification now rejects `published-release-smoke` rows that include `--release-dir`, so local
  staged artifacts cannot satisfy final proof that must come from the GitHub Release surface.
- Final release evidence verification can now require a specific signing public key with `--public-key`, and
  published-release evidence archive checks pass through the same key used to verify signed release assets.
- Final release evidence verification can now require the resolved release tag commit with `--git-head`, and the release
  workflow passes that SHA into the evidence verifier and published-release archive verifier.
- New `pnpm verify:final-release` command composes the final public proof gate across signed release assets, live docs,
  final release evidence, every VM target bundle, support-matrix promotion, and docs verification.
- The support-matrix verifier can now require installed-release smoke with `--require-published-release`, and the final
  release proof wrapper uses that stricter mode for `Verified` rows.
- The support-matrix verifier now validates custom `--matrix` and `--evidence-root` paths before reading promotion
  claims, rejecting symlinks, traversal, URL-like values, glob metacharacters, root/home placeholders, and wrong
  existing file/directory types.
- Release evidence collection can now require verified VM evidence with `--require-vm-evidence`, including guest
  installed-release smoke when `--require-published-release` is also enabled.
- Release evidence collection now records a read-only `dsp-provider-plan` row in the full profile, and final release
  proof requires `--require-dsp-provider-plan` so the command-backed DSP provider contract cannot disappear from the
  public evidence bundle.
- Final release evidence now binds `dsp-provider-plan.tsv` rows to the configured routed sources and outputs, rejecting
  placeholder DSP provider rows that do not match the manifest-bound configuration.
- Final release DSP provider evidence now also requires `clear-output` rows for configured outputs, so release proof
  covers the same rollback/unload operation required by live DSP restore.
- Release tarballs, the curl installer, AUR metadata, and Nix metadata now expose `loopwire-dsp-provider` beside the
  main `loopwire` launcher.
- Release evidence collection and verification can now require live docs smoke with `--require-live-docs`, binding final
  release evidence to the deployed homepage and public installer.
- Final live-docs evidence now must match the `docsLive` base URL or hostname plus remote prefix recorded in
  `release-evidence.json`, so a green smoke against the wrong deployment cannot satisfy final release proof.
- Release evidence collection can now expand `--vm-target all` across all declared VM matrix targets for final
  cross-system release proof.
- Final release evidence can now require `vm-launch-plan.tsv`, validating matrix-wide dry-run launch rows and paired SSH
  evidence-pull commands before public release proof passes.
- New `pnpm verify:release-evidence` command to verify final release evidence bundles, including required published
  release smoke, all VM targets, non-empty logs, and blocker-free readiness.
- The release workflow now collects, verifies, attaches `loopwire-release-evidence-<tag>.tar.gz` to the GitHub Release,
  and uploads a matching workflow artifact after the publish smoke passes.
- The release workflow now re-signs `SHA256SUMS` after evidence collection so
  `loopwire-release-evidence-<tag>.tar.gz` is covered by the same signed checksum manifest as the installable tarballs.
- A manual `Final Release Proof` workflow now downloads release and VM evidence archives from the GitHub Release,
  checks the tag commit, verifies live docs, and runs the same final proof script used locally.
- The final release proof workflow now downloads signed `SHA256SUMS` files and verifies both release and VM evidence
  archives are checksum-bound before extraction.
- The final release proof workflow now validates downloaded release and VM evidence tarballs with
  `scripts/extract-safe-tar.sh` before extraction, rejecting unsafe member paths or link entries before project-specific
  evidence verification runs.
- The final release proof workflow now defaults its live-docs hostname and remote prefix from
  `BUNNY_PULL_ZONE_HOSTNAME` and `BUNNY_REMOTE_PREFIX`, so the required secret setup feeds the final proof run without
  retyping the pull-zone hostname on every manual dispatch.
- The final release proof workflow now validates custom release and VM evidence asset names before download, rejecting
  path traversal, URL-like names, glob patterns, wrong evidence-kind prefixes, and tag mismatches.
- Final release proof dry-runs can now write the exact command plan to a `--plan-output` file for release handoff
  review without touching GitHub, Bunny.net, release assets, docs URLs, or VM evidence.
- Final release proof plan-output files must now stay under `dist/release/`, and the verifier rejects absolute paths
  or `.`/`..` traversal before writing release handoff artifacts.
- Final release proof dry-runs now include the `pnpm vm:prepare-release-evidence` handoff, including VM evidence
  packaging, signed `SHA256SUMS` refresh, signed-checksum verification, and the matching `gh release upload --clobber`
  command before the manual proof workflow.
- New `pnpm vm:package-evidence` command packages verified VM bundles into
  `loopwire-vm-evidence-<tag>.tar.gz` with the `vm-evidence/<target>` layout expected by final release proof.
- `pnpm vm:package-evidence` now validates custom output basenames against the tag-bound VM evidence release asset
  naming contract before writing archives.
- New `pnpm vm:prepare-release-evidence` command prepares that VM evidence tarball inside a release directory,
  regenerates and re-signs `SHA256SUMS`, verifies the archive entry, and prints the exact GitHub upload command.
- `pnpm vm:prepare-release-evidence` can now read release signing key paths from the local release env file, matching
  the secret setup and final handoff ceremony while ignoring Bunny storage credentials.
- VM evidence packaging now validates the completed tarball with `scripts/extract-safe-tar.sh`, so unsafe archive
  members fail before the archive is attached to a public release.
- Published release verification can now require that public evidence archive with `--require-release-evidence`, extract
  it, and reject archives with missing published-release smoke or blocker findings.
- Published release verification now supports `--require-github-release-source`, and final release proof passes it so
  local `--release-dir` smoke cannot satisfy public release proof.
- Published release evidence archive verification now binds the manifest to the expected `release.tag` and repo. It
  rejects unsafe archive paths before extraction, rejects link members with `scripts/extract-safe-tar.sh`, and rejects
  manifest command logs that escape the evidence directory or resolve through symlinks.
- `pnpm release:status` now downloads the public `loopwire-release-evidence-<tag>.tar.gz` asset, verifies its signed
  checksum entry, safe-extracts it, and rejects release-evidence manifests that do not match the selected
  tag/repo/commit before final proof can be marked ready.
- `pnpm release:status` now resolves the GitHub tag ref, including annotated tags, and rejects releases whose tag does
  not point at the expected `--git-head` commit.
- Final release proof now runs the same live GitHub tag-ref check before published-release downloads, so the manual
  proof workflow rejects a release whose `refs/tags/<tag>` no longer resolves to the expected commit.
- Local release-directory verification now derives the expected evidence tag from the single
  `loopwire-release-evidence-<tag>.tar.gz` asset when `--tag` is omitted, rejecting archive-name and manifest tag drift.
- Release evidence verification now validates source-state metadata such as `git.head` and `git.statusShort`, and final
  bundles can require a clean checkout with `--require-clean-git`.
- Release evidence verification now rejects malformed VM evidence manifest rows, including unknown or duplicate target
  ids, unsafe `evidenceDir` paths, and VM command rows that do not invoke the matching VM evidence verifier target.
- Release evidence verification now tokenizes final proof command rows, rejecting echo-disguised published-release,
  live-docs, or VM evidence commands that only print the expected verifier path.
- Product requirement verification now runs in `pnpm check`, keeping the v1 UX, backend, Linux integration, docs, and
  quality checklist tied to source, docs, workflow, and packaging evidence while leaving SHIP proof pending.
- Redacted support bundle collection for user bug reports and cross-system compatibility triage.
- Support bundle manifests now summarize detected backend availability, route-control scope, per-edge gain/mute flags,
  diagnostics, and known gaps from `detect-audio.json`.
- VM evidence verification now requires a successful guest command ledger and nested redacted support bundle, so support
  claims cannot rely on file presence alone.
- VM evidence collection now starts the Loopwire desktop shell, records `desktop-launch.log`, and requires a successful
  `desktop-launch` ledger row before support claims can be promoted.
- VM evidence verification now rejects tiny placeholder screenshots; `screenshot.png` must include PNG header
  dimensions of at least 320x200 before a target can be promoted.
- VM evidence collection can now run published-release installer smoke inside the guest and `verify-vm-evidence` can
  require that installed-release proof for final release gates.
- VM evidence now writes `published-release.json`, and final release proof can require the VM bundle to match the exact
  release tag instead of accepting any successful published-release smoke log.
- Final VM evidence checks now require `published-release.json` to record GitHub release source, so guest-visible local
  release directories cannot satisfy public support evidence for a published tag.
- VM evidence promotion now has a guarded `pnpm vm:promote-evidence` command that verifies target evidence before
  changing a support-matrix row from `Manual VM` to `Verified`.
- VM evidence promotion can now require published-release smoke, so final public support rows cannot be promoted from
  source-checkout-only guest evidence.
- VM evidence promotion can now run in `--all` mode to promote every verified target-scoped evidence bundle while
  reporting missing targets and failing invalid bundles.
- New `pnpm vm:evidence-status` command reports missing, invalid, and verified evidence bundles across the VM matrix,
  with optional `--require-published-release` strictness for final public release proof.
- `pnpm vm:evidence-status` can now take `--release-tag` with published-release strictness, so operators can inventory
  VM proof for the exact release before promoting support-matrix rows.
- `pnpm vm:evidence-status` now prints target-specific SSH collection ports from the same `--start-port` convention as
  `pnpm vm:render-ssh-plan`, so multi-VM proof handoffs no longer repeat port `2222` for every missing target.
- `pnpm release:status` now uses the same VM evidence start-port default as the final release handoff, and exposes
  `--vm-start-port` when an operator chooses a different forwarded-port range.
- `pnpm release:status` now threads the verified commit-scoped Deploy Docs workflow run id into the final release
  handoff, so the docs proof fetch and final proof dispatch commands no longer fall back to a placeholder after a
  successful docs run for the release commit.
- `pnpm release:status` now reuses the already verified Deploy Docs run id when printing missing-manifest recovery,
  avoiding a second unverified run lookup for the docs proof fetch command.
- `pnpm release:status` now keeps its fallback missing-manifest docs proof run-id hint scoped to an artifact-bearing
  Deploy Docs run for the expected release commit, so recovery commands cannot point at a newer unrelated or
  artifact-incomplete docs workflow run.
- `pnpm release:status` can now audit a pinned Deploy Docs run with `--docs-deployment-run-id`, keeping final proof
  rehearsals tied to the operator-selected docs deployment instead of the commit-scoped workflow lookup.
- `pnpm release:status --vm-evidence-root` now passes the selected evidence root into support-matrix verification, so
  promoted support rows are checked against the same copied-back VM evidence bundle path as the matrix status gate.
- Pinned Deploy Docs release-status audits now label the evidence as the selected run, avoiding latest-run wording when
  an operator intentionally audits a specific workflow run id.
- `scripts/setup-github-secrets.sh` now accepts `--env-file` for local uncommitted Bunny.net values and release key
  file paths, with command-line flags taking precedence and dry-run output still hiding secret values.
- `scripts/setup-github-secrets.sh` now rejects unsafe local env-file, secret-list, release private-key, and release
  public-key paths before reading those artifacts during the release secret ceremony.
- Missing Bunny secret checks now print the `--write-env-template <secret-env-file>` and
  `--env-file <secret-env-file>` setup route alongside direct placeholder flags, making the safer local-file ceremony
  visible at the exact release blocker.
- `.env.example` now mirrors every `--env-file` key accepted by the GitHub secret helper, so operators have a checked
  key-name template without committing secret values.
- The GitHub secret helper can now print the same no-value env-file template with `--print-env-template`, keeping the
  local release-secret ceremony available from the script itself.
- The GitHub secret helper can now create the local release-secret env template with `--write-env-template`, refusing
  existing files and writing the no-value template with `0600` permissions.
- The Deploy Docs workflow now prints the same safe `--write-env-template /secure/loopwire-release-secrets.env` and
  `--env-file /secure/loopwire-release-secrets.env` recovery commands when Bunny.net upload secrets are missing, plus
  the `BUNNY_PULL_ZONE_HOSTNAME` reminder needed for final live-docs proof.
- JACK live port delegation now preserves the process environment while applying Loopwire-specific overrides, so
  provider scripts that use `/usr/bin/env node` keep resolving Node on CI and operator hosts.
- VM evidence collection now writes `environment.json`, and verification rejects bundles whose observed distro,
  desktop/session, or architecture do not match the selected target row.
- Host-side SSH VM evidence collection can run the guest collector, copy target evidence back, and verify the bundle
  without changing support-matrix rows prematurely.
- Direct SSH VM evidence collection now rejects unsafe custom remote and local output paths before dry-run or execute
  mode, including parent traversal and paths that omit the target id as a path segment.
- Host-side matrix VM evidence collection can expand a TSV guest plan into target-scoped SSH collectors for several
  reachable systems while staying dry-run-first.
- Matrix VM evidence collection now rejects unsafe local output paths, including parent traversal and paths that do not
  include the target id as a path segment.
- Matrix VM evidence collection can now require all `vm/targets.tsv` rows with `--require-all-targets`, failing a
  final-release collection plan before SSH runs if any target was omitted.
- VM matrix planning can now generate that target-scoped SSH TSV with unique forwarded ports, so multi-system guest
  passes do not start from hand-authored rows.
- VM host planning now prints cross-distro virtualization setup hints, operator-owned image policy, target-specific
  render commands, launch dry runs, and SSH evidence handoff commands.
- VM host setup now has a dry-run-only `pnpm vm:host-setup` command that prints one package-family install command and
  the matching post-install `vm:doctor` verification command.
- VM host setup now supports `--all`, printing the all-target QEMU tool requirements and the matching `doctor --all`
  verifier without installing packages.
- VM host setup hints are now architecture-scoped, so Fedora and openSUSE all-target setup includes the AArch64 QEMU
  packages required by the Ubuntu AArch64 VM target.
- VM launch dry-runs now stay non-mutating: they print the planned QEMU command and `.vm/run` paths without requiring
  the image path to exist, rendering cloud-init, or writing VM state.
- New `pnpm vm:launch` command exposes those dry-run-first QEMU launch plans alongside the rest of the VM matrix
  workflow.
- New `pnpm vm:render-launch-plan` command emits target-scoped launch and evidence-pull rows for all VM targets, with
  deterministic SSH ports and operator-owned image placeholders.
- New `pnpm vm:render-runbook` command emits a markdown VM evidence runbook with host setup, launch, SSH evidence,
  verification, support-matrix promotion, and AArch64 firmware handoffs.
- The final release handoff now prints `pnpm vm:host-setup -- --all` and `pnpm vm:doctor -- --all` before VM SSH
  planning and evidence collection, so host virtualization readiness is explicit before operator-run guests.
- VM evidence runbooks now include the final-release `pnpm vm:collect-matrix` command with published-release smoke and
  all-target strictness, so operator handoffs do not silently collect source-checkout-only support evidence.
- VM evidence collectors now forward `--require-github-release-source` through direct guest, SSH, and matrix collection
  paths, so final support bundles fail early when published-release smoke uses a guest-visible local directory.
- VM launch now supports `--ssh-port` and prints the matching evidence-pull command, so operators can run or plan
  multiple guest targets without hardcoding host port `2222`.
- VM launch planning now rejects invalid memory, CPU count, SSH port, and backing image-format values before printing
  or executing a QEMU command.
- VM evidence collectors now reject invalid SSH and desktop smoke ports before touching SSH, Vite, or guest evidence
  commands.
- VM doctor now treats `cloud-localds` as a required launch preflight, matching the launch path that creates cloud-init
  seed media only after `--execute`.
- VM doctor now supports `--all` for a non-mutating matrix-wide host preflight that prints `target-check=*` blocks and
  exits nonzero when any target's architecture-specific launch prerequisites are missing.
- VM cloud-init rendering can now generate guest bootstrap assets for every target in one command.
- VM matrix verification now renders and checks cloud-init plus guest command handoffs for every target in CI before
  any operator-run guest evidence is claimed.
- VM evidence verification now rejects bundles whose `detect-audio.json` does not report the selected target's expected
  audio backend as available.
- VM evidence verification now rejects header-only, truncated, or CRC-corrupt `screenshot.png` placeholders, requiring
  decodable PNG image data with desktop-sized dimensions before support evidence can be promoted.
- Debian and Ubuntu VM cloud-init commands now install the pinned pnpm toolchain before workspace validation.
- Non-Nix VM cloud-init commands now install Rust and Tauri Linux build prerequisites before running `pnpm check`.
- NixOS VM cloud-init commands now run evidence collection through `nix develop --command`.
- The VM target matrix now includes `opensuse-kde-pipewire` with zypper-based guest bootstrap validation.
- The VM target matrix now includes an AArch64 Ubuntu target and prints architecture-specific QEMU launch handoffs.
- `pnpm check` now includes `pnpm verify:tauri`, which runs Tauri Rust formatting, compile checks, and tests.
- The Nix flake now exposes `packages.<system>.loopwire-bin` as a binary package template with fake hashes, plus a
  helper for injecting real release hashes after published artifacts exist.
- `pnpm nix:render-release` now renders a concrete Nix package expression from checksum-bound release tarballs and
  rejects missing or duplicate checksum manifest entries before any Nix publication claim.
- `pnpm verify:nix-release` now wraps the Nix render step and runs `nix build` on Nix-enabled hosts, with an explicit
  skip flag reserved for non-Nix wiring checks.
- `pnpm verify:nix-release` can now download signed assets from `--repo OWNER/REPO --tag vX.Y.Z`, so final release
  proof can verify the Nix package from the published GitHub Release instead of a local staging directory.
- Release evidence collection and verification now support `--require-nix-release`, rejecting render-only or skipped
  Nix proof rows when a release evidence bundle claims package-manager evidence.
- `pnpm verify:final-release` now includes a direct Nix release package proof step before accepting final release
  evidence, VM evidence, support-matrix, and docs proof.
- The final release proof workflow now installs Determinate Nix with a pinned
  `DeterminateSystems/determinate-nix-action@v3.21.2` step before running package proof, so the GitHub runner can
  execute the non-skipped Nix build gate.
- The final release proof workflow now passes the GitHub Actions token into the composed proof step, and release
  readiness fails if that token wiring disappears before the workflow downloads release assets.
- The final release proof workflow contract now fails if the composed proof step reintroduces `--release-dir`, keeping
  final proof tied to downloaded GitHub Release assets instead of local staging directories.
- Release readiness and workflow contract checks now require `scripts/verify-final-release-proof.sh` to invoke the
  shared release tag-ref verifier, so final proof cannot silently drift away from the live tag binding gate.
- `pnpm verify:final-release` now requires the current checkout `HEAD` to match `--git-head` by default; offline fixture
  rehearsals must opt in with `--allow-head-mismatch`.
- The final release handoff now prints an exact-commit `pnpm release:agent-ready -- --require-hosted-checks` preflight
  before secret checks, tagging, workflow dispatch, VM evidence, or final proof steps.
- The final release handoff now also prints a post-deploy `pnpm release:agent-ready -- --require-docs-deployment-artifacts
  --skip-local-gates` check after docs proof fetch, so operators re-run the same release-ready surface once Bunny
  deployment artifacts exist.
- The final release handoff now ends with `pnpm release:status`, so operators finish publication with the same
  read-only aggregate audit that checks GitHub Release assets, docs deployment proof, final-proof workflow status, VM
  evidence, and support-matrix claims.
- Final Release Proof workflow runs now include the audited tag and commit in their visible run name, and
  `pnpm release:status` rejects commit-scoped final-proof runs whose title does not match the selected release tag.
- The final release handoff now prints that expected Final Release Proof run name immediately after the dispatch
  command, so operators can match the workflow run that `pnpm release:status` will accept.
- `pnpm release:status` now stops published release evidence and VM evidence archive checks at the missing download
  failure, avoiding follow-on checksum, extraction, and manifest errors for absent release assets.
- The final release proof workflow now requires a docs deployment run id, downloads that run's
  `loopwire-docs-deployment` artifact, rebuilds docs from the release commit, and verifies `deployment-manifest.json`
  before accepting the live docs smoke.
- Final proof and `pnpm release:fetch-docs-proof` now verify the selected Deploy Docs run completed successfully for the
  expected commit before downloading docs deployment artifacts.
- The docs site now carries a VitePress public installer asset at `/install.sh` that is verified byte-for-byte against
  the canonical `scripts/install.sh`.
- The release installer now rejects signed tarballs with unsafe absolute or parent-traversing archive paths before
  extraction.
- Release readiness now fails if the public docs installer drifts from `scripts/install.sh`, and the Bunny deploy
  dry-run contract proves `install.sh` would be uploaded.
- Release readiness now validates custom public-key and saved secret-list artifacts before reads, rejecting symlinks,
  traversal, URL-like values, glob metacharacters, root/home placeholders, and existing non-file paths.
- Release evidence collection now validates `--output-dir` and summarized readiness-log paths before reading or writing
  artifacts, rejecting symlinks, traversal, URL-like values, glob metacharacters, root/home placeholders, and wrong
  existing file/directory types.
- Final release handoffs now print the reviewed annotated tag creation command and exact `refs/tags/<tag>` push before
  workflow dispatch, so the operator ceremony has no implicit tag step.

## Known Limitations

- No public signed release artifact exists yet.
- `packaging/release-signing-public.pem` now contains the project release public key, and the live repository has the
  matching `LOOPWIRE_RELEASE_PRIVATE_KEY` secret; Bunny deployment secrets and tagged release proof are still required
  before publishing.
- Native JACK client creation and true per-edge gain remain planned. App-only JACK routes and monitors still require a
  separate JACK client or `loopwire-jack-ports` delegate to create the expected Loopwire-owned ports before live apply.
- Live host apply needs Tauri desktop runtime; browser preview fails closed without host mutation.
- Packaged background restore uses the bundled JavaScript restore engine and currently requires `node` on `PATH`.
- VM host planning and cloud-init rendering do not launch guests, download distro images, or promote support-matrix rows
  without operator-captured evidence.
- VM desktop launch smoke proves the Loopwire shell responds locally; screenshot commands still need operator care to
  capture the intended desktop surface in each guest.
- Public AArch64 release proof still requires a tagged workflow run and published `loopwire-linux-aarch64.tar.gz`
  asset.
- Nix flake package wiring exists, but non-skipped `pnpm verify:nix-release` proof must come from a Nix-enabled host or
  VM target after real release hashes exist; render-only and missing-Nix modes remain wiring checks only.

## Verification To Keep Current

- `pnpm check`
- `pnpm detect:audio`
- `pnpm verify:docs`
- `pnpm verify:vm`
- `pnpm verify:tauri`
