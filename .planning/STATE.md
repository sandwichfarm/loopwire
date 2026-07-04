---
gsd_state_version: 1.0
milestone: v0.2
milestone_name: Production Audio Routing
status: In Progress
last_updated: "2026-07-04T20:36:42+02:00"
last_activity: 2026-07-04 - Restore-on-boot now names the active configuration and saved backend
progress:
  total_phases: 5
  completed_phases: 4
  total_plans: 20
  completed_plans: 20
  percent: 80
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-07-03)

**Core value:** World-class UX for real Linux audio routing.
**Current focus:** v0.2 production audio routing.

## Current Position

Phase: 12 Published Release and VM Proof
Plan: Release proof remains gated on real release, secrets, and VM evidence
Status: In Progress
Last activity: 2026-07-04 - Desktop restore-on-boot now names the active configuration and saved backend before
enablement, keeps the saved configuration visible when the background launcher is blocked, and documents that unsafe
unit creation remains disabled until the packaged launcher/backend prerequisites are satisfied. Phase 12 remains gated
on a public release, configured Bunny secrets, live Bunny deployment proof, host QEMU/Nix tooling for local VM launch,
and operator-run VM evidence.

## Blockers / Concerns

- Full audio graph mutation is intentionally incomplete. The PulseAudio compatibility adapter covers Loopwire null
  sinks, running stream enumeration, matched stream moves, stream-level volume/mute, monitor loopbacks, and physical
  monitor sink targets. Native PipeWire covers Loopwire-owned virtual output and monitor sinks, existing route links,
  route mute by disconnecting configured links, physical monitor sink links, and rollback/unload cleanup for selected
  virtual nodes. ALSA covers read-only playback/capture hardware diagnostics only. Native JACK covers read-only port
  enumeration, existing route links, app endpoint resolution to pre-existing Loopwire-owned JACK ports, route mute by
  disconnecting configured connections, and monitor sink links. Pure DSP mix math and an injected audio-host DSP graph
  adapter now exist, DSP rollback now restores the rollback configuration through the core switch transaction contract,
  the DSP adapter now exposes an explicit core configuration runtime wrapper for startup/switch transactions, the
  audio-host DSP adapter now has a command-backed provider port helper, background restore can drive an explicit DSP
  provider command, `pnpm dsp:plan`/`pnpm dsp:verify` can preflight that provider command, and desktop route-control UX
  is driven by detected backend mixing semantics. A bundled file-backed `loopwire-dsp-provider` now exists for local
  restore-contract smoke and packaging proof. Native JACK now has an injected virtual-port provider hook and bundled
  `loopwire-jack-ports` wrapper for manifest/delegation proof, but live host DSP capture/injection, native JACK client
  creation, and native host graph-edge gain implementation remain planned. DSP live restore now requires the operator
  to declare a live provider explicitly with `--dsp-provider-mode live`, and live DSP restore now requires provider
  `capabilities` to declare `supportsLiveGraph:true`.

- Install artifacts are not published yet. Installer and package docs must not claim release availability before
  artifacts exist.
- A real project release public key now exists at `packaging/release-signing-public.pem`, and the private key was
  generated outside the repository at `/home/sandwich/.config/loopwire/release/loopwire-release-private.pem` with
  `0600` permissions. The live `sandwichfarm/loopwire` repository now has `LOOPWIRE_RELEASE_PRIVATE_KEY`, but do not
  claim public signed installer readiness until the Bunny deploy secrets are configured and a tagged release workflow
  has passed.

- Nix package metadata and final proof wiring are smoke-tested structurally, but non-skipped `nix build` proof still
  needs a Nix-enabled host or VM target.
- Live JACK client creation, live backend DSP capture/injection, native graph-edge gain, and published release proof
  remain the major product gaps for a fully functional Loopback-class app.
- Packaged background restore is now release-shaped through `loopwire --background`, but public release proof still
  requires signed published artifacts.
- Public release proof is gated on an explicit versioned release decision, real signing key material, tag push, and VM
  run evidence.
- Support matrix rows must remain `Manual VM` until `scripts/collect-vm-evidence-ssh.sh --execute` or equivalent
  operator-run guest evidence produces a passing `.vm/evidence/<target>` bundle.
- The `fedora-kde-jack` target is metadata and plan coverage only until an operator-run guest evidence bundle passes.
- The `v0.1.0` release-note page is a candidate document only. Do not remove its candidate disclaimer until the public
  GitHub Release and signed artifacts exist.

## Accumulated Context

### Decisions

- Use pnpm workspace, Svelte app UI, Tauri 2 shell path, VitePress docs/site, and Vitest for the walking skeleton.
- Treat PipeWire as the reference backend while modeling PulseAudio, JACK, and ALSA compatibility from the start.
- Keep backend selection and configuration persistence in a pure core package before host integration.

## Verification Log

- 2026-07-04 Restore-on-boot target summary: the desktop restore-on-boot sidebar card now derives a tested summary from
  the active configuration, saved backend, service availability, and enabled state, so users can see exactly what will
  be restored before a user-scoped background service is written. Docs now describe the behavior and `verify-docs.sh`
  asserts the guide and release-note copy. Validation passed: codebase-memory MCP `search_graph` located the startup
  restore and backend selection paths, and `get_code_snippet` confirmed the Tauri background service writes
  `loopwire --background --state-file ... --mode live`; `pnpm --filter @loopwire/desktop test --
  startup-restore-summary.test.ts`, `pnpm --filter @loopwire/desktop typecheck`, `pnpm --filter @loopwire/desktop
  build`, `pnpm verify:docs`, `git diff --check`, and `pnpm check` passed.
- 2026-07-04 Recoverable hidden monitor tray: the desktop now groups monitors by visibility, renders only visible
  monitors in the main monitor grid, and lists hidden monitors in a compact recovery tray with per-monitor `Show`
  actions. The core hidden-monitor persistence contract is unchanged; the new desktop helper is covered by focused
  tests that prove hidden monitors leave the visible group and remain scoped to the active configuration. Validation
  passed: codebase-memory MCP listed `home-sandwich-Develop-loopwire` ready with 3,157 nodes and 6,135 edges, and
  `search_graph`/`trace_path` showed hidden monitor primitives existed in core but needed desktop recovery polish;
  `pnpm --filter @loopwire/desktop test -- monitor-visibility.test.ts`, `pnpm --filter @loopwire/desktop typecheck`,
  `pnpm --filter @loopwire/desktop build`, `pnpm verify:docs`, `git diff --check`, Chromium desktop render smoke, and
  `pnpm check` passed.
- 2026-07-04 Landing-page curl installer hero: the public VitePress first viewport now shows current source install,
  release-gated `curl ... /install.sh | sh`, and `loopwire --background --mode preview` instructions without claiming
  public release availability before signed artifacts, Bunny deploy, and VM proof exist. The hero install cards now wrap
  long commands instead of requiring horizontal scroll on desktop or mobile. Validation passed: `pnpm verify:docs`,
  `pnpm verify:requirements`, `pnpm --filter @loopwire/docs docs:build`, `git diff --check`, Chromium VitePress
  preview screenshots at 1440x900 and 390x844, and `pnpm check`.
- 2026-07-04 First-run backend choice callout: the desktop backend chooser now maps core `prompt`/`auto`/`none`
  decisions into a tested callout above the backend cards, so multi-backend detection asks the user to choose before
  live apply while single-backend and no-backend states explain automatic selection or diagnostics. Docs now describe
  the first-run callout and keep release notes aligned. Validation passed: codebase-memory MCP listed
  `home-sandwich-Develop-loopwire` ready with 3,143 nodes and 6,090 edges, and `search_graph`/`trace_path` showed
  `selectBackend` prompt rules were implemented in core but not called by desktop outside the Svelte chooser; `pnpm
  --filter @loopwire/desktop test -- backend-choice.test.ts`, `pnpm --filter @loopwire/desktop typecheck`, `pnpm
  --filter @loopwire/desktop build`, `pnpm verify:docs`, `git diff --check`, Chromium screenshots at 1440x900 and
  390x844, and `pnpm check` passed.
- 2026-07-04 Docs deployment source-commit binding: `scripts/deploy-docs-bunny.sh` now writes
  `source.gitHead` into `loopwire.docs-deployment.v1` manifests, `scripts/verify-docs-deployment-manifest.mjs` requires
  a valid manifest git head and rejects `--git-head` mismatches, the docs deploy workflow checks the manifest against
  `GITHUB_SHA`, and final release proof checks the downloaded deployment artifact against the requested release commit.
  Validation passed: codebase-memory MCP listed `home-sandwich-Develop-loopwire` ready with 3,143 nodes and 6,090
  edges, and `search_graph`/`get_code_snippet` located the docs deployment manifest, manifest verifier, and final proof
  contracts; `bash -n scripts/deploy-docs-bunny.sh scripts/verify-final-release-proof.sh scripts/verify-scripts.sh
  scripts/verify-docs.sh`, `node --check scripts/verify-docs-deployment-manifest.mjs`, `git diff --check`,
  `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm verify:workflows`, and `pnpm check` passed.
- 2026-07-04 Final VM evidence GitHub-source hardening: `scripts/verify-vm-evidence.sh` now supports
  `--require-github-release-source`, rejecting exact-tag final evidence whose `published-release.json` records a local
  directory source. Final VM archive packaging, final proof, support-matrix verification, promotion, VM matrix status,
  release evidence collection, and release evidence verification now pass or require that strict flag when
  `--require-published-release --release-tag` is used. `scripts/verify-scripts.sh` proves directory-source VM evidence
  still passes ordinary exact-tag verification but fails final GitHub-source verification. Validation passed:
  codebase-memory MCP `index_status` reported `home-sandwich-Develop-loopwire` ready with 3,138 nodes and 6,061 edges,
  and `search_graph`/`get_code_snippet` located the VM evidence, final proof, package, support-matrix, and release
  evidence verifier contracts; `node --check scripts/collect-release-evidence.mjs
  scripts/verify-release-evidence.mjs scripts/verify-support-matrix.mjs scripts/promote-vm-evidence.mjs`, `bash -n
  scripts/verify-vm-evidence.sh scripts/package-vm-evidence.sh scripts/verify-final-release-proof.sh
  scripts/vm-matrix.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, `pnpm verify:scripts`, and
  `pnpm verify:docs`, `git diff --check`, and `pnpm check` passed.
- 2026-07-04 Final release evidence published-surface hardening: `scripts/verify-release-evidence.mjs` now rejects
  `published-release-smoke` rows containing `--release-dir`, while `scripts/verify-scripts.sh` includes a negative
  bundle proving a local staged release directory cannot satisfy `--require-published-release`. Docs now distinguish
  local pre-publish smoke from final published-release evidence. Validation passed: codebase-memory MCP `index_status`
  reported `home-sandwich-Develop-loopwire` ready with 3,138 nodes and 6,076 edges, and `search_graph`/`get_code_snippet`
  located the final proof, release evidence, and published-release verifier contracts; `node --check
  scripts/verify-release-evidence.mjs`, `bash -n scripts/verify-scripts.sh scripts/verify-docs.sh`,
  `pnpm verify:scripts`, `pnpm verify:docs`, `git diff --check`, and `pnpm check` passed.
- 2026-07-04 Desktop unavailable-backend live switch guard: live-apply preflight now treats selected backend detection
  reports with `availability: "unavailable"` as hard blockers before backend-specific rules, and
  `describeConfigurationSwitchPreflight` uses the same selected-backend report. Focused tests prove an unavailable
  PulseAudio report blocks both the visible preflight and configuration switching. Validation passed: codebase-memory
  MCP `index_status` reported `home-sandwich-Develop-loopwire` ready with 3,135 nodes and 6,068 edges, and
  `search_graph`/`get_code_snippet` located the preflight and backend report contracts; `pnpm --filter
  @loopwire/desktop test -- live-apply-preflight.test.ts`, `pnpm --filter @loopwire/desktop typecheck`, `pnpm --filter
  @loopwire/desktop build`, `pnpm verify:docs`, `git diff --check`, and `pnpm check` passed.
- 2026-07-04 Desktop live switch guard regression coverage: `describeConfigurationSwitchPreflight` now resolves the
  selected backend capability report for configuration-switch guards, and `App.svelte` uses that helper instead of
  open-coding the lookup. Focused tests prove the guard uses the selected backend report and ignores reports for other
  backends. Validation passed: `pnpm --filter @loopwire/desktop test -- live-apply-preflight.test.ts` and `pnpm
  --filter @loopwire/desktop typecheck`, `pnpm --filter @loopwire/desktop build`, `pnpm verify:docs`,
  `git diff --check`, and `pnpm check`.
- 2026-07-04 Desktop live switch capability guard: `chooseConfiguration` now passes the selected backend's detected
  capability report into `describeLiveApplyPreflight`, matching the visible preflight strip, route gain lock, and
  switch guard decisions. Docs now call out that the UI and runtime guard share the same capability source. Validation
  passed: `pnpm --filter @loopwire/desktop typecheck`, `pnpm --filter @loopwire/desktop test`, `pnpm --filter
  @loopwire/desktop build`, `pnpm verify:docs`, `git diff --check`, and `pnpm check`.
- 2026-07-04 DSP live capability preflight: `scripts/describe-dsp-provider.mjs` now accepts
  `--require-live-capability`, calls only the provider `capabilities` operation, includes `providerCapability` in JSON
  output, and exits nonzero unless `supportsLiveGraph:true` is declared. Docs now show the preflight before live DSP
  boot restore. Validation passed: `node --check scripts/describe-dsp-provider.mjs`, `bash -n
  scripts/verify-scripts.sh scripts/verify-docs.sh`, `git diff --check`, `pnpm verify:scripts`, and
  `pnpm verify:docs`.
- 2026-07-04 Live DSP provider capability hardening: `loopwire-dsp-provider capabilities` now declares the bundled
  provider as file-backed with `supportsLiveGraph:false`, and `restore-background.mjs --backend dsp --mode live`
  probes provider capabilities before creating a runtime adapter. Regression coverage proves live restore accepts a
  provider that declares `supportsLiveGraph:true` and rejects a file-backed provider before source/output operations.
  Validation passed: `pnpm --filter @loopwire/audio-host test -- --runInBand dsp-provider-cli.test.ts`, `pnpm
  --filter @loopwire/audio-host typecheck`, `node --check scripts/restore-background.mjs`, `bash -n
  scripts/verify-autostart.sh scripts/verify-scripts.sh scripts/verify-docs.sh scripts/verify-release-artifacts.sh`,
  `pnpm verify:autostart`, `pnpm verify:release`, `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm verify:runtime`,
  and `git diff --check`.
- 2026-07-04 Command-backed DSP verification hardening: `createDspRuntimeCommandPorts` now treats empty
  `verify-output` stdout as a failed provider verification instead of accepting exit code 0 as proof. Regression
  coverage proves a silent provider fails closed before Loopwire reports verified graph-edge output. Docs now state
  that DSP provider verification must return explicit JSON. Validation passed: red/green focused
  `pnpm --filter @loopwire/audio-host test -- --runInBand dsp-adapter.test.ts`, `pnpm --filter @loopwire/audio-host
  typecheck`, `pnpm verify:docs`, `git diff --check`, and `pnpm check`.
- 2026-07-04 Desktop backend chooser UX: the desktop shell now renders a dedicated backend chooser panel with
  selected/available/unavailable backend cards, persistence/startup-restore copy, and the live-apply disarm rule.
  Mobile layout now orders the active workspace before the sidebar so backend/configuration controls are not buried
  below boot cards. The public product screenshot SVG and unreleased notes were refreshed. Validation passed:
  `pnpm --filter @loopwire/desktop typecheck`, `pnpm --filter @loopwire/desktop build`, `pnpm verify:docs`,
  `git diff --check`, Chromium CDP screenshots at 1440x900 and 390x844 with zero horizontal overflow, and
  `pnpm check`.
- 2026-07-04 Phase 12 VM evidence status tag audit: `scripts/vm-matrix.sh evidence-status` now supports
  `--release-tag` only with `--require-published-release`, validates semver tags before inspecting bundles, forwards
  the tag to `scripts/verify-vm-evidence.sh`, and generated runbooks now use tag-bound final status and promotion
  commands. Validation passed: `bash -n scripts/vm-matrix.sh scripts/verify-scripts.sh scripts/verify-docs.sh`,
  `bash scripts/vm-matrix.sh evidence-status --target arch-hyprland-pipewire --evidence-root /tmp/loopwire-missing
  --require-published-release --release-tag v0.1.0`, `pnpm verify:scripts`, `pnpm verify:docs`, `git diff --check`,
  and `pnpm check` after rerunning a transient Tauri test failure successfully.
- 2026-07-04 Phase 12 VM release-tag evidence binding: VM guest evidence now writes structured
  `published-release.json`, `scripts/verify-vm-evidence.sh --require-published-release --release-tag <tag>` rejects
  mismatched release evidence, VM archive packaging passes the archive tag into every target verifier, final release
  proof dry-runs include tag-bound VM/support-matrix checks, and docs describe the exact-tag support-claim ceremony.
  Validation passed: `bash -n scripts/verify-vm-evidence.sh scripts/collect-vm-evidence.sh
  scripts/collect-vm-evidence-ssh.sh scripts/collect-vm-matrix-evidence.sh scripts/package-vm-evidence.sh
  scripts/verify-final-release-proof.sh scripts/verify-scripts.sh`, `node --check scripts/promote-vm-evidence.mjs
  scripts/verify-support-matrix.mjs scripts/collect-release-evidence.mjs scripts/verify-release-evidence.mjs`,
  `git diff --check`, `pnpm verify:scripts`, `pnpm verify:docs`, and `pnpm check`.
- 2026-07-04 Phase 12 GitHub secret scope checks: `scripts/setup-github-secrets.sh --check` now accepts
  `--scope deploy` to check only the Bunny.net upload secret pair, while the default `--scope final` remains strict for
  `BUNNY_PULL_ZONE_HOSTNAME` and `LOOPWIRE_RELEASE_PRIVATE_KEY`. Deploy-scope missing-secret guidance prints only the
  storage zone/access-key setup command. Validation passed: `bash -n scripts/setup-github-secrets.sh
  scripts/verify-scripts.sh scripts/verify-docs.sh`, `bash scripts/setup-github-secrets.sh --print-required --scope
  deploy`, `bash scripts/setup-github-secrets.sh --print-required`, `pnpm verify:scripts`, `pnpm verify:docs`, and
  `pnpm check`.
  Live read-only check: `bash scripts/setup-github-secrets.sh --repo sandwichfarm/loopwire --check --scope deploy`
  still fails closed on missing `BUNNY_STORAGE_ZONE` and `BUNNY_ACCESS_KEY`.
- 2026-07-04 Phase 12 DSP provider configuration isolation: rendered DSP outputs now include `configurationId`, the
  command-backed provider appends `--configuration-id` to write/verify commands, and `loopwire-dsp-provider` stores
  outputs below `outputs/<configuration-id>/<output-id>.json`. Regression tests cover same-output-id isolation across
  configurations. Validation passed: `pnpm --filter @loopwire/core test`, `pnpm --filter @loopwire/audio-host test`,
  `pnpm --filter @loopwire/audio-host typecheck`, `pnpm verify:docs`, `pnpm verify:scripts`, `git diff --check`, and
  `pnpm check`.
- 2026-07-04 Phase 12 DSP provider evidence binding: final release evidence now validates `dsp-provider-plan.tsv`
  against the manifest-bound configuration instead of accepting any read/write/verify placeholder rows. The verifier
  derives expected read-source rows from routed inputs and expected write-output/verify-output rows from configured
  outputs, checks labels/channels/frame count, and rejects duplicate or unexpected rows. Validation passed:
  `node --check scripts/verify-release-evidence.mjs`, `bash -n scripts/verify-scripts.sh`, and
  `pnpm verify:scripts`, `pnpm verify:docs`, `git diff --check`, and `pnpm check`.
- 2026-07-04 Phase 12 VM screenshot evidence hardening: `scripts/verify-vm-evidence.sh` now parses PNG IHDR width and
  height and rejects screenshots below 320x200, preventing 1x1 or header-only placeholders from satisfying VM support
  evidence. `scripts/verify-scripts.sh` now builds a dimensioned synthetic PNG for positive fixture coverage and
  rejects a 1x1 PNG in a negative case. Validation passed: `bash -n scripts/verify-vm-evidence.sh
  scripts/verify-scripts.sh`, `pnpm verify:scripts`, `pnpm verify:docs`, `git diff --check`, and `pnpm check`.
- 2026-07-04 Phase 12 final proof handoff hardening: final release proof dry-run plan output is now constrained to
  repo-local `dist/release/` files, creates that handoff directory explicitly, rejects absolute paths, shell glob
  metacharacters, symlinks, directories, and `.`/`..` traversal before writing, and keeps the documented release review
  path aligned with the verifier. Validation passed: focused positive/negative dry-run checks,
  `bash -n scripts/verify-final-release-proof.sh scripts/verify-scripts.sh`, `pnpm verify:scripts`,
  `pnpm verify:docs`, `git diff --check`, and `pnpm check`.
- 2026-07-04 Phase 12 installer dependency reporting: the curl installer now reports whether `node` is available after
  install and warns raw tarball users that packaged background restore/provider commands require Node.js before Restore
  on boot. `apps/docs/docs/public/install.sh` was synced byte-for-byte from `scripts/install.sh`, and install plus
  start-on-boot docs now explain that AUR/Nix paths declare or wrap the dependency. Validation passed: `bash -n
  scripts/install.sh apps/docs/docs/public/install.sh scripts/verify-install.sh scripts/verify-docs.sh`,
  `pnpm verify:install`,
  `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm check`, and `git diff --check`. No public release, VM launch, Bunny
  deployment, secret write, tag push, host audio mutation, or support-matrix promotion was performed.
- 2026-07-04 Phase 12 VM evidence handoff: final proof dry-runs now print the VM evidence archive packaging command and
  matching `gh release upload` command before per-target VM verification, making the required
  `loopwire-vm-evidence-<tag>.tar.gz` release attachment explicit. Validation passed: `bash -n
  scripts/verify-final-release-proof.sh scripts/verify-scripts.sh`, `git diff --check`, `pnpm verify:scripts`,
  `pnpm verify:docs`, direct `scripts/verify-final-release-proof.sh --dry-run` grep for the new handoff lines, and
  `pnpm check`. No public release, VM launch, Bunny deployment, secret write, tag push, host audio mutation, or
  support-matrix promotion was performed.
- 2026-07-04 Phase 12 final proof token guard: codebase-memory MCP `index_status` reported
  `home-sandwich-Develop-loopwire` ready, and `search_code` confirmed the existing final proof token scopes were only
  on archive download steps before the composed proof step was updated. `bash -n scripts/verify-release-readiness.sh
  scripts/verify-github-workflows.sh scripts/verify-scripts.sh`, `pnpm verify:workflows`, offline
  `pnpm verify:release-readiness -- --repo sandwichfarm/loopwire --tag v0.1.0 --public-key
  packaging/release-signing-public.pem --skip-gh --skip-tag --skip-clean-git --allow-candidate-notes`,
  `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm check`, `git diff --check`, added-line length scan, GSD
  roadmap/phase queries, and codebase-memory MCP fast reindex/status passed. The reindex reported ready with 2,617
  nodes and 5,451 edges.
- 2026-07-03 Phase 1: `pnpm install` completed with lockfile and approved `esbuild` build policy.
- 2026-07-03 Phase 1: `pnpm check` passed: typecheck, tests, docs build, core build, desktop Vite build.
- 2026-07-03 Phase 1: `pnpm verify:scripts` passed bash syntax checks for installer, CT diagnostics, and secret helper.
- 2026-07-03 Phase 1: workflow YAML parsed with Ruby `YAML.load_file`; `actionlint` was not installed.
- 2026-07-03 Phase 1: `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml` passed.
- 2026-07-03 Phase 2: `pnpm check` passed with 15 tests total.
- 2026-07-03 Phase 2: `pnpm detect:audio` reported PipeWire 1.6.7 available, PulseAudio compatibility available,
  ALSA available, and JACK unavailable because `jack_lsp` is missing.

- 2026-07-03 Phase 2: `bash scripts/ct-host-check.sh` passed and redacted local user, host, cookie, pid, and
  `/run/user` details in diagnostics output.

- 2026-07-03 Phase 2: `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml`, workflow YAML parse, and
  `git diff --check` passed.

- 2026-07-03 Phase 3: Core tests passed with 4 files and 23 tests covering CRUD, import/export, migrations,
  switch success, apply rollback, verify rollback, and startup re-apply.

- 2026-07-03 Phase 3: `pnpm check`, `pnpm verify:scripts`, `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml`,
  workflow YAML parse, `pnpm detect:audio`, `bash scripts/ct-host-check.sh`, and `git diff --check` passed.

- 2026-07-03 Phase 3: Playwright smoke passed at 1440x900 and 390x844 against `http://127.0.0.1:5174/` with
  duplicate/export verified and zero horizontal overflow.

- 2026-07-03 Phase 4: Core tests passed with 26 tests covering route gain, route mute, invalid gain, configuration
  runtime, persistence, and backend selection.

- 2026-07-03 Phase 4: `pnpm check`, `pnpm verify:scripts`, `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml`,
  workflow YAML parse, `pnpm detect:audio`, `bash scripts/ct-host-check.sh`, and `git diff --check` passed.

- 2026-07-03 Phase 4: Playwright smoke passed at 1440x900 and 390x844 against `http://127.0.0.1:5174/` with
  diagnostics, route gain, route mute, custom chrome fallback, and zero horizontal overflow.

- 2026-07-03 Phase 5 VM matrix: `pnpm verify:vm`, `pnpm verify:scripts`, `pnpm check`,
  `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml`, workflow YAML parse, `pnpm detect:audio`, and
  `git diff --check` passed.

- 2026-07-03 Phase 5 VM matrix: `bash scripts/vm-matrix.sh doctor || true` reported KVM available, SSH present,
  `qemu-system-x86_64` missing, `qemu-img` missing, and `cloud-localds` missing optional; no VM was launched.

- 2026-07-03 Phase 5 startup helper: `pnpm verify:autostart` passed with temp-dir validation for XDG desktop autostart
  and systemd user unit rendering.

- 2026-07-03 Phase 5 installer/package smoke: `pnpm verify:install` passed with a local fake release artifact,
  installed binary execution, and bad-checksum rejection; `pnpm verify:packaging` passed for AUR/Nix metadata.

- 2026-07-03 Phase 5 release workflow/checksums: `pnpm verify:release` passed with package generation, same-input
  reproducibility, multi-architecture checksum entries, installer round-trip, staged native bundle checksum coverage,
  and installed binary execution.

- 2026-07-03 Phase 5 Tauri bundle follow-up: local AppImage build first exposed missing icon configuration, then an
  Arch/linuxdeploy strip failure. Adding configured icons and using `NO_STRIP=true` allowed full Tauri bundling to pass
  for AppImage, deb, and rpm outputs.

- 2026-07-03 Phase 5 real release packaging smoke: packaged the real compiled Tauri binary, copied AppImage/deb/rpm
  bundles, regenerated `SHA256SUMS`, verified all artifacts, and installed the generated tarball into a temp prefix.

- 2026-07-03 Phase 5 AUR local package smoke: `pnpm verify:aur` passed on this Arch host, rendering the PKGBUILD from
  generated artifacts and building a package archive containing `usr/bin/loopwire`.

- 2026-07-03 Phase 5 signed release manifest: `pnpm verify:install`, `pnpm verify:release`, and `pnpm verify:scripts`
  passed with temporary RSA keys, signed `SHA256SUMS`, strict installer verification, and tampered-artifact rejection.

- 2026-07-03 backend runtime supplemental: `pnpm --filter @loopwire/audio-host test` and typecheck passed for the
  guarded `pactl` virtual-sink adapter. No live host mutation was performed.

- 2026-07-03 stream routing supplemental: `pnpm --filter @loopwire/audio-host test` and typecheck passed for guarded
  `pactl move-sink-input` routing, verification, and moved-stream rollback. No live host mutation was performed.

- 2026-07-03 stream control supplemental: `pnpm --filter @loopwire/audio-host test` and typecheck passed for guarded
  `pactl` sink-input volume/mute apply, verification, and rollback. No live host mutation was performed.

- 2026-07-03 stream control full check: `pnpm check`, `pnpm detect:audio`,
  `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml`, workflow YAML parse, GSD queries, and code graph
  reindex with persistence passed.

- 2026-07-03 Phase 6 docs contract: `pnpm verify:docs`, `pnpm verify:scripts`, and `pnpm build:docs` passed for
  support matrix, troubleshooting, screenshot, release workflow, and unreleased release-note pages.

- 2026-07-03 Phase 7 CI/CT/CD hardening: workflow YAML parse passed, action tags were verified live with
  `git ls-remote`, and `pnpm check`, `pnpm detect:audio`, `cargo check`, GSD queries, line checks, and code graph
  reindex passed after workflow changes.

- 2026-07-03 Phase 12 release proof tooling: `node scripts/collect-release-evidence.mjs --output-dir "$tmp_dir"
  --profile quick` and `pnpm collect:evidence -- --output-dir "$tmp_dir" --profile quick` passed, producing
  `release-evidence.json` plus script, VM, docs, backend-detection, and Tauri cargo-check logs.

- 2026-07-03 Phase 12 validation: `pnpm verify:scripts`, `pnpm check`, `pnpm detect:audio`,
  `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml`, GSD milestone/roadmap queries, touched-file
  line-length check, `git diff --check`, and code graph reindex with persistence passed.

- 2026-07-03 Phase 12 VM collector: `bash scripts/collect-vm-evidence.sh --target arch-hyprland-pipewire
  --output-dir "$tmp_dir" --screenshot-command <generated-png>` passed as a local flow smoke, producing the
  verifier-required evidence files. This is not support-matrix VM evidence.

- 2026-07-03 Phase 12 VM hardening: `bash scripts/verify-vm-evidence.sh --target arch-hyprland-pipewire
  --evidence-dir /tmp/tmp.uCOiVH2dec` passed, a non-PNG screenshot rejection smoke passed, `pnpm verify:packaging`
  passed, and code search found no remaining `github.com/loopwire/loopwire` links.

- 2026-07-03 Phase 12 support matrix guard: `pnpm verify:support-matrix` passed with six targets and zero
  evidence-backed rows; `pnpm verify:docs` now runs the same guard. A synthetic evidence bundle under a temp
  `--evidence-root` was rejected while the row still said `Manual VM`, proving the docs cannot lag real VM evidence.

- 2026-07-03 Phase 12 support matrix validation: `pnpm verify:scripts`, `pnpm verify:vm`, `pnpm check`,
  `pnpm detect:audio`, GSD milestone/roadmap queries, touched-file line-length check, and `git diff --check` passed.

- 2026-07-03 Phase 12 workflow contract: `pnpm verify:workflows` passed and `pnpm check` now runs it before runtime
  checks, typecheck, tests, and builds. The verifier parses workflow YAML and asserts CI, CT, docs deployment, release,
  and VM matrix workflow commands remain wired.

- 2026-07-03 Phase 12 workflow validation: `pnpm verify:scripts`, `pnpm verify:workflows`, Ruby workflow YAML parse,
  `pnpm check`, `pnpm verify:docs`, `pnpm verify:vm`, `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml`,
  touched-file line-length check, and `git diff --check` passed.

- 2026-07-03 Phase 12 repository owner correction: installer defaults, AUR metadata, Nix metadata, release docs, and
  VM bootstrap commands now point at `sandwichfarm/loopwire`. Search found no remaining `github.com/loopwire/loopwire`,
  `loopwire/loopwire`, or `--repo loopwire` references.

- 2026-07-03 Phase 12 owner validation: `pnpm verify:packaging`, `pnpm verify:install`, `pnpm verify:workflows`,
  `pnpm verify:docs`, `pnpm check`, `pnpm detect:audio`, `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml`,
  and GSD milestone/roadmap queries passed.

- 2026-07-03 Phase 12 GitHub secret helper: `bash scripts/setup-github-secrets.sh --print-required`, dry-run with
  Bunny and release-key inputs, and mutually exclusive `--check --dry-run` rejection passed. No secrets were written.

- 2026-07-03 Phase 12 live secret audit: `bash scripts/setup-github-secrets.sh --repo sandwichfarm/loopwire --check`
  read secret names only and failed closed because `BUNNY_STORAGE_ZONE`, `BUNNY_ACCESS_KEY`, and
  `LOOPWIRE_RELEASE_PRIVATE_KEY` are missing; optional `BUNNY_PULL_ZONE_HOSTNAME` is also unset.

- 2026-07-03 Phase 12 secret-helper validation: `pnpm verify:scripts`, `pnpm check`, `pnpm verify:docs`,
  `pnpm verify:workflows`, `pnpm detect:audio`, and `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml`
  passed.

- 2026-07-03 monitor loopback supplemental: `pnpm --filter @loopwire/audio-host test` passed with 17 tests, typecheck
  passed, and line checks passed for touched audio-host files. No live host mutation was performed.
- 2026-07-03 physical monitor binding: `pnpm --filter @loopwire/core test`, core typecheck,
  `pnpm --filter @loopwire/audio-host test`, audio-host typecheck, desktop typecheck, and line checks passed. No live
  host mutation was performed.

- 2026-07-04 Phase 12 JACK provider wrapper: `pnpm --filter @loopwire/audio-host test -- jack-ports-cli.test.ts`
  passed with 107 audio-host tests, `pnpm --filter @loopwire/audio-host typecheck` passed, and a strict built CLI smoke
  proved `pnpm jack:provider -- --help`, fail-closed manifest recording without a delegate, and delegated provider
  argument forwarding.

- 2026-07-04 Phase 12 release/package validation: `pnpm verify:release`, `pnpm verify:install`,
  `pnpm verify:packaging`, `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm verify:autostart`, `pnpm verify:aur`,
  `pnpm check`, `pnpm detect:audio`, shell syntax checks, touched-file line-length check, and `git diff --check`
  passed after adding the packaged `loopwire-jack-ports` wrapper.

- 2026-07-04 Phase 12 DSP trust boundary: `node --check scripts/restore-background.mjs`,
  `bash -n scripts/manage-autostart.sh scripts/verify-autostart.sh scripts/verify-scripts.sh scripts/verify-docs.sh`,
  `pnpm verify:autostart`, a direct restore CLI smoke for the `--dsp-provider-mode live` requirement,
  `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm check`, `pnpm detect:audio`, GSD roadmap/phase queries,
  touched-file line-length check, and `git diff --check` passed.

- 2026-07-04 Phase 12 release public key: `pnpm release:prepare-key -- --private-key-out
  /home/sandwich/.config/loopwire/release/loopwire-release-private.pem --public-key-out
  packaging/release-signing-public.pem` generated a 3072-bit RSA key pair, kept the private key outside the repository
  with `0600` permissions, and wrote the public key for commit. `pnpm verify:release-readiness -- --repo
  sandwichfarm/loopwire --tag v0.1.0 --public-key packaging/release-signing-public.pem --skip-gh --skip-tag
  --skip-clean-git --allow-candidate-notes` passed and reported `ok: release public key`. Without
  `--allow-candidate-notes`, readiness still failed on candidate release-note wording, not missing public key. The
  GitHub secret helper dry-run validated the private/public key pair and printed only secret names that would be set.
- 2026-07-03 physical monitor binding full check: `pnpm check`, `pnpm detect:audio`, Rust `cargo check`, workflow
  YAML parse, GSD queries, line checks, `git diff --check`, and Playwright desktop/mobile smoke passed. No live host
  audio mutation was performed.
- 2026-07-03 native PipeWire graph adapter: `pnpm --filter @loopwire/audio-host test` passed with 3 files and 27
  tests, and audio-host typecheck passed. No live `pw-link` mutation was performed.
- 2026-07-03 native PipeWire graph adapter full check: `pnpm check`, `pnpm detect:audio`, Rust `cargo check`,
  workflow YAML parse, GSD queries, and `git diff --check` passed. No live `pw-link` mutation was performed.
- 2026-07-03 live apply consent and runtime wiring: desktop typecheck, audio-host typecheck, and Rust `cargo check`
  passed. No live `pactl` or `pw-link` mutation was performed.
- 2026-07-03 live apply consent full check: `pnpm check` passed, and Playwright desktop/mobile smoke verified the
  `Host apply` control and browser fail-closed behavior with zero horizontal overflow. No live host mutation was
  performed.
- 2026-07-03 route-control semantics: audio-host tests passed with 27 tests, audio-host typecheck passed, desktop
  typecheck passed, and core split-source routing regression was added. No live host mutation was performed.
- 2026-07-03 route-control semantics full check: `pnpm check` passed, and Playwright desktop/mobile smoke verified
  PipeWire link-only and PulseAudio stream-level semantics messaging with zero horizontal overflow. No live host
  mutation was performed.
- 2026-07-03 published release proof setup: added reusable published-release verifier. Actual GitHub Release and VM
  evidence were not produced because they require an explicit release/tag/signing-key decision.
- 2026-07-03 VM evidence setup: added target-scoped VM evidence verifier for check logs, backend JSON, CT log,
  autostart log, screenshot, and notes. No VM was launched.
- 2026-07-03 release readiness setup: added a non-mutating release preflight for versioned notes, signing public key,
  tag visibility, GitHub repository access, and required GitHub secrets. No release was published.
- 2026-07-03 desktop backend detection: desktop startup now hydrates the Backend picker and Diagnostics panel from
  `detectAudioBackends` through the Tauri allowlisted command bridge for `pw-cli`, `wpctl`, `pactl`, `jack_lsp`, and
  `aplay`; browser preview keeps packaged fallback candidates.
- 2026-07-03 first-run backend selection: default state no longer hardcodes PipeWire as a persisted backend choice, so
  multiple detected backends enter prompt mode. Live apply refuses to arm until the user chooses a backend.
- 2026-07-03 desktop backend detection validation: audio-host typecheck/build/test, desktop typecheck/build,
  core typecheck/test, Rust `cargo check`, `pnpm verify:docs`, `pnpm check`, `pnpm detect:audio`, Playwright
  desktop/mobile screenshot smoke, `pnpm verify:vm`, touched-file line-length check, `git diff --check`, and GSD
  queries passed. No live host audio mutation was performed.
- 2026-07-03 source background restore: the desktop shell now reads/writes
  `${XDG_CONFIG_HOME:-$HOME/.config}/loopwire/state.json`, and `pnpm restore:background` can verify the selected
  persisted configuration with dry-run adapters or explicit live backend adapters.
- 2026-07-03 source background restore validation: `pnpm verify:autostart` first exposed a `grep` option parsing bug
  for `--state-file`; after fixing literal matching, it passed and exercised source-checkout systemd rendering plus the
  background restore runner.
- 2026-07-03 source background restore validation: Rust tests first exposed a `config_home` result type mismatch; after
  fixing it, `cargo test --manifest-path apps/desktop/src-tauri/Cargo.toml` passed with three tests covering state-file
  writes and autostart rendering.
- 2026-07-03 source background restore validation: `pnpm verify:docs` first exposed the same literal `grep` issue for
  `--source-dir`; after fixing it, docs verification passed.
- 2026-07-03 source background restore validation: `node --check scripts/restore-background.mjs`,
  `bash -n scripts/manage-autostart.sh scripts/verify-autostart.sh scripts/verify-scripts.sh scripts/verify-docs.sh`,
  `pnpm verify:scripts`, `pnpm verify:vm`, `pnpm verify:docs`,
  `cargo fmt --manifest-path apps/desktop/src-tauri/Cargo.toml --check`, `git diff --check`, corrected touched-file
  trailing-whitespace and line-length checks, docs preview HTTP 200, and GSD milestone/roadmap queries passed.
- 2026-07-03 source background restore full check: `pnpm check` passed, including script, workflow, runtime, typecheck,
  test, docs build, and desktop build gates. `pnpm detect:audio` passed with PipeWire and PulseAudio compatibility
  available, ALSA available, and JACK unavailable because `jack_lsp` is missing.
- 2026-07-03 source background restore tooling gap: codebase-memory MCP `index_repository` retry failed with
  `Transport closed`, so the graph could not be refreshed for this pass.
- 2026-07-03 VM host planning: `scripts/vm-matrix.sh host-plan` was added as a non-mutating cross-system planning
  surface for every VM target, and `scripts/vm-matrix.sh render-cloud-init --all` now renders `user-data`,
  `meta-data`, and `guest-commands.sh` for all seven targets in one command. `launch` now chooses the QEMU system
  binary from target architecture instead of hardcoding x86_64.
- 2026-07-03 VM host planning validation: `bash -n scripts/vm-matrix.sh scripts/verify-scripts.sh
  scripts/verify-docs.sh`, `bash scripts/vm-matrix.sh validate`, `bash scripts/vm-matrix.sh host-plan --target
  fedora-sway-pipewire`, all-target cloud-init rendering, `pnpm vm:host-plan -- --target fedora-sway-pipewire`,
  `pnpm vm:render-cloud-init -- --all`, `pnpm verify:scripts`, `pnpm verify:vm`, `pnpm verify:docs`, `pnpm check`,
  `pnpm detect:audio`, `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml`, touched-file
  trailing-whitespace and line-length checks, `git diff --check`, and GSD milestone/roadmap queries passed.
- 2026-07-03 VM host planning readback: `pnpm vm:doctor -- --target arch-hyprland-pipewire` still fails closed on
  this host because `qemu-system-x86_64` and `qemu-img` are missing; KVM is available, SSH is present, and the command
  prints the Arch install hint plus guest and host evidence handoff commands. No package installation, image download,
  VM launch, or support-matrix promotion was performed.
- 2026-07-03 VM host planning tooling gap: codebase-memory MCP `index_repository` retry failed with `Transport closed`,
  so the code graph could not be refreshed for this pass.
- 2026-07-03 PulseAudio stream verification: added a red regression test proving `verify` previously returned
  `ok: true` and `Verified 1 Loopwire sink(s)` when both configured PulseAudio routes had no matching live stream.
  The adapter now reports `Missing matching PulseAudio stream(s) for route(s): ...` before a route can be treated as
  verified.
- 2026-07-03 PulseAudio stream verification validation: the first focused test run failed with the missing-stream
  regression, then `pnpm --filter @loopwire/audio-host test` passed with 61 tests after implementation and fixture
  cleanup. `pnpm --filter @loopwire/audio-host typecheck`, `pnpm verify:docs`, `bash -n scripts/verify-docs.sh`,
  `pnpm check`, `pnpm detect:audio`, `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml`, `pnpm verify:vm`,
  touched-file trailing-whitespace and line-length checks, `git diff --check`, docs preview HTTP 200, and GSD
  milestone/roadmap queries passed.
- 2026-07-03 PulseAudio stream verification tooling gap: codebase-memory MCP `index_repository` failed with
  `Transport closed` before and after the slice, so this pass used focused shell reads after the required graph
  attempts.
- 2026-07-03 Phase 12 blocker recheck: live GitHub secret-name audit for `sandwichfarm/loopwire` still reports
  missing `BUNNY_STORAGE_ZONE`, `BUNNY_ACCESS_KEY`, and `LOOPWIRE_RELEASE_PRIVATE_KEY`; optional
  `BUNNY_PULL_ZONE_HOSTNAME` is unset.
- 2026-07-03 VM evidence hardening: `scripts/verify-vm-evidence.sh` now requires `command-results.tsv` plus
  `audio-host-build.log`, verifies every required guest command exited 0, checks each ledger row points at the expected
  non-empty log, and rejects failed command rows in `pnpm verify:scripts`.

- 2026-07-03 docs homepage UX: reworked the VitePress home page into a product-screenshot hero with source install,
  `v0.1.0` candidate status, a proof strip, and a release ceremony band. Public release and VM claims remain gated.

- 2026-07-03 docs homepage validation: `pnpm verify:docs`, docs build, Playwright desktop/mobile at
  `http://127.0.0.1:4173`, `pnpm check`, touched-file line-length check, and `git diff --check` passed. Playwright
  verified screenshot rendering, the install command, three proof cards, next-section visibility, and zero overflow.

- 2026-07-03 code graph fallback: codebase-memory MCP indexing/search failed with `Transport closed`, so this docs UX
  pass used focused file reads instead of graph discovery.
- 2026-07-03 VM collector compatibility smoke: `bash scripts/collect-vm-evidence.sh --target
  arch-hyprland-pipewire --output-dir "$tmp_dir" --screenshot-command <generated-png>` passed, then
  `bash scripts/verify-vm-evidence.sh --target arch-hyprland-pipewire --evidence-dir "$tmp_dir"` passed. This remains
  local verifier compatibility evidence, not support-matrix VM evidence.
- 2026-07-03 VM evidence validation: `pnpm verify:scripts`, `pnpm check`, `pnpm verify:docs`,
  `pnpm verify:vm`, `pnpm verify:support-matrix`, and Rust `cargo check` passed. Support matrix still has six targets
  and zero evidence-backed rows.
- 2026-07-03 release readiness verification: offline preflight smoke passed; real preflight failed closed on missing
  versioned notes, signing key, tag, and GitHub secrets. `pnpm check` passed after updates.
- 2026-07-03 source picker functional slice: added pure core `addInputSourceToConfiguration`, desktop source-picker
  wiring, duplicate-source disabled states, configuration docs, and unreleased notes. Source additions create an input
  and route to the active output in app-runtime state; no live host audio mutation was performed.
- 2026-07-03 source picker validation: core tests passed with 32 tests, core typecheck passed, desktop typecheck
  passed, Playwright desktop smoke verified source count and route count move from 2 to 3 and survive reload, and
  Playwright mobile screenshot smoke showed no layout overlap.
- 2026-07-03 source picker full check: `pnpm check`, `pnpm verify:docs`, `pnpm detect:audio`, Rust `cargo check`,
  and `pnpm verify:vm` passed.
- 2026-07-03 output picker functional slice: added pure core `addOutputBusToConfiguration`, desktop output-picker
  wiring, duplicate-output disabled states, configuration docs, and unreleased notes. Output additions create an
  output bus and default routes from existing sources in app-runtime state; no live host audio mutation was performed.
- 2026-07-03 output picker validation: core tests passed with 34 tests, core typecheck passed, desktop typecheck
  passed, Playwright desktop smoke verified outputs move from 1 to 2 and routes move from 2 to 4 and survive reload,
  and Playwright mobile screenshot smoke showed no layout overlap.
- 2026-07-03 output picker full check: `pnpm check`, `pnpm verify:docs`, `pnpm detect:audio`, Rust `cargo check`,
  and `pnpm verify:vm` passed.
- 2026-07-03 live source discovery: added read-only PulseAudio-compatible `pactl list sink-inputs` enumeration,
  desktop source-picker hydration, browser preview samples, static fallback candidates, and PulseAudio runtime matching
  against discovered source names. No live host audio mutation was performed.
- 2026-07-03 live source discovery validation: audio-host tests passed with 34 tests, audio-host typecheck/build
  passed, desktop typecheck/build passed, and Playwright desktop/mobile smoke verified the PulseAudio preview picker,
  add-source persistence from 2 to 3 sources/routes, and zero horizontal overflow.
- 2026-07-03 live source discovery host proof: read-only host `enumerateInputSources` against PulseAudio compatibility
  listed 2 running source stream(s) through `pactl list sink-inputs`; this did not mutate host audio.
- 2026-07-03 live source discovery full check: `pnpm check`, `pnpm verify:docs`, `pnpm verify:vm`,
  `pnpm detect:audio`, `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml`, touched-file line-length
  check, and `git diff --check` passed.
- 2026-07-03 code graph note: codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`,
  so source discovery for this slice used focused shell reads instead.
- 2026-07-03 monitor picker functional slice: added pure core `addMonitorToConfiguration`, desktop monitor-picker
  wiring, duplicate-monitor disabled states, configuration docs, and unreleased notes. Monitor additions append an
  app-runtime monitor endpoint without changing routes; no live host audio mutation was performed.
- 2026-07-03 monitor picker validation: core tests passed with 36 tests, core typecheck passed, desktop typecheck
  passed, Playwright desktop smoke verified monitors move from 2 to 3 and survive reload, and Playwright mobile
  screenshot smoke showed no layout overlap.
- 2026-07-03 monitor picker full check: `pnpm check`, `pnpm verify:docs`, `pnpm detect:audio`, Rust `cargo check`,
  `pnpm verify:vm`, touched-file line-length check, and `git diff --check` passed.
- 2026-07-03 monitor target picker functional slice: added typed `enumeratePlaybackDevices` for read-only
  PulseAudio-compatible playback sink enumeration, desktop monitor target selectors with manual override, docs updates,
  and runtime/status wrapping for long device identifiers. Unsupported backends remain explicit manual-target mode.
- 2026-07-03 monitor target picker validation: audio-host tests passed with 30 tests, audio-host typecheck passed,
  desktop typecheck passed, desktop production build passed after refreshing package dist, and Playwright verified
  PulseAudio target selection plus reload persistence on desktop and mobile.
- 2026-07-03 monitor target picker full check: `pnpm check`, `pnpm verify:docs`, `pnpm detect:audio`, Rust
  `cargo check`, `pnpm verify:vm`, `git diff --check`, and GSD roadmap readback passed. A read-only host run of
  `enumeratePlaybackDevices` listed 3 PulseAudio-compatible playback sink(s).
- 2026-07-03 desktop start-on-boot functional slice: added native Tauri XDG autostart status/install/uninstall for
  `~/.config/autostart/loopwire.desktop`, a sidebar Start on boot panel, browser-preview fail-closed behavior, and
  docs/README/release-note updates. No system-wide startup files were touched by automated validation.
- 2026-07-03 desktop start-on-boot validation: Rust unit tests passed with 2 tests for rendering, installing, and
  removing the XDG autostart entry; desktop typecheck and production build passed; Playwright desktop/mobile smoke
  verified the panel is visible, Enable is disabled in browser preview, Check remains non-mutating, and text fits.
- 2026-07-03 desktop start-on-boot full check: `pnpm check`, `pnpm verify:docs`, `pnpm detect:audio`, Rust
  `cargo check`, Rust `cargo test`, `pnpm verify:vm`, touched-file line-length check, `git diff --check`, and GSD
  roadmap readback passed.
- 2026-07-03 VM SSH evidence collector: added `scripts/collect-vm-evidence-ssh.sh`, a dry-run-first host helper that
  prints the guest collector, `scp`, and local verifier commands, then runs them only with `--execute`.
- 2026-07-03 VM SSH evidence validation: `bash scripts/verify-scripts.sh` passed with syntax/help checks, a dry-run
  output check, pnpm `--` separator coverage, and a fake SSH/SCP execution smoke that copied a verified evidence
  bundle and ran the real VM evidence verifier.
- 2026-07-03 VM SSH evidence full check: `pnpm check`, `pnpm verify:vm`, `pnpm verify:docs`,
  `pnpm verify:workflows`, touched-file line-length check, and `git diff --check` passed. `shellcheck` was not
  installed on this host, so that optional check was skipped.
- 2026-07-03 VM SSH release-readiness recheck: real preflight still failed closed on missing signing public key, tag
  `v0.1.0`, and GitHub secrets `BUNNY_STORAGE_ZONE`, `BUNNY_ACCESS_KEY`, and `LOOPWIRE_RELEASE_PRIVATE_KEY`.
- 2026-07-03 v0.1.0 release-candidate notes: added `apps/docs/docs/release-notes/0.1.0.md`, linked it in the
  VitePress release-note sidebar, and updated the release-note workflow to require candidate disclaimers before public
  artifacts exist.
- 2026-07-03 v0.1.0 release-note validation: `pnpm verify:docs`, `pnpm --filter @loopwire/docs docs:build`,
  `bash scripts/verify-scripts.sh`, `pnpm check`, touched-file line-length check, and `git diff --check` passed.
  Release readiness now reports `ok: versioned release notes` and still fails closed on missing signing public key,
  tag `v0.1.0`, and required GitHub secrets.
- 2026-07-03 PipeWire picker enumeration: added read-only `pw-link -i` playback target enumeration and `pw-link -o`
  source enumeration in `@loopwire/audio-host`, with typed diagnostics for failed probes. No live host audio mutation
  was performed.
- 2026-07-03 PipeWire picker validation: new detector tests first failed against manual fallback, then passed with
  audio-host at 38 tests. Audio-host typecheck/build, `pnpm verify:docs`, docs contract guards, touched-file
  line/trailing-whitespace checks, `pnpm check`, `pnpm detect:audio`, and Rust `cargo check` passed.
- 2026-07-03 PipeWire picker host proof: a read-only built-package probe listed 7 PipeWire playback target group(s)
  from `pw-link -i` and 11 PipeWire source group(s) from `pw-link -o` on this host.
- 2026-07-03 code graph fallback: codebase-memory MCP `index_repository`, `list_projects`, `search_graph`, and
  `search_code` failed with `Transport closed`, so this slice used focused shell reads after the required graph attempt.
- 2026-07-03 PipeWire physical monitor links: extended the native PipeWire adapter to plan, apply, verify, unload, and
  roll back configured output monitor ports to existing physical monitor sink input ports. This earlier limitation for
  monitors without a `deviceName` was superseded by guarded native PipeWire virtual monitor sink creation.
- 2026-07-03 PipeWire physical monitor validation: new fake-runner tests first failed against route-only behavior, then
  passed with audio-host at 42 tests. Audio-host typecheck/build, `pnpm verify:docs`, touched-file
  line/trailing-whitespace checks, `pnpm check`, `pnpm detect:audio`, Rust `cargo check`, and docs preview HTTP 200
  passed. Read-only host probe still listed 7 PipeWire playback target group(s) and 11 source group(s).
- 2026-07-03 JACK existing-port adapter: added dry-run-by-default native JACK routing for existing route ports and
  physical monitor sink ports through `jack_lsp`, `jack_connect`, and `jack_disconnect`; non-unity gain and virtual
  monitor sinks fail before host commands. No live host audio mutation was performed.
- 2026-07-03 JACK VM target: added `fedora-kde-jack` to the manual VM matrix. `pnpm vm:plan --target
  fedora-kde-jack` renders the Fedora bootstrap command with `jack-audio-connection-kit`. No VM was launched.
- 2026-07-03 JACK validation: new fake-runner tests first failed because `createJackGraphRuntimeAdapter` did not
  exist, then passed with audio-host at 52 tests. Audio-host typecheck/build, `pnpm verify:docs`, `pnpm verify:vm`,
  touched-file line/trailing-whitespace checks, `pnpm check`, `pnpm detect:audio`, Rust `cargo check`, and docs preview
  HTTP 200 passed. Live-safe detection still reports JACK unavailable on this host because `jack_lsp` is missing.
- 2026-07-03 code graph fallback: codebase-memory MCP `index_repository`, `search_graph`, and `search_code` failed
  with `Transport closed`, so this JACK slice used focused shell reads after the required graph attempt.
- 2026-07-03 JACK picker enumeration: added read-only `jack_lsp -p` parsing for desktop source candidates from JACK
  output ports and physical monitor target candidates from JACK input ports. Desktop notes now describe JACK ports
  instead of running app streams. No live host audio mutation was performed.
- 2026-07-03 JACK picker validation: new detector tests first failed against manual/static backend behavior, then
  passed with audio-host at 56 tests. Audio-host typecheck/build, desktop typecheck, `pnpm verify:docs`, touched-file
  line/trailing-whitespace checks, `pnpm check`, `pnpm detect:audio`, Rust `cargo check`, `pnpm verify:vm`,
  `pnpm vm:plan --target fedora-kde-jack`, and docs preview HTTP 200 passed. Live-safe detection still reports JACK
  unavailable on this host because `jack_lsp` is missing.
- 2026-07-03 code graph fallback: codebase-memory MCP `index_status`, `list_projects`, `index_repository`,
  `search_graph`, and `search_code` failed with `Transport closed`, so this JACK picker slice used focused shell reads
  after the required graph attempt.
- 2026-07-03 native host-backed output picker: core output-bus creation now preserves output `deviceName` values and
  supports a `host-device` existing-input routing mode that auto-routes only host-backed sources. The desktop output
  picker reuses detected PipeWire/JACK target ports as host-backed outputs, while new native-backend source additions
  prefer an existing host-backed output over app-only virtual buses. No live host audio mutation was performed.
- 2026-07-03 native host-backed output validation: new core tests first failed against missing output `deviceName`
  persistence and over-broad native output routing, then passed with core at 38 tests. Core typecheck, desktop
  typecheck, `pnpm verify:docs`, touched-file line/trailing-whitespace checks, `git diff --check`, `pnpm check`,
  `pnpm detect:audio`, `pnpm verify:vm`, Rust `cargo check`, and docs preview HTTP 200 passed. Live-safe detection
  still reports JACK unavailable on this host because `jack_lsp` is missing.
- 2026-07-03 code graph fallback: codebase-memory MCP `index_status` and `search_graph` failed with
  `Transport closed`, so this native host-backed output slice used focused shell reads after the required graph
  attempt.
- 2026-07-03 support bundle collector: added `scripts/collect-support-bundle.mjs` and `pnpm collect:support` for
  redacted cross-system bug-report bundles. The quick profile writes `support-bundle.json`, `command-results.tsv`,
  `notes.md`, `detect-audio.json`, `ct-host-check.log`, and `autostart-status.log`; the full profile also captures
  workspace check and Tauri Rust compile logs. The collector does not upload data, publish artifacts, launch VMs, or
  mutate host audio.
- 2026-07-03 support bundle validation: `pnpm verify:scripts` first failed because the collector was missing, then
  passed after implementation and covered syntax, help, quick bundle creation, manifest shape, expected files, and a
  hostname leak guard. Targeted quick bundle smoke passed with three successful commands. `pnpm verify:docs`,
  `pnpm check`, touched-file line/trailing-whitespace checks, `git diff --check`, `pnpm detect:audio`,
  `pnpm verify:vm`, Rust `cargo check`, docs preview HTTP 200, and package-script support bundle smoke passed. Live-safe
  detection still reports JACK unavailable on this host because `jack_lsp` is missing.
- 2026-07-03 code graph fallback: codebase-memory MCP `index_status`, `search_graph`, and `index_repository` failed
  with `Transport closed`, so this support-bundle slice used focused shell reads after the required graph attempt.
- 2026-07-03 VM support-bundle evidence: `scripts/collect-vm-evidence.sh` now runs the redacted support bundle
  collector inside each guest evidence run and stores the result under `support-bundle/`. `scripts/verify-vm-evidence.sh`
  requires `support-bundle.log`, nested support bundle manifest, command ledger, and notes, and it requires a successful
  top-level `support-bundle` command row before VM evidence can pass. This strengthens future operator-run VM proof
  without changing support-matrix rows or claiming public release support.
- 2026-07-03 VM support-bundle validation: `pnpm verify:scripts` first failed on missing `support-bundle.log`, then
  passed after the collector and fixture updates. Targeted `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm verify:vm`,
  and a real local `collect-vm-evidence.sh` smoke with a generated PNG passed; the smoke produced a nested
  `loopwire.support-bundle` manifest with `redacted: true` and 7 top-level command rows. `pnpm check`,
  `pnpm detect:audio`, Rust `cargo check`, touched-file line/trailing-whitespace checks, `git diff --check`, and docs
  preview HTTP 200 passed. Live-safe detection still reports JACK unavailable on this host because `jack_lsp` is
  missing.
- 2026-07-03 code graph fallback: codebase-memory MCP `index_status`, `search_graph`, `search_code`, and
  `index_repository` failed with `Transport closed`, so this VM evidence slice used focused shell reads after the
  required graph attempt.
- 2026-07-03 release signing key ceremony: added `scripts/prepare-release-signing-key.sh` and `pnpm release:prepare-key`.
  The helper requires an explicit private key path, refuses repo-local private keys, refuses overwrites without
  `--force`, derives `packaging/release-signing-public.pem` by default, verifies the key pair against a temporary
  `SHA256SUMS` payload, and prints the existing GitHub secret setup and release-readiness commands. It does not upload
  secrets or publish artifacts.
- 2026-07-03 release key validation: `pnpm release:prepare-key -- --private-key-out "$tmp_private" --public-key-out
  "$tmp_public"` generated and verified a temporary key pair, and `pnpm verify:release-readiness -- --repo
  sandwichfarm/loopwire --tag v0.1.0 --public-key "$tmp_public" --skip-gh --skip-tag` passed. `pnpm verify:scripts`
  covers helper syntax, help, temp key generation, public/private key parsing, unsafe repo-local private-key rejection,
  and release-readiness parsing through a pnpm `--` separator. `pnpm verify:docs`, `pnpm check`, `pnpm detect:audio`,
  `pnpm verify:vm`, Rust `cargo check`, touched-file line/trailing-whitespace checks, `git diff --check`, and docs
  preview HTTP 200 passed.
- 2026-07-03 release readiness readback: real `pnpm verify:release-readiness -- --repo sandwichfarm/loopwire --tag
  v0.1.0` still fails closed on missing `packaging/release-signing-public.pem`, missing local/remote tag `v0.1.0`, and
  missing GitHub secrets `BUNNY_STORAGE_ZONE`, `BUNNY_ACCESS_KEY`, and `LOOPWIRE_RELEASE_PRIVATE_KEY`.
- 2026-07-03 code graph fallback: codebase-memory MCP `index_status`, `search_graph`, `search_code`, and
  `index_repository` failed with `Transport closed`, so this release key ceremony slice used focused shell reads after
  the required graph attempt.
- 2026-07-03 VM target preflight: `scripts/vm-matrix.sh doctor --target arch-hyprland-pipewire` now reports target
  metadata, checks `qemu-system-x86_64`, prints `host-install-hint`, and emits guest/host evidence handoff commands.
  `pnpm vm:doctor -- --target arch-hyprland-pipewire` now parses the pnpm `--` separator and fails closed on this host
  because `qemu-system-x86_64` and `qemu-img` are missing; KVM is available and SSH is present. No packages were
  installed and no VM was launched.
- 2026-07-03 VM target preflight validation: a red check first confirmed `doctor --target` lacked target context, then
  `bash scripts/verify-scripts.sh`, `bash scripts/vm-matrix.sh validate`, `bash scripts/verify-docs.sh`, `pnpm check`,
  `pnpm detect:audio`, Rust `cargo check`, `pnpm verify:vm && pnpm verify:docs`, touched-file line-length check,
  `git diff --check`, and docs preview HTTP 200 passed. `shellcheck` is not installed. codebase-memory MCP
  `index_repository` still fails with `Transport closed`, so this slice used focused shell reads after the graph
  attempt.
- 2026-07-03 native route mute: PipeWire and JACK adapters now keep muted routes in their host plans. Live apply
  disconnects any existing configured muted PipeWire/JACK edge, verification fails if muted edges remain connected,
  and capability reports now show native PipeWire/JACK `supportsPerEdgeMute: true` while keeping per-edge gain and
  virtual-node creation as gaps. No live host audio mutation was performed.
- 2026-07-03 native route mute validation: tests first failed because muted native routes were ignored and verification
  passed stale links, then passed after implementation. `pnpm --filter @loopwire/audio-host test`, audio-host
  typecheck, `pnpm verify:docs`, `pnpm detect:audio`, `pnpm check`, Rust `cargo check`, `pnpm verify:vm`, touched-file
  line-length check, `git diff --check`, and docs preview HTTP 200 passed. codebase-memory MCP `index_repository`
  still fails with `Transport closed`, so this slice used focused shell reads after the required graph attempts.
- 2026-07-03 PulseAudio startup pending mode: the new regression first failed because absent matching streams still
  returned hard failure even when the adapter was constructed for pending startup verification. After implementation,
  strict PulseAudio switch verification remains the default and startup/background restore can report
  `Pending matching PulseAudio stream(s)` without rolling back prepared virtual sinks.
- 2026-07-03 PulseAudio startup pending validation: `pnpm --filter @loopwire/audio-host test` passed with 62 tests,
  `pnpm --filter @loopwire/audio-host typecheck` passed, `pnpm --filter @loopwire/desktop typecheck` passed with zero
  Svelte diagnostics, `node --check scripts/restore-background.mjs` passed, `pnpm verify:docs`, `pnpm check`,
  `pnpm detect:audio`, `pnpm verify:vm`, Rust `cargo check`, `git diff --check`, touched-file trailing-whitespace and
  line-length checks, docs preview HTTP 200, and GSD milestone/roadmap queries passed. No live host audio mutation was
  performed. codebase-memory MCP `index_repository` still fails with `Transport closed`, so this slice used focused
  shell reads after the required graph attempt.
- 2026-07-03 published-release verifier offline mode: `scripts/verify-published-release.sh` can now verify a local
  signed release directory without GitHub access, checks `SHA256SUMS.sig`, requires at least one
  `loopwire-linux-*.tar.gz` asset, verifies every `SHA256SUMS` entry, installs from the release directory, and runs the
  installed binary.
- 2026-07-03 published-release verifier validation: `bash scripts/verify-scripts.sh` now creates a signed fake release
  directory, verifies it through `verify-published-release.sh --release-dir`, confirms the installed binary output, and
  rejects a tampered tarball. `pnpm verify:docs` passed after documenting the offline verifier path. No GitHub Release
  was created and no secrets were changed. codebase-memory MCP `index_repository` still fails with `Transport closed`,
  so this slice used focused shell reads after the required graph attempt.
- 2026-07-03 apt VM bootstrap fix: Debian and Ubuntu cloud-init guest commands now run
  `sudo npm install -g pnpm@11.3.0` after installing `nodejs` and `npm`, before the shared validation commands call
  `pnpm install --frozen-lockfile`. This keeps apt-based VM evidence runs aligned with the root package manager pin.
- 2026-07-03 apt VM bootstrap validation: `bash -n scripts/vm-matrix.sh scripts/verify-scripts.sh scripts/verify-docs.sh`,
  `bash scripts/vm-matrix.sh validate`, rendered Ubuntu and Debian cloud-init smoke with grep checks for
  `pnpm@11.3.0`, `pnpm verify:docs`, `pnpm check`, `pnpm detect:audio`, Rust `cargo check`, `pnpm verify:vm`,
  `git diff --check`, touched-file trailing-whitespace and line-length checks, docs preview HTTP 200, and GSD
  milestone/roadmap queries passed. No VM was launched and no support matrix row was promoted. codebase-memory MCP
  `index_repository` still fails with `Transport closed`, so this slice used focused shell reads after the required
  graph attempt.
- 2026-07-03 NixOS VM evidence handoff: `scripts/vm-matrix.sh` now emits the Nix target evidence collector as
  `nix develop --command bash scripts/collect-vm-evidence.sh ...` in doctor output, guest plans, and rendered
  cloud-init commands. Non-Nix targets continue to run the collector directly.
- 2026-07-03 NixOS VM evidence validation: `bash -n scripts/vm-matrix.sh scripts/verify-scripts.sh scripts/verify-docs.sh`,
  `bash scripts/vm-matrix.sh validate`, a rendered NixOS cloud-init grep smoke, `vm-matrix.sh doctor --target
  nixos-gnome-pipewire` readback, `pnpm verify:docs`, `bash scripts/verify-scripts.sh`, `pnpm check`,
  `pnpm detect:audio`, Rust `cargo check`, `pnpm verify:vm`, `git diff --check`, touched-file trailing-whitespace and
  line-length checks, docs preview HTTP 200, and GSD milestone/roadmap queries passed. No VM was launched and no
  support matrix row was promoted. codebase-memory MCP `index_repository` still fails with `Transport closed`, so this
  slice used focused shell reads after the required graph attempt.
- 2026-07-03 PulseAudio pending route refresh: `PactlVirtualSinkRuntimeAdapter.refreshRoutes` now re-runs only matching
  PulseAudio sink-input moves and stream controls for the selected configuration. Source-checkout
  `restore-background.mjs` can use `--retry-pending-ms` and `--retry-interval-ms` in live PulseAudio mode to refresh
  late-starting app streams after startup verification reports `Pending matching PulseAudio stream(s)`. The source
  systemd renderer validates and passes the retry flags.
- 2026-07-03 PulseAudio pending route refresh validation: `pnpm --filter @loopwire/audio-host test` passed with 63
  tests, audio-host typecheck passed, `node --check scripts/restore-background.mjs` passed, the restore CLI rejected
  `--retry-pending-ms` outside live mode, `pnpm verify:autostart`, `pnpm verify:scripts`, `pnpm verify:docs`,
  `pnpm check`, `pnpm detect:audio`, Rust `cargo check`, `pnpm verify:vm`, `git diff --check`, touched-file
  trailing-whitespace and line-length checks, docs preview HTTP 200, and GSD milestone/roadmap queries passed. No live
  host audio mutation was performed, no VM was launched, and no support matrix row was promoted.
- 2026-07-03 PulseAudio pending route refresh code graph fallback: codebase-memory MCP `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempt.
- 2026-07-03 packaged background restore: `scripts/package-release.sh` now creates a `loopwire` launcher, places the
  Tauri GUI binary at `libexec/loopwire/loopwire-gui`, and bundles `restore-background.mjs` plus compiled
  core/audio-host assets under `libexec/loopwire`. `scripts/install.sh`, the AUR template, and the Nix template now
  install those support files so `loopwire --background ...` can run from installed artifacts.
- 2026-07-03 packaged background restore validation: `pnpm verify:release` passed and now proves
  `loopwire --background --help` from both the extracted tarball and installed prefix. `pnpm verify:install`,
  `pnpm verify:packaging`, `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm verify:aur`, `pnpm check`,
  `pnpm detect:audio`, Rust `cargo check`, `pnpm verify:vm`, `git diff --check`, touched-file trailing-whitespace and
  line-length checks, docs preview HTTP 200, and GSD roadmap readback passed. No public release was created, no secrets
  were changed, no VM was launched, and no support matrix row was promoted.
- 2026-07-03 packaged background restore code graph fallback: codebase-memory MCP `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempt.
- 2026-07-03 desktop restore-on-boot UI: the Tauri shell now renders, installs, reports, and removes a user-scoped
  background restore systemd unit under `${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user`. The Svelte sidebar now has
  separate **Open on boot** and **Restore on boot** cards so users can choose GUI autostart independently from
  background audio restore.
- 2026-07-03 desktop restore-on-boot validation: Rust tests passed with 5 tests covering XDG autostart, state writes,
  background unit rendering, install, status, and removal. Desktop typecheck and build passed. Playwright desktop/mobile
  smoke at `http://127.0.0.1:5181/` verified both startup cards, restore Check/Enable buttons, screenshots, and no
  horizontal overflow. `pnpm verify:docs`, `pnpm check`, `pnpm detect:audio`, Rust `cargo check`, Rust
  `cargo fmt --check`, `pnpm verify:vm`, `git diff --check`, touched-file trailing-whitespace and line-length checks,
  docs preview HTTP 200, and GSD roadmap readback passed. No public release was created, no secrets were changed, no VM
  was launched, and no support matrix row was promoted.
- 2026-07-03 desktop restore-on-boot code graph fallback: codebase-memory MCP `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempt.
- 2026-07-03 VM desktop launch evidence: `scripts/collect-vm-evidence.sh` now starts the Loopwire desktop shell through
  Vite on a guest-local port, polls for the Loopwire shell, records `desktop-launch.log`, and writes a required
  `desktop-launch` command ledger row. `scripts/verify-vm-evidence.sh` now rejects evidence bundles without that launch
  proof, and `scripts/collect-vm-evidence-ssh.sh` forwards `--desktop-port` for target guests with port conflicts.
- 2026-07-03 VM desktop launch validation: `bash scripts/verify-scripts.sh`, `bash scripts/verify-docs.sh`,
  `bash scripts/vm-matrix.sh validate`, a real local `collect-vm-evidence.sh` smoke with generated PNG screenshot and
  `--desktop-port 5199`, `pnpm check`, `pnpm detect:audio`, `pnpm verify:vm`, and Rust `cargo check` passed. The real
  collector ledger showed `desktop-launch` exit 0 and `vm-evidence-verify` exit 0. No public release was created, no
  secrets were changed, no VM was launched, and no support matrix row was promoted.
- 2026-07-03 VM desktop launch code graph fallback: codebase-memory MCP `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempt.
- 2026-07-03 native PipeWire virtual output sinks: `PipeWireGraphRuntimeAdapter` now creates missing output buses as
  Loopwire-owned PipeWire sink nodes with `pw-cli create-node adapter`, maps routes to the generated sink names, and
  destroys those selected virtual sink nodes during unload or rollback. The adapter keeps dry-run mode non-mutating and
  still rejects virtual monitor sinks and non-unity route gain before host commands run.
- 2026-07-03 native PipeWire virtual output validation: the new regression tests first failed because outputs without
  `deviceName` were rejected as missing native PipeWire link targets. After implementation,
  `pnpm --filter @loopwire/audio-host test`, `pnpm --filter @loopwire/audio-host typecheck`,
  `bash scripts/verify-docs.sh`, `pnpm detect:audio`, `pnpm verify:vm`, Rust `cargo check`, line-length hygiene,
  `git diff --check`, `pnpm check`, and docs preview HTTP 200 for the homepage, backend guide, and support matrix
  passed. No live `pw-cli create-node`, live `pw-link`, public release, secret write, VM launch, or support matrix
  promotion was performed.
- 2026-07-03 native PipeWire virtual output code graph fallback: codebase-memory MCP `list_projects` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempt.
- 2026-07-03 native PipeWire virtual monitor sinks: `PipeWireGraphRuntimeAdapter` now creates missing monitor endpoints
  as Loopwire-owned PipeWire sink nodes with `pw-cli create-node adapter`, maps monitor links to generated sink names,
  destroys selected virtual monitor nodes during unload, and rolls them back when later monitor linking fails. The
  adapter still keeps dry-run mode non-mutating and rejects non-unity route gain before host commands run.
- 2026-07-03 native PipeWire virtual monitor validation: the new regression tests first failed because monitors without
  `deviceName` were rejected as requiring an existing sink. After implementation,
  `pnpm --filter @loopwire/audio-host test` passed with 68 tests, audio-host typecheck passed,
  `bash scripts/verify-docs.sh` passed, `pnpm detect:audio` passed and reported PipeWire gaps as only
  `per-edge gain controls`, `pnpm verify:vm` passed, Rust `cargo check` passed, `pnpm check` passed,
  line-length hygiene passed, `git diff --check` passed, and docs preview HTTP 200 passed for the homepage,
  backend guide, configurations guide, and support matrix. No live `pw-cli create-node`, live `pw-link`, public release,
  secret write, VM launch, or support matrix promotion was performed.
- 2026-07-03 native PipeWire virtual monitor code graph fallback: codebase-memory MCP `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempt.
- 2026-07-03 desktop routing canvas UX: `apps/desktop/src/App.svelte` now derives cable SVG paths from source, route,
  and output positions; shows route count, muted count, and backend board status; adds endpoint sockets; and lets
  configuration action buttons wrap before labels overflow.
- 2026-07-03 desktop routing canvas validation: codebase-memory MCP `index_repository` failed with `Transport closed`,
  so this slice used focused shell reads after the required graph attempt. `pnpm --filter @loopwire/desktop typecheck`
  passed with 0 Svelte diagnostics, `pnpm --filter @loopwire/desktop build` passed, Playwright assertions passed at
  1440x920 and 390x844 against `http://127.0.0.1:4174/` with 3 lanes, 2 route cards, desktop cables visible, mobile
  cables hidden, no page errors, no text overflow, and no horizontal overflow. Full `pnpm check` passed. No backend
  mutation, public release, secret write, VM launch, or support matrix promotion was performed.
- 2026-07-03 desktop live-apply preflight: `apps/desktop/src/App.svelte` now shows an explicit backend placeholder
  instead of visually defaulting to PipeWire, gives the backend selector a unique accessible label, updates
  route-control semantics reactively after backend changes, and disables live arming when static backend blockers are
  present. Preflight blockers currently cover missing backend selection, native PipeWire/JACK non-unity gain, missing
  native source ports, JACK host-output gaps, JACK monitor targets, and unsupported ALSA live apply.
- 2026-07-03 desktop live-apply preflight validation: codebase-memory MCP `index_status` and `list_projects` failed
  with `Transport closed`, so this slice used focused shell reads after the required graph attempt. Desktop typecheck
  and build passed. Playwright assertions passed at 1440x920 and 390x844 against `http://127.0.0.1:4175/`: initial
  state had empty backend value, `No backend` board status, blocked preflight, and disabled live button; selecting
  PipeWire changed the board status to PipeWire, semantics to link mode, and preflight to the expected gain/source
  blockers without page errors, text overflow, or horizontal overflow. `pnpm verify:docs` and full `pnpm check` passed.
  No backend mutation, public release, secret write, VM launch, or support matrix promotion was performed.
- 2026-07-03 VM cloud-init handoff verifier: `scripts/vm-matrix.sh verify-cloud-init` now renders cloud-init and
  guest commands to a temp directory by default, validates target hostnames, target markers, metadata, repository
  clone, backend detection, target-specific evidence collection, apt pnpm pinning, Nix `nix develop` usage, and
  `pnpm check` coverage for pacman/dnf targets. `pnpm verify:vm` and the GitHub VM matrix workflow now run this gate.
- 2026-07-03 VM cloud-init handoff validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempt. `bash -n
  scripts/vm-matrix.sh`, `bash scripts/vm-matrix.sh verify-cloud-init`, target-scoped `verify-cloud-init --target
  fedora-kde-jack --output "$tmp_dir"`, `pnpm verify:vm`, `pnpm verify:workflows`, `pnpm verify:docs`,
  `pnpm verify:scripts`, touched-file line-length checks, `git diff --check`, and full `pnpm check` passed. No VM was
  launched, no distro image was downloaded, no public release was created, no secrets were changed, and no support
  matrix row was promoted.
- 2026-07-03 release-note publishability gate: `scripts/verify-release-readiness.sh` now rejects versioned notes that
  still look like candidate/unpublished notes by default. The release workflow invokes that notes gate before artifact
  staging, while local smoke tests can pass `--allow-candidate-notes` explicitly to keep the current pre-release
  candidate page verifiable without allowing publication.
- 2026-07-03 release-note publishability validation: codebase-memory MCP `index_status` and `index_repository` failed
  with `Transport closed`, so this slice used focused shell reads after the required graph attempt. A temporary-key
  smoke proved default readiness fails on the current `v0.1.0` candidate page and passes only with
  `--allow-candidate-notes`; `pnpm verify:workflows`, `pnpm verify:docs`, `pnpm verify:scripts`, `bash -n` for touched
  shell scripts, touched-file line-length checks, `git diff --check`, and full `pnpm check` passed. No public release
  was created, no secrets were changed, no tag was pushed, no VM was launched, and no support matrix row was promoted.
- 2026-07-03 release evidence preflight capture: `scripts/collect-release-evidence.mjs` now accepts `--release-tag`,
  `--repo`, and `--public-key`, records release metadata in `release-evidence.json`, runs candidate readiness as a
  required command, and records the strict publish preflight as optional full-profile evidence. The docs homepage
  release ceremony command now includes the required `--output-dir`.
- 2026-07-03 release evidence validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempt. `node --check
  scripts/collect-release-evidence.mjs`, collector `--help`, offline candidate readiness, `bash -n` for touched shell
  verifiers, quick evidence collection, full evidence collection, touched-file line-length checks, touched-file
  trailing-whitespace checks, `git diff --check`, `pnpm check`, `gsd-sdk query init.milestone-op`, and
  `gsd-sdk query roadmap.analyze --format json` passed. The quick collector manifest included required
  `release-readiness-candidate` exit 0; the full collector manifest kept `release-readiness-publish-preflight` optional
  and captured its expected exit 1. No public release was created, no signing key was generated, no secrets were
  changed, no tag was pushed, no VM was launched, and no support matrix row was promoted.
- 2026-07-03 VM environment manifest: `scripts/collect-vm-evidence.sh` now writes `environment.json` with the selected
  `vm/targets.tsv` row and observed guest distro, desktop/session, architecture, display availability, and kernel.
  `scripts/verify-vm-evidence.sh` now requires that manifest and rejects evidence whose observed distro,
  desktop/session, or architecture does not match the selected target.
- 2026-07-03 VM environment validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempt. `bash -n` for touched
  scripts, verifier help readback, touched-file line-length checks, touched-file trailing-whitespace checks,
  `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm verify:vm`, a real local
  `collect-vm-evidence.sh --target arch-hyprland-pipewire` smoke with generated PNG screenshot, `pnpm check`,
  `git diff --check`, `gsd-sdk query init.milestone-op`, and `gsd-sdk query roadmap.analyze --format json` passed.
  The local smoke captured observed Arch Linux, Hyprland, Wayland, and x86_64 in `environment.json`. No public release
  was created, no signing key was generated, no secrets were changed, no tag was pushed, no VM was launched, and no
  support matrix row was promoted.
- 2026-07-04 desktop route-control semantics UX: the desktop semantics strip now reports native PipeWire route mute as
  implemented by disconnecting links and native JACK route mute as implemented by disconnecting connections. Both
  messages keep route gain marked as planned, matching the backend adapters and docs.
- 2026-07-04 desktop route-control semantics validation: codebase-memory MCP `index_status` and `index_repository`
  failed with `Transport closed`, so this slice used focused shell reads after the required graph attempt.
  `pnpm --filter @loopwire/desktop typecheck`, `pnpm --filter @loopwire/desktop build`, `pnpm verify:docs`,
  touched-file line-length checks, touched-file trailing-whitespace checks, Playwright desktop/mobile checks against
  `http://127.0.0.1:4176/`, `pnpm check`, `git diff --check`, `gsd-sdk query init.milestone-op`, and
  `gsd-sdk query roadmap.analyze --format json` passed. Playwright verified the PipeWire semantics text on 1440x920
  and 390x844 viewports, captured `/tmp/loopwire-semantics-desktop.png` and `/tmp/loopwire-semantics-mobile.png`, and
  found no horizontal overflow or clipped text containers. No host audio mutation, public release, secret write, tag
  push, VM launch, or support matrix promotion was performed.
- 2026-07-04 desktop endpoint removal UX: core configuration mutations now remove input sources, output buses, and
  monitors. Input/output removal prunes dependent routes, output removal refuses to remove the final output, and
  monitor removal clears hidden-monitor state. The desktop source, output, and monitor cards expose compact remove
  controls, and docs/release notes describe the route-pruning behavior.
- 2026-07-04 desktop endpoint removal validation: codebase-memory MCP `index_status` failed with `Transport closed`,
  so this slice used focused shell reads after the required graph attempt. `pnpm --filter @loopwire/core test`,
  `pnpm --filter @loopwire/core typecheck`, `pnpm --filter @loopwire/desktop typecheck`,
  `pnpm --filter @loopwire/desktop build`, `pnpm verify:docs`, Playwright desktop/mobile checks against
  `http://127.0.0.1:4177/`, `pnpm check`, touched-file line-length checks, touched-file trailing-whitespace checks,
  `git diff --check`, `gsd-sdk query init.milestone-op`, and `gsd-sdk query roadmap.analyze --format json` passed.
  Playwright verified source deletion removes its route, final-output deletion is disabled, output deletion prunes
  routes, monitor deletion clears hidden state, and both 1440x920 and 390x844 viewports had no horizontal overflow.
  Screenshots were captured at `/tmp/loopwire-endpoint-removal-desktop.png` and
  `/tmp/loopwire-endpoint-removal-mobile.png`. No host audio mutation, public release, secret write, tag push, VM
  launch, or support matrix promotion was performed.
- 2026-07-04 desktop route edge lifecycle: core configuration mutations now add and remove individual routes. Route
  addition requires existing input/output endpoints, rejects duplicate source/output pairs, and preserves independent
  gain/mute state per route. Graph validation now also rejects duplicate route ids and duplicate route pairs.
- 2026-07-04 desktop route edge validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempt.
  `pnpm --filter @loopwire/core test`, `pnpm --filter @loopwire/core typecheck`,
  `pnpm --filter @loopwire/desktop typecheck`, `pnpm --filter @loopwire/desktop build`, `pnpm verify:docs`,
  Playwright desktop/mobile checks against `http://127.0.0.1:4178/`, `pnpm check`, touched-file line-length checks,
  touched-file trailing-whitespace checks, `git diff --check`, `gsd-sdk query init.milestone-op`, and
  `gsd-sdk query roadmap.analyze --format json` passed. Playwright verified duplicate route creation is disabled,
  route removal preserves endpoints, removed routes can be re-added through the route lane, and both 1440x920 and
  390x844 viewports had no horizontal overflow. Screenshots were captured at `/tmp/loopwire-route-edge-desktop.png`
  and `/tmp/loopwire-route-edge-mobile.png`. No host audio mutation, public release, secret write, tag push, VM
  launch, or support matrix promotion was performed.
- 2026-07-04 desktop host binding UX: core configuration mutation now sets or clears optional `deviceName` values on
  input, output, and monitor endpoints. The desktop source and output cards expose manual host binding fields for
  backend enumeration gaps, and monitor target editing uses the same core mutation path.
- 2026-07-04 desktop host binding validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempt.
  `pnpm --filter @loopwire/core test`, `pnpm --filter @loopwire/core typecheck`,
  `pnpm --filter @loopwire/desktop typecheck`, `pnpm --filter @loopwire/desktop build`, `pnpm verify:docs`,
  Playwright desktop/mobile checks against `http://127.0.0.1:4179/`, `pnpm check`, touched-file line-length checks,
  touched-file trailing-whitespace checks, `git diff --check`, `gsd-sdk query init.milestone-op`, and
  `gsd-sdk query roadmap.analyze --format json` passed. Playwright verified setting and clearing host source bindings,
  setting host target bindings, status messaging, and no horizontal overflow at 1440x920 and 390x844. Screenshots were
  captured at `/tmp/loopwire-host-binding-desktop.png` and `/tmp/loopwire-host-binding-mobile.png`. No host audio
  mutation, public release, secret write, tag push, VM launch, or support matrix promotion was performed.
- 2026-07-04 scoped monitor visibility: new monitor hide/show writes are configuration-scoped in `hiddenMonitorIds`
  while legacy bare ids are still honored on read. The desktop now uses core `isMonitorHidden` instead of raw id
  membership, so same-id monitors in different configurations can have independent visibility.
- 2026-07-04 scoped monitor visibility validation: codebase-memory MCP `index_status` and `index_repository` failed
  with `Transport closed`, so this slice used focused shell reads after the required graph attempt.
  `pnpm --filter @loopwire/core test`, `pnpm --filter @loopwire/core typecheck`,
  `pnpm --filter @loopwire/desktop typecheck`, `pnpm --filter @loopwire/desktop build`, `pnpm verify:docs`,
  Playwright desktop/mobile checks against `http://127.0.0.1:4180/`, `pnpm check`, touched-file line-length checks,
  touched-file trailing-whitespace checks, `git diff --check`, `gsd-sdk query init.milestone-op`, and
  `gsd-sdk query roadmap.analyze --format json` passed. Playwright verified hiding Studio `Headphones` leaves Call
  `Headphones` visible, switching back to Studio preserves the hidden state, and both 1440x920 and 390x844 viewports
  had no horizontal overflow. Screenshots were captured at `/tmp/loopwire-monitor-scope-desktop.png` and
  `/tmp/loopwire-monitor-scope-mobile.png`. No host audio mutation, public release, secret write, tag push, VM launch,
  or support matrix promotion was performed.
- 2026-07-04 custom chrome decoration UX: the desktop Chrome selector now persists `native` or `custom` mode outside
  the audio state file. Custom mode calls Tauri `setDecorations(false)` before showing Loopwire-owned drag, minimize,
  and close controls; native mode calls `setDecorations(true)` and removes the custom title bar.
- 2026-07-04 custom chrome validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempt.
  `pnpm --filter @loopwire/desktop typecheck`, `pnpm --filter @loopwire/desktop build`, `pnpm verify:docs`, and
  `pnpm check` passed. Playwright desktop/mobile checks against `http://127.0.0.1:4181/` verified custom chrome
  persistence across reload, native restoration, and no horizontal overflow at 1440x920 and 390x844. A custom-mode
  desktop screenshot was captured at `/tmp/loopwire-chrome-custom-desktop.png`; native-restored screenshots were
  captured at `/tmp/loopwire-chrome-desktop.png` and `/tmp/loopwire-chrome-mobile.png`. No host audio mutation, public
  release, secret write, tag push, VM launch, or support matrix promotion was performed.
- 2026-07-04 restore-on-boot launcher resolution: the Tauri startup bridge now resolves packaged background restore
  launchers from both archive layout (`libexec/loopwire/loopwire-gui` -> `loopwire`) and installed layout
  (`lib/loopwire/loopwire-gui` -> `bin/loopwire`). A GUI binary with no launcher is rejected instead of writing a
  systemd unit that would run `loopwire-gui --background`.
- 2026-07-04 restore-on-boot launcher validation: codebase-memory MCP `index_status` and `index_repository` failed
  with `Transport closed`, so this slice used focused shell reads after the required graph attempt. `cargo fmt -- --check`,
  `cargo test`, `pnpm verify:docs`, `pnpm --filter @loopwire/desktop typecheck`, and `pnpm check` passed. Rust tests
  verified archive launcher resolution, installed launcher resolution, non-GUI launcher passthrough, and missing-launcher
  rejection. No host audio mutation, public release, secret write, tag push, VM launch, or support matrix promotion was
  performed.
- 2026-07-04 Bunny docs deployment helper: `scripts/deploy-docs-bunny.sh` now uploads built VitePress docs to Bunny
  Edge Storage with `PUT`, `AccessKey`, uppercase SHA256 `Checksum`, optional `BUNNY_STORAGE_ENDPOINT` regional host
  support, optional remote prefixes, and dry-run target readback. The docs deployment workflow now calls the helper,
  and `scripts/setup-github-secrets.sh` can set or check the optional endpoint secret.
- 2026-07-04 Bunny docs deployment validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempt. Official Bunny docs were
  checked for HTTP upload authentication, regional endpoints, raw upload bodies, and checksum behavior. `bash -n`
  passed for touched shell verifiers, manual Bunny dry-run printed two regional upload URLs, manual secret-helper
  dry-run printed the optional endpoint secret without writing secrets, and `pnpm verify:workflows`,
  `pnpm verify:docs`, `pnpm verify:scripts`, and `pnpm check` passed. No real Bunny deployment, secret write, public
  release, tag push, VM launch, host audio mutation, or support matrix promotion was performed.
- 2026-07-04 AArch64 release workflow lane: `.github/workflows/release.yml` now has a build matrix for `x86_64` on
  `ubuntu-22.04` and `aarch64` on `ubuntu-22.04-arm`. Each architecture stages and smoke-installs signed local
  artifacts, uploads only release attachments, and a single publish job downloads both lanes, regenerates one combined
  `SHA256SUMS`, signs it, verifies it, publishes the GitHub Release, and runs the post-publish installer smoke.
- 2026-07-04 AArch64 release workflow validation: codebase-memory MCP `index_status` and `index_repository` failed
  with `Transport closed`, so this slice used focused shell reads after the required graph attempt. Official GitHub
  runner/action sources were checked for ARM64 runner labels and current artifact action versions. `bash -n` for
  workflow/docs verifiers, Ruby workflow YAML parse, `pnpm verify:workflows`, `pnpm verify:docs`, touched-file
  line-length and trailing-whitespace checks, `git diff --check`, `pnpm check`, and GSD milestone/roadmap queries
  passed. No public release, secret write, tag push, VM launch, host audio mutation, or support matrix promotion was
  performed.
- 2026-07-04 multi-arch published-release verifier: `scripts/verify-published-release.sh` now requires the signed
  release directory to contain `loopwire-linux-x86_64.tar.gz` and `loopwire-linux-aarch64.tar.gz`, and verifies both
  assets have entries in `SHA256SUMS` before the installer smoke can pass.
- 2026-07-04 multi-arch published-release validation: codebase-memory MCP `index_status` and `index_repository` failed
  with `Transport closed`, so this slice used focused shell reads after the required graph attempt.
  `scripts/verify-scripts.sh` now builds both canonical fake release tarballs, verifies the good signed fixture, rejects
  a fixture missing the secondary architecture, and still rejects a tampered host-architecture tarball. `bash -n`
  passed for touched verifiers, `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm check`, touched-file line-length and
  trailing-whitespace checks, `git diff --check`, `gsd-sdk query init.milestone-op`, and
  `gsd-sdk query roadmap.analyze --format json` passed. No public release, secret write, tag push, VM launch, host
  audio mutation, or support matrix promotion was performed.
- 2026-07-04 non-mutating VM launch dry-run: `scripts/vm-matrix.sh launch` now returns before image existence checks,
  cloud-init rendering, overlay creation, seed ISO creation, or QEMU execution unless `--execute` is present. Dry-run
  output includes the operator image path, planned overlay path, planned seed path, and QEMU command.
- 2026-07-04 non-mutating VM launch validation: `scripts/verify-scripts.sh` now runs a launch dry-run with
  `LOOPWIRE_VM_ROOT` pointed at a temp path and a nonexistent operator image, asserts the planned paths are printed,
  asserts no VM root is written, and asserts `--execute` still rejects a missing image. `bash -n` for touched VM/docs
  verifiers, `pnpm verify:vm`, `pnpm verify:docs`, `pnpm verify:scripts`, and `pnpm check` passed. No VM was launched,
  no image was downloaded, no public release, secret write, tag push, host audio mutation, or support matrix promotion
  was performed.
- 2026-07-04 VM launch preflight tightening: `scripts/vm-matrix.sh doctor` now treats `cloud-localds` as required
  launch tooling instead of optional, matching the execute path that creates cloud-init seed media.
- 2026-07-04 VM launch preflight validation: `scripts/verify-scripts.sh` now asserts `vm:doctor` reports
  `cloud-localds=...`, and the VM docs/release notes describe missing `cloud-localds` as host setup work. `bash -n`
  for touched VM/docs verifiers, `pnpm verify:vm`, `pnpm verify:docs`, `pnpm verify:scripts`, and `pnpm check` passed.
  No VM was launched, no image was downloaded, no public release, secret write, tag push, host audio mutation, or
  support matrix promotion was performed.
- 2026-07-04 release evidence published-smoke mode: `scripts/collect-release-evidence.mjs` now includes
  `published-release-smoke` as optional full-profile evidence and supports `--require-published-release` to make that
  verifier mandatory for final release evidence. `--list-commands` prints the command plan as JSON without running
  commands or writing files.
- 2026-07-04 release evidence published-smoke validation: `node --check scripts/collect-release-evidence.mjs`,
  `bash -n scripts/verify-scripts.sh scripts/verify-docs.sh`, full-profile and required quick command-plan readbacks,
  `pnpm verify:scripts`, `pnpm verify:docs`, and `pnpm check` passed. No public release was created, no GitHub secrets
  were written, and no tag push, VM launch, image download, host audio mutation, or support matrix promotion was
  performed.
- 2026-07-04 VM evidence promotion guard: `scripts/promote-vm-evidence.mjs` now verifies a target evidence bundle with
  `scripts/verify-vm-evidence.sh`, confirms the target exists in `vm/targets.tsv`, supports `--dry-run`, and only
  promotes support-matrix rows from `Manual VM` to `Verified`.
- 2026-07-04 VM evidence promotion validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempt. `node --check
  scripts/promote-vm-evidence.mjs`, `bash -n scripts/verify-scripts.sh scripts/verify-docs.sh`,
  `pnpm verify:scripts`, `pnpm verify:docs`, and `pnpm check` passed. The script verifier exercised dry-run preview,
  temp-matrix promotion, already-verified no-op behavior, and failed-evidence rejection. No real VM was launched, no
  image was downloaded, and no real support matrix row was promoted.
- 2026-07-04 VM launch input guard: `scripts/vm-matrix.sh launch` now rejects invalid memory, CPU count, SSH port,
  and backing image-format values before printing or executing QEMU commands.
- 2026-07-04 VM launch input validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempt. `bash -n
  scripts/vm-matrix.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, targeted launch rejection assertions,
  `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm check`, `git diff --check`, and touched-file line-length checks
  passed. `scripts/verify-scripts.sh` now covers non-numeric memory, too-small memory, invalid CPU count, and
  unsupported image format launch requests. VM matrix docs, unreleased notes, and `scripts/verify-docs.sh` document and
  guard the launch input contract. No VM was launched, no image was downloaded, and no support matrix row was promoted.
- 2026-07-04 GitHub secret helper Bunny validation: `scripts/setup-github-secrets.sh` now rejects Bunny storage zones
  with slashes, storage endpoints with newlines, pull-zone hostnames that are URLs or paths, and remote prefixes with
  `.` or `..` path segments before dry-run output or `gh secret set`.
- 2026-07-04 GitHub secret helper Bunny validation evidence: codebase-memory MCP `index_status` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempt. `bash -n
  scripts/setup-github-secrets.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, targeted helper rejection
  assertions, `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm check`, and `git diff --check` passed. Release docs,
  unreleased notes, and `scripts/verify-docs.sh` document and guard the secret helper's Bunny validation contract. No
  GitHub secrets were written and no Bunny deployment or live docs smoke was performed.
- 2026-07-04 Bunny prefixed live-smoke alignment: `.github/workflows/deploy-docs.yml` now passes
  `--remote-prefix "$BUNNY_REMOTE_PREFIX"` to `scripts/verify-docs-live.sh` and reports the prefixed deployment URL.
  This keeps post-upload verification aligned with the deploy helper when one storage zone serves multiple paths.
- 2026-07-04 Bunny prefixed live-smoke validation: codebase-memory MCP `index_status` failed with `Transport closed`,
  so this slice used focused shell reads after the required graph attempt. `bash -n scripts/verify-github-workflows.sh
  scripts/verify-docs.sh`, Ruby YAML parsing for `.github/workflows/deploy-docs.yml`,
  `bash scripts/verify-github-workflows.sh`, `pnpm verify:docs`, `pnpm verify:workflows`, `pnpm check`,
  `git diff --check`, and touched-file line-length checks passed. Release docs, unreleased notes, and
  `scripts/verify-docs.sh` document and guard the prefixed live-smoke path. No Bunny deployment or live docs smoke was
  performed.
- 2026-07-04 installer archive path guard: `scripts/install.sh` now lists the signed/checksummed release tarball before
  extraction and rejects empty, absolute, or parent-traversing archive member paths. The VitePress public
  `apps/docs/docs/public/install.sh` asset was synced byte-for-byte from the canonical installer.
- 2026-07-04 installer archive path validation: codebase-memory MCP `index_status` failed with `Transport closed`, so
  this slice used focused shell reads after the required graph attempt. `bash -n scripts/install.sh
  apps/docs/docs/public/install.sh scripts/verify-install.sh scripts/verify-docs.sh`, `pnpm verify:install`,
  `pnpm verify:docs`, `cmp -s scripts/install.sh apps/docs/docs/public/install.sh`, `pnpm verify:scripts`,
  `pnpm check`, `git diff --check`, and touched-file line-length checks passed. `scripts/verify-install.sh` now signs
  a malicious tarball containing `../escape` and proves the installer rejects it before extraction. No public release,
  tag push, secret write, Bunny deployment, live URL smoke, VM launch, image download, or support matrix promotion was
  performed.
- 2026-07-04 release blocker manifest: `scripts/collect-release-evidence.mjs` now stores parsed
  `release.findings` and `release.blockers` in `release-evidence.json` from release-readiness logs, and
  `--summarize-release-readiness-log` can parse an existing preflight log without rerunning release checks.
- 2026-07-04 release blocker manifest validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempt. Real
  `pnpm verify:release-readiness -- --repo sandwichfarm/loopwire --tag v0.1.0` failed closed on the expected blockers:
  missing public key, candidate release-note wording, missing tag, and missing required GitHub secrets. `node --check
  scripts/collect-release-evidence.mjs`, `bash -n scripts/verify-scripts.sh scripts/verify-docs.sh`, direct log-summary
  JSON readback, `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm check`, quick evidence bundle manifest readback,
  touched-file line-length and trailing-whitespace checks, and `git diff --check` passed. No public release was created,
  no key was generated, no secrets were changed, no tag was pushed, no VM was launched, and no support matrix row was
  promoted.
- 2026-07-04 live-apply blocker list: desktop preflight now shows all live-apply blockers in a compact list when more
  than one issue prevents arming live apply. The aggregate message stays short, and each concrete blocker remains
  visible without requiring users to fix issues one at a time.
- 2026-07-04 live-apply blocker validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempt. Official PipeWire and
  JACK docs were checked before leaving backend gain work planned instead of faking graph-edge gain through unsafe CLI
  guesses. `pnpm --filter @loopwire/desktop typecheck`, `pnpm --filter @loopwire/desktop build`, `pnpm verify:docs`,
  Playwright desktop/mobile smoke against `http://127.0.0.1:4192/`, `pnpm test`, `pnpm check`, direct touched-file
  trailing-whitespace and line-length checks, and `git diff --check` passed. The Playwright smoke rendered exactly two
  PipeWire blockers and zero horizontal overflow at 1440x1100 and 390x900. Screenshots were written to
  `/tmp/loopwire-preflight-blockers-desktop.png` and `/tmp/loopwire-preflight-blockers-mobile.png`. No host audio
  mutation, public release, secret write, key generation, tag push, VM launch, or support matrix promotion was
  performed.
- 2026-07-04 VM launch SSH-port handoff: `scripts/vm-matrix.sh launch` now accepts `--ssh-port`, validates that it is
  in the TCP port range, uses it in the QEMU `hostfwd` network argument, and prints the matching
  `collect-vm-evidence-ssh.sh --port ...` command in dry-run output.
- 2026-07-04 VM launch SSH-port validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempt.
  `bash -n scripts/vm-matrix.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, launch dry-run readback with
  `--ssh-port 2322`, invalid-port rejection with `--ssh-port 70000`, `pnpm verify:scripts`, `pnpm verify:docs`,
  `pnpm verify:vm`, `pnpm check`, touched-file trailing-whitespace and line-length checks, and `git diff --check`
  passed. No VM was launched, no image was downloaded, and no public release, secret write, key generation, tag push,
  host audio mutation, or support matrix promotion was performed.
- 2026-07-04 VM collector port validation: `scripts/collect-vm-evidence.sh` now validates `--desktop-port`, and
  `scripts/collect-vm-evidence-ssh.sh` now validates both `--port` and `--desktop-port` before invoking SSH, SCP, Vite,
  or guest collection commands.
- 2026-07-04 VM collector port validation checks: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempt.
  `bash -n scripts/collect-vm-evidence.sh scripts/collect-vm-evidence-ssh.sh scripts/verify-scripts.sh
  scripts/verify-docs.sh`, direct negative checks for invalid SSH and desktop smoke ports, `pnpm verify:scripts`,
  `pnpm verify:docs`, `pnpm verify:vm`, `pnpm check`, touched-file trailing-whitespace and line-length checks, and
  `git diff --check` passed. No VM was launched, no image was downloaded, no public release, secret write, key
  generation, tag push, host audio mutation, or support matrix promotion was performed.
- 2026-07-04 installed-release VM evidence gate: `scripts/collect-vm-evidence.sh` can now run
  `scripts/verify-published-release.sh` inside a guest from either a guest-visible signed release directory or a GitHub
  release repo/tag, recording `published-release-smoke.log` and a `published-release-smoke` command ledger row.
  `scripts/verify-vm-evidence.sh --require-published-release` now rejects VM bundles that do not prove installed
  release smoke, and `scripts/collect-vm-evidence-ssh.sh` forwards the same strict release-smoke options into the guest
  and the host-side verifier.
- 2026-07-04 installed-release VM evidence validation: codebase-memory MCP `index_status` and `index_repository` failed
  with `Transport closed`, so this slice used focused shell reads after the required graph attempt. Focused syntax/help
  checks, missing-release-input rejection, SSH dry-run readback with `--published-release-dir`, `--release-public-key`,
  and `--require-published-release`, `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm verify:vm`, `pnpm check`,
  touched-file trailing-whitespace and line-length checks, and `git diff --check` passed. No VM was launched, no image
  was downloaded, no public release, secret write, key generation, tag push, host audio mutation, or support matrix
  promotion was performed.
- 2026-07-04 release evidence VM gate: `scripts/collect-release-evidence.mjs` now supports `--vm-target`,
  `--vm-evidence-dir`, and `--require-vm-evidence`. Full-profile evidence includes VM bundle verification as optional
  context by default, while quick or full profiles can make `scripts/verify-vm-evidence.sh` mandatory. When
  `--require-published-release` is also set, the VM verifier command inherits `--require-published-release`.
- 2026-07-04 release evidence VM gate validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempt. `node --check
  scripts/collect-release-evidence.mjs`, `bash -n scripts/verify-scripts.sh scripts/verify-docs.sh`, help readback,
  optional full-profile command-plan readback, required quick command-plan readback with published-release strictness,
  `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm verify:vm`, `pnpm check`, touched-file trailing-whitespace and
  line-length checks, and `git diff --check` passed. No VM was launched, no image was downloaded, no public release,
  secret write, key generation, tag push, host audio mutation, or support matrix promotion was performed.
- 2026-07-04 all-target release evidence gate: `scripts/collect-release-evidence.mjs` now expands
  `--vm-target all` from `vm/targets.tsv`, validates unknown target ids, supports repeated or comma-separated target
  values, and requires `{target}` in `--vm-evidence-dir` when multiple VM targets are selected. Multi-target command
  plans generate one `vm-evidence:<target>` verifier and log per target.
- 2026-07-04 all-target release evidence validation: codebase-memory MCP `index_status` and `index_repository` failed
  with `Transport closed`, so this slice used focused shell reads after the required graph attempt.
  `node --check scripts/collect-release-evidence.mjs`, `bash -n scripts/verify-scripts.sh scripts/verify-docs.sh`,
  all-target command-plan readback proving seven VM verifier commands with `--require-published-release`, negative
  readback for a shared multi-target evidence directory, `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm verify:vm`,
  `pnpm check`, touched-file trailing-whitespace and line-length checks, and `git diff --check` passed. No VM was
  launched, no image was downloaded, no public release, secret write, key generation, tag push, host audio mutation, or
  support matrix promotion was performed.
- 2026-07-04 release evidence bundle verifier: added `scripts/verify-release-evidence.mjs` and
  `pnpm verify:release-evidence` to audit an existing `release-evidence.json` bundle. The verifier checks manifest
  `ok`, required command success, non-empty command logs, optional published-release smoke, optional VM evidence, full
  `vm/targets.tsv` coverage, and optional blocker-free readiness.
- 2026-07-04 release evidence bundle verifier validation: codebase-memory MCP `index_status` and `index_repository`
  failed with `Transport closed`, so this slice used focused shell reads after the required graph attempt.
  `node --check scripts/verify-release-evidence.mjs`, `bash -n scripts/verify-scripts.sh scripts/verify-docs.sh`,
  verifier help readback, fixture final-evidence acceptance, fixture incomplete-VM-target rejection, fixture
  release-blocker rejection, fixture empty-log rejection, `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm verify:vm`,
  `pnpm check`, touched-file trailing-whitespace and line-length checks, and `git diff --check` passed. No VM was
  launched, no image was downloaded, no public release, secret write, key generation, tag push, host audio mutation, or
  support matrix promotion was performed.
- 2026-07-04 release workflow evidence artifact: `.github/workflows/release.yml` now installs the publish-job evidence
  dependencies, runs `pnpm collect:evidence -- --require-published-release` after the published-release smoke, verifies
  the bundle with `pnpm verify:release-evidence`, and uploads `loopwire-release-evidence-<tag>` with 90-day retention.
  VM evidence remains operator-collected outside GitHub-hosted runners.
- 2026-07-04 release workflow evidence validation: codebase-memory MCP `index_status` and `index_repository` failed
  with `Transport closed`, so this slice used focused shell reads after the required graph attempt.
  `bash -n scripts/verify-github-workflows.sh scripts/verify-docs.sh scripts/verify-scripts.sh`, Ruby workflow YAML
  parse, `pnpm verify:workflows`, `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm check`, touched-file
  trailing-whitespace and line-length checks, and `git diff --check` passed. The release workflow itself was not run
  because there is no real signing key, tag, GitHub Release, or configured release secret yet.
- 2026-07-04 public release evidence asset: `.github/workflows/release.yml` now packages the verified release evidence
  directory as `loopwire-release-evidence-<tag>.tar.gz`, uploads that archive to the GitHub Release with
  `gh release upload --clobber`, and keeps the evidence directory plus archive in the workflow artifact.
- 2026-07-04 public release evidence asset validation: codebase-memory MCP `index_status` and `index_repository`
  failed with `Transport closed`, so this slice used focused shell reads after the required graph attempt.
  `bash -n scripts/verify-github-workflows.sh scripts/verify-docs.sh scripts/verify-scripts.sh`, Ruby workflow YAML
  parse, `pnpm verify:workflows`, `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm check`, touched-file
  trailing-whitespace and line-length checks, and `git diff --check` passed. The release workflow itself was not run
  because there is no real signing key, tag, GitHub Release, or configured release secret yet.
- 2026-07-04 public evidence archive gate: `scripts/verify-published-release.sh` now supports
  `--require-release-evidence`, requires `loopwire-release-evidence-<tag>.tar.gz`, extracts it, and verifies the bundle
  with `scripts/verify-release-evidence.mjs --require-published-release --require-no-release-blockers`. The release
  workflow runs this gate after uploading the archive to the GitHub Release.
- 2026-07-04 public evidence archive validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempt. `bash -n
  scripts/verify-published-release.sh scripts/verify-scripts.sh scripts/verify-github-workflows.sh
  scripts/verify-docs.sh`, `pnpm verify:workflows`, `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm check`, Ruby
  release-workflow YAML parse, and `git diff --check` passed. `pnpm verify:scripts` now covers missing evidence archive
  rejection, valid archive acceptance, and blocker archive rejection. No VM was launched, no image was downloaded, no
  public release, secret write, key generation, tag push, host audio mutation, or support matrix promotion was
  performed.
- 2026-07-04 public evidence archive hardening: `scripts/verify-release-evidence.mjs` now accepts `--release-tag` and
  `--repo` and rejects manifest mismatches. `scripts/verify-published-release.sh --require-release-evidence` now passes
  those expected values when known and validates archive member paths before extraction so absolute paths and `..`
  components are rejected.
- 2026-07-04 public evidence archive hardening validation: codebase-memory MCP `index_status` and `index_repository`
  failed with `Transport closed`, so this slice used focused shell reads after the required graph attempt.
  `node --check scripts/verify-release-evidence.mjs`, `bash -n scripts/verify-published-release.sh
  scripts/verify-scripts.sh scripts/verify-docs.sh`, `pnpm verify:scripts`, `pnpm verify:docs`,
  `pnpm verify:workflows`, `pnpm check`, touched-file line-length checks, and `git diff --check` passed.
  `pnpm verify:scripts` now covers direct evidence tag/repo mismatch rejection, public evidence tag mismatch rejection,
  and unsafe tar path rejection. No VM was launched, no image was downloaded, no public release, secret write, key
  generation, tag push, host audio mutation, or support matrix promotion was performed.
- 2026-07-04 native route-gain blocker UX: desktop live-apply preflight now names the native PipeWire/JACK routes
  blocked by non-100% gain and shows a `Reset gains` action when those blockers are present. The action resets affected
  app-state route gains to 100% and preserves other blockers such as missing native source ports.
- 2026-07-04 native route-gain blocker UX validation: codebase-memory MCP `index_status` and `index_repository` failed
  with `Transport closed`, so this slice used focused shell reads after the required graph attempt.
  `pnpm --filter @loopwire/desktop typecheck`, `pnpm --filter @loopwire/core test`,
  `pnpm --filter @loopwire/audio-host test`, `pnpm --filter @loopwire/desktop build`, `pnpm verify:docs`,
  `pnpm check`, Playwright desktop/mobile checks against `http://127.0.0.1:4182`, touched-file line-length checks, and
  `git diff --check` passed. The Playwright check selected PipeWire, verified the route-specific gain blocker and
  `Reset gains` button, clicked it, confirmed all route gains changed to 100%, confirmed the gain blocker disappeared,
  confirmed missing-host-source blockers remained, and confirmed zero horizontal overflow. No host audio mutation,
  public release, VM launch, image download, key generation, secret write, tag push, or support matrix promotion was
  performed.
- 2026-07-04 native host-binding blocker UX: desktop live-apply preflight now names the affected source, output, and
  monitor labels for native PipeWire/JACK host-binding blockers instead of only naming the blocker category.
- 2026-07-04 native host-binding blocker UX validation: codebase-memory MCP `index_status` and `index_repository`
  failed with `Transport closed`, so this slice used focused shell reads after the required graph attempt.
  `pnpm --filter @loopwire/desktop typecheck`, `pnpm --filter @loopwire/desktop build`, `pnpm verify:docs`,
  `pnpm --filter @loopwire/core test`, `pnpm --filter @loopwire/audio-host test`, `pnpm check`, Playwright
  desktop/mobile checks against `http://127.0.0.1:4183`, touched-file line-length checks, and `git diff --check`
  passed. The Playwright check selected PipeWire, verified route-specific gain blockers, verified source-specific host
  binding blockers for `Studio Mic` and `Browser Audio`, and confirmed zero horizontal overflow. No host audio mutation,
  public release, VM launch, image download, key generation, secret write, tag push, or support matrix promotion was
  performed.
- 2026-07-04 custom chrome maximize/restore: desktop custom chrome fallback now exposes Loopwire-owned minimize,
  maximize/restore, and close controls for undecorated Tauri windows. The maximize/restore control calls Tauri
  `toggleMaximize()` and shares the same browser-preview fallback note as the existing window controls.
- 2026-07-04 custom chrome maximize/restore validation: codebase-memory MCP `index_status` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempt.
  `pnpm --filter @loopwire/desktop typecheck`, `pnpm --filter @loopwire/desktop build`, `pnpm verify:docs`,
  `bash -n scripts/verify-docs.sh`, `pnpm check`, Playwright desktop/mobile checks against
  `http://127.0.0.1:4184`, touched-file line-length checks, and `git diff --check` passed. The Playwright check
  selected custom chrome, verified minimize, maximize/restore, and close controls, clicked maximize/restore, confirmed
  the expected browser-preview Tauri fallback message, and confirmed zero horizontal overflow. No host audio mutation,
  public release, VM launch, image download, key generation, secret write, tag push, or support matrix promotion was
  performed.
- 2026-07-04 native JACK virtual-port blockers: the JACK adapter now validates route sources, route targets, and
  monitor source outputs before any `jack_lsp`, `jack_connect`, or `jack_disconnect` command. App-only endpoints that
  still require virtual JACK ports fail closed with endpoint-specific messages instead of probing the host first.
- 2026-07-04 native JACK virtual-port blockers validation: codebase-memory MCP `index_status` and `index_repository`
  failed with `Transport closed`, so this slice used focused shell reads after the required graph attempt. Test-first
  validation produced the expected red run: `pnpm --filter @loopwire/audio-host test` failed 3 tests for virtual JACK
  route input, route output, and monitor source-output blockers before adapter changes. After implementation,
  `pnpm --filter @loopwire/audio-host typecheck`, `pnpm --filter @loopwire/audio-host test`, `pnpm verify:docs`,
  `bash -n scripts/verify-docs.sh`, `pnpm check`, touched-file line-length checks, and `git diff --check` passed. No
  host audio mutation, public release, VM launch, image download, key generation, secret write, tag push, or support
  matrix promotion was performed.
- 2026-07-04 Tauri bridge argument policy: the Tauri `run_audio_command` boundary now validates both command names and
  argument shapes against Loopwire's detector/runtime contract before spawning any live audio process. The policy allows
  current `aplay`, `wpctl`, `pactl`, `pw-cli`, `pw-link`, `jack_lsp`, `jack_connect`, and `jack_disconnect` operations
  while rejecting unrelated subcommands, option expansion, and non-port mutation arguments.
- 2026-07-04 Tauri bridge argument policy validation: codebase-memory MCP `index_status` and `index_repository` failed
  with `Transport closed`, so this slice used focused shell reads after the required graph attempt.
  `cargo fmt --manifest-path apps/desktop/src-tauri/Cargo.toml`, `cargo test --manifest-path
  apps/desktop/src-tauri/Cargo.toml`, `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml`,
  `pnpm verify:docs`, `bash -n scripts/verify-docs.sh`, `pnpm check`, touched-file line-length checks, and
  `git diff --check` passed. The Tauri unit suite now has 12 passing tests, including allowed probe/mutation command
  shapes and rejected out-of-contract host command shapes. No host audio mutation, public release, VM launch, image
  download, key generation, secret write, tag push, or support matrix promotion was performed.
- 2026-07-04 Tauri verification gate: `pnpm check` now runs `pnpm check:verify`, which includes `pnpm verify:tauri`.
  The new Tauri verifier runs Rust format checks, compile checks, and the Tauri unit suite. CI and release workflows
  rely on that workspace gate instead of carrying separate cargo-only checks, and release/support evidence now records
  `tauri-verify.log`.
- 2026-07-04 Tauri verification gate validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempt. Current Tauri Linux
  prerequisite package groups were checked against the official Tauri v2 prerequisites, and Arch package availability
  was checked locally with `pacman -Ss`. `bash -n scripts/verify-tauri.sh scripts/verify-scripts.sh
  scripts/verify-github-workflows.sh scripts/verify-docs.sh scripts/vm-matrix.sh scripts/collect-vm-evidence.sh
  scripts/collect-vm-evidence-ssh.sh`, `pnpm verify:vm`, `pnpm verify:docs`, `pnpm verify:workflows`,
  `pnpm verify:scripts`, `pnpm verify:tauri`, `node scripts/collect-release-evidence.mjs --list-commands
  --profile quick`, `pnpm check`, stale active-reference search, touched-file line-length checks, and
  `git diff --check` passed. No host audio mutation, public release, VM launch, image download, key generation, secret
  write, tag push, or support matrix promotion was performed.
- 2026-07-04 openSUSE VM matrix coverage: added `opensuse-kde-pipewire` to `vm/targets.tsv` and the support matrix as
  a Manual VM target for openSUSE Tumbleweed, KDE Plasma, Wayland, and PipeWire/WirePlumber. `scripts/vm-matrix.sh`
  now treats `zypper` as a supported package family, renders openSUSE guest bootstrap commands with Rust, pinned pnpm,
  PipeWire/WirePlumber, and Tauri openSUSE prerequisites, and rejects rendered zypper handoffs that are missing
  WebKitGTK, Rust cargo, build pattern, or pinned pnpm coverage.
- 2026-07-04 openSUSE VM matrix validation: codebase-memory MCP `index_repository` failed with `Transport closed`, so
  this slice used focused shell reads after the required graph attempt. The zypper Tauri prerequisite set was checked
  against the official Tauri v2 openSUSE guidance. `bash -n scripts/vm-matrix.sh scripts/verify-scripts.sh
  scripts/verify-docs.sh scripts/verify-vm-evidence.sh`, `pnpm verify:vm`, `pnpm verify:docs`,
  `bash scripts/vm-matrix.sh plan --target opensuse-kde-pipewire`, `pnpm verify:scripts`,
  `node scripts/collect-release-evidence.mjs --list-commands --profile quick --require-published-release
  --require-vm-evidence --vm-target all --vm-evidence-dir '.vm/evidence/{target}' --release-tag v0.1.0 --repo
  sandwichfarm/loopwire --public-key packaging/release-signing-public.pem`, `pnpm check`, touched-file line-length
  checks, and `git diff --check` passed. The release evidence command plan now expands to 8 VM evidence commands,
  including `vm-evidence:opensuse-kde-pipewire`. No host audio mutation, public release, VM launch, image download, key
  generation, secret write, tag push, or support matrix promotion was performed.
- 2026-07-04 AArch64 VM matrix coverage: added `ubuntu-gnome-pipewire-aarch64` to `vm/targets.tsv` and the support
  matrix as a Manual VM target for Ubuntu LTS, GNOME, Wayland, PipeWire/PulseAudio compatibility, and AArch64.
  `scripts/vm-matrix.sh launch` now accepts `--firmware`, prints `qemu-system-aarch64`, `-machine virt`, and
  `-cpu max` for AArch64 dry-runs, and rejects AArch64 `--execute` without an operator-owned UEFI firmware path.
- 2026-07-04 AArch64 VM matrix validation: codebase-memory MCP `index_repository` failed with `Transport closed`, so
  this slice used focused shell reads after the required graph attempt. `bash -n scripts/vm-matrix.sh
  scripts/verify-scripts.sh scripts/verify-docs.sh`, `pnpm verify:vm`, `pnpm verify:docs`,
  `bash scripts/vm-matrix.sh launch --target ubuntu-gnome-pipewire-aarch64 --image
  /operator/images/ubuntu-aarch64.qcow2 --ssh-port 2422`, `pnpm verify:scripts`, `pnpm check`,
  `node scripts/collect-release-evidence.mjs --list-commands --profile quick --require-published-release
  --require-vm-evidence --vm-target all --vm-evidence-dir '.vm/evidence/{target}' --release-tag v0.1.0 --repo
  sandwichfarm/loopwire --public-key packaging/release-signing-public.pem`, touched-file line-length checks, and
  `git diff --check` passed. The release evidence command plan now expands to 9 VM evidence commands, including
  `vm-evidence:ubuntu-gnome-pipewire-aarch64`. No host audio mutation, public release, VM launch, image download, key
  generation, secret write, tag push, or support matrix promotion was performed.
- 2026-07-04 GitHub secret check hardening: `scripts/setup-github-secrets.sh --check` and
  `scripts/verify-release-readiness.sh` now preserve `gh secret list` failures instead of treating unreadable secret
  names as ordinary missing secrets. `scripts/verify-scripts.sh` covers the success path and failure path with a fake
  `gh` executable, so the contract is reproducible without live credentials.
- 2026-07-04 GitHub secret check validation: codebase-memory MCP `index_repository` failed with `Transport closed`, so
  this slice used focused shell reads after the required graph attempt. `bash -n scripts/setup-github-secrets.sh
  scripts/verify-release-readiness.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, `pnpm verify:docs`,
  `pnpm verify:scripts`, and `pnpm check` passed. A manual dry-run with a nonexistent private key file failed closed as
  expected. No GitHub secrets were read beyond names, no secret values were printed, no secret was written, no public
  release was created, no tag was pushed, no VM was launched, and no support matrix row was promoted.
- 2026-07-04 Bunny remote-prefix deployment support: `.github/workflows/deploy-docs.yml` now passes optional
  `BUNNY_REMOTE_PREFIX` into the Bunny deploy step, and `scripts/setup-github-secrets.sh` can print, check, dry-run, and
  set the optional `BUNNY_REMOTE_PREFIX` secret alongside `BUNNY_STORAGE_ENDPOINT` and `BUNNY_PULL_ZONE_HOSTNAME`.
  The required Bunny deploy secret pair remains `BUNNY_STORAGE_ZONE` plus `BUNNY_ACCESS_KEY`.
- 2026-07-04 Bunny remote-prefix validation: codebase-memory MCP `index_repository` failed with `Transport closed`, so
  this slice used focused shell reads after the required graph attempt. `bash -n scripts/setup-github-secrets.sh
  scripts/verify-github-workflows.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, `pnpm verify:workflows`,
  `pnpm verify:docs`, `pnpm verify:scripts`, and `pnpm check` passed. `scripts/verify-scripts.sh` now proves the
  dry-run names `BUNNY_REMOTE_PREFIX` without printing its value, and fake-`gh` check mode reports the optional secret.
  No Bunny deployment was performed, no GitHub secrets were written, no public release was created, no tag was pushed,
  no VM was launched, and no support matrix row was promoted.
- 2026-07-04 VM host setup dry-run helper: `scripts/vm-matrix.sh host-setup` and `pnpm vm:host-setup` now print
  `package-family=*`, one `install-command=*`, required VM host tools, and the target-aware `verify-command=*`.
  The command is dry-run-only and rejects `--execute`, so it cannot install packages on the operator host.
- 2026-07-04 VM host setup validation: codebase-memory MCP `index_repository` failed with `Transport closed`, so this
  slice used focused shell reads after the required graph attempt. `bash -n scripts/vm-matrix.sh
  scripts/verify-scripts.sh scripts/verify-docs.sh`, direct apt/AArch64 and pnpm zypper host-setup dry-runs,
  `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm verify:vm`, and `pnpm check` passed. The new verifier caught and
  fixed a shell scoping regression where host package-family detection overwrote the selected NixOS guest family in
  `vm:doctor`. No package installation, VM launch, image download, host audio mutation, public release, secret write,
  tag push, or support matrix promotion was performed.
- 2026-07-04 JACK Loopwire-owned port resolution: native JACK now resolves app route inputs, route outputs, and monitor
  targets without host `deviceName` values to deterministic Loopwire-owned JACK port names. It connects only when those
  ports already exist and still does not create JACK clients or ports. Desktop JACK preflight now lets those endpoints
  reach the runtime `jack_lsp` probe while continuing to block non-100% native gain.
- 2026-07-04 JACK port resolution validation: codebase-memory MCP `search_graph` failed with `Transport closed`, so
  this slice used focused shell reads after the required graph attempt. The new JACK regression tests first failed on
  the old missing-`deviceName` rejection, then `pnpm --filter @loopwire/audio-host test -- jack-adapter.test.ts` passed
  with 73 tests. `pnpm --filter @loopwire/audio-host typecheck`, `pnpm --filter @loopwire/desktop typecheck`,
  `pnpm verify:docs`, `pnpm check`, touched-file line-length checks, and `git diff --check` passed. No JACK host audio
  mutation, VM launch, image download, package installation, public release, secret write, tag push, or support matrix
  promotion was performed.
- 2026-07-04 release evidence path hardening: `scripts/verify-release-evidence.mjs` now rejects command log paths that
  contain parent traversal, escape the evidence directory after realpath resolution, resolve through symlinks, or point
  to non-file entries. This keeps published release evidence archives from proving commands with logs outside the
  attached evidence bundle.
- 2026-07-04 release evidence path validation: codebase-memory MCP `index_repository` failed with `Transport closed`,
  so this slice used focused shell reads after the required graph attempt. The new verifier regression first failed
  because `../outside.log` was accepted. After implementation, `pnpm verify:scripts` and `pnpm verify:docs` passed. No
  package installation, VM launch, image download, host audio mutation, public release, secret write, tag push, Bunny
  deployment, or support matrix promotion was performed.
- 2026-07-04 backend selector live-disarm UX: changing the selected backend now persists the new backend, refreshes
  source and monitor candidates, disarms any live host-apply session, and runs preview verification against the active
  configuration. If preview verification fails, the disarm note preserves the verification failure detail.
- 2026-07-04 backend selector validation: codebase-memory MCP `index_repository` failed with `Transport closed`, so
  this slice used focused shell reads after the required graph attempt. `pnpm --filter @loopwire/desktop typecheck`,
  `pnpm --filter @loopwire/desktop build`, and `pnpm verify:docs` passed. Playwright against
  `http://127.0.0.1:4185/` selected PulseAudio, armed live apply, switched to PipeWire, verified the host-apply control
  returned to `Preview`, verified the runtime note says live apply was disarmed for preview verification, and confirmed
  zero horizontal overflow. No live host audio mutation, package installation, VM launch, image download, public
  release, secret write, tag push, Bunny deployment, or support matrix promotion was performed.
- 2026-07-04 configuration switch transaction guard: desktop configuration switches and fallback delete switches now use a
  tokenized busy state. The latest switch can update runtime state and unblock the sidebar, while stale async results are
  ignored instead of replacing the latest selected configuration.
- 2026-07-04 configuration switch validation: codebase-memory MCP `index_repository` and `search_graph` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempts.
  `pnpm --filter @loopwire/desktop typecheck`, `pnpm --filter @loopwire/desktop build`, and `pnpm verify:docs` passed.
  Playwright against `http://127.0.0.1:4186/` switched from Studio to Call, verified the switch persisted after reload,
  verified configuration buttons were enabled after the transaction, and confirmed zero horizontal overflow on desktop and
  mobile. No live host audio mutation, package installation, VM launch, image download, public release, secret write, tag
  push, Bunny deployment, or support matrix promotion was performed.
- 2026-07-04 configuration switch full check: `pnpm check`, touched-file line-length check, `git diff --check`, and
  `gsd-sdk query roadmap.analyze` passed. Roadmap analysis still shows Phase 12 as the only incomplete phase at 80%
  milestone progress.
- 2026-07-04 release evidence VM-row hardening: `scripts/verify-release-evidence.mjs` now validates required VM evidence
  target rows before trusting command results. It rejects unknown target ids, duplicate target ids, absolute or
  parent-traversing `evidenceDir` values, evidence dirs that omit the target id as a path segment, and VM command rows
  that do not call `scripts/verify-vm-evidence.sh` with the matching `--target` and `--evidence-dir`.
- 2026-07-04 release evidence VM-row validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempts. `node --check
  scripts/verify-release-evidence.mjs`, `bash -n scripts/verify-scripts.sh scripts/verify-docs.sh`,
  `pnpm verify:scripts`, and `pnpm verify:docs` passed. No package installation, VM launch, image download, host audio
  mutation, public release, secret write, tag push, Bunny deployment, or support matrix promotion was performed.
- 2026-07-04 ALSA playback/capture diagnostics: `@loopwire/audio-host` now enumerates ALSA playback hardware with
  `aplay -l` and ALSA capture hardware with `arecord -l`. The desktop labels ALSA source/output candidates as diagnostics,
  the Tauri bridge allows only `arecord -l` for ALSA capture probing, and ALSA live apply remains blocked.
- 2026-07-04 ALSA diagnostics validation: codebase-memory MCP `index_status`, `search_graph`, and `index_repository`
  failed with `Transport closed`, so this slice used focused shell reads after the required graph attempts.
  `pnpm --filter @loopwire/audio-host test -- detectors.test.ts`, `pnpm --filter @loopwire/audio-host typecheck`,
  `pnpm --filter @loopwire/desktop typecheck`, `pnpm --filter @loopwire/desktop build`,
  `cargo fmt --manifest-path apps/desktop/src-tauri/Cargo.toml --check`,
  `cargo test --manifest-path apps/desktop/src-tauri/Cargo.toml`, `pnpm verify:tauri`, `pnpm verify:docs`,
  `pnpm verify:scripts`, `pnpm check`, `git diff --check`, touched-file line-length checks, and
  `gsd-sdk query roadmap.analyze` passed. `pnpm detect:audio` confirmed read-only ALSA availability on this host,
  `aplay -l` listed playback hardware, and `arecord -l` listed capture hardware. No live host audio mutation,
  ALSA route/apply implementation, package installation, VM launch, image download, public release, secret write,
  tag push, Bunny deployment, or support matrix promotion was performed.
- 2026-07-04 ALSA capability detection correction: ALSA backend detection now probes both `aplay -l` and `arecord -l`,
  keeps playback-only or capture-only visibility available for diagnostics, and reports `createVirtualDevice`,
  `routeAudio`, `monitorAudio`, `apply`, `verify`, and `rollback` as unavailable instead of planned.
- 2026-07-04 ALSA capability validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempts.
  `pnpm --filter @loopwire/audio-host test -- detectors.test.ts` passed with 76 tests,
  `pnpm --filter @loopwire/audio-host typecheck`, `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm check`,
  `git diff --check`, touched-file line-length checks, and `gsd-sdk query roadmap.analyze` passed. `pnpm detect:audio`
  confirmed ALSA commands now include both `aplay -l` and `arecord -l`, with route/apply/verify/rollback unavailable.
  No live host audio mutation, ALSA routing implementation, package installation, VM launch, image download, public
  release, secret write, tag push, Bunny deployment, or support matrix promotion was performed.
- 2026-07-04 VM matrix-wide doctor: `scripts/vm-matrix.sh doctor --all` now prints a `target-check=*` block for every
  target in `vm/targets.tsv`, including architecture-specific QEMU checks, guest evidence commands, host pull commands,
  KVM status, and host install hints. It fails closed if any target lacks required launch tools and rejects `--all`
  together with `--target`.
- 2026-07-04 VM matrix-wide doctor validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempts. `bash -n
  scripts/vm-matrix.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, direct `doctor --all` readback, conflicting
  `doctor --all --target` rejection, `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm verify:vm`, `pnpm check`,
  `git diff --check`, touched-file line-length checks, and `gsd-sdk query roadmap.analyze` passed. No package
  installation, VM launch, image download, host audio mutation, public release, secret write, tag push, Bunny deployment,
  or support matrix promotion was performed.
- 2026-07-04 VM all-target host setup: `scripts/vm-matrix.sh host-setup --all` now prints `target-scope=all`, all QEMU
  system tools required by `vm/targets.tsv`, the shared launch support tools, and
  `verify-command=bash scripts/vm-matrix.sh doctor --all`. It remains dry-run-only and rejects `--all` together with
  `--target`.
- 2026-07-04 VM all-target host setup validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempts. `bash -n
  scripts/vm-matrix.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, direct `host-setup --all` readback,
  conflicting `host-setup --all --target` rejection, `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm verify:vm`,
  `pnpm check`, `git diff --check`, touched-file line-length checks, and `gsd-sdk query roadmap.analyze` passed. No
  package installation, VM launch, image download, host audio mutation, public release, secret write, tag push, Bunny
  deployment, or support matrix promotion was performed.
- 2026-07-04 release evidence source-state hardening: `scripts/verify-release-evidence.mjs` now rejects manifests that
  omit valid git metadata, require a 40-character `git.head`, reject unavailable or unsafe git fields, and support
  `--require-clean-git` for final release bundles. The release workflow passes the expected tag and repository into the
  direct evidence verification step before attaching `loopwire-release-evidence-<tag>.tar.gz`.
- 2026-07-04 release evidence source-state validation: codebase-memory MCP `index_status` and `index_repository` failed
  with `Transport closed`, so this slice used focused shell reads after the required graph attempts. `node --check
  scripts/verify-release-evidence.mjs`, `bash -n scripts/verify-scripts.sh scripts/verify-docs.sh
  scripts/verify-github-workflows.sh`, `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm verify:workflows`, real
  `pnpm collect:evidence -- --output-dir /tmp/loopwire-release-evidence.xiH9qF --profile quick --release-tag v0.1.0`,
  `pnpm verify:release-evidence -- --evidence-dir /tmp/loopwire-release-evidence.xiH9qF --release-tag v0.1.0 --repo
  sandwichfarm/loopwire`, and a negative `--require-clean-git` check against the current dirty tree passed. No package
  installation, VM launch, image download, host audio mutation, public release, secret write, tag push, Bunny deployment,
  or support matrix promotion was performed.
- 2026-07-04 product requirements evidence gate: added `scripts/verify-requirements.sh`, wired `pnpm verify:requirements`
  into `pnpm check:verify`, and updated `.planning/REQUIREMENTS.md` so v1 requirements are complete only where current
  source/docs/workflow/package/test anchors prove them. `SHIP-01..SHIP-03` remain pending.
- 2026-07-04 product requirements gate validation: codebase-memory MCP `index_status`, `search_graph`, and
  `index_repository` failed with `Transport closed`, so this slice used focused shell reads after the required graph
  attempts. The first `pnpm verify:requirements` run failed on an over-specific homepage install anchor and then passed
  after using the current source-install evidence. `pnpm verify:docs` initially recursed because a new assertion used
  shell backticks inside double quotes; the verifier session was interrupted and the assertion was fixed with single
  quotes. `bash -n scripts/verify-requirements.sh scripts/verify-scripts.sh scripts/verify-docs.sh`,
  `pnpm verify:requirements`, `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm verify:workflows`, `pnpm check`,
  `git diff --check`, and touched-file line-length checks passed. No package installation, VM launch, image download,
  host audio mutation, public release, secret write, tag push, Bunny deployment, or support matrix promotion was
  performed.
- 2026-07-04 VM architecture-scoped host setup: `scripts/vm-matrix.sh host-setup --family dnf --all` now prints a
  Fedora install command that includes `qemu-system-aarch64`, and `scripts/vm-matrix.sh host-setup --family zypper
  --all` now prints an openSUSE install command that includes both `qemu-x86` and `qemu-arm`. Targeted AArch64
  host-plan output now prints Fedora and openSUSE AArch64 package hints.
- 2026-07-04 VM architecture-scoped host setup validation: codebase-memory MCP `index_status` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempt. Official package lookup
  confirmed Fedora exposes `qemu-system-aarch64` and openSUSE exposes `qemu-arm`. `bash -n
  scripts/vm-matrix.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, direct `host-setup --family dnf --all`,
  direct `host-setup --family zypper --all`, direct AArch64 `host-plan` readback, `pnpm verify:docs`,
  `pnpm verify:scripts`, `pnpm verify:vm`, `pnpm check`, `git diff --check`, and touched-file line-length checks
  passed. No package installation, VM launch, image download, host audio mutation, public release, secret write, tag
  push, Bunny deployment, or support matrix promotion was performed.
- 2026-07-04 Nix flake package template: `flake.nix` now exposes `packages.<system>.loopwire-bin` and
  `packages.<system>.default` for `x86_64-linux` and `aarch64-linux` through `packaging/nix/loopwire-bin.nix`. The
  default package intentionally uses `nixpkgs.lib.fakeHash` until published artifacts provide real release hashes, and
  `lib.<system>.mkLoopwireBinPackage` lets release automation or downstream consumers inject the real version and
  hashes.
- 2026-07-04 Nix flake package-template validation: codebase-memory MCP `index_status` and `index_repository` failed
  with `Transport closed`, so this slice used focused shell reads after the required graph attempts. `bash -n
  scripts/verify-packaging.sh scripts/verify-docs.sh`, `pnpm verify:packaging`, `pnpm verify:docs`, `pnpm check`,
  `git diff --check`, and touched-file line-length checks passed. `nix` is not installed on this host, so no
  `nix flake show` or `nix build` proof was produced. No package installation, VM launch, image download, host audio
  mutation, public release, secret write, tag push, Bunny deployment, or support matrix promotion was performed.
- 2026-07-04 public installer endpoint plumbing: `apps/docs/docs/public/install.sh` now mirrors `scripts/install.sh`
  byte-for-byte, so the VitePress/Bunny docs deployment can serve `/install.sh` without introducing a second installer
  contract. `scripts/verify-docs.sh` rejects drift and runs shell syntax checks against the public asset; `pnpm
  build:docs` emitted `apps/docs/docs/.vitepress/dist/install.sh`, and a direct `cmp` proved it matched
  `scripts/install.sh`.
- 2026-07-04 public installer endpoint validation: codebase-memory MCP `index_status` and `index_repository` failed
  with `Transport closed`, so this slice used focused shell reads after the required graph attempts. `bash -n
  apps/docs/docs/public/install.sh scripts/install.sh scripts/verify-docs.sh scripts/verify-scripts.sh`, public
  installer drift `cmp`, `pnpm verify:docs`, `pnpm --filter @loopwire/docs docs:build`, built-dist installer `cmp`,
  `pnpm verify:scripts`, `pnpm check`, `git diff --check`, and touched-file line-length checks passed. No package
  installation, VM launch, image download, host audio mutation, public release, secret write, tag push, Bunny
  deployment, or support matrix promotion was performed.
- 2026-07-04 public installer release-gate hardening: `scripts/verify-release-readiness.sh` now checks the canonical
  installer and public docs installer, rejects byte drift between them, and runs `bash -n` on the public docs installer.
  `scripts/verify-scripts.sh` now proves Bunny.net dry-run output includes `install.sh` and covers both synced and stale
  public-installer readiness cases.
- 2026-07-04 public installer release-gate validation: codebase-memory MCP `index_status` and `index_repository` failed
  with `Transport closed`, so this slice used focused shell reads after the required graph attempts. `bash -n
  scripts/verify-release-readiness.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, `pnpm verify:docs`,
  `pnpm verify:scripts`, touched-file line-length checks, `pnpm check`, `git diff --check`, and
  `gsd-sdk query roadmap.analyze` passed. No package installation, VM launch, image download, host audio mutation,
  public release, secret write, tag push, Bunny deployment, or support matrix promotion was performed.
- 2026-07-04 Bunny docs dist gate: `scripts/deploy-docs-bunny.sh` now requires non-empty built `index.html` and
  `install.sh` files, runs `bash -n` on the built public installer, and rejects unsafe `.` or `..` segments in
  `BUNNY_REMOTE_PREFIX` before dry-run or live upload planning.
- 2026-07-04 Bunny docs dist-gate validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempts. `bash -n
  scripts/deploy-docs-bunny.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, `pnpm verify:docs`,
  `pnpm verify:scripts`, touched-file line-length checks, `pnpm check`, `git diff --check`, and
  `gsd-sdk query roadmap.analyze` passed. `pnpm verify:scripts` covers positive `install.sh` dry-run upload plus
  negative missing-`install.sh`, missing-`index.html`, and unsafe-remote-prefix cases. No package installation, VM
  launch, image download, host audio mutation, public release, secret write, tag push, Bunny deployment, or support
  matrix promotion was performed.
- 2026-07-04 Bunny pull-zone smoke wiring: added `scripts/verify-docs-live.sh` and `pnpm verify:docs-live` to fetch a
  deployed docs homepage plus `/install.sh`, verify the installer parses as shell, and compare it byte-for-byte with the
  local public installer. `.github/workflows/deploy-docs.yml` now runs that smoke after upload when
  `BUNNY_PULL_ZONE_HOSTNAME` is configured.
- 2026-07-04 Bunny pull-zone smoke validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempts. `bash -n
  scripts/verify-docs-live.sh scripts/verify-scripts.sh scripts/verify-docs.sh scripts/verify-github-workflows.sh`,
  `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm verify:workflows`, touched-file line-length checks, `pnpm check`,
  `git diff --check`, and `gsd-sdk query roadmap.analyze` passed. `pnpm verify:scripts` covers a fake-curl positive
  pull-zone smoke plus stale deployed installer and unsafe remote-prefix rejection. No package installation, VM launch,
  image download, host audio mutation, public release, secret write, tag push, Bunny deployment, live URL smoke, or
  support matrix promotion was performed.
- 2026-07-04 release evidence live-docs gate: `scripts/collect-release-evidence.mjs` now supports
  `--require-live-docs`, docs URL/hostname/remote-prefix options, records `release.docsLive`, and schedules the
  `docs-live-smoke` command. `scripts/verify-release-evidence.mjs` now rejects final evidence when
  `--require-live-docs` is set without a required passing `docs-live-smoke` row.
- 2026-07-04 release evidence live-docs gate validation: codebase-memory MCP `index_status` and `index_repository`
  failed with `Transport closed`, so this slice used focused shell reads after the required graph attempts. `node --check
  scripts/collect-release-evidence.mjs scripts/verify-release-evidence.mjs`, `bash -n
  scripts/verify-scripts.sh scripts/verify-docs.sh`, `pnpm verify:docs`, `pnpm verify:scripts`, command-plan readback
  for `--require-live-docs`, `pnpm check`, `git diff --check`, touched-file line-length checks, and
  `gsd-sdk query roadmap.analyze` passed. No package installation, VM launch, image download, host audio mutation,
  public release, secret write, tag push, Bunny deployment, live URL smoke, or support matrix promotion was performed.
- 2026-07-04 matrix VM evidence collection: `scripts/collect-vm-matrix-evidence.sh` and `pnpm vm:collect-matrix` can
  read a tab-separated guest plan, reject unknown or duplicate targets and invalid ports, forward published-release
  smoke flags, and expand each row into `scripts/collect-vm-evidence-ssh.sh` with target-scoped local evidence paths.
- 2026-07-04 matrix VM evidence validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempts. `bash -n
  scripts/collect-vm-matrix-evidence.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, `pnpm verify:docs`,
  `pnpm verify:scripts`, `pnpm vm:collect-matrix -- --help`, direct dry-run plan readback, touched-file line-length
  checks, `pnpm check`, `git diff --check`, and `gsd-sdk query roadmap.analyze` passed. No package installation, VM
  launch, image download, host audio mutation, public release, secret write, tag push, Bunny deployment, live URL smoke,
  or support matrix promotion was performed.
- 2026-07-04 JACK desktop preflight tightening: the desktop now blocks JACK live apply before arming when any routed
  source, routed output, monitor source output, or monitor target lacks a host binding to an existing JACK port. This
  moves a predictable `jack_lsp`/missing-port failure into the preflight strip without claiming Loopwire can create
  JACK ports.
- 2026-07-04 JACK desktop preflight validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempts.
  `pnpm --filter @loopwire/desktop typecheck`, `pnpm verify:docs`, touched-file line-length checks, and
  `git diff --check` passed. No live JACK server, host audio mutation, VM launch, package install, public release,
  Bunny deployment, or support matrix promotion was performed.
- 2026-07-04 desktop preflight test surface: live-apply preflight rules moved from private `App.svelte` helpers into
  `apps/desktop/src/live-apply-preflight.ts`, and the Svelte shell now imports the pure helper. Focused Vitest coverage
  protects no-backend, ALSA diagnostics-only, PulseAudio ready, PipeWire gain/source blockers, JACK gain/port blockers,
  and native gain route filtering.
- 2026-07-04 desktop preflight test validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempts.
  `pnpm --filter @loopwire/desktop test -- src/live-apply-preflight.test.ts`,
  `pnpm --filter @loopwire/desktop typecheck`, `pnpm verify:docs`, touched-file line-length checks, `git diff --check`,
  `pnpm check`, and `gsd-sdk query roadmap.analyze` passed. No live JACK server, host audio mutation, VM launch,
  package install, public release, Bunny deployment, or support matrix promotion was performed.
- 2026-07-04 VM SSH plan generation: `scripts/vm-matrix.sh render-ssh-plan` and `pnpm vm:render-ssh-plan` can emit the
  `collect-vm-matrix-evidence.sh` TSV for one target or all targets, with target-scoped `.vm/evidence/<target>` output
  paths, configurable guest user/host/identity, optional desktop smoke port, and unique forwarded SSH ports.
- 2026-07-04 VM SSH plan validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempts. `bash -n
  scripts/vm-matrix.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, single-target render readback,
  all-target render readback, invalid start-port rejection, `pnpm verify:vm`, `pnpm verify:docs`,
  `pnpm verify:scripts`, `pnpm vm:render-ssh-plan -- --target ubuntu-gnome-pipewire-aarch64 --start-port 2422
  --desktop-port 5199`, generated-plan-to-collector dry-run smoke, `pnpm check`, and GSD milestone/roadmap queries
  passed. No package installation, VM launch, image download, host audio mutation, public release, secret write, tag
  push, Bunny deployment, live URL smoke, or support matrix promotion was performed.
- 2026-07-04 support bundle backend summary: `scripts/collect-support-bundle.mjs` now keeps `detect-audio.json` valid
  JSON by suppressing build chatter and writes `audio.backends` into `support-bundle.json`. Each row summarizes backend
  kind, availability, transport, route-control scope, per-edge gain/mute flags, diagnostics, and known gaps.
- 2026-07-04 support bundle backend validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempts. `node --check
  scripts/collect-support-bundle.mjs`, `bash -n scripts/verify-vm-evidence.sh scripts/verify-scripts.sh
  scripts/verify-docs.sh`, `pnpm verify:docs`, direct quick support-bundle smoke with parsed PipeWire, PulseAudio,
  JACK, and ALSA backend rows, `pnpm verify:scripts`, audio-host tests/typecheck, `pnpm verify:vm`, touched-file
  line-length checks, `git diff --check`, and `pnpm check` passed. No package installation, VM launch, image download,
  host audio mutation, public release, secret write, tag push, Bunny deployment, live URL smoke, or support matrix
  promotion was performed.
- 2026-07-04 shared JACK port requirements: `packages/audio-host/src/jack-adapter.ts` now exports
  `describeJackPortRequirements`, a pure helper that uses the same deterministic naming path as the JACK runtime
  adapter. The helper reports configured vs Loopwire-owned requirements, channel counts, deterministic client names,
  and suggested channel ports. Desktop preflight now uses the helper when naming unbound JACK endpoint blockers.
- 2026-07-04 shared JACK port validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempts.
  `pnpm --filter @loopwire/audio-host test -- jack-adapter.test.ts`,
  `pnpm --filter @loopwire/desktop test -- src/live-apply-preflight.test.ts`,
  `pnpm --filter @loopwire/audio-host typecheck`, `pnpm --filter @loopwire/desktop typecheck`, `pnpm verify:docs`,
  audio-host tests, desktop tests, `pnpm check`, `git diff --check`, touched-file line-length checks, and
  `gsd-sdk query roadmap.analyze` plus `gsd-sdk query init.milestone-op` passed after the helper and preflight wiring.
  `apps/desktop/vitest.config.ts` now mirrors the Vite source aliases so desktop tests do not depend on stale built
  `dist` exports. A final codebase-memory MCP retry still failed with `Transport closed`. No live JACK server, host
  audio mutation, VM launch, package install, public release, secret write, tag push, Bunny deployment, live URL smoke,
  or support matrix promotion was performed.
- 2026-07-04 JACK port CLI handoff: added `scripts/describe-jack-ports.mjs` and `pnpm jack:ports`. The command reads a
  Loopwire configuration export, raw configuration JSON, or persisted state file, then prints shared JACK port
  requirements as JSON or TSV. `--loopwire-owned-only` filters to endpoints that still need pre-existing
  Loopwire-owned JACK clients, making pro-audio session templates and support handoffs easier without touching JACK.
- 2026-07-04 JACK port CLI validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempts. `node --check
  scripts/describe-jack-ports.mjs`, `pnpm jack:ports -- --help`, `pnpm verify:scripts`, `pnpm verify:docs`,
  `pnpm check`, `git diff --check`, touched-file line-length checks, and `gsd-sdk query roadmap.analyze` passed.
  `pnpm verify:scripts` includes deterministic JSON and TSV smoke coverage for `describe-jack-ports.mjs`. A final
  codebase-memory MCP retry still failed with `Transport closed`. No live JACK server, host audio mutation, VM launch,
  package install, public release, secret write, tag push, Bunny deployment, live URL smoke, or support matrix
  promotion was performed.
- 2026-07-04 JACK readiness verifier: `scripts/describe-jack-ports.mjs --verify` and `pnpm jack:verify` now compare
  required configured/Loopwire-owned JACK ports against live `jack_lsp` output or `--ports-file` fixtures. The JSON and
  TSV output now include per-requirement readiness, matched ports, and missing suggested ports, and the command exits
  nonzero when required port matches are absent.
- 2026-07-04 JACK readiness validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempts. `node --check
  scripts/describe-jack-ports.mjs`, `pnpm jack:verify -- --help`, `pnpm verify:scripts`, `pnpm verify:docs`,
  `pnpm check`, `git diff --check`, touched-file line-length checks, `gsd-sdk query roadmap.analyze`, and
  `gsd-sdk query init.milestone-op` passed. `pnpm verify:scripts` covers positive JSON/TSV captured-port readiness and
  a negative missing-port case. A final codebase-memory MCP retry still failed with `Transport closed`. No live JACK
  server, host audio mutation, VM launch, package install, public release, secret write, tag push, Bunny deployment,
  live URL smoke, or support matrix promotion was performed.
- 2026-07-04 support bundle JACK readiness: `scripts/collect-support-bundle.mjs` accepts `--configuration` or
  `--state-file` plus optional `--jack-ports-file`, runs the read-only JACK readiness verifier, writes
  `jack-port-requirements.json`, and summarizes readiness as `jack` in `support-bundle.json`. Default support bundles
  keep `jack.status = "not_requested"` so users without a saved Loopwire configuration do not get noisy failures.
- 2026-07-04 support bundle JACK validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempts. `node --check
  scripts/collect-support-bundle.mjs`, `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm check`, `git diff --check`,
  touched-file line-length checks, `gsd-sdk query roadmap.analyze`, and `gsd-sdk query init.milestone-op` passed.
  `pnpm verify:scripts` proves default support bundles mark JACK readiness as not requested and configuration-backed
  bundles include a parsed passing JACK readiness summary. A final codebase-memory MCP retry still failed with
  `Transport closed`. No live JACK server, host audio mutation, VM launch, package install, public release, secret
  write, tag push, Bunny deployment, live URL smoke, or support matrix promotion was performed.
- 2026-07-04 VM target audio proof: `scripts/verify-vm-evidence.sh` now rejects VM evidence whose `detect-audio.json`
  does not report the selected target's expected backend as available. The guard maps `PipeWire/WirePlumber` to
  PipeWire, `PipeWire/PulseAudio compatibility` to PipeWire plus PulseAudio, `PulseAudio` to PulseAudio, and `JACK` to
  JACK.
- 2026-07-04 VM target audio validation: codebase-memory MCP `index_status`, `search_graph`, `list_projects`, and
  `index_repository` failed with `Transport closed`, so this slice used focused shell reads after the required graph
  attempts. `bash -n scripts/verify-vm-evidence.sh scripts/verify-scripts.sh scripts/verify-docs.sh`,
  `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm verify:vm`, and `pnpm check` passed. `pnpm verify:scripts` now
  includes a negative case proving VM evidence is rejected when the target PipeWire backend report is unavailable. No
  VM was launched and no support matrix row was promoted.
- 2026-07-04 published-release evidence binding: `scripts/verify-release-evidence.mjs` now validates that a required
  `published-release-smoke` row ran `scripts/verify-published-release.sh` with the manifest repo, tag, and public key.
  This prevents a green evidence bundle from substituting a fake successful command row for real published-artifact
  install smoke.
- 2026-07-04 published-release evidence validation: codebase-memory MCP `index_status`, `search_graph`,
  `search_code`, and `index_repository` failed with `Transport closed`, so this slice used focused shell reads after
  the required graph attempts. `node --check scripts/verify-release-evidence.mjs`, `bash -n scripts/verify-scripts.sh`,
  `pnpm verify:scripts`, `pnpm verify:docs`, and `pnpm check` passed. `pnpm verify:scripts` now includes a negative
  case proving fake `published-release-smoke` rows are rejected. No public release, tag push, secret write, Bunny
  deployment, live URL smoke, VM launch, or support matrix promotion was performed.
- 2026-07-04 PulseAudio detection gap: `packages/audio-host` now reports `one output per source` in PulseAudio backend
  gaps and warning text, matching the runtime adapter and desktop preflight fail-closed behavior for source fan-out.
  Support matrix, backend docs, unreleased notes, and docs verification now pin the same limitation for support bundles
  and release notes.
- 2026-07-04 PulseAudio detection validation: the detector regression test first failed while the implementation still
  omitted `one output per source`, then passed after the detector update. Codebase-memory MCP `index_status` and
  `index_repository` failed with `Transport closed`, so this slice used focused shell reads after the required graph
  attempts. `pnpm --filter @loopwire/audio-host test -- detectors.test.ts`, audio-host typecheck, `pnpm verify:docs`,
  `pnpm check`, `git diff --check`, touched-file line-length checks, `gsd-sdk query roadmap.analyze`, and
  `gsd-sdk query init.milestone-op` passed. No host audio mutation, VM launch, package install, public release, tag
  push, secret write, Bunny deployment, live URL smoke, or support matrix promotion was performed.
- 2026-07-04 final evidence command hardening: `scripts/verify-release-evidence.mjs` now tokenizes command rows for
  required final proof commands. Published-release, live-docs, and VM evidence rows must directly invoke the expected
  `bash scripts/...` verifier with exact binding flags, so a manifest cannot pass by recording an `echo` command that
  merely prints the expected verifier path and arguments.
- 2026-07-04 final evidence command validation: the new `pnpm verify:scripts` regression first failed because the old
  verifier accepted an echo-disguised VM evidence command, then passed after tokenized validation was added.
  Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this slice used focused
  shell reads after the required graph attempts. `node --check scripts/verify-release-evidence.mjs`,
  `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm check`, `git diff --check`, touched-file line-length checks,
  `gsd-sdk query roadmap.analyze`, and `gsd-sdk query init.milestone-op` passed. No host audio mutation, VM launch,
  package install, public release, tag push, secret write, Bunny deployment, live URL smoke, or support matrix
  promotion was performed.
- 2026-07-04 release readiness tag fidelity: `scripts/verify-release-readiness.sh` now resolves local or remote
  release tags to commits and rejects tags that do not point at the current checkout `HEAD`. This prevents a stale tag
  from satisfying the publish preflight for different source content.
- 2026-07-04 release readiness tag validation: `pnpm verify:scripts` now creates a temporary git repo, passes readiness
  while `v0.1.0` points at `HEAD`, advances `HEAD`, and proves the same tag is rejected as stale. Codebase-memory MCP
  `index_status` and `index_repository` failed with `Transport closed`, so this slice used focused shell reads after
  the required graph attempts. `bash -n scripts/verify-release-readiness.sh scripts/verify-scripts.sh`,
  `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm check`, `git diff --check`, touched-file line-length checks,
  `gsd-sdk query roadmap.analyze`, and `gsd-sdk query init.milestone-op` passed. Real release readiness still failed
  closed on missing public key, candidate notes, missing tag, and missing GitHub secrets. No host audio mutation, VM
  launch, package install, public release, tag push, secret write, Bunny deployment, live URL smoke, or support matrix
  promotion was performed.
- 2026-07-04 release readiness clean checkout: `scripts/verify-release-readiness.sh` now requires a clean git checkout
  by default and exposes `--skip-clean-git` for explicit candidate evidence collection. The release evidence collector
  uses that opt-out only for candidate bundles so dirty release-prep work cannot accidentally satisfy the final publish
  preflight.
- 2026-07-04 release readiness clean-check validation: Codebase-memory MCP `index_status` and `index_repository`
  failed with `Transport closed`, so this slice used focused shell reads after the required graph attempts.
  `bash -n scripts/verify-release-readiness.sh scripts/verify-scripts.sh scripts/verify-docs.sh`,
  `node --check scripts/collect-release-evidence.mjs`, `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm check`,
  touched-file line-length checks, `git diff --check`, `gsd-sdk query roadmap.analyze`, and
  `gsd-sdk query init.milestone-op` passed. Real release readiness still failed closed on missing public key, candidate
  notes, dirty git status, missing tag, and missing GitHub secrets. No host audio mutation, VM launch, package install,
  public release, tag push, secret write, Bunny deployment, live URL smoke, or support matrix promotion was performed.
- 2026-07-04 native route gain lock: Desktop route-control semantics moved into a tested helper, and selected native
  PipeWire/JACK backends now lock route gain sliders because those adapters can only apply link mute/unmute today.
  Existing non-unity route state stays visible, route mute stays usable, and the existing `Reset gains` action remains
  the explicit repair path before live apply.
- 2026-07-04 native route gain lock validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempts.
  `pnpm --filter @loopwire/desktop test -- route-control-semantics.test.ts live-apply-preflight.test.ts`,
  `pnpm --filter @loopwire/desktop typecheck`, `pnpm verify:docs`, and `pnpm --filter @loopwire/desktop build`
  passed. Playwright desktop and mobile smokes against `http://127.0.0.1:4190/` selected PipeWire, confirmed all route
  gain sliders were disabled with locked accessible labels, captured screenshots under `/tmp`, and found zero
  horizontal overflow. No host audio mutation, VM launch, package install, public release, tag push, secret write,
  Bunny deployment, live URL smoke, or support matrix promotion was performed.
- 2026-07-04 runtime activity ledger: Desktop startup restore and configuration clicks now persist the last runtime
  plan log in app state and render an inspectable ledger for startup restore or configuration switch operations. The
  ledger shows unload, apply, verify, and rollback rows from `ConfigurationRuntimeResult.log`, so clicking a
  configuration exposes the actual switch sequence instead of only the final status message.
- 2026-07-04 runtime activity ledger validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempts.
  `pnpm --filter @loopwire/desktop typecheck`, `pnpm --filter @loopwire/desktop build`,
  `pnpm --filter @loopwire/desktop test -- live-apply-preflight.test.ts route-control-semantics.test.ts`, and
  `pnpm verify:docs` passed. Playwright desktop and mobile smokes against `http://127.0.0.1:4191/` verified startup
  restore ledger presence, clicked `Stream`, confirmed `Unload Studio`, `Apply Stream`, and `Verify Stream` rows,
  confirmed `Stream` became active, captured screenshots under `/tmp`, and found zero horizontal overflow. No host
  audio mutation, VM launch, package install, public release, tag push, secret write, Bunny deployment, live URL smoke,
  or support matrix promotion was performed.
- 2026-07-04 release workflow tag checkout: `.github/workflows/release.yml` now validates the resolved release tag as a
  git tag name, fetches tags, resolves `refs/tags/<tag>^{commit}`, and checks out the commit detached in both the
  `build-linux` and `publish-release` jobs before release notes, build, publish, or evidence steps. The build job no
  longer passes `--skip-tag`, so `scripts/verify-release-readiness.sh` also checks that the selected tag points at the
  detached checkout.
- 2026-07-04 release workflow tag-checkout validation: codebase-memory MCP `index_status` and `index_repository`
  failed with `Transport closed`, so this slice used focused shell reads after the required graph attempts.
  `bash -n scripts/verify-github-workflows.sh scripts/verify-docs.sh`, Ruby YAML parsing for
  `.github/workflows/release.yml`, `bash scripts/verify-github-workflows.sh`, `pnpm verify:docs`,
  `pnpm verify:workflows`, `pnpm check`, `git diff --check`, touched-file line-length checks,
  `gsd-sdk query roadmap.analyze`, and `gsd-sdk query init.milestone-op` passed. No host audio mutation, VM launch,
  package install, public release, tag push, secret write, Bunny deployment, live URL smoke, or support matrix
  promotion was performed.
- 2026-07-04 release tag path hardening: `.github/workflows/release.yml` and
  `scripts/verify-release-readiness.sh` now require v-prefixed semver release tags without path separators. This
  rejects tags like `v0.1.0/preview` before release-note, evidence-directory, or evidence-archive paths are derived
  from the tag.
- 2026-07-04 release tag path validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempts.
  `bash -n scripts/verify-release-readiness.sh scripts/verify-scripts.sh scripts/verify-github-workflows.sh
  scripts/verify-docs.sh`, direct tag-regex smoke, expected-failure readiness smoke for `v0.1.0/preview`,
  `bash scripts/verify-github-workflows.sh`, `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm check`,
  `git diff --check`, touched-file line-length checks, and `gsd-sdk query roadmap.analyze` passed. No host audio
  mutation, VM launch, package install, public release, tag push, secret write, Bunny deployment, live URL smoke, or
  support matrix promotion was performed.
- 2026-07-04 release evidence tag contract: `scripts/collect-release-evidence.mjs` and
  `scripts/verify-release-evidence.mjs` now enforce the same v-prefixed semver release tag rule as the release
  workflow and readiness preflight. Path-like tags are rejected before command planning, manifest acceptance, or final
  evidence verification.
- 2026-07-04 release evidence tag validation: codebase-memory MCP `index_status` and `index_repository` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempts.
  `node --check scripts/collect-release-evidence.mjs scripts/verify-release-evidence.mjs`,
  `bash -n scripts/verify-scripts.sh scripts/verify-docs.sh`, expected-failure collector smoke for
  `v0.1.0/preview`, prerelease command-plan smoke for `v0.1.0-rc.1`, `pnpm verify:scripts`, `pnpm verify:docs`,
  `pnpm check`, `git diff --check`, touched-file line-length checks, and `gsd-sdk query roadmap.analyze` passed.
  No host audio mutation, VM launch, package install, public release, tag push, secret write, Bunny deployment, live
  URL smoke, or support matrix promotion was performed.
- 2026-07-04 release proof repository contract: `scripts/verify-release-readiness.sh`,
  `scripts/verify-published-release.sh`, `scripts/collect-release-evidence.mjs`, and
  `scripts/verify-release-evidence.mjs` now require release repository identities in `OWNER/REPO` form. URL-like
  values, spaces, and extra path segments are rejected before GitHub access, command planning, manifest acceptance, or
  final evidence verification.
- 2026-07-04 release proof repository validation: codebase-memory MCP `index_status` and `index_repository` failed
  with `Transport closed`, so this slice used focused shell reads after the required graph attempts.
  `bash -n scripts/verify-release-readiness.sh scripts/verify-published-release.sh scripts/verify-scripts.sh
  scripts/verify-docs.sh`, `node --check scripts/collect-release-evidence.mjs scripts/verify-release-evidence.mjs`,
  targeted negative smokes for URL-like and path-like repositories, `pnpm verify:scripts`, `pnpm verify:docs`,
  `pnpm check`, `git diff --check`, touched-file line-length checks, and `gsd-sdk query roadmap.analyze` passed.
  No host audio mutation, VM launch, package install, public release, tag push, secret write, Bunny deployment, live
  URL smoke, or support matrix promotion was performed.
- 2026-07-04 local release evidence archive tag binding: `scripts/verify-published-release.sh` now derives the expected
  evidence tag from the single `loopwire-release-evidence-<tag>.tar.gz` asset in `--release-dir` mode when `--tag` is
  omitted. The extracted `release-evidence.json` must match that archive-name tag before local signed release-directory
  proof can pass.
- 2026-07-04 local release evidence archive validation: codebase-memory MCP `index_status` and `index_repository`
  failed with `Transport closed`, so this slice used focused shell reads after the required graph attempts. `bash -n
  scripts/verify-published-release.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, `node --check
  scripts/collect-release-evidence.mjs scripts/verify-release-evidence.mjs`, `pnpm verify:docs`,
  `pnpm verify:scripts`, `pnpm check`, `pnpm detect:audio`, `git diff --check`, touched-file line-length checks,
  `gsd-sdk query roadmap.analyze`, and `gsd-sdk query init.milestone-op` passed. `pnpm verify:scripts` now proves local
  release-directory verification passes without an explicit `--tag` when the evidence archive name and manifest agree,
  and rejects archive-name/manifest tag drift. No host audio mutation, VM launch, package install, public release, tag
  push, secret write, Bunny deployment, live URL smoke, or support matrix promotion was performed.
- 2026-07-04 live-docs release evidence binding: `scripts/verify-release-evidence.mjs` now requires
  `docs-live-smoke` command rows to use the same docs base URL or hostname plus remote prefix recorded in
  `release-evidence.json`. The verifier still requires the public installer path and direct
  `bash scripts/verify-docs-live.sh` invocation.
- 2026-07-04 live-docs release evidence validation: codebase-memory MCP `index_status` and `index_repository` failed
  with `Transport closed`, so this slice used focused shell reads after the required graph attempts. `pnpm
  verify:scripts` first failed because the old verifier accepted a live-docs command for `wrong-docs.example.test`, then
  passed after binding validation was added. `node --check scripts/verify-release-evidence.mjs
  scripts/collect-release-evidence.mjs`, `bash -n scripts/verify-scripts.sh scripts/verify-docs.sh`,
  `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm check`, `pnpm detect:audio`, `git diff --check`, touched-file
  line-length checks, `gsd-sdk query roadmap.analyze`, and `gsd-sdk query init.milestone-op` passed. Release docs,
  unreleased notes, and `scripts/verify-docs.sh` now document and guard the deployment binding. No host audio mutation,
  VM launch, package install, public release, tag push, secret write, Bunny deployment, live URL smoke, or support
  matrix promotion was performed.
- 2026-07-04 release evidence public-key binding: `scripts/verify-release-evidence.mjs` now accepts `--public-key` and
  requires `release.publicKey` to match it. `scripts/verify-published-release.sh --require-release-evidence` forwards
  the same public key used to verify `SHA256SUMS.sig`, so the public evidence archive cannot prove install smoke with a
  different signing trust root.
- 2026-07-04 release evidence public-key validation: codebase-memory MCP `index_status` and `index_repository` failed
  with `Transport closed`, so this slice used focused shell reads after the required graph attempts.
  `pnpm verify:scripts` first failed because the old verifier accepted a release evidence manifest and
  `published-release-smoke` command using `packaging/other-release-signing-public.pem`; after implementation it passed
  with the wrong-key negative case and local signed release-directory fixture rebound to the generated temp public key.
  `node --check scripts/verify-release-evidence.mjs scripts/collect-release-evidence.mjs`,
  `bash -n scripts/verify-published-release.sh scripts/verify-scripts.sh scripts/verify-docs.sh`,
  `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm check`, `pnpm detect:audio`, `git diff --check`, touched-file
  line-length checks, `gsd-sdk query roadmap.analyze`, and `gsd-sdk query init.milestone-op` passed. Release docs,
  unreleased notes, and `scripts/verify-docs.sh` now document and guard the public-key binding. No host audio mutation,
  VM launch, package install, public release, tag push, secret write, Bunny deployment, live URL smoke, or support matrix
  promotion was performed.
- 2026-07-04 release evidence git-head binding: `scripts/verify-release-evidence.mjs` now accepts `--git-head` and
  rejects evidence whose `git.head` differs from the expected release commit. The release workflow exports the resolved
  tag commit as `LOOPWIRE_RELEASE_COMMIT`, verifies the collected evidence with that SHA and the release public key, and
  passes the same SHA into `scripts/verify-published-release.sh --require-release-evidence`.
- 2026-07-04 release evidence git-head validation: codebase-memory MCP `index_status` and `index_repository` failed
  with `Transport closed`, so this slice used focused shell reads after the required graph attempts.
  `pnpm verify:scripts` first failed because the old verifier ignored `--git-head` and accepted a wrong expected commit;
  after implementation it passed with direct verifier and published-release archive wrong-head negative cases.
  `node --check scripts/verify-release-evidence.mjs scripts/collect-release-evidence.mjs`,
  `bash -n scripts/verify-published-release.sh scripts/verify-scripts.sh scripts/verify-docs.sh
  scripts/verify-github-workflows.sh`, `pnpm verify:docs`, `pnpm verify:workflows`, Ruby workflow YAML parsing,
  `pnpm verify:scripts`, `pnpm check`, `git diff --check`, and touched-file line-length checks passed. Release docs,
  unreleased notes, `scripts/verify-docs.sh`, and `scripts/verify-github-workflows.sh` now document and guard the
  git-head binding. No host audio mutation, VM launch, package install, public release, tag push, secret write, Bunny
  deployment, live URL smoke, or support matrix promotion was performed.
- 2026-07-04 final release proof wrapper: `scripts/verify-final-release-proof.sh` and `pnpm verify:final-release` now
  provide one strict final gate for the full stop condition. The wrapper verifies signed published release assets with
  `--require-release-evidence`, live docs smoke, final release evidence with published-release/live-docs/all-VM-target
  requirements, each `vm/targets.tsv` evidence bundle with installed-release smoke, support-matrix promotion, and the
  docs contract. `--dry-run` prints the full command plan without touching network, release assets, docs URLs, or VM
  evidence.
- 2026-07-04 final release proof wrapper validation: codebase-memory MCP `index_status` and `index_repository` failed
  with `Transport closed`, so this slice used focused shell reads after the required graph attempts.
  `pnpm verify:final-release -- --repo sandwichfarm/loopwire --tag v0.1.0 --public-key
  packaging/release-signing-public.pem --git-head 0123456789abcdef0123456789abcdef01234567 --release-evidence-dir
  .release-evidence/v0.1.0-published --docs-hostname docs.example.test --docs-remote-prefix preview --vm-evidence-root
  .vm/evidence --dry-run` passed and printed published-release, live-docs, release-evidence, all nine VM evidence,
  support-matrix, and docs-contract commands. `pnpm verify:scripts`, `pnpm verify:docs`, `bash -n` for the final proof
  wrapper and script/doc guards, touched-file line-length checks, and `git diff --check` passed. No host audio mutation,
  VM launch, package install, public release, tag push, secret write, Bunny deployment, live URL smoke, or support matrix
  promotion was performed.
- 2026-07-04 final support-matrix strictness: `scripts/verify-support-matrix.mjs` now accepts `--matrix` and
  `--require-published-release`; final proof passes the release support-matrix path and requires installed-release
  smoke for every `Verified` row. `pnpm verify:scripts` proves strict mode rejects a forced `Verified` row whose
  evidence bundle has no `published-release-smoke`, then accepts the same target after the release-smoke row and log are
  present.
- 2026-07-04 final support-matrix strictness validation: codebase-memory MCP `index_status` and `index_repository`
  failed with `Transport closed`, so this slice used focused shell reads after the required graph attempts.
  `bash -n scripts/verify-final-release-proof.sh scripts/verify-scripts.sh scripts/verify-docs.sh`,
  `node --check scripts/verify-support-matrix.mjs`, touched-file line-length checks, `pnpm verify:scripts`,
  `pnpm verify:docs`, `pnpm check`, `pnpm detect:audio`, `git diff --check`, `gsd-sdk query roadmap.analyze`, and
  `gsd-sdk query init.milestone-op` passed. The final proof dry-run with
  `--support-matrix apps/docs/docs/guide/support-matrix.md` printed support-matrix verification with
  `--require-published-release`. No host audio mutation, VM launch, package install, public release, tag push, secret
  write, Bunny deployment, live URL smoke, or support matrix promotion was performed.
- 2026-07-04 VM evidence status inventory: `scripts/vm-matrix.sh evidence-status` and `pnpm vm:evidence-status` now
  report `status=missing`, `status=invalid`, or `status=verified` for target-scoped evidence bundles under an
  evidence root. The command prints the matching verifier command, collector handoff for missing targets, and a
  checked/verified/missing/invalid summary without promoting support-matrix rows.
- 2026-07-04 VM evidence status validation: codebase-memory MCP `index_status` failed with `Transport closed`, so this
  slice used focused shell reads after the required graph attempt. `bash -n scripts/vm-matrix.sh
  scripts/verify-scripts.sh scripts/verify-docs.sh`, package JSON parsing, direct and pnpm missing-evidence smokes,
  touched-file line-length checks, `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm verify:vm`, `pnpm check`,
  `pnpm detect:audio`, all-target `evidence-status` against an empty temp root, `git diff --check`,
  `gsd-sdk query roadmap.analyze`, and `gsd-sdk query init.milestone-op` passed. `pnpm verify:scripts` also covers a
  verified fixture bundle, strict-mode rejection before `published-release-smoke`, and strict-mode success after that
  smoke row exists. No host audio mutation, VM launch, package install, public release, tag push, secret write, Bunny
  deployment, live URL smoke, or support matrix promotion was performed.
- 2026-07-04 all-target VM evidence promotion: `scripts/promote-vm-evidence.mjs` now accepts `--all` and
  `--evidence-root`, verifies each existing target-scoped evidence bundle before promotion, reports missing evidence
  directories, fails invalid evidence, and writes all support-matrix row promotions in one guarded operation. The
  existing single-target path still supports `--target`, `--evidence-dir`, `--matrix`, `--dry-run`, and
  `--require-published-release`.
- 2026-07-04 all-target VM evidence promotion validation: codebase-memory MCP `index_status` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempt.
  `node --check scripts/promote-vm-evidence.mjs`, `bash -n scripts/verify-scripts.sh scripts/verify-docs.sh`,
  promotion help readback, touched-file line-length checks, `pnpm verify:scripts`, `pnpm verify:docs`,
  `pnpm verify:vm`, `pnpm check`, `pnpm detect:audio`, `git diff --check`, `gsd-sdk query roadmap.analyze`, and
  `gsd-sdk query init.milestone-op` passed. `pnpm verify:scripts` proves all-target dry-run does not mutate the matrix,
  reports missing target evidence, promotes the verified fixture row after release-smoke evidence exists, and rejects
  invalid `--all --target` and `--all --evidence-dir` argument combinations. No host audio mutation, VM launch,
  package install, public release, tag push, secret write, Bunny deployment, live URL smoke, or real support matrix
  promotion was performed.
- 2026-07-04 JACK readiness contract: `packages/audio-host` now exports `describeJackPortReadiness`, a shared matcher
  that reports per-requirement readiness, matched ports, missing ports, and port counts from the same deterministic
  JACK requirement helper used by runtime plans. Native JACK apply/verify failures for missing host or Loopwire-owned
  ports now include the exact suggested channel ports before any `jack_connect` mutation.
- 2026-07-04 JACK readiness contract validation: codebase-memory MCP was unavailable or insufficient (`Transport
  closed` / oversized output), so this slice used focused shell reads after the graph attempts.
  `pnpm --filter @loopwire/audio-host test -- --runInBand`, `pnpm --filter @loopwire/audio-host typecheck`,
  `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm check`, `pnpm detect:audio`, `git diff --check`, touched-file
  line-length checks, `gsd-sdk query roadmap.analyze`, and `gsd-sdk query init.milestone-op` passed.
  `pnpm jack:verify -- --configuration <tmp> --ports-file <tmp> --pretty` also passed against a temporary normalized
  JACK fixture. No host audio mutation, VM launch, package install, public release, tag push, secret write, Bunny
  deployment, live URL smoke, or support matrix promotion was performed.
- 2026-07-04 core DSP mix planner: `packages/core/src/dsp-mix.ts` now exports `createDspMixPlan` and
  `renderDspMixPlan`. The pure planner derives output contribution plans from a valid configuration, applies per-edge
  gain/mute to supplied planar `Float32Array` source buffers, sums active routes without clamping float headroom,
  reports missing source buffers, and covers one-source-to-many-output routing math.
- 2026-07-04 core DSP mix validation: codebase-memory MCP `search_graph` failed with `Transport closed`, so this slice
  used focused shell reads after the required graph attempt. The first `pnpm --filter @loopwire/core test --
  --runInBand` run failed because `createDspMixPlan` did not exist. After implementation,
  `pnpm --filter @loopwire/core test -- --runInBand`, `pnpm --filter @loopwire/core typecheck`, `pnpm verify:docs`,
  `pnpm verify:scripts`, `pnpm check`, `pnpm detect:audio`, `git diff --check`, touched-file line-length checks,
  `gsd-sdk query roadmap.analyze`, and `gsd-sdk query init.milestone-op` passed. No host audio mutation, live backend
  DSP insertion, VM launch, package install, public release, tag push, secret write, Bunny deployment, live URL smoke,
  or support matrix promotion was performed.
- 2026-07-04 core DSP cycle runner: `packages/core/src/dsp-mix.ts` now exports `listDspSourceRequests` and
  `runDspMixCycle`. The cycle runner deduplicates required sources, reads buffers through injected source ports,
  renders the shared DSP mix plan, writes rendered outputs through injected output ports, can fail closed before writes
  when required source buffers are missing, and reports write failures with the outputs already written.
- 2026-07-04 core DSP cycle validation: codebase-memory MCP `search_graph` failed with `Transport closed`, so this
  slice used focused shell reads after the required graph attempt. The first `pnpm --filter @loopwire/core test --
  --runInBand` run failed because `listDspSourceRequests` and `runDspMixCycle` did not exist. After implementation,
  `pnpm --filter @loopwire/core test -- --runInBand`, `pnpm --filter @loopwire/core typecheck`, `pnpm verify:docs`,
  `pnpm verify:scripts`, `pnpm check`, `pnpm detect:audio`, `git diff --check`, touched-file line-length checks,
  `gsd-sdk query roadmap.analyze`, and `gsd-sdk query init.milestone-op` passed. No host audio mutation, live backend
  DSP insertion, VM launch, package install, public release, tag push, secret write, Bunny deployment, live URL smoke,
  or support matrix promotion was performed.
- 2026-07-04 audio-host DSP graph adapter: `packages/audio-host/src/dsp-adapter.ts` now wraps the core DSP cycle
  runner behind injected runtime ports. It supports dry-run planning, apply-mode source reads and output writes,
  fail-closed missing-source behavior, verifier-driven output checks, and clear-on-rollback/unload behavior without
  touching live PipeWire or JACK state.
- 2026-07-04 audio-host DSP adapter validation: codebase-memory MCP `search_graph` failed with `Transport closed`, so
  this slice used focused shell reads after the required graph attempt. `pnpm --filter @loopwire/audio-host test --
  --runInBand`, `pnpm --filter @loopwire/audio-host typecheck`, `pnpm verify:docs`, `pnpm verify:scripts`,
  `pnpm check`, `pnpm detect:audio`, `git diff --check`, source/docs touched-file line-length checks,
  `gsd-sdk query roadmap.analyze`, and `gsd-sdk query init.milestone-op` passed. Early `pnpm verify:docs` runs caught
  line-wrapped guard phrases before the final docs contract passed. No host audio mutation, live backend DSP insertion,
  VM launch, package install, public release, tag push, secret write, Bunny deployment, live URL smoke, or support
  matrix promotion was performed.
- 2026-07-04 data-driven route-control semantics: `apps/desktop/src/route-control-semantics.ts`,
  `apps/desktop/src/live-apply-preflight.ts`, and `apps/desktop/src/App.svelte` now consume detected backend mixing
  reports for route-control status, route-gain locking, and live-apply preflight. Synthetic graph-edge capability
  tests prove PipeWire-style reports can unlock per-route gain while still blocking missing source ports, and JACK-style
  graph-edge reports with virtual-device creation can skip the old link-only gain/port blockers.
- 2026-07-04 data-driven route-control validation: codebase-memory MCP `search_graph` failed with `Transport closed`,
  so this slice used focused shell reads after the required graph attempt. The first
  `pnpm --filter @loopwire/desktop test -- --runInBand` run failed because helper logic ignored graph-edge capability
  reports. After implementation, `pnpm --filter @loopwire/desktop test -- --runInBand`,
  `pnpm --filter @loopwire/desktop typecheck`, `pnpm --filter @loopwire/desktop build`, `pnpm verify:docs`,
  `pnpm verify:scripts`, `pnpm check`, `pnpm detect:audio`, `git diff --check`, source/docs/GSD touched-file
  line-length checks, `gsd-sdk query roadmap.analyze`, and `gsd-sdk query init.milestone-op` passed. The live detection
  smoke still reports PipeWire as link-only and PulseAudio compatibility as stream-level, so no live graph-edge DSP
  behavior was claimed.
- 2026-07-04 DSP runtime rollback contract: `packages/audio-host/src/dsp-adapter.ts` now treats `unload` as clear-only
  and `rollback` as a restore operation. Rollback clears the last written DSP outputs when a clear port is supplied,
  then re-renders the rollback configuration through the same injected source/output ports. This aligns the adapter
  with `@loopwire/core` configuration switch semantics, where a failed apply or verify rolls back to the previous
  configuration.
- 2026-07-04 DSP rollback validation: codebase-memory MCP `search_graph` failed with `Transport closed`, so this slice
  used focused shell reads after the required graph attempt. The first `pnpm --filter @loopwire/audio-host test --
  --runInBand` run failed because rollback only cleared outputs and did not restore the previous DSP mix through
  `applyConfigurationSwitch`. After implementation, `pnpm --filter @loopwire/audio-host test -- --runInBand`,
  `pnpm --filter @loopwire/audio-host typecheck`, `pnpm --filter @loopwire/core test -- --runInBand`,
  `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm check`, `pnpm detect:audio`, `git diff --check`,
  source/docs/GSD touched-file line-length checks, `gsd-sdk query roadmap.analyze`, and
  `gsd-sdk query init.milestone-op` passed. No live host audio mutation, VM launch, package install, public release,
  tag push, secret write, Bunny deployment, live URL smoke, or support matrix promotion was performed.
- 2026-07-04 DSP configuration runtime wrapper: `packages/audio-host/src/dsp-adapter.ts` now exports
  `createDspConfigurationRuntimeAdapter`, a first-class `ConfigurationRuntimeAdapter` wrapper around the injected DSP
  graph adapter. The wrapper makes startup re-apply and configuration switch transactions call through the exact core
  runtime contract instead of relying on structural method compatibility.
- 2026-07-04 DSP configuration runtime wrapper validation: codebase-memory MCP `search_graph` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempt. The first
  `pnpm --filter @loopwire/audio-host test -- --runInBand` run failed because
  `createDspConfigurationRuntimeAdapter` did not exist. After implementation,
  `pnpm --filter @loopwire/audio-host test -- --runInBand`, `pnpm --filter @loopwire/audio-host typecheck`,
  `pnpm --filter @loopwire/core test -- --runInBand`, `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm check`,
  `pnpm detect:audio`, `git diff --check`, touched-file line-length checks, `gsd-sdk query roadmap.analyze`, and
  `gsd-sdk query init.milestone-op` passed. No live host audio mutation, VM launch, package install, public release,
  tag push, secret write, Bunny deployment, live URL smoke, or support matrix promotion was performed.
- 2026-07-04 JACK injected virtual-port provider: `packages/audio-host/src/jack-adapter.ts` now accepts an injected
  `JackVirtualPortProvider`. When all missing readiness requirements are Loopwire-owned JACK ports, apply/verify/unload
  can ask the provider to create those ports, re-run `jack_lsp`, and continue only if the required ports exist.
  Configured host-port gaps still fail through the existing missing-port path, and the shipped desktop path still does
  not bundle a real JACK client provider.
- 2026-07-04 JACK injected provider validation: codebase-memory MCP `search_graph` failed with `Transport closed`, so
  this slice used focused shell reads after the required graph attempt. The first
  `pnpm --filter @loopwire/audio-host test -- --runInBand` run failed because the adapter did not consult a virtual-port
  provider. After implementation, `pnpm --filter @loopwire/audio-host test -- --runInBand`,
  `pnpm --filter @loopwire/audio-host typecheck`, `pnpm verify:docs`, and touched-file line-length checks passed before
  the broader gate run. Final validation passed with `pnpm verify:scripts`, `pnpm check`, `pnpm detect:audio`,
  `git diff --check`, touched-file line-length checks, `gsd-sdk query roadmap.analyze`, and
  `gsd-sdk query init.milestone-op`. No live JACK server, host audio mutation, VM launch, package install, public
  release, tag push, secret write, Bunny deployment, live URL smoke, or support matrix promotion was performed.
- 2026-07-04 command-backed JACK provider: `packages/audio-host/src/jack-adapter.ts` now exports
  `createJackVirtualPortCommandProvider`, which maps a `JackVirtualPortProvisionPlan` to stable
  `ensure --configuration-id ... --requirement ... --port ...` command arguments and preserves provider stderr on
  failure. `scripts/restore-background.mjs` accepts `--jack-provider-command` and
  `--jack-provider-timeout-ms`, then passes the command-backed provider into JACK startup restore.
- 2026-07-04 command-backed JACK provider validation: codebase-memory MCP `search_graph` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempt. The first
  `pnpm --filter @loopwire/audio-host test -- --runInBand` run failed because
  `createJackVirtualPortCommandProvider` did not exist. After implementation,
  `pnpm --filter @loopwire/audio-host test -- --runInBand`, `pnpm --filter @loopwire/audio-host typecheck`,
  `node --check scripts/restore-background.mjs`, `pnpm verify:scripts`, `pnpm verify:docs`, and touched-file
  line-length checks passed before the broader gate run. Final validation passed with `pnpm check`,
  `pnpm detect:audio`, `git diff --check`, `gsd-sdk query roadmap.analyze`, and
  `gsd-sdk query init.milestone-op`. No real JACK provider binary was executed, and no live JACK server, host audio
  mutation, VM launch, package install, public release, tag push, secret write, Bunny deployment, live URL smoke, or
  support matrix promotion was performed.
- 2026-07-04 boot restore and VM launch surface: `scripts/manage-autostart.sh` now uses one restore-argument renderer
  for source-checkout and packaged systemd units, so boot restore preserves state file, mode, PulseAudio retry, and
  JACK provider flags. `pnpm vm:launch` now forwards to the dry-run-first VM launch planner.
- 2026-07-04 boot restore and VM launch validation: codebase-memory MCP `search_graph` failed with `Transport closed`,
  so this slice used focused shell reads after the required graph attempt. The first `pnpm verify:autostart` run failed
  because `manage-autostart.sh` rejected `--jack-provider-command`. After implementation, `bash -n` for touched shell
  scripts, `pnpm vm:launch -- --target arch-hyprland-pipewire --image /operator/images/arch.qcow2 --ssh-port 2322`,
  `pnpm verify:autostart`, `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm verify:vm`, `pnpm check`,
  `pnpm detect:audio`, `git diff --check`, touched-file line-length checks, `gsd-sdk query roadmap.analyze`, and
  `gsd-sdk query init.milestone-op` passed. The VM launch dry-run wrote no `.vm/run` state. No real JACK provider
  binary was executed, and no live VM, host audio mutation, package install, public release, tag push, secret write,
  Bunny deployment, live URL smoke, or support matrix promotion was performed.
- 2026-07-04 VM launch-plan surface: `scripts/vm-matrix.sh render-launch-plan` now emits TSV rows with target,
  operator-owned image placeholder, image format, firmware placeholder, SSH port, memory, CPU count, dry-run launch
  command, and matching evidence-pull command. `pnpm vm:render-launch-plan` exposes the same all-target handoff.
- 2026-07-04 VM launch-plan validation: codebase-memory MCP `search_graph` failed with `Transport closed`, so this
  slice used focused shell reads after the required graph attempt. `bash -n scripts/vm-matrix.sh
  scripts/verify-scripts.sh scripts/verify-docs.sh`, direct `pnpm vm:render-launch-plan -- --all --image-root
  /operator/images --start-port 2600` readback, `pnpm verify:scripts`, `pnpm verify:docs`, and `pnpm verify:vm`
  passed before the broader gate run. No VM was launched, no `.vm/run` state was written, no image was downloaded, and
  no support matrix row was promoted.
- 2026-07-04 final release VM launch-plan evidence: `scripts/collect-release-evidence.mjs` now records
  `vm-launch-plan.tsv` in every evidence profile plus `release.vmLaunchPlan` metadata for image root and start port.
  `scripts/verify-release-evidence.mjs --require-vm-launch-plan` now requires a successful `vm-launch-plan` command,
  validates the `render-launch-plan --all` invocation, checks every `vm/targets.tsv` row in the TSV log, and verifies
  the paired dry-run `scripts/vm-matrix.sh launch` and `scripts/collect-vm-evidence-ssh.sh --execute` commands.
- 2026-07-04 final release VM launch-plan validation: codebase-memory MCP `search_graph` failed with
  `Transport closed`, so this slice used focused shell reads after the required graph attempt. `node --check
  scripts/collect-release-evidence.mjs`, `node --check scripts/verify-release-evidence.mjs`,
  `bash -n scripts/verify-final-release-proof.sh scripts/verify-scripts.sh scripts/verify-docs.sh`,
  `pnpm verify:scripts`, and `pnpm verify:docs` passed before the broader gate run. No VM was launched, no `.vm/run`
  state was written, no image was downloaded, no public release was created, no secret was written, and no support
  matrix row was promoted. Final validation also passed with `pnpm verify:vm`, `pnpm check`, `pnpm detect:audio`,
  `git diff --check`, touched-file line-length checks, `gsd-sdk query roadmap.analyze`, and
  `gsd-sdk query init.phase-op 12`.
- 2026-07-04 VM matrix runbook generation: `scripts/vm-matrix.sh render-runbook` now renders a markdown operator
  runbook from `vm/targets.tsv` for `--target` or `--all`, reusing the launch/evidence command builders and the same
  port/resource validation as launch-plan rendering. `package.json` exposes `pnpm vm:render-runbook`, and docs explain
  that it is non-mutating until an operator runs printed `--execute` commands.
- 2026-07-04 VM matrix runbook validation: codebase-memory MCP `search_graph` failed with `Transport closed`, so this
  slice used focused shell reads after the required graph attempt. `bash -n scripts/vm-matrix.sh
  scripts/verify-scripts.sh scripts/verify-docs.sh`, touched-file line-length checks, direct
  `pnpm vm:render-runbook -- --target arch-hyprland-pipewire --image-root /operator/images --start-port 2600`
  readback, `pnpm verify:scripts`, and `pnpm verify:docs` passed before the broader gate run. No VM was launched,
  no `.vm/run` state was written, no image was downloaded, no package was installed, no public release was created,
  no secret was written, and no support matrix row was promoted. Final validation also passed with `pnpm verify:vm`,
  `pnpm check`, `pnpm detect:audio`, `git diff --check`, touched-file line-length checks,
  `gsd-sdk query roadmap.analyze`, and `gsd-sdk query init.phase-op 12`.
- 2026-07-04 release private key secret setup: the current `gh secret set` CLI rejected the helper's obsolete
  `--body-file` usage. `scripts/setup-github-secrets.sh` now writes all secrets through stdin and
  `scripts/verify-scripts.sh` has fake-`gh` write coverage for Bunny values and the release private key file.
  `bash -n scripts/setup-github-secrets.sh scripts/verify-scripts.sh` passed, and a helper dry-run with the real
  release key pair printed only `LOOPWIRE_RELEASE_PRIVATE_KEY`.
- 2026-07-04 release private key GitHub secret evidence: `openssl pkey -in
  /home/sandwich/.config/loopwire/release/loopwire-release-private.pem -pubout` matched
  `packaging/release-signing-public.pem`, then `bash scripts/setup-github-secrets.sh --repo sandwichfarm/loopwire
  --release-private-key-file /home/sandwich/.config/loopwire/release/loopwire-release-private.pem
  --release-public-key-file packaging/release-signing-public.pem` succeeded. Live readback with
  `gh secret list --repo sandwichfarm/loopwire` shows `LOOPWIRE_RELEASE_PRIVATE_KEY`, while
  `bash scripts/setup-github-secrets.sh --repo sandwichfarm/loopwire --check` still fails closed on missing
  `BUNNY_STORAGE_ZONE` and `BUNNY_ACCESS_KEY`. A release readiness preflight with tag and clean-git checks skipped
  now fails on the two Bunny secrets, not the release signing secret.
- 2026-07-04 release secret final validation: `pnpm verify:scripts`, `pnpm verify:docs`, full `pnpm check`,
  `pnpm detect:audio`, `git diff --check`, added-line length scan, `gsd-sdk query roadmap.analyze --format json`,
  `gsd-sdk query init.phase-op 12 --format json`, and codebase-memory MCP `index_status` passed. No Bunny secret was
  available or written, no public release was created, no tag was pushed, no VM was launched, and no support matrix row
  was promoted.
- 2026-07-04 final proof workflow handoff: `.github/workflows/final-release-proof.yml` now provides a manual
  `workflow_dispatch` gate for the completed release ceremony. It validates the tag and expected commit, downloads
  `loopwire-release-evidence-<tag>.tar.gz` and `loopwire-vm-evidence-<tag>.tar.gz` from the GitHub Release, supports
  live docs proof by base URL or Bunny hostname/prefix, and runs `scripts/verify-final-release-proof.sh` with the
  extracted evidence roots.
- 2026-07-04 final proof workflow validation: codebase-memory MCP `search_graph` and `search_code` located the
  existing final-proof, docs-live, and workflow contract surfaces before implementation. `pnpm verify:workflows`,
  `pnpm verify:docs`, Ruby workflow YAML parsing for `.github/workflows/final-release-proof.yml`, `git diff --check`,
  and an added-line length scan passed. No release asset, VM evidence archive, Bunny deployment, live URL smoke,
  tag push, or public release was created.
- 2026-07-04 final proof asset-name validation: `.github/workflows/final-release-proof.yml` now validates optional
  release and VM evidence asset inputs with `scripts/validate-release-asset-name.sh` before download path construction.
  The validator accepts basename-only tag-bound evidence tarballs and rejects traversal, URL-like names, glob patterns,
  wrong evidence-kind prefixes, and tag mismatches. Codebase-memory MCP `index_status` reported
  `home-sandwich-Develop-loopwire` ready with 2555 nodes and 5415 edges, and graph search found the final proof
  workflow surface before implementation.
- 2026-07-04 published-release safe extraction: `scripts/verify-published-release.sh` now uses
  `scripts/extract-safe-tar.sh` for required `loopwire-release-evidence-<tag>.tar.gz` extraction, replacing its local
  path-only checker with the same absolute-path, traversal, dot-segment, duplicate-separator, symlink, and hardlink
  guard used by final proof. Codebase-memory MCP `index_status` reported ready, and graph search found the published
  release verifier and release-evidence surfaces before implementation.
- 2026-07-04 published-release safe extraction validation: `bash -n scripts/verify-published-release.sh
  scripts/verify-scripts.sh scripts/verify-docs.sh`, `pnpm verify:scripts`, `pnpm verify:docs`, offline
  `pnpm verify:release-readiness -- --repo sandwichfarm/loopwire --tag v0.1.0 --public-key
  packaging/release-signing-public.pem --skip-gh --skip-tag --skip-clean-git --allow-candidate-notes`,
  `pnpm verify:requirements`, `pnpm check`, `pnpm detect:audio`, `git diff --check`, added-line length scan, GSD
  roadmap/phase queries, and codebase-memory MCP fast reindex/status passed. `pnpm verify:scripts` rejects a signed
  fake release whose evidence archive contains a symlinked manifest member. No VM launch, public release, release asset
  upload, Bunny deployment, or support-matrix promotion was performed.
- 2026-07-04 final proof checksum binding: `scripts/verify-release-asset-checksum.sh` now verifies a single downloaded
  release asset against signed `SHA256SUMS`, requiring exactly one manifest entry and rejecting missing entries,
  duplicate entries, tampered assets, and unsafe asset names. `.github/workflows/final-release-proof.yml` downloads
  `SHA256SUMS`/`SHA256SUMS.sig` and verifies both release and VM evidence archives before extraction. Codebase-memory
  MCP `index_status` reported ready, and graph search found the checksum/signature/final-proof surfaces before
  implementation.
- 2026-07-04 final proof checksum binding validation: `bash -n scripts/verify-release-asset-checksum.sh
  scripts/verify-release-readiness.sh scripts/verify-scripts.sh scripts/verify-github-workflows.sh`,
  `pnpm verify:scripts`, `pnpm verify:workflows`, `pnpm verify:docs`, offline `pnpm verify:release-readiness -- --repo
  sandwichfarm/loopwire --tag v0.1.0 --public-key packaging/release-signing-public.pem --skip-gh --skip-tag
  --skip-clean-git --allow-candidate-notes`, `pnpm verify:requirements`, `pnpm check`, `pnpm detect:audio`,
  `git diff --check`, added-line length scan, GSD roadmap/phase queries, and codebase-memory MCP fast reindex/status
  passed. `pnpm verify:scripts` covers missing checksum entries, duplicate entries, tampered assets, and the successful
  signed-asset smoke path. No VM launch, public release, release asset upload, Bunny deployment, or support-matrix
  promotion was performed.
- 2026-07-04 Nix release package renderer: `scripts/render-nix-release-package.sh` now reads canonical
  `loopwire-linux-x86_64.tar.gz` and `loopwire-linux-aarch64.tar.gz` entries from `SHA256SUMS`, verifies each asset
  checksum, optionally verifies the signed manifest through `scripts/verify-release-asset-checksum.sh`, converts hashes
  to Nix SRI form, and writes a concrete `loopwire-bin` Nix expression for a published release.
- 2026-07-04 Nix release package renderer validation: `bash -n scripts/render-nix-release-package.sh
  scripts/verify-packaging.sh scripts/verify-scripts.sh scripts/verify-requirements.sh`, `pnpm verify:packaging`,
  `pnpm verify:requirements`, `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm check`, `pnpm detect:audio`, GSD
  roadmap/phase queries, and codebase-memory MCP fast reindex/status passed. `pnpm verify:packaging` renders a
  temporary Nix expression from checksum-bound fake artifacts and rejects duplicate checksum entries. No real
  `nix build`, public release, tag push, Bunny deployment, VM launch, or support-matrix promotion was performed.
- 2026-07-04 Nix release package build verifier: `scripts/verify-nix-release-package.sh` wraps
  `scripts/render-nix-release-package.sh` and then runs `nix build -f <rendered> --arg loopwireSrc <repo> --no-link`
  when `nix` is available. It fails closed by default when `nix` is missing, supports `--skip-build-if-missing-nix`
  only for non-Nix wiring checks, and supports `--render-only` for fake-artifact metadata smokes.
- 2026-07-04 Nix release package build verifier validation: `bash -n scripts/verify-nix-release-package.sh
  scripts/verify-packaging.sh scripts/verify-scripts.sh scripts/verify-requirements.sh`, `pnpm verify:packaging`,
  `pnpm verify:requirements`, `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm check`, `pnpm detect:audio`, GSD
  roadmap/phase queries, and codebase-memory MCP fast reindex/status passed. `pnpm verify:packaging` runs the verifier
  in `--render-only` mode against checksum-bound fake artifacts so Nix-enabled hosts do not try to build unpublished
  fake tarballs. No non-skipped `nix build`, public release, tag push, Bunny deployment, VM launch, or support-matrix
  promotion was performed.
- 2026-07-04 published-release Nix proof gate: `scripts/verify-nix-release-package.sh` now supports
  `--repo OWNER/REPO --tag vX.Y.Z`, downloads signed release assets with `gh`, and still fails closed unless real
  `nix build` proof succeeds. `scripts/collect-release-evidence.mjs` / `scripts/verify-release-evidence.mjs` expose
  `--require-nix-release`, and `scripts/verify-final-release-proof.sh` now runs the published-release Nix package
  verifier directly before release evidence, VM evidence, support-matrix, and docs proof.
- 2026-07-04 published-release Nix proof validation: `bash -n` for changed shell scripts, `node --check` for release
  evidence scripts, `pnpm verify:packaging`, `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm verify:workflows`,
  `pnpm verify:requirements`, offline `pnpm verify:release-readiness`, `pnpm verify:vm`, `pnpm detect:audio`,
  `pnpm check`, `git diff --check`, added-line length scan, and GSD roadmap/phase queries passed. Codebase-memory MCP
  `index_status` reported ready with 2,616 nodes and 5,447 edges. No non-skipped `nix build`, GitHub release, tag
  push, Bunny deployment, VM launch, or support-matrix promotion was performed.
- 2026-07-04 final proof Nix runner setup: `.github/workflows/final-release-proof.yml` now installs
  `DeterminateSystems/determinate-nix-action@v3.21.2` before the release proof script runs. Release readiness and
  workflow contract verification now require that pinned Nix setup so the final GitHub runner cannot reach the Nix
  package proof step without `nix`.
- 2026-07-04 VM evidence archive packager: `scripts/package-vm-evidence.sh` now validates a v-prefixed release tag,
  selects one or all targets from `vm/targets.tsv`, re-runs `scripts/verify-vm-evidence.sh` for every selected bundle,
  and writes a deterministic `vm-evidence/<target>` tarball for final release proof. `package.json` exposes
  `pnpm vm:package-evidence`, and release/VM docs describe how to create
  `loopwire-vm-evidence-<tag>.tar.gz` after operator-run VM evidence exists.
- 2026-07-04 VM evidence packager validation: codebase-memory MCP `search_graph` located the existing VM evidence and
  final proof surfaces before implementation. `bash -n scripts/package-vm-evidence.sh scripts/verify-scripts.sh
  scripts/verify-docs.sh`, a packager dry-run, `pnpm verify:docs`, and `pnpm verify:scripts` passed. The script
  verifier packages a fake strict single-target evidence archive and checks `--all`/`--target` conflict rejection.
  No VM was launched, no public release was created, no release asset was uploaded, and no support matrix row was
  promoted.
- 2026-07-04 docs deployment manifest evidence: `scripts/deploy-docs-bunny.sh` now accepts
  `--deployment-manifest` / `LOOPWIRE_DOCS_DEPLOYMENT_MANIFEST` and writes a non-secret
  `loopwire.docs-deployment.v1` JSON manifest with storage endpoint, zone, remote prefix, dry-run/live mode, file
  count, required files, upload paths, and SHA-256 checksums. `.github/workflows/deploy-docs.yml` requests that
  manifest during Bunny uploads and publishes it as the `loopwire-docs-deployment` artifact.
- 2026-07-04 docs deployment manifest validation: codebase-memory MCP `search_graph` located existing deploy,
  live-docs, release-evidence, and workflow surfaces before implementation. `bash -n scripts/deploy-docs-bunny.sh
  scripts/verify-scripts.sh scripts/verify-docs.sh scripts/verify-github-workflows.sh`, `pnpm verify:workflows`,
  `pnpm verify:docs`, and `pnpm verify:scripts` passed. A real VitePress build plus Bunny dry-run wrote a
  `loopwire.docs-deployment.v1` manifest with 68 files and `install.sh`. No Bunny secret was written, no Bunny upload
  was attempted, and no live docs smoke was performed.
- 2026-07-04 docs deployment manifest verifier: `scripts/verify-docs-deployment-manifest.mjs` and
  `pnpm verify:docs-deployment` now verify deployment manifests against the current built docs dist before workflow
  artifact upload. The verifier checks schema, timestamp, storage bindings, dry-run/live mode when requested, required
  files, exact dist inventory, remote-prefix mapping, SHA-256 checksums, path safety, and secret-like manifest keys.
- 2026-07-04 docs deployment manifest verifier validation: codebase-memory MCP `search_graph` located deployment
  manifest, workflow, docs-live, and release-evidence surfaces before implementation. `node --check
  scripts/verify-docs-deployment-manifest.mjs`, `bash -n scripts/verify-scripts.sh scripts/verify-docs.sh
  scripts/verify-github-workflows.sh`, `pnpm verify:workflows`, `pnpm verify:docs`, and `pnpm verify:scripts` passed.
  Real VitePress build dry-run smokes verified 68-file manifests for both `preview` and empty remote prefixes. No
  Bunny secret was written, no Bunny upload was attempted, and no live docs smoke was performed.
- 2026-07-04 release readiness docs deployment guard: `scripts/verify-release-readiness.sh` now fails preflight if
  `scripts/verify-docs-deployment-manifest.mjs` is missing or unparsable, if `package.json` does not expose
  `pnpm verify:docs-deployment`, or if `.github/workflows/deploy-docs.yml` does not run the manifest verifier before
  artifact upload.
- 2026-07-04 release readiness docs deployment guard validation: codebase-memory MCP `search_graph` located release
  readiness and docs deployment verifier surfaces before implementation. `bash -n scripts/verify-release-readiness.sh
  scripts/verify-scripts.sh scripts/verify-docs.sh`, `pnpm verify:docs`, `pnpm verify:workflows`,
  `pnpm verify:scripts`, `pnpm verify:requirements`, and offline `pnpm verify:release-readiness -- --repo
  sandwichfarm/loopwire --tag v0.1.0 --public-key packaging/release-signing-public.pem --skip-gh --skip-tag
  --skip-clean-git --allow-candidate-notes` passed. No GitHub release, Bunny upload, secret write, live docs smoke,
  or VM run was performed.
- 2026-07-04 release readiness final proof guard: `scripts/verify-release-readiness.sh` now fails preflight if the
  final release proof verifier, VM evidence packager, `pnpm verify:final-release`, `pnpm vm:package-evidence`, or
  `.github/workflows/final-release-proof.yml` wiring disappears before the release handoff.
- 2026-07-04 release readiness final proof guard validation: codebase-memory MCP `index_status` reported
  `home-sandwich-Develop-loopwire` ready, and `search_graph` located the final release proof and VM evidence packager
  surfaces. `bash -n scripts/verify-release-readiness.sh scripts/verify-scripts.sh scripts/verify-docs.sh` and offline
  `pnpm verify:release-readiness -- --repo sandwichfarm/loopwire --tag v0.1.0 --public-key
  packaging/release-signing-public.pem --skip-gh --skip-tag --skip-clean-git --allow-candidate-notes` passed.
- 2026-07-04 release readiness final proof guard full validation: `pnpm verify:docs`, `pnpm verify:workflows`,
  `pnpm verify:scripts`, `pnpm verify:requirements`, full `pnpm check`, `pnpm detect:audio`, `git diff --check`,
  touched-file added-line scan, `gsd-sdk query roadmap.analyze --format json`, and
  `gsd-sdk query init.phase-op 12 --format json` passed. Codebase-memory MCP fast reindex wrote a persistent artifact
  and `index_status` reported ready with 2,534 nodes and 5,387 edges. `pnpm detect:audio` reported PipeWire,
  PulseAudio compatibility, and ALSA available; JACK remains unavailable because `jack_lsp` is missing.
- 2026-07-04 final proof command-plan artifact: `scripts/verify-final-release-proof.sh --dry-run` now accepts
  `--plan-output FILE` and writes the same published-release, live-docs, strict release-evidence, all-target VM
  evidence, support-matrix, and docs-contract command plan that it prints to stdout. The option is rejected outside
  dry-run mode so it cannot look like proof from a real final release run.
- 2026-07-04 final proof command-plan validation: codebase-memory MCP `index_status` reported ready and graph search
  located the final proof, VM evidence, support matrix, Bunny docs, and secret setup surfaces before implementation.
  `bash -n scripts/verify-final-release-proof.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, direct
  `scripts/verify-final-release-proof.sh --dry-run --plan-output <tmp>` smoke, `pnpm verify:docs`, and
  `pnpm verify:scripts` passed.
- 2026-07-04 final proof command-plan full validation: offline `pnpm verify:release-readiness -- --repo
  sandwichfarm/loopwire --tag v0.1.0 --public-key packaging/release-signing-public.pem --skip-gh --skip-tag
  --skip-clean-git --allow-candidate-notes`, `pnpm verify:workflows`, `pnpm verify:requirements`, full `pnpm check`,
  `pnpm detect:audio`, `git diff --check`, touched-file added-line scan, `gsd-sdk query roadmap.analyze --format
  json`, and `gsd-sdk query init.phase-op 12 --format json` passed. Codebase-memory MCP fast reindex wrote a
  persistent artifact and `index_status` reported ready with 2,536 nodes and 5,389 edges. `pnpm detect:audio`
  reported PipeWire, PulseAudio compatibility, and ALSA available; JACK remains unavailable because `jack_lsp` is
  missing.
- 2026-07-04 GitHub secret check guidance: `scripts/setup-github-secrets.sh --check` now prints placeholder-only
  next steps when required Bunny or release signing secrets are missing, while still preserving the underlying
  `gh secret list` failure when GitHub secret names cannot be read. When `BUNNY_PULL_ZONE_HOSTNAME` is absent, the
  check explains that docs deployment can upload to Bunny.net but will skip post-upload live docs smoke.
- 2026-07-04 GitHub secret check guidance validation: codebase-memory MCP `index_status` reported ready and graph
  search located the setup helper, release readiness, Bunny deploy, workflow, and docs-live surfaces before
  implementation. `bash -n scripts/setup-github-secrets.sh scripts/verify-scripts.sh scripts/verify-docs.sh`,
  `pnpm verify:docs`, and `pnpm verify:scripts` passed, including fake `gh secret list` cases for all-required-present,
  missing-required, and API failure.
- 2026-07-04 GitHub secret check guidance full validation: offline `pnpm verify:release-readiness -- --repo
  sandwichfarm/loopwire --tag v0.1.0 --public-key packaging/release-signing-public.pem --skip-gh --skip-tag
  --skip-clean-git --allow-candidate-notes`, `pnpm verify:workflows`, `pnpm verify:requirements`, full `pnpm check`,
  `pnpm detect:audio`, `git diff --check`, touched-file added-line scan, `gsd-sdk query roadmap.analyze --format
  json`, and `gsd-sdk query init.phase-op 12 --format json` passed. Codebase-memory MCP fast reindex wrote a
  persistent artifact and `index_status` reported ready with 2,536 nodes and 5,390 edges. `pnpm detect:audio`
  reported PipeWire, PulseAudio compatibility, and ALSA available; JACK remains unavailable because `jack_lsp` is
  missing.
- 2026-07-04 packaged restore launcher preflight: desktop restore-on-boot status now preflights packaged or explicitly
  configured background launchers with `loopwire --background --help` before reporting the action available or writing
  a user systemd unit. Raw tarball installs with a present launcher but missing Node.js now surface a blocked status
  instead of installing a unit that exits 127.
- 2026-07-04 packaged restore launcher preflight focused validation: codebase-memory MCP `index_status` reported
  `home-sandwich-Develop-loopwire` ready with 2,622 nodes and 5,471 edges before implementation, and graph search
  located the Tauri startup helpers and tests. `cargo test --manifest-path apps/desktop/src-tauri/Cargo.toml`,
  `pnpm verify:tauri`, `pnpm verify:docs`, and `git diff --check` passed. No public release, VM launch, Bunny
  deployment, secret write, tag push, host audio mutation, or support-matrix promotion was performed.
- 2026-07-04 packaged restore launcher preflight full validation: full `pnpm check` passed after the change, including
  requirements verification, scripts/workflows/runtime/Tauri verification, install and release-artifact smokes,
  packaging metadata smoke, VM target/cloud-init validation, docs contract checks, typechecks, unit tests, and docs,
  core, audio-host, and desktop builds.
- 2026-07-04 final-release VM matrix runbook handoff: generated VM evidence runbooks now include the strict
  final-release `pnpm vm:collect-matrix` command with published-release smoke, the checked-in release public key, and
  `--require-all-targets` for full-matrix runs. This keeps operator handoffs aligned with final proof requirements
  instead of collecting source-checkout-only evidence by accident.
- 2026-07-04 final-release VM matrix runbook validation: codebase-memory MCP `index_status` reported
  `home-sandwich-Develop-loopwire` ready before implementation, and graph search located the VM matrix runbook,
  collector, and verification surfaces. `bash -n scripts/vm-matrix.sh scripts/verify-scripts.sh
  scripts/verify-docs.sh`, focused `scripts/vm-matrix.sh render-runbook` smokes, `pnpm verify:scripts`,
  `pnpm verify:docs`, and `git diff --check` passed. No VM launch, public release, Bunny deployment, secret write,
  tag push, host audio mutation, or support-matrix promotion was performed.
- 2026-07-04 final-release VM matrix runbook full validation: full `pnpm check` passed after the change, including
  requirements verification, scripts/workflows/runtime/Tauri verification, install and release-artifact smokes,
  packaging metadata smoke, VM target/cloud-init validation, docs contract checks, typechecks, unit tests, and docs,
  core, audio-host, and desktop builds.
- 2026-07-04 VM evidence signed-release asset preparation: `scripts/prepare-vm-evidence-release-asset.sh` and
  `pnpm vm:prepare-release-evidence` now package verified VM evidence into `dist/release`, regenerate and sign the
  release `SHA256SUMS`, verify `loopwire-vm-evidence-<tag>.tar.gz` with the signed-checksum verifier, and print the
  exact `gh release upload --clobber` command for the archive plus refreshed manifest files. Final proof dry-runs now
  execute that helper in dry-run mode so handoff plans include packaging, signed manifest refresh, and upload steps
  instead of a raw tarball upload.
- 2026-07-04 VM evidence signed-release asset validation: codebase-memory MCP `index_status` reported
  `home-sandwich-Develop-loopwire` ready before implementation, and graph search located the final proof, release
  checksum, VM evidence, and release docs surfaces. `bash -n scripts/prepare-vm-evidence-release-asset.sh
  scripts/verify-final-release-proof.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, direct helper and final
  proof dry-run smokes, `pnpm verify:scripts`, and `pnpm verify:docs` passed. No VM launch, public release, Bunny
  deployment, secret write, tag push, host audio mutation, or support-matrix promotion was performed.
- 2026-07-04 VM evidence signed-release asset full validation: full `pnpm check` passed after the change, including
  requirements verification, scripts/workflows/runtime/Tauri verification, install and release-artifact smokes,
  packaging metadata smoke, VM target/cloud-init validation, docs contract checks, typechecks, unit tests, and docs,
  core, audio-host, and desktop builds.
- 2026-07-04 publishable release notes and readiness guard: `apps/docs/docs/release-notes/0.1.0.md` is now framed as
  publishable v0.1.0 release notes instead of candidate notes, and `scripts/verify-release-readiness.sh` now requires
  the VM signed-release asset helper plus `pnpm vm:prepare-release-evidence` wiring before a release can be considered
  ready.
- 2026-07-04 publishable release notes validation: live GitHub checks showed no `v*` tags on `origin`, no
  `v0.1.0` release, and only `LOOPWIRE_RELEASE_PRIVATE_KEY` configured as a repository secret. `pnpm
  verify:release-readiness -- --repo sandwichfarm/loopwire --tag v0.1.0 --public-key
  packaging/release-signing-public.pem --skip-gh --skip-tag --skip-clean-git` now passes without
  `--allow-candidate-notes`, and `pnpm verify:scripts` plus `pnpm verify:docs` passed. No release tag, public release,
  Bunny deployment, secret write, VM launch, host audio mutation, or support-matrix promotion was performed.
- 2026-07-04 publishable release notes full validation: full `pnpm check` passed after the change, including
  requirements verification, scripts/workflows/runtime/Tauri verification, install and release-artifact smokes,
  packaging metadata smoke, VM target/cloud-init validation, docs contract checks, typechecks, unit tests, and docs,
  core, audio-host, and desktop builds.
- 2026-07-04 scoped GitHub secret guidance: `scripts/setup-github-secrets.sh --check` now prints only the next-step
  command for the missing secret class. The current live repository has `LOOPWIRE_RELEASE_PRIVATE_KEY` but lacks
  `BUNNY_STORAGE_ZONE` and `BUNNY_ACCESS_KEY`, so the check now prints only the Bunny.net setup command instead of
  also telling the operator to reset the release signing key.
- 2026-07-04 scoped GitHub secret validation: live `setup-github-secrets.sh --check` against `sandwichfarm/loopwire`
  reported missing Bunny secrets, present `LOOPWIRE_RELEASE_PRIVATE_KEY`, and only the Bunny setup next step.
  `bash -n scripts/setup-github-secrets.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, `pnpm verify:scripts`,
  and `pnpm verify:docs` passed. No secret write, Bunny deployment, tag push, public release, VM launch, host audio
  mutation, or support-matrix promotion was performed.
- 2026-07-04 scoped GitHub secret full validation and Tauri test stability: full `pnpm check` initially exposed a
  parallel Rust test race in the packaged background launcher preflight tests. The Tauri startup tests now use temp
  directories with process id, atomic counter, and timestamp suffixes instead of timestamp-only names. `pnpm
  verify:tauri` and full `pnpm check` then passed, including requirements verification, scripts/workflows/runtime/Tauri
  verification, install and release-artifact smokes, packaging metadata smoke, VM target/cloud-init validation, docs
  contract checks, typechecks, unit tests, and docs, core, audio-host, and desktop builds.
- 2026-07-04 release readiness next-step handoff: `scripts/verify-release-readiness.sh` now emits value-safe next-step
  commands for the currently missing blocker classes before failing. The live preflight for `sandwichfarm/loopwire`
  now prints the Bunny secret setup command and the guarded `git tag -a v0.1.0` / `git push origin v0.1.0` commands,
  explicitly after required secrets are configured and readiness passes.
- 2026-07-04 release readiness next-step validation: codebase-memory MCP `index_status` reported ready and graph search
  located the readiness, tag, Bunny deploy, and final proof surfaces before implementation. `bash -n
  scripts/verify-release-readiness.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, live `pnpm
  verify:release-readiness -- --repo sandwichfarm/loopwire --tag v0.1.0 --public-key
  packaging/release-signing-public.pem` failure-surface review, `pnpm verify:scripts`, and `pnpm verify:docs` passed.
  No secret write, Bunny deployment, tag push, public release, VM launch, host audio mutation, or support-matrix
  promotion was performed.
- 2026-07-04 release readiness next-step full validation: full `pnpm check` passed after the change, including
  requirements verification, scripts/workflows/runtime/Tauri verification, install and release-artifact smokes,
  packaging metadata smoke, VM target/cloud-init validation, docs contract checks, typechecks, unit tests, and docs,
  core, audio-host, and desktop builds.
- 2026-07-04 final proof published-source workflow guard: `scripts/verify-github-workflows.sh` now fails if the manual
  final release proof workflow's composed `scripts/verify-final-release-proof.sh` step reintroduces `--release-dir`,
  keeping final proof tied to downloaded GitHub Release assets, signed checksums, live docs, and operator-collected VM
  evidence instead of local staging directories.
- 2026-07-04 final proof published-source workflow guard validation: codebase-memory MCP `index_status` reported
  `home-sandwich-Develop-loopwire` ready, and graph search located the workflow verifier symbol before implementation.
  `bash -n scripts/verify-github-workflows.sh scripts/verify-docs.sh`, `pnpm verify:workflows`, `pnpm verify:docs`,
  `pnpm verify:scripts`, and full `pnpm check` passed. No release tag, public release, Bunny deployment, secret write,
  VM launch, host audio mutation, or support-matrix promotion was performed.
- 2026-07-04 VM screenshot evidence hardening: `scripts/verify-vm-evidence.sh` now parses VM `screenshot.png` files as
  real non-interlaced PNGs with IHDR, IDAT, IEND, decodable image data, and desktop-sized dimensions. Header-only or
  truncated PNG placeholders can no longer satisfy Phase 12 screenshot evidence.
- 2026-07-04 VM screenshot evidence hardening validation: codebase-memory MCP `index_status` reported
  `home-sandwich-Develop-loopwire` ready, and graph search located the VM evidence verifier and screenshot collection
  surfaces before implementation. `bash -n scripts/verify-vm-evidence.sh scripts/verify-scripts.sh
  scripts/verify-docs.sh`, `pnpm verify:scripts`, `pnpm verify:docs`, and full `pnpm check` passed. No VM launch,
  public release, Bunny deployment, secret write, tag push, host audio mutation, or support-matrix promotion was
  performed.
- 2026-07-04 VM screenshot CRC evidence hardening: `scripts/verify-vm-evidence.sh` now validates every PNG chunk CRC
  before accepting VM screenshot evidence, and rejects corrupt IDAT CRCs even when the image dimensions and zlib stream
  otherwise look plausible.
- 2026-07-04 VM screenshot CRC evidence hardening validation: codebase-memory MCP `index_status` reported
  `home-sandwich-Develop-loopwire` ready, and graph search located the VM evidence verifier and PNG test fixture.
  `bash -n scripts/verify-vm-evidence.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, `pnpm verify:scripts`,
  `pnpm verify:docs`, and full `pnpm check` passed. No VM launch, public release, Bunny deployment, secret write, tag
  push, host audio mutation, or support-matrix promotion was performed.
- 2026-07-04 VM GitHub-source collection strictness: direct guest, SSH, and matrix VM evidence collectors now accept
  and forward `--require-github-release-source`, reject attempts to combine that final-proof mode with guest-visible
  local release directories, and include it in generated final-release runbooks.
- 2026-07-04 VM GitHub-source collection strictness validation: codebase-memory MCP `index_status` reported
  `home-sandwich-Develop-loopwire` ready, and graph search located the VM evidence collection, SSH forwarding,
  release-evidence validation, and runbook surfaces before implementation. `bash -n scripts/collect-vm-evidence.sh
  scripts/collect-vm-evidence-ssh.sh scripts/collect-vm-matrix-evidence.sh scripts/vm-matrix.sh
  scripts/verify-scripts.sh scripts/verify-docs.sh`, `pnpm verify:docs`, `pnpm verify:scripts`, and full `pnpm check`
  passed. No VM launch, public release, Bunny deployment, secret write, tag push, host audio mutation, or
  support-matrix promotion was performed.
