#!/usr/bin/env bash
set -euo pipefail

repo="${LOOPWIRE_GITHUB_REPO:-}"
tag="${LOOPWIRE_RELEASE_TAG:-}"
public_key="${LOOPWIRE_RELEASE_PUBLIC_KEY:-packaging/release-signing-public.pem}"
canonical_installer="${LOOPWIRE_INSTALLER_SCRIPT:-scripts/install.sh}"
public_installer="${LOOPWIRE_PUBLIC_INSTALLER:-apps/docs/docs/public/install.sh}"
require_gh="true"
require_tag="true"
require_public_key="true"
require_clean_git="true"
allow_candidate_notes="false"

usage() {
  cat <<'USAGE'
Verify Loopwire release readiness without publishing.

Usage:
  verify-release-readiness.sh --repo OWNER/REPO --tag vX.Y.Z [--public-key FILE]
  verify-release-readiness.sh --repo OWNER/REPO --tag vX.Y.Z --skip-gh --skip-tag
  verify-release-readiness.sh --tag vX.Y.Z --skip-gh --skip-tag --skip-public-key --skip-clean-git

Checks:
  - release tag is v-prefixed semver without path separators,
  - GitHub repository is OWNER/REPO when provided,
  - versioned release notes exist,
  - versioned release notes no longer carry release-candidate/not-published wording,
  - public docs installer stays synchronized with the canonical installer,
  - docs deployment manifest verifier is present, parseable, and wired into the deploy workflow,
  - final release proof workflow, asset-name validator, asset checksum verifier, Nix package verifier, safe archive
    extractor, and VM evidence packager are present, parseable, and wired,
  - release public key exists and parses,
  - git checkout is clean unless --skip-clean-git is passed,
  - local or remote tag exists and resolves to the current HEAD unless --skip-tag is passed,
  - GitHub repository is reachable unless --skip-gh is passed,
  - release/docs secrets are present unless --skip-gh is passed.

No secret values are read and no release is created.
USAGE
}

fail() {
  echo "verify-release-readiness: $*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --)
      shift
      ;;
    --repo)
      repo="${2:-}"
      shift 2
      ;;
    --tag)
      tag="${2:-}"
      shift 2
      ;;
    --public-key)
      public_key="${2:-}"
      shift 2
      ;;
    --skip-gh)
      require_gh="false"
      shift
      ;;
    --skip-tag)
      require_tag="false"
      shift
      ;;
    --skip-public-key)
      require_public_key="false"
      shift
      ;;
    --skip-clean-git)
      require_clean_git="false"
      shift
      ;;
    --allow-candidate-notes)
      allow_candidate_notes="true"
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

[ -n "$tag" ] || fail "missing --tag vX.Y.Z"
tag_pattern='^v[0-9]+[.][0-9]+[.][0-9]+([.-][0-9A-Za-z][0-9A-Za-z.-]*)?$'
if [[ ! "$tag" =~ $tag_pattern ]]; then
  fail "release tag must be v-prefixed semver without path separators: $tag"
fi

if [ "$require_gh" = "true" ] && [ -z "$repo" ]; then
  command -v gh >/dev/null 2>&1 || fail "gh is required when --repo is omitted"
  repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
fi

[ "$require_gh" = "false" ] || [ -n "$repo" ] || fail "missing --repo OWNER/REPO"
if [ -n "$repo" ]; then
  repo_pattern='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
  if [[ ! "$repo" =~ $repo_pattern ]]; then
    fail "repository must use OWNER/REPO without URLs, spaces, or extra path segments: $repo"
  fi
fi

failed=0
version="${tag#v}"
release_notes="apps/docs/docs/release-notes/${version}.md"

check_file() {
  path="$1"
  label="$2"

  if [ -s "$path" ]; then
    echo "ok: ${label}: ${path}"
  else
    echo "missing: ${label}: ${path}" >&2
    failed=1
  fi
}

check_release_notes_are_publishable() {
  path="$1"

  [ -s "$path" ] || return 0

  if [ "$allow_candidate_notes" = "true" ]; then
    echo "allowed: release notes still carry candidate wording"
    return 0
  fi

  candidate_pattern='release candidate|before the public GitHub Release|not proof that signed artifacts'
  candidate_pattern="${candidate_pattern}|blocked until|No public signed|must still fail"

  if grep -Eiq "$candidate_pattern" "$path"; then
    echo "invalid: release notes still look like a candidate: $path" >&2
    failed=1
    return 0
  fi

  echo "ok: release notes are publishable"
}

check_file "$release_notes" "versioned release notes"
if [ "$require_public_key" = "true" ]; then
  check_file "$public_key" "release public key"
else
  echo "skipped: release public key check"
fi

check_release_notes_are_publishable "$release_notes"

check_file "$canonical_installer" "canonical installer"
check_file "$public_installer" "public docs installer"
check_file "scripts/verify-docs-deployment-manifest.mjs" "docs deployment manifest verifier"
check_file "scripts/verify-final-release-proof.sh" "final release proof verifier"
check_file "scripts/validate-release-asset-name.sh" "release evidence asset-name validator"
check_file "scripts/verify-release-asset-checksum.sh" "release evidence asset checksum verifier"
check_file "scripts/verify-nix-release-package.sh" "Nix release package verifier"
check_file "scripts/extract-safe-tar.sh" "safe release archive extractor"
check_file "scripts/package-vm-evidence.sh" "VM evidence packager"
check_file "package.json" "package manifest"
check_file ".github/workflows/deploy-docs.yml" "docs deployment workflow"
check_file ".github/workflows/final-release-proof.yml" "final release proof workflow"
if [ -s "$canonical_installer" ] && [ -s "$public_installer" ]; then
  if cmp -s "$canonical_installer" "$public_installer"; then
    echo "ok: public docs installer matches canonical installer"
  else
    echo "invalid: public docs installer differs from canonical installer: $public_installer" >&2
    failed=1
  fi
  if ! bash -n "$public_installer"; then
    echo "invalid: public docs installer has shell syntax errors: $public_installer" >&2
    failed=1
  fi
fi

if [ -s "scripts/verify-docs-deployment-manifest.mjs" ]; then
  if node --check scripts/verify-docs-deployment-manifest.mjs >/dev/null; then
    echo "ok: docs deployment manifest verifier parses"
  else
    echo "invalid: docs deployment manifest verifier has syntax errors" >&2
    failed=1
  fi
fi

if [ -s "scripts/verify-final-release-proof.sh" ] && [ -s "scripts/validate-release-asset-name.sh" ] &&
  [ -s "scripts/verify-release-asset-checksum.sh" ] &&
  [ -s "scripts/verify-nix-release-package.sh" ] &&
  [ -s "scripts/extract-safe-tar.sh" ] &&
  [ -s "scripts/package-vm-evidence.sh" ]; then
  if bash -n scripts/verify-final-release-proof.sh scripts/validate-release-asset-name.sh \
    scripts/verify-release-asset-checksum.sh scripts/verify-nix-release-package.sh scripts/extract-safe-tar.sh \
    scripts/package-vm-evidence.sh; then
    echo "ok: final proof scripts parse"
  else
    echo "invalid: final proof scripts have shell syntax errors" >&2
    failed=1
  fi
fi

if [ -s "scripts/package-vm-evidence.sh" ]; then
  if bash scripts/package-vm-evidence.sh --help | grep -F -- "--require-published-release" >/dev/null; then
    echo "ok: VM evidence packager supports published-release strictness"
  else
    echo "invalid: VM evidence packager is missing published-release strictness support" >&2
    failed=1
  fi
fi

check_package_script() {
  script_name="$1"
  expected="$2"

  if [ -s "package.json" ] && node -e '
const fs = require("node:fs");
const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
const scriptName = process.argv[1];
const expected = process.argv[2];
process.exit(pkg.scripts?.[scriptName] === expected ? 0 : 1);
' "$script_name" "$expected"; then
    echo "ok: package script ${script_name} is wired"
  else
    echo "invalid: package script ${script_name} is missing or changed" >&2
    failed=1
  fi
}

check_package_script "verify:docs-deployment" "node scripts/verify-docs-deployment-manifest.mjs"
check_package_script "verify:final-release" "bash scripts/verify-final-release-proof.sh"
check_package_script "vm:package-evidence" "bash scripts/package-vm-evidence.sh"

if [ -s ".github/workflows/deploy-docs.yml" ]; then
  if grep -F -- "pnpm verify:docs-deployment" .github/workflows/deploy-docs.yml >/dev/null &&
    grep -F -- "dist/docs-deployment/deployment-manifest.json" .github/workflows/deploy-docs.yml >/dev/null; then
    echo "ok: docs deployment workflow verifies manifest before artifact upload"
  else
    echo "invalid: docs deployment workflow does not verify the deployment manifest" >&2
    failed=1
  fi
fi

if [ -s ".github/workflows/final-release-proof.yml" ]; then
  final_proof_workflow=".github/workflows/final-release-proof.yml"
  release_evidence_asset='loopwire-release-evidence-${LOOPWIRE_RELEASE_TAG}.tar.gz'
  vm_evidence_asset='loopwire-vm-evidence-${LOOPWIRE_RELEASE_TAG}.tar.gz'
  if grep -F -- "scripts/verify-final-release-proof.sh" "$final_proof_workflow" >/dev/null &&
    grep -F -- "DeterminateSystems/determinate-nix-action@v3.21.2" "$final_proof_workflow" >/dev/null &&
    grep -F -- "scripts/validate-release-asset-name.sh" "$final_proof_workflow" >/dev/null &&
    grep -F -- "scripts/verify-release-asset-checksum.sh" "$final_proof_workflow" >/dev/null &&
    grep -F -- "scripts/extract-safe-tar.sh" "$final_proof_workflow" >/dev/null &&
    grep -F -- "$release_evidence_asset" "$final_proof_workflow" >/dev/null &&
    grep -F -- "$vm_evidence_asset" "$final_proof_workflow" >/dev/null &&
    grep -F -- "--vm-evidence-root" "$final_proof_workflow" >/dev/null; then
    echo "ok: final release proof workflow verifies release and VM evidence archives"
  else
    echo "invalid: final release proof workflow is missing release or VM evidence verification" >&2
    failed=1
  fi
  if grep -F -- "scripts/verify-nix-release-package.sh" scripts/verify-final-release-proof.sh >/dev/null &&
    grep -F -- "DeterminateSystems/determinate-nix-action@v3.21.2" "$final_proof_workflow" >/dev/null; then
    echo "ok: final release proof workflow installs Nix for package proof"
  else
    echo "invalid: final release proof workflow is missing Nix setup or package proof" >&2
    failed=1
  fi
  if awk '
    $0 == "      - name: Verify final release proof" { in_step = 1; next }
    in_step && $0 ~ /^      - name: / { in_step = 0 }
    in_step && $0 == "          GH_TOKEN: ${{ github.token }}" { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$final_proof_workflow"; then
    echo "ok: final release proof workflow passes GitHub token to proof step"
  else
    echo "invalid: final release proof workflow is missing GitHub token for proof step" >&2
    failed=1
  fi
fi

if [ "$require_public_key" = "true" ] && [ -s "$public_key" ] &&
  ! openssl pkey -pubin -in "$public_key" -noout >/dev/null 2>&1; then
  echo "invalid: release public key does not parse: $public_key" >&2
  failed=1
fi

if [ "$require_clean_git" = "true" ]; then
  git_status="$(git status --short 2>/dev/null || true)"
  if [ -z "$git_status" ]; then
    echo "ok: git status is clean"
  else
    echo "invalid: git status is not clean" >&2
    failed=1
  fi
else
  echo "skipped: clean git status check"
fi

current_head() {
  git rev-parse HEAD 2>/dev/null || true
}

local_tag_commit() {
  git rev-parse -q --verify "refs/tags/${tag}^{commit}" 2>/dev/null || true
}

remote_tag_commit() {
  local direct_ref=""
  local peeled_ref=""

  peeled_ref="$(git ls-remote --tags origin "refs/tags/${tag}^{}" 2>/dev/null | awk '{ print $1 }' | head -1)"
  if [ -n "$peeled_ref" ]; then
    printf '%s\n' "$peeled_ref"
    return
  fi

  direct_ref="$(git ls-remote --tags origin "refs/tags/${tag}" 2>/dev/null | awk '{ print $1 }' | head -1)"
  [ -z "$direct_ref" ] || printf '%s\n' "$direct_ref"
}

check_tag_commit() {
  local source="$1"
  local commit="$2"
  local head_commit="$3"

  if [ "$commit" = "$head_commit" ]; then
    echo "ok: ${source} tag points at current HEAD: $tag"
  else
    echo "invalid: ${source} tag does not point at current HEAD: $tag" >&2
    failed=1
  fi
}

if [ "$require_tag" = "true" ]; then
  head_commit="$(current_head)"
  local_commit="$(local_tag_commit)"
  remote_commit=""

  if [ -z "$head_commit" ]; then
    echo "invalid: could not resolve current HEAD" >&2
    failed=1
  elif [ -n "$local_commit" ]; then
    check_tag_commit "local" "$local_commit" "$head_commit"
  else
    remote_commit="$(remote_tag_commit)"
    if [ -n "$remote_commit" ]; then
      check_tag_commit "remote" "$remote_commit" "$head_commit"
    else
      echo "missing: local or remote tag: $tag" >&2
      failed=1
    fi
  fi
else
  echo "skipped: tag existence check"
fi

if [ "$require_gh" = "true" ]; then
  command -v gh >/dev/null 2>&1 || fail "gh is required"
  gh repo view "$repo" >/dev/null

  if secret_list_output="$(gh secret list --repo "$repo" 2>&1)"; then
    secret_names="$(printf '%s\n' "$secret_list_output" | awk '{ print $1 }')"
    for secret in BUNNY_STORAGE_ZONE BUNNY_ACCESS_KEY LOOPWIRE_RELEASE_PRIVATE_KEY; do
      if printf '%s\n' "$secret_names" | grep -Fxq "$secret"; then
        echo "ok: GitHub secret present: $secret"
      else
        echo "missing: GitHub secret: $secret" >&2
        failed=1
      fi
    done
  else
    echo "error: unable to read GitHub secret names for ${repo}: ${secret_list_output}" >&2
    failed=1
  fi

  if gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
    echo "ok: GitHub release exists and will be updated: $repo@$tag"
  else
    echo "ok: GitHub release does not exist yet and will be created: $repo@$tag"
  fi
else
  echo "skipped: GitHub repository and secret checks"
fi

[ "$failed" -eq 0 ] || fail "release readiness checks failed"
echo "Release readiness checks passed for ${repo:-offline}@${tag}."
