#!/usr/bin/env bash
set -euo pipefail

repo=""
storage_zone="${BUNNY_STORAGE_ZONE:-}"
access_key="${BUNNY_ACCESS_KEY:-}"
storage_endpoint="${BUNNY_STORAGE_ENDPOINT:-}"
pull_zone_hostname="${BUNNY_PULL_ZONE_HOSTNAME:-}"
remote_prefix="${BUNNY_REMOTE_PREFIX:-}"
release_private_key_file=""
release_public_key_file="${LOOPWIRE_RELEASE_PUBLIC_KEY_FILE:-}"
dry_run="false"
check_mode="false"
print_required="false"

usage() {
  cat <<'USAGE'
Set GitHub Actions secrets needed for Loopwire Bunny.net docs deployment.

Usage:
  setup-github-secrets.sh --repo owner/name [--storage-zone ZONE --access-key KEY]
                          [--storage-endpoint URL] [--pull-zone-hostname HOST]
                          [--remote-prefix PATH]
                          [--release-private-key-file FILE]
                          [--release-public-key-file FILE]
  setup-github-secrets.sh --repo owner/name --check
  setup-github-secrets.sh --print-required
  setup-github-secrets.sh --repo owner/name --dry-run [secret options]

Environment fallback:
  BUNNY_STORAGE_ZONE
  BUNNY_ACCESS_KEY
  BUNNY_STORAGE_ENDPOINT
  BUNNY_PULL_ZONE_HOSTNAME
  BUNNY_REMOTE_PREFIX
  LOOPWIRE_RELEASE_PUBLIC_KEY_FILE

Required secrets:
  BUNNY_STORAGE_ZONE
  BUNNY_ACCESS_KEY
  LOOPWIRE_RELEASE_PRIVATE_KEY

Optional secrets:
  BUNNY_STORAGE_ENDPOINT
  BUNNY_PULL_ZONE_HOSTNAME
  BUNNY_REMOTE_PREFIX

No secret values are printed in --check or --dry-run output.
USAGE
}

print_required() {
  cat <<'SECRETS'
Required GitHub secrets:
  BUNNY_STORAGE_ZONE
  BUNNY_ACCESS_KEY
  LOOPWIRE_RELEASE_PRIVATE_KEY

Optional GitHub secrets:
  BUNNY_STORAGE_ENDPOINT
  BUNNY_PULL_ZONE_HOSTNAME
  BUNNY_REMOTE_PREFIX
SECRETS
}

require_gh() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "GitHub CLI is required: gh" >&2
    exit 1
  fi
}

fail() {
  echo "setup-github-secrets: $*" >&2
  exit 1
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

validate_storage_zone() {
  reject_unsafe_value "$storage_zone" "storage zone"

  case "$storage_zone" in
    */*)
      fail "storage zone must not contain slashes"
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

normalize_pull_zone_hostname() {
  hostname="$1"
  reject_unsafe_value "$hostname" "pull-zone hostname"

  case "$hostname" in
    http://* | https://* | */*)
      fail "pull-zone hostname must be a hostname, not a URL or path"
      ;;
  esac

  printf '%s\n' "$hostname"
}

resolve_repo() {
  if [ -z "$repo" ]; then
    repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
  fi

  if [ -z "$repo" ]; then
    usage >&2
    exit 2
  fi
}

check_secret_presence() {
  local docs_live_smoke_ready="false"

  if ! secret_list_output="$(gh secret list --repo "$repo" 2>&1)"; then
    echo "unable to read GitHub secret names for ${repo}: ${secret_list_output}" >&2
    exit 1
  fi

  secret_names="$(printf '%s\n' "$secret_list_output" | awk '{ print $1 }')"
  missing=0

  for secret in BUNNY_STORAGE_ZONE BUNNY_ACCESS_KEY LOOPWIRE_RELEASE_PRIVATE_KEY; do
    if printf '%s\n' "$secret_names" | grep -Fxq "$secret"; then
      echo "ok: GitHub secret present: $secret"
    else
      echo "missing: GitHub secret: $secret" >&2
      missing=1
    fi
  done

  if printf '%s\n' "$secret_names" | grep -Fxq BUNNY_PULL_ZONE_HOSTNAME; then
    echo "ok: optional GitHub secret present: BUNNY_PULL_ZONE_HOSTNAME"
    docs_live_smoke_ready="true"
  else
    echo "optional: GitHub secret not set: BUNNY_PULL_ZONE_HOSTNAME"
    echo "hint: set BUNNY_PULL_ZONE_HOSTNAME to enable post-upload live docs smoke in deploy-docs.yml"
  fi

  if printf '%s\n' "$secret_names" | grep -Fxq BUNNY_STORAGE_ENDPOINT; then
    echo "ok: optional GitHub secret present: BUNNY_STORAGE_ENDPOINT"
  else
    echo "optional: GitHub secret not set: BUNNY_STORAGE_ENDPOINT"
  fi

  if printf '%s\n' "$secret_names" | grep -Fxq BUNNY_REMOTE_PREFIX; then
    echo "ok: optional GitHub secret present: BUNNY_REMOTE_PREFIX"
  else
    echo "optional: GitHub secret not set: BUNNY_REMOTE_PREFIX"
  fi

  if [ "$missing" -ne 0 ]; then
    cat >&2 <<EOF
next: set Bunny.net deployment secrets without printing values:
  bash scripts/setup-github-secrets.sh --repo ${repo} --storage-zone <zone> --access-key <key>
next: set release signing secret from a local private key:
  bash scripts/setup-github-secrets.sh --repo ${repo} \\
    --release-private-key-file <private-key> \\
    --release-public-key-file packaging/release-signing-public.pem
EOF
    exit 1
  fi

  if [ "$docs_live_smoke_ready" = "true" ]; then
    echo "ok: docs deploy workflow can run post-upload live smoke"
  else
    echo "notice: docs deploy workflow can upload to Bunny.net but will skip post-upload live smoke"
  fi
}

set_github_secret() {
  secret_name="$1"

  gh secret set "$secret_name" --repo "$repo"
}

validate_requested_secret_set() {
  if [ -n "$storage_zone" ] || [ -n "$access_key" ] || [ -n "$storage_endpoint" ] || \
    [ -n "$pull_zone_hostname" ] || [ -n "$remote_prefix" ]; then
    if [ -z "$storage_zone" ] || [ -z "$access_key" ]; then
      echo "Bunny.net deployment secrets require both storage zone and access key." >&2
      exit 2
    fi
  fi

  if [ -n "$release_private_key_file" ] && [ ! -f "$release_private_key_file" ]; then
    echo "Release private key file does not exist: $release_private_key_file" >&2
    exit 1
  fi

  if [ -n "$release_public_key_file" ] && [ ! -f "$release_public_key_file" ]; then
    echo "Release public key file does not exist: $release_public_key_file" >&2
    exit 1
  fi

  if [ -n "$release_private_key_file" ]; then
    validate_release_private_key
  fi

  if [ -n "$storage_zone" ]; then
    validate_storage_zone
  fi

  if [ -n "$storage_endpoint" ]; then
    storage_endpoint="$(normalize_endpoint "$storage_endpoint")"
  fi

  if [ -n "$pull_zone_hostname" ]; then
    pull_zone_hostname="$(normalize_pull_zone_hostname "$pull_zone_hostname")"
  fi

  if [ -n "$remote_prefix" ]; then
    remote_prefix="$(normalize_prefix "$remote_prefix")"
  fi
}

validate_release_private_key() {
  local tmp_public

  command -v openssl >/dev/null 2>&1 || fail "openssl is required to validate release signing keys"

  if ! openssl pkey -in "$release_private_key_file" -noout >/dev/null 2>&1; then
    fail "release private key does not parse: $release_private_key_file"
  fi

  if [ -z "$release_public_key_file" ]; then
    return
  fi

  if ! openssl pkey -pubin -in "$release_public_key_file" -noout >/dev/null 2>&1; then
    fail "release public key does not parse: $release_public_key_file"
  fi

  tmp_public="$(mktemp)"
  openssl pkey -in "$release_private_key_file" -pubout -out "$tmp_public" >/dev/null 2>&1

  if ! cmp -s "$tmp_public" "$release_public_key_file"; then
    rm -f "$tmp_public"
    fail "release private key does not match public key: $release_public_key_file"
  fi

  rm -f "$tmp_public"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      repo="${2:?missing value for --repo}"
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
    --pull-zone-hostname)
      pull_zone_hostname="${2:?missing value for --pull-zone-hostname}"
      shift 2
      ;;
    --remote-prefix)
      remote_prefix="${2:?missing value for --remote-prefix}"
      shift 2
      ;;
    --release-private-key-file)
      release_private_key_file="${2:?missing value for --release-private-key-file}"
      shift 2
      ;;
    --release-public-key-file)
      release_public_key_file="${2:?missing value for --release-public-key-file}"
      shift 2
      ;;
    --dry-run)
      dry_run="true"
      shift
      ;;
    --check)
      check_mode="true"
      shift
      ;;
    --print-required)
      print_required="true"
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ "$print_required" = "true" ]; then
  print_required
  exit 0
fi

if [ "$check_mode" = "true" ] && [ "$dry_run" = "true" ]; then
  echo "--check and --dry-run are mutually exclusive." >&2
  exit 2
fi

if [ "$check_mode" = "true" ] || [ "$dry_run" != "true" ] || [ -z "$repo" ]; then
  require_gh
fi

resolve_repo

if [ "$check_mode" = "true" ]; then
  check_secret_presence
  exit 0
fi

validate_requested_secret_set

set_any="false"

if [ -n "$storage_zone" ] || [ -n "$access_key" ] || [ -n "$storage_endpoint" ] || \
  [ -n "$pull_zone_hostname" ] || [ -n "$remote_prefix" ]; then
  if [ "$dry_run" = "true" ]; then
    echo "would set GitHub secret for ${repo}: BUNNY_STORAGE_ZONE"
    echo "would set GitHub secret for ${repo}: BUNNY_ACCESS_KEY"
  else
    printf '%s' "$storage_zone" | set_github_secret BUNNY_STORAGE_ZONE
    printf '%s' "$access_key" | set_github_secret BUNNY_ACCESS_KEY
  fi
  set_any="true"

  if [ -n "$pull_zone_hostname" ]; then
    if [ "$dry_run" = "true" ]; then
      echo "would set optional GitHub secret for ${repo}: BUNNY_PULL_ZONE_HOSTNAME"
    else
      printf '%s' "$pull_zone_hostname" | set_github_secret BUNNY_PULL_ZONE_HOSTNAME
    fi
  fi

  if [ -n "$storage_endpoint" ]; then
    if [ "$dry_run" = "true" ]; then
      echo "would set optional GitHub secret for ${repo}: BUNNY_STORAGE_ENDPOINT"
    else
      printf '%s' "$storage_endpoint" | set_github_secret BUNNY_STORAGE_ENDPOINT
    fi
  fi

  if [ -n "$remote_prefix" ]; then
    if [ "$dry_run" = "true" ]; then
      echo "would set optional GitHub secret for ${repo}: BUNNY_REMOTE_PREFIX"
    else
      printf '%s' "$remote_prefix" | set_github_secret BUNNY_REMOTE_PREFIX
    fi
  fi
fi

if [ -n "$release_private_key_file" ]; then
  if [ "$dry_run" = "true" ]; then
    echo "would set GitHub secret for ${repo}: LOOPWIRE_RELEASE_PRIVATE_KEY"
  else
    set_github_secret LOOPWIRE_RELEASE_PRIVATE_KEY <"$release_private_key_file"
  fi
  set_any="true"
fi

if [ "$set_any" != "true" ]; then
  usage >&2
  exit 2
fi

if [ "$dry_run" = "true" ]; then
  echo "Dry run complete; no GitHub secrets were changed for ${repo}."
else
  echo "GitHub deployment/release secrets set for ${repo}."
fi
