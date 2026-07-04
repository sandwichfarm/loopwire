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
- PulseAudio backend detection and support-bundle summaries now expose `one output per source` as a known gap, matching
  the runtime and desktop preflight boundary.
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
- Desktop backend selection now has a dedicated chooser panel that shows selected, available, and unavailable backends,
  explains that the choice is persisted for startup restore, and keeps the active workspace ahead of the sidebar on
  mobile.
- Changing the selected backend now disarms live host apply and immediately runs preview verification for the active
  configuration against the new backend.
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
- Native-backend live-apply preflight now names routes blocked by non-100% gain and provides a `Reset gains` action
  that restores affected routes to 100% without touching host audio.
- Native-backend non-100% gain blockers now explain both repair paths: reset affected route gains to 100%, or switch
  to a graph-edge/DSP-capable backend when one is available.
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
- `pnpm dsp:plan` and `pnpm dsp:verify` now describe and exercise the command-backed DSP provider contract before a
  user enables provider-backed boot restore. `pnpm dsp:verify -- --require-live-capability` now probes provider
  `capabilities` and fails unless the provider declares `supportsLiveGraph:true`.
- `pnpm jack:ports` can print JACK port requirements from a configuration export or persisted state as JSON or TSV,
  giving pro-audio users a read-only session-template handoff.
- `pnpm jack:verify` can compare those JACK requirements against live `jack_lsp` output or a saved port-list fixture
  before users arm native JACK live apply.
- Support bundles can include read-only JACK readiness by passing a Loopwire configuration export or persisted state,
  writing `jack-port-requirements.json` and a parsed `jack` manifest summary.
- Desktop live-apply preflight rules are now covered by focused regression tests, including no-backend, ALSA,
  PulseAudio, native PipeWire, native JACK blocker behavior, and selected-backend capability lookup for the
  configuration-switch guard.
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
- Desktop custom chrome now persists as a preference and requests an undecorated Tauri window before showing
  Loopwire-owned drag, minimize, maximize/restore, and close controls.
- Desktop sidebar start-on-boot control for XDG autostart status, enable, and disable, plus CLI helper fallback.
- Desktop sidebar restore-on-boot control for a user-scoped systemd unit that runs packaged background restore without
  opening the GUI.
- Desktop restore-on-boot now resolves the packaged `loopwire` launcher from `loopwire-gui` before writing systemd
  units, and refuses to install a broken GUI-binary `--background` unit when the launcher is missing.
- Restore-on-boot status now stays readable when the packaged background launcher is missing or fails
  `loopwire --background --help`, marks the action blocked, and still allows removal of an already-installed user unit.
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
- Release evidence bundles now record the candidate readiness check and the strict publish preflight log separately, so
  current release blockers can be attached without failing candidate evidence collection.
- Release evidence manifests now expose parsed `release.findings` and `release.blockers` from the readiness log, plus a
  log-summary mode for checking preflight blockers without rerunning release checks.
- Release signing key preparation helper that refuses repo-local private keys and verifies the generated key pair before
  printing the GitHub secret setup command.
- GitHub secret checks now fail with the underlying `gh secret list` error when repository secret names cannot be read,
  instead of misreporting API or auth failures as missing release/deploy secrets.
- GitHub secret checks now support `--scope deploy` for Bunny.net upload readiness separately from the default strict
  final-proof scope.
- Release readiness now rejects local or remote release tags that do not point at the current checkout commit, preventing
  stale tag preflights from looking publishable.
- Release readiness now requires a clean git checkout by default, while candidate evidence collection opts out with
  `--skip-clean-git` so work-in-progress evidence can still record its source state.
- Docs deployment now uses a reusable Bunny.net upload helper with dry-run verification, checksum headers, and optional
  regional storage endpoint support through `BUNNY_STORAGE_ENDPOINT`.
- The docs deployment workflow and GitHub secret helper now pass optional `BUNNY_REMOTE_PREFIX` through to Bunny.net
  uploads for storage zones that serve multiple paths.
- The Bunny.net docs deploy helper can now write a non-secret `loopwire.docs-deployment.v1` manifest, and the docs
  deploy workflow uploads it as the `loopwire-docs-deployment` artifact after successful Bunny uploads.
- New `pnpm verify:docs-deployment` verifies that deployment manifest against the built docs dist before artifact
  upload, including file inventory, SHA-256 checksums, remote-prefix paths, and secret-like key rejection.
- Release readiness now fails if the docs deployment manifest verifier is missing, unparsable, absent from
  `package.json`, or not wired into the docs deploy workflow before the manifest artifact upload.
- Release readiness now fails if the final release proof workflow, `pnpm verify:final-release`,
  `pnpm vm:package-evidence`, or `pnpm vm:prepare-release-evidence` wiring disappears before the release handoff.
- The v0.1.0 release notes are now publishable release notes instead of candidate notes, so release readiness no
  longer needs the candidate-wording override when GitHub/tag checks are intentionally skipped.
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
- Release readiness now prints no-value next steps for missing Bunny secrets and missing release tags, including the
  guarded `git tag -a <tag>` and `git push origin <tag>` commands only after required secrets are configured.
- Release readiness and the GitHub secret helper now require `BUNNY_PULL_ZONE_HOSTNAME` for final proof, because the
  published release ceremony must prove the live docs deployment and public installer from the Bunny pull-zone URL.
  The helper can set that hostname by itself when Bunny storage credentials are already configured.
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
- Release evidence collection can now require verified VM evidence with `--require-vm-evidence`, including guest
  installed-release smoke when `--require-published-release` is also enabled.
- Release evidence collection now records a read-only `dsp-provider-plan` row in the full profile, and final release
  proof requires `--require-dsp-provider-plan` so the command-backed DSP provider contract cannot disappear from the
  public evidence bundle.
- Final release evidence now binds `dsp-provider-plan.tsv` rows to the configured routed sources and outputs, rejecting
  placeholder DSP provider rows that do not match the manifest-bound configuration.
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
- New `pnpm vm:prepare-release-evidence` command prepares that VM evidence tarball inside a release directory,
  regenerates and re-signs `SHA256SUMS`, verifies the archive entry, and prints the exact GitHub upload command.
- VM evidence packaging now validates the completed tarball with `scripts/extract-safe-tar.sh`, so unsafe archive
  members fail before the archive is attached to a public release.
- Published release verification can now require that public evidence archive with `--require-release-evidence`, extract
  it, and reject archives with missing published-release smoke or blocker findings.
- Published release evidence archive verification now binds the manifest to the expected `release.tag` and repo. It
  rejects unsafe archive paths before extraction, rejects link members with `scripts/extract-safe-tar.sh`, and rejects
  manifest command logs that escape the evidence directory or resolve through symlinks.
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
- VM evidence collection now writes `environment.json`, and verification rejects bundles whose observed distro,
  desktop/session, or architecture do not match the selected target row.
- Host-side SSH VM evidence collection can run the guest collector, copy target evidence back, and verify the bundle
  without changing support-matrix rows prematurely.
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
- VM evidence runbooks now include the final-release `pnpm vm:collect-matrix` command with published-release smoke and
  all-target strictness, so operator handoffs do not silently collect source-checkout-only support evidence.
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
- The final release proof workflow now requires a docs deployment run id, downloads that run's
  `loopwire-docs-deployment` artifact, rebuilds docs from the release commit, and verifies `deployment-manifest.json`
  before accepting the live docs smoke.
- The docs site now carries a VitePress public installer asset at `/install.sh` that is verified byte-for-byte against
  the canonical `scripts/install.sh`.
- The release installer now rejects signed tarballs with unsafe absolute or parent-traversing archive paths before
  extraction.
- Release readiness now fails if the public docs installer drifts from `scripts/install.sh`, and the Bunny deploy
  dry-run contract proves `install.sh` would be uploaded.

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
