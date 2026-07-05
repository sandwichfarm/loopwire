#!/usr/bin/env bash
set -euo pipefail

repo="${LOOPWIRE_GITHUB_REPO:-sandwichfarm/loopwire}"
tag=""
release_dir="dist/release"
private_key_file="${LOOPWIRE_RELEASE_PRIVATE_KEY_FILE:-}"
public_key_file="${LOOPWIRE_RELEASE_PUBLIC_KEY_FILE:-${LOOPWIRE_RELEASE_PUBLIC_KEY:-}}"
evidence_root="${LOOPWIRE_VM_EVIDENCE_ROOT:-.vm/evidence}"
env_file=""
asset_name=""
dry_run="false"
all_targets="false"
targets=()
private_key_file_explicit="false"
public_key_file_explicit="false"

usage() {
  cat <<'USAGE'
Prepare the VM evidence archive as a signed Loopwire release asset.

Usage:
  prepare-vm-evidence-release-asset.sh --tag vX.Y.Z --private-key FILE [--public-key FILE]
                                       [--repo OWNER/REPO] [--release-dir DIR]
                                       [--evidence-root DIR] [--asset-name NAME]
                                       [--env-file FILE] [--target TARGET ... | --all] [--dry-run]

The script packages verified VM evidence with scripts/package-vm-evidence.sh, writes it into the release directory,
regenerates SHA256SUMS for every release attachment, signs SHA256SUMS, verifies the VM evidence archive with
scripts/verify-release-asset-checksum.sh, and prints the exact gh release upload --clobber command for publishing the
archive plus refreshed manifest files.
Custom --release-dir values may be absolute or relative, but they must not contain parent traversal, URL syntax, glob
metacharacters, symlinks, or file paths.

--env-file accepts the same local release secret file used by scripts/setup-github-secrets.sh, but this helper only
consumes LOOPWIRE_RELEASE_PRIVATE_KEY_FILE and LOOPWIRE_RELEASE_PUBLIC_KEY_FILE. Bunny storage credentials are ignored.

It does not upload to GitHub. Run the printed gh command only after reviewing the regenerated release directory.
USAGE
}

fail() {
  echo "prepare-vm-evidence-release-asset: $*" >&2
  exit 1
}

quote_command() {
  local quoted=()
  local arg

  for arg in "$@"; do
    quoted+=("$(printf '%q' "$arg")")
  done

  printf '%s\n' "${quoted[*]}"
}

validate_repo() {
  local value="$1"
  local pattern='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'

  [[ "$value" =~ $pattern ]] || fail "repository must use OWNER/REPO without URLs, spaces, or extra path segments: $value"
}

validate_tag() {
  local value="$1"
  local pattern='^v[0-9]+[.][0-9]+[.][0-9]+([.-][0-9A-Za-z][0-9A-Za-z.-]*)?$'

  [[ "$value" =~ $pattern ]] || fail "tag must be v-prefixed semver without path separators: $value"
}

reject_unsafe_value() {
  local value="$1"
  local label="$2"

  case "$value" in
    *$'\n'* | *$'\r'*)
      fail "$label must be a single safe value"
      ;;
  esac
}

validate_release_dir_path() {
  local value="$1"
  local normalized

  reject_unsafe_value "$value" "release directory"
  normalized="${value#./}"

  [ -n "$normalized" ] || fail "release directory must not be empty"
  case "$normalized" in
    "/" | "~" | "~/"* | *://* | *'*'* | *'?'* | *'['* | *']'*)
      fail "release directory must not be root, home-expanded, URL-like, or contain glob metacharacters"
      ;;
  esac

  case "/$normalized/" in
    */../* | */./*)
      fail "release directory must not contain . or .. path segments"
      ;;
  esac

  [ ! -L "$value" ] || fail "release directory must not be a symlink"
  if [ -e "$value" ] && [ ! -d "$value" ]; then
    fail "release directory must be a directory when it exists"
  fi
}

refresh_manifest() {
  local dir="$1"
  local files=()

  mapfile -t files < <(
    cd "$dir"
    find . -maxdepth 1 -type f ! -name SHA256SUMS ! -name SHA256SUMS.sig -printf '%f\n' | sort
  )

  [ "${#files[@]}" -gt 0 ] || fail "release directory has no files to checksum: $dir"

  (
    cd "$dir"
    sha256sum "${files[@]}" >SHA256SUMS
    sha256sum --check SHA256SUMS >/dev/null
  )
}

strip_wrapping_quotes() {
  local value="$1"

  case "$value" in
    \"*\")
      value="${value#\"}"
      value="${value%\"}"
      ;;
    \'*\')
      value="${value#\'}"
      value="${value%\'}"
      ;;
  esac

  printf '%s\n' "$value"
}

assign_env_file_value() {
  local key="$1"
  local value="$2"

  reject_unsafe_value "$value" "env-file value for ${key}"

  case "$key" in
    LOOPWIRE_RELEASE_PRIVATE_KEY_FILE)
      [ "$private_key_file_explicit" = "true" ] || private_key_file="$value"
      ;;
    LOOPWIRE_RELEASE_PUBLIC_KEY_FILE)
      [ "$public_key_file_explicit" = "true" ] || public_key_file="$value"
      ;;
    BUNNY_STORAGE_ZONE | BUNNY_ACCESS_KEY | BUNNY_STORAGE_ENDPOINT | BUNNY_PULL_ZONE_HOSTNAME | BUNNY_REMOTE_PREFIX)
      ;;
    *)
      fail "unsupported key in --env-file: $key"
      ;;
  esac
}

load_env_file() {
  local line
  local line_no=0
  local key
  local value

  [ -f "$env_file" ] || fail "env file does not exist: $env_file"

  while IFS= read -r line || [ -n "$line" ]; do
    line_no=$((line_no + 1))
    line="${line%$'\r'}"

    case "$line" in
      "" | \#*)
        continue
        ;;
      export\ *)
        line="${line#export }"
        ;;
    esac

    case "$line" in
      *=*)
        key="${line%%=*}"
        value="${line#*=}"
        ;;
      *)
        fail "invalid --env-file line ${line_no}: expected KEY=VALUE"
        ;;
    esac

    case "$key" in
      *[!A-Z0-9_]* | "")
        fail "invalid --env-file key on line ${line_no}: $key"
        ;;
    esac

    value="$(strip_wrapping_quotes "$value")"
    assign_env_file_value "$key" "$value"
  done <"$env_file"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --)
      shift
      ;;
    --repo)
      repo="${2:?missing value for --repo}"
      shift 2
      ;;
    --tag)
      tag="${2:?missing value for --tag}"
      shift 2
      ;;
    --release-dir)
      release_dir="${2:?missing value for --release-dir}"
      shift 2
      ;;
    --private-key)
      private_key_file="${2:?missing value for --private-key}"
      private_key_file_explicit="true"
      shift 2
      ;;
    --public-key)
      public_key_file="${2:?missing value for --public-key}"
      public_key_file_explicit="true"
      shift 2
      ;;
    --env-file)
      env_file="${2:?missing value for --env-file}"
      shift 2
      ;;
    --evidence-root)
      evidence_root="${2:?missing value for --evidence-root}"
      shift 2
      ;;
    --asset-name)
      asset_name="${2:?missing value for --asset-name}"
      shift 2
      ;;
    --target)
      targets+=("${2:?missing value for --target}")
      shift 2
      ;;
    --all)
      all_targets="true"
      shift
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

[ -z "$env_file" ] || load_env_file

[ -n "$repo" ] || fail "missing --repo OWNER/REPO"
[ -n "$tag" ] || fail "missing --tag vX.Y.Z"
[ -n "$release_dir" ] || fail "missing --release-dir DIR"
[ -n "$private_key_file" ] || fail "missing --private-key FILE"
validate_repo "$repo"
validate_tag "$tag"
validate_release_dir_path "$release_dir"
reject_unsafe_value "$private_key_file" "private key path"
reject_unsafe_value "$public_key_file" "public key path"
reject_unsafe_value "$evidence_root" "evidence root"
reject_unsafe_value "$env_file" "env file"

if [ "$all_targets" = "true" ] && [ "${#targets[@]}" -gt 0 ]; then
  fail "use either --all or --target, not both"
fi

if [ -z "$asset_name" ]; then
  asset_name="loopwire-vm-evidence-${tag}.tar.gz"
fi
bash scripts/validate-release-asset-name.sh --kind vm-evidence --tag "$tag" --asset "$asset_name" >/dev/null

target_flags=()
if [ "$all_targets" = "true" ] || [ "${#targets[@]}" -eq 0 ]; then
  target_flags+=(--all)
else
  for target in "${targets[@]}"; do
    reject_unsafe_value "$target" "target"
    target_flags+=(--target "$target")
  done
fi

archive_path="${release_dir%/}/${asset_name}"

if [ "$dry_run" = "true" ]; then
  refresh_command=(
    bash scripts/prepare-vm-evidence-release-asset.sh
    --tag "$tag"
    --repo "$repo"
    --release-dir "$release_dir"
    --private-key "$private_key_file"
    --evidence-root "$evidence_root"
    --asset-name "$asset_name"
    "${target_flags[@]}"
  )
  if [ -n "$public_key_file" ]; then
    refresh_command+=(--public-key "$public_key_file")
  fi

  printf 'dry-run: package VM evidence archive: %s\n' "$(
    quote_command \
      bash scripts/package-vm-evidence.sh \
      --tag "$tag" \
      --evidence-root "$evidence_root" \
      --output "$archive_path" \
      "${target_flags[@]}" \
      --require-published-release
  )"
  printf 'dry-run: refresh signed release manifest: %s\n' "$(
    quote_command "${refresh_command[@]}"
  )"
  printf 'dry-run: upload VM evidence release assets: %s\n' "$(
    quote_command \
      gh release upload "$tag" \
      "$archive_path" \
      "${release_dir%/}/SHA256SUMS" \
      "${release_dir%/}/SHA256SUMS.sig" \
      --repo "$repo" \
      --clobber
  )"
  exit 0
fi

[ -d "$release_dir" ] || fail "missing release directory: $release_dir"
[ -f "$private_key_file" ] || fail "missing private key: $private_key_file"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required"
command -v openssl >/dev/null 2>&1 || fail "OpenSSL is required"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

bash scripts/package-vm-evidence.sh \
  --tag "$tag" \
  --evidence-root "$evidence_root" \
  --output "$archive_path" \
  "${target_flags[@]}" \
  --require-published-release >/dev/null

refresh_manifest "$release_dir"
bash scripts/sign-release-artifacts.sh --release-dir "$release_dir" --private-key "$private_key_file" >/dev/null

if [ -z "$public_key_file" ]; then
  public_key_file="$tmp_dir/release-public.pem"
  openssl pkey -in "$private_key_file" -pubout -out "$public_key_file" >/dev/null
fi

bash scripts/verify-release-asset-checksum.sh \
  --release-dir "$release_dir" \
  --asset "$asset_name" \
  --public-key "$public_key_file" \
  --label "VM evidence archive" >/dev/null

printf 'Prepared signed VM evidence release asset: %s\n' "$archive_path"
printf 'Upload with: %s\n' "$(
  quote_command \
    gh release upload "$tag" \
    "$archive_path" \
    "${release_dir%/}/SHA256SUMS" \
    "${release_dir%/}/SHA256SUMS.sig" \
    --repo "$repo" \
    --clobber
)"
