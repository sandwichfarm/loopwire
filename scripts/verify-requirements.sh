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

assert_contains "apps/desktop/src/lib/components/AppShell.svelte" "Sidebar"
assert_contains "apps/desktop/src/lib/components/DeviceCanvas.svelte" "CableLayer"
assert_contains ".planning/REQUIREMENTS.md" "custom-chrome fallback removed in the UI rebuild"
assert_contains "apps/desktop/src/lib/stores/uiStore.ts" "toggleMonitorsHidden"
assert_contains "apps/desktop/src/lib/components/CanvasFooter.svelte" "Show Monitors"
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
assert_contains "apps/desktop/src/lib/components/SettingsWindow.svelte" "chooseBackend"

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
assert_file "packaging/aur/loopwire/PKGBUILD.in"
assert_file "packaging/aur/loopwire-bin/PKGBUILD.in"
assert_file "scripts/deploy-aur-package.sh"
assert_file "scripts/verify-aur-source-package.sh"
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
assert_script "package.json" "deploy:aur" "bash scripts/deploy-aur-package.sh"

for requirement in DOCS-01 DOCS-02 DOCS-03 DOCS-04; do
  assert_requirement_checked "$requirement"
done

assert_script "package.json" "build:docs" "pnpm --filter @loopwire/docs docs:build"
assert_script "package.json" "build:site" "pnpm --filter @loopwire/site build"
assert_script "package.json" "build:web" "pnpm build:site && pnpm build:docs && node scripts/build-static-site.mjs"
assert_contains "apps/docs/docs/index.md" "product-screenshot"
assert_contains "apps/docs/docs/index.md" "Loopwire Docs"
assert_contains "apps/docs/docs/guide/basic-usage.md" "This is the shortest honest Loopwire walkthrough"
assert_contains "apps/docs/docs/guide/backends.md" "Loopwire is designed around a backend contract"
assert_contains "apps/docs/docs/guide/start-on-boot.md" "background restore"
assert_contains "apps/docs/docs/release-notes/unreleased.md" "Release evidence verification"
assert_file "apps/site/package.json"
assert_contains "apps/site/src/pages/index.astro" "Linux virtual audio routing"

for requirement in QUAL-01 QUAL-02 QUAL-03 QUAL-04 QUAL-05; do
  assert_requirement_checked "$requirement"
done

assert_script "package.json" "check" "pnpm check:verify && pnpm lint && pnpm typecheck && pnpm test && pnpm build && pnpm verify:site"
assert_script "package.json" "check:verify" \
  "pnpm verify:requirements && pnpm verify:docs && pnpm test:setup-github && pnpm verify:scripts && pnpm verify:workflows && pnpm verify:runtime && pnpm verify:tauri"
assert_script "package.json" "verify:requirements" "bash scripts/verify-requirements.sh"
assert_script "package.json" "setup:github" "node scripts/setup-github-actions.mjs"
assert_script "package.json" "test:setup-github" "node scripts/test-setup-github-actions.mjs"
assert_contains "packages/core/tests/configuration.test.ts" "keeps independent route controls"
assert_contains ".github/workflows/ci.yml" "pnpm check"
assert_contains ".github/workflows/continuous-tests.yml" "Linux host audio diagnostics"
assert_contains ".github/workflows/vm-matrix.yml" "Validate VM target matrix"
assert_contains ".github/workflows/deploy-docs.yml" "Deploy to Bunny.net"
assert_contains ".github/workflows/deploy-docs.yml" "pnpm build:web"
assert_contains ".github/workflows/deploy-docs.yml" "dist/site"
assert_contains "scripts/setup-github-secrets.sh" "BUNNY_STORAGE_ZONE"
assert_contains "scripts/setup-github-secrets.sh" "LOOPWIRE_RELEASE_PRIVATE_KEY"
assert_contains "scripts/setup-github-actions.mjs" "Variables and secrets are sent to gh through stdin"
assert_contains "scripts/setup-github-actions.mjs" "FTP & API Access"

for requirement in ROUTE-01 ROUTE-02 ROUTE-03 ROUTE-04 ROUTE-05; do
  assert_requirement_checked "$requirement"
done

assert_contains "packages/audio-host/tests/runtime-adapter.test.ts" "physical monitor"
assert_contains "packages/audio-host/tests/pipewire-adapter.test.ts" "links matching PipeWire ports"
assert_contains "packages/audio-host/tests/jack-adapter.test.ts" "connects matching JACK ports"
assert_contains "packages/core/tests/configuration.test.ts" "keeps independent route controls"

for requirement in WEB-01 WEB-02 WEB-03 WEB-04 WEB-05; do
  assert_requirement_checked "$requirement"
done

for requirement in OPS-01 OPS-02 OPS-03 OPS-04 OPS-05; do
  assert_requirement_checked "$requirement"
done

for requirement in SHIP-01 SHIP-02 SHIP-03; do
  assert_requirement_pending "$requirement"
done

assert_contains ".planning/REQUIREMENTS.md" "v1 requirements: 26 total, 26 complete"
assert_contains ".planning/REQUIREMENTS.md" "SHIP-01..SHIP-03 | Phase 12 | Pending"

echo "Product requirements evidence verified."
