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

node "$root/scripts/verify-support-matrix.mjs"

assert_contains "apps/docs/docs/.vitepress/config.ts" "/guide/support-matrix"
assert_contains "apps/docs/docs/.vitepress/config.ts" "/guide/troubleshooting"
assert_contains "apps/docs/docs/.vitepress/config.ts" "/developer/release-notes"
assert_contains "apps/docs/docs/.vitepress/config.ts" "/release-notes/0.1.0"
assert_contains "apps/docs/docs/.vitepress/config.ts" "/release-notes/unreleased"
assert_contains "apps/docs/docs/index.md" "/product-screenshot.svg"
assert_contains "apps/docs/docs/index.md" "A desktop-grade routing workspace"
assert_contains "apps/docs/docs/index.md" "Current source install"
assert_contains "apps/docs/docs/index.md" "v0.1.0 candidate"
assert_contains "apps/docs/docs/index.md" "Release ceremony"
assert_contains "apps/docs/docs/index.md" "--output-dir .release-evidence/v0.1.0 --profile full --release-tag v0.1.0"
assert_contains "apps/docs/docs/guide/support-matrix.md" "arch-hyprland-pipewire"
assert_contains "apps/docs/docs/guide/support-matrix.md" "fedora-kde-jack"
assert_contains "apps/docs/docs/guide/support-matrix.md" "debian-xfce-pulseaudio"
assert_contains "apps/docs/docs/guide/support-matrix.md" "desktop launch smoke"
assert_contains "apps/docs/docs/guide/support-matrix.md" "environment.json"
assert_contains "apps/docs/docs/guide/support-matrix.md" "packaged user-scoped systemd restore paths are verified locally"
assert_contains "apps/docs/docs/guide/support-matrix.md" "pnpm vm:promote-evidence -- --target"
assert_contains "apps/docs/docs/guide/support-matrix.md" "Virtual sinks, routes, mute, monitor links"
assert_contains "apps/docs/docs/guide/backends.md" "list PipeWire output ports as source candidates"
assert_contains "apps/docs/docs/guide/backends.md" "create Loopwire-owned virtual output and monitor sinks"
assert_contains "apps/docs/docs/guide/backends.md" "virtual monitor sink ports"
assert_contains "apps/docs/docs/guide/backends.md" "disconnect configured route links when a route is muted"
assert_contains "apps/docs/docs/guide/backends.md" "host-backed output and physical monitor target candidates"
assert_contains "apps/docs/docs/guide/backends.md" "native JACK adapter"
assert_contains "apps/docs/docs/guide/backends.md" "list JACK output ports as source candidates"
assert_contains "apps/docs/docs/guide/backends.md" "disconnect configured route connections when a route is muted"
assert_contains "apps/docs/docs/guide/backends.md" "physical monitor sink ports"
assert_contains "apps/docs/docs/guide/backends.md" "no matching live stream"
assert_contains "apps/docs/docs/guide/backends.md" "pending during startup and background restore"
assert_contains "apps/docs/docs/guide/backends.md" "refresh pending stream routes"
assert_contains "apps/docs/docs/guide/configurations.md" "detected PipeWire output ports"
assert_contains "apps/docs/docs/guide/configurations.md" "Native PipeWire can create Loopwire-owned virtual output and monitor sinks"
assert_contains "apps/docs/docs/guide/configurations.md" "native PipeWire and the"
assert_contains "apps/docs/docs/guide/configurations.md" "native PipeWire/JACK target ports also appear in the output picker"
assert_contains "apps/docs/docs/guide/configurations.md" "add or remove individual route edges"
assert_contains "apps/docs/docs/guide/configurations.md" "one edge per"
assert_contains "apps/docs/docs/guide/configurations.md" "Removing an input or output prunes the routes"
assert_contains "apps/docs/docs/guide/configurations.md" "manual host binding fields"
assert_contains "apps/docs/docs/guide/configurations.md" "Clearing the field returns the endpoint"
assert_contains "apps/docs/docs/guide/configurations.md" "Monitor visibility is scoped to the active configuration"
assert_contains "apps/docs/docs/guide/configurations.md" "preflight strip lists every blocker"
assert_contains "apps/docs/docs/guide/troubleshooting.md" "pnpm detect:audio"
assert_contains "apps/docs/docs/guide/troubleshooting.md" "pnpm collect:support"
assert_contains "apps/docs/docs/guide/troubleshooting.md" "absent app stream cannot prove"
assert_contains "apps/docs/docs/guide/troubleshooting.md" "Pending matching PulseAudio"
assert_contains "apps/docs/docs/guide/troubleshooting.md" "pendingStreamRefresh"
assert_contains "apps/docs/docs/guide/troubleshooting.md" "creates a virtual PipeWire sink"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "pnpm restore:background"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "Packaged Background Restore Path"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "Open on boot"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "Restore on boot"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "loopwire --background"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "default.target.wants/loopwire.service"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "--source-dir"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "pending until those apps launch"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "--retry-pending-ms"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "pendingStreamRefresh.cleared"
assert_contains "apps/docs/docs/developer/screenshots.md" "product-screenshot.svg"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "collect-vm-evidence.sh"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "desktop-launch.log"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "environment.json"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "LOOPWIRE_EVIDENCE_SESSION"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "--desktop-port 5199"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "support-bundle/support-bundle.json"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "host-install-hint=*"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "pnpm vm:promote-evidence"
assert_contains "apps/docs/docs/developer/vm-matrix.md" 'only changes rows from `Manual VM` to'
assert_contains "apps/docs/docs/developer/vm-matrix.md" "pnpm vm:host-plan"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "pnpm vm:render-cloud-init -- --all"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "verify-cloud-init"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "sudo npm install -g pnpm@11.3.0"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "NixOS cloud-init guest commands"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "operator-owned image policy"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "does not render cloud-init, and does not write"
assert_contains "apps/docs/docs/developer/vm-matrix.md" 'Use `--ssh-port`'
assert_contains "apps/docs/docs/developer/vm-matrix.md" 'collect-vm-evidence-ssh.sh --port'
assert_contains "apps/docs/docs/developer/vm-matrix.md" "valid TCP ports from 1 to 65535"
assert_contains "apps/docs/docs/developer/vm-matrix.md" "validates the port range"
assert_contains "apps/docs/docs/developer/vm-matrix.md" 'missing `cloud-localds`'
assert_contains "apps/docs/docs/developer/release-notes.md" "Release-note workflow"
assert_contains "apps/docs/docs/developer/release-notes.md" "release workflow reject"
assert_contains "apps/docs/docs/developer/release.md" "redacted support bundle"
assert_contains "apps/docs/docs/developer/release.md" "rejects release-candidate/not-published wording"
assert_contains "apps/docs/docs/developer/release.md" "--release-tag v0.1.0"
assert_contains "apps/docs/docs/developer/release.md" "--require-published-release"
assert_contains "apps/docs/docs/developer/release.md" "--list-commands"
assert_contains "apps/docs/docs/developer/release.md" "strict publish preflight and published-release installer smoke"
assert_contains "apps/docs/docs/developer/release.md" 'release.findings` plus `release.blockers'
assert_contains "apps/docs/docs/developer/release.md" "--summarize-release-readiness-log"
assert_contains "apps/docs/docs/developer/release.md" "--release-dir dist/release"
assert_contains "apps/docs/docs/developer/release.md" "requires both canonical Linux tarballs"
assert_contains "apps/docs/docs/developer/release.md" "missing-architecture rejection case"
assert_contains "apps/docs/docs/developer/release.md" "tampered-asset rejection"
assert_contains "apps/docs/docs/developer/release.md" "loopwire --background --help"
assert_contains "apps/docs/docs/developer/release.md" "libexec/loopwire"
assert_contains "apps/docs/docs/developer/release.md" "ubuntu-22.04-arm"
assert_contains "apps/docs/docs/developer/release.md" 'one combined `SHA256SUMS`'
assert_contains "apps/docs/docs/developer/release.md" "public AArch64 proof still requires a tagged"
assert_contains "apps/docs/docs/developer/release.md" "pnpm release:prepare-key"
assert_contains "apps/docs/docs/developer/release.md" "refuses to write the private key inside the repository"
assert_contains "apps/docs/docs/developer/release.md" "scripts/deploy-docs-bunny.sh"
assert_contains "apps/docs/docs/developer/release.md" "BUNNY_STORAGE_ENDPOINT"
assert_contains "apps/docs/docs/developer/release.md" 'storage-zone password in the `AccessKey` header'
assert_contains "apps/docs/docs/developer/architecture.md" "pw-cli create-node adapter"
assert_contains "apps/docs/docs/release-notes/0.1.0.md" "v0.1.0 Release Candidate"
assert_contains "apps/docs/docs/release-notes/0.1.0.md" "not proof that signed artifacts"
assert_contains "apps/docs/docs/release-notes/0.1.0.md" "Native PipeWire virtual output sink creation"
assert_contains "apps/docs/docs/release-notes/0.1.0.md" "Native PipeWire virtual monitor sink creation"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Unreleased"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "PipeWire source and monitor target pickers"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Native PipeWire can now create Loopwire-owned virtual output sinks"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Native PipeWire can now create Loopwire-owned virtual monitor sinks"
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'for `pactl`, `pw-cli`, `pw-link`'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "JACK source and monitor target pickers"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Native PipeWire route mute now disconnects configured existing links"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Native JACK route mute now disconnects configured existing connections"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "mute as implemented link disconnect behavior"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "live-apply preflight now lists every blocker"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "route lane now creates and removes individual"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Desktop source, output, and monitor cards now support endpoint removal"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "manual host binding fields"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Monitor visibility is now scoped per configuration"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "custom chrome now persists"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Native PipeWire monitor routing"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "native JACK adapter"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Source-checkout background restore runner"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "restore-on-boot control"
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'resolves the packaged `loopwire` launcher'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "loopwire --background"
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'requires `node` on `PATH`'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "local signed release directory"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "strict publish preflight log"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Release evidence manifests now expose parsed"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Bunny.net upload helper"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "BUNNY_STORAGE_ENDPOINT"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Release evidence collection can now include"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Release workflow now has x86_64 and AArch64"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Published release verification now rejects release directories missing"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "no matching live stream"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "keep absent matching streams pending"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "retry pending app-stream routes"
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'records `desktop-launch.log`'
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'writes `environment.json`'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "VM host planning now prints cross-distro virtualization setup hints"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "VM launch dry-runs now stay non-mutating"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "VM launch now supports"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "VM evidence collectors now reject invalid"
assert_contains "apps/docs/docs/release-notes/unreleased.md" 'VM doctor now treats `cloud-localds` as a required'
assert_contains "apps/docs/docs/release-notes/unreleased.md" "VM evidence promotion now has a guarded"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "VM cloud-init rendering can now generate guest bootstrap assets"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Debian and Ubuntu VM cloud-init commands"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "NixOS VM cloud-init commands"
assert_contains "apps/docs/docs/public/product-screenshot.svg" "Loopwire desktop shell screenshot"

echo "Docs contract verification passed."
