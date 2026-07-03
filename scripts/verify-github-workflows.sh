#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "verify-github-workflows: $*" >&2
  exit 1
}

assert_file() {
  local file="$1"

  [ -s "$root/$file" ] || fail "missing workflow file: $file"
}

assert_contains() {
  local file="$1"
  local needle="$2"

  if ! grep -Fq -- "$needle" "$root/$file"; then
    fail "missing workflow content in $file: $needle"
  fi
}

if ! command -v ruby >/dev/null 2>&1; then
  fail "ruby is required to parse workflow YAML"
fi

workflows=(
  ".github/workflows/ci.yml"
  ".github/workflows/continuous-tests.yml"
  ".github/workflows/deploy-docs.yml"
  ".github/workflows/release.yml"
  ".github/workflows/vm-matrix.yml"
)

for workflow in "${workflows[@]}"; do
  assert_file "$workflow"
done

ruby_paths=()
for workflow in "${workflows[@]}"; do
  ruby_paths+=("$root/$workflow")
done

ruby -e 'require "yaml"; ARGV.each { |path| YAML.load_file(path); puts path }' "${ruby_paths[@]}" >/dev/null

assert_contains ".github/workflows/ci.yml" "pnpm check"
assert_contains ".github/workflows/ci.yml" "cargo check --manifest-path apps/desktop/src-tauri/Cargo.toml"
assert_contains ".github/workflows/ci.yml" "libwebkit2gtk-4.1-dev"

assert_contains ".github/workflows/continuous-tests.yml" "schedule:"
assert_contains ".github/workflows/continuous-tests.yml" "scripts/ct-host-check.sh"
assert_contains ".github/workflows/continuous-tests.yml" "loopwire-host-audio-diagnostics"

assert_contains ".github/workflows/deploy-docs.yml" "pnpm verify:docs"
assert_contains ".github/workflows/deploy-docs.yml" "pnpm build:docs"
assert_contains ".github/workflows/deploy-docs.yml" "BUNNY_STORAGE_ZONE"
assert_contains ".github/workflows/deploy-docs.yml" "BUNNY_ACCESS_KEY"
assert_contains ".github/workflows/deploy-docs.yml" "BUNNY_STORAGE_ENDPOINT"
assert_contains ".github/workflows/deploy-docs.yml" "Bunny.net secrets are not configured; skipping deployment."
assert_contains ".github/workflows/deploy-docs.yml" "bash scripts/deploy-docs-bunny.sh"

assert_contains ".github/workflows/release.yml" "tags:"
assert_contains ".github/workflows/release.yml" "v*"
assert_contains ".github/workflows/release.yml" "build-linux:"
assert_contains ".github/workflows/release.yml" "publish-release:"
assert_contains ".github/workflows/release.yml" "needs: build-linux"
assert_contains ".github/workflows/release.yml" "release_arch: x86_64"
assert_contains ".github/workflows/release.yml" "release_arch: aarch64"
assert_contains ".github/workflows/release.yml" "runner: ubuntu-22.04-arm"
assert_contains ".github/workflows/release.yml" "actions/upload-artifact@v7.0.1"
assert_contains ".github/workflows/release.yml" "actions/download-artifact@v8.0.1"
assert_contains ".github/workflows/release.yml" "merge-multiple: true"
assert_contains ".github/workflows/release.yml" "Prepare architecture release upload"
assert_contains ".github/workflows/release.yml" 'release-upload-${{ matrix.release_arch }}'
assert_contains ".github/workflows/release.yml" "loopwire-linux-aarch64.tar.gz"
assert_contains ".github/workflows/release.yml" "LOOPWIRE_RELEASE_PRIVATE_KEY"
assert_contains ".github/workflows/release.yml" "Require versioned release notes"
assert_contains ".github/workflows/release.yml" "scripts/verify-release-readiness.sh"
assert_contains ".github/workflows/release.yml" "--skip-public-key"
assert_contains ".github/workflows/release.yml" "scripts/stage-release-artifacts.sh"
assert_contains ".github/workflows/release.yml" "Sign combined release manifest"
assert_contains ".github/workflows/release.yml" "Smoke install generated tarball"
assert_contains ".github/workflows/release.yml" "Smoke install published release"
assert_contains ".github/workflows/release.yml" "gh release create"

assert_contains ".github/workflows/vm-matrix.yml" "scripts/vm-matrix.sh validate"
assert_contains ".github/workflows/vm-matrix.yml" "scripts/vm-matrix.sh verify-cloud-init"
assert_contains ".github/workflows/vm-matrix.yml" "scripts/vm-matrix.sh plan"
assert_contains ".github/workflows/vm-matrix.yml" "scripts/verify-support-matrix.mjs"
assert_contains ".github/workflows/vm-matrix.yml" "node scripts/verify-support-matrix.mjs"
assert_contains ".github/workflows/vm-matrix.yml" "apps/docs/docs/guide/support-matrix.md"

echo "GitHub workflow contract verification passed."
