#!/usr/bin/env bash
set -euo pipefail

archive=""
output_dir=""
label="archive"

usage() {
  cat <<'USAGE'
Safely extract a tar.gz archive after validating member paths.

Usage:
  extract-safe-tar.sh --archive FILE --output-dir DIR [--label NAME]

The validator rejects empty archives, absolute paths, parent traversal, duplicate separators, dot path components, and
symlink or hardlink members before extraction. Use it for release artifacts that are downloaded before project-specific
manifest verification can run.
USAGE
}

fail() {
  echo "extract-safe-tar: $*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --archive)
      archive="${2:?missing value for --archive}"
      shift 2
      ;;
    --output-dir)
      output_dir="${2:?missing value for --output-dir}"
      shift 2
      ;;
    --label)
      label="${2:?missing value for --label}"
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

[ -n "$archive" ] || fail "missing --archive FILE"
[ -n "$output_dir" ] || fail "missing --output-dir DIR"
[ -f "$archive" ] || fail "missing ${label}: $archive"
command -v tar >/dev/null 2>&1 || fail "tar is required"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

listing="$tmp_dir/listing.txt"
verbose_listing="$tmp_dir/verbose-listing.txt"

tar -tzf "$archive" >"$listing" || fail "failed to list ${label}: $archive"
[ -s "$listing" ] || fail "${label} is empty: $archive"

while IFS= read -r entry; do
  [ -n "$entry" ] || fail "${label} contains an empty path"

  case "$entry" in
    /*)
      fail "${label} contains an absolute path: $entry"
      ;;
    *"//"*)
      fail "${label} contains duplicate separators: $entry"
      ;;
  esac

  IFS="/" read -r -a parts <<<"$entry"
  for part in "${parts[@]}"; do
    case "$part" in
      "" | "." | "..")
        fail "${label} contains an unsafe path component: $entry"
        ;;
    esac
  done
done <"$listing"

tar -tvzf "$archive" >"$verbose_listing" || fail "failed to inspect ${label}: $archive"
while IFS= read -r entry; do
  case "$entry" in
    l* | h*)
      fail "${label} contains a link member: $entry"
      ;;
  esac
done <"$verbose_listing"

mkdir -p "$output_dir"
tar -C "$output_dir" -xzf "$archive"
