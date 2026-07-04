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
check_file "package.json" "package manifest"
check_file ".github/workflows/deploy-docs.yml" "docs deployment workflow"
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

if [ -s "package.json" ] && node -e '
const fs = require("node:fs");
const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
process.exit(pkg.scripts?.["verify:docs-deployment"] === "node scripts/verify-docs-deployment-manifest.mjs" ? 0 : 1);
'; then
  echo "ok: package script verify:docs-deployment is wired"
else
  echo "invalid: package script verify:docs-deployment is missing or changed" >&2
  failed=1
fi

if [ -s ".github/workflows/deploy-docs.yml" ]; then
  if grep -F -- "pnpm verify:docs-deployment" .github/workflows/deploy-docs.yml >/dev/null &&
    grep -F -- "dist/docs-deployment/deployment-manifest.json" .github/workflows/deploy-docs.yml >/dev/null; then
    echo "ok: docs deployment workflow verifies manifest before artifact upload"
  else
    echo "invalid: docs deployment workflow does not verify the deployment manifest" >&2
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
