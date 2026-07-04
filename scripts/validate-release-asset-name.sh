#!/usr/bin/env bash
set -euo pipefail

asset=""
tag=""
kind=""

usage() {
  cat <<'USAGE'
Validate a Loopwire release evidence asset name.

Usage:
  validate-release-asset-name.sh --kind release-evidence --tag vX.Y.Z --asset NAME
  validate-release-asset-name.sh --kind vm-evidence --tag vX.Y.Z --asset NAME

The validator accepts only basename-style tar.gz asset names bound to the release tag and expected evidence kind.
It rejects empty names, path separators, parent traversal, shell glob characters, URL-like names, and wrong prefixes.
USAGE
}

fail() {
  echo "validate-release-asset-name: $*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --asset)
      asset="${2:?missing value for --asset}"
      shift 2
      ;;
    --tag)
      tag="${2:?missing value for --tag}"
      shift 2
      ;;
    --kind)
      kind="${2:?missing value for --kind}"
      shift 2
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

[ -n "$asset" ] || fail "missing --asset NAME"
[ -n "$tag" ] || fail "missing --tag vX.Y.Z"
[ -n "$kind" ] || fail "missing --kind KIND"

tag_pattern='^v[0-9]+[.][0-9]+[.][0-9]+([.-][0-9A-Za-z][0-9A-Za-z.-]*)?$'
if [[ ! "$tag" =~ $tag_pattern ]]; then
  fail "release tag must be v-prefixed semver without path separators: $tag"
fi

case "$kind" in
  release-evidence)
    prefix="loopwire-release-evidence-${tag}"
    ;;
  vm-evidence)
    prefix="loopwire-vm-evidence-${tag}"
    ;;
  *)
    fail "kind must be release-evidence or vm-evidence: $kind"
    ;;
esac

case "$asset" in
  "" | /* | *"/"* | *"\\"* | *".."* | *":"* | *"*"* | *"?"* | *"["* | *"]"* | *"{"* | *"}"*)
    fail "asset name must be a basename without traversal, URL syntax, or glob metacharacters: $asset"
    ;;
  .* | -*)
    fail "asset name must not start with dot or dash: $asset"
    ;;
esac

if [[ ! "$asset" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*[.]tar[.]gz$ ]]; then
  fail "asset name must contain only letters, numbers, dot, underscore, dash, and end with .tar.gz: $asset"
fi

case "$asset" in
  "${prefix}.tar.gz" | "${prefix}-"*.tar.gz)
    ;;
  *)
    fail "asset name must match ${prefix}.tar.gz or ${prefix}-*.tar.gz: $asset"
    ;;
esac

printf '%s\n' "$asset"
