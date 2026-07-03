# Unreleased

These notes describe source-tree progress. They are not a public release announcement.

## Supported In Source

- Contributor source install with `pnpm install` and `pnpm check`.
- Backend detection for PipeWire, PulseAudio compatibility, JACK availability, and ALSA playback visibility.
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
- Native JACK route mute now disconnects configured existing connections and verification fails if muted connections
  remain connected.
- Dry-run-by-default PulseAudio compatibility adapter for Loopwire null sinks, matched stream moves, and stream-level
  volume/mute controls.
- PulseAudio compatibility verification now fails when a configured route has no matching live stream, instead of
  reporting fake success for an absent app stream.
- PulseAudio startup and background restore now keep absent matching streams pending until those apps launch, without
  weakening normal switch verification.
- Source-checkout PulseAudio background restore can retry pending app-stream routes for a bounded live window without
  recreating the virtual sinks.
- Release tarballs now package a `loopwire --background` launcher with bundled restore assets under
  `libexec/loopwire/`, and package templates install those support files.
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
- Desktop startup backend detection through the allowlisted Tauri bridge for `pw-cli`, `wpctl`, `pactl`, `jack_lsp`,
  and `aplay`; browser preview keeps packaged fallback candidates.
- First-run backend selection now prompts when multiple detected backends are available instead of treating PipeWire as
  an already persisted choice.
- Backend route-control semantics report whether controls are graph-edge, stream-level, link-only, or unavailable.
- Desktop status shows degraded route-control behavior for selected backends, and now names native PipeWire/JACK route
  mute as implemented link disconnect behavior while keeping route gain marked as planned.
- Desktop live-apply preflight now lists every blocker when a configuration has multiple issues, instead of showing
  only the first blocker plus a count.
- Configuration CRUD, source-picker additions, output-bus additions, monitor additions, import/export, persistence
  migration, and startup re-apply through the app runtime contract.
- Desktop route lane now creates and removes individual source-to-output edges, while preserving one route per
  source/output pair and independent per-edge gain/mute state.
- Desktop source, output, and monitor cards now support endpoint removal. Source/output removal prunes dependent routes,
  monitor removal clears hidden-monitor state, and the last output remains protected.
- Desktop source and output cards now support manual host binding fields for PipeWire/JACK ports or PulseAudio stream
  tokens that are not listed by backend enumeration.
- Monitor visibility is now scoped per configuration, so hiding a monitor in one workspace does not hide same-id
  monitors in other workspaces.
- Desktop custom chrome now persists as a preference and requests an undecorated Tauri window before showing
  Loopwire-owned drag, minimize, and close controls.
- Desktop sidebar start-on-boot control for XDG autostart status, enable, and disable, plus CLI helper fallback.
- Desktop sidebar restore-on-boot control for a user-scoped systemd unit that runs packaged background restore without
  opening the GUI.
- Desktop restore-on-boot now resolves the packaged `loopwire` launcher from `loopwire-gui` before writing systemd
  units, and refuses to install a broken GUI-binary `--background` unit when the launcher is missing.
- Source-checkout background restore runner reads the Tauri-written state file and verifies the selected configuration
  through dry-run or explicit live backend adapters.
- Local release artifact packaging, checksum signing, installer smoke, AUR package smoke, and VM target metadata
  validation.
- Published-release verification can now run against a local signed release directory in CI and rejects tampered
  tarballs before the live GitHub Release smoke path is available.
- Release workflow now has x86_64 and AArch64 Linux build lanes, with a single publish job that signs one combined
  `SHA256SUMS` manifest before creating or updating the GitHub Release.
- Release evidence bundles now record the candidate readiness check and the strict publish preflight log separately, so
  current release blockers can be attached without failing candidate evidence collection.
- Release evidence manifests now expose parsed `release.findings` and `release.blockers` from the readiness log, plus a
  log-summary mode for checking preflight blockers without rerunning release checks.
- Release signing key preparation helper that refuses repo-local private keys and verifies the generated key pair before
  printing the GitHub secret setup command.
- Docs deployment now uses a reusable Bunny.net upload helper with dry-run verification, checksum headers, and optional
  regional storage endpoint support through `BUNNY_STORAGE_ENDPOINT`.
- Published release verification now rejects release directories missing either canonical Linux tarball
  (`loopwire-linux-x86_64.tar.gz` or `loopwire-linux-aarch64.tar.gz`) before a release can be called installable.
- Release evidence collection can now include published-release installer smoke as optional full-profile evidence, or
  require it with `--require-published-release` for final release proof after GitHub assets exist.
- Redacted support bundle collection for user bug reports and cross-system compatibility triage.
- VM evidence verification now requires a successful guest command ledger and nested redacted support bundle, so support
  claims cannot rely on file presence alone.
- VM evidence collection now starts the Loopwire desktop shell, records `desktop-launch.log`, and requires a successful
  `desktop-launch` ledger row before support claims can be promoted.
- VM evidence promotion now has a guarded `pnpm vm:promote-evidence` command that verifies target evidence before
  changing a support-matrix row from `Manual VM` to `Verified`.
- VM evidence collection now writes `environment.json`, and verification rejects bundles whose observed distro,
  desktop/session, or architecture do not match the selected target row.
- Host-side SSH VM evidence collection can run the guest collector, copy target evidence back, and verify the bundle
  without changing support-matrix rows prematurely.
- VM host planning now prints cross-distro virtualization setup hints, operator-owned image policy, target-specific
  render commands, launch dry runs, and SSH evidence handoff commands.
- VM launch dry-runs now stay non-mutating: they print the planned QEMU command and `.vm/run` paths without requiring
  the image path to exist, rendering cloud-init, or writing VM state.
- VM launch now supports `--ssh-port` and prints the matching evidence-pull command, so operators can run or plan
  multiple guest targets without hardcoding host port `2222`.
- VM evidence collectors now reject invalid SSH and desktop smoke ports before touching SSH, Vite, or guest evidence
  commands.
- VM doctor now treats `cloud-localds` as a required launch preflight, matching the launch path that creates cloud-init
  seed media only after `--execute`.
- VM cloud-init rendering can now generate guest bootstrap assets for every target in one command.
- VM matrix verification now renders and checks cloud-init plus guest command handoffs for every target in CI before
  any operator-run guest evidence is claimed.
- Debian and Ubuntu VM cloud-init commands now install the pinned pnpm toolchain before workspace validation.
- NixOS VM cloud-init commands now run evidence collection through `nix develop --command`.

## Known Limitations

- No public signed release artifact exists yet.
- `packaging/release-signing-public.pem` still needs the real project release public key.
- JACK virtual port creation and true per-edge gain remain planned. Native JACK monitor routing still requires an
  existing target sink.
- Live host apply needs Tauri desktop runtime; browser preview fails closed without host mutation.
- Packaged background restore uses the bundled JavaScript restore engine and currently requires `node` on `PATH`.
- VM host planning and cloud-init rendering do not launch guests, download distro images, or promote support-matrix rows
  without operator-captured evidence.
- VM desktop launch smoke proves the Loopwire shell responds locally; screenshot commands still need operator care to
  capture the intended desktop surface in each guest.
- Public AArch64 release proof still requires a tagged workflow run and published `loopwire-linux-aarch64.tar.gz`
  asset.
- Nix package metadata exists, but Nix build proof must come from a Nix-enabled host or VM target.

## Verification To Keep Current

- `pnpm check`
- `pnpm detect:audio`
- `pnpm verify:docs`
- `pnpm verify:vm`
- `cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml`
