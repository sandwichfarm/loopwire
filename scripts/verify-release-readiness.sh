#!/usr/bin/env bash
set -euo pipefail

repo="${LOOPWIRE_GITHUB_REPO:-}"
tag="${LOOPWIRE_RELEASE_TAG:-}"
public_key="${LOOPWIRE_RELEASE_PUBLIC_KEY:-packaging/release-signing-public.pem}"
require_gh="true"
require_tag="true"
require_public_key="true"
allow_candidate_notes="false"

usage() {
  cat <<'USAGE'
Verify Loopwire release readiness without publishing.

Usage:
  verify-release-readiness.sh --repo OWNER/REPO --tag vX.Y.Z [--public-key FILE]
  verify-release-readiness.sh --repo OWNER/REPO --tag vX.Y.Z --skip-gh --skip-tag
  verify-release-readiness.sh --tag vX.Y.Z --skip-gh --skip-tag --skip-public-key

Checks:
  - versioned release notes exist,
  - versioned release notes no longer carry release-candidate/not-published wording,
  - release public key exists and parses,
  - local or remote tag exists unless --skip-tag is passed,
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
case "$tag" in
  v*) ;;
  *) fail "release tag must start with v: $tag" ;;
esac

if [ "$require_gh" = "true" ] && [ -z "$repo" ]; then
  command -v gh >/dev/null 2>&1 || fail "gh is required when --repo is omitted"
  repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
fi

[ "$require_gh" = "false" ] || [ -n "$repo" ] || fail "missing --repo OWNER/REPO"

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

if [ "$require_public_key" = "true" ] && [ -s "$public_key" ] &&
  ! openssl pkey -pubin -in "$public_key" -noout >/dev/null 2>&1; then
  echo "invalid: release public key does not parse: $public_key" >&2
  failed=1
fi

if [ "$require_tag" = "true" ]; then
  if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
    echo "ok: local tag exists: $tag"
  elif git ls-remote --tags origin "refs/tags/${tag}" | grep -Fq "refs/tags/${tag}"; then
    echo "ok: remote tag exists: $tag"
  else
    echo "missing: local or remote tag: $tag" >&2
    failed=1
  fi
else
  echo "skipped: tag existence check"
fi

if [ "$require_gh" = "true" ]; then
  command -v gh >/dev/null 2>&1 || fail "gh is required"
  gh repo view "$repo" >/dev/null

  secret_names="$(gh secret list --repo "$repo" 2>/dev/null | awk '{ print $1 }')"
  for secret in BUNNY_STORAGE_ZONE BUNNY_ACCESS_KEY LOOPWIRE_RELEASE_PRIVATE_KEY; do
    if printf '%s\n' "$secret_names" | grep -Fxq "$secret"; then
      echo "ok: GitHub secret present: $secret"
    else
      echo "missing: GitHub secret: $secret" >&2
      failed=1
    fi
  done

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
