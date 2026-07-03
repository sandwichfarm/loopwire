---
gsd_state_version: 1.0
milestone: v0.2
milestone_name: Production Audio Routing
status: In Progress
last_updated: "2026-07-04T01:52:41+02:00"
last_activity: 2026-07-04 - VM evidence collectors reject invalid handoff ports
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
Last activity: 2026-07-04 - VM evidence collectors now validate SSH and desktop smoke ports before starting SSH, Vite,
or guest collection commands. Release publication and real VM proof remain gated until the real signing key is
generated, the public key is committed, a tag exists, GitHub secrets are configured, and operator-run VM evidence
exists.

## Blockers / Concerns

- Full audio graph mutation is intentionally incomplete. The PulseAudio compatibility adapter covers Loopwire null
  sinks, running stream enumeration, matched stream moves, stream-level volume/mute, monitor loopbacks, and physical
  monitor sink targets. Native PipeWire covers Loopwire-owned virtual output and monitor sinks, existing route links,
  route mute by disconnecting configured links, physical monitor sink links, and rollback/unload cleanup for selected
  virtual nodes. Native JACK covers read-only port enumeration plus existing route links, route mute by disconnecting
  configured connections, and physical monitor sink links when route endpoints have host device names. Backend DSP,
  JACK virtual ports, and graph-edge gain implementation remain planned.

- Install artifacts are not published yet. Installer and package docs must not claim release availability before artifacts exist.
- A real project release public key has not been generated or committed yet. `pnpm release:prepare-key` now provides
  the guarded ceremony, but do not claim public signed installer readiness until `packaging/release-signing-public.pem`
  exists and a tagged release workflow has passed.

- Nix package metadata is smoke-tested structurally, but Nix build proof still needs a Nix-enabled host or VM target.
- JACK virtual ports, backend DSP/graph-edge gain, and published release proof remain the major product gap for a
  fully functional Loopback-class app.
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
