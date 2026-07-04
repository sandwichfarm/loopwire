#!/usr/bin/env bash
set -euo pipefail

dist_dir="${LOOPWIRE_DOCS_DIST:-apps/docs/docs/.vitepress/dist}"
storage_zone="${BUNNY_STORAGE_ZONE:-}"
access_key="${BUNNY_ACCESS_KEY:-}"
storage_endpoint="${BUNNY_STORAGE_ENDPOINT:-https://storage.bunnycdn.com}"
remote_prefix="${BUNNY_REMOTE_PREFIX:-}"
deployment_manifest="${LOOPWIRE_DOCS_DEPLOYMENT_MANIFEST:-}"
dry_run="false"

usage() {
  cat <<'USAGE'
Deploy the built VitePress docs directory to Bunny.net Edge Storage.

Usage:
  deploy-docs-bunny.sh [--dist DIR] [--storage-zone ZONE] [--access-key KEY]
                       [--storage-endpoint URL] [--remote-prefix PATH]
                       [--deployment-manifest FILE] [--dry-run]

Environment:
  LOOPWIRE_DOCS_DIST      Built docs directory, default apps/docs/docs/.vitepress/dist
  BUNNY_STORAGE_ZONE      Bunny Edge Storage zone name
  BUNNY_ACCESS_KEY        Storage zone password from Bunny's FTP & API Access panel
  BUNNY_STORAGE_ENDPOINT  Regional storage endpoint, default https://storage.bunnycdn.com
  BUNNY_REMOTE_PREFIX     Optional remote path prefix inside the storage zone
  LOOPWIRE_DOCS_DEPLOYMENT_MANIFEST
                           Optional JSON manifest describing uploaded files without secrets

Dry-run mode validates the local build output, prints upload targets, and can write the deployment manifest without
contacting Bunny.net.
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

write_deployment_manifest() {
  manifest_path="$1"
  uploads_tsv="$2"

  command -v node >/dev/null 2>&1 || fail "node is required to write deployment manifests"
  mkdir -p "$(dirname "$manifest_path")"

  node - "$manifest_path" "$uploads_tsv" "$dist_dir" "$storage_zone" "$storage_endpoint" "$remote_prefix" \
    "$dry_run" "$file_count" <<'NODE'
const { readFileSync, writeFileSync } = require("node:fs");

const [
  manifestPath,
  uploadsTsv,
  distDir,
  storageZone,
  storageEndpoint,
  remotePrefix,
  dryRun,
  fileCount
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

[ "$file_count" -gt 0 ] || fail "docs dist directory has no files: $dist_dir"

if [ -n "$deployment_manifest" ]; then
  write_deployment_manifest "$deployment_manifest" "$uploads_tsv"
fi

if [ "$dry_run" = "true" ]; then
  echo "Dry run complete; ${file_count} docs file(s) would be uploaded to ${storage_endpoint}/${storage_zone}."
else
  echo "Uploaded ${file_count} docs file(s) to ${storage_endpoint}/${storage_zone}."
fi
