#!/usr/bin/env bash
set -euo pipefail

base_url="${LOOPWIRE_DOCS_BASE_URL:-}"
pull_zone_hostname="${BUNNY_PULL_ZONE_HOSTNAME:-}"
remote_prefix="${BUNNY_REMOTE_PREFIX:-}"
expected_installer="${LOOPWIRE_PUBLIC_INSTALLER:-apps/docs/docs/public/install.sh}"
tmp_dir=""

usage() {
  cat <<'USAGE'
Verify a deployed Loopwire docs site without mutating remote state.

Usage:
  verify-docs-live.sh --base-url https://loopwire.app
  verify-docs-live.sh --hostname loopwire.b-cdn.net [--remote-prefix PATH]

Environment:
  LOOPWIRE_DOCS_BASE_URL    Full deployed docs URL
  BUNNY_PULL_ZONE_HOSTNAME  Bunny pull-zone hostname used when --base-url is omitted
  BUNNY_REMOTE_PREFIX       Optional remote path prefix inside the pull zone
  LOOPWIRE_PUBLIC_INSTALLER Local public installer to compare, default apps/docs/docs/public/install.sh

Checks:
  - deployed homepage is reachable and contains Loopwire,
  - deployed /install.sh is reachable,
  - deployed installer parses as shell,
  - deployed installer matches the local public installer byte-for-byte.
USAGE
}

fail() {
  echo "verify-docs-live: $*" >&2
  exit 1
}

cleanup() {
  if [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ]; then
    rm -rf "$tmp_dir"
  fi
}

reject_unsafe_value() {
  value="$1"
  label="$2"

  case "$value" in
    *$'\n'* | *$'\r'*)
      fail "$label must not contain newlines"
      ;;
  esac
}

normalize_prefix() {
  prefix="$1"
  reject_unsafe_value "$prefix" "remote prefix"
  prefix="${prefix#/}"
  prefix="${prefix%/}"
  case "$prefix" in
    "." | ".." | ./* | ../* | */../* | */.. | */./* | */.)
      fail "remote prefix must not contain . or .. path segments"
      ;;
  esac
  printf '%s\n' "$prefix"
}

normalize_base_url() {
  url="$1"
  reject_unsafe_value "$url" "base URL"
  case "$url" in
    http://* | https://*)
      ;;
    *)
      fail "base URL must start with http:// or https://"
      ;;
  esac
  printf '%s\n' "${url%/}"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --base-url)
      base_url="${2:?missing value for --base-url}"
      shift 2
      ;;
    --hostname)
      pull_zone_hostname="${2:?missing value for --hostname}"
      shift 2
      ;;
    --remote-prefix)
      remote_prefix="${2:?missing value for --remote-prefix}"
      shift 2
      ;;
    --expected-installer)
      expected_installer="${2:?missing value for --expected-installer}"
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

command -v curl >/dev/null 2>&1 || fail "curl is required"
[ -s "$expected_installer" ] || fail "expected installer does not exist: $expected_installer"

remote_prefix="$(normalize_prefix "$remote_prefix")"
if [ -n "$base_url" ]; then
  base_url="$(normalize_base_url "$base_url")"
else
  [ -n "$pull_zone_hostname" ] || fail "missing --base-url or --hostname"
  reject_unsafe_value "$pull_zone_hostname" "pull-zone hostname"
  case "$pull_zone_hostname" in
    http://* | https://* | */*)
      fail "pull-zone hostname must be a hostname, not a URL or path"
      ;;
  esac
  base_url="https://${pull_zone_hostname}"
  if [ -n "$remote_prefix" ]; then
    base_url="${base_url}/${remote_prefix}"
  fi
fi

tmp_dir="$(mktemp -d)"
trap cleanup EXIT

homepage="$tmp_dir/index.html"
installer="$tmp_dir/install.sh"

curl -fsSL --max-time 20 "${base_url}/" -o "$homepage"
curl -fsSL --max-time 20 "${base_url}/install.sh" -o "$installer"

grep -Fq "Loopwire" "$homepage" || fail "deployed homepage does not contain Loopwire"
bash -n "$installer" || fail "deployed install.sh has shell syntax errors"

if cmp -s "$expected_installer" "$installer"; then
  echo "Live docs smoke passed for ${base_url}."
else
  fail "deployed install.sh differs from ${expected_installer}"
fi
