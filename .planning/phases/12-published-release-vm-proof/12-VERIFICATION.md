# Phase 12 Verification: Published Release and VM Proof

**Date:** 2026-07-04
**Status:** Partial, decision-gated

## Evidence Passed

- `node scripts/collect-release-evidence.mjs --output-dir "$tmp_dir" --profile quick` passed and produced
  `release-evidence.json`, `verify-scripts.log`, `verify-vm.log`, `verify-docs.log`, `audio-detect.json`, and
  `tauri-verify.log`.
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
- Restore-on-boot status now remains readable when the packaged background launcher is missing: status returns
  `available: false`, the desktop marks the action blocked, and install still refuses to write a broken GUI-binary
  `--background` unit.
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
- `loopwire-jack-ports` is now bundled as a JACK virtual-port provider wrapper for source checkout, release tarball,
  curl installer, AUR, and Nix package paths. It writes a `loopwire.jack-ports.provision-plan` manifest and fails
  closed unless `LOOPWIRE_JACK_PORTS_DELEGATE` or `--delegate-command` points at a live JACK client provider.
- `pnpm --filter @loopwire/audio-host test -- jack-ports-cli.test.ts` passed with 107 audio-host tests, including
  fail-closed manifest recording, pnpm `--` separator handling, delegate argument forwarding, wrapper-only
  `--delegate-command` stripping, and malformed requirement rejection.
- A strict built CLI smoke passed for `pnpm jack:provider -- --help`, fail-closed manifest recording without a delegate,
  and delegated live-provider argument forwarding.
- `pnpm verify:release` passed after proving the extracted and installed release artifact contains
  `loopwire-jack-ports`, its help runs, and it records a provision manifest while failing closed without a delegate.
- `pnpm verify:install` passed after proving the curl-style installer installs `loopwire-jack-ports`.
- `pnpm verify:aur` passed after the AUR smoke selected the main package archive and verified `usr/bin/loopwire`,
  `usr/bin/loopwire-dsp-provider`, `usr/bin/loopwire-jack-ports`, `usr/lib/loopwire/loopwire-gui`, and the bundled
  background restore runner.
- `pnpm verify:packaging`, `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm verify:autostart`, `pnpm check`,
  `pnpm detect:audio`, shell syntax checks, touched-file line-length check, and `git diff --check` passed after the
  JACK provider wrapper packaging/docs update.
- DSP background restore now requires `--dsp-provider-mode live` when `--backend dsp --mode live` is used. The bundled
  `loopwire-dsp-provider` remains a file-backed preflight provider by default, so live restore cannot silently treat
  seeded JSON buffers as real PipeWire/JACK capture and playback.
- `scripts/manage-autostart.sh` now accepts and renders `--dsp-provider-mode`; it rejects live DSP restore when a DSP
  provider command is configured without an explicit live provider mode.
- `node --check scripts/restore-background.mjs`,
  `bash -n scripts/manage-autostart.sh scripts/verify-autostart.sh scripts/verify-scripts.sh scripts/verify-docs.sh`,
  `pnpm verify:autostart`, and a direct restore CLI smoke passed for the new live-DSP trust-boundary gate.
- `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm check`, `pnpm detect:audio`, GSD roadmap/phase queries,
  touched-file line-length check, and `git diff --check` passed after the DSP provider mode update.
- `pnpm release:prepare-key -- --private-key-out
  /home/sandwich/.config/loopwire/release/loopwire-release-private.pem --public-key-out
  packaging/release-signing-public.pem` generated a 3072-bit RSA release key pair, verified a temporary
  `SHA256SUMS` signature, wrote the public key under `packaging/`, and kept the private key outside the repository with
  `0600` permissions.
- `openssl pkey -pubin -in packaging/release-signing-public.pem -noout` passed.
- `pnpm verify:release-readiness -- --repo sandwichfarm/loopwire --tag v0.1.0 --public-key
  packaging/release-signing-public.pem --skip-gh --skip-tag --skip-clean-git --allow-candidate-notes` passed and
  reported `ok: release public key`.
- The same release-readiness command without `--allow-candidate-notes` still failed closed on candidate release-note
  wording and no longer reported a missing release public key.
- `bash scripts/setup-github-secrets.sh --repo sandwichfarm/loopwire --storage-zone loopwire-docs --access-key
  dummy-access-key --release-private-key-file
  /home/sandwich/.config/loopwire/release/loopwire-release-private.pem --release-public-key-file
  packaging/release-signing-public.pem --dry-run` passed, validating the private/public key pair and printing only the
  GitHub secret names that would be set.
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
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempts.
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
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempt.
- `scripts/collect-vm-evidence.sh` now supports installed-release smoke with `--published-release-dir` or
  `--published-release-repo` plus `--published-release-tag`, `--release-public-key`, and `--require-published-release`.
  When configured, it runs `scripts/verify-published-release.sh` inside the guest and records
  `published-release-smoke.log`.
- `scripts/verify-vm-evidence.sh --require-published-release` now requires a successful `published-release-smoke`
  ledger row and non-empty log, so final VM proof can reject source-checkout-only bundles.
- `scripts/collect-vm-evidence-ssh.sh` now forwards published-release smoke arguments into the guest collector and adds
  `--require-published-release` to the local post-copy verifier when requested.
- `scripts/verify-scripts.sh` now checks collector help text, missing-release-input rejections, SSH dry-run passthrough,
  strict verifier rejection when the release smoke row is absent, and strict verifier acceptance when the row/log exist.
- `apps/docs/docs/developer/vm-matrix.md`, `apps/docs/docs/release-notes/unreleased.md`, and
  `scripts/verify-docs.sh` now document and guard the installed-release VM proof lane.
- `bash -n scripts/collect-vm-evidence.sh scripts/collect-vm-evidence-ssh.sh scripts/verify-vm-evidence.sh
  scripts/verify-scripts.sh scripts/verify-docs.sh` passed.
- Direct focused checks passed: collector help exposes `--published-release-dir` and `--require-published-release`;
  missing required release inputs fail closed; SSH dry-run prints the guest release-smoke flags and the local
  `verify-vm-evidence.sh --require-published-release` command.
- `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm verify:vm`, and `pnpm check` passed after the installed-release VM
  evidence update.
- Touched-file line-length checks, trailing-whitespace checks, and `git diff --check` passed. Because the repo is still
  greenfield/untracked, `git diff --check` is supplemental to direct touched-file hygiene.
- No VM was launched, no image was downloaded, no public release was created, no release key was generated, no GitHub
  secrets were written, no tag was pushed, no host audio mutation was performed, and no support matrix row was promoted.
- `scripts/collect-release-evidence.mjs` now supports `--vm-target`, `--vm-evidence-dir`, and
  `--require-vm-evidence`. Full-profile evidence includes `vm-evidence` as optional command-plan context by default,
  while required runs make `scripts/verify-vm-evidence.sh` fail the release evidence bundle if VM proof is absent or
  invalid.
- When release evidence also uses `--require-published-release`, the generated `vm-evidence` command includes
  `--require-published-release`, so final release proof requires installed-release smoke inside the guest bundle.
- `scripts/verify-scripts.sh` now checks release-evidence help text, optional full-profile `vm-evidence` planning,
  required quick-profile `vm-evidence` planning, and published-release strictness passthrough into the VM verifier.
- `apps/docs/docs/developer/release.md`, `apps/docs/docs/release-notes/unreleased.md`, and `scripts/verify-docs.sh`
  now document and guard the final release evidence gate that combines published-release and VM evidence proof.
- `node --check scripts/collect-release-evidence.mjs`, `bash -n scripts/verify-scripts.sh scripts/verify-docs.sh`,
  release-evidence help readback, full-profile command-plan readback, required quick command-plan readback with
  published-release strictness, `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm verify:vm`, and `pnpm check` passed.
- Touched-file line-length checks, trailing-whitespace checks, and `git diff --check` passed.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempt.
- No VM was launched, no image was downloaded, no public release was created, no release key was generated, no GitHub
  secrets were written, no tag was pushed, no host audio mutation was performed, and no support matrix row was promoted.
- `scripts/collect-release-evidence.mjs` now expands `--vm-target all` from `vm/targets.tsv`, validates unknown target
  ids, supports repeated or comma-separated `--vm-target` values, and rejects a shared `--vm-evidence-dir` when
  multiple targets are selected without a `{target}` placeholder.
- Multi-target release evidence command plans now emit one `vm-evidence:<target>` command and log per selected target,
  so final release proof can require every declared VM matrix target instead of only the default Arch reference path.
- `apps/docs/docs/developer/release.md`, `apps/docs/docs/release-notes/unreleased.md`, `scripts/verify-docs.sh`, and
  `scripts/verify-scripts.sh` now document and guard the all-target VM release evidence ceremony.
- `node --check scripts/collect-release-evidence.mjs`, `bash -n scripts/verify-scripts.sh scripts/verify-docs.sh`,
  all-target command-plan readback proving seven VM verifier commands with `--require-published-release`, shared-dir
  rejection readback, `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm verify:vm`, and `pnpm check` passed.
- Touched-file line-length checks, trailing-whitespace checks, and `git diff --check` passed.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempt.
- No VM was launched, no image was downloaded, no public release was created, no release key was generated, no GitHub
  secrets were written, no tag was pushed, no host audio mutation was performed, and no support matrix row was promoted.
- Added `scripts/verify-release-evidence.mjs` and `pnpm verify:release-evidence` for independently auditing a collected
  release evidence bundle. The verifier checks `release-evidence.json`, manifest `ok`, required command success,
  non-empty command logs, optional published-release smoke, optional VM evidence, complete `vm/targets.tsv` coverage,
  and optional blocker-free release readiness.
- `scripts/verify-scripts.sh` now builds fixture evidence bundles proving final-evidence acceptance, incomplete VM target
  coverage rejection, release-blocker rejection, and empty-command-log rejection.
- `apps/docs/docs/developer/release.md`, `apps/docs/docs/release-notes/unreleased.md`, `package.json`, and
  `scripts/verify-docs.sh` now document and guard the final release evidence verification command.
- `node --check scripts/verify-release-evidence.mjs`, `bash -n scripts/verify-scripts.sh scripts/verify-docs.sh`,
  verifier help readback, fixture verifier acceptance/rejection checks, `pnpm verify:docs`, `pnpm verify:scripts`,
  `pnpm verify:vm`, and `pnpm check` passed.
- Touched-file line-length checks, trailing-whitespace checks, and `git diff --check` passed.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempt.
- No VM was launched, no image was downloaded, no public release was created, no release key was generated, no GitHub
  secrets were written, no tag was pushed, no host audio mutation was performed, and no support matrix row was promoted.
- `.github/workflows/release.yml` now collects published-release evidence after the GitHub Release publish smoke, runs
  `pnpm verify:release-evidence` against the generated bundle, and uploads `loopwire-release-evidence-<tag>` with
  90-day retention.
- `scripts/verify-github-workflows.sh` now guards the release workflow evidence collection and upload steps.
- `apps/docs/docs/developer/release.md`, `apps/docs/docs/release-notes/unreleased.md`, and `scripts/verify-docs.sh`
  now document and guard that CI captures the published-release evidence artifact while VM evidence remains
  operator-collected outside GitHub-hosted runners.
- `bash -n scripts/verify-github-workflows.sh scripts/verify-docs.sh scripts/verify-scripts.sh`, Ruby workflow YAML
  parse, `pnpm verify:workflows`, `pnpm verify:docs`, `pnpm verify:scripts`, and `pnpm check` passed.
- Touched-file line-length checks, trailing-whitespace checks, and `git diff --check` passed.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempt.
- The release workflow itself was not run because there is no real signing key, tag, GitHub Release, or configured
  release secret yet.
- No VM was launched, no image was downloaded, no public release was created, no release key was generated, no GitHub
  secrets were written, no tag was pushed, no host audio mutation was performed, and no support matrix row was promoted.
- `.github/workflows/release.yml` now packages the verified release evidence directory as
  `loopwire-release-evidence-<tag>.tar.gz`, uploads that archive to the GitHub Release with `gh release upload
  --clobber`, and keeps both the expanded evidence directory and tarball as workflow artifacts.
- `scripts/verify-github-workflows.sh` now guards the evidence archive name, tar command, and GitHub Release upload
  command.
- `apps/docs/docs/developer/release.md`, `apps/docs/docs/release-notes/unreleased.md`, and `scripts/verify-docs.sh`
  now document and guard the public release evidence asset.
- `bash -n scripts/verify-github-workflows.sh scripts/verify-docs.sh scripts/verify-scripts.sh`, Ruby workflow YAML
  parse, `pnpm verify:workflows`, `pnpm verify:docs`, `pnpm verify:scripts`, and `pnpm check` passed.
- Touched-file line-length checks, trailing-whitespace checks, and `git diff --check` passed.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempt.
- The release workflow itself was not run because there is no real signing key, tag, GitHub Release, or configured
  release secret yet.
- No VM was launched, no image was downloaded, no public release was created, no release key was generated, no GitHub
  secrets were written, no tag was pushed, no host audio mutation was performed, and no support matrix row was promoted.
- `scripts/verify-published-release.sh` now supports `--require-release-evidence`, requires
  `loopwire-release-evidence-<tag>.tar.gz`, extracts the archive, and verifies the extracted bundle with
  `scripts/verify-release-evidence.mjs --require-published-release --require-no-release-blockers`.
- `.github/workflows/release.yml` now runs published-release verification with `--require-release-evidence` immediately
  after uploading the public evidence archive, so the tag workflow fails if the GitHub Release lacks the evidence asset
  or the archive contains blocker findings.
- `scripts/verify-scripts.sh` now covers missing evidence archive rejection, valid public evidence archive acceptance,
  and blocked evidence archive rejection against the signed fake release-directory fixture.
- `apps/docs/docs/developer/release.md`, `apps/docs/docs/release-notes/unreleased.md`, `scripts/verify-docs.sh`, and
  `scripts/verify-github-workflows.sh` now document and guard the public evidence archive requirement.
- `bash -n scripts/verify-published-release.sh scripts/verify-scripts.sh scripts/verify-github-workflows.sh
  scripts/verify-docs.sh`, `pnpm verify:workflows`, `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm check`, Ruby
  release-workflow YAML parse, and `git diff --check` passed.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempt.
- The release workflow itself was not run because there is no real signing key, tag, GitHub Release, or configured
  release secret yet.
- No VM was launched, no image was downloaded, no public release was created, no release key was generated, no GitHub
  secrets were written, no tag was pushed, no host audio mutation was performed, and no support matrix row was promoted.
- `scripts/verify-release-evidence.mjs` now supports `--release-tag` and `--repo`, rejecting evidence bundles whose
  manifest `release.tag` or `release.repo` does not match the expected public release surface.
- `scripts/verify-published-release.sh --require-release-evidence` now passes expected tag/repo values when known and
  validates evidence archive member paths before extraction, rejecting absolute paths and `..` components.
- `scripts/verify-scripts.sh` now covers direct release-evidence tag/repo mismatch rejection, public evidence archive
  tag mismatch rejection, and unsafe tar path rejection against the published-release verifier.
- `apps/docs/docs/developer/release.md`, `apps/docs/docs/release-notes/unreleased.md`, and `scripts/verify-docs.sh`
  now document and guard the stricter public evidence archive verification.
- `node --check scripts/verify-release-evidence.mjs`, `bash -n scripts/verify-published-release.sh
  scripts/verify-scripts.sh scripts/verify-docs.sh`, `pnpm verify:scripts`, `pnpm verify:docs`,
  `pnpm verify:workflows`, `pnpm check`, touched-file line-length checks, and `git diff --check` passed.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempt.
- The release workflow itself was not run because there is no real signing key, tag, GitHub Release, or configured
  release secret yet.
- No VM was launched, no image was downloaded, no public release was created, no release key was generated, no GitHub
  secrets were written, no tag was pushed, no host audio mutation was performed, and no support matrix row was promoted.
- Desktop live-apply preflight now names native PipeWire/JACK routes blocked by non-100% gain and offers a `Reset gains`
  action that restores affected route gains to 100% in app state without touching host audio.
- The reset flow preserves other blockers after it clears gain blockers, so missing native source ports or JACK
  virtual-port gaps still prevent live apply.
- `apps/docs/docs/guide/configurations.md`, `apps/docs/docs/release-notes/unreleased.md`, and `scripts/verify-docs.sh`
  now document and guard the route-gain recovery affordance.
- `pnpm --filter @loopwire/desktop typecheck`, `pnpm --filter @loopwire/core test`,
  `pnpm --filter @loopwire/audio-host test`, `pnpm --filter @loopwire/desktop build`, `pnpm verify:docs`,
  `pnpm check`, touched-file line-length checks, and `git diff --check` passed.
- Playwright desktop/mobile checks against `http://127.0.0.1:4182` selected PipeWire, verified the route-specific gain
  blocker and `Reset gains` action, clicked the action, confirmed all route gains changed to 100%, confirmed the gain
  blocker disappeared, confirmed missing-host-source blockers remained, and confirmed zero horizontal overflow.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempt.
- No VM was launched, no image was downloaded, no public release was created, no release key was generated, no GitHub
  secrets were written, no tag was pushed, no host audio mutation was performed, and no support matrix row was promoted.
- Desktop live-apply preflight now names source, output, and monitor labels for native PipeWire/JACK host-binding
  blockers, so missing host ports point to the exact UI fields that need repair.
- `apps/docs/docs/guide/configurations.md`, `apps/docs/docs/release-notes/unreleased.md`, and `scripts/verify-docs.sh`
  now document and guard the endpoint-specific blocker wording.
- `pnpm --filter @loopwire/desktop typecheck`, `pnpm --filter @loopwire/desktop build`, `pnpm verify:docs`,
  `pnpm --filter @loopwire/core test`, `pnpm --filter @loopwire/audio-host test`, `pnpm check`, touched-file
  line-length checks, and `git diff --check` passed.
- Playwright desktop/mobile checks against `http://127.0.0.1:4183` selected PipeWire, verified the route-specific gain
  blocker, verified the source-specific host-binding blocker for `Studio Mic` and `Browser Audio`, and confirmed zero
  horizontal overflow.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempt.
- No VM was launched, no image was downloaded, no public release was created, no release key was generated, no GitHub
  secrets were written, no tag was pushed, no host audio mutation was performed, and no support matrix row was promoted.
- Desktop custom chrome fallback now exposes a maximize/restore control alongside the existing minimize and close
  actions for undecorated Tauri windows.
- The new control calls Tauri `toggleMaximize()` and shares the same browser-preview fallback note as the existing
  window controls when the app is not running inside the Tauri desktop shell.
- `apps/docs/docs/guide/troubleshooting.md`, `apps/docs/docs/release-notes/unreleased.md`, and `scripts/verify-docs.sh`
  now document and guard the complete custom chrome control set.
- `pnpm --filter @loopwire/desktop typecheck`, `pnpm --filter @loopwire/desktop build`, `pnpm verify:docs`,
  `bash -n scripts/verify-docs.sh`, `pnpm check`, touched-file line-length checks, and `git diff --check` passed.
- Playwright desktop/mobile checks against `http://127.0.0.1:4184` selected custom chrome, verified minimize,
  maximize/restore, and close controls, clicked maximize/restore, confirmed the expected browser-preview Tauri fallback
  message, and confirmed zero horizontal overflow.
- Codebase-memory MCP `index_status` failed with `Transport closed`, so this pass used focused shell reads after the
  required graph attempt.
- No VM was launched, no image was downloaded, no public release was created, no release key was generated, no GitHub
  secrets were written, no tag was pushed, no host audio mutation was performed, and no support matrix row was promoted.
- The native JACK adapter now validates route sources, route targets, and monitor source outputs before any `jack_lsp`,
  `jack_connect`, or `jack_disconnect` command. App-only endpoints that still require virtual JACK ports fail closed
  with endpoint-specific messages instead of probing the host first.
- `packages/audio-host/tests/jack-adapter.test.ts` now covers virtual JACK route input, route output, and monitor
  source-output blockers and asserts no JACK commands are run for those invalid configurations.
- Test-first validation produced the expected red run: `pnpm --filter @loopwire/audio-host test` failed 3 tests before
  the adapter validation change.
- `pnpm --filter @loopwire/audio-host typecheck`, `pnpm --filter @loopwire/audio-host test`, `pnpm verify:docs`,
  `bash -n scripts/verify-docs.sh`, `pnpm check`, touched-file line-length checks, and `git diff --check` passed.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempt.
- No VM was launched, no image was downloaded, no public release was created, no release key was generated, no GitHub
  secrets were written, no tag was pushed, no host audio mutation was performed, and no support matrix row was promoted.
- The Tauri `run_audio_command` boundary now validates command names and argument shapes against Loopwire's
  detector/runtime contract before spawning live audio processes. The policy allows the current `aplay`, `wpctl`,
  `pactl`, `pw-cli`, `pw-link`, `jack_lsp`, `jack_connect`, and `jack_disconnect` operations while rejecting unrelated
  subcommands, option expansion, and non-port mutation arguments.
- `apps/desktop/src-tauri/src/main.rs` now has unit coverage for allowed probe commands, allowed mutation commands, and
  rejected out-of-contract host command shapes.
- `cargo fmt --manifest-path apps/desktop/src-tauri/Cargo.toml`, `cargo test --manifest-path
  apps/desktop/src-tauri/Cargo.toml`, `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml`,
  `pnpm verify:docs`, `bash -n scripts/verify-docs.sh`, `pnpm check`, touched-file line-length checks, and
  `git diff --check` passed. The Tauri unit suite now reports 12 passing tests.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempt.
- No VM was launched, no image was downloaded, no public release was created, no release key was generated, no GitHub
  secrets were written, no tag was pushed, no host audio mutation was performed, and no support matrix row was promoted.
- `pnpm check` now runs `pnpm check:verify`, which includes `pnpm verify:tauri`. The verifier runs Rust format checks,
  compile checks, and the Tauri unit suite, so local, CI, release, support-bundle, and release-evidence paths share the
  same Tauri shell gate.
- Rendered non-Nix VM guest commands now install Rust plus Tauri Linux build prerequisites before running `pnpm check`.
  `verify-cloud-init` rejects generated Arch, Debian/Ubuntu, or Fedora handoffs that are missing WebKitGTK/Rust
  coverage, and Fedora JACK targets must include the JACK package.
- CI and release workflows now rely on the workspace `pnpm check` gate instead of keeping separate cargo-only steps.
- `node scripts/collect-release-evidence.mjs --list-commands --profile quick` lists `tauri-verify`,
  `pnpm verify:tauri`, and `tauri-verify.log`.
- `bash -n scripts/verify-tauri.sh scripts/verify-scripts.sh scripts/verify-github-workflows.sh
  scripts/verify-docs.sh scripts/vm-matrix.sh scripts/collect-vm-evidence.sh scripts/collect-vm-evidence-ssh.sh`,
  `pnpm verify:vm`, `pnpm verify:docs`, `pnpm verify:workflows`, `pnpm verify:scripts`, `pnpm verify:tauri`,
  `pnpm check`, stale active-reference search, touched-file line-length checks, and `git diff --check` passed.
- Current Tauri Linux prerequisite package groups were checked against the official Tauri v2 prerequisites, and Arch
  package availability was checked locally with `pacman -Ss`.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempt.
- No VM was launched, no image was downloaded, no public release was created, no release key was generated, no GitHub
  secrets were written, no tag was pushed, no host audio mutation was performed, and no support matrix row was promoted.
- `opensuse-kde-pipewire` is now a Manual VM target for openSUSE Tumbleweed, KDE Plasma, Wayland, and
  PipeWire/WirePlumber.
- `scripts/vm-matrix.sh` now treats `zypper` as a supported package family, renders openSUSE guest bootstrap commands
  with Rust, pinned pnpm, PipeWire/WirePlumber, and Tauri openSUSE prerequisites, and rejects rendered zypper handoffs
  that are missing WebKitGTK, Rust cargo, build pattern, or pinned pnpm coverage.
- `scripts/verify-vm-evidence.sh` now maps `openSUSE Tumbleweed` target metadata to the expected
  `opensuse-tumbleweed` `/etc/os-release` id for future evidence bundles.
- `bash -n scripts/vm-matrix.sh scripts/verify-scripts.sh scripts/verify-docs.sh scripts/verify-vm-evidence.sh`,
  `pnpm verify:vm`, `pnpm verify:docs`, `bash scripts/vm-matrix.sh plan --target opensuse-kde-pipewire`,
  `pnpm verify:scripts`, `pnpm check`, touched-file line-length checks, and `git diff --check` passed.
- `node scripts/collect-release-evidence.mjs --list-commands --profile quick --require-published-release
  --require-vm-evidence --vm-target all --vm-evidence-dir '.vm/evidence/{target}' --release-tag v0.1.0 --repo
  sandwichfarm/loopwire --public-key packaging/release-signing-public.pem` now expands to 8 required VM evidence
  commands, including `vm-evidence:opensuse-kde-pipewire`.
- The zypper Tauri prerequisite set was checked against the official Tauri v2 openSUSE guidance.
- Codebase-memory MCP `index_repository` failed with `Transport closed`, so this pass used focused shell reads after
  the required graph attempt.
- No VM was launched, no image was downloaded, no public release was created, no release key was generated, no GitHub
  secrets were written, no tag was pushed, no host audio mutation was performed, and no support matrix row was promoted.
- `ubuntu-gnome-pipewire-aarch64` is now a Manual VM target for Ubuntu LTS, GNOME, Wayland,
  PipeWire/PulseAudio compatibility, and AArch64.
- `scripts/vm-matrix.sh launch` now accepts `--firmware`, prints `qemu-system-aarch64`, `-machine virt`, and
  `-cpu max` for AArch64 dry-runs, and rejects AArch64 `--execute` without an operator-owned UEFI firmware path.
- `bash -n scripts/vm-matrix.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, `pnpm verify:vm`,
  `pnpm verify:docs`, `bash scripts/vm-matrix.sh launch --target ubuntu-gnome-pipewire-aarch64 --image
  /operator/images/ubuntu-aarch64.qcow2 --ssh-port 2422`, `pnpm verify:scripts`, `pnpm check`, touched-file
  line-length checks, and `git diff --check` passed.
- `node scripts/collect-release-evidence.mjs --list-commands --profile quick --require-published-release
  --require-vm-evidence --vm-target all --vm-evidence-dir '.vm/evidence/{target}' --release-tag v0.1.0 --repo
  sandwichfarm/loopwire --public-key packaging/release-signing-public.pem` now expands to 9 required VM evidence
  commands, including `vm-evidence:ubuntu-gnome-pipewire-aarch64`.
- Codebase-memory MCP `index_repository` failed with `Transport closed`, so this pass used focused shell reads after
  the required graph attempt.
- No VM was launched, no image was downloaded, no public release was created, no release key was generated, no GitHub
  secrets were written, no tag was pushed, no host audio mutation was performed, and no support matrix row was promoted.
- `scripts/setup-github-secrets.sh --check` now preserves `gh secret list` failures instead of treating unreadable
  repository secret names as ordinary missing secrets.
- `scripts/verify-release-readiness.sh` now reports the same unreadable secret-name failure during the release
  readiness preflight, while still avoiding secret values.
- `scripts/verify-scripts.sh` now covers secret-check success and failure with a fake `gh` executable, including the
  release readiness preflight path, so the contract remains reproducible without live GitHub credentials.
- `bash -n scripts/setup-github-secrets.sh scripts/verify-release-readiness.sh scripts/verify-scripts.sh
  scripts/verify-docs.sh`, `pnpm verify:docs`, `pnpm verify:scripts`, and `pnpm check` passed after the secret-check
  hardening.
- A manual dry-run with a nonexistent release private key file failed closed as expected.
- Codebase-memory MCP `index_repository` failed with `Transport closed`, so this pass used focused shell reads after
  the required graph attempt.
- No GitHub secrets were read beyond names, no secret values were printed, no secret was written, no public release was
  created, no tag was pushed, no VM was launched, and no support matrix row was promoted.
- `.github/workflows/deploy-docs.yml` now passes optional `BUNNY_REMOTE_PREFIX` into the Bunny.net upload step, so one
  storage zone can host Loopwire docs under a configured path without changing the deploy script.
- `scripts/setup-github-secrets.sh` now prints, checks, dry-runs, and sets optional `BUNNY_REMOTE_PREFIX` while keeping
  `BUNNY_STORAGE_ZONE` plus `BUNNY_ACCESS_KEY` as the required Bunny deployment pair.
- `scripts/verify-scripts.sh` now proves the secret helper dry-run names `BUNNY_REMOTE_PREFIX` without printing its
  value, and fake-`gh` check mode reports the optional prefix secret when present.
- `bash -n scripts/setup-github-secrets.sh scripts/verify-github-workflows.sh scripts/verify-scripts.sh
  scripts/verify-docs.sh`, `pnpm verify:workflows`, `pnpm verify:docs`, `pnpm verify:scripts`, and `pnpm check` passed
  after the remote-prefix deployment update.
- Codebase-memory MCP `index_repository` failed with `Transport closed`, so this pass used focused shell reads after
  the required graph attempt.
- No Bunny deployment was performed, no GitHub secrets were written, no public release was created, no tag was pushed,
  no VM was launched, and no support matrix row was promoted.
- `scripts/vm-matrix.sh host-setup` and `pnpm vm:host-setup` now print a dry-run-only VM host setup handoff:
  `package-family=*`, one `install-command=*`, required VM host tools, and the target-aware `verify-command=*`.
- `host-setup` rejects `--execute`, so the helper cannot install packages on the operator host.
- `scripts/verify-scripts.sh` now covers apt AArch64 host setup output, the pnpm zypper host setup path, unknown package
  family rejection, and `--execute` rejection.
- The new verifier caught and fixed a shell scoping regression where host package-family detection overwrote the
  selected NixOS guest family in `vm:doctor`; NixOS doctor output again uses `nix develop --command` for guest bootstrap
  and evidence collection.
- `bash -n scripts/vm-matrix.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, direct apt/AArch64 and pnpm zypper
  host-setup dry-runs, `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm verify:vm`, and `pnpm check` passed after the
  host setup update.
- Codebase-memory MCP `index_repository` failed with `Transport closed`, so this pass used focused shell reads after
  the required graph attempt.
- No package installation, VM launch, image download, host audio mutation, public release, secret write, tag push, or
  support matrix promotion was performed.
- Native JACK can now resolve app route inputs, route outputs, and monitor targets without host `deviceName` values to
  deterministic Loopwire-owned JACK port names. It connects only when those ports already exist and still does not
  create JACK clients or ports.
- Desktop JACK live-apply preflight now allows those app-owned endpoints to reach the runtime `jack_lsp` probe, while
  non-100% native route gain remains a static blocker.
- The new JACK regression tests first failed on the old missing-`deviceName` validation path, then
  `pnpm --filter @loopwire/audio-host test -- jack-adapter.test.ts` passed with 73 tests.
- `pnpm --filter @loopwire/audio-host typecheck`, `pnpm --filter @loopwire/desktop typecheck`, `pnpm verify:docs`,
  `pnpm check`, touched-file line-length checks, and `git diff --check` passed after the JACK port resolution update.
- Codebase-memory MCP `search_graph` failed with `Transport closed`, so this pass used focused shell reads after the
  required graph attempt.
- No JACK host audio mutation, VM launch, image download, package installation, public release, secret write, tag push,
  or support matrix promotion was performed.
- Release evidence verification now rejects manifest command log paths that contain parent traversal, escape the
  evidence directory after realpath resolution, resolve through symlinks, or point to non-file entries.
- The new release evidence verifier regression first failed because `../outside.log` was accepted. After implementation,
  `pnpm verify:scripts` passed with parent-directory and symlink-escape negative cases.
- `pnpm verify:docs` passed after documenting the stricter release evidence command-log containment contract.
- Codebase-memory MCP `index_repository` failed with `Transport closed`, so this pass used focused shell reads after
  the required graph attempt.
- No package installation, VM launch, image download, host audio mutation, public release, secret write, tag push, Bunny
  deployment, or support matrix promotion was performed.
- Changing the selected desktop backend now persists the backend, refreshes source and monitor candidates, disarms any
  live host-apply session, and immediately preview-verifies the active configuration against the new backend.
- If backend-change preview verification fails, the runtime note preserves the failure detail while still making the
  live-disarm safety action explicit.
- `pnpm --filter @loopwire/desktop typecheck`, `pnpm --filter @loopwire/desktop build`, and `pnpm verify:docs` passed
  after the backend selector update.
- Playwright against `http://127.0.0.1:4185/` selected PulseAudio, armed live apply, switched to PipeWire, verified the
  host-apply control returned to `Preview`, verified the runtime note says live apply was disarmed for preview
  verification, and confirmed zero horizontal overflow.
- Codebase-memory MCP `index_repository` failed with `Transport closed`, so this pass used focused shell reads after
  the required graph attempt.
- No live host audio mutation, package installation, VM launch, image download, public release, secret write, tag push,
  Bunny deployment, or support matrix promotion was performed.
- Desktop configuration switching now uses a tokenized busy state, so only the latest switch/delete transaction can update
  runtime state and stale async results cannot replace the latest selected configuration.
- Configuration actions are disabled while the latest switch transaction is in flight, and unexpected switch exceptions
  fail closed without leaving the sidebar locked.
- `pnpm --filter @loopwire/desktop typecheck`, `pnpm --filter @loopwire/desktop build`, and `pnpm verify:docs` passed
  after the configuration-switch update.
- Playwright against `http://127.0.0.1:4186/` switched from Studio to Call, verified the selected configuration persisted
  across reload, verified the configuration buttons were enabled after the transaction, and confirmed zero horizontal
  overflow on desktop and mobile.
- Codebase-memory MCP `index_repository` and `search_graph` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempts.
- No live host audio mutation, package installation, VM launch, image download, public release, secret write, tag push,
  Bunny deployment, or support matrix promotion was performed.
- `pnpm check`, touched-file line-length check, `git diff --check`, and `gsd-sdk query roadmap.analyze` passed after the
  configuration-switch update. Roadmap analysis still reports Phase 12 as planned/incomplete and milestone progress at
  80%.
- Release evidence verification now validates required VM evidence target rows before trusting command results. It rejects
  unknown target ids, duplicate target ids, absolute or parent-traversing `evidenceDir` values, evidence dirs that omit
  the target id as a path segment, and VM command rows that do not call `scripts/verify-vm-evidence.sh` with the matching
  `--target` and `--evidence-dir`.
- The script contract now includes malformed VM evidence row smokes for unsafe `evidenceDir`, duplicate target entries,
  and VM command rows that do not invoke the target-bound verifier command.
- `node --check scripts/verify-release-evidence.mjs`, `bash -n scripts/verify-scripts.sh scripts/verify-docs.sh`,
  `pnpm verify:scripts`, and `pnpm verify:docs` passed after the release evidence VM-row hardening.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempts.
- No live host audio mutation, package installation, VM launch, image download, public release, secret write, tag push,
  Bunny deployment, or support matrix promotion was performed.
- ALSA playback/capture diagnostics now enumerate playback hardware with `aplay -l` and capture hardware with
  `arecord -l`. The desktop labels ALSA candidates as diagnostics, the Tauri bridge allows only `arecord -l` for capture
  probing, and ALSA live apply remains blocked.
- `pnpm --filter @loopwire/audio-host test -- detectors.test.ts`, `pnpm --filter @loopwire/audio-host typecheck`,
  `pnpm --filter @loopwire/desktop typecheck`, `pnpm --filter @loopwire/desktop build`,
  `cargo fmt --manifest-path apps/desktop/src-tauri/Cargo.toml --check`,
  `cargo test --manifest-path apps/desktop/src-tauri/Cargo.toml`, `pnpm verify:tauri`, `pnpm verify:docs`,
  `pnpm verify:scripts`, `pnpm check`, `git diff --check`, touched-file line-length checks, and
  `gsd-sdk query roadmap.analyze` passed after the ALSA diagnostics update.
- `pnpm detect:audio` confirmed read-only ALSA availability on this host, `aplay -l` listed playback hardware, and
  `arecord -l` listed capture hardware.
- Codebase-memory MCP `index_status`, `search_graph`, and `index_repository` failed with `Transport closed`, so this
  pass used focused shell reads after the required graph attempts.
- No live host audio mutation, ALSA route/apply implementation, package installation, VM launch, image download, public
  release, secret write, tag push, Bunny deployment, or support matrix promotion was performed.
- ALSA capability detection now probes both `aplay -l` and `arecord -l`, keeps playback-only or capture-only visibility
  available for diagnostics, and reports `createVirtualDevice`, `routeAudio`, `monitorAudio`, `apply`, `verify`, and
  `rollback` as unavailable instead of planned.
- `pnpm --filter @loopwire/audio-host test -- detectors.test.ts` passed with 76 tests,
  `pnpm --filter @loopwire/audio-host typecheck`, `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm check`,
  `git diff --check`, touched-file line-length checks, and `gsd-sdk query roadmap.analyze` passed after the ALSA
  capability correction.
- `pnpm detect:audio` confirmed ALSA commands now include both `aplay -l` and `arecord -l`, with
  route/apply/verify/rollback unavailable.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempts.
- No live host audio mutation, ALSA routing implementation, package installation, VM launch, image download, public
  release, secret write, tag push, Bunny deployment, or support matrix promotion was performed.
- `scripts/vm-matrix.sh doctor --all` now prints a `target-check=*` block for every target in `vm/targets.tsv`,
  including architecture-specific QEMU checks, guest evidence commands, host pull commands, KVM status, and host install
  hints. It fails closed if any target lacks required launch tools and rejects `--all` together with `--target`.
- `bash -n scripts/vm-matrix.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, direct `doctor --all` readback,
  conflicting `doctor --all --target` rejection, `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm verify:vm`,
  `pnpm check`, `git diff --check`, touched-file line-length checks, and `gsd-sdk query roadmap.analyze` passed after
  the matrix-wide doctor update.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempts.
- No package installation, VM launch, image download, host audio mutation, public release, secret write, tag push, Bunny
  deployment, or support matrix promotion was performed.
- `scripts/vm-matrix.sh host-setup --all` now prints `target-scope=all`, all QEMU system tools required by
  `vm/targets.tsv`, the shared launch support tools, and `verify-command=bash scripts/vm-matrix.sh doctor --all`.
  It remains dry-run-only and rejects `--all` together with `--target`.
- `bash -n scripts/vm-matrix.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, direct `host-setup --all` readback,
  conflicting `host-setup --all --target` rejection, `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm verify:vm`,
  `pnpm check`, `git diff --check`, touched-file line-length checks, and `gsd-sdk query roadmap.analyze` passed after
  the all-target host setup update.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempts.
- No package installation, VM launch, image download, host audio mutation, public release, secret write, tag push, Bunny
  deployment, or support matrix promotion was performed.
- Release evidence verification now validates source-state metadata before trusting a bundle. It requires a 40-character
  `git.head`, rejects unavailable or unsafe git fields, and supports `--require-clean-git` for final release bundles.
- The release workflow now passes `--release-tag "$LOOPWIRE_RELEASE_TAG"` and `--repo "$GITHUB_REPOSITORY"` into direct
  `pnpm verify:release-evidence` before attaching `loopwire-release-evidence-<tag>.tar.gz`.
- The script contract now includes negative smokes for missing git metadata and dirty `git.statusShort` when
  `--require-clean-git` is enabled.
- `node --check scripts/verify-release-evidence.mjs`, `bash -n scripts/verify-scripts.sh scripts/verify-docs.sh
  scripts/verify-github-workflows.sh`, `pnpm verify:scripts`, `pnpm verify:docs`, and `pnpm verify:workflows` passed
  after the release evidence source-state update.
- A real quick collector smoke wrote `/tmp/loopwire-release-evidence.xiH9qF/release-evidence.json`; `pnpm
  verify:release-evidence -- --evidence-dir /tmp/loopwire-release-evidence.xiH9qF --release-tag v0.1.0 --repo
  sandwichfarm/loopwire` passed and recorded commit `704f511122a7de549f804a9995db59fde1757482`. A negative
  `--require-clean-git` check failed closed on the same bundle because the current worktree is dirty.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempts.
- No package installation, VM launch, image download, host audio mutation, public release, secret write, tag push, Bunny
  deployment, or support matrix promotion was performed.
- `scripts/verify-requirements.sh` now verifies the v1/v2 product requirements ledger against concrete source, docs,
  workflow, packaging, and test anchors. It is wired into `pnpm check:verify` through `pnpm verify:requirements`.
- `.planning/REQUIREMENTS.md` now marks the v1 UX, backend, configuration, Linux integration, docs, and quality
  requirements complete because they have current verification anchors. `SHIP-01..SHIP-03` remain pending.
- The first requirements verifier run failed on an over-specific homepage install anchor, proving the new gate catches
  stale evidence assumptions. The anchor now matches the current source-install homepage copy instead of advertising
  unpublished curl install artifacts.
- `pnpm verify:docs` initially recursed after a new assertion used shell backticks inside double quotes. The running
  verifier session was interrupted, the assertion was switched to single quotes, and `pnpm verify:docs` passed.
- `bash -n scripts/verify-requirements.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, `pnpm
  verify:requirements`, `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm verify:workflows`, `pnpm check`, `git diff
  --check`, and touched-file line-length checks passed after the product requirements evidence-gate update.
- Codebase-memory MCP `index_status`, `search_graph`, and `index_repository` failed with `Transport closed`, so this
  pass used focused shell reads after the required graph attempts.
- No package installation, VM launch, image download, host audio mutation, public release, secret write, tag push, Bunny
  deployment, or support matrix promotion was performed.
- `scripts/vm-matrix.sh host-setup --family dnf --all` now prints a Fedora install command with
  `qemu-system-aarch64`, and `scripts/vm-matrix.sh host-setup --family zypper --all` now prints an openSUSE install
  command with both `qemu-x86` and `qemu-arm`. Targeted AArch64 `host-plan` output also prints the architecture-scoped
  package hints for Fedora and openSUSE.
- `bash -n scripts/vm-matrix.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, direct `host-setup --family dnf
  --all` readback, direct `host-setup --family zypper --all` readback, direct AArch64 `host-plan` readback, `pnpm
  verify:docs`, `pnpm verify:scripts`, `pnpm verify:vm`, `pnpm check`, `git diff --check`, and touched-file
  line-length checks passed after the architecture-scoped host setup update.
- Codebase-memory MCP `index_status` failed with `Transport closed`, so this pass used focused shell reads after the
  required graph attempt.
- Official package lookup confirmed Fedora exposes `qemu-system-aarch64` and openSUSE exposes `qemu-arm`.
- No package installation, VM launch, image download, host audio mutation, public release, secret write, tag push, Bunny
  deployment, or support matrix promotion was performed.
- `flake.nix` now exposes `packages.<system>.loopwire-bin` and `packages.<system>.default` for `x86_64-linux` and
  `aarch64-linux` through `packaging/nix/loopwire-bin.nix`. The default package intentionally uses
  `nixpkgs.lib.fakeHash` until published artifacts provide real release hashes, and
  `lib.<system>.mkLoopwireBinPackage` lets release automation or downstream consumers inject the real version and
  hashes.
- `bash -n scripts/verify-packaging.sh scripts/verify-docs.sh`, `pnpm verify:packaging`, `pnpm verify:docs`,
  `pnpm check`, `git diff --check`, and touched-file line-length checks passed after the Nix flake package-template
  update.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempts.
- `nix` is not installed on this host, so no `nix flake show` or `nix build` proof was produced.
- No package installation, VM launch, image download, host audio mutation, public release, secret write, tag push, Bunny
  deployment, or support matrix promotion was performed.
- `apps/docs/docs/public/install.sh` now mirrors `scripts/install.sh` byte-for-byte, so the VitePress/Bunny docs
  deployment can serve `/install.sh` without introducing a second installer contract. `scripts/verify-docs.sh` rejects
  drift and runs shell syntax checks against the public asset.
- `bash -n apps/docs/docs/public/install.sh scripts/install.sh scripts/verify-docs.sh scripts/verify-scripts.sh`,
  public installer drift `cmp`, `pnpm verify:docs`, `pnpm --filter @loopwire/docs docs:build`, built-dist installer
  `cmp`, `pnpm verify:scripts`, `pnpm check`, `git diff --check`, and touched-file line-length checks passed after the
  public installer endpoint update.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempts.
- No package installation, VM launch, image download, host audio mutation, public release, secret write, tag push, Bunny
  deployment, or support matrix promotion was performed.
- `scripts/verify-release-readiness.sh` now checks the canonical installer and public docs installer, rejects byte drift
  between them, and runs `bash -n` on the public docs installer.
- `scripts/verify-scripts.sh` now proves the Bunny.net dry-run would upload `install.sh` and covers positive synced
  installer plus negative stale public-installer release-readiness cases.
- `bash -n scripts/verify-release-readiness.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, `pnpm verify:docs`,
  `pnpm verify:scripts`, touched-file line-length checks, `pnpm check`, `git diff --check`, and
  `gsd-sdk query roadmap.analyze` passed after the public installer release-gate hardening.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempts.
- No package installation, VM launch, image download, host audio mutation, public release, secret write, tag push, Bunny
  deployment, or support matrix promotion was performed.
- `scripts/deploy-docs-bunny.sh` now requires non-empty built `index.html` and `install.sh` files before dry-run or live
  upload planning, runs `bash -n` on the built public installer, and rejects unsafe `.` or `..` segments in
  `BUNNY_REMOTE_PREFIX`.
- `bash -n scripts/deploy-docs-bunny.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, `pnpm verify:docs`,
  `pnpm verify:scripts`, touched-file line-length checks, `pnpm check`, `git diff --check`, and
  `gsd-sdk query roadmap.analyze` passed after the Bunny docs dist-gate update.
- `pnpm verify:scripts` covers positive `install.sh` dry-run upload plus negative missing-`install.sh`,
  missing-`index.html`, and unsafe-remote-prefix cases.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempts.
- No package installation, VM launch, image download, host audio mutation, public release, secret write, tag push, Bunny
  deployment, or support matrix promotion was performed.
- `scripts/verify-docs-live.sh` and `pnpm verify:docs-live` now fetch a deployed docs homepage plus `/install.sh`, verify
  the deployed installer parses as shell, and compare it byte-for-byte with `apps/docs/docs/public/install.sh`.
- `.github/workflows/deploy-docs.yml` now runs `scripts/verify-docs-live.sh` after Bunny upload when
  `BUNNY_PULL_ZONE_HOSTNAME` is configured, turning the optional pull-zone hostname secret into a real post-deploy smoke
  surface.
- `bash -n scripts/verify-docs-live.sh scripts/verify-scripts.sh scripts/verify-docs.sh
  scripts/verify-github-workflows.sh`, `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm verify:workflows`,
  touched-file line-length checks, `pnpm check`, `git diff --check`, and `gsd-sdk query roadmap.analyze` passed after
  the Bunny pull-zone smoke wiring.
- `pnpm verify:scripts` covers a fake-curl positive pull-zone smoke plus stale deployed installer and unsafe
  remote-prefix rejection.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempts.
- No package installation, VM launch, image download, host audio mutation, public release, secret write, tag push, Bunny
  deployment, live URL smoke, or support matrix promotion was performed.
- Desktop live-apply preflight now blocks JACK configurations whose routed sources, routed outputs, monitor source
  outputs, or monitor targets lack explicit host bindings to existing JACK ports. This moves a predictable missing-port
  failure to the preflight strip before live apply can be armed.
- The JACK runtime adapter still keeps the lower-level deterministic Loopwire-owned port fallback for automation and
  still fails closed after read-only `jack_lsp` when required ports are missing. Loopwire still does not create JACK
  virtual ports.
- `pnpm --filter @loopwire/desktop typecheck`, `pnpm verify:docs`, touched-file line-length checks, and
  `git diff --check` passed after the JACK desktop preflight update.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempts.
- No live JACK server, host audio mutation, VM launch, package install, public release, secret write, tag push, Bunny
  deployment, live URL smoke, or support matrix promotion was performed.
- Desktop live-apply preflight rules now live in `apps/desktop/src/live-apply-preflight.ts`, and `App.svelte` imports
  that pure helper instead of carrying private duplicate blocker logic.
- `apps/desktop/src/live-apply-preflight.test.ts` covers no-backend, ALSA diagnostics-only, PulseAudio ready, native
  PipeWire gain/source blockers, native JACK gain/port blockers, JACK-ready configurations, and native gain route
  filtering.
- `pnpm --filter @loopwire/desktop test -- src/live-apply-preflight.test.ts`,
  `pnpm --filter @loopwire/desktop typecheck`, `pnpm verify:docs`, touched-file line-length checks,
  `git diff --check`, `pnpm check`, and `gsd-sdk query roadmap.analyze` passed after the preflight extraction.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempts.
- No live JACK server, host audio mutation, VM launch, package install, public release, secret write, tag push, Bunny
  deployment, live URL smoke, or support matrix promotion was performed.
- `scripts/collect-vm-matrix-evidence.sh` and `pnpm vm:collect-matrix` now read a tab-separated guest plan and expand
  each row into the existing SSH evidence collector, preserving target-scoped local evidence paths for multi-system
  passes.
- The matrix collector rejects unknown targets, duplicate targets, invalid SSH or desktop ports, and malformed
  published-release smoke options before touching a guest.
- The matrix collector can forward `--published-release-dir` or `--published-release-repo`, `--release-public-key`, and
  `--require-published-release` to every guest row for final release proof.
- `bash -n scripts/collect-vm-matrix-evidence.sh scripts/verify-scripts.sh scripts/verify-docs.sh`,
  `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm vm:collect-matrix -- --help`, direct dry-run plan readback,
  touched-file line-length checks, `pnpm check`, `git diff --check`, and `gsd-sdk query roadmap.analyze` passed after
  the matrix VM evidence collector wiring.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempts.
- No package installation, VM launch, image download, host audio mutation, public release, secret write, tag push, Bunny
  deployment, live URL smoke, or support matrix promotion was performed.
- `scripts/collect-release-evidence.mjs` now supports `--require-live-docs`, docs URL/hostname/remote-prefix options,
  records `release.docsLive`, and schedules `docs-live-smoke` through `scripts/verify-docs-live.sh` against the public
  installer at `apps/docs/docs/public/install.sh`.
- `scripts/verify-release-evidence.mjs` now rejects final evidence when `--require-live-docs` is set without a required
  passing `docs-live-smoke` command row.
- Command-plan readback for
  `node scripts/collect-release-evidence.mjs --list-commands --profile quick --require-live-docs --docs-hostname
  docs.example.test --docs-remote-prefix preview` produced a required `docs-live-smoke` command with the expected
  hostname, remote prefix, and public installer path.
- `node --check scripts/collect-release-evidence.mjs scripts/verify-release-evidence.mjs`, `bash -n
  scripts/verify-scripts.sh scripts/verify-docs.sh`, `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm check`,
  `git diff --check`, touched-file line-length checks, and `gsd-sdk query roadmap.analyze` passed after the release
  evidence live-docs gate wiring.
- Codebase-memory MCP `index_status` failed with `Transport closed`, so this pass used focused shell reads after the
  required graph attempt.
- No package installation, VM launch, image download, host audio mutation, public release, secret write, tag push, Bunny
  deployment, live URL smoke, or support matrix promotion was performed.
- `scripts/vm-matrix.sh render-ssh-plan` now generates the TSV consumed by `scripts/collect-vm-matrix-evidence.sh` for
  one target or the full target matrix. Rows include target-scoped `.vm/evidence/<target>` output paths, configurable
  guest host/user/identity fields, optional desktop smoke port, and unique forwarded SSH ports.
- `pnpm vm:render-ssh-plan -- --target ubuntu-gnome-pipewire-aarch64 --start-port 2422 --desktop-port 5199` passed and
  printed the expected AArch64 target row.
- `bash scripts/vm-matrix.sh render-ssh-plan --target fedora-kde-jack --host 127.0.0.1 --start-port 2322
  --desktop-port 5199` passed, all-target render readback passed, and invalid all-target `--start-port 65500` was
  rejected before producing an unusable plan.
- A generated one-target plan was accepted by `scripts/collect-vm-matrix-evidence.sh` in dry-run mode and expanded to
  the expected `scripts/collect-vm-evidence-ssh.sh` command with target-scoped local and remote evidence directories.
- `pnpm verify:vm`, `pnpm verify:docs`, and `pnpm verify:scripts` passed after the SSH plan generator was documented
  and added to script guards.
- `pnpm check` and GSD milestone/roadmap queries passed after the final handoff update.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempts.
- No package installation, VM launch, image download, host audio mutation, public release, secret write, tag push, Bunny
  deployment, live URL smoke, or support matrix promotion was performed.
- `scripts/collect-support-bundle.mjs` now suppresses audio-host build chatter before writing `detect-audio.json`, so
  the file remains valid JSON for downstream parsing.
- Support bundle manifests now include `audio.backends` rows summarizing backend kind, availability, transport,
  route-control scope, per-edge gain/mute flags, diagnostics, and known gaps from `detect-audio.json`.
- `scripts/verify-vm-evidence.sh` now requires nested support bundles to include that parsed backend summary before VM
  evidence can pass.
- A direct quick support-bundle smoke passed and produced parsed rows for PipeWire, PulseAudio compatibility, JACK, and
  ALSA.
- `pnpm verify:scripts` passed with manifest-shape assertions and a negative VM-evidence case proving support bundles
  without `audio.backends` are rejected.
- `node --check scripts/collect-support-bundle.mjs`, `bash -n scripts/verify-vm-evidence.sh scripts/verify-scripts.sh
  scripts/verify-docs.sh`, `pnpm verify:docs`, audio-host tests/typecheck, `pnpm verify:vm`, touched-file line-length
  checks, `git diff --check`, and `pnpm check` passed after the support-bundle summary update.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempts.
- No package installation, VM launch, image download, host audio mutation, public release, secret write, tag push, Bunny
  deployment, live URL smoke, or support matrix promotion was performed.
- Native JACK port requirements now use a shared `describeJackPortRequirements` helper from `@loopwire/audio-host`.
  The helper reports configured vs Loopwire-owned requirements, deterministic client names, channel counts, and
  suggested channel ports from the same naming path used by the runtime adapter.
- Desktop JACK live-apply preflight now consumes that helper when naming unbound endpoint blockers, so users see the
  exact deterministic Loopwire-owned client name before arming host commands.
- `apps/desktop/vitest.config.ts` now mirrors the Vite source aliases for `@loopwire/core` and
  `@loopwire/audio-host/*`, preventing source tests from depending on stale package `dist` exports.
- `pnpm --filter @loopwire/audio-host test -- jack-adapter.test.ts`,
  `pnpm --filter @loopwire/desktop test -- src/live-apply-preflight.test.ts`,
  `pnpm --filter @loopwire/audio-host typecheck`, `pnpm --filter @loopwire/desktop typecheck`, `pnpm verify:docs`,
  audio-host tests, desktop tests, `pnpm check`, `git diff --check`, touched-file line-length checks, and
  `gsd-sdk query roadmap.analyze` plus `gsd-sdk query init.milestone-op` passed after the shared JACK requirement
  helper update.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempts. A final retry after broad validation failed the same way.
- No live JACK server, host audio mutation, VM launch, package install, public release, secret write, tag push, Bunny
  deployment, live URL smoke, or support matrix promotion was performed.
- `scripts/describe-jack-ports.mjs` and `pnpm jack:ports` now expose the shared JACK requirement helper as a read-only
  CLI. It accepts a configuration export, raw configuration JSON, or persisted state file and emits JSON or TSV rows
  for configured JACK clients plus deterministic Loopwire-owned client/port requirements.
- `--loopwire-owned-only` filters the CLI output to endpoints that require pre-existing Loopwire-owned JACK clients,
  giving pro-audio users a concrete session-template handoff without claiming Loopwire creates JACK ports yet.
- `pnpm verify:scripts` now covers the CLI help text plus deterministic JSON and TSV output from a fixture
  configuration, including configured ports and Loopwire-owned route/monitor requirements.
- `node --check scripts/describe-jack-ports.mjs`, `pnpm jack:ports -- --help`, `pnpm verify:scripts`,
  `pnpm verify:docs`, `pnpm check`, `git diff --check`, touched-file line-length checks, and
  `gsd-sdk query roadmap.analyze` passed after the JACK port CLI update.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempts. A final retry after broad validation failed the same way.
- No live JACK server, host audio mutation, VM launch, package install, public release, secret write, tag push, Bunny
  deployment, live URL smoke, or support matrix promotion was performed.
- `scripts/describe-jack-ports.mjs --verify` and `pnpm jack:verify` now compare the shared JACK requirements against
  live `jack_lsp` output or a saved `--ports-file` fixture. Verification is read-only and reports per-requirement
  readiness, matched ports, and missing suggested ports.
- The verifier exits nonzero when required JACK port matches are absent, so users can check an external JACK session
  template before arming native JACK live apply.
- `pnpm verify:scripts` now covers positive JSON and TSV readiness output against a captured port list and a negative
  missing-port case.
- `node --check scripts/describe-jack-ports.mjs`, `pnpm jack:verify -- --help`, `pnpm verify:scripts`,
  `pnpm verify:docs`, `pnpm check`, `git diff --check`, touched-file line-length checks,
  `gsd-sdk query roadmap.analyze`, and `gsd-sdk query init.milestone-op` passed after the JACK readiness update.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempts. A final retry after broad validation failed the same way.
- No live JACK server, host audio mutation, VM launch, package install, public release, secret write, tag push, Bunny
  deployment, live URL smoke, or support matrix promotion was performed.
- `scripts/collect-support-bundle.mjs` now accepts optional `--configuration` or `--state-file` input for JACK
  readiness, plus `--configuration-id` for persisted state selection and `--jack-ports-file` for captured port-list
  verification.
- When those inputs are provided, support bundles write `jack-port-requirements.json` and summarize read-only JACK
  readiness as `jack` in `support-bundle.json`. Default bundles keep `jack.status = "not_requested"` so support
  collection does not fail merely because no Loopwire configuration was provided.
- `pnpm verify:scripts` now covers default support-bundle manifests and configuration-backed support bundles with
  parsed passing JACK readiness summaries.
- `node --check scripts/collect-support-bundle.mjs`, `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm check`,
  `git diff --check`, touched-file line-length checks, `gsd-sdk query roadmap.analyze`, and
  `gsd-sdk query init.milestone-op` passed after the support-bundle JACK readiness update.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempts. A final retry after broad validation failed the same way.
- No live JACK server, host audio mutation, VM launch, package install, public release, secret write, tag push, Bunny
  deployment, live URL smoke, or support matrix promotion was performed.
- `scripts/verify-vm-evidence.sh` now rejects VM bundles whose `detect-audio.json` does not report the selected
  target's expected audio backend as available. PipeWire targets require PipeWire, PipeWire/PulseAudio compatibility
  targets require both PipeWire and PulseAudio, PulseAudio targets require PulseAudio, and JACK targets require JACK.
- `pnpm verify:scripts` now includes a negative case proving unavailable target audio backend evidence is rejected
  before support-matrix promotion can proceed.
- `bash -n scripts/verify-vm-evidence.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, `pnpm verify:scripts`,
  `pnpm verify:docs`, `pnpm verify:vm`, and `pnpm check` passed after the VM target audio proof update.
- Codebase-memory MCP `index_status`, `search_graph`, `list_projects`, and `index_repository` failed with
  `Transport closed`, so this pass used focused shell reads after the required graph attempts.
- No VM was launched and no support matrix row was promoted.
- `scripts/verify-release-evidence.mjs --require-published-release` now rejects fake `published-release-smoke` rows
  unless the command ran `scripts/verify-published-release.sh` with the manifest repo, tag, and public key.
- `pnpm verify:scripts` now uses a real-shaped positive `published-release-smoke` fixture and a negative fake command
  fixture, proving final release evidence cannot substitute a fake command row for published-artifact install smoke.
- `node --check scripts/verify-release-evidence.mjs`, `bash -n scripts/verify-scripts.sh`, `pnpm verify:scripts`,
  `pnpm verify:docs`, and `pnpm check` passed after the published-release evidence binding update.
- Codebase-memory MCP `index_status`, `search_graph`, `search_code`, and `index_repository` failed with
  `Transport closed`, so this pass used focused shell reads after the required graph attempts.
- No public release, tag push, secret write, Bunny deployment, live URL smoke, VM launch, or support matrix promotion
  was performed.
- `scripts/verify-published-release.sh --require-release-evidence` now resolves the public evidence archive before
  checksum verification and requires `loopwire-release-evidence-<tag>.tar.gz` to appear in the signed `SHA256SUMS`
  manifest before extracting the archive.
- `.github/workflows/release.yml` now writes the evidence archive into `dist/release`, regenerates `SHA256SUMS`,
  re-signs it with `LOOPWIRE_RELEASE_PRIVATE_KEY`, verifies the signature, uploads the updated manifest/signature plus
  evidence archive, and then reruns the published-release verifier with `--require-release-evidence`.
- `scripts/verify-scripts.sh` now rejects a signed fake release where the evidence archive exists but is missing from
  `SHA256SUMS`, then re-signs invalid evidence fixtures so mismatched tags, unsafe archive paths, and blocked findings
  are tested after checksum binding.
- `scripts/verify-install.sh` now signs a local `SHA256SUMS` manifest that includes a missing evidence archive entry,
  proving the installer still accepts the selected tarball via `sha256sum --check --ignore-missing`.
- `bash -n scripts/verify-published-release.sh scripts/verify-scripts.sh scripts/verify-github-workflows.sh
  scripts/verify-docs.sh scripts/sign-release-artifacts.sh scripts/verify-install.sh`, `pnpm verify:install`,
  `pnpm verify:workflows`, `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm check`, touched-file line-length checks, and
  `git diff --check` passed after the signed evidence archive update.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempts.
- No public release, tag push, secret write, Bunny deployment, live URL smoke, VM launch, package install, host audio
  mutation, or support matrix promotion was performed.
- PulseAudio compatibility now rejects one-source-to-many-output route shapes before unloading modules, creating sinks,
  moving streams, refreshing pending routes, or verifying host state. This prevents the previous false-positive path
  where one matching sink input could be moved through multiple outputs and only the final move would win.
- Desktop live-apply preflight now blocks the same PulseAudio fan-out shape and names the affected routes before live
  apply can be armed.
- Regression tests first failed against the previous behavior: the PulseAudio adapter returned success for duplicate
  source routes, and the desktop preflight reported PulseAudio live apply as ready. After implementation,
  `pnpm --filter @loopwire/audio-host test -- runtime-adapter.test.ts` passed with 79 tests and
  `pnpm --filter @loopwire/desktop test -- live-apply-preflight.test.ts` passed with 8 tests.
- `pnpm --filter @loopwire/audio-host typecheck && pnpm --filter @loopwire/audio-host test`,
  `pnpm --filter @loopwire/desktop typecheck && pnpm --filter @loopwire/desktop test`, `pnpm verify:docs`,
  `pnpm check`, touched-file line-length checks, and `git diff --check` passed after the PulseAudio fan-out update.
- `gsd-sdk query roadmap.analyze` and `gsd-sdk query init.milestone-op` passed; Phase 12 remains planned/incomplete at
  80% milestone progress.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempts.
- No public release, tag push, secret write, Bunny deployment, live URL smoke, VM launch, package install, host audio
  mutation, or support matrix promotion was performed.
- PulseAudio backend detection now reports `one output per source` in available-backend gaps and warning text, matching
  the runtime adapter and desktop live-apply preflight boundary for source fan-out.
- Support matrix, backend docs, unreleased notes, and `scripts/verify-docs.sh` now pin that same PulseAudio limitation
  so support bundles and docs expose the real stream-level contract.
- The detector regression test first failed while the implementation omitted `one output per source`, then passed after
  the detector update.
- `pnpm --filter @loopwire/audio-host test -- detectors.test.ts`, `pnpm --filter @loopwire/audio-host typecheck`,
  `pnpm verify:docs`, `pnpm check`, touched-file line-length checks, `git diff --check`,
  `gsd-sdk query roadmap.analyze`, and `gsd-sdk query init.milestone-op` passed after the PulseAudio detection update.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempts.
- No public release, tag push, secret write, Bunny deployment, live URL smoke, VM launch, package install, host audio
  mutation, or support matrix promotion was performed.
- `scripts/verify-release-evidence.mjs` now tokenizes required final proof command rows and requires direct
  `bash scripts/verify-published-release.sh`, `bash scripts/verify-docs-live.sh`, or
  `bash scripts/verify-vm-evidence.sh` invocations with exact binding flags.
- `pnpm verify:scripts` now includes echo-disguised published-release, live-docs, and VM command fixtures. The new
  regression first failed because the old verifier accepted the disguised VM evidence command, then passed after
  tokenized command validation was added.
- Release docs, unreleased notes, and `scripts/verify-docs.sh` now document and guard the direct-invocation evidence
  requirement.
- `node --check scripts/verify-release-evidence.mjs`, `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm check`,
  touched-file line-length checks, `git diff --check`, `gsd-sdk query roadmap.analyze`, and
  `gsd-sdk query init.milestone-op` passed after the final evidence command hardening.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempts.
- No public release, tag push, secret write, Bunny deployment, live URL smoke, VM launch, package install, host audio
  mutation, or support matrix promotion was performed.
- `scripts/verify-release-readiness.sh` now resolves local or remote release tags to commits and requires the selected
  tag to point at the current checkout `HEAD`.
- `pnpm verify:scripts` now includes a temp-git-repo release-readiness smoke that first passes while `v0.1.0` points at
  `HEAD`, then advances `HEAD` and proves the stale tag is rejected.
- Release docs, unreleased notes, and `scripts/verify-docs.sh` now document and guard the tag-current-HEAD release
  preflight requirement.
- `bash -n scripts/verify-release-readiness.sh scripts/verify-scripts.sh`, `pnpm verify:scripts`,
  `pnpm verify:docs`, `pnpm check`, touched-file line-length checks, `git diff --check`,
  `gsd-sdk query roadmap.analyze`, and `gsd-sdk query init.milestone-op` passed after the stale-tag readiness update.
- Real `pnpm verify:release-readiness -- --repo sandwichfarm/loopwire --tag v0.1.0` still failed closed on expected
  blockers: missing release public key, candidate release notes, missing local or remote tag, and missing required
  GitHub secrets.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempts.
- No public release, tag push, secret write, Bunny deployment, live URL smoke, VM launch, package install, host audio
  mutation, or support matrix promotion was performed.
- `scripts/verify-release-readiness.sh` now requires `git status --short` to be clean by default before final release
  readiness can pass.
- `scripts/verify-release-readiness.sh --skip-clean-git` exists for explicit candidate evidence collection, and
  `scripts/collect-release-evidence.mjs` uses it only for the candidate readiness command.
- `pnpm verify:scripts` now asserts the clean-git help text, the candidate command opt-out, dirty checkout rejection,
  opt-out acceptance with `skipped: clean git status check`, and stale tag rejection after `HEAD` advances.
- Release docs, unreleased notes, and `scripts/verify-docs.sh` now document and guard the clean-check release preflight
  and the candidate evidence opt-out.
- `bash -n scripts/verify-release-readiness.sh scripts/verify-scripts.sh scripts/verify-docs.sh`,
  `node --check scripts/collect-release-evidence.mjs`, `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm check`,
  touched-file line-length checks, `git diff --check`, `gsd-sdk query roadmap.analyze`, and
  `gsd-sdk query init.milestone-op` passed after the clean-check readiness update.
- Real `pnpm verify:release-readiness -- --repo sandwichfarm/loopwire --tag v0.1.0` still failed closed on expected
  blockers: missing release public key, candidate release notes, dirty git status, missing local or remote tag, and
  missing required GitHub secrets.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempts.
- No public release, tag push, secret write, Bunny deployment, live URL smoke, VM launch, package install, host audio
  mutation, or support matrix promotion was performed.
- Desktop route-control semantics now live in `apps/desktop/src/route-control-semantics.ts` with focused unit coverage.
- Native PipeWire and JACK selections now lock route gain sliders because those backends are link-only today. Existing
  non-unity values remain visible, route mute remains available, and the existing `Reset gains` action stays the repair
  path before live apply.
- Configuration docs, unreleased notes, and `scripts/verify-docs.sh` now document and guard the native gain-lock UX.
- `pnpm --filter @loopwire/desktop test -- route-control-semantics.test.ts live-apply-preflight.test.ts`,
  `pnpm --filter @loopwire/desktop typecheck`, `pnpm verify:docs`, and `pnpm --filter @loopwire/desktop build` passed.
- Playwright desktop and mobile smokes against `http://127.0.0.1:4190/` selected PipeWire, confirmed all route gain
  sliders were disabled with locked accessible labels, captured `/tmp/loopwire-route-gain-lock-desktop.png` and
  `/tmp/loopwire-route-gain-lock-mobile.png`, and found zero horizontal overflow.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempts.
- No public release, tag push, secret write, Bunny deployment, live URL smoke, VM launch, package install, host audio
  mutation, or support matrix promotion was performed.
- Desktop startup restore and configuration clicks now render the last runtime activity ledger from
  `ConfigurationRuntimeResult.log`, so users can inspect unload, apply, verify, and rollback rows for the actual runtime
  plan.
- Configuration docs, unreleased notes, and `scripts/verify-docs.sh` now document and guard the runtime activity ledger.
- `pnpm --filter @loopwire/desktop typecheck`, `pnpm --filter @loopwire/desktop build`,
  `pnpm --filter @loopwire/desktop test -- live-apply-preflight.test.ts route-control-semantics.test.ts`, and
  `pnpm verify:docs` passed after the ledger update.
- Playwright desktop and mobile smokes against `http://127.0.0.1:4191/` verified startup restore ledger presence,
  clicked `Stream`, confirmed `Unload Studio`, `Apply Stream`, and `Verify Stream` rows, confirmed `Stream` became
  active, captured `/tmp/loopwire-runtime-ledger-desktop.png` and `/tmp/loopwire-runtime-ledger-mobile.png`, and found
  zero horizontal overflow.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this pass used focused
  shell reads after the required graph attempts.
- No public release, tag push, secret write, Bunny deployment, live URL smoke, VM launch, package install, host audio
  mutation, or support matrix promotion was performed.
- `scripts/collect-vm-matrix-evidence.sh` now rejects unsafe `local_output_dir` cells before it can touch guests:
  parent traversal is blocked, and custom paths must include the VM target id as a path segment.
- `scripts/verify-scripts.sh` now includes negative smokes for parent-traversing and non-target-scoped matrix evidence
  output paths, while preserving absolute temp output paths that include the target id.
- VM matrix docs, unreleased notes, and `scripts/verify-docs.sh` now document and guard the local output path rule.
- `scripts/promote-vm-evidence.mjs` now supports `--require-published-release` and forwards it to
  `scripts/verify-vm-evidence.sh`, so final support-matrix promotion can require installed-release guest smoke.
- `scripts/verify-scripts.sh` now rejects promotion with `--require-published-release` until `published-release-smoke`
  evidence exists, then verifies the dry-run promotion path after that smoke row is present.
- Support matrix docs, VM matrix docs, unreleased notes, and `scripts/verify-docs.sh` now document and guard the
  stricter final support promotion mode.
- `scripts/vm-matrix.sh launch` now rejects invalid memory, CPU count, SSH port, and backing image-format values
  before printing or executing QEMU commands.
- `scripts/verify-scripts.sh` now includes negative smokes for non-numeric memory, too-small memory, invalid CPU
  count, and unsupported image format launch requests.
- VM matrix docs, unreleased notes, and `scripts/verify-docs.sh` now document and guard the launch input contract.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this slice used focused
  shell reads after the required graph attempt. `bash -n scripts/vm-matrix.sh scripts/verify-scripts.sh
  scripts/verify-docs.sh`, targeted launch rejection assertions, `pnpm verify:scripts`, `pnpm verify:docs`,
  `pnpm check`, `git diff --check`, and touched-file line-length checks passed.
- `scripts/setup-github-secrets.sh` now rejects Bunny storage zones with slashes, storage endpoints with newlines,
  pull-zone hostnames that are URLs or paths, and remote prefixes with `.` or `..` path segments before dry-run output
  or `gh secret set`.
- `scripts/verify-scripts.sh` now includes negative smokes for those unsafe Bunny secret values, while preserving the
  existing dry-run guarantee that secret values are not printed.
- Release docs, unreleased notes, and `scripts/verify-docs.sh` now document and guard the secret helper's Bunny
  validation contract.
- Codebase-memory MCP `index_status` failed with `Transport closed`, so this slice used focused shell reads after the
  required graph attempt. `bash -n scripts/setup-github-secrets.sh scripts/verify-scripts.sh scripts/verify-docs.sh`,
  targeted helper rejection assertions, `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm check`, and
  `git diff --check` passed.
- `.github/workflows/deploy-docs.yml` now passes `--remote-prefix "$BUNNY_REMOTE_PREFIX"` to
  `scripts/verify-docs-live.sh` and reports the prefixed deployment URL, so Bunny deployments under a remote prefix
  verify the same path that received uploaded docs.
- `scripts/verify-github-workflows.sh` now guards the deploy workflow's remote-prefix live-smoke forwarding and
  prefixed deployment URL reporting.
- Release docs, unreleased notes, and `scripts/verify-docs.sh` now document and guard the prefixed Bunny live-smoke
  path.
- Codebase-memory MCP `index_status` failed with `Transport closed`, so this slice used focused shell reads after the
  required graph attempt. `bash -n scripts/verify-github-workflows.sh scripts/verify-docs.sh`, Ruby YAML parsing for
  `.github/workflows/deploy-docs.yml`, `bash scripts/verify-github-workflows.sh`, `pnpm verify:docs`,
  `pnpm verify:workflows`, `pnpm check`, `git diff --check`, and touched-file line-length checks passed.
- `scripts/install.sh` now lists the signed/checksummed release tarball before extraction and rejects empty, absolute,
  or parent-traversing archive member paths.
- `apps/docs/docs/public/install.sh` was synced from the canonical installer so the future public `/install.sh` endpoint
  has the same archive-safety behavior.
- `scripts/verify-install.sh` now signs a malicious tarball containing `../escape` and proves the installer rejects it
  before extraction.
- Install docs, release docs, unreleased notes, and `scripts/verify-docs.sh` now document and guard unsafe archive
  rejection.
- Codebase-memory MCP `index_status` failed with `Transport closed`, so this slice used focused shell reads after the
  required graph attempt. `bash -n scripts/install.sh apps/docs/docs/public/install.sh scripts/verify-install.sh
  scripts/verify-docs.sh`, `pnpm verify:install`, `pnpm verify:docs`,
  `cmp -s scripts/install.sh apps/docs/docs/public/install.sh`, `pnpm verify:scripts`, `pnpm check`,
  `git diff --check`, and touched-file line-length checks passed.
- `.github/workflows/release.yml` now validates the resolved release tag as a git tag name, fetches tags, resolves
  `refs/tags/<tag>^{commit}`, and checks out the commit detached in both the `build-linux` and `publish-release` jobs.
  Manual dispatch and tag-push releases now build, publish, and collect evidence from the resolved tag source instead
  of the ambient workflow checkout.
- The build job no longer passes `--skip-tag` to `scripts/verify-release-readiness.sh`, so the readiness step checks
  that the selected release tag points at the detached checkout before package builds run.
- `scripts/verify-github-workflows.sh` now requires both release jobs to keep the tag-format check, tag commit
  resolution, detached checkout steps, and absence of `--skip-tag`.
- Release docs, unreleased notes, and `scripts/verify-docs.sh` now document and guard the release workflow tag-source
  contract.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this slice used focused
  shell reads after the required graph attempts. `bash -n scripts/verify-github-workflows.sh scripts/verify-docs.sh`,
  Ruby YAML parsing for `.github/workflows/release.yml`, `bash scripts/verify-github-workflows.sh`,
  `pnpm verify:docs`, `pnpm verify:workflows`, `pnpm check`, `git diff --check`, touched-file line-length checks,
  `gsd-sdk query roadmap.analyze`, and `gsd-sdk query init.milestone-op` passed.
- `.github/workflows/release.yml` and `scripts/verify-release-readiness.sh` now require v-prefixed semver release tags
  without path separators. Tags like `v0.1.0/preview` are rejected before the release workflow derives release-note,
  evidence-directory, or evidence-archive paths from the tag.
- `scripts/verify-scripts.sh` now includes a negative smoke proving `scripts/verify-release-readiness.sh` rejects a
  path-like release tag even when GitHub, tag-existence, clean-git, and candidate-note gates are skipped.
- `scripts/verify-github-workflows.sh` now requires both release jobs to retain the semver/path-separator rejection
  before tag checkout.
- Release docs, unreleased notes, and `scripts/verify-docs.sh` now document and guard the semver tag contract.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this slice used focused
  shell reads after the required graph attempts. `bash -n scripts/verify-release-readiness.sh scripts/verify-scripts.sh
  scripts/verify-github-workflows.sh scripts/verify-docs.sh`, direct tag-regex smoke, expected-failure readiness smoke
  for `v0.1.0/preview`, Ruby YAML parsing for `.github/workflows/release.yml`,
  `bash scripts/verify-github-workflows.sh`, `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm check`,
  `git diff --check`, touched-file line-length checks, and `gsd-sdk query roadmap.analyze` passed.
- `scripts/collect-release-evidence.mjs` now rejects non-semver or path-like release tags before it prints command
  plans or writes evidence files.
- `scripts/verify-release-evidence.mjs` now rejects non-semver or path-like release tags in both `--release-tag`
  expectations and `release.tag` manifest values.
- `scripts/verify-scripts.sh` now includes negative smokes for path-like collector tags, path-like expected verifier
  tags, and path-like manifest tags.
- Release docs, unreleased notes, and `scripts/verify-docs.sh` now document and guard that final release evidence uses
  the same v-prefixed semver tag contract as the release workflow and readiness preflight.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this slice used focused
  shell reads after the required graph attempts. `node --check scripts/collect-release-evidence.mjs
  scripts/verify-release-evidence.mjs`, `bash -n scripts/verify-scripts.sh scripts/verify-docs.sh`,
  expected-failure collector smoke for `v0.1.0/preview`, prerelease command-plan smoke for `v0.1.0-rc.1`,
  `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm check`, `git diff --check`, touched-file line-length checks, and
  `gsd-sdk query roadmap.analyze` passed.
- `scripts/verify-release-readiness.sh`, `scripts/verify-published-release.sh`,
  `scripts/collect-release-evidence.mjs`, and `scripts/verify-release-evidence.mjs` now require release repository
  identities in plain `OWNER/REPO` form.
- URL-like repository values, spaces, and extra path segments are rejected before GitHub access, command planning,
  manifest acceptance, or final evidence verification.
- `scripts/verify-scripts.sh` now includes negative smokes for malformed repository identities across readiness,
  published-release verification, release evidence collection, expected evidence verification, and manifest evidence
  verification.
- Release docs, unreleased notes, and `scripts/verify-docs.sh` now document and guard the repository identity contract.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this slice used focused
  shell reads after the required graph attempts. `bash -n scripts/verify-release-readiness.sh
  scripts/verify-published-release.sh scripts/verify-scripts.sh scripts/verify-docs.sh`,
  `node --check scripts/collect-release-evidence.mjs scripts/verify-release-evidence.mjs`, targeted negative smokes
  for URL-like and path-like repositories, `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm check`,
  `git diff --check`, touched-file line-length checks, and `gsd-sdk query roadmap.analyze` passed.
- `scripts/verify-published-release.sh` now derives the expected release evidence tag from the single
  `loopwire-release-evidence-<tag>.tar.gz` asset when `--release-dir --require-release-evidence` is used without an
  explicit `--tag`.
- The extracted `release-evidence.json` must match that archive-name tag, so local signed release-directory smokes
  cannot silently verify an evidence archive whose filename and manifest disagree.
- `pnpm verify:scripts` now proves the no-`--tag` local release-directory verifier path passes when the evidence
  archive name and manifest agree, and rejects archive-name/manifest tag drift.
- Release docs, unreleased notes, and `scripts/verify-docs.sh` now document and guard the local evidence archive tag
  binding.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this slice used focused
  shell reads after the required graph attempts. `bash -n scripts/verify-published-release.sh scripts/verify-scripts.sh
  scripts/verify-docs.sh`, `node --check scripts/collect-release-evidence.mjs scripts/verify-release-evidence.mjs`,
  `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm check`, `pnpm detect:audio`, `git diff --check`, touched-file
  line-length checks, `gsd-sdk query roadmap.analyze`, and `gsd-sdk query init.milestone-op` passed.
- `scripts/verify-release-evidence.mjs` now requires `docs-live-smoke` command rows to match the `docsLive` base URL
  or hostname plus remote prefix recorded in `release-evidence.json`, in addition to the existing direct script and
  public installer checks.
- `pnpm verify:scripts` first failed because the old verifier accepted a `docs-live-smoke` command for
  `wrong-docs.example.test`, then passed after the live-docs deployment binding was added.
- Release docs, unreleased notes, and `scripts/verify-docs.sh` now document and guard the final live-docs evidence
  binding.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this slice used focused
  shell reads after the required graph attempts. `node --check scripts/verify-release-evidence.mjs
  scripts/collect-release-evidence.mjs`, `bash -n scripts/verify-scripts.sh scripts/verify-docs.sh`,
  `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm check`, `pnpm detect:audio`, `git diff --check`, touched-file
  line-length checks, `gsd-sdk query roadmap.analyze`, and `gsd-sdk query init.milestone-op` passed.
- `scripts/verify-release-evidence.mjs` now accepts `--public-key` and rejects evidence whose `release.publicKey`
  differs from the expected signing public key.
- `scripts/verify-published-release.sh --require-release-evidence` forwards the same public key it used to verify
  `SHA256SUMS.sig` into release evidence verification, binding public evidence archives to the release asset trust
  root.
- `pnpm verify:scripts` first failed because the old verifier accepted evidence and a `published-release-smoke` command
  using `packaging/other-release-signing-public.pem`, then passed after public-key binding was added and the local
  signed release-directory fixture was rebound to its generated temp public key.
- Release docs, unreleased notes, and `scripts/verify-docs.sh` now document and guard the final public-key evidence
  binding.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this slice used focused
  shell reads after the required graph attempts.
- `node --check scripts/verify-release-evidence.mjs scripts/collect-release-evidence.mjs`,
  `bash -n scripts/verify-published-release.sh scripts/verify-scripts.sh scripts/verify-docs.sh`,
  `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm check`, `pnpm detect:audio`, `git diff --check`, touched-file
  line-length checks, `gsd-sdk query roadmap.analyze`, and `gsd-sdk query init.milestone-op` passed after the public-key
  binding update.
- `scripts/verify-release-evidence.mjs` now accepts `--git-head` and rejects evidence whose `git.head` differs from the
  expected release commit.
- The release workflow now exports the resolved tag commit as `LOOPWIRE_RELEASE_COMMIT`, verifies collected release
  evidence against that SHA and the release public key, and passes the same SHA into
  `scripts/verify-published-release.sh --require-release-evidence`.
- `pnpm verify:scripts` first failed because the old verifier ignored `--git-head` and accepted a wrong expected commit,
  then passed after git-head binding was added with direct verifier and published-release archive wrong-head negative
  cases.
- Release docs, unreleased notes, `scripts/verify-docs.sh`, and `scripts/verify-github-workflows.sh` now document and
  guard the final git-head evidence binding.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this slice used focused
  shell reads after the required graph attempts.
- `node --check scripts/verify-release-evidence.mjs scripts/collect-release-evidence.mjs`,
  `bash -n scripts/verify-published-release.sh scripts/verify-scripts.sh scripts/verify-docs.sh
  scripts/verify-github-workflows.sh`, `pnpm verify:docs`, `pnpm verify:workflows`, Ruby workflow YAML parsing,
  `pnpm verify:scripts`, `pnpm check`, `git diff --check`, and touched-file line-length checks passed after the
  git-head binding update.
- `scripts/verify-final-release-proof.sh` and `pnpm verify:final-release` now provide one strict final gate for the full
  stop condition: signed published release assets with public evidence archive verification, live docs smoke, strict
  final release evidence, every VM target bundle with installed-release smoke, support-matrix verification, and docs
  contract verification.
- The final proof wrapper supports `--dry-run` so operators can preview the exact proof command plan without touching
  network, release assets, docs URLs, or VM evidence.
- `pnpm verify:final-release -- --repo sandwichfarm/loopwire --tag v0.1.0 --public-key
  packaging/release-signing-public.pem --git-head 0123456789abcdef0123456789abcdef01234567 --release-evidence-dir
  .release-evidence/v0.1.0-published --docs-hostname docs.example.test --docs-remote-prefix preview --vm-evidence-root
  .vm/evidence --dry-run` passed and printed published-release, live-docs, release-evidence, all nine VM evidence,
  support-matrix, and docs-contract commands.
- `pnpm verify:scripts`, `pnpm verify:docs`, `bash -n` for the final proof wrapper and script/doc guards, touched-file
  line-length checks, and `git diff --check` passed after the final proof wrapper update.
- `scripts/verify-support-matrix.mjs` now accepts `--matrix` and `--require-published-release`; final proof passes the
  release support matrix path and requires installed-release smoke for every `Verified` row.
- `pnpm verify:scripts` now proves support-matrix strict mode rejects a forced `Verified` row whose evidence bundle has
  no `published-release-smoke`, then accepts the same target after the release-smoke row and log are present.
- `pnpm verify:final-release -- --repo sandwichfarm/loopwire --tag v0.1.0 --public-key
  packaging/release-signing-public.pem --git-head 0123456789abcdef0123456789abcdef01234567 --release-evidence-dir
  .release-evidence/v0.1.0-published --docs-hostname docs.example.test --docs-remote-prefix preview --vm-evidence-root
  .vm/evidence --support-matrix apps/docs/docs/guide/support-matrix.md --dry-run` passed and printed support-matrix
  verification with `--require-published-release`.
- `bash -n scripts/verify-final-release-proof.sh scripts/verify-scripts.sh scripts/verify-docs.sh`,
  `node --check scripts/verify-support-matrix.mjs`, touched-file line-length checks, `pnpm verify:scripts`,
  `pnpm verify:docs`, `pnpm check`, `pnpm detect:audio`, `git diff --check`, `gsd-sdk query roadmap.analyze`, and
  `gsd-sdk query init.milestone-op` passed after the strict support-matrix update.
- Codebase-memory MCP `index_status` and `index_repository` failed with `Transport closed`, so this slice used focused
  shell reads after the required graph attempts.
- `scripts/vm-matrix.sh evidence-status` and `pnpm vm:evidence-status` now report `status=missing`, `status=invalid`,
  or `status=verified` for target-scoped VM evidence bundles under an evidence root. The command prints verifier
  commands, collector handoffs for missing targets, and a checked/verified/missing/invalid summary without promoting
  support-matrix rows.
- `pnpm verify:scripts` now covers missing evidence status, pnpm argument forwarding, unknown target rejection,
  `--all`/`--target` rejection, a verified fixture bundle, strict-mode rejection before `published-release-smoke`, and
  strict-mode success after that smoke row exists.
- `bash -n scripts/vm-matrix.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, package JSON parsing, direct and
  pnpm missing-evidence smokes, touched-file line-length checks, `pnpm verify:scripts`, `pnpm verify:docs`,
  `pnpm verify:vm`, `pnpm check`, `pnpm detect:audio`, all-target `evidence-status` against an empty temp root,
  `git diff --check`, `gsd-sdk query roadmap.analyze`, and `gsd-sdk query init.milestone-op` passed after the VM
  evidence status update.
- Codebase-memory MCP `index_status` failed with `Transport closed`, so this slice used focused shell reads after the
  required graph attempt.
- `scripts/promote-vm-evidence.mjs` now accepts `--all` and `--evidence-root`, verifies each existing target-scoped
  evidence bundle before promotion, reports missing evidence directories, fails invalid evidence, and writes all
  support-matrix row promotions in one guarded operation.
- `pnpm verify:scripts` now proves all-target promotion dry-run does not mutate the matrix, reports missing target
  evidence, promotes the verified fixture row after release-smoke evidence exists, and rejects invalid
  `--all --target` and `--all --evidence-dir` argument combinations.
- `node --check scripts/promote-vm-evidence.mjs`, `bash -n scripts/verify-scripts.sh scripts/verify-docs.sh`,
  promotion help readback, touched-file line-length checks, `pnpm verify:scripts`, `pnpm verify:docs`,
  `pnpm verify:vm`, `pnpm check`, `pnpm detect:audio`, `git diff --check`, `gsd-sdk query roadmap.analyze`, and
  `gsd-sdk query init.milestone-op` passed after the all-target VM evidence promotion update.
- Codebase-memory MCP `index_status` failed with `Transport closed`, so this slice used focused shell reads after the
  required graph attempt.
- `packages/audio-host` now exports `describeJackPortReadiness`, a shared JACK readiness matcher that reports
  per-requirement readiness, matched ports, missing ports, total port count, and missing port count from the same
  deterministic requirements used by runtime JACK plans.
- Native JACK runtime failures for missing route source, route target, monitor source, or monitor target ports now
  include the exact suggested channel ports before any `jack_connect` mutation.
- `scripts/describe-jack-ports.mjs`, `pnpm jack:verify`, and support-bundle JACK summaries now use the shared
  readiness contract. The support-bundle manifest includes matched and missing ports for each JACK requirement.
- `pnpm --filter @loopwire/audio-host test -- --runInBand`, `pnpm --filter @loopwire/audio-host typecheck`,
  `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm check`, `pnpm detect:audio`, `git diff --check`, touched-file
  line-length checks, `gsd-sdk query roadmap.analyze`, and `gsd-sdk query init.milestone-op` passed after the shared
  JACK readiness update. A temporary `pnpm jack:verify -- --configuration <tmp> --ports-file <tmp> --pretty` fixture
  also passed with normalized Loopwire-owned JACK port names.
- Codebase-memory MCP was unavailable or insufficient (`Transport closed` / oversized output), so this slice used
  focused shell reads after the graph attempts.
- `packages/core/src/dsp-mix.ts` now exports a pure DSP mix planner and renderer. It creates per-output contribution
  plans from configuration routes, applies per-edge gain/mute to supplied planar `Float32Array` source buffers, sums
  active routes without clamping float headroom, reports missing source buffers, and covers one-source-to-many-output
  routing math without host mutation.
- `packages/core/tests/dsp-mix.test.ts` covers contribution planning, independent per-edge gain/mute rendering,
  one-source-to-many-output rendering, unclamped float headroom, peak reporting, and missing source-buffer silence.
- The first `pnpm --filter @loopwire/core test -- --runInBand` run failed because `createDspMixPlan` did not exist.
  After implementation, `pnpm --filter @loopwire/core test -- --runInBand`, `pnpm --filter @loopwire/core typecheck`,
  `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm check`, `pnpm detect:audio`, `git diff --check`, touched-file
  line-length checks, `gsd-sdk query roadmap.analyze`, and `gsd-sdk query init.milestone-op` passed.
- Codebase-memory MCP `search_graph` failed with `Transport closed`, so this slice used focused shell reads after the
  required graph attempt.
- The pure DSP module now exports `listDspSourceRequests` and `runDspMixCycle` so backend adapters have a typed
  execution contract. The cycle runner deduplicates source reads, calls injected source ports, renders the shared DSP
  mix plan, writes every rendered output through injected output ports, can fail closed before writes when required
  sources are missing, and reports output write failures with successful writes preserved.
- `packages/core/tests/dsp-mix.test.ts` now covers source-request deduplication, successful cycle reads/writes,
  fail-closed missing-source behavior, and output write failure reporting.
- The first `pnpm --filter @loopwire/core test -- --runInBand` run failed because `listDspSourceRequests` and
  `runDspMixCycle` did not exist. After implementation, `pnpm --filter @loopwire/core test -- --runInBand`,
  `pnpm --filter @loopwire/core typecheck`, `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm check`,
  `pnpm detect:audio`, `git diff --check`, touched-file line-length checks, `gsd-sdk query roadmap.analyze`, and
  `gsd-sdk query init.milestone-op` passed.
- Codebase-memory MCP `search_graph` failed with `Transport closed`, so this slice used focused shell reads after the
  required graph attempt.
- `packages/audio-host/src/dsp-adapter.ts` now exposes an injected DSP graph adapter that consumes the core DSP cycle
  runner through runtime ports. It dry-runs source/output plans, renders and writes output buffers in apply mode,
  fails closed before writes when required source buffers are missing, verifies rendered outputs through a supplied
  verifier, and clears outputs during rollback/unload.
- `packages/audio-host/tests/dsp-adapter.test.ts` covers dry-run planning without buffer IO, apply-mode render/write,
  fail-closed missing-source behavior, required verifier wiring, verifier mismatch reporting, and rollback clearing.
- `packages/audio-host/package.json` now declares the inward workspace dependency on `@loopwire/core` and builds core
  before audio-host build/test/typecheck so direct package checks work from a clean checkout.
- `apps/docs/docs/developer/architecture.md`, `apps/docs/docs/guide/backends.md`, and
  `apps/docs/docs/release-notes/unreleased.md` now document the injected audio-host DSP graph adapter while still
  stating that live backend DSP insertion remains unimplemented.
- The first `pnpm verify:docs` reruns failed on line-wrapped/case-sensitive guard phrases after the documentation
  update. After correcting the prose, `pnpm --filter @loopwire/audio-host test -- --runInBand`,
  `pnpm --filter @loopwire/audio-host typecheck`, `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm check`,
  `pnpm detect:audio`, `git diff --check`, source/docs touched-file line-length checks,
  `gsd-sdk query roadmap.analyze`, and `gsd-sdk query init.milestone-op` passed.
- Codebase-memory MCP `search_graph` failed with `Transport closed`, so this slice used focused shell reads after the
  required graph attempt.
- Desktop route-control status, route gain locking, and live-apply preflight now consume detected backend mixing
  semantics instead of hardcoded backend names. This keeps current PipeWire/JACK link-only behavior intact while giving
  graph-edge-capable reports a tested path to unlock route gain and skip link-only preflight blockers.
- `apps/desktop/src/route-control-semantics.test.ts` now covers synthetic graph-edge PipeWire semantics and confirms
  route gain editing is not locked when a detected report supports per-edge gain.
- `apps/desktop/src/live-apply-preflight.test.ts` now covers graph-edge PipeWire reports that keep source-port blockers
  but drop non-unity gain blockers, plus graph-edge JACK reports with virtual-device creation that skip the old
  link-only gain and missing Loopwire-owned port blockers.
- `apps/docs/docs/developer/architecture.md`, `apps/docs/docs/guide/backends.md`,
  `apps/docs/docs/guide/configurations.md`, and `apps/docs/docs/release-notes/unreleased.md` now document that the
  desktop consumes detected backend mixing semantics without claiming live backend DSP insertion.
- The first `pnpm --filter @loopwire/desktop test -- --runInBand` run failed with three expected red assertions because
  route-control helpers ignored graph-edge capability reports. After implementation,
  `pnpm --filter @loopwire/desktop test -- --runInBand`, `pnpm --filter @loopwire/desktop typecheck`,
  `pnpm --filter @loopwire/desktop build`, `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm check`,
  `pnpm detect:audio`, `git diff --check`, source/docs/GSD touched-file line-length checks,
  `gsd-sdk query roadmap.analyze`, and `gsd-sdk query init.milestone-op` passed.
- Codebase-memory MCP `search_graph` failed with `Transport closed`, so this slice used focused shell reads after the
  required graph attempt.
- DSP runtime rollback now restores the rollback configuration instead of only clearing outputs. `unload` remains
  clear-only, while `rollback` clears the last written DSP output ids when a clear port exists and then re-renders the
  rollback configuration through injected source/output ports.
- `packages/audio-host/tests/dsp-adapter.test.ts` now exercises the DSP adapter through
  `applyConfigurationSwitch`, proving a failed stream switch rolls back to the previous `studio` configuration and
  writes the restored `recorder` mix. It also covers direct rollback after a successful DSP apply.
- `apps/docs/docs/developer/architecture.md`, `apps/docs/docs/guide/backends.md`, and
  `apps/docs/docs/release-notes/unreleased.md` now distinguish clear-on-unload from restore-on-rollback behavior while
  still stating that live host capture/playback injection remains unimplemented.
- The first `pnpm --filter @loopwire/audio-host test -- --runInBand` run failed because rollback only cleared outputs
  and did not restore the previous DSP mix through the core switch transaction. After implementation,
  `pnpm --filter @loopwire/audio-host test -- --runInBand`, `pnpm --filter @loopwire/audio-host typecheck`,
  `pnpm --filter @loopwire/core test -- --runInBand`, `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm check`,
  `pnpm detect:audio`, `git diff --check`, source/docs/GSD touched-file line-length checks,
  `gsd-sdk query roadmap.analyze`, and `gsd-sdk query init.milestone-op` passed.
- Codebase-memory MCP `search_graph` failed with `Transport closed`, so this slice used focused shell reads after the
  required graph attempt.
- `packages/audio-host/src/dsp-adapter.ts` now exposes `createDspConfigurationRuntimeAdapter`, a first-class
  `ConfigurationRuntimeAdapter` wrapper around the injected DSP graph adapter. This lets core startup re-apply and
  configuration switch transactions call the DSP adapter through the exact core runtime contract instead of relying on
  structural method compatibility.
- `packages/audio-host/tests/dsp-adapter.test.ts` now uses the explicit wrapper for `applyConfigurationSwitch`
  rollback and adds `verifyStartupConfiguration` coverage proving startup re-applies the active stream configuration,
  writes the rendered `broadcast` output, and verifies that output through the injected verifier.
- The first `pnpm --filter @loopwire/audio-host test -- --runInBand` run for this slice failed because
  `createDspConfigurationRuntimeAdapter` did not exist. After implementation, the same command passed with 5 files and
  89 tests.
- `apps/docs/docs/developer/architecture.md`, `apps/docs/docs/guide/backends.md`, and
  `apps/docs/docs/release-notes/unreleased.md` now document the first-class DSP configuration runtime adapter wrapper
  while still stating that live backend DSP insertion remains unimplemented.
- Final validation for this slice passed: `pnpm --filter @loopwire/audio-host test -- --runInBand`,
  `pnpm --filter @loopwire/audio-host typecheck`, `pnpm --filter @loopwire/core test -- --runInBand`,
  `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm check`, `pnpm detect:audio`, `git diff --check`, touched-file
  line-length checks, `gsd-sdk query roadmap.analyze`, and `gsd-sdk query init.milestone-op`.
- Codebase-memory MCP `search_graph` failed with `Transport closed`, so this slice used focused shell reads after the
  required graph attempt.
- `packages/audio-host/src/jack-adapter.ts` now accepts an injected `JackVirtualPortProvider`. When all missing JACK
  readiness requirements are Loopwire-owned ports, the runtime asks the provider to ensure those ports, re-runs
  `jack_lsp`, and proceeds only if the expected ports appear before `jack_connect`.
- `packages/audio-host/tests/jack-adapter.test.ts` now proves the provider path by starting with no Loopwire-owned JACK
  ports, invoking the provider, re-listing ports, and connecting after the expected `capture_*` and `playback_*` ports
  appear. It also proves fail-closed behavior when a provider claims success but the required ports are still absent.
- `apps/docs/docs/developer/architecture.md`, `apps/docs/docs/guide/backends.md`, and
  `apps/docs/docs/release-notes/unreleased.md` now document the injected JACK virtual port provider boundary while
  still stating that the shipped desktop path does not bundle a real JACK client provider.
- The first `pnpm --filter @loopwire/audio-host test -- --runInBand` run for this slice failed because the adapter did
  not consult a virtual-port provider. After implementation, the same command passed with 5 files and 91 tests.
- Final validation for this slice passed: `pnpm --filter @loopwire/audio-host test -- --runInBand`,
  `pnpm --filter @loopwire/audio-host typecheck`, `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm check`,
  `pnpm detect:audio`, `git diff --check`, touched-file line-length checks, `gsd-sdk query roadmap.analyze`, and
  `gsd-sdk query init.milestone-op`.
- Codebase-memory MCP `search_graph` failed with `Transport closed`, so this slice used focused shell reads after the
  required graph attempt.
- `packages/audio-host/src/jack-adapter.ts` now exports `createJackVirtualPortCommandProvider`, which adapts any
  command runner to the injected `JackVirtualPortProvider` contract. It passes stable
  `ensure --configuration-id ... --requirement ... --port ...` arguments and returns the provider's first stdout or
  stderr line in the runtime result.
- `scripts/restore-background.mjs` now accepts `--jack-provider-command` and `--jack-provider-timeout-ms`. When JACK is
  the selected restore backend, those flags wrap the command as the injected provider before startup restore applies
  and verifies the active configuration.
- `packages/audio-host/tests/jack-adapter.test.ts` covers command argument generation and failure reporting. The first
  `pnpm --filter @loopwire/audio-host test -- --runInBand` run for this slice failed because
  `createJackVirtualPortCommandProvider` did not exist. After implementation, the same command passed with 5 files and
  93 tests.
- `apps/docs/docs/guide/start-on-boot.md`, `apps/docs/docs/guide/backends.md`, and
  `apps/docs/docs/release-notes/unreleased.md` now document the command-backed JACK provider path while still requiring
  an external or future bundled provider command.
- Final validation for this slice passed: `pnpm --filter @loopwire/audio-host test -- --runInBand`,
  `pnpm --filter @loopwire/audio-host typecheck`, `node --check scripts/restore-background.mjs`,
  `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm check`, `pnpm detect:audio`, `git diff --check`, touched-file
  line-length checks, `gsd-sdk query roadmap.analyze`, and `gsd-sdk query init.milestone-op`.
- Codebase-memory MCP `search_graph` failed with `Transport closed`, so this slice used focused shell reads after the
  required graph attempt.
- `scripts/manage-autostart.sh` now renders both source-checkout and packaged background systemd units with the same
  restore runtime options: `--state-file`, `--mode`, PulseAudio retry flags, and optional
  `--jack-provider-command`/`--jack-provider-timeout-ms`.
- `package.json` now exposes `pnpm vm:launch`, which forwards to the existing dry-run-first QEMU launch planner for
  VM targets without requiring image files or writing `.vm/run` state.
- `scripts/verify-autostart.sh`, `scripts/verify-scripts.sh`, and `scripts/verify-docs.sh` now guard the new boot
  restore and VM launch contracts.
- The first `pnpm verify:autostart` run for this slice failed because `manage-autostart.sh` rejected
  `--jack-provider-command`. After implementation, `pnpm verify:autostart` passed.
- Final validation for this slice passed: `bash -n scripts/manage-autostart.sh scripts/verify-autostart.sh
  scripts/verify-docs.sh scripts/verify-scripts.sh scripts/vm-matrix.sh`,
  `pnpm vm:launch -- --target arch-hyprland-pipewire --image /operator/images/arch.qcow2 --ssh-port 2322`,
  `pnpm verify:autostart`, `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm verify:vm`, `pnpm check`,
  `pnpm detect:audio`, `git diff --check`, touched-file line-length checks, `gsd-sdk query roadmap.analyze`, and
  `gsd-sdk query init.milestone-op`.
- The `pnpm vm:launch` dry-run wrote no `.vm/run` state. No real JACK provider binary was executed, and no live VM,
  host audio mutation, package install, public release, tag push, secret write, Bunny deployment, live URL smoke, or
  support matrix promotion was performed.
- Codebase-memory MCP `search_graph` failed with `Transport closed`, so this slice used focused shell reads after the
  required graph attempt.
- `scripts/vm-matrix.sh render-launch-plan` now prints or writes target-scoped TSV rows for dry-run QEMU launch
  planning. Each row includes the target id, operator-owned image path placeholder, image format, firmware cell, SSH
  port, memory, CPU count, dry-run launch command, and matching evidence-pull command.
- `package.json` now exposes `pnpm vm:render-launch-plan`, and `apps/docs/docs/developer/vm-matrix.md` documents the
  all-target flow beside `pnpm vm:launch`, `pnpm vm:render-ssh-plan`, and `pnpm vm:collect-matrix`.
- `scripts/verify-scripts.sh` now guards selected-target launch-plan output, all-target package-script forwarding,
  output-file rendering, deterministic AArch64 port assignment, invalid resource rejection, and exhausted port-range
  rejection. `scripts/verify-docs.sh` guards the docs/release-note contract.
- Validation for this slice passed before the broader gate run: `bash -n scripts/vm-matrix.sh scripts/verify-scripts.sh
  scripts/verify-docs.sh`, `pnpm vm:render-launch-plan -- --all --image-root /operator/images --start-port 2600`,
  `pnpm verify:scripts`, `pnpm verify:docs`, and `pnpm verify:vm`.
- No VM was launched, no `.vm/run` state was written, no image was downloaded, and no support matrix row was promoted.
- Codebase-memory MCP `search_graph` failed with `Transport closed`, so this slice used focused shell reads after the
  required graph attempt.
- `scripts/collect-release-evidence.mjs` now includes `vm-launch-plan.tsv` in every release evidence profile and stores
  `release.vmLaunchPlan` metadata for the image root plus start port used to render the plan.
- `scripts/verify-release-evidence.mjs --require-vm-launch-plan` now requires a successful `vm-launch-plan` command row,
  verifies it invoked `bash scripts/vm-matrix.sh render-launch-plan --all`, validates one TSV row for every
  `vm/targets.tsv` target, and checks that each row pairs the dry-run launch command with
  `scripts/collect-vm-evidence-ssh.sh --execute` for the same target and SSH port.
- `scripts/verify-final-release-proof.sh` now passes `--require-vm-launch-plan`, so final public release proof cannot
  pass with VM evidence bundles but no matrix-wide launch handoff.
- `scripts/verify-scripts.sh` now includes positive and negative fixtures for launch-plan evidence: missing command,
  echo-disguised command, and incomplete target rows are rejected.
- `apps/docs/docs/developer/release.md`, `apps/docs/docs/release-notes/unreleased.md`, and
  `scripts/verify-docs.sh` now document and guard the final release VM launch-plan evidence contract.
- Validation for this slice passed before the broader gate run: `node --check scripts/collect-release-evidence.mjs`,
  `node --check scripts/verify-release-evidence.mjs`, `bash -n scripts/verify-final-release-proof.sh
  scripts/verify-scripts.sh scripts/verify-docs.sh`, `pnpm verify:scripts`, and `pnpm verify:docs`.
- Final validation also passed: `pnpm verify:vm`, `pnpm check`, `pnpm detect:audio`, `git diff --check`,
  touched-file line-length checks, `gsd-sdk query roadmap.analyze`, and `gsd-sdk query init.phase-op 12`.
- No public release, tag push, secret write, Bunny deployment, live URL smoke, VM launch, `.vm/run` write, image
  download, or support matrix promotion was performed.
- Codebase-memory MCP `search_graph` failed with `Transport closed`, so this slice used focused shell reads after the
  required graph attempt.
- `scripts/vm-matrix.sh render-runbook` now emits a markdown VM evidence runbook for one target or the whole matrix.
  The runbook includes host setup and doctor commands, cloud-init rendering, deterministic dry-run launch commands,
  target-scoped SSH evidence-pull commands, local evidence verification, dry-run support-matrix promotion commands,
  and AArch64 firmware reminders.
- `package.json` now exposes `pnpm vm:render-runbook`. The generated runbook is non-mutating unless an operator runs
  the printed `--execute` commands or chooses to write it with `--output`.
- `scripts/verify-scripts.sh` now covers target and all-target runbook rendering, output-file writing, deterministic
  AArch64 port assignment, target-scoped local evidence paths, AArch64 firmware guidance, and invalid argument
  rejection for `--all` plus `--target` and exhausted port ranges.
- `apps/docs/docs/developer/vm-matrix.md`, `apps/docs/docs/release-notes/unreleased.md`, and
  `scripts/verify-docs.sh` now document and guard the operator runbook workflow for other systems.
- Validation for this slice passed before the broader gate run: `bash -n scripts/vm-matrix.sh scripts/verify-scripts.sh
  scripts/verify-docs.sh`, touched-file line-length checks, direct `pnpm vm:render-runbook -- --target
  arch-hyprland-pipewire --image-root /operator/images --start-port 2600` readback, `pnpm verify:scripts`, and
  `pnpm verify:docs`.
- Final validation also passed: `pnpm verify:vm`, `pnpm check`, `pnpm detect:audio`, `git diff --check`,
  touched-file line-length checks, `gsd-sdk query roadmap.analyze`, and `gsd-sdk query init.phase-op 12`.
- No public release, tag push, secret write, Bunny deployment, live URL smoke, VM launch, `.vm/run` write, image
  download, package installation, or support matrix promotion was performed.
- Codebase-memory MCP `search_graph` failed with `Transport closed`, so this slice used focused shell reads after the
  required graph attempt.
- `CommandRunOptions` and the Node command runner now support optional stdin input while preserving existing
  command-runner callers.
- `@loopwire/audio-host` now exposes `createDspRuntimeCommandPorts`, which maps DSP runtime ports to a provider command
  with stable `read-source`, `write-output`, `verify-output`, and `clear-output` operations. Source buffers are read as
  JSON stdout; rendered buffers are sent as JSON stdin for write and verify commands.
- The command-backed DSP provider path is covered through `createDspGraphRuntimeAdapter` apply and verify tests,
  including stable command args, timeout forwarding, JSON stdin payloads, provider verification failures, and malformed
  source-buffer fail-closed behavior before writes.
- `apps/docs/docs/guide/backends.md`, `apps/docs/docs/developer/architecture.md`,
  `apps/docs/docs/release-notes/unreleased.md`, and `scripts/verify-docs.sh` now document and guard the DSP provider
  protocol while keeping the live PipeWire/JACK host-adapter gap explicit.
- Validation passed: `pnpm --filter @loopwire/audio-host test`, `pnpm --filter @loopwire/audio-host typecheck`,
  `bash -n scripts/verify-docs.sh`, touched-file line-length checks, `git diff --check`, `pnpm verify:docs`,
  `pnpm verify:scripts`, `pnpm detect:audio`, and full `pnpm check`.
- `pnpm detect:audio` still reports native PipeWire as link-only with `supportsPerEdgeGain: false`, PulseAudio
  compatibility as stream-level, ALSA as diagnostics-only, and JACK unavailable because `jack_lsp` is missing.
- No live host audio mutation, public release, tag push, secret write, Bunny deployment, live URL smoke, VM launch,
  `.vm/run` write, image download, package installation, or support matrix promotion was performed.
- Codebase-memory MCP `search_graph` failed with `Transport closed`, so this slice used focused shell reads after the
  required graph attempt.
- `scripts/restore-background.mjs` now accepts explicit `--backend dsp` with `--dsp-provider-command`,
  `--dsp-provider-timeout-ms`, and optional `--dsp-frame-count`. It routes startup apply/verify through the
  command-backed DSP graph adapter and rejects ambiguous provider combinations.
- `scripts/manage-autostart.sh` can render the same DSP provider flags for source-checkout and packaged user systemd
  restore, appending `--backend dsp` only when a DSP provider command is configured.
- `scripts/verify-autostart.sh` now creates a temporary DSP provider command and proves live background restore calls
  `read-source`, `write-output`, and `verify-output` with stable arguments and JSON payload flow.
- `scripts/verify-scripts.sh` now guards restore-background help and parse failures for missing DSP providers, invalid
  DSP provider timeouts, invalid frame counts, and mixed DSP/JACK provider flags.
- `apps/docs/docs/guide/start-on-boot.md`, `apps/docs/docs/release-notes/unreleased.md`, and `scripts/verify-docs.sh`
  now document and guard the explicit background DSP provider restore workflow.
- Additional validation passed: `node --check scripts/restore-background.mjs`,
  `bash -n scripts/manage-autostart.sh scripts/verify-autostart.sh scripts/verify-scripts.sh scripts/verify-docs.sh`,
  touched-file line-length checks, `pnpm verify:autostart`, `pnpm verify:scripts`, `pnpm verify:docs`,
  `pnpm detect:audio`, `git diff --check`, and full `pnpm check`.
- No bundled DSP provider binary was added. No public release, tag push, secret write, Bunny deployment, live URL smoke,
  VM launch, `.vm/run` write, image download, package installation, support matrix promotion, or real host audio
  mutation was performed.
- `scripts/setup-github-secrets.sh` now accepts `--release-public-key-file FILE`, parses the release private key, parses
  the release public key when supplied, derives the public key from the private key, and fails before dry-run output or
  `gh secret set` when the pair does not match.
- `scripts/verify-scripts.sh` now creates a temporary RSA key pair for secret-helper dry-run coverage, asserts the
  helper help includes `--release-public-key-file`, rejects mismatched release key pairs, and rejects invalid release
  private key material.
- `apps/docs/docs/developer/release.md`, `apps/docs/docs/release-notes/unreleased.md`, and `scripts/verify-docs.sh`
  now document and guard the key-pair validation ceremony.
- Focused validation passed: `bash -n scripts/setup-github-secrets.sh scripts/verify-scripts.sh
  scripts/verify-docs.sh`, matching-key secret-helper dry-run, mismatched-key secret-helper failure, touched-file
  line-length checks, `pnpm verify:scripts`, `pnpm verify:docs`, `git diff --check`, `pnpm detect:audio`, and full
  `pnpm check`.
- No real project release key was generated, no public key was committed, no GitHub secret was written, and no public
  release, tag push, Bunny deployment, live URL smoke, VM launch, package installation, or support matrix promotion was
  performed.
- `scripts/describe-dsp-provider.mjs` now describes the bounded `read-source`, `write-output`, and `verify-output`
  operations required by a Loopwire configuration. It is read-only by default and requires `--execute` plus
  `--provider-command` before invoking a provider.
- `package.json` now exposes `pnpm dsp:plan` for the read-only operation plan and `pnpm dsp:verify` for explicit
  provider execution through the DSP graph adapter apply/verify path.
- `scripts/verify-scripts.sh` now covers DSP provider help, JSON plan output, TSV plan output, fake-provider apply and
  verify execution, provider command logging, missing-provider rejection, and provider verification failure rejection.
- `README.md`, `apps/docs/docs/guide/backends.md`, `apps/docs/docs/guide/start-on-boot.md`,
  `apps/docs/docs/release-notes/unreleased.md`, and `scripts/verify-docs.sh` now document and guard the provider
  preflight workflow before boot restore.
- Focused validation passed: `node --check scripts/describe-dsp-provider.mjs`, `bash -n scripts/verify-scripts.sh
  scripts/verify-docs.sh`, touched-file line-length checks, a temp `pnpm dsp:plan` TSV smoke, a temp
  `pnpm dsp:verify` fake-provider execute smoke, `pnpm verify:scripts`, `pnpm verify:docs`, `git diff --check`,
  `pnpm detect:audio`, and full `pnpm check`.
- No real DSP provider binary was added. No public release, tag push, secret write, Bunny deployment, live URL smoke,
  VM launch, `.vm/run` write, image download, package installation, support matrix promotion, or real host audio
  mutation was performed.
- `scripts/collect-release-evidence.mjs` now records a full-profile required `dsp-provider-plan` row and
  `release.dspProviderPlan` metadata. Quick profile can include the same row with `--require-dsp-provider-plan`.
- `scripts/collect-dsp-provider-plan.sh` builds the core/audio-host packages quietly, runs
  `scripts/describe-dsp-provider.mjs` against `scripts/fixtures/dsp-provider-configuration.json`, and emits only the
  read-only TSV plan rows needed by release evidence.
- `scripts/verify-release-evidence.mjs --require-dsp-provider-plan` now requires a successful DSP plan command,
  validates that it invokes `bash scripts/collect-dsp-provider-plan.sh`, binds the configuration path and frame count to
  `release-evidence.json`, rejects `--execute`, and verifies `dsp-provider-plan.tsv` contains read-source,
  write-output, and verify-output rows for the manifest-bound frame count.
- `scripts/verify-final-release-proof.sh` and `.github/workflows/release.yml` now require the DSP provider plan row in
  final/public release evidence, so a published evidence archive cannot satisfy the final proof while silently dropping
  the command-backed DSP provider contract.
- `scripts/verify-scripts.sh` now covers DSP release-evidence command planning, invalid DSP evidence options, missing
  DSP plan evidence, fake `echo`-style DSP commands, and incomplete DSP TSV rows. `apps/docs/docs/developer/release.md`,
  `apps/docs/docs/release-notes/unreleased.md`, and `scripts/verify-docs.sh` document and guard the new ceremony.
- Focused validation passed: `node --check scripts/collect-release-evidence.mjs`, `node --check
  scripts/verify-release-evidence.mjs`, `bash -n scripts/collect-dsp-provider-plan.sh
  scripts/verify-final-release-proof.sh scripts/verify-scripts.sh scripts/verify-docs.sh
  scripts/verify-github-workflows.sh`, direct `bash scripts/collect-dsp-provider-plan.sh --configuration
  scripts/fixtures/dsp-provider-configuration.json --frame-count 16`, strict temp
  `node scripts/verify-release-evidence.mjs --require-dsp-provider-plan`, `pnpm verify:scripts`, `pnpm verify:docs`,
  `pnpm verify:workflows`, `git diff --check`, and touched-file line-length checks.
- Final validation also passed: full `pnpm check`, `pnpm detect:audio`, `gsd-sdk query roadmap.analyze --format json`,
  and `gsd-sdk query init.phase-op 12 --format json`.
- `pnpm detect:audio` still reports native PipeWire as link-only with `supportsPerEdgeGain: false`, PulseAudio
  compatibility as stream-level, ALSA as diagnostics-only, and JACK unavailable because `jack_lsp` is missing.
- No real DSP provider binary was added. No public release, tag push, secret write, Bunny deployment, live URL smoke,
  VM launch, `.vm/run` write, image download, package installation, support matrix promotion, or real host audio
  mutation was performed.
- `scripts/collect-vm-matrix-evidence.sh` now accepts `--require-all-targets` for final-release VM collection plans.
  It validates the whole TSV before printing collector commands or running SSH, so an incomplete plan fails before any
  guest is touched.
- `scripts/verify-scripts.sh` now covers help text for `--require-all-targets`, positive generated all-target plan
  acceptance, partial-plan rejection, and `--execute` rejection that proves the strict collector does not invoke SSH
  before all-target validation passes.
- `apps/docs/docs/developer/vm-matrix.md`, `apps/docs/docs/release-notes/unreleased.md`, and `scripts/verify-docs.sh`
  now document and guard the final-release collection flag.
- Focused validation passed: `bash -n scripts/collect-vm-matrix-evidence.sh scripts/verify-scripts.sh
  scripts/verify-docs.sh`, generated all-target dry-run collection with `--require-all-targets`, partial-plan rejection
  with no collector command output, touched-file line-length checks, `pnpm verify:scripts`, `pnpm verify:docs`, and
  `git diff --check`.
- Final validation also passed: `pnpm verify:vm`, full `pnpm check`, `pnpm detect:audio`,
  `gsd-sdk query roadmap.analyze --format json`, and `gsd-sdk query init.phase-op 12 --format json`.
- `pnpm detect:audio` still reports native PipeWire as link-only with `supportsPerEdgeGain: false`, PulseAudio
  compatibility as stream-level, ALSA as diagnostics-only, and JACK unavailable because `jack_lsp` is missing.
- No VM was launched, no SSH guest was contacted, no image was downloaded, no public release was created, no release key
  was generated, no GitHub secret was written, no Bunny deployment was performed, and no support matrix row was
  promoted.
- `packages/audio-host/src/dsp-provider-cli.ts` now provides a bundled file-backed `loopwire-dsp-provider` CLI with
  `seed-source`, `read-source`, `write-output`, `verify-output`, and `clear-output` commands. The audio-host package
  exposes it as a package `bin`, and release tarballs now include a top-level `loopwire-dsp-provider` launcher beside
  `loopwire`.
- `scripts/install.sh`, `packaging/aur/PKGBUILD.in`, and `packaging/nix/loopwire-bin.nix` now install
  `loopwire-dsp-provider`. `scripts/package-release.sh`, `scripts/verify-release-artifacts.sh`,
  `scripts/verify-install.sh`, `scripts/verify-packaging.sh`, and `scripts/verify-aur-package.sh` guard the new
  provider artifact path.
- README, install docs, backend docs, start-on-boot docs, release docs, packaging docs, unreleased notes, and
  `scripts/verify-docs.sh` now describe the bundled provider while keeping the live PipeWire/JACK capture/injection gap
  explicit.
- Focused validation passed: `pnpm --filter @loopwire/audio-host test -- dsp-provider-cli.test.ts`,
  `pnpm --filter @loopwire/audio-host typecheck`, `bash -n scripts/package-release.sh scripts/install.sh
  scripts/verify-release-artifacts.sh scripts/verify-packaging.sh scripts/verify-aur-package.sh scripts/verify-docs.sh
  scripts/verify-scripts.sh`, a temp wrapper `pnpm dsp:verify` smoke against
  `scripts/fixtures/dsp-provider-configuration.json`, `pnpm verify:release`, `pnpm verify:packaging`,
  `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm verify:autostart`, `pnpm verify:install`, and
  `pnpm verify:requirements`.
- Final validation passed: full `pnpm check`, `pnpm detect:audio`, `git diff --check`, and touched-file line-length
  checks.
- `pnpm detect:audio` still reports native PipeWire as link-only with `supportsPerEdgeGain: false`, PulseAudio
  compatibility as stream-level, ALSA as diagnostics-only, and JACK unavailable because `jack_lsp` is missing.
- No public release, tag push, Bunny deployment, live URL smoke, VM launch,
  `.vm/run` write, image download, support matrix promotion, live host DSP capture/injection, live JACK provider, or
  real host audio mutation was performed.
- The `LOOPWIRE_RELEASE_PRIVATE_KEY` GitHub secret was written after validating the local private key against
  `packaging/release-signing-public.pem`.
- The live secret readback now shows `LOOPWIRE_RELEASE_PRIVATE_KEY` present for `sandwichfarm/loopwire`; the same
  helper check still fails closed on missing `BUNNY_STORAGE_ZONE` and `BUNNY_ACCESS_KEY`.
- `scripts/setup-github-secrets.sh` now writes secrets through stdin for compatibility with the installed `gh secret
  set` contract, and `scripts/verify-scripts.sh` covers the write path with a fake `gh`.
- Final validation passed: `pnpm verify:scripts`, `pnpm verify:docs`, full `pnpm check`, `pnpm detect:audio`,
  `git diff --check`, added-line length scan, `gsd-sdk query roadmap.analyze --format json`,
  `gsd-sdk query init.phase-op 12 --format json`, and codebase-memory MCP `index_status`.
- `.github/workflows/final-release-proof.yml` now exposes the final proof as a manual GitHub workflow. It validates the
  requested tag commit, downloads release and VM evidence archives from the GitHub Release, verifies the live docs
  target by URL or Bunny hostname/prefix, and runs `scripts/verify-final-release-proof.sh`.
- Workflow validation passed: `pnpm verify:workflows`, `pnpm verify:docs`, Ruby YAML parsing for
  `.github/workflows/final-release-proof.yml`, `git diff --check`, and an added-line length scan.
- `scripts/package-vm-evidence.sh` and `pnpm vm:package-evidence` now package verified operator-collected VM bundles
  into `loopwire-vm-evidence-<tag>.tar.gz` with `vm-evidence/<target>` archive layout. The packager validates the tag,
  resolves targets from `vm/targets.tsv`, and re-runs `scripts/verify-vm-evidence.sh` before writing archive entries.
- Focused validation passed: `bash -n scripts/package-vm-evidence.sh scripts/verify-scripts.sh scripts/verify-docs.sh`,
  a packager dry-run, `pnpm verify:docs`, and `pnpm verify:scripts`.
- `scripts/deploy-docs-bunny.sh` now accepts `--deployment-manifest` / `LOOPWIRE_DOCS_DEPLOYMENT_MANIFEST` and writes
  a non-secret `loopwire.docs-deployment.v1` manifest with storage endpoint, zone, remote prefix, dry-run/live mode,
  file count, required files, upload paths, and SHA-256 checksums. `.github/workflows/deploy-docs.yml` uploads that
  manifest as the `loopwire-docs-deployment` artifact after Bunny.net uploads.
- Focused validation passed: `bash -n scripts/deploy-docs-bunny.sh scripts/verify-scripts.sh scripts/verify-docs.sh
  scripts/verify-github-workflows.sh`, `pnpm verify:workflows`, `pnpm verify:docs`, `pnpm verify:scripts`, and a
  real VitePress build plus Bunny dry-run manifest smoke that wrote a `loopwire.docs-deployment.v1` manifest with 68
  files and `install.sh`.
- `scripts/verify-docs-deployment-manifest.mjs` and `pnpm verify:docs-deployment` now verify
  `loopwire.docs-deployment.v1` artifacts against the built VitePress dist before `.github/workflows/deploy-docs.yml`
  uploads the `loopwire-docs-deployment` artifact. The verifier checks schema, timestamp, storage bindings,
  dry-run/live mode when requested, required files, exact dist inventory, remote-prefix mapping, SHA-256 checksums, path
  safety, and secret-like manifest keys.
- Focused validation passed: `node --check scripts/verify-docs-deployment-manifest.mjs`, `bash -n
  scripts/verify-scripts.sh scripts/verify-docs.sh scripts/verify-github-workflows.sh`, `pnpm verify:workflows`,
  `pnpm verify:docs`, `pnpm verify:scripts`, and real VitePress build dry-run smokes that verified 68-file manifests
  for both `preview` and empty remote prefixes.
- `scripts/verify-release-readiness.sh` now fails preflight if the docs deployment manifest verifier is missing or
  unparsable, if `package.json` does not expose `pnpm verify:docs-deployment`, or if
  `.github/workflows/deploy-docs.yml` does not run the manifest verifier before artifact upload.
- Focused validation passed: `bash -n scripts/verify-release-readiness.sh scripts/verify-scripts.sh
  scripts/verify-docs.sh`, `pnpm verify:docs`, `pnpm verify:workflows`, `pnpm verify:scripts`,
  `pnpm verify:requirements`, and offline `pnpm verify:release-readiness -- --repo sandwichfarm/loopwire --tag
  v0.1.0 --public-key packaging/release-signing-public.pem --skip-gh --skip-tag --skip-clean-git
  --allow-candidate-notes`.
- `scripts/verify-release-readiness.sh` now also fails preflight if the final release proof verifier, VM evidence
  packager, `pnpm verify:final-release`, `pnpm vm:package-evidence`, or
  `.github/workflows/final-release-proof.yml` wiring disappears before the release handoff.
- Focused validation passed: codebase-memory MCP `index_status` reported `home-sandwich-Develop-loopwire` ready,
  `search_graph` located the final release proof and VM evidence packager surfaces, `bash -n
  scripts/verify-release-readiness.sh scripts/verify-scripts.sh scripts/verify-docs.sh` passed, and offline
  `pnpm verify:release-readiness -- --repo sandwichfarm/loopwire --tag v0.1.0 --public-key
  packaging/release-signing-public.pem --skip-gh --skip-tag --skip-clean-git --allow-candidate-notes` passed.
- Full validation passed: `pnpm verify:docs`, `pnpm verify:workflows`, `pnpm verify:scripts`,
  `pnpm verify:requirements`, full `pnpm check`, `pnpm detect:audio`, `git diff --check`, touched-file added-line
  scan, `gsd-sdk query roadmap.analyze --format json`, and `gsd-sdk query init.phase-op 12 --format json`.
  Codebase-memory MCP fast reindex wrote a persistent artifact and `index_status` reported ready with 2,534 nodes and
  5,387 edges. `pnpm detect:audio` reported PipeWire, PulseAudio compatibility, and ALSA available; JACK remains
  unavailable because `jack_lsp` is missing.
- `scripts/verify-final-release-proof.sh --dry-run` now accepts `--plan-output FILE` and writes the same
  published-release, live-docs, strict release-evidence, all-target VM evidence, support-matrix, and docs-contract
  command plan that it prints to stdout. The option is rejected outside dry-run mode so it cannot look like proof from
  a real final release run.
- Focused validation passed: codebase-memory MCP `index_status` reported ready and graph search located the final
  proof, VM evidence, support matrix, Bunny docs, and secret setup surfaces before implementation. `bash -n
  scripts/verify-final-release-proof.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, direct
  `scripts/verify-final-release-proof.sh --dry-run --plan-output <tmp>` smoke, `pnpm verify:docs`, and
  `pnpm verify:scripts` passed.
- Full validation passed: offline `pnpm verify:release-readiness -- --repo sandwichfarm/loopwire --tag v0.1.0
  --public-key packaging/release-signing-public.pem --skip-gh --skip-tag --skip-clean-git --allow-candidate-notes`,
  `pnpm verify:workflows`, `pnpm verify:requirements`, full `pnpm check`, `pnpm detect:audio`, `git diff --check`,
  touched-file added-line scan, `gsd-sdk query roadmap.analyze --format json`, and
  `gsd-sdk query init.phase-op 12 --format json`. Codebase-memory MCP fast reindex wrote a persistent artifact and
  `index_status` reported ready with 2,536 nodes and 5,389 edges. `pnpm detect:audio` reported PipeWire, PulseAudio
  compatibility, and ALSA available; JACK remains unavailable because `jack_lsp` is missing.
- `scripts/setup-github-secrets.sh --check` now prints placeholder-only next steps when required Bunny or release
  signing secrets are missing, while still preserving the underlying `gh secret list` failure when GitHub secret names
  cannot be read. When `BUNNY_PULL_ZONE_HOSTNAME` is absent, the check explains that docs deployment can upload to
  Bunny.net but will skip post-upload live docs smoke.
- Focused validation passed: codebase-memory MCP `index_status` reported ready and graph search located the setup
  helper, release readiness, Bunny deploy, workflow, and docs-live surfaces before implementation. `bash -n
  scripts/setup-github-secrets.sh scripts/verify-scripts.sh scripts/verify-docs.sh`, `pnpm verify:docs`, and
  `pnpm verify:scripts` passed, including fake `gh secret list` cases for all-required-present, missing-required, and
  API failure.
- Full validation passed: offline `pnpm verify:release-readiness -- --repo sandwichfarm/loopwire --tag v0.1.0
  --public-key packaging/release-signing-public.pem --skip-gh --skip-tag --skip-clean-git --allow-candidate-notes`,
  `pnpm verify:workflows`, `pnpm verify:requirements`, full `pnpm check`, `pnpm detect:audio`, `git diff --check`,
  touched-file added-line scan, `gsd-sdk query roadmap.analyze --format json`, and
  `gsd-sdk query init.phase-op 12 --format json`. Codebase-memory MCP fast reindex wrote a persistent artifact and
  `index_status` reported ready with 2,536 nodes and 5,390 edges. `pnpm detect:audio` reported PipeWire, PulseAudio
  compatibility, and ALSA available; JACK remains unavailable because `jack_lsp` is missing.
- `scripts/extract-safe-tar.sh` now validates downloaded final-proof tarballs before extraction, rejecting empty
  archives, absolute paths, parent traversal, duplicate separators, dot path components, and symlink/hardlink members.
  `.github/workflows/final-release-proof.yml` uses it for both release evidence and VM evidence archives before running
  the project-specific final proof verifier.
- Focused validation passed: `bash -n scripts/extract-safe-tar.sh scripts/verify-scripts.sh
  scripts/verify-github-workflows.sh scripts/verify-release-readiness.sh`, `pnpm verify:workflows`,
  `pnpm verify:docs`, `pnpm verify:scripts`, offline `pnpm verify:release-readiness -- --repo sandwichfarm/loopwire
  --tag v0.1.0 --public-key packaging/release-signing-public.pem --skip-gh --skip-tag --skip-clean-git
  --allow-candidate-notes`, and `git diff --check`.
- Full validation passed: full `pnpm check`, `pnpm detect:audio`, and codebase-memory MCP fast reindex/status.
  `index_status` reported ready with 2,547 nodes and 5,404 edges. The graph excludes `scripts/`, so the helper itself
  is covered by shell verification rather than code graph symbols. `pnpm detect:audio` reported PipeWire, PulseAudio
  compatibility, and ALSA available; JACK remains unavailable because `jack_lsp` is missing.
- `scripts/package-vm-evidence.sh` now validates the completed `loopwire-vm-evidence-<tag>.tar.gz` archive with
  `scripts/extract-safe-tar.sh` before reporting success, so VM evidence bundles containing unsafe paths or link members
  fail before the tarball can be attached to a public release.
- Focused validation passed: `bash -n scripts/package-vm-evidence.sh scripts/verify-scripts.sh scripts/verify-docs.sh`,
  `pnpm verify:docs`, `pnpm verify:scripts`, `pnpm verify:workflows`, offline `pnpm verify:release-readiness -- --repo
  sandwichfarm/loopwire --tag v0.1.0 --public-key packaging/release-signing-public.pem --skip-gh --skip-tag
  --skip-clean-git --allow-candidate-notes`, `pnpm verify:requirements`, and `git diff --check`.
- Full validation passed: full `pnpm check`, `pnpm detect:audio`, and codebase-memory MCP fast reindex/status.
  `index_status` reported ready with 2,547 nodes and 5,405 edges. The graph excludes `scripts/` and `apps/docs/`, so
  this slice is covered by shell/docs verification rather than code graph symbols. `pnpm detect:audio` reported
  PipeWire, PulseAudio compatibility, and ALSA available; JACK remains unavailable because `jack_lsp` is missing.
- `scripts/validate-release-asset-name.sh` now validates final proof release and VM evidence asset names before the
  workflow calls `gh release download`, keeping custom dispatch inputs basename-only, tag-bound, evidence-kind-bound,
  and free of traversal, URL syntax, or glob metacharacters.
- Focused validation passed: `bash -n scripts/validate-release-asset-name.sh scripts/verify-release-readiness.sh
  scripts/verify-scripts.sh scripts/verify-github-workflows.sh`, direct positive and negative asset-name validator
  smokes, `pnpm verify:workflows`, `pnpm verify:docs`, offline `pnpm verify:release-readiness -- --repo
  sandwichfarm/loopwire --tag v0.1.0 --public-key packaging/release-signing-public.pem --skip-gh --skip-tag
  --skip-clean-git --allow-candidate-notes`, `pnpm verify:requirements`, added-line length scan, and
  `git diff --check`.
- Full validation passed: `pnpm verify:scripts`, `pnpm check`, `pnpm detect:audio`, GSD roadmap/phase queries, and
  codebase-memory MCP fast reindex/status. `index_status` reported ready with 2,555 nodes and 5,415 edges. The graph
  excludes `scripts/` and `apps/docs/`, so this slice is covered by shell/docs verification rather than code graph
  symbols. `pnpm detect:audio` reported PipeWire, PulseAudio compatibility, and ALSA available; JACK remains
  unavailable because `jack_lsp` is missing. No VM launch, public release, release asset upload, Bunny deployment, or
  support-matrix promotion was performed.
- `scripts/verify-published-release.sh` now extracts required published release evidence archives with
  `scripts/extract-safe-tar.sh`, aligning the post-publish verifier with final-proof archive safety. This rejects
  symlink/hardlink archive members before evidence verification reads extracted manifests or command logs.
- Focused validation passed: `bash -n scripts/verify-published-release.sh scripts/verify-scripts.sh
  scripts/verify-docs.sh`, `pnpm verify:scripts`, `pnpm verify:docs`, offline `pnpm verify:release-readiness -- --repo
  sandwichfarm/loopwire --tag v0.1.0 --public-key packaging/release-signing-public.pem --skip-gh --skip-tag
  --skip-clean-git --allow-candidate-notes`, `pnpm verify:requirements`, `git diff --check`, added-line length scan,
  and GSD roadmap/phase queries. `pnpm verify:scripts` rejects a signed fake release whose evidence archive contains a
  symlinked manifest member.
- Full validation passed: `pnpm check`, `pnpm detect:audio`, and codebase-memory MCP fast reindex/status.
  `index_status` reported ready with 2,554 nodes and 5,404 edges. `pnpm detect:audio` reported PipeWire, PulseAudio
  compatibility, and ALSA available; JACK remains unavailable because `jack_lsp` is missing. No VM launch, public
  release, release asset upload, Bunny deployment, or support-matrix promotion was performed.
- `scripts/verify-release-asset-checksum.sh` now verifies an individual release asset against signed `SHA256SUMS`,
  requiring exactly one manifest entry and rejecting missing entries, duplicate entries, tampered assets, and unsafe
  asset names.
- `.github/workflows/final-release-proof.yml` now downloads `SHA256SUMS`/`SHA256SUMS.sig` and verifies both release and
  VM evidence archives are signed-checksum-bound before extracting them.
- Focused validation passed: `bash -n scripts/verify-release-asset-checksum.sh scripts/verify-release-readiness.sh
  scripts/verify-scripts.sh scripts/verify-github-workflows.sh`, `pnpm verify:scripts`, `pnpm verify:workflows`,
  `pnpm verify:docs`, offline `pnpm verify:release-readiness -- --repo sandwichfarm/loopwire --tag v0.1.0 --public-key
  packaging/release-signing-public.pem --skip-gh --skip-tag --skip-clean-git --allow-candidate-notes`,
  `pnpm verify:requirements`, `git diff --check`, added-line length scan, and GSD roadmap/phase queries.
- Full validation passed: `pnpm check`, `pnpm detect:audio`, and codebase-memory MCP fast reindex/status.
  `index_status` reported ready with 2,565 nodes and 5,417 edges. `pnpm verify:scripts` covers the direct signed-asset
  checksum regressions for missing manifest entries, duplicate entries, tampered assets, and the successful smoke path.
  `pnpm detect:audio` reported PipeWire, PulseAudio compatibility, and ALSA available; JACK remains unavailable because
  `jack_lsp` is missing. No VM launch, public release, release asset upload, Bunny deployment, or support-matrix
  promotion was performed.
- `scripts/render-nix-release-package.sh` now renders a concrete Nix `loopwire-bin` package expression from canonical
  release tarball entries in `SHA256SUMS`, verifies each asset checksum, optionally verifies `SHA256SUMS.sig` through
  `scripts/verify-release-asset-checksum.sh`, and converts the release hashes into Nix SRI form.
- `package.json` exposes the helper as `pnpm nix:render-release`; packaging docs, install docs, README, and unreleased
  notes describe the render ceremony while preserving the boundary that real Nix publication still needs `nix build`
  on a Nix-enabled host against published artifacts.
- Focused validation passed: `bash -n scripts/render-nix-release-package.sh scripts/verify-packaging.sh
  scripts/verify-scripts.sh scripts/verify-requirements.sh`, `pnpm verify:packaging`, `pnpm verify:requirements`,
  `pnpm verify:scripts`, `pnpm verify:docs`, added-line length scan, and GSD roadmap/phase queries.
- Full validation passed: `pnpm check`, `pnpm detect:audio`, and codebase-memory MCP fast reindex/status.
  `index_status` reported ready with 2,584 nodes and 5,439 edges. `pnpm verify:packaging` renders a temporary Nix
  expression from checksum-bound fake artifacts and rejects duplicate checksum entries. `pnpm detect:audio` reported
  PipeWire, PulseAudio compatibility, and ALSA available; JACK remains unavailable because `jack_lsp` is missing. No
  real `nix build`, public release, tag push, Bunny deployment, VM launch, or support-matrix promotion was performed.
- `scripts/verify-nix-release-package.sh` now wraps the checksum-bound Nix render step and runs
  `nix build -f <rendered> --arg loopwireSrc <repo> --no-link` when `nix` is available. It fails closed by default if
  `nix` is missing, has `--skip-build-if-missing-nix` only for non-Nix wiring checks, and has `--render-only` for
  fake-artifact metadata smokes.
- `package.json` exposes the build-proof wrapper as `pnpm verify:nix-release`; packaging docs, install docs, README,
  and unreleased notes distinguish render-only checks, non-Nix wiring skips, and real release-time Nix build proof.
- Focused validation passed: `bash -n scripts/verify-nix-release-package.sh scripts/verify-packaging.sh
  scripts/verify-scripts.sh scripts/verify-requirements.sh`, `pnpm verify:packaging`, `pnpm verify:requirements`,
  `pnpm verify:scripts`, `pnpm verify:docs`, added-line length scan, and GSD roadmap/phase queries.
- Full validation passed: `pnpm check`, `pnpm detect:audio`, and codebase-memory MCP fast reindex/status.
  `index_status` reported ready with 2,598 nodes and 5,455 edges. `pnpm verify:packaging` runs the verifier in
  `--render-only` mode against checksum-bound fake artifacts so Nix-enabled hosts do not try to build unpublished fake
  tarballs. `pnpm detect:audio` reported PipeWire, PulseAudio compatibility, and ALSA available; JACK remains
  unavailable because `jack_lsp` is missing. No non-skipped `nix build`, public release, tag push, Bunny deployment,
  VM launch, or support-matrix promotion was performed.
- `scripts/verify-nix-release-package.sh` now also accepts `--repo OWNER/REPO --tag vX.Y.Z --public-key FILE`, downloads
  the signed GitHub Release assets with `gh`, derives the Nix package version from the tag, renders the checksum-bound
  package expression, and still fails closed unless a real `nix build` succeeds.
- `scripts/collect-release-evidence.mjs` and `scripts/verify-release-evidence.mjs` now support
  `--require-nix-release`. The evidence verifier requires a successful `nix-release-package` command bound to the same
  repo, tag, and public key, and rejects `--release-dir`, `--skip-build-if-missing-nix`, and `--render-only` rows as
  final Nix proof.
- `scripts/verify-final-release-proof.sh` now runs the published-release Nix package verifier directly before checking
  release evidence, all-target VM evidence, support-matrix, and docs proof. Its dry-run plan now includes the Nix
  command so release operators can see the package-manager gate before launching a final proof run.
- Focused validation passed: `bash -n scripts/verify-nix-release-package.sh scripts/verify-final-release-proof.sh
  scripts/verify-release-readiness.sh scripts/verify-github-workflows.sh scripts/verify-packaging.sh
  scripts/verify-scripts.sh`, `node --check scripts/collect-release-evidence.mjs`, `node --check
  scripts/verify-release-evidence.mjs`, `bash scripts/verify-nix-release-package.sh --help`, and a quick
  `collect-release-evidence --list-commands --require-nix-release` smoke.
- Full validation passed after the published-release Nix proof update: `pnpm verify:packaging`,
  `pnpm verify:scripts`, `pnpm verify:docs`, `pnpm verify:workflows`, `pnpm verify:requirements`,
  offline `pnpm verify:release-readiness -- --repo sandwichfarm/loopwire --tag v0.1.0 --public-key
  packaging/release-signing-public.pem --skip-gh --skip-tag --skip-clean-git --allow-candidate-notes`,
  `pnpm verify:vm`, `pnpm detect:audio`, `pnpm check`, `git diff --check`, added-line length scan, and GSD
  roadmap/phase queries. Codebase-memory MCP `index_status` reported ready with 2,616 nodes and 5,447 edges.
  `pnpm detect:audio` reported PipeWire, PulseAudio compatibility, and ALSA available; JACK remains unavailable because
  `jack_lsp` is missing. No non-skipped `nix build`, GitHub release, tag push, Bunny deployment, VM launch, or
  support-matrix promotion was performed.
- `.github/workflows/final-release-proof.yml` now installs pinned Determinate Nix with
  `DeterminateSystems/determinate-nix-action@v3.21.2` before invoking `scripts/verify-final-release-proof.sh`, so the
  hosted final proof runner can execute the non-skipped Nix package gate.
- `scripts/verify-github-workflows.sh`, `scripts/verify-release-readiness.sh`, and `scripts/verify-scripts.sh` now
  guard that final proof Nix setup. The action version was checked live with `gh release list --repo
  DeterminateSystems/determinate-nix-action --limit 5`, which reported `v3.21.2` as the latest release on
  2026-06-20.
- `.github/workflows/final-release-proof.yml` now passes `GH_TOKEN: ${{ github.token }}` into the composed final proof
  step, covering the nested `gh release` calls made by the published-release and Nix package verifiers.
- `scripts/verify-github-workflows.sh`, `scripts/verify-release-readiness.sh`, and `scripts/verify-scripts.sh` now
  guard that final proof token wiring.
- Focused validation passed: `bash -n scripts/verify-release-readiness.sh scripts/verify-github-workflows.sh
  scripts/verify-scripts.sh`, `pnpm verify:workflows`, offline `pnpm verify:release-readiness -- --repo
  sandwichfarm/loopwire --tag v0.1.0 --public-key packaging/release-signing-public.pem --skip-gh --skip-tag
  --skip-clean-git --allow-candidate-notes`, `pnpm verify:scripts`, `pnpm verify:docs`, `git diff --check`, and
  added-line length scan.
- Full validation passed: `pnpm check`, GSD roadmap/phase queries, and codebase-memory MCP fast reindex/status.
  `index_status` reported ready with 2,617 nodes and 5,451 edges.

## Evidence Missing

- No public GitHub Release was created.
- A real release signing public key exists at `packaging/release-signing-public.pem`, and the matching private key is
  now stored as the `LOOPWIRE_RELEASE_PRIVATE_KEY` GitHub secret for `sandwichfarm/loopwire`.
- No release tag exists locally or remotely.
- Required Bunny.net deployment secrets are not present: `BUNNY_STORAGE_ZONE` and `BUNNY_ACCESS_KEY`.
- The docs site can now build a synced `/install.sh`, the deploy helper fails closed on incomplete dist artifacts, the
  workflow has a pull-zone smoke gate plus verified deployment manifest artifact, and release evidence can require a
  successful `docs-live-smoke` row, but no Bunny deployment or live URL smoke was performed.
- The final proof workflow exists, but no release evidence archive, VM evidence archive, live docs target, or public
  release exists for it to verify yet.
- The VM evidence packager exists, but no real all-target VM evidence archive has been produced from operator-run
  guests.
- Host-side single-target and matrix SSH collectors are available, but no live VM evidence bundle was captured from an
  actual VM run.
- Host VM launch is not available on this machine until QEMU tooling is installed; `scripts/vm-matrix.sh doctor --all`
  reports missing `qemu-system-x86_64`, `qemu-system-aarch64`, `qemu-img`, and `cloud-localds`.
- Nix package output is statically wired, can now be rendered from checksum-bound release artifacts, and final release
  proof now includes the published-release Nix package verifier. This host lacks `nix`, so non-skipped `nix build`
  proof still needs a Nix-enabled host or VM target after real release hashes exist.
- A bundled JACK virtual port provider/client, live backend graph-edge gain, and live host DSP capture/injection remain
  unimplemented, but the pure core DSP gain/mute mix math, the injected audio-host DSP graph adapter, the injected JACK
  virtual-port provider hook, the command-backed DSP provider port helper, explicit background DSP provider restore,
  provider plan/verify tooling, and bundled file-backed `loopwire-dsp-provider` now exist. The DSP adapter now follows
  core rollback semantics, and the desktop now consumes backend mixing reports for route-control UX, but current live
  PipeWire/JACK reports still remain link-only and the desktop still blocks unbound JACK live-apply attempts before
  arming.
- Codebase-memory MCP is currently available for `home-sandwich-Develop-loopwire`; `index_status` reports the graph is
  ready.

## Status

Phase 12 remains incomplete. Publication and VM proof require Bunny secrets, a release tag, a public GitHub Release,
live docs deployment/smoke proof, and operator-run VM evidence.
