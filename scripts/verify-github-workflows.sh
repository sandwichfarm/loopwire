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

assert_not_contains() {
  local file="$1"
  local needle="$2"

  if grep -Fq -- "$needle" "$root/$file"; then
    fail "unexpected workflow content in $file: $needle"
  fi
}

assert_occurrences() {
  local file="$1"
  local needle="$2"
  local expected="$3"
  local count

  count="$(grep -F -- "$needle" "$root/$file" | wc -l | tr -d ' ')"
  if [ "$count" != "$expected" ]; then
    fail "expected $expected occurrence(s) in $file but found $count: $needle"
  fi
}

assert_final_proof_step_has_github_token() {
  local file=".github/workflows/final-release-proof.yml"

  if ! awk '
    $0 == "      - name: Verify final release proof" { in_step = 1; next }
    in_step && $0 ~ /^      - name: / { in_step = 0 }
    in_step && $0 == "          GH_TOKEN: ${{ github.token }}" { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$root/$file"; then
    fail "final release proof step is missing GH_TOKEN: $file"
  fi
}

assert_final_proof_step_uses_published_release_inputs() {
  local file=".github/workflows/final-release-proof.yml"

  if awk '
    $0 == "      - name: Verify final release proof" { in_step = 1; next }
    in_step && $0 ~ /^      - name: / { in_step = 0 }
    in_step && /--release-dir/ { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$root/$file"; then
    fail "final release proof step must not pass --release-dir: $file"
  fi
}

assert_final_proof_vm_archive_step_verifies_bundles() {
  local file=".github/workflows/final-release-proof.yml"

  if ! awk '
    $0 == "      - name: Download VM evidence archive" { in_step = 1; next }
    in_step && $0 ~ /^      - name: / { in_step = 0 }
    in_step && /node scripts[/]verify-vm-evidence-archive-manifest[.]mjs/ { verifier = 1 }
    in_step && /--require-all-targets/ { all_targets = 1 }
    in_step && /--evidence-root "\$vm_evidence_root"/ { evidence_root = 1 }
    in_step && /--verify-bundles/ { verify_bundles = 1 }
    in_step && /--require-published-release/ { published_release = 1 }
    in_step && /LOOPWIRE_FINAL_VM_EVIDENCE_ASSET=%s/ { exports_asset = 1 }
    in_step && /LOOPWIRE_FINAL_VM_EVIDENCE_ROOT=%s/ { exports_root = 1 }
    END { exit(verifier && all_targets && evidence_root && verify_bundles && published_release && exports_asset && exports_root ? 0 : 1) }
  ' "$root/$file"; then
    fail "final release proof VM archive step must verify all published VM bundles and export VM evidence asset/root: $file"
  fi
}

if ! command -v ruby >/dev/null 2>&1; then
  fail "ruby is required to parse workflow YAML"
fi

workflows=(
  ".github/workflows/ci.yml"
  ".github/workflows/continuous-tests.yml"
  ".github/workflows/deploy-docs.yml"
  ".github/workflows/final-release-proof.yml"
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
assert_contains ".github/workflows/ci.yml" "fetch-depth: 0"
assert_contains ".github/workflows/ci.yml" "libwebkit2gtk-4.1-dev"
assert_contains "package.json" '"verify:tauri": "bash scripts/verify-tauri.sh"'
assert_contains "package.json" "pnpm verify:tauri"

assert_contains ".github/workflows/continuous-tests.yml" "schedule:"
assert_contains ".github/workflows/continuous-tests.yml" "scripts/ct-host-check.sh"
assert_contains ".github/workflows/continuous-tests.yml" "loopwire-host-audio-diagnostics"

assert_contains ".github/workflows/deploy-docs.yml" "pnpm verify:docs"
assert_contains ".github/workflows/deploy-docs.yml" "pnpm build:web"
assert_contains ".github/workflows/deploy-docs.yml" "pnpm verify:site"
assert_contains ".github/workflows/deploy-docs.yml" "BUNNY_STORAGE_ZONE"
assert_contains ".github/workflows/deploy-docs.yml" "BUNNY_ACCESS_KEY"
assert_contains ".github/workflows/deploy-docs.yml" "BUNNY_STORAGE_ENDPOINT"
assert_contains ".github/workflows/deploy-docs.yml" "BUNNY_REMOTE_PREFIX"
assert_contains ".github/workflows/deploy-docs.yml" "Bunny.net secrets are not configured; skipping deployment."
assert_contains ".github/workflows/deploy-docs.yml" 'vars.BUNNY_STORAGE_ZONE || secrets.BUNNY_STORAGE_ZONE'
assert_contains ".github/workflows/deploy-docs.yml" 'vars.BUNNY_STORAGE_ENDPOINT || secrets.BUNNY_STORAGE_ENDPOINT'
assert_contains ".github/workflows/deploy-docs.yml" 'vars.BUNNY_PULL_ZONE_HOSTNAME || secrets.BUNNY_PULL_ZONE_HOSTNAME'
assert_contains ".github/workflows/deploy-docs.yml" 'vars.BUNNY_REMOTE_PREFIX || secrets.BUNNY_REMOTE_PREFIX'
assert_contains ".github/workflows/deploy-docs.yml" 'pnpm setup:github -- --repo ${GITHUB_REPOSITORY} --scope deploy'
assert_contains ".github/workflows/deploy-docs.yml" "actions/download-artifact@v8.0.1"
assert_contains ".github/workflows/deploy-docs.yml" "bash scripts/deploy-docs-bunny.sh"
assert_contains ".github/workflows/deploy-docs.yml" "bash scripts/verify-docs-live.sh"
assert_contains ".github/workflows/deploy-docs.yml" '--remote-prefix "$BUNNY_REMOTE_PREFIX"'
assert_contains ".github/workflows/deploy-docs.yml" 'docs_url="${docs_url}/${prefix}"'
assert_contains ".github/workflows/deploy-docs.yml" "LOOPWIRE_DOCS_DEPLOYMENT_MANIFEST"
assert_contains ".github/workflows/deploy-docs.yml" "Verify docs deployment manifest"
assert_contains ".github/workflows/deploy-docs.yml" "pnpm verify:docs-deployment"
assert_contains ".github/workflows/deploy-docs.yml" "--expected-dry-run false"
assert_contains ".github/workflows/deploy-docs.yml" "Upload docs deployment manifest"
assert_contains ".github/workflows/deploy-docs.yml" "loopwire-docs-deployment"
assert_contains ".github/workflows/deploy-docs.yml" "dist/docs-deployment/deployment-manifest.json"
assert_contains ".github/workflows/deploy-docs.yml" "path: dist/site"
assert_contains ".github/workflows/deploy-docs.yml" "--dist dist/site"
assert_contains "package.json" '"verify:docs-deployment": "node scripts/verify-docs-deployment-manifest.mjs"'
assert_contains "package.json" '"verify:docs-live": "bash scripts/verify-docs-live.sh"'

assert_contains ".github/workflows/final-release-proof.yml" "workflow_dispatch:"
assert_contains ".github/workflows/final-release-proof.yml" 'run-name: Final Release Proof ${{ inputs.tag }} @ ${{ inputs.git_head }}'
assert_contains ".github/workflows/final-release-proof.yml" "actions: read"
assert_contains ".github/workflows/final-release-proof.yml" "Verify final release proof"
assert_contains ".github/workflows/final-release-proof.yml" "Set up Nix"
assert_contains ".github/workflows/final-release-proof.yml" "DeterminateSystems/determinate-nix-action@v3.21.2"
assert_contains ".github/workflows/final-release-proof.yml" "docs_base_url"
assert_contains ".github/workflows/final-release-proof.yml" "docs_hostname"
assert_contains ".github/workflows/final-release-proof.yml" "docs_deployment_run_id"
assert_contains ".github/workflows/final-release-proof.yml" 'LOOPWIRE_DOCS_HOSTNAME_SECRET: ${{ vars.BUNNY_PULL_ZONE_HOSTNAME || secrets.BUNNY_PULL_ZONE_HOSTNAME }}'
assert_contains ".github/workflows/final-release-proof.yml" 'LOOPWIRE_DOCS_REMOTE_PREFIX_SECRET: ${{ vars.BUNNY_REMOTE_PREFIX || secrets.BUNNY_REMOTE_PREFIX }}'
assert_contains ".github/workflows/final-release-proof.yml" "LOOPWIRE_FINAL_DOCS_HOSTNAME"
assert_contains ".github/workflows/final-release-proof.yml" "LOOPWIRE_FINAL_DOCS_REMOTE_PREFIX"
assert_contains ".github/workflows/final-release-proof.yml" "docs_base_url, docs_hostname, or BUNNY_PULL_ZONE_HOSTNAME"
assert_contains ".github/workflows/final-release-proof.yml" "Download docs deployment manifest"
assert_contains ".github/workflows/final-release-proof.yml" "scripts/verify-workflow-run.sh"
assert_contains ".github/workflows/final-release-proof.yml" '--label "Deploy Docs workflow run"'
assert_contains ".github/workflows/final-release-proof.yml" "gh run download"
assert_contains ".github/workflows/final-release-proof.yml" "loopwire-docs-deployment"
assert_contains ".github/workflows/final-release-proof.yml" "deployment-manifest.json"
assert_contains ".github/workflows/final-release-proof.yml" "--docs-deployment-manifest"
assert_contains ".github/workflows/final-release-proof.yml" "release_evidence_asset"
assert_contains ".github/workflows/final-release-proof.yml" "vm_evidence_asset"
assert_contains ".github/workflows/final-release-proof.yml" "gh release download"
assert_contains ".github/workflows/final-release-proof.yml" "Download signed checksum manifest"
assert_contains ".github/workflows/final-release-proof.yml" "--pattern SHA256SUMS"
assert_contains ".github/workflows/final-release-proof.yml" "--pattern SHA256SUMS.sig"
assert_contains ".github/workflows/final-release-proof.yml" "scripts/extract-safe-tar.sh"
assert_contains ".github/workflows/final-release-proof.yml" "scripts/validate-release-asset-name.sh"
assert_contains ".github/workflows/final-release-proof.yml" "scripts/verify-release-asset-checksum.sh"
assert_contains ".github/workflows/final-release-proof.yml" '--label "release evidence archive"'
assert_contains ".github/workflows/final-release-proof.yml" '--label "VM evidence archive"'
assert_contains ".github/workflows/final-release-proof.yml" "--kind release-evidence"
assert_contains ".github/workflows/final-release-proof.yml" "--kind vm-evidence"
assert_contains ".github/workflows/final-release-proof.yml" "LOOPWIRE_FINAL_RELEASE_EVIDENCE_ASSET"
assert_contains ".github/workflows/final-release-proof.yml" "LOOPWIRE_FINAL_VM_EVIDENCE_ASSET"
assert_contains ".github/workflows/final-release-proof.yml" '--release-evidence-asset "$LOOPWIRE_FINAL_RELEASE_EVIDENCE_ASSET"'
assert_contains ".github/workflows/final-release-proof.yml" '--vm-evidence-asset "$LOOPWIRE_FINAL_VM_EVIDENCE_ASSET"'
assert_contains ".github/workflows/final-release-proof.yml" 'loopwire-release-evidence-${LOOPWIRE_RELEASE_TAG}.tar.gz'
assert_contains ".github/workflows/final-release-proof.yml" 'loopwire-vm-evidence-${LOOPWIRE_RELEASE_TAG}.tar.gz'
assert_contains ".github/workflows/final-release-proof.yml" "Release evidence archive must contain"
assert_contains ".github/workflows/final-release-proof.yml" "scripts/verify-final-release-proof.sh"
assert_final_proof_step_has_github_token
assert_final_proof_step_uses_published_release_inputs
assert_final_proof_vm_archive_step_verifies_bundles
assert_contains "scripts/verify-final-release-proof.sh" "scripts/verify-release-tag-ref.sh"
assert_contains "scripts/verify-final-release-proof.sh" "release tag ref"
assert_contains "scripts/fetch-docs-deployment-proof.sh" "scripts/verify-workflow-run.sh"
assert_contains ".github/workflows/final-release-proof.yml" "--docs-base-url"
assert_contains ".github/workflows/final-release-proof.yml" "--docs-hostname"
assert_contains ".github/workflows/final-release-proof.yml" "--docs-remote-prefix"
assert_contains ".github/workflows/final-release-proof.yml" "--vm-evidence-root"
assert_contains ".github/workflows/final-release-proof.yml" "--verify-bundles"
assert_contains ".github/workflows/final-release-proof.yml" "--evidence-root"
assert_contains ".github/workflows/final-release-proof.yml" "packaging/release-signing-public.pem"
assert_contains ".github/workflows/final-release-proof.yml" "Release tag"
assert_contains ".github/workflows/final-release-proof.yml" "40-character SHA"
assert_contains "scripts/audit-final-release-state.sh" "displayTitle"
assert_contains "scripts/audit-final-release-state.sh" 'Final Release Proof ${expectedTag} @ ${expectedHead}'

assert_contains ".github/workflows/release.yml" "tags:"
assert_contains ".github/workflows/release.yml" "v*"
assert_contains ".github/workflows/release.yml" 'run-name: Release ${{ inputs.tag || github.ref_name }}'
assert_contains ".github/workflows/release.yml" 'group: release-${{ inputs.tag || github.ref_name }}'
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
assert_not_contains ".github/workflows/release.yml" "--skip-tag"
assert_occurrences ".github/workflows/release.yml" "Release tag must be v-prefixed semver without path separators" "2"
assert_occurrences ".github/workflows/release.yml" 'tag_pattern=' "2"
assert_occurrences ".github/workflows/release.yml" 'git check-ref-format --allow-onelevel "$release_tag"' "2"
assert_occurrences ".github/workflows/release.yml" 'tag_ref="refs/tags/${release_tag}"' "2"
assert_occurrences ".github/workflows/release.yml" 'git rev-parse -q --verify "${tag_ref}^{commit}"' "2"
assert_occurrences ".github/workflows/release.yml" 'git checkout --detach "$release_commit"' "2"
assert_occurrences ".github/workflows/release.yml" 'LOOPWIRE_RELEASE_COMMIT=%s' "2"
assert_contains ".github/workflows/release.yml" "-u LOOPWIRE_RELEASE_TAG"
assert_contains ".github/workflows/release.yml" "-u LOOPWIRE_RELEASE_VERSION"
assert_contains ".github/workflows/release.yml" "-u LOOPWIRE_RELEASE_COMMIT"
assert_contains ".github/workflows/release.yml" "-u LOOPWIRE_RELEASE_NOTES_FILE"
assert_contains ".github/workflows/release.yml" "scripts/stage-release-artifacts.sh"
assert_contains ".github/workflows/release.yml" "stage_args+=(--native-packages)"
assert_contains ".github/workflows/release.yml" "stage_args+=(--appimage-only)"
assert_contains ".github/workflows/release.yml" "docker version"
assert_contains "scripts/stage-release-artifacts.sh" "scripts/build-native-packages.sh"
assert_contains "scripts/stage-release-artifacts.sh" "--appimage-only"
assert_contains ".github/workflows/release.yml" 'tauri:build --config "$release_config"'
assert_contains ".github/workflows/release.yml" "scripts/release-asset-manifest.mjs write"
assert_contains ".github/workflows/release.yml" "scripts/release-asset-manifest.mjs verify"
assert_contains ".github/workflows/release.yml" "dist/release/release-assets.json"
assert_contains ".github/workflows/release.yml" "--require-evidence"
assert_contains ".github/workflows/release.yml" "gh release delete-asset"
assert_contains ".github/workflows/release.yml" "--json assets --jq '.assets[].name'"
assert_contains ".github/workflows/release.yml" "Sign combined release manifest"
assert_contains ".github/workflows/release.yml" "Smoke install generated tarball"
assert_contains ".github/workflows/release.yml" "Smoke install published release"
assert_contains ".github/workflows/release.yml" "Collect published release evidence"
assert_contains ".github/workflows/release.yml" "Upload failed release evidence diagnostics"
assert_contains ".github/workflows/release.yml" 'if: failure()'
assert_contains ".github/workflows/release.yml" 'loopwire-release-evidence-failure-${{ env.LOOPWIRE_RELEASE_TAG }}-${{ github.run_attempt }}'
assert_contains ".github/workflows/release.yml" "pnpm collect:evidence"
assert_contains ".github/workflows/release.yml" "pnpm verify:release-evidence"
assert_contains ".github/workflows/release.yml" '--release-tag "$LOOPWIRE_RELEASE_TAG"'
assert_contains ".github/workflows/release.yml" '--repo "$GITHUB_REPOSITORY"'
assert_contains ".github/workflows/release.yml" '--git-head "$LOOPWIRE_RELEASE_COMMIT"'
assert_contains ".github/workflows/release.yml" "--require-published-release"
assert_contains "scripts/verify-final-release-proof.sh" "scripts/verify-nix-release-package.sh"
assert_contains "scripts/verify-final-release-proof.sh" "Nix release package"
assert_contains ".github/workflows/release.yml" "--require-dsp-provider-plan"
assert_contains ".github/workflows/release.yml" "--require-jack-provider-plan"
assert_contains "scripts/verify-final-release-proof.sh" "--require-jack-provider-plan"
assert_contains ".github/workflows/release.yml" 'loopwire-release-evidence-${LOOPWIRE_RELEASE_TAG}.tar.gz'
assert_contains ".github/workflows/release.yml" 'evidence_archive="dist/release/loopwire-release-evidence-${LOOPWIRE_RELEASE_TAG}.tar.gz"'
assert_contains ".github/workflows/release.yml" 'tar -C "dist/release-evidence" -czf'
assert_contains ".github/workflows/release.yml" "dist/release/SHA256SUMS"
assert_contains ".github/workflows/release.yml" "dist/release/SHA256SUMS.sig"
assert_contains ".github/workflows/release.yml" "scripts/verify-published-release.sh"
assert_contains ".github/workflows/release.yml" "--require-release-evidence"
assert_contains ".github/workflows/release.yml" "Upload release evidence"
assert_contains ".github/workflows/release.yml" "loopwire-release-evidence-"
assert_contains ".github/workflows/release.yml" "gh release create"

assert_contains ".github/workflows/vm-matrix.yml" "scripts/vm-matrix.sh validate"
assert_contains ".github/workflows/vm-matrix.yml" "scripts/vm-matrix.sh verify-cloud-init"
assert_contains ".github/workflows/vm-matrix.yml" "scripts/vm-matrix.sh verify-handoffs"
assert_contains ".github/workflows/vm-matrix.yml" "scripts/vm-matrix.sh plan"
assert_contains ".github/workflows/vm-matrix.yml" "scripts/verify-support-matrix.mjs"
assert_contains ".github/workflows/vm-matrix.yml" "node scripts/verify-support-matrix.mjs"
assert_contains ".github/workflows/vm-matrix.yml" "apps/docs/docs/guide/support-matrix.md"

echo "GitHub workflow contract verification passed."
