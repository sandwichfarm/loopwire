#!/usr/bin/env bash
set -euo pipefail

dist_dir="${LOOPWIRE_DOCS_DIST:-apps/docs/docs/.vitepress/dist}"
storage_zone="${BUNNY_STORAGE_ZONE:-}"
access_key="${BUNNY_ACCESS_KEY:-}"
storage_endpoint="${BUNNY_STORAGE_ENDPOINT:-https://storage.bunnycdn.com}"
remote_prefix="${BUNNY_REMOTE_PREFIX:-}"
dry_run="false"

usage() {
  cat <<'USAGE'
Deploy the built VitePress docs directory to Bunny.net Edge Storage.

Usage:
  deploy-docs-bunny.sh [--dist DIR] [--storage-zone ZONE] [--access-key KEY]
                       [--storage-endpoint URL] [--remote-prefix PATH] [--dry-run]

Environment:
  LOOPWIRE_DOCS_DIST      Built docs directory, default apps/docs/docs/.vitepress/dist
  BUNNY_STORAGE_ZONE      Bunny Edge Storage zone name
  BUNNY_ACCESS_KEY        Storage zone password from Bunny's FTP & API Access panel
  BUNNY_STORAGE_ENDPOINT  Regional storage endpoint, default https://storage.bunnycdn.com
  BUNNY_REMOTE_PREFIX     Optional remote path prefix inside the storage zone

Dry-run mode validates the local build output and prints upload targets without contacting Bunny.net.
USAGE
}

fail() {
  echo "deploy-docs-bunny: $*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dist)
      dist_dir="${2:?missing value for --dist}"
      shift 2
      ;;
    --storage-zone)
      storage_zone="${2:?missing value for --storage-zone}"
      shift 2
      ;;
    --access-key)
      access_key="${2:?missing value for --access-key}"
      shift 2
      ;;
    --storage-endpoint)
      storage_endpoint="${2:?missing value for --storage-endpoint}"
      shift 2
      ;;
    --remote-prefix)
      remote_prefix="${2:?missing value for --remote-prefix}"
      shift 2
      ;;
    --dry-run)
      dry_run="true"
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

reject_unsafe_value() {
  value="$1"
  label="$2"

  case "$value" in
    *$'\n'* | *$'\r'*)
      fail "$label must not contain newlines"
      ;;
  esac
}

normalize_endpoint() {
  endpoint="$1"
  reject_unsafe_value "$endpoint" "storage endpoint"

  case "$endpoint" in
    http://* | https://*)
      ;;
    *)
      endpoint="https://${endpoint}"
      ;;
  esac

  printf '%s\n' "${endpoint%/}"
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

require_dist_file() {
  relative_path="$1"
  label="$2"
  path="${dist_dir}/${relative_path}"

  [ -s "$path" ] || fail "docs dist is missing ${label}: ${relative_path}"
}

remote_path_for_file() {
  relative_path="$1"

  if [ -n "$remote_prefix" ]; then
    printf '%s/%s\n' "$remote_prefix" "$relative_path"
  else
    printf '%s\n' "$relative_path"
  fi
}

upload_file() {
  file="$1"
  relative_path="$2"
  remote_path="$(remote_path_for_file "$relative_path")"
  checksum="$(sha256sum "$file" | awk '{ print toupper($1) }')"
  url="${storage_endpoint}/${storage_zone}/${remote_path}"

  if [ "$dry_run" = "true" ]; then
    printf 'would upload %s -> %s\n' "$relative_path" "$url"
    return
  fi

  curl -fsS -X PUT \
    -H "AccessKey: ${access_key}" \
    -H "Checksum: ${checksum}" \
    --upload-file "$file" \
    "$url" >/dev/null
}

[ -n "$storage_zone" ] || fail "BUNNY_STORAGE_ZONE or --storage-zone is required"
reject_unsafe_value "$storage_zone" "storage zone"
case "$storage_zone" in
  */*)
    fail "storage zone must not contain slashes"
    ;;
esac

if [ "$dry_run" != "true" ]; then
  [ -n "$access_key" ] || fail "BUNNY_ACCESS_KEY or --access-key is required outside dry-run mode"
  command -v curl >/dev/null 2>&1 || fail "curl is required"
fi

command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required"
[ -d "$dist_dir" ] || fail "docs dist directory does not exist: $dist_dir"

storage_endpoint="$(normalize_endpoint "$storage_endpoint")"
remote_prefix="$(normalize_prefix "$remote_prefix")"

require_dist_file "index.html" "homepage"
require_dist_file "install.sh" "public installer"
bash -n "${dist_dir}/install.sh" || fail "public installer has shell syntax errors: install.sh"

file_count=0
while IFS= read -r -d '' file; do
  file_count=$((file_count + 1))
  relative_path="${file#"$dist_dir"/}"
  reject_unsafe_value "$relative_path" "file path"
  upload_file "$file" "$relative_path"
done < <(find "$dist_dir" -type f -print0 | sort -z)

[ "$file_count" -gt 0 ] || fail "docs dist directory has no files: $dist_dir"

if [ "$dry_run" = "true" ]; then
  echo "Dry run complete; ${file_count} docs file(s) would be uploaded to ${storage_endpoint}/${storage_zone}."
else
  echo "Uploaded ${file_count} docs file(s) to ${storage_endpoint}/${storage_zone}."
fi
