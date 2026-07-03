# Phase 12 Verification: Published Release and VM Proof

**Date:** 2026-07-04
**Status:** Partial, decision-gated

## Evidence Passed

- `node scripts/collect-release-evidence.mjs --output-dir "$tmp_dir" --profile quick` passed and produced
  `release-evidence.json`, `verify-scripts.log`, `verify-vm.log`, `verify-docs.log`, `audio-detect.json`, and
  `tauri-cargo-check.log`.
- `pnpm collect:evidence -- --output-dir "$tmp_dir" --profile quick` passed, proving the documented package-script
  invocation.
- `scripts/verify-release-readiness.sh` offline smoke passed with temporary signing material and release notes.
- Real release readiness preflight failed closed with missing versioned notes, release public key, `v0.1.0` tag, and
  required GitHub secrets.
- `scripts/verify-vm-evidence.sh` passed against a temporary target-scoped evidence bundle.
- `scripts/collect-vm-evidence.sh` local flow smoke passed for `arch-hyprland-pipewire`, writing
  `pnpm-check.log`, `detect-audio.json`, `ct-host-check.log`, `autostart.log`, `screenshot.png`, `notes.md`,
  `audio-host-build.log`, `command-results.tsv`, and `vm-evidence-verify.log`. The smoke used a generated PNG test
  image and is not support-matrix VM evidence.
- `scripts/verify-vm-evidence.sh` accepted the local collector smoke bundle and rejected a text `screenshot.png` as
  non-PNG.
- `scripts/vm-matrix.sh plan --target arch-hyprland-pipewire` includes the guest collector command and target-scoped
  evidence paths.
- `scripts/vm-matrix.sh render-cloud-init --target arch-hyprland-pipewire` now writes guest commands that clone
  `https://github.com/sandwichfarm/loopwire.git` and run the guest collector.
- `pnpm verify:support-matrix` passed, confirming the support matrix mirrors all seven `vm/targets.tsv` targets and
  currently has zero evidence-backed rows.
- `scripts/verify-support-matrix.mjs --evidence-root "$tmp_dir"` rejected a synthetic verified evidence bundle while
  the row still said `Manual VM`, proving docs must be promoted to `Verified` after real evidence arrives.
- The support-matrix guard caught and fixed a docs drift: `debian-xfce-pulseaudio` now matches the target metadata
  audio value `PulseAudio`.
- `pnpm verify:workflows` passed, proving the CI, continuous diagnostics, docs deployment, release, and VM matrix
  workflows still contain the expected release and validation commands.
- `pnpm check` now runs the workflow contract before runtime, typecheck, tests, and builds.
- Workflow YAML parsed successfully with Ruby `YAML.load_file`.
- Stale placeholder repository references were removed from installer defaults, AUR metadata, and release docs; search
  found no remaining `github.com/loopwire/loopwire`, `loopwire/loopwire`, or `--repo loopwire` references.
- `pnpm verify:install` and `pnpm verify:packaging` passed after changing install/package defaults to
  `sandwichfarm/loopwire`.
- `bash scripts/setup-github-secrets.sh --print-required` passed and lists required release/docs secrets without
  requiring GitHub access.
- `bash scripts/setup-github-secrets.sh --repo sandwichfarm/loopwire --dry-run ...` passed and printed only secret names
  that would be set; no GitHub secrets were changed.
- `bash scripts/setup-github-secrets.sh --repo sandwichfarm/loopwire --check` performed a read-only live secret-name
  audit and failed closed because `BUNNY_STORAGE_ZONE`, `BUNNY_ACCESS_KEY`, and `LOOPWIRE_RELEASE_PRIVATE_KEY` are not
  configured. Optional `BUNNY_PULL_ZONE_HOSTNAME` is also unset.
- `pnpm verify:scripts` passed.
- `pnpm verify:docs` passed.
- `pnpm check` passed after release-readiness updates.
- `pnpm verify:packaging` passed after the Nix release URL moved to `sandwichfarm/loopwire`.
- `pnpm detect:audio` passed and reported PipeWire and PulseAudio compatibility available, ALSA available, and JACK
  unavailable because `jack_lsp` is missing.
- Desktop startup backend detection now uses the browser-safe `@loopwire/audio-host/detectors` export and the
  allowlisted Tauri command bridge for `pw-cli`, `wpctl`, `pactl`, `jack_lsp`, and `aplay`.
- First-run state no longer hardcodes PipeWire as a persisted choice; multiple detected backends enter prompt mode and
  live apply refuses to arm until a backend is selected.
- Browser preview keeps packaged fallback candidates and shows that host detection requires the desktop shell.
- `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml` passed.
- Playwright desktop and mobile screenshot smoke passed for the new backend probe status strip with no text overlap or
  horizontal overflow.
- `scripts/verify-vm-evidence.sh` now requires `command-results.tsv` and `audio-host-build.log`, verifies the required
  guest commands exited 0, and checks ledger rows point to the expected non-empty log files.
- `pnpm verify:scripts` includes a deterministic VM evidence smoke bundle and a negative case proving a failed
  `detect-audio` ledger row is rejected.
- `scripts/collect-vm-evidence-ssh.sh` now provides a dry-run-first host handoff for reachable guests: run the guest
  collector over SSH, copy `.vm/evidence/<target>` back with `scp`, then verify locally with
  `scripts/verify-vm-evidence.sh`.
- `pnpm vm:collect-ssh -- --target arch-hyprland-pipewire --host 127.0.0.1 --port 2222` passed as a dry-run package
  script invocation and printed the SSH, SCP, and verifier commands without touching the guest.
- `bash scripts/verify-scripts.sh` passed with syntax/help checks, dry-run output checks, pnpm `--` separator coverage,
  and a fake SSH/SCP execution smoke that copied a verified evidence bundle and ran the real VM evidence verifier.
- `scripts/vm-matrix.sh doctor --target arch-hyprland-pipewire` now reports the selected target context, checks
  `qemu-system-x86_64`, prints `host-install-hint`, and emits exact guest and host evidence handoff commands.
- `pnpm vm:doctor -- --target arch-hyprland-pipewire` now parses the pnpm `--` separator and fails closed on this host
  because `qemu-system-x86_64` and `qemu-img` are missing. KVM is available and SSH is present.
- `bash scripts/collect-vm-evidence.sh --target arch-hyprland-pipewire --output-dir "$tmp_dir" --screenshot-command
  <generated-png>` passed against the hardened verifier. This is local verifier compatibility proof, not support-matrix
  VM evidence.
- `pnpm check`, `pnpm verify:docs`, `pnpm verify:vm`, `pnpm verify:support-matrix`, and Rust `cargo check` passed after
  the VM evidence hardening.
- `bash scripts/setup-github-secrets.sh --repo sandwichfarm/loopwire --check` still reports missing
  `BUNNY_STORAGE_ZONE`, `BUNNY_ACCESS_KEY`, and `LOOPWIRE_RELEASE_PRIVATE_KEY`; optional `BUNNY_PULL_ZONE_HOSTNAME` is
  unset.
- Code search found no remaining `github.com/loopwire/loopwire` links.
- `gsd-sdk query init.milestone-op` and `gsd-sdk query roadmap.analyze` passed, confirming Phase 12 remains planned and
  the milestone remains 80% complete.
- Touched-file line-length check and `git diff --check` passed.
- `pnpm check`, `pnpm verify:vm`, `pnpm verify:docs`, and `pnpm verify:workflows` passed after adding the SSH evidence
  collector.
- `shellcheck` is not installed on this host, so shell lint beyond `bash -n` and execution smokes was skipped.
- `apps/docs/docs/release-notes/0.1.0.md` now exists as a release-candidate page with explicit non-publication
  disclaimers, and the VitePress sidebar links it.
- `pnpm verify:docs` now requires the `0.1.0` release-candidate page, sidebar link, and disclaimer text.
- `bash scripts/verify-release-readiness.sh --repo sandwichfarm/loopwire --tag v0.1.0` now reports
  `ok: versioned release notes` before failing closed on the remaining release blockers.
- `pnpm --filter @loopwire/docs docs:build` and `pnpm check` passed after adding the candidate notes page.
- The docs homepage now presents the actual product screenshot as the first-viewport signal, plus source install,
  `v0.1.0` candidate status, three proof cards, and a release ceremony band.
- `pnpm verify:docs` now asserts the homepage keeps the desktop-grade routing offer, current source install,
  candidate status, and release ceremony copy.
- Playwright desktop/mobile validation against `http://127.0.0.1:4173` passed, confirming screenshot rendering,
  install command visibility, three proof cards, next-section visibility, and zero horizontal overflow.
- `pnpm --filter @loopwire/docs docs:build`, `pnpm check`, touched-file line-length check, and `git diff --check`
  passed after the homepage UX pass.
- `bash scripts/verify-scripts.sh`, `bash scripts/vm-matrix.sh validate`, `bash scripts/verify-docs.sh`, `pnpm check`,
  `pnpm detect:audio`, Rust `cargo check`, `pnpm verify:vm && pnpm verify:docs`, touched-file line-length check,
  `git diff --check`, and docs preview HTTP 200 passed after the VM target preflight update.
- Native PipeWire and JACK route mute tests first failed because muted routes were ignored and verification passed stale
  connected edges. After implementation, `pnpm --filter @loopwire/audio-host test` passed with 60 tests and audio-host
  typecheck passed.
- `pnpm detect:audio` now reports native PipeWire `supportsPerEdgeMute: true`, keeps `supportsPerEdgeGain: false`, and
  lists `per-edge gain controls` as the remaining graph-control gap.
- `pnpm verify:docs` passed after docs and release notes were updated to say native PipeWire/JACK route mute disconnects
  configured existing links/connections while virtual nodes and per-edge gain remain planned.
- `pnpm check`, Rust `cargo check`, `pnpm verify:vm`, touched-file line-length check, `git diff --check`, and docs
  preview HTTP 200 passed after the native route-mute update.
- The Tauri desktop shell now mirrors serialized state to
  `${XDG_CONFIG_HOME:-$HOME/.config}/loopwire/state.json` through `read_state` and `write_state` commands, so source
  startup restore does not depend on browser-local storage.
- `scripts/restore-background.mjs` can restore the persisted state without opening the UI, select the requested or
  persisted backend, and run the shared startup verification transaction in dry-run preview mode or explicit live mode.
- `scripts/manage-autostart.sh` can render a user-scoped systemd unit for a source checkout with `--source-dir`,
  `--state-file`, and `--restore-mode`, while preserving the existing GUI XDG autostart path.
- `pnpm verify:autostart` first exposed a literal `grep` bug for needles beginning with `--`; after fixing
  `assert_contains`, it passed and exercised source-checkout systemd rendering plus `pnpm restore:background`.
- `cargo test --manifest-path apps/desktop/src-tauri/Cargo.toml` first exposed a `config_home` result type mismatch;
  after fixing it, the three Rust tests passed.
- `pnpm verify:docs` first exposed the same literal `grep` bug for `--source-dir`; after fixing it, docs verification
  passed.
- `node --check scripts/restore-background.mjs` and
  `bash -n scripts/manage-autostart.sh scripts/verify-autostart.sh scripts/verify-scripts.sh scripts/verify-docs.sh`
  passed.
- `pnpm check` passed after the source background restore changes, including script, workflow, runtime, typecheck, test,
  docs build, and desktop build gates.
- `pnpm detect:audio` passed and reported PipeWire and PulseAudio compatibility available, ALSA available, and JACK
  unavailable because `jack_lsp` is missing.
- `pnpm verify:scripts`, `pnpm verify:vm`, `pnpm verify:docs`,
  `cargo fmt --manifest-path apps/desktop/src-tauri/Cargo.toml --check`,
  `cargo test --manifest-path apps/desktop/src-tauri/Cargo.toml`, `git diff --check`, corrected touched-file
  trailing-whitespace and line-length checks, docs preview HTTP 200, and GSD milestone/roadmap queries passed.
- Codebase-memory MCP `index_repository` retry failed with `Transport closed`, so the code graph could not be refreshed
  for this pass.
- `scripts/vm-matrix.sh host-plan` now prints target-specific host tools, Arch/Debian/Ubuntu/Fedora/Nix install hints,
  operator-owned image policy, render commands, dry-run launch commands, and SSH evidence handoff commands without
  installing packages, downloading images, or launching VMs.
- `scripts/vm-matrix.sh render-cloud-init --all` now renders `user-data`, `meta-data`, and `guest-commands.sh` for all
  seven VM targets in one command.
- `scripts/vm-matrix.sh launch` now chooses the QEMU system binary from the target architecture instead of hardcoding
  x86_64.
- `bash -n scripts/vm-matrix.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, `bash scripts/vm-matrix.sh validate`,
  `bash scripts/vm-matrix.sh host-plan --target fedora-sway-pipewire`, direct all-target cloud-init rendering,
  `pnpm vm:host-plan -- --target fedora-sway-pipewire`, and
  `pnpm vm:render-cloud-init -- --all --output "$tmp_dir/cloud-init"` passed.
- `pnpm verify:scripts` passed with positive assertions for `host-plan`, positive assertions for all-target cloud-init
  rendering, and a negative case rejecting `render-cloud-init --all --target ...`.
- `pnpm check`, `pnpm detect:audio`, `pnpm verify:vm`, `pnpm verify:docs`,
  `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml`, touched-file trailing-whitespace and line-length
  checks, `git diff --check`, and GSD milestone/roadmap queries passed.
- `pnpm vm:doctor -- --target arch-hyprland-pipewire` still fails closed on this host because `qemu-system-x86_64` and
  `qemu-img` are missing; KVM is available, SSH is present, and the command prints the Arch install hint plus guest and
  host evidence handoff commands. No package installation, image download, VM launch, or support-matrix promotion was
  performed.
- Codebase-memory MCP `index_repository` retry failed with `Transport closed`, so the code graph could not be refreshed
  for this pass.
- PulseAudio compatibility route verification now fails when a configured route has no matching live sink input, so an
  absent app stream cannot be reported as verified.
- The new regression test first failed because `verify` returned `ok: true` and `Verified 1 Loopwire sink(s)` when both
  configured routes had no matching live stream.
- After implementation, `pnpm --filter @loopwire/audio-host test` passed with 61 tests and
  `pnpm --filter @loopwire/audio-host typecheck` passed.
- `pnpm verify:docs`, `bash -n scripts/verify-docs.sh`, `pnpm check`, `pnpm detect:audio`,
  `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml`, `pnpm verify:vm`, touched-file
  trailing-whitespace and line-length checks, `git diff --check`, docs preview HTTP 200, and GSD milestone/roadmap
  queries passed after documenting the stricter verification behavior.
- Codebase-memory MCP `index_repository` retry failed with `Transport closed`, so the code graph could not be refreshed
  for this pass.
- PulseAudio compatibility startup verification can now report missing matching app streams as pending while preserving
  hard failure for normal switch verification.
- The new pending-mode regression test first failed because the adapter still returned
  `Missing matching PulseAudio stream(s)` and `ok: false` when constructed with `missingStreamVerification: "pending"`.
- After implementation, `pnpm --filter @loopwire/audio-host test` passed with 62 tests and
  `pnpm --filter @loopwire/audio-host typecheck` passed.
- `pnpm --filter @loopwire/desktop typecheck` passed with zero Svelte diagnostics after the desktop host adapter was
  wired to runtime plan reasons.
- `node --check scripts/restore-background.mjs` passed after source-checkout background restore was wired to pending
  PulseAudio startup verification.
- `pnpm verify:docs` passed after backend, start-on-boot, troubleshooting, architecture, and release-note docs were
  updated with pending-stream wording.
- `pnpm check`, `pnpm detect:audio`, `pnpm verify:vm`, `cargo check --manifest-path
  apps/desktop/src-tauri/Cargo.toml`, `git diff --check`, touched-file trailing-whitespace and line-length checks,
  docs preview HTTP 200, and GSD milestone/roadmap queries passed after the pending startup verification update.
- Codebase-memory MCP `index_repository` retry failed with `Transport closed`, so the code graph could not be refreshed
  for this pass.
- `scripts/verify-published-release.sh` now supports `--release-dir DIR` for CI smoke coverage without GitHub access.
- The verifier now downloads all GitHub release assets in live mode, verifies `SHA256SUMS.sig`, checks every
  `SHA256SUMS` entry, requires a `loopwire-linux-*.tar.gz` asset, installs the host tarball from that release
  directory, and runs the installed binary.
- `bash scripts/verify-scripts.sh` passed after adding a signed fake release-directory smoke for
  `verify-published-release.sh --release-dir`, an installed-binary output check, and a tampered-tarball rejection case.
- `pnpm verify:docs` passed after documenting the local signed release-directory verifier path and release-note entry.
- Codebase-memory MCP `index_repository` retry failed with `Transport closed`, so the code graph could not be refreshed
  for this pass.
- Debian and Ubuntu cloud-init guest commands now install pinned `pnpm@11.3.0` after apt installs `nodejs` and `npm`,
  before the shared `pnpm install --frozen-lockfile` validation command runs.
- `bash -n scripts/vm-matrix.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, `bash scripts/vm-matrix.sh validate`,
  a rendered Ubuntu/Debian cloud-init grep smoke for `sudo npm install -g pnpm@11.3.0`, and `pnpm verify:docs` passed.
- `scripts/verify-scripts.sh` now asserts the rendered Ubuntu and Debian cloud-init guest commands contain the pinned
  pnpm bootstrap.
- `pnpm check`, `pnpm detect:audio`, `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml`,
  `pnpm verify:vm`, `git diff --check`, touched-file trailing-whitespace and line-length checks, docs preview HTTP
  200, and GSD milestone/roadmap queries passed after the final line-length cleanup.
- No VM was launched and no support matrix row was promoted.
- Codebase-memory MCP `index_repository` retry failed with `Transport closed`, so the code graph could not be refreshed
  for this pass.
- NixOS VM evidence collection now runs through `nix develop --command` in `scripts/vm-matrix.sh` doctor output, guest
  plans, and rendered cloud-init commands. This keeps the collector inside the project flake toolchain instead of
  assuming global `pnpm`, Node, Rust, OpenSSL, or WebKitGTK in the guest profile.
- `bash -n scripts/vm-matrix.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, `bash scripts/vm-matrix.sh validate`,
  rendered NixOS cloud-init grep smoke, `vm-matrix.sh doctor --target nixos-gnome-pipewire` readback, `pnpm verify:docs`,
  and `bash scripts/verify-scripts.sh` passed.
- `scripts/verify-scripts.sh` now asserts both `vm:doctor` and rendered NixOS cloud-init commands use
  `nix develop --command bash scripts/collect-vm-evidence.sh`.
- `pnpm check`, `pnpm detect:audio`, `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml`,
  `pnpm verify:vm`, `git diff --check`, touched-file trailing-whitespace and line-length checks, docs preview HTTP
  200, and GSD milestone/roadmap queries passed after the NixOS evidence handoff update.
- No VM was launched and no support matrix row was promoted.
- Codebase-memory MCP `index_repository` retry failed with `Transport closed`, so the code graph could not be refreshed
  for this pass.
- `PactlVirtualSinkRuntimeAdapter.refreshRoutes` now refreshes matching PulseAudio sink inputs for the selected
  configuration without unloading or recreating Loopwire virtual sinks.
- `scripts/restore-background.mjs` now supports live PulseAudio `--retry-pending-ms` and `--retry-interval-ms` after
  startup verification reports `Pending matching PulseAudio stream(s)`. The JSON payload records
  `pendingStreamRefresh`, retry attempts, and whether pending routes cleared.
- `scripts/manage-autostart.sh` now validates and passes pending retry flags into source-checkout systemd restore units.
- The new refresh regression test first failed because the public adapter had no route-refresh method. After
  implementation, `pnpm --filter @loopwire/audio-host test` passed with 63 tests and
  `pnpm --filter @loopwire/audio-host typecheck` passed.
- `node --check scripts/restore-background.mjs`, `bash -n scripts/manage-autostart.sh scripts/verify-autostart.sh
  scripts/verify-scripts.sh scripts/verify-docs.sh`, and a negative restore CLI parse check for
  `--retry-pending-ms` outside live mode passed.
- `pnpm verify:autostart`, `pnpm verify:scripts`, and `pnpm verify:docs` passed after the retry-window updates.
- `pnpm check`, `pnpm detect:audio`, `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml`,
  `pnpm verify:vm`, touched-file trailing-whitespace and line-length checks, `git diff --check`, docs preview HTTP
  200, and GSD milestone/roadmap queries passed after the pending route refresh update.
- No live host audio mutation was performed, no VM was launched, and no support matrix row was promoted.
- Codebase-memory MCP `index_repository` retry failed with `Transport closed`, so the code graph could not be refreshed
  for this pass.
- `scripts/package-release.sh` now creates a release tarball with a `loopwire` launcher, a bundled Tauri GUI binary at
  `libexec/loopwire/loopwire-gui`, and background restore assets under `libexec/loopwire/scripts` and
  `libexec/loopwire/packages`.
- `scripts/install.sh` now installs bundled `libexec/loopwire` support files beside the binary prefix when release
  artifacts provide them.
- `packaging/aur/PKGBUILD.in` and `packaging/nix/loopwire-bin.nix` now install the libexec support files and include
  Node in the runtime package environment for `loopwire --background`.
- `pnpm verify:release` passed after proving `loopwire --background --help` works from the extracted release tarball and
  from the installed prefix.
- `pnpm verify:aur` passed on this Arch host and confirmed the generated package archive contains `usr/bin/loopwire`,
  `usr/lib/loopwire/loopwire-gui`, and `usr/lib/loopwire/scripts/restore-background.mjs`.
- `pnpm verify:install`, `pnpm verify:packaging`, `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm check`,
  `pnpm detect:audio`, `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml`, `pnpm verify:vm`,
  touched-file trailing-whitespace and line-length checks, `git diff --check`, docs preview HTTP 200, and GSD roadmap
  readback passed after the packaged background restore update.
- No public release was created, no secrets were changed, no VM was launched, and no support matrix row was promoted.
- Codebase-memory MCP `index_repository` retry failed with `Transport closed`, so the code graph could not be refreshed
  for this pass.
- The Tauri shell now renders, installs, reports, and removes a user-scoped background restore systemd unit under
  `${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user`; it also writes the `default.target.wants/loopwire.service` link
  without `sudo`, `/etc/systemd`, or shelling out to `systemctl`.
- The desktop sidebar now has separate **Open on boot** and **Restore on boot** cards, letting users enable GUI
  autostart independently from packaged background audio restore.
- Rust tests passed with 5 tests covering XDG autostart, state writes, background unit rendering, install, status, and
  removal after the restore-on-boot UI update.
- `pnpm --filter @loopwire/desktop typecheck` and `pnpm --filter @loopwire/desktop build` passed after the Svelte
  sidebar update.
- Playwright desktop/mobile smoke at `http://127.0.0.1:5181/` verified both startup cards, restore Check/Enable
  buttons, screenshots, and no horizontal overflow.
- `pnpm verify:docs`, `pnpm check`, `pnpm detect:audio`, Rust `cargo check`, Rust `cargo fmt --check`,
  `pnpm verify:vm`, `git diff --check`, touched-file trailing-whitespace and line-length checks, docs preview HTTP
  200, and GSD roadmap readback passed after the desktop restore-on-boot update.
- No public release was created, no secrets were changed, no VM was launched, and no support matrix row was promoted.
- Codebase-memory MCP `index_repository` retry failed with `Transport closed`, so the code graph could not be refreshed
  for this pass.
- `scripts/collect-vm-evidence.sh` now starts the Loopwire desktop shell through Vite on a guest-local port, polls for
  the Loopwire shell, records `desktop-launch.log`, and writes a required `desktop-launch` command ledger row before
  audio detection, host diagnostics, autostart checks, support-bundle capture, and screenshot verification.
- `scripts/verify-vm-evidence.sh` now rejects evidence bundles without `desktop-launch.log` and a successful
  `desktop-launch` row in `command-results.tsv`.
- `scripts/collect-vm-evidence-ssh.sh` now forwards `--desktop-port` so operators can avoid guest port conflicts while
  keeping the host-side evidence handoff dry-run-first.
- `bash scripts/verify-scripts.sh`, `bash scripts/verify-docs.sh`, and `bash scripts/vm-matrix.sh validate` passed after
  the VM desktop launch evidence update.
- A real local `collect-vm-evidence.sh` smoke passed with a generated PNG screenshot and `--desktop-port 5199`; the
  produced ledger showed `desktop-launch` exit 0 and `vm-evidence-verify` exit 0.
- `pnpm check`, `pnpm detect:audio`, `pnpm verify:vm`, and `cargo check --manifest-path
  apps/desktop/src-tauri/Cargo.toml` passed after the VM desktop launch evidence update.
- No public release was created, no secrets were changed, no VM was launched, and no support matrix row was promoted.
- Codebase-memory MCP `index_repository` retry failed with `Transport closed`, so the code graph could not be refreshed
  for this pass.
- Native PipeWire can now create Loopwire-owned virtual output sinks with guarded `pw-cli create-node adapter` calls,
  link existing source ports into the generated sink names, and destroy selected virtual output nodes during unload or
  rollback.
- Native PipeWire virtual output regression tests first failed because outputs without `deviceName` were rejected as
  missing native PipeWire link targets. After implementation, `pnpm --filter @loopwire/audio-host test` passed with
  66 tests and `pnpm --filter @loopwire/audio-host typecheck` passed.
- `bash scripts/verify-docs.sh`, `pnpm detect:audio`, `pnpm verify:vm`, `cargo check --manifest-path
  apps/desktop/src-tauri/Cargo.toml`, touched-file line-length hygiene, `git diff --check`, `pnpm check`, and docs
  preview HTTP 200 for the homepage, backend guide, and support matrix passed after the native PipeWire virtual output
  update.
- No live `pw-cli create-node` or live `pw-link` mutation was performed; no public release was created, no secrets
  were changed, no VM was launched, and no support matrix row was promoted.
- Codebase-memory MCP `list_projects` failed with `Transport closed`, so this pass used focused shell reads after the
  required graph attempt.
- Native PipeWire can now create Loopwire-owned virtual monitor sinks with guarded `pw-cli create-node adapter` calls,
  link output monitor ports into the generated sink names, and destroy selected virtual monitor nodes during unload or
  rollback.
- Native PipeWire virtual monitor regression tests first failed because monitors without `deviceName` were rejected as
  requiring an existing sink. After implementation, `pnpm --filter @loopwire/audio-host test` passed with 68 tests and
  `pnpm --filter @loopwire/audio-host typecheck` passed.
- `bash scripts/verify-docs.sh`, `pnpm detect:audio`, `pnpm verify:vm`, `cargo check --manifest-path
  apps/desktop/src-tauri/Cargo.toml`, touched-file line-length hygiene, `git diff --check`, `pnpm check`, and docs
  preview HTTP 200 for the homepage, backend guide, configurations guide, and support matrix passed after the native
  PipeWire virtual monitor update.
- No live `pw-cli create-node` or live `pw-link` mutation was performed; no public release was created, no secrets
  were changed, no VM was launched, and no support matrix row was promoted.
- Codebase-memory MCP `index_repository` failed with `Transport closed`, so this pass used focused shell reads after
  the required graph attempt.
- VM evidence bundles now include `environment.json`, a structured manifest of the selected `vm/targets.tsv` row plus
  observed guest distro, desktop/session, architecture, display availability, and kernel.
- `scripts/verify-vm-evidence.sh` now rejects evidence bundles whose `environment.json` target metadata or observed
  distro, desktop/session, or architecture does not match the selected VM target.
- `bash -n scripts/collect-vm-evidence.sh scripts/verify-vm-evidence.sh scripts/verify-scripts.sh scripts/verify-docs.sh`,
  verifier help readback, touched-file line-length checks, touched-file trailing-whitespace checks,
  `pnpm verify:scripts`, `pnpm verify:docs`, and `pnpm verify:vm` passed after the environment-manifest update.
- A real local `collect-vm-evidence.sh --target arch-hyprland-pipewire` smoke passed with a generated PNG screenshot
  and captured `environment.json` showing Arch Linux, Hyprland, Wayland, and x86_64.
- `pnpm check`, `git diff --check`, `gsd-sdk query init.milestone-op`, and
  `gsd-sdk query roadmap.analyze --format json` passed after the environment-manifest update.
- No public release was created, no signing key was generated, no secrets were changed, no tag was pushed, no VM was
  launched, and no support matrix row was promoted.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempt.
- The desktop semantics strip now reports native PipeWire route mute as implemented by disconnecting links and native
  JACK route mute as implemented by disconnecting connections, while keeping route gain marked as planned.
- `pnpm --filter @loopwire/desktop typecheck`, `pnpm --filter @loopwire/desktop build`, `pnpm verify:docs`,
  touched-file line-length checks, and touched-file trailing-whitespace checks passed after the semantics wording
  update.
- Playwright desktop/mobile checks passed against `http://127.0.0.1:4176/`: after selecting PipeWire, the semantics
  strip contained the new route-mute text, stale “gain and mute controls are planned” copy was absent, screenshots
  were captured at `/tmp/loopwire-semantics-desktop.png` and `/tmp/loopwire-semantics-mobile.png`, and no horizontal
  overflow or clipped text containers were found.
- `pnpm check`, `git diff --check`, `gsd-sdk query init.milestone-op`, and
  `gsd-sdk query roadmap.analyze --format json` passed after the semantics wording update.
- No host audio mutation, public release, secret write, tag push, VM launch, or support matrix promotion was performed.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempt.
- Core configuration mutations now remove input sources, output buses, and monitors. Input/output removal prunes
  dependent routes, output removal refuses to remove the final output, and monitor removal clears hidden-monitor state.
- Desktop source, output, and monitor cards now expose compact remove controls. The final output remove control is
  disabled instead of allowing an invalid graph.
- `pnpm --filter @loopwire/core test` passed with 42 tests, including endpoint removal route-pruning regressions.
- `pnpm --filter @loopwire/core typecheck`, `pnpm --filter @loopwire/desktop typecheck`,
  `pnpm --filter @loopwire/desktop build`, and `pnpm verify:docs` passed after endpoint removal was wired.
- Playwright desktop/mobile checks passed against `http://127.0.0.1:4177/`: source deletion removed its route, final
  output deletion was disabled, output deletion pruned routes, monitor deletion cleared hidden state, screenshots were
  captured at `/tmp/loopwire-endpoint-removal-desktop.png` and `/tmp/loopwire-endpoint-removal-mobile.png`, and no
  horizontal overflow was found.
- `pnpm check`, touched-file line-length checks, touched-file trailing-whitespace checks, `git diff --check`,
  `gsd-sdk query init.milestone-op`, and `gsd-sdk query roadmap.analyze --format json` passed after endpoint removal
  was wired.
- No host audio mutation, public release, secret write, tag push, VM launch, or support matrix promotion was performed.
- Codebase-memory MCP `index_status` failed with `Transport closed`, so this pass used focused shell reads after the
  required graph attempt.
- Core configuration mutations now add and remove individual source-to-output routes. Route addition requires existing
  input/output endpoints, rejects duplicate source/output pairs, and keeps per-route gain/mute independent.
- Graph validation now rejects duplicate route ids and duplicate route pairs, so imported or direct-updated
  configurations cannot create ambiguous matrix rows.
- Desktop route cards now expose compact route removal, and the route lane can add a route between existing sources
  and outputs. The add button is disabled when the selected pair already exists.
- `pnpm --filter @loopwire/core test` passed with 46 tests, including add-route, duplicate-pair rejection, route
  removal, and graph-validation regressions.
- `pnpm --filter @loopwire/core typecheck`, `pnpm --filter @loopwire/desktop typecheck`,
  `pnpm --filter @loopwire/desktop build`, and `pnpm verify:docs` passed after route edge lifecycle wiring.
- Playwright desktop/mobile checks passed against `http://127.0.0.1:4178/`: duplicate route creation was disabled,
  route removal preserved endpoints, removed routes could be re-added through the route lane, screenshots were captured
  at `/tmp/loopwire-route-edge-desktop.png` and `/tmp/loopwire-route-edge-mobile.png`, and no horizontal overflow was
  found.
- `pnpm check`, touched-file line-length checks, touched-file trailing-whitespace checks, `git diff --check`,
  `gsd-sdk query init.milestone-op`, and `gsd-sdk query roadmap.analyze --format json` passed after route edge lifecycle
  wiring.
- No host audio mutation, public release, secret write, tag push, VM launch, or support matrix promotion was performed.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempt.
- Core configuration mutation now sets and clears optional host `deviceName` values on input, output, and monitor
  endpoints. Empty values remove the binding.
- Desktop source and output cards now expose manual host binding fields for native backend enumeration gaps. Monitor
  target editing now uses the same core endpoint mutation path.
- `pnpm --filter @loopwire/core test` passed with 48 tests, including set/clear host binding and unknown-endpoint
  regressions.
- `pnpm --filter @loopwire/core typecheck`, `pnpm --filter @loopwire/desktop typecheck`,
  `pnpm --filter @loopwire/desktop build`, and `pnpm verify:docs` passed after host binding wiring.
- Playwright desktop/mobile checks passed against `http://127.0.0.1:4179/`: host source binding could be saved and
  cleared, host target binding could be saved, status messages updated correctly, screenshots were captured at
  `/tmp/loopwire-host-binding-desktop.png` and `/tmp/loopwire-host-binding-mobile.png`, and no horizontal overflow was
  found.
- `pnpm check`, touched-file line-length checks, touched-file trailing-whitespace checks, `git diff --check`,
  `gsd-sdk query init.milestone-op`, and `gsd-sdk query roadmap.analyze --format json` passed after host binding wiring.
- No host audio mutation, public release, secret write, tag push, VM launch, or support matrix promotion was performed.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempt.
- Monitor hide/show writes are now scoped by configuration while legacy bare hidden-monitor ids remain honored on read.
- The desktop now checks monitor visibility through core `isMonitorHidden`, so hiding a monitor in one configuration
  does not hide a same-id monitor in another configuration.
- `pnpm --filter @loopwire/core test` passed with 50 tests, including scoped monitor visibility and legacy bare-id
  compatibility regressions.
- `pnpm --filter @loopwire/core typecheck`, `pnpm --filter @loopwire/desktop typecheck`,
  `pnpm --filter @loopwire/desktop build`, and `pnpm verify:docs` passed after scoped monitor visibility wiring.
- Playwright desktop/mobile checks passed against `http://127.0.0.1:4180/`: hiding Studio `Headphones` left Call
  `Headphones` visible, switching back to Studio preserved the hidden state, screenshots were captured at
  `/tmp/loopwire-monitor-scope-desktop.png` and `/tmp/loopwire-monitor-scope-mobile.png`, and no horizontal overflow
  was found.
- `pnpm check`, touched-file line-length checks, touched-file trailing-whitespace checks, `git diff --check`,
  `gsd-sdk query init.milestone-op`, and `gsd-sdk query roadmap.analyze --format json` passed after scoped monitor
  visibility wiring.
- No host audio mutation, public release, secret write, tag push, VM launch, or support matrix promotion was performed.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempt.
- Desktop custom chrome now persists as a preference and requests an undecorated Tauri window before showing
  Loopwire-owned drag, minimize, and close controls. Native mode restores platform decorations and removes the custom
  title bar.
- `pnpm --filter @loopwire/desktop typecheck`, `pnpm --filter @loopwire/desktop build`, `pnpm verify:docs`, and
  `pnpm check` passed after custom chrome decoration wiring.
- Playwright desktop/mobile checks passed against `http://127.0.0.1:4181/`: custom chrome persisted across reload,
  native restoration removed the fallback title bar, screenshots were captured at
  `/tmp/loopwire-chrome-custom-desktop.png`, `/tmp/loopwire-chrome-desktop.png`, and
  `/tmp/loopwire-chrome-mobile.png`, and no horizontal overflow was found.
- No host audio mutation, public release, secret write, tag push, VM launch, or support matrix promotion was performed.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempt.
- The Tauri restore-on-boot bridge now resolves the packaged `loopwire` background launcher from installed
  `loopwire-gui` paths before writing systemd units. It supports archive layout
  (`libexec/loopwire/loopwire-gui` -> `loopwire`) and installed layout
  (`lib/loopwire/loopwire-gui` -> `bin/loopwire`), and rejects a GUI binary with no launcher instead of writing a
  broken `loopwire-gui --background` unit.
- `cargo fmt -- --check`, `cargo test`, `pnpm verify:docs`, `pnpm --filter @loopwire/desktop typecheck`, and
  `pnpm check` passed after restore-on-boot launcher resolution wiring.
- Rust tests verified archive launcher resolution, installed launcher resolution, non-GUI launcher passthrough, and
  missing-launcher rejection.
- No host audio mutation, public release, secret write, tag push, VM launch, or support matrix promotion was performed.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempt.
- `scripts/deploy-docs-bunny.sh` now uploads built VitePress docs to Bunny Edge Storage with `PUT`, `AccessKey`,
  uppercase SHA256 `Checksum`, optional `BUNNY_STORAGE_ENDPOINT` regional host support, optional remote prefixes, and
  dry-run target readback.
- `.github/workflows/deploy-docs.yml` now calls `scripts/deploy-docs-bunny.sh`, and
  `scripts/setup-github-secrets.sh` can set or check optional `BUNNY_STORAGE_ENDPOINT` alongside the required Bunny
  storage zone and access key secrets.
- Official Bunny docs were checked for HTTP upload authentication, regional endpoints, raw upload bodies, and checksum
  behavior.
- `bash -n scripts/deploy-docs-bunny.sh scripts/setup-github-secrets.sh scripts/verify-scripts.sh
  scripts/verify-github-workflows.sh scripts/verify-docs.sh` passed.
- A manual Bunny dry-run against `ny.storage.bunnycdn.com`, storage zone `loopwire-docs`, and remote prefix `preview`
  printed two upload targets and made no network request.
- A manual secret-helper dry-run printed the required and optional GitHub secret names, including
  `BUNNY_STORAGE_ENDPOINT`, and wrote no secrets.
- `pnpm verify:workflows`, `pnpm verify:docs`, `pnpm verify:scripts`, and `pnpm check` passed after the Bunny docs
  deployment helper update.
- No real Bunny deployment was performed, no GitHub secrets were written, and no public release, tag push, VM launch,
  host audio mutation, or support matrix promotion was performed.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempt.
- `.github/workflows/release.yml` now has a build matrix for `x86_64` on `ubuntu-22.04` and `aarch64` on
  `ubuntu-22.04-arm`.
- Each release build lane stages and smoke-installs signed local artifacts, uploads only release attachments, and leaves
  temporary per-architecture manifests out of the publish boundary.
- The publish job downloads both architecture lanes, regenerates one combined `SHA256SUMS`, signs it, verifies it,
  publishes the GitHub Release, and runs the post-publish installer smoke from the combined release directory.
- Official GitHub runner/action sources were checked for ARM64 runner labels and current artifact action versions.
- `bash -n scripts/verify-github-workflows.sh scripts/verify-docs.sh`, Ruby workflow YAML parse,
  `pnpm verify:workflows`, and `pnpm verify:docs` passed after the release workflow matrix update.
- Touched-file line-length and trailing-whitespace checks passed for the workflow, verifiers, release docs, and release
  notes changed in this slice.
- `git diff --check`, `pnpm check`, `gsd-sdk query init.milestone-op`, and
  `gsd-sdk query roadmap.analyze --format json` passed after the release workflow matrix update.
- No public release was created, no GitHub secrets were written, and no tag push, VM launch, host audio mutation, or
  support matrix promotion was performed.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempt.
- `scripts/verify-published-release.sh` now requires both canonical Linux tarballs
  (`loopwire-linux-x86_64.tar.gz` and `loopwire-linux-aarch64.tar.gz`) and verifies both have entries in the signed
  `SHA256SUMS` manifest before install smoke can pass.
- `scripts/verify-scripts.sh` now builds both canonical fake release tarballs for the local published-release smoke,
  verifies the good signed fixture, rejects a fixture missing the secondary architecture, and still rejects a tampered
  host-architecture tarball.
- `bash -n scripts/verify-published-release.sh scripts/verify-scripts.sh scripts/verify-docs.sh`,
  `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm check`, touched-file line-length and trailing-whitespace checks,
  `git diff --check`, `gsd-sdk query init.milestone-op`, and `gsd-sdk query roadmap.analyze --format json` passed after
  the stricter published-release verifier.
- No public release was created, no GitHub secrets were written, and no tag push, VM launch, host audio mutation, or
  support matrix promotion was performed.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempt.
- `scripts/vm-matrix.sh launch` now returns before image existence checks, cloud-init rendering, overlay creation, seed
  ISO creation, or QEMU execution unless `--execute` is present. Dry-run output includes the operator image path,
  planned overlay path, planned seed path, and QEMU command.
- `scripts/verify-scripts.sh` now runs a launch dry-run with `LOOPWIRE_VM_ROOT` pointed at a temp path and a nonexistent
  operator image, asserts the planned paths are printed, asserts no VM root is written, and asserts `--execute` still
  rejects a missing image.
- `bash -n scripts/vm-matrix.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, `pnpm verify:vm`,
  `pnpm verify:docs`, `pnpm verify:scripts`, and `pnpm check` passed after the non-mutating VM launch dry-run update.
- No VM was launched, no image was downloaded, and no public release, secret write, tag push, host audio mutation, or
  support matrix promotion was performed.
- `scripts/vm-matrix.sh doctor` now treats `cloud-localds` as required launch tooling instead of optional, matching the
  execute path that creates cloud-init seed media.
- `scripts/verify-scripts.sh` now asserts `vm:doctor` reports `cloud-localds=...`, and the VM docs/release notes
  describe missing `cloud-localds` as host setup work.
- `bash -n scripts/vm-matrix.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, `pnpm verify:vm`,
  `pnpm verify:docs`, `pnpm verify:scripts`, and `pnpm check` passed after the stricter VM doctor preflight.
- No VM was launched, no image was downloaded, and no public release, secret write, tag push, host audio mutation, or
  support matrix promotion was performed.
- `scripts/collect-release-evidence.mjs` now includes `published-release-smoke` as optional full-profile evidence and
  supports `--require-published-release` to make the published-release verifier mandatory for final release evidence.
  `--list-commands` prints the command plan as JSON without running commands or writing files.
- `node --check scripts/collect-release-evidence.mjs`, `bash -n scripts/verify-scripts.sh scripts/verify-docs.sh`,
  full-profile and required quick command-plan readbacks, `pnpm verify:scripts`, `pnpm verify:docs`, and `pnpm check`
  passed after the release evidence update.
- No public release was created, no GitHub secrets were written, and no tag push, VM launch, image download, host audio
  mutation, or support matrix promotion was performed.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempt.
- `scripts/promote-vm-evidence.mjs` now verifies target evidence with `scripts/verify-vm-evidence.sh`, confirms the
  target exists in `vm/targets.tsv`, supports dry-run previews, and only promotes support-matrix rows from `Manual VM`
  to `Verified`.
- `pnpm vm:promote-evidence -- --target <target> --dry-run` is documented as the operator preview command before
  changing the support matrix after real VM evidence has been copied back and verified.
- `node --check scripts/promote-vm-evidence.mjs`, `bash -n scripts/verify-scripts.sh scripts/verify-docs.sh`,
  `pnpm verify:scripts`, `pnpm verify:docs`, and `pnpm check` passed after the VM evidence promotion update.
- `scripts/verify-scripts.sh` exercises dry-run preview without mutating the matrix, real promotion against a temp
  matrix copy, already-verified no-op behavior, and failed-evidence rejection.
- No real VM was launched, no image was downloaded, no real support-matrix row was promoted, no public release was
  created, no GitHub secrets were written, no tag was pushed, and no host audio mutation was performed.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempt.
- `scripts/collect-release-evidence.mjs` now writes parsed `release.findings` and `release.blockers` into
  `release-evidence.json`, derived from release-readiness logs.
- `scripts/collect-release-evidence.mjs --summarize-release-readiness-log FILE` can parse an existing readiness log into
  JSON findings without rerunning release checks.
- Real `pnpm verify:release-readiness -- --repo sandwichfarm/loopwire --tag v0.1.0` failed closed on the expected
  blockers: missing release public key, candidate release-note wording, missing local or remote tag, and missing
  required GitHub secrets.
- `node --check scripts/collect-release-evidence.mjs`, `bash -n scripts/verify-scripts.sh scripts/verify-docs.sh`,
  direct log-summary JSON readback, `pnpm verify:scripts`, `pnpm verify:docs`, and `pnpm check` passed after the release
  blocker manifest update.
- A quick evidence bundle generated `release-evidence.json` with `ok: true`, `release.findings` present, and
  `release.blockers` present.
- Touched-file line-length checks, trailing-whitespace checks, and `git diff --check` passed. Because the repo is still
  greenfield/untracked, `git diff --check` is only supplemental to direct touched-file hygiene.
- No public release was created, no release key was generated, no GitHub secrets were written, no tag was pushed, no VM
  was launched, and no support-matrix row was promoted.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempt.
- Official PipeWire filter-chain, PipeWire properties, `pw-cli`, and JACK client API docs were checked before leaving
  backend graph-edge gain planned instead of adding an unproven native-gain implementation.
- Desktop live-apply preflight now shows a compact list of all blockers when more than one issue prevents arming live
  apply. The aggregate message says how many blockers remain, and the list names each concrete backend constraint.
- `apps/docs/docs/guide/configurations.md`, `apps/docs/docs/release-notes/unreleased.md`, and
  `scripts/verify-docs.sh` now document and guard that multi-blocker preflight behavior.
- `pnpm --filter @loopwire/desktop typecheck`, `pnpm --filter @loopwire/desktop build`, and `pnpm verify:docs` passed
  after the desktop preflight update.
- Playwright desktop/mobile smoke against `http://127.0.0.1:4192/` rendered exactly two PipeWire blockers, verified the
  aggregate message, and found zero horizontal overflow at 1440x1100 and 390x900. Screenshots were written to
  `/tmp/loopwire-preflight-blockers-desktop.png` and `/tmp/loopwire-preflight-blockers-mobile.png`.
- `pnpm test` and `pnpm check` passed after the preflight UX update.
- Direct touched-file line-length checks, trailing-whitespace checks, and `git diff --check` passed. Because the repo is
  still greenfield/untracked, `git diff --check` is supplemental to direct touched-file hygiene.
- No host audio mutation, public release, release-key generation, GitHub secret write, tag push, VM launch, or support
  matrix promotion was performed.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempt.
- `scripts/vm-matrix.sh launch` now supports `--ssh-port`, validates the port range, uses the selected port in QEMU
  `hostfwd`, and prints the matching host-side evidence-pull command with the same port.
- `scripts/verify-scripts.sh` now checks the non-default port dry-run, the QEMU `hostfwd` value, the printed evidence
  pull command, and an invalid-port rejection.
- `apps/docs/docs/developer/vm-matrix.md`, `apps/docs/docs/release-notes/unreleased.md`, and
  `scripts/verify-docs.sh` now document and guard configurable VM SSH forwarding.
- `bash -n scripts/vm-matrix.sh scripts/verify-scripts.sh scripts/verify-docs.sh` passed.
- `bash scripts/vm-matrix.sh launch --target arch-hyprland-pipewire --image /operator/images/arch.qcow2 --ssh-port
  2322` passed as a non-mutating dry-run and printed `hostfwd=tcp::2322-:22` plus the matching
  `collect-vm-evidence-ssh.sh --port 2322 --execute` command.
- `bash scripts/vm-matrix.sh launch --target arch-hyprland-pipewire --image /operator/images/arch.qcow2 --ssh-port
  70000` failed closed with `SSH port must be a number from 1 to 65535`.
- `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm verify:vm`, and `pnpm check` passed after the SSH-port update.
- Touched-file line-length checks, trailing-whitespace checks, and `git diff --check` passed. Because the repo is still
  greenfield/untracked, `git diff --check` is supplemental to direct touched-file hygiene.
- No VM was launched, no image was downloaded, no public release was created, no release key was generated, no GitHub
  secrets were written, no tag was pushed, no host audio mutation was performed, and no support matrix row was promoted.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempt.
- `scripts/collect-vm-evidence.sh` now rejects invalid `--desktop-port` values before starting the desktop launch
  smoke.
- `scripts/collect-vm-evidence-ssh.sh` now rejects invalid SSH `--port` and guest `--desktop-port` values before
  printing or executing SSH/SCP handoff commands.
- `scripts/verify-scripts.sh` now covers invalid SSH collector port, invalid SSH collector desktop port, and invalid
  in-guest collector desktop port cases.
- `apps/docs/docs/developer/vm-matrix.md`, `apps/docs/docs/release-notes/unreleased.md`, and
  `scripts/verify-docs.sh` now document and guard the collector port validation contract.
- `bash -n scripts/collect-vm-evidence.sh scripts/collect-vm-evidence-ssh.sh scripts/verify-scripts.sh
  scripts/verify-docs.sh` passed.
- Direct negative checks passed: `collect-vm-evidence-ssh.sh --port nope`,
  `collect-vm-evidence-ssh.sh --desktop-port 70000`, and `collect-vm-evidence.sh --desktop-port 0` all failed closed
  before doing guest work.
- `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm verify:vm`, and `pnpm check` passed after the collector validation
  update.
- Touched-file line-length checks, trailing-whitespace checks, and `git diff --check` passed. Because the repo is still
  greenfield/untracked, `git diff --check` is supplemental to direct touched-file hygiene.
- No VM was launched, no image was downloaded, no public release was created, no release key was generated, no GitHub
  secrets were written, no tag was pushed, no host audio mutation was performed, and no support matrix row was promoted.

## Evidence Missing

- No public GitHub Release was created.
- No real release signing public key exists at `packaging/release-signing-public.pem`.
- No release tag exists locally or remotely.
- Required GitHub secrets are not present for release and Bunny.net deployment.
- No live VM evidence bundle was captured from an actual VM run.
- Host VM launch is not available on this machine until QEMU tooling is installed; `pnpm vm:doctor` reports missing
  `qemu-system-x86_64` and `qemu-img`.
- JACK virtual port creation and graph-edge gain/DSP remain unimplemented.
- The codebase-memory MCP transport is currently closed, so the code graph could not be refreshed in the latest
  verification passes.

## Status

Phase 12 remains incomplete. Publication and VM proof require explicit release/tag/signing-key and VM-run decisions.
