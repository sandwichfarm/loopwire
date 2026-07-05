#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

required_files=(
  "apps/docs/docs/index.md"
  "apps/docs/docs/guide/install.md"
  "apps/docs/docs/guide/start-on-boot.md"
  "apps/docs/docs/guide/backends.md"
  "apps/docs/docs/guide/support-matrix.md"
  "apps/docs/docs/guide/troubleshooting.md"
  "apps/docs/docs/developer/architecture.md"
  "apps/docs/docs/developer/screenshots.md"
  "apps/docs/docs/developer/vm-matrix.md"
  "apps/docs/docs/developer/release.md"
  "apps/docs/docs/developer/release-notes.md"
  "apps/docs/docs/release-notes/0.1.0.md"
  "apps/docs/docs/release-notes/unreleased.md"
  "apps/docs/docs/public/install.sh"
  "apps/docs/docs/public/product-screenshot.svg"
)

assert_file() {
  local file="$1"

  if [[ ! -s "$root/$file" ]]; then
    echo "Missing required docs file: $file" >&2
    exit 1
  fi
}

assert_contains() {
  local file="$1"
  local needle="$2"

  if ! grep -Fq -- "$needle" "$root/$file"; then
    echo "Missing docs content in $file: $needle" >&2
    exit 1
  fi
}

for file in "${required_files[@]}"; do
  assert_file "$file"
done

if ! cmp -s "$root/scripts/install.sh" "$root/apps/docs/docs/public/install.sh"; then
  echo "Public docs install.sh must stay byte-for-byte synced with scripts/install.sh" >&2
  exit 1
fi
bash -n "$root/apps/docs/docs/public/install.sh"

node "$root/scripts/verify-support-matrix.mjs"

assert_contains "apps/docs/docs/.vitepress/config.ts" "/guide/support-matrix"
assert_contains "apps/docs/docs/.vitepress/config.ts" "/guide/troubleshooting"
assert_contains "apps/docs/docs/.vitepress/config.ts" "/developer/release-notes"
assert_contains "apps/docs/docs/.vitepress/config.ts" "/release-notes/0.1.0"
assert_contains "apps/docs/docs/.vitepress/config.ts" "/release-notes/unreleased"
assert_contains "apps/docs/docs/index.md" "/product-screenshot.svg"
assert_contains "apps/docs/docs/index.md" "A desktop-grade routing workspace"
assert_contains "apps/docs/docs/index.md" "Current source install"
assert_contains "apps/docs/docs/index.md" "Release-gated curl install"
assert_contains "apps/docs/docs/index.md" "curl -fsSL https://&lt;docs-host&gt;/install.sh \\"
assert_contains "apps/docs/docs/index.md" "  | sh"
assert_contains "apps/docs/docs/index.md" "loopwire --background --mode preview"
assert_contains "apps/docs/docs/index.md" "signed public artifacts, Bunny deploy, and VM proof"
assert_contains "apps/docs/docs/index.md" "v0.1.0 candidate"
assert_contains "apps/docs/docs/index.md" "Release ceremony"
assert_contains "apps/docs/docs/index.md" "--output-dir .release-evidence/v0.1.0 --profile full --release-tag v0.1.0"
assert_contains "README.md" "flake package templates"
assert_contains "README.md" "fake hashes"
assert_contains "README.md" "pnpm jack:ports"
assert_contains "README.md" "pnpm jack:verify"
assert_contains "README.md" "pnpm dsp:plan"
assert_contains "README.md" "pnpm dsp:verify"
assert_contains "README.md" "loopwire-dsp-provider"
assert_contains "README.md" "does not yet capture or inject live PipeWire/JACK audio streams"
assert_contains "apps/docs/docs/guide/support-matrix.md" "arch-hyprland-pipewire"
assert_contains "apps/docs/docs/guide/support-matrix.md" "fedora-kde-jack"
assert_contains "apps/docs/docs/guide/support-matrix.md" "debian-xfce-pulseaudio"
assert_contains "apps/docs/docs/guide/support-matrix.md" "opensuse-kde-pipewire"
assert_contains "apps/docs/docs/guide/support-matrix.md" "ubuntu-gnome-pipewire-aarch64"
assert_contains "apps/docs/docs/guide/support-matrix.md" "desktop launch smoke"
assert_contains "apps/docs/docs/guide/support-matrix.md" "environment.json"
assert_contains "apps/docs/docs/guide/support-matrix.md" "audio backend as available"
assert_contains "apps/docs/docs/guide/support-matrix.md" "packaged user-scoped systemd restore paths are verified locally"
assert_contains "apps/docs/docs/guide/support-matrix.md" "pnpm vm:promote-evidence -- --target"
assert_contains "apps/docs/docs/guide/support-matrix.md" "Direct SSH collection keeps guest and copied-back output target-scoped"
assert_contains "apps/docs/docs/guide/support-matrix.md" "--require-published-release"
assert_contains "apps/docs/docs/guide/support-matrix.md" 'Custom verifier `--evidence-root` and `--matrix` paths'
assert_contains "apps/docs/docs/guide/support-matrix.md" "before reading the matrix or scanning copied-back VM evidence"
assert_contains "apps/docs/docs/guide/support-matrix.md" "pnpm vm:render-ssh-plan"
assert_contains "apps/docs/docs/guide/support-matrix.md" "Virtual sinks, routes, mute, monitor links"
assert_contains "apps/docs/docs/guide/support-matrix.md" "one output per source"
assert_contains "apps/docs/docs/guide/support-matrix.md" "Playback/capture hardware detection"
assert_contains "apps/docs/docs/guide/support-matrix.md" "Nix flake package template"
assert_contains "apps/docs/docs/guide/support-matrix.md" "fake hashes"
assert_contains "apps/docs/docs/guide/backends.md" "list PipeWire output ports as source candidates"
assert_contains "apps/docs/docs/guide/backends.md" "create Loopwire-owned virtual output and monitor sinks"
assert_contains "apps/docs/docs/guide/backends.md" "virtual monitor sink ports"
assert_contains "apps/docs/docs/guide/backends.md" "reject configurations that route one source to multiple outputs"
assert_contains "apps/docs/docs/guide/backends.md" "source fan-out"
assert_contains "apps/docs/docs/guide/backends.md" 'detection/support bundles expose `one output per source`'
assert_contains "apps/docs/docs/guide/backends.md" "disconnect configured route links when a route is muted"
assert_contains "apps/docs/docs/guide/backends.md" "host-backed output and physical monitor target candidates"
assert_contains "apps/docs/docs/guide/backends.md" "native JACK adapter"
assert_contains "apps/docs/docs/guide/backends.md" "list JACK output ports as source candidates"
assert_contains "apps/docs/docs/guide/backends.md" "disconnect configured route connections when a route is muted"
assert_contains "apps/docs/docs/guide/backends.md" "physical monitor sink ports"
assert_contains "apps/docs/docs/guide/backends.md" "connect pre-existing Loopwire-owned JACK route ports"
assert_contains "apps/docs/docs/guide/backends.md" 'fail closed before `jack_connect`'
assert_contains "apps/docs/docs/guide/backends.md" "Loopwire-owned JACK ports already exist"
assert_contains "apps/docs/docs/guide/backends.md" "injected JACK virtual port provider"
assert_contains "apps/docs/docs/guide/backends.md" "command-backed provider arguments"
assert_contains "apps/docs/docs/guide/backends.md" "deterministic Loopwire-owned client names and suggested channel ports"
assert_contains "apps/docs/docs/guide/backends.md" "loopwire-jack-ports"
assert_contains "apps/docs/docs/guide/backends.md" "loopwire.jack-ports.provision-plan"
assert_contains "apps/docs/docs/guide/backends.md" "pnpm jack:ports"
assert_contains "apps/docs/docs/guide/backends.md" "pnpm jack:verify"
assert_contains "apps/docs/docs/guide/backends.md" "--ports-file captured-jack-lsp.txt"
assert_contains "apps/docs/docs/guide/backends.md" "The desktop live-apply preflight is"
assert_contains "apps/docs/docs/guide/backends.md" 'ALSA path is read-only diagnostics'
assert_contains "apps/docs/docs/guide/backends.md" '`arecord -l`'
assert_contains "apps/docs/docs/guide/backends.md" "ALSA reports unavailable controls because it is diagnostics-only"
assert_contains "apps/docs/docs/guide/backends.md" "desktop consumes detected backend mixing semantics"
assert_contains "apps/docs/docs/guide/backends.md" "first-run backend choice callout"
assert_contains "apps/docs/docs/guide/backends.md" "saved for live apply and startup restore"
assert_contains "apps/docs/docs/guide/backends.md" "no matching live stream"
assert_contains "apps/docs/docs/guide/backends.md" "pending during startup and background restore"
assert_contains "apps/docs/docs/guide/backends.md" "refresh pending stream routes"
assert_contains "apps/docs/docs/guide/backends.md" "pure DSP mix planner, renderer, and cycle runner"
assert_contains "apps/docs/docs/guide/backends.md" "injected source port"
assert_contains "apps/docs/docs/guide/backends.md" "fail closed before writes"
assert_contains "apps/docs/docs/guide/backends.md" "injected DSP graph adapter"
assert_contains "apps/docs/docs/guide/backends.md" "verify rendered outputs"
assert_contains "apps/docs/docs/guide/backends.md" "restore the rollback configuration"
assert_contains "apps/docs/docs/guide/backends.md" "first-class configuration runtime adapter wrapper"
assert_contains "apps/docs/docs/guide/backends.md" "command-backed DSP provider helper"
assert_contains \
  "apps/docs/docs/guide/backends.md" \
  '`capabilities`, `read-source`, `write-output`, `verify-output`, and `clear-output`'
assert_contains "apps/docs/docs/guide/backends.md" "supportsLiveGraph:false"
assert_contains "apps/docs/docs/guide/backends.md" "--require-live-capability"
assert_contains "apps/docs/docs/guide/backends.md" "JSON stdin"
assert_contains "apps/docs/docs/guide/backends.md" "stored by configuration"
assert_contains "apps/docs/docs/guide/backends.md" "Release artifacts ship"
assert_contains "apps/docs/docs/guide/backends.md" '`loopwire-dsp-provider`'
assert_contains "apps/docs/docs/guide/backends.md" "seed-source"
assert_contains "apps/docs/docs/guide/backends.md" "live backend DSP still needs"
assert_contains "apps/docs/docs/guide/backends.md" "pnpm dsp:plan"
assert_contains "apps/docs/docs/guide/backends.md" "pnpm dsp:verify"
assert_contains "apps/docs/docs/guide/backends.md" "explicit execute mode"
assert_contains "apps/docs/docs/guide/configurations.md" "detected PipeWire output ports"
assert_contains "apps/docs/docs/guide/configurations.md" 'recovery tray with a `Show` action'
assert_contains "apps/docs/docs/guide/configurations.md" "Native PipeWire can create Loopwire-owned virtual output and monitor sinks"
assert_contains "apps/docs/docs/guide/configurations.md" "native PipeWire and the"
assert_contains "apps/docs/docs/guide/configurations.md" "native PipeWire/JACK target ports also appear in the output picker"
assert_contains "apps/docs/docs/guide/configurations.md" "add or remove individual route edges"
assert_contains "apps/docs/docs/guide/configurations.md" "one edge per"
assert_contains "apps/docs/docs/guide/configurations.md" "runtime activity ledger"
assert_contains "apps/docs/docs/guide/configurations.md" "the exact unload"
assert_contains "apps/docs/docs/guide/configurations.md" "apply, verify, and rollback operations"
assert_contains "apps/docs/docs/guide/configurations.md" '`Reset gains` action'
assert_contains "apps/docs/docs/guide/configurations.md" "without touching host audio"
assert_contains "apps/docs/docs/guide/configurations.md" "route gain sliders become read-only"
assert_contains "apps/docs/docs/guide/configurations.md" "names the affected routes, sources, outputs, and monitors"
assert_contains "apps/docs/docs/guide/configurations.md" "Removing an input or output prunes the routes"
assert_contains "apps/docs/docs/guide/configurations.md" "manual host binding fields"
assert_contains "apps/docs/docs/guide/configurations.md" "Clearing the field returns the endpoint"
assert_contains "apps/docs/docs/guide/configurations.md" "Monitor visibility is scoped to the active configuration"
assert_contains "apps/docs/docs/guide/configurations.md" "preflight strip lists every blocker"
assert_contains "apps/docs/docs/guide/configurations.md" "configuration-switch guard both consume"
assert_contains "apps/docs/docs/guide/configurations.md" "current detection reports as"
assert_contains "apps/docs/docs/guide/configurations.md" "it can route each source to only one output"
assert_contains "apps/docs/docs/guide/configurations.md" "PulseAudio routes that fan one source out to multiple"
assert_contains "apps/docs/docs/guide/configurations.md" "JACK live apply also requires every routed source"
assert_contains "apps/docs/docs/guide/configurations.md" "pnpm jack:ports"
assert_contains "apps/docs/docs/guide/configurations.md" "pnpm jack:verify"
assert_contains "apps/docs/docs/guide/configurations.md" "Editing the active configuration disarms live apply"
assert_contains "apps/docs/docs/guide/configurations.md" "Re-arm live apply after"
assert_contains "apps/docs/docs/guide/configurations.md" "Changing the selected backend runs a backend-change transaction"
assert_contains "apps/docs/docs/guide/configurations.md" "Loopwire commits the new"
assert_contains "apps/docs/docs/guide/configurations.md" "backend as the saved startup-restore choice only after"
assert_contains "apps/docs/docs/guide/configurations.md" "only after the active configuration verifies"
assert_contains "apps/docs/docs/guide/configurations.md" "controls stay disabled while a backend-change transaction is in flight"
assert_contains "apps/docs/docs/guide/configurations.md" "stale backend results are ignored"
assert_contains "apps/docs/docs/guide/configurations.md" "Automatic single-backend selection uses the same transaction path"
assert_contains "apps/docs/docs/guide/configurations.md" "is not persisted until the active configuration verifies"
assert_contains "apps/docs/docs/guide/configurations.md" "disarms any previous"
assert_contains "apps/docs/docs/guide/configurations.md" "ALSA route controls are unavailable"
assert_contains "apps/docs/docs/guide/configurations.md" "detected backend mixing semantics"
assert_contains "apps/docs/docs/guide/configurations.md" "Configuration switches are serialized"
assert_contains "apps/docs/docs/guide/configurations.md" "stale async switch results cannot replace"
assert_contains "apps/docs/docs/guide/troubleshooting.md" "pnpm detect:audio"
assert_contains "apps/docs/docs/guide/troubleshooting.md" "pnpm collect:support"
assert_contains "apps/docs/docs/guide/troubleshooting.md" "--configuration exported-loopwire-config.json"
assert_contains "apps/docs/docs/guide/troubleshooting.md" "absent app stream cannot prove"
assert_contains "apps/docs/docs/guide/troubleshooting.md" "Pending matching PulseAudio"
assert_contains "apps/docs/docs/guide/troubleshooting.md" "pendingStreamRefresh"
assert_contains "apps/docs/docs/guide/troubleshooting.md" "creates a virtual PipeWire sink"
assert_contains "apps/docs/docs/guide/troubleshooting.md" "deterministic ports"
assert_contains "apps/docs/docs/guide/troubleshooting.md" '`arecord -l` has no cards'
assert_contains "apps/docs/docs/guide/troubleshooting.md" 'before any `jack_connect` mutation'
assert_contains "apps/docs/docs/guide/troubleshooting.md" "minimize, maximize/restore, and close controls"
assert_contains "apps/docs/docs/guide/troubleshooting.md" "If close, maximize/restore, or minimize controls are missing"
assert_contains "apps/docs/docs/guide/troubleshooting.md" "audio.backends"
assert_contains "apps/docs/docs/guide/troubleshooting.md" "jack-port-requirements.json"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "pnpm restore:background"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "Packaged Background Restore Path"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "Open on boot"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "Restore on boot"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "The restore card names the active configuration and saved backend"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "loopwire --background"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "If that file is missing, unreadable, corrupt, or incompatible"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "choose the configuration you want"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "restored at login"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "The curl installer reports that dependency"
assert_contains "apps/docs/docs/guide/start-on-boot.md" 'install the distro `nodejs` package'
assert_contains "apps/docs/docs/guide/start-on-boot.md" 'preflights `loopwire --background --help`'
assert_contains "apps/docs/docs/guide/start-on-boot.md" "default.target.wants/loopwire.service"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "--source-dir"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "Settings > Audio backend"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "fail-closed instead of guessing"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "pending until those apps launch"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "--retry-pending-ms"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "--jack-provider-command"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "--jack-provider-timeout-ms"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "LOOPWIRE_JACK_PORTS_DELEGATE"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "--backend dsp"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "--dsp-provider-command"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "--dsp-provider-timeout-ms"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "--dsp-provider-mode live"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "supportsLiveGraph:true"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "--require-live-capability"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "--dsp-frame-count"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "pnpm dsp:plan"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "pnpm dsp:verify"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "Release artifacts install"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "LOOPWIRE_DSP_PROVIDER_DIR"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "configuration-scoped rendered output"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "same runtime contract"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "pendingStreamRefresh.cleared"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "The check remains non-destructive"
assert_contains "apps/docs/docs/guide/install.md" 'packages.<system>.loopwire-bin'
assert_contains "apps/docs/docs/guide/install.md" "loopwire-dsp-provider"
assert_contains "apps/docs/docs/guide/install.md" 'The curl installer reports whether `node` is available'
assert_contains "apps/docs/docs/guide/install.md" "AUR and Nix package"
assert_contains "apps/docs/docs/guide/install.md" "paths declare or wrap that dependency"
assert_contains "apps/docs/docs/guide/install.md" "fake"
assert_contains "apps/docs/docs/guide/install.md" "VitePress public asset"
assert_contains "apps/docs/docs/guide/install.md" "/install.sh"
assert_contains "apps/docs/docs/guide/install.md" "tampered or unsafe archive artifacts are rejected"
assert_contains "apps/docs/docs/developer/screenshots.md" "product-screenshot.svg"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "collect-vm-evidence.sh"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "desktop-launch.log"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "audio.backends"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "jack-port-requirements.json"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "published-release-smoke.log"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "verify-vm-evidence.sh --require-published-release"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "--require-github-release-source"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "published-release.json"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "--release-tag v0.1.0"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "published-release-smoke"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "environment.json"
assert_contains "apps/docs/docs/developer/vm-matrix.md" 'backend availability from `detect-audio.json`'
assert_contains "apps/docs/docs/developer/vm-matrix.md" "JACK targets require JACK"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "LOOPWIRE_EVIDENCE_SESSION"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "--desktop-port 5199"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "support-bundle/support-bundle.json"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "host-install-hint=*"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "pnpm vm:promote-evidence"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "pnpm vm:promote-evidence -- --all"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "missing evidence directories are reported"
assert_contains "apps/docs/docs/developer/vm-matrix.md" 'only changes rows from `Manual VM` to'
assert_contains "apps/docs/docs/developer/vm-matrix.md" "pnpm vm:host-plan"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "pnpm vm:host-setup"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "pnpm vm:evidence-status"
assert_contains "apps/docs/docs/developer/vm-matrix.md" '--require-published-release --release-tag <tag>'
assert_contains "apps/docs/docs/developer/vm-matrix.md" "pnpm vm:launch"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "pnpm vm:render-launch-plan"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "pnpm vm:render-runbook"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "launch_command"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "evidence_pull_command"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "markdown runbook"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "AArch64 firmware"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "does not download images, install packages, launch guests"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "status=missing"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "status=invalid"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "status=verified"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "CRC-corrupt PNG placeholders are rejected"
assert_contains "apps/docs/docs/developer/vm-matrix.md" 'pnpm vm:host-setup -- --all'
assert_contains "apps/docs/docs/developer/vm-matrix.md" 'pnpm vm:doctor -- --all'
assert_contains "apps/docs/docs/developer/vm-matrix.md" "Host setup hints are architecture-scoped"
assert_contains "apps/docs/docs/developer/vm-matrix.md" 'Fedora `qemu-system-aarch64`'
assert_contains "apps/docs/docs/developer/vm-matrix.md" 'openSUSE `qemu-arm`'
assert_contains "apps/docs/docs/developer/vm-matrix.md" "target-check=*"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "package-family=*"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "verify-command=*"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "pnpm vm:render-ssh-plan"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "pnpm vm:render-cloud-init -- --all"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "verify-cloud-init"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "sudo npm install -g pnpm@11.3.0"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "Tauri Linux build prerequisites"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "pnpm verify:tauri"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "opensuse-kde-pipewire"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "zypper"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "ubuntu-gnome-pipewire-aarch64"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "qemu-system-aarch64"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "--firmware /path/to/QEMU_EFI.fd"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "NixOS cloud-init guest commands"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "operator-owned image policy"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "does not render cloud-init, and does not write"
assert_contains "apps/docs/docs/developer/vm-matrix.md" 'Use `--ssh-port`'
assert_contains "apps/docs/docs/developer/vm-matrix.md" 'collect-vm-evidence-ssh.sh --port'
assert_contains "apps/docs/docs/developer/vm-matrix.md" 'Launch inputs fail before QEMU planning'
assert_contains "apps/docs/docs/developer/vm-matrix.md" '`--image-format` is not `qcow2` or `raw`'
assert_contains "apps/docs/docs/developer/vm-matrix.md" 'Custom `--remote-output-dir` and `--local-output-dir` paths'
assert_contains "apps/docs/docs/developer/vm-matrix.md" "forwards the published-release smoke options"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "valid TCP ports from 1 to 65535"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "validates the port range"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "pnpm vm:collect-matrix"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "scripts/collect-vm-matrix-evidence.sh"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "TSV"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "duplicate targets"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "unsafe local output paths"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "--require-all-targets"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "fails before SSH runs"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "target id as its own path"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "segment and must not contain"
assert_contains "apps/docs/docs/developer/vm-matrix.md" 'Use `--require-published-release` with `--release-tag` for final'
assert_contains "apps/docs/docs/developer/vm-matrix.md" 'final-release `pnpm vm:collect-matrix` command'
assert_contains "apps/docs/docs/developer/vm-matrix.md" 'missing `cloud-localds`'
assert_contains "apps/docs/docs/developer/release-notes.md" "Release-note workflow"
assert_contains "apps/docs/docs/developer/release-notes.md" "release workflow reject"
assert_contains "apps/docs/docs/developer/release.md" "redacted support bundle"
assert_contains "apps/docs/docs/developer/release.md" "audio.backends"
assert_contains "apps/docs/docs/developer/release.md" "jack-port-requirements.json"
assert_contains "apps/docs/docs/developer/release.md" "rejects release-candidate/not-published wording"
assert_contains "apps/docs/docs/developer/release.md" "--release-tag v0.1.0"
assert_contains "apps/docs/docs/developer/release.md" "--require-published-release"
assert_contains "apps/docs/docs/developer/release.md" "--require-live-docs"
assert_contains "apps/docs/docs/developer/release.md" "--require-release-evidence"
assert_contains "apps/docs/docs/developer/release.md" "--require-vm-evidence"
assert_contains "apps/docs/docs/developer/release.md" "--require-vm-launch-plan"
assert_contains "apps/docs/docs/developer/release.md" "--require-dsp-provider-plan"
assert_contains "apps/docs/docs/developer/release.md" '--docs-hostname "$BUNNY_PULL_ZONE_HOSTNAME"'
assert_contains "apps/docs/docs/developer/release.md" "pnpm verify:release-evidence"
assert_contains "apps/docs/docs/developer/release.md" "pnpm verify:final-release"
assert_contains "apps/docs/docs/developer/release.md" "--public-key packaging/release-signing-public.pem"
assert_contains "apps/docs/docs/developer/release.md" '--git-head "$(git rev-parse HEAD)"'
assert_contains "apps/docs/docs/developer/release.md" "--support-matrix apps/docs/docs/guide/support-matrix.md"
assert_contains "apps/docs/docs/developer/release.md" 'installed-release smoke required for `Verified` rows'
assert_contains "apps/docs/docs/developer/release.md" "--require-all-vm-targets"
assert_contains "apps/docs/docs/developer/release.md" "--require-no-release-blockers"
assert_contains "apps/docs/docs/developer/release.md" "--require-clean-git"
assert_contains "apps/docs/docs/developer/release.md" "The tag release workflow collects the published-release portion"
assert_contains "apps/docs/docs/developer/release.md" "loopwire-release-evidence-<tag>"
assert_contains "apps/docs/docs/developer/release.md" "loopwire-release-evidence-<tag>.tar.gz"
assert_contains "apps/docs/docs/developer/release.md" 'the signed `SHA256SUMS` manifest so the evidence archive is checksummed'
assert_contains "apps/docs/docs/developer/release.md" "to the GitHub Release"
assert_contains "apps/docs/docs/developer/release.md" "The evidence collector and verifier enforce the same"
assert_contains "apps/docs/docs/developer/release.md" "rejected before command planning, manifest acceptance"
assert_contains "apps/docs/docs/developer/release.md" 'repository identity in `OWNER/REPO` form'
assert_contains "apps/docs/docs/developer/release.md" "rejected before GitHub access or evidence verification"
assert_contains "apps/docs/docs/developer/release.md" 'expected `release.tag` and repository'
assert_contains "apps/docs/docs/developer/release.md" "derives the expected tag from the single evidence"
assert_contains "apps/docs/docs/developer/release.md" 'rejects any mismatch with `release-evidence.json`'
assert_contains "apps/docs/docs/developer/release.md" 'git.head'
assert_contains "apps/docs/docs/developer/release.md" 'git.statusShort'
assert_contains "apps/docs/docs/developer/release.md" "rejects unsafe archive paths before extraction"
assert_contains "apps/docs/docs/developer/release.md" "rejects command log paths that escape the evidence directory"
assert_contains "apps/docs/docs/developer/release.md" 'known `vm/targets.tsv` target ids exactly once'
assert_contains "apps/docs/docs/developer/release.md" 'keep each `evidenceDir` relative and target-scoped'
assert_contains "apps/docs/docs/developer/release.md" 'bash scripts/verify-vm-evidence.sh --target'
assert_contains "apps/docs/docs/developer/release.md" "--require-github-release-source"
assert_contains "apps/docs/docs/developer/release.md" "verify-published-release.sh --require-github-release-source"
assert_contains "apps/docs/docs/developer/release.md" "vm-launch-plan.tsv"
assert_contains "apps/docs/docs/developer/release.md" "scripts/collect-vm-evidence-ssh.sh --execute"
assert_contains "apps/docs/docs/developer/release.md" "dsp-provider-plan.tsv"
assert_contains "apps/docs/docs/developer/release.md" "scripts/collect-dsp-provider-plan.sh"
assert_contains "apps/docs/docs/developer/release.md" 'scripts/fixtures/dsp-provider-configuration.json'
assert_contains "apps/docs/docs/developer/release.md" "loopwire-dsp-provider"
assert_contains "apps/docs/docs/developer/release.md" "read-source, write-output"
assert_contains "apps/docs/docs/developer/release.md" "verify-output operation rows"
assert_contains "apps/docs/docs/developer/release.md" "must invoke the expected script directly"
assert_contains "apps/docs/docs/developer/release.md" "same deployed docs base URL or hostname"
assert_contains "apps/docs/docs/developer/release.md" 'must not pass `--release-dir`'
assert_contains "apps/docs/docs/developer/release.md" 'remote prefix recorded in `release-evidence.json`'
assert_contains "apps/docs/docs/developer/release.md" "GitHub-hosted runners do not provide"
assert_contains "apps/docs/docs/developer/release.md" "--vm-target all"
assert_contains "apps/docs/docs/developer/release.md" ".vm/evidence/{target}"
assert_contains "apps/docs/docs/developer/release.md" "--list-commands"
assert_contains "apps/docs/docs/developer/release.md" "read-only DSP provider plan evidence"
assert_contains "apps/docs/docs/developer/release.md" "VM bundle verification as optional evidence"
assert_contains "apps/docs/docs/developer/release.md" 'expands `--vm-target all` from `vm/targets.tsv`'
assert_contains "apps/docs/docs/developer/release.md" "requires non-empty command logs"
assert_contains "apps/docs/docs/developer/release.md" 'release.findings` plus `release.blockers'
assert_contains "apps/docs/docs/developer/release.md" "--summarize-release-readiness-log"
assert_contains "apps/docs/docs/developer/release.md" "--release-dir dist/release"
assert_contains "apps/docs/docs/developer/release.md" "apps/docs/docs/public/install.sh"
assert_contains "apps/docs/docs/developer/release.md" "matches the canonical installer"
assert_contains "apps/docs/docs/developer/release.md" "the dry-run should include"
assert_contains "apps/docs/docs/developer/release.md" "dist/release/final-release-proof-plan.txt"
assert_contains "apps/docs/docs/developer/release.md" "fails closed if the built dist omits"
assert_contains "apps/docs/docs/developer/release.md" 'rejects unsafe `.` or `..`'
assert_contains "apps/docs/docs/developer/release.md" "pull-zone hostnames must be hostnames"
assert_contains "apps/docs/docs/developer/release.md" "required for final proof"
assert_contains "apps/docs/docs/developer/release.md" "--pull-zone-hostname docs.example.test"
assert_contains "apps/docs/docs/developer/release.md" "scripts/verify-docs-live.sh"
assert_contains "apps/docs/docs/developer/release.md" '--remote-prefix "$BUNNY_REMOTE_PREFIX"'
assert_contains "apps/docs/docs/developer/release.md" "same pull-zone prefix used for upload"
assert_contains "apps/docs/docs/developer/release.md" 'uses the required `BUNNY_PULL_ZONE_HOSTNAME` repository secret'
assert_contains "apps/docs/docs/developer/release.md" 'uses `BUNNY_REMOTE_PREFIX` when that optional secret exists'
assert_contains "apps/docs/docs/developer/release.md" "only to override the stored Bunny pull-zone target"
assert_contains "apps/docs/docs/developer/release.md" "published-release-smoke"
assert_contains "apps/docs/docs/developer/release.md" "same repo, tag, and public key"
assert_contains "apps/docs/docs/developer/release.md" "must not include"
assert_contains "apps/docs/docs/developer/release.md" "public key used to verify the release assets"
assert_contains "apps/docs/docs/developer/release.md" "BUNNY_PULL_ZONE_HOSTNAME"
assert_contains "apps/docs/docs/developer/release.md" "requires both canonical Linux tarballs"
assert_contains "apps/docs/docs/developer/release.md" "missing-architecture rejection case"
assert_contains "apps/docs/docs/developer/release.md" "tampered-asset rejection"
assert_contains "apps/docs/docs/developer/release.md" "unsafe absolute or parent-traversing paths"
assert_contains "apps/docs/docs/developer/release.md" "loopwire --background --help"
assert_contains "apps/docs/docs/developer/release.md" "libexec/loopwire"
assert_contains "apps/docs/docs/developer/release.md" "ubuntu-22.04-arm"
assert_contains "apps/docs/docs/developer/release.md" 'including `pnpm verify:tauri`'
assert_contains "apps/docs/docs/developer/release.md" 'one combined `SHA256SUMS`'
assert_contains "apps/docs/docs/developer/release.md" "v-prefixed semver release tag without path separators"
assert_contains "apps/docs/docs/developer/release.md" "rejects non-semver or path-like tag names"
assert_contains "apps/docs/docs/developer/release.md" "detached mode before any build"
assert_contains "apps/docs/docs/developer/release.md" "checks out the resolved tag before build/publish work"
assert_contains "apps/docs/docs/developer/release.md" "keeps tag verification enabled"
assert_contains "apps/docs/docs/developer/release.md" "public AArch64 proof still requires a tagged"
assert_contains "apps/docs/docs/developer/release.md" "pnpm release:prepare-key"
assert_contains "apps/docs/docs/developer/release.md" "refuses to write the private key inside the repository"
assert_contains "apps/docs/docs/developer/release.md" "scripts/deploy-docs-bunny.sh"
assert_contains "apps/docs/docs/developer/release.md" "docs-live-smoke"
assert_contains "apps/docs/docs/developer/release.md" "loopwire.docs-deployment.v1"
assert_contains "apps/docs/docs/developer/release.md" "pnpm verify:docs-deployment"
assert_contains "apps/docs/docs/developer/release.md" "rejects checksum drift"
assert_contains "apps/docs/docs/developer/release.md" "source git head"
assert_contains "apps/docs/docs/developer/release.md" "rejects source git head drift"
assert_contains "apps/docs/docs/developer/release.md" "loopwire-docs-deployment"
assert_contains "apps/docs/docs/developer/release.md" "requires a clean git checkout"
assert_contains "apps/docs/docs/developer/release.md" "local or remote tag resolves"
assert_contains "apps/docs/docs/developer/release.md" "to the current checkout commit"
assert_contains "apps/docs/docs/developer/release.md" 'verifies that `pnpm verify:docs-deployment` is present'
assert_contains "apps/docs/docs/developer/release.md" 'verifies that `pnpm verify:final-release`'
assert_contains "apps/docs/docs/developer/release.md" '`pnpm vm:package-evidence`'
assert_contains "apps/docs/docs/developer/release.md" '`pnpm vm:prepare-release-evidence` command plan'
assert_contains "apps/docs/docs/developer/release.md" '`gh release upload --clobber` command'
assert_contains "apps/docs/docs/developer/release.md" "--skip-clean-git"
assert_contains "apps/docs/docs/developer/release.md" "BUNNY_STORAGE_ENDPOINT"
assert_contains "apps/docs/docs/developer/release.md" "BUNNY_REMOTE_PREFIX"
assert_contains "apps/docs/docs/developer/release.md" "--check --scope deploy"
assert_contains "apps/docs/docs/developer/release.md" 'default `--scope final`'
assert_contains "apps/docs/docs/developer/release.md" 'underlying `gh secret list` error'
assert_contains "apps/docs/docs/developer/release.md" "prints next-step commands with placeholders"
assert_contains "apps/docs/docs/developer/release.md" "only Bunny.net storage or live-docs secrets are missing"
assert_contains "apps/docs/docs/developer/release.md" "it prints only the release signing command"
assert_contains "apps/docs/docs/developer/release.md" '`pnpm verify:release-readiness` also prints no-value next steps'
assert_contains "apps/docs/docs/developer/release.md" 'git tag -a <tag> -m "Loopwire <tag>"'
assert_contains "apps/docs/docs/developer/release.md" "post-upload live"
assert_contains "apps/docs/docs/developer/release.md" 'storage-zone password in the `AccessKey` header'
assert_contains "apps/docs/docs/developer/architecture.md" "pw-cli create-node adapter"
assert_contains "apps/docs/docs/developer/architecture.md" "minimize, maximize/restore"
assert_contains "apps/docs/docs/developer/architecture.md" "and close controls"
assert_contains "apps/docs/docs/developer/architecture.md" '`jack_lsp`, `jack_connect`, and `jack_disconnect`'
assert_contains "apps/docs/docs/developer/architecture.md" "injected JACK virtual port provider"
assert_contains "apps/docs/docs/developer/architecture.md" "rejects argument shapes outside Loopwire's detector/runtime contract"
assert_contains "apps/docs/docs/developer/architecture.md" '`arecord -l`'
assert_contains "apps/docs/docs/developer/architecture.md" "pure DSP mix planner, renderer, and cycle runner"
assert_contains "apps/docs/docs/developer/architecture.md" "injected DSP graph adapter"
assert_contains "apps/docs/docs/developer/architecture.md" "command-backed DSP provider helper"
assert_contains "apps/docs/docs/developer/architecture.md" "restore-on-rollback behavior"
assert_contains "apps/docs/docs/developer/architecture.md" "first-class configuration runtime adapter wrapper"
assert_contains "apps/docs/docs/developer/architecture.md" "consume detected backend mixing semantics"
assert_contains "apps/docs/docs/developer/architecture.md" "typed execution contract"
assert_contains "apps/docs/docs/developer/architecture.md" "does not yet connect live host capture streams"
assert_contains "apps/docs/docs/release-notes/0.1.0.md" "# v0.1.0"
assert_contains "apps/docs/docs/release-notes/0.1.0.md" "ALSA playback/capture visibility"
assert_contains "apps/docs/docs/release-notes/0.1.0.md" "Artifact, package-channel, and VM compatibility claims"
assert_contains "apps/docs/docs/release-notes/0.1.0.md" "Native PipeWire virtual output sink creation"
assert_contains "apps/docs/docs/release-notes/0.1.0.md" "Native PipeWire virtual monitor sink creation"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Unreleased"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "PipeWire source and monitor target pickers"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "ALSA playback/capture visibility"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "reports route controls as unavailable"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Native PipeWire can now create Loopwire-owned virtual output sinks"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Native PipeWire can now create Loopwire-owned virtual monitor sinks"
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'for `pactl`, `pw-cli`, `pw-link`'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "validates command arguments against Loopwire's detector/runtime contract"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "JACK source and monitor target pickers"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Native PipeWire route mute now disconnects configured existing links"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Native JACK route mute now disconnects configured existing connections"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "mute as implemented link disconnect behavior"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "live-apply preflight now lists every blocker"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "configuration-switch guard now"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Editing the active configuration now disarms live apply"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "re-arm before verifying the edited"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Background restore now tells users to open Settings > Audio backend"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "persisted state file is missing, unreadable, corrupt, or"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "incompatible: open Loopwire"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Changing the selected backend now runs a backend-change transaction"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "commits the backend as the saved startup-restore choice"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "only after the active configuration verifies"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "configuration-switch controls disabled while verification"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "is in flight"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "stale backend verification results are ignored"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Automatic single-backend selection now uses the same backend-change transaction path"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "first-run callout"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "runtime activity ledger"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "names routes blocked by non-100% gain"
assert_contains "apps/docs/docs/release-notes/unreleased.md" '`Reset gains` action'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "route gain sliders now lock"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "deterministic Loopwire-owned JACK port"
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'fails before `jack_connect`'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "live-apply preflight rules are now covered"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "route lane now creates and removes individual"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "configuration switching is now serialized"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "stale async runtime results"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Desktop source, output, and monitor cards now support endpoint removal"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "manual host binding fields"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Monitor visibility is now scoped per configuration"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "compact recovery tray"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "custom chrome now persists"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "native-first"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "minimize, maximize/restore, and close controls"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Native PipeWire monitor routing"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "native JACK adapter"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Source-checkout background restore runner"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "restore-on-boot control"
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'resolves the packaged `loopwire` launcher'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Restore-on-boot status now stays readable"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Restore-on-boot now names the active configuration and saved backend"
assert_contains "apps/docs/docs/release-notes/unreleased.md" '`loopwire --background --help`'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "loopwire --background"
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'requires `node` on `PATH`'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "local signed release directory"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "strict publish preflight log"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Release evidence manifests now expose parsed"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Bunny.net upload helper"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "loopwire.docs-deployment.v1"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "pnpm verify:docs-deployment"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "source git head"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Release readiness now fails if the docs deployment"
assert_contains \
  "apps/docs/docs/release-notes/unreleased.md" \
  "Release readiness now fails if the final release proof workflow"
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'reintroduces `--release-dir`'
assert_contains "apps/docs/docs/release-notes/unreleased.md" '`pnpm vm:prepare-release-evidence` wiring disappears'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "remain candidate-gated until public signed artifacts"
assert_contains "apps/docs/docs/release-notes/0.1.0.md" "These candidate-gated notes describe"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "loopwire-docs-deployment"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "BUNNY_STORAGE_ENDPOINT"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "BUNNY_REMOTE_PREFIX"
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'built dist omits `index.html`'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "scripts/verify-docs-live.sh"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "docs deployment live smoke now forwards"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "misreporting API or auth failures"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "do not point at the current checkout commit"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "requires a clean git checkout by default"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Release evidence collection can now include"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "--require-live-docs"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Host-side matrix VM evidence collection"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Direct SSH VM evidence collection now rejects unsafe"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "custom remote and local output paths"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "rejects unsafe local output paths"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "--require-all-targets"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "The GitHub secret helper now rejects Bunny storage zones"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "validate the release private key against the release public key"
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'current `gh secret set` stdin contract'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "prints no-value next steps"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "will skip live-docs smoke"
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'names-only `--secret-list-file` artifact'
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'New `pnpm release:handoff`'
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'New `pnpm release:fetch-docs-proof`'
assert_contains "apps/docs/docs/release-notes/unreleased.md" '`pnpm release:fetch-docs-proof` now rejects absolute'
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'New `pnpm release:status`'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "VM evidence asset preparation now rejects unsafe"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "redirect checksum regeneration"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Final release proof dry-runs now reject unsafe"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "root/home-expanded paths"
assert_contains "apps/docs/docs/release-notes/unreleased.md" '`pnpm release:status` now rejects unsafe local env-file'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "wrong existing"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "parseable release signing public key"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "non-dry-run docs deployment manifest proof"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "smaller required-secret"
assert_contains "apps/docs/docs/developer/release.md" "Final Release Proof"
assert_contains "apps/docs/docs/developer/release.md" "loopwire-vm-evidence-<tag>.tar.gz"
assert_contains "apps/docs/docs/developer/release.md" "workflow_dispatch"
assert_contains "apps/docs/docs/developer/release.md" "pnpm vm:package-evidence"
assert_contains "apps/docs/docs/developer/release.md" "pnpm vm:prepare-release-evidence"
assert_contains "apps/docs/docs/developer/release.md" "scripts/verify-release-asset-checksum.sh"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "pnpm vm:package-evidence"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "vm-evidence/<target>"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "basename must still be a validated"
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'manual `Final Release Proof` workflow'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Final release proof dry-runs can now write"
assert_contains "apps/docs/docs/release-notes/unreleased.md" '`--plan-output` file'
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'New `pnpm vm:package-evidence` command'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "validates custom output basenames"
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'New `pnpm vm:prepare-release-evidence` command'
assert_contains "apps/docs/docs/developer/release.md" 'Custom `--output` paths may point at temp locations'
assert_contains "apps/docs/docs/developer/release.md" "--release-public-key-file packaging/release-signing-public.pem"
assert_contains "apps/docs/docs/developer/release.md" "--secret-list-file release-secret-names.tsv"
assert_contains "apps/docs/docs/developer/release.md" "pnpm release:handoff"
assert_contains "apps/docs/docs/developer/release.md" 'Custom `--vm-ssh-plan` and `--vm-runbook` outputs'
assert_contains "apps/docs/docs/developer/release.md" 'validates custom `--release-dir` values'
assert_contains "apps/docs/docs/developer/release.md" 'regenerate `SHA256SUMS` or `SHA256SUMS.sig`'
assert_contains "apps/docs/docs/developer/release.md" 'validates `--env-file`, `--private-key`, `--public-key`, and `--evidence-root`'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "unsafe env-file, private-key, public-key, and evidence-root paths"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "signed VM evidence handoff"
assert_contains "apps/docs/docs/developer/release.md" 'When `--release-dir` is used for local signed-release rehearsal'
assert_contains "apps/docs/docs/developer/release.md" "release surface"
assert_contains "apps/docs/docs/developer/release.md" "pnpm release:fetch-docs-proof"
assert_contains "apps/docs/docs/developer/release.md" "must stay repo-relative"
assert_contains "apps/docs/docs/developer/release.md" "pnpm release:status"
assert_contains "apps/docs/docs/developer/release.md" 'If the docs deployment manifest is missing'
assert_contains "apps/docs/docs/developer/release.md" 'Custom local path inputs for `release:status`'
assert_contains "apps/docs/docs/developer/release.md" 'including `--env-file`, `--secret-list-file`'
assert_contains "apps/docs/docs/developer/release.md" "wrong file or directory type"
assert_contains "apps/docs/docs/developer/release.md" "uses that same root"
assert_contains "apps/docs/docs/developer/release.md" "release signing public key"
assert_contains "apps/docs/docs/developer/release.md" "docs deployment manifest"
assert_contains "apps/docs/docs/developer/release.md" "completed successful CI, Deploy Docs, and Final Release Proof"
assert_contains "apps/docs/docs/developer/release.md" "successful CI, docs, or proof run for an older commit"
assert_contains "apps/docs/docs/developer/release.md" "--docs-deployment-manifest"
assert_contains "apps/docs/docs/developer/release.md" "--docs-dist"
assert_contains "apps/docs/docs/developer/release.md" "loopwire-docs-deployment"
assert_contains "apps/docs/docs/developer/release.md" "<docs-deployment-run-id>"
assert_contains "apps/docs/docs/developer/release.md" 'Local file inputs for `--env-file`, `--secret-list-file`'
assert_contains "apps/docs/docs/developer/release.md" '`--release-private-key-file`, and `--release-public-key-file`'
assert_contains "apps/docs/docs/developer/release.md" "fails before any secret write if the pair"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "release private-key, and release"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "before reading those artifacts"
assert_contains "apps/docs/docs/developer/release.md" "contains the project release public key"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "now contains the project release public key"
assert_contains "apps/docs/docs/developer/release.md" 'matching `LOOPWIRE_RELEASE_PRIVATE_KEY` secret'
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'matching `LOOPWIRE_RELEASE_PRIVATE_KEY` secret'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "latest CI workflow run for the expected commit"
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'same hosted `pnpm check` gate'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "rejects absolute or parent-traversal VM handoff output paths"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "no longer gets release-key reset guidance"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Release readiness now prints no-value next steps"
assert_contains "apps/docs/docs/release-notes/0.1.0.md" 'matching `LOOPWIRE_RELEASE_PRIVATE_KEY` secret'
assert_contains "apps/docs/docs/release-notes/0.1.0.md" 'Bunny.net docs deployment requires `BUNNY_STORAGE_ZONE`'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Desktop JACK live-apply preflight"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "shared audio-host helper"
assert_contains "apps/docs/docs/release-notes/unreleased.md" '`pnpm jack:ports`'
assert_contains "apps/docs/docs/release-notes/unreleased.md" '`pnpm jack:verify`'
assert_contains "apps/docs/docs/release-notes/unreleased.md" '`pnpm dsp:plan`'
assert_contains "apps/docs/docs/release-notes/unreleased.md" '`pnpm dsp:verify`'
assert_contains "apps/docs/docs/release-notes/unreleased.md" '`loopwire-dsp-provider`'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "--dsp-provider-mode live"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "supportsLiveGraph:true"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "--require-live-capability"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Support bundles can include read-only JACK readiness"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "injected JACK virtual port provider"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "loopwire-jack-ports"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "--jack-provider-command"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "same runtime contract"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Release workflow now has x86_64 and AArch64"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "manual dispatch now checks out the resolved tag"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "keeps tag verification enabled after the detached checkout"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "reject non-semver or path-like release tags"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "path-like manifest or expected"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "URLs or extra path segments instead of plain"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Published release verification now rejects release directories missing"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Published release verification now supports"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "no matching live stream"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "keep absent matching streams pending"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "VM evidence promotion can now require published-release smoke"
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'VM evidence promotion can now run in `--all` mode'
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'New `pnpm vm:evidence-status` command'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "missing, invalid, and verified evidence bundles"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "one-source-to-many-output routes"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "pure DSP mix planner/renderer plus an injected"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "injected DSP graph adapter"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "restores the rollback configuration"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "first-class configuration runtime adapter wrapper"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "consume detected backend mixing"
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'expose `one output per source` as a known gap'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "retry pending app-stream routes"
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'records `desktop-launch.log`'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "published-release installer smoke inside the guest"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "require verified VM evidence"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "GitHub release source"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "all declared VM matrix targets"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "verify final release evidence bundles"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "green smoke against the wrong deployment"
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'fake `published-release-smoke` rows'
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'rows that include `--release-dir`'
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'specific signing public key with `--public-key`'
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'resolved release tag commit with `--git-head`'
assert_contains "apps/docs/docs/release-notes/unreleased.md" '`pnpm verify:final-release`'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "support-matrix verifier can now require installed-release smoke"
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'validates custom `--matrix` and `--evidence-root` paths'
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'stricter mode for `Verified` rows'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "loopwire-release-evidence-<tag>"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "loopwire-release-evidence-<tag>.tar.gz"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "covered by the same signed checksum manifest"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "--require-release-evidence"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "--require-dsp-provider-plan"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "--require-clean-git"
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'expected `release.tag` and repo'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "archive-name and manifest tag drift"
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'git.head'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "rejects unsafe archive paths before extraction"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "manifest command logs that escape the evidence directory"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "rejects malformed VM evidence manifest rows"
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'unsafe `evidenceDir` paths'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "tokenizes final proof command rows"
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'Product requirement verification now runs in `pnpm check`'
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'writes `environment.json`'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "does not report the selected target's expected"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "VM host planning now prints cross-distro virtualization setup hints"
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'dry-run-only `pnpm vm:host-setup`'
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'New `pnpm vm:launch` command'
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'New `pnpm vm:render-launch-plan` command'
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'New `pnpm vm:render-runbook` command'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "VM evidence runbooks now include the final-release"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "VM evidence collectors now forward"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "VM host setup now supports"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "VM host setup hints are now architecture-scoped"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "VM launch dry-runs now stay non-mutating"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "VM launch now supports"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "VM launch planning now rejects invalid memory"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "VM evidence collectors now reject invalid"
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'VM doctor now treats `cloud-localds` as a required'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "VM doctor now supports"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "VM evidence promotion now has a guarded"
assert_contains "apps/docs/docs/release-notes/unreleased.md" '`pnpm release:status --vm-evidence-root`'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "VM cloud-init rendering can now generate guest bootstrap assets"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Debian and Ubuntu VM cloud-init commands"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Non-Nix VM cloud-init commands now install Rust"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "NixOS VM cloud-init commands"
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'packages.<system>.loopwire-bin'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "fake hashes"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "VitePress public installer asset"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "unsafe absolute or parent-traversing archive paths"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Release readiness now fails if the public docs installer drifts"
assert_contains "apps/docs/docs/developer/release.md" 'Custom `--public-key` and `--secret-list-file` values'
assert_contains "apps/docs/docs/developer/release.md" "before parsing a key or replaying saved secret names"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Release readiness now validates custom public-key"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "existing non-file paths"
assert_contains "apps/docs/docs/developer/release.md" 'Custom `--output-dir` values are local evidence directories only'
assert_contains "apps/docs/docs/developer/release.md" 'before writing command logs or `release-evidence.json`'
assert_contains "apps/docs/docs/developer/release.md" "The summarized readiness log path is also a local file artifact"
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'Release evidence collection now validates `--output-dir`'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "wrong existing file/directory types"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "opensuse-kde-pipewire"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "AArch64 Ubuntu target"
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'CRC-corrupt `screenshot.png` placeholders'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "pnpm verify:tauri"
assert_contains "apps/docs/docs/public/product-screenshot.svg" "Loopwire desktop shell screenshot"
assert_contains "apps/docs/docs/release-notes/0.1.0.md" "Nix flake"
assert_contains "apps/docs/docs/release-notes/0.1.0.md" "fake hashes"

echo "Docs contract verification passed."
