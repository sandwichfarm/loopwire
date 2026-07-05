#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "verify-requirements: $*" >&2
  exit 1
}

assert_file() {
  [ -f "$1" ] || fail "missing file: $1"
}

assert_contains() {
  local file="$1"
  local needle="$2"

  assert_file "$file"
  grep -F -- "$needle" "$file" >/dev/null || fail "missing requirement evidence in $file: $needle"
}

assert_script() {
  node -e '
const fs = require("node:fs");
const packagePath = process.argv[1];
const name = process.argv[2];
const expected = process.argv[3];
const pkg = JSON.parse(fs.readFileSync(packagePath, "utf8"));
if (pkg.scripts?.[name] !== expected) process.exit(1);
' "$1" "$2" "$3" || fail "package script $2 does not match expected command"
}

assert_requirement_checked() {
  assert_contains ".planning/REQUIREMENTS.md" "- [x] **$1**"
}

assert_requirement_pending() {
  assert_contains ".planning/REQUIREMENTS.md" "- [ ] **$1**"
}

for requirement in UX-01 UX-02 UX-03 UX-04; do
  assert_requirement_checked "$requirement"
done

assert_contains "apps/desktop/src/App.svelte" "Chrome"
assert_contains "apps/desktop/src/App.svelte" "segmented-control"
assert_contains "apps/desktop/src/chrome-mode-summary.ts" "System chrome preferred"
assert_contains "apps/desktop/src/App.svelte" "applyWindowChrome"
assert_contains "apps/desktop/src/App.svelte" "setMonitorHidden"
assert_contains "apps/docs/docs/guide/troubleshooting.md" "Window Controls Look Wrong"

for requirement in BACKEND-01 BACKEND-02 BACKEND-03 BACKEND-04 BACKEND-05; do
  assert_requirement_checked "$requirement"
done

assert_contains "packages/audio-host/src/detectors.ts" "detectAudioBackends"
assert_contains "packages/audio-host/src/detectors.ts" "detectPipeWire"
assert_contains "packages/audio-host/src/detectors.ts" "detectPulseAudio"
assert_contains "packages/audio-host/src/detectors.ts" "detectJack"
assert_contains "packages/audio-host/src/detectors.ts" "detectAlsa"
assert_contains "packages/core/src/backend-selection.ts" "Exactly one supported audio backend is available."
assert_contains "packages/core/src/backend-selection.ts" "Multiple supported audio backends are available. The user must choose one."
assert_contains "apps/desktop/src/App.svelte" "handleBackendChange"

for requirement in CONFIG-01 CONFIG-02 CONFIG-03 CONFIG-04; do
  assert_requirement_checked "$requirement"
done

assert_contains "packages/core/src/configuration.ts" "createConfiguration"
assert_contains "packages/core/src/runtime.ts" "applyConfigurationSwitch"
assert_contains "packages/core/src/persistence.ts" "restoreState"
assert_contains "apps/desktop/src-tauri/src/main.rs" "write_state"
assert_contains "scripts/restore-background.mjs" "choose and persist one before enabling background restore"
assert_contains "scripts/restore-background.mjs" "Open Loopwire, use Settings > Audio backend to save a verified backend"
assert_contains "scripts/restore-background.mjs" "Open Loopwire once, choose a configuration, and enable Restore on boot again."
assert_contains "scripts/restore-background.mjs" "Could not restore persisted Loopwire state at"

for requirement in LINUX-01 LINUX-02 LINUX-03 LINUX-04; do
  assert_requirement_checked "$requirement"
done

assert_contains "apps/desktop/src-tauri/tauri.conf.json" '"decorations": true'
assert_contains "scripts/manage-autostart.sh" "systemd"
assert_contains "scripts/install.sh" "detect_arch"
assert_contains "scripts/install.sh" "loopwire-linux-aarch64.tar.gz"
assert_file "packaging/aur/PKGBUILD.in"
assert_file "packaging/nix/loopwire-bin.nix"
assert_file "flake.nix"
assert_contains "flake.nix" "packages = forEachSystem"
assert_contains "flake.nix" "loopwire-bin = loopwireBin"
assert_contains "flake.nix" "mkLoopwireBinPackage"
assert_file "scripts/render-nix-release-package.sh"
assert_file "scripts/verify-nix-release-package.sh"
assert_script "package.json" "nix:render-release" "bash scripts/render-nix-release-package.sh"
assert_script "package.json" "verify:nix-release" "bash scripts/verify-nix-release-package.sh"
assert_script "package.json" "release:agent-ready" "bash scripts/verify-agent-release-ready.sh"

for requirement in DOCS-01 DOCS-02 DOCS-03 DOCS-04; do
  assert_requirement_checked "$requirement"
done

assert_script "package.json" "build:docs" "pnpm --filter @loopwire/docs docs:build"
assert_contains "apps/docs/docs/index.md" "product-screenshot"
assert_contains "apps/docs/docs/index.md" "git clone https://github.com/sandwichfarm/loopwire"
assert_contains "apps/docs/docs/index.md" "curl -fsSL https://&lt;docs-host&gt;/install.sh \\"
assert_contains "apps/docs/docs/index.md" "  | sh"
assert_contains "apps/docs/docs/index.md" "loopwire --background --mode preview"
assert_contains "apps/docs/docs/guide/backends.md" "Loopwire is designed around a backend contract"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "background restore"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Release evidence verification"

for requirement in QUAL-01 QUAL-02 QUAL-03 QUAL-04 QUAL-05; do
  assert_requirement_checked "$requirement"
done

assert_script "package.json" "check" "pnpm check:verify && pnpm lint && pnpm typecheck && pnpm test && pnpm build"
assert_script "package.json" "check:verify" \
  "pnpm verify:requirements && pnpm verify:scripts && pnpm verify:workflows && pnpm verify:runtime && pnpm verify:tauri"
assert_script "package.json" "verify:requirements" "bash scripts/verify-requirements.sh"
assert_contains "packages/core/tests/configuration.test.ts" "keeps independent route controls"
assert_contains ".github/workflows/ci.yml" "pnpm check"
assert_contains ".github/workflows/continuous-tests.yml" "Linux host audio diagnostics"
assert_contains ".github/workflows/vm-matrix.yml" "Validate VM target matrix"
assert_contains ".github/workflows/deploy-docs.yml" "Deploy to Bunny.net"
assert_contains "scripts/setup-github-secrets.sh" "BUNNY_STORAGE_ZONE"
assert_contains "scripts/setup-github-secrets.sh" "LOOPWIRE_RELEASE_PRIVATE_KEY"

for requirement in ROUTE-01 ROUTE-02 ROUTE-03 ROUTE-04 ROUTE-05; do
  assert_requirement_checked "$requirement"
done

assert_contains "packages/audio-host/tests/runtime-adapter.test.ts" "physical monitor"
assert_contains "packages/audio-host/tests/pipewire-adapter.test.ts" "links matching PipeWire ports"
assert_contains "packages/audio-host/tests/jack-adapter.test.ts" "connects matching JACK ports"
assert_contains "packages/core/tests/configuration.test.ts" "keeps independent route controls"

for requirement in SHIP-01 SHIP-02 SHIP-03; do
  assert_requirement_pending "$requirement"
done

assert_contains ".planning/REQUIREMENTS.md" "v1 requirements: 26 total, 26 complete"
assert_contains ".planning/REQUIREMENTS.md" "SHIP-01..SHIP-03 | Phase 12 | Pending"

echo "Product requirements evidence verified."
