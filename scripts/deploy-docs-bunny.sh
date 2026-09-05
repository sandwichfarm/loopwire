#!/usr/bin/env bash
set -euo pipefail

dist_dir="${LOOPWIRE_SITE_DIST:-${LOOPWIRE_DOCS_DIST:-dist/site}}"
storage_zone="${BUNNY_STORAGE_ZONE:-}"
access_key="${BUNNY_ACCESS_KEY:-}"
api_key="${BUNNY_API_KEY:-}"
pull_zone_id="${BUNNY_PULL_ZONE_ID:-}"
storage_endpoint="${BUNNY_STORAGE_ENDPOINT:-https://storage.bunnycdn.com}"
remote_prefix="${BUNNY_REMOTE_PREFIX:-}"
deployment_manifest="${LOOPWIRE_DOCS_DEPLOYMENT_MANIFEST:-}"
dry_run="false"
purge_cache="false"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

usage() {
  cat <<'USAGE'
Deploy the built Loopwire static site directory to Bunny.net Edge Storage.

Usage:
  deploy-docs-bunny.sh [--dist DIR] [--storage-zone ZONE] [--access-key KEY]
                       [--storage-endpoint URL] [--remote-prefix PATH]
                       [--deployment-manifest FILE] [--purge-cache] [--dry-run]

Environment:
  LOOPWIRE_SITE_DIST      Built combined site directory, default dist/site
  LOOPWIRE_DOCS_DIST      Legacy fallback for the built site directory
  BUNNY_STORAGE_ZONE      Bunny Edge Storage zone name
  BUNNY_ACCESS_KEY        Storage zone password from Bunny's FTP & API Access panel
  BUNNY_API_KEY           Account API key for --purge-cache, distinct from the storage password
  BUNNY_PULL_ZONE_ID      Numeric CDN Pull Zone ID for --purge-cache, not the Storage Zone ID
  BUNNY_STORAGE_ENDPOINT  Regional storage endpoint, default https://storage.bunnycdn.com
  BUNNY_REMOTE_PREFIX     Optional remote path prefix inside the storage zone
  LOOPWIRE_DOCS_DEPLOYMENT_MANIFEST
                           Optional JSON manifest describing uploaded files without secrets

With --purge-cache, purge the entire CDN Pull Zone after every upload and manifest write succeeds. Existing browser
caches are unaffected. Dry-run validates the local build output and Pull Zone ID, prints planned uploads/purge, and
can write the deployment manifest without contacting Bunny.net or requiring credentials.
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
    --deployment-manifest)
      deployment_manifest="${2:?missing value for --deployment-manifest}"
      shift 2
      ;;
    --dry-run)
      dry_run="true"
      shift
      ;;
    --purge-cache)
      purge_cache="true"
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
    *$'\n'* | *$'\r'* | *$'\t'*)
      fail "$label must not contain control separators"
      ;;
  esac
}

validate_purge_configuration() {
  local LC_ALL=C
  local significant_id="${pull_zone_id#"${pull_zone_id%%[!0]*}"}"

  # Equal-length decimal strings compare exactly without shell integer overflow.
  # shellcheck disable=SC2071
  if [[ ! "$pull_zone_id" =~ ^[0-9]+$ || -z "$significant_id" || ${#significant_id} -gt 19 ||
    ( ${#significant_id} -eq 19 && "$significant_id" > 9223372036854775807 ) ]]; then
    fail "BUNNY_PULL_ZONE_ID must be a positive integer no greater than 9223372036854775807"
  fi
  if [ "$dry_run" != "true" ]; then
    [ -n "$api_key" ] || fail "BUNNY_API_KEY is required for --purge-cache outside dry-run mode"
    if [[ "$api_key" =~ [[:cntrl:]] ]]; then
      fail "BUNNY_API_KEY must not contain control characters"
    fi
  fi
}

purge_pull_zone_cache() {
  local status
  if [ "$dry_run" = "true" ]; then
    printf 'would purge the entire Bunny CDN Pull Zone %s\n' "$pull_zone_id"
    return
  fi

  if ! status="$(printf 'AccessKey: %s\n' "$api_key" | curl --disable --silent --request POST \
    --header @- --connect-timeout 10 --max-time 30 --retry 2 --retry-delay 2 --retry-max-time 60 \
    --output /dev/null --write-out '%{http_code}' \
    "https://api.bunny.net/pullzone/${pull_zone_id}/purgeCache" 2>/dev/null)"; then
    fail "Bunny CDN cache purge request failed; uploaded files remain in storage. Check connectivity and retry deployment."
  fi
  case "$status" in
    2[0-9][0-9])
      printf 'Bunny CDN cache purge accepted for Pull Zone %s.\n' "$pull_zone_id"
      ;;
    [0-9][0-9][0-9])
      fail "Bunny CDN cache purge failed (HTTP ${status}); check the account API key and Pull Zone ID, then retry deployment."
      ;;
    *)
      fail "Bunny CDN cache purge returned an invalid HTTP status; retry deployment."
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

  [ -s "$path" ] || fail "site dist is missing ${label}: ${relative_path}"
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

write_deployment_manifest() {
  manifest_path="$1"
  uploads_tsv="$2"
  git_head="$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || true)"

  command -v node >/dev/null 2>&1 || fail "node is required to write deployment manifests"
  [ -n "$git_head" ] || fail "git is required to bind deployment manifests to a source commit"
  mkdir -p "$(dirname "$manifest_path")"

  node - "$manifest_path" "$uploads_tsv" "$dist_dir" "$storage_zone" "$storage_endpoint" "$remote_prefix" \
    "$dry_run" "$file_count" "$git_head" <<'NODE'
const { readFileSync, writeFileSync } = require("node:fs");

const [
  manifestPath,
  uploadsTsv,
  distDir,
  storageZone,
  storageEndpoint,
  remotePrefix,
  dryRun,
  fileCount,
  gitHead
] = process.argv.slice(2);

const uploads = readFileSync(uploadsTsv, "utf8")
  .split(/\r?\n/)
  .filter(Boolean)
  .map((line) => {
    const [relativePath, remotePath, checksumSha256] = line.split("\t");
    return { relativePath, remotePath, checksumSha256 };
  });

const manifest = {
  schema: "loopwire.docs-deployment.v1",
  generatedAt: new Date().toISOString(),
  dryRun: dryRun === "true",
  distDir,
  storage: {
    zone: storageZone,
    endpoint: storageEndpoint,
    remotePrefix
  },
  source: {
    gitHead
  },
  requiredFiles: ["index.html", "install.sh"],
  fileCount: Number(fileCount),
  uploads
};

writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
NODE
}

[ -n "$storage_zone" ] || fail "BUNNY_STORAGE_ZONE or --storage-zone is required"
reject_unsafe_value "$storage_zone" "storage zone"
reject_unsafe_value "$deployment_manifest" "deployment manifest path"
case "$storage_zone" in
  */*)
    fail "storage zone must not contain slashes"
    ;;
esac

if [ "$purge_cache" = "true" ]; then
  validate_purge_configuration
fi

if [ "$dry_run" != "true" ]; then
  [ -n "$access_key" ] || fail "BUNNY_ACCESS_KEY or --access-key is required outside dry-run mode"
  command -v curl >/dev/null 2>&1 || fail "curl is required"
fi

command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required"
[ -d "$dist_dir" ] || fail "site dist directory does not exist: $dist_dir"

storage_endpoint="$(normalize_endpoint "$storage_endpoint")"
remote_prefix="$(normalize_prefix "$remote_prefix")"

require_dist_file "index.html" "homepage"
require_dist_file "docs/index.html" "docs homepage"
require_dist_file "docs/guide/basic-usage.html" "basic usage page"
require_dist_file "install.sh" "public installer"
bash -n "${dist_dir}/install.sh" || fail "public installer has shell syntax errors: install.sh"

file_count=0
uploads_tsv=""
if [ -n "$deployment_manifest" ]; then
  uploads_tsv="$(mktemp)"
  cleanup_manifest_tsv() {
    rm -f "$uploads_tsv"
  }
  trap cleanup_manifest_tsv EXIT
fi
while IFS= read -r -d '' file; do
  file_count=$((file_count + 1))
  relative_path="${file#"$dist_dir"/}"
  reject_unsafe_value "$relative_path" "file path"
  upload_file "$file" "$relative_path"
  if [ -n "$uploads_tsv" ]; then
    remote_path="$(remote_path_for_file "$relative_path")"
    checksum="$(sha256sum "$file" | awk '{ print toupper($1) }')"
    printf '%s\t%s\t%s\n' "$relative_path" "$remote_path" "$checksum" >>"$uploads_tsv"
  fi
done < <(find "$dist_dir" -type f -print0 | sort -z)

[ "$file_count" -gt 0 ] || fail "site dist directory has no files: $dist_dir"

if [ -n "$deployment_manifest" ]; then
  write_deployment_manifest "$deployment_manifest" "$uploads_tsv"
fi

if [ "$purge_cache" = "true" ]; then
  purge_pull_zone_cache
fi

if [ "$dry_run" = "true" ]; then
  echo "Dry run complete; ${file_count} site file(s) would be uploaded to ${storage_endpoint}/${storage_zone}."
else
  echo "Uploaded ${file_count} site file(s) to ${storage_endpoint}/${storage_zone}."
fi
