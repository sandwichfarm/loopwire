#!/usr/bin/env bash
set -euo pipefail

repo=""
storage_zone="${BUNNY_STORAGE_ZONE:-}"
access_key="${BUNNY_ACCESS_KEY:-}"
storage_endpoint="${BUNNY_STORAGE_ENDPOINT:-}"
pull_zone_hostname="${BUNNY_PULL_ZONE_HOSTNAME:-}"
release_private_key_file=""
dry_run="false"
check_mode="false"
print_required="false"

usage() {
  cat <<'USAGE'
Set GitHub Actions secrets needed for Loopwire Bunny.net docs deployment.

Usage:
  setup-github-secrets.sh --repo owner/name [--storage-zone ZONE --access-key KEY]
                          [--storage-endpoint URL] [--pull-zone-hostname HOST]
                          [--release-private-key-file FILE]
  setup-github-secrets.sh --repo owner/name --check
  setup-github-secrets.sh --print-required
  setup-github-secrets.sh --repo owner/name --dry-run [secret options]

Environment fallback:
  BUNNY_STORAGE_ZONE
  BUNNY_ACCESS_KEY
  BUNNY_STORAGE_ENDPOINT
  BUNNY_PULL_ZONE_HOSTNAME

Required secrets:
  BUNNY_STORAGE_ZONE
  BUNNY_ACCESS_KEY
  LOOPWIRE_RELEASE_PRIVATE_KEY

Optional secrets:
  BUNNY_STORAGE_ENDPOINT
  BUNNY_PULL_ZONE_HOSTNAME

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
SECRETS
}

require_gh() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "GitHub CLI is required: gh" >&2
    exit 1
  fi
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
  secret_names="$(gh secret list --repo "$repo" 2>/dev/null | awk '{ print $1 }')"
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
  else
    echo "optional: GitHub secret not set: BUNNY_PULL_ZONE_HOSTNAME"
  fi

  if printf '%s\n' "$secret_names" | grep -Fxq BUNNY_STORAGE_ENDPOINT; then
    echo "ok: optional GitHub secret present: BUNNY_STORAGE_ENDPOINT"
  else
    echo "optional: GitHub secret not set: BUNNY_STORAGE_ENDPOINT"
  fi

  [ "$missing" -eq 0 ] || exit 1
}

validate_requested_secret_set() {
  if [ -n "$storage_zone" ] || [ -n "$access_key" ] || [ -n "$storage_endpoint" ] || [ -n "$pull_zone_hostname" ]; then
    if [ -z "$storage_zone" ] || [ -z "$access_key" ]; then
      echo "Bunny.net deployment secrets require both storage zone and access key." >&2
      exit 2
    fi
  fi

  if [ -n "$release_private_key_file" ] && [ ! -f "$release_private_key_file" ]; then
    echo "Release private key file does not exist: $release_private_key_file" >&2
    exit 1
  fi
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
    --release-private-key-file)
      release_private_key_file="${2:?missing value for --release-private-key-file}"
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

if [ -n "$storage_zone" ] || [ -n "$access_key" ] || [ -n "$storage_endpoint" ] || [ -n "$pull_zone_hostname" ]; then
  if [ "$dry_run" = "true" ]; then
    echo "would set GitHub secret for ${repo}: BUNNY_STORAGE_ZONE"
    echo "would set GitHub secret for ${repo}: BUNNY_ACCESS_KEY"
  else
    printf '%s' "$storage_zone" | gh secret set BUNNY_STORAGE_ZONE --repo "$repo" --body-file -
    printf '%s' "$access_key" | gh secret set BUNNY_ACCESS_KEY --repo "$repo" --body-file -
  fi
  set_any="true"

  if [ -n "$pull_zone_hostname" ]; then
    if [ "$dry_run" = "true" ]; then
      echo "would set optional GitHub secret for ${repo}: BUNNY_PULL_ZONE_HOSTNAME"
    else
      printf '%s' "$pull_zone_hostname" | gh secret set BUNNY_PULL_ZONE_HOSTNAME --repo "$repo" --body-file -
    fi
  fi

  if [ -n "$storage_endpoint" ]; then
    if [ "$dry_run" = "true" ]; then
      echo "would set optional GitHub secret for ${repo}: BUNNY_STORAGE_ENDPOINT"
    else
      printf '%s' "$storage_endpoint" | gh secret set BUNNY_STORAGE_ENDPOINT --repo "$repo" --body-file -
    fi
  fi
fi

if [ -n "$release_private_key_file" ]; then
  if [ "$dry_run" = "true" ]; then
    echo "would set GitHub secret for ${repo}: LOOPWIRE_RELEASE_PRIVATE_KEY"
  else
    gh secret set LOOPWIRE_RELEASE_PRIVATE_KEY --repo "$repo" --body-file "$release_private_key_file"
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
