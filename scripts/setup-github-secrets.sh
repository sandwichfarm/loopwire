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
env_file=""
secret_list_file=""
write_env_template_file=""
dry_run="false"
check_mode="false"
print_required="false"
print_env_template="false"
scope="final"
storage_zone_explicit="false"
access_key_explicit="false"
storage_endpoint_explicit="false"
pull_zone_hostname_explicit="false"
remote_prefix_explicit="false"
release_private_key_file_explicit="false"
release_public_key_file_explicit="false"

usage() {
  cat <<'USAGE'
Set GitHub Actions secrets needed for Loopwire Bunny.net docs deployment.

Usage:
  setup-github-secrets.sh --repo owner/name [--scope deploy|final]
                          [--storage-zone ZONE --access-key KEY]
                          [--storage-endpoint URL] [--pull-zone-hostname HOST]
                          [--remote-prefix PATH]
                          [--release-private-key-file FILE]
                          [--release-public-key-file FILE]
                          [--env-file FILE]
  setup-github-secrets.sh --repo owner/name --check [--scope deploy|final] [--secret-list-file FILE]
  setup-github-secrets.sh --print-required [--scope deploy|final]
  setup-github-secrets.sh --print-env-template
  setup-github-secrets.sh --write-env-template FILE
  setup-github-secrets.sh --repo owner/name --dry-run [--scope deploy|final] [secret options]

Environment fallback:
  BUNNY_STORAGE_ZONE
  BUNNY_ACCESS_KEY
  BUNNY_STORAGE_ENDPOINT
  BUNNY_PULL_ZONE_HOSTNAME
  BUNNY_REMOTE_PREFIX
  LOOPWIRE_RELEASE_PUBLIC_KEY_FILE

Env files:
  --env-file accepts simple KEY=VALUE lines for the same environment names above.
  It also accepts LOOPWIRE_RELEASE_PRIVATE_KEY_FILE for a local private-key path.
  Command-line flags override env-file values.
  --print-env-template prints the committed no-value template accepted by --env-file.
  --write-env-template FILE writes that template with 0600 permissions and refuses overwrites.

Interactive set mode:
  When setting secrets for real and required values are missing, the helper prompts
  for one secret at a time, explains where to find it, and sends each value to
  `gh secret set` via stdin without printing the value. The release private-key
  prompt asks for a local PEM file path; the file contents are sent as
  LOOPWIRE_RELEASE_PRIVATE_KEY.

Secret-list files:
  --secret-list-file accepts saved `gh secret list` output for offline check-mode rehearsal.
  The file contains names only plus optional metadata columns; values must never be included.

Required deploy secrets:
  BUNNY_STORAGE_ZONE
  BUNNY_ACCESS_KEY

Required final-proof secrets:
  BUNNY_STORAGE_ZONE
  BUNNY_ACCESS_KEY
  BUNNY_PULL_ZONE_HOSTNAME
  LOOPWIRE_RELEASE_PRIVATE_KEY

Optional secrets:
  BUNNY_STORAGE_ENDPOINT
  BUNNY_REMOTE_PREFIX

No secret values are printed in --check or --dry-run output.
USAGE
}

print_required() {
  if [ "$scope" = "deploy" ]; then
    cat <<'SECRETS'
Required deploy GitHub secrets:
  BUNNY_STORAGE_ZONE
  BUNNY_ACCESS_KEY

Optional GitHub secrets:
  BUNNY_STORAGE_ENDPOINT
  BUNNY_REMOTE_PREFIX
  BUNNY_PULL_ZONE_HOSTNAME
SECRETS
    return
  fi

  cat <<'SECRETS'
Required final-proof GitHub secrets:
  BUNNY_STORAGE_ZONE
  BUNNY_ACCESS_KEY
  BUNNY_PULL_ZONE_HOSTNAME
  LOOPWIRE_RELEASE_PRIVATE_KEY

Optional GitHub secrets:
  BUNNY_STORAGE_ENDPOINT
  BUNNY_REMOTE_PREFIX
SECRETS
}

print_env_template() {
  cat <<'ENV_TEMPLATE'
# Local release-secret input template for scripts/setup-github-secrets.sh --env-file.
# Copy to an uncommitted path such as /secure/loopwire-release-secrets.env.
BUNNY_STORAGE_ZONE=
BUNNY_ACCESS_KEY=
BUNNY_STORAGE_ENDPOINT=
BUNNY_PULL_ZONE_HOSTNAME=
BUNNY_REMOTE_PREFIX=
LOOPWIRE_RELEASE_PRIVATE_KEY_FILE=
LOOPWIRE_RELEASE_PUBLIC_KEY_FILE=packaging/release-signing-public.pem
ENV_TEMPLATE
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

validate_local_file_path() {
  value="$1"
  label="$2"
  normalized="${value#./}"

  reject_unsafe_value "$value" "$label"

  [ -n "$normalized" ] || fail "$label must not be empty"
  case "$normalized" in
    "/" | "~" | "~/"* | *://* | *'*'* | *'?'* | *'['* | *']'*)
      fail "$label must not be root, home-expanded, URL-like, or contain glob metacharacters"
      ;;
  esac

  case "/$normalized/" in
    */../* | */./*)
      fail "$label must not contain . or .. path segments"
      ;;
  esac

  [ ! -L "$value" ] || fail "$label must not be a symlink"
  [ -f "$value" ] || fail "$label must be a file"
}

validate_local_output_file_path() {
  value="$1"
  label="$2"
  normalized="${value#./}"
  parent_dir="$(dirname "$value")"

  reject_unsafe_value "$value" "$label"

  [ -n "$normalized" ] || fail "$label must not be empty"
  case "$normalized" in
    "/" | "~" | "~/"* | *://* | *'*'* | *'?'* | *'['* | *']'* | */)
      fail "$label must not be root, home-expanded, URL-like, directory-like, or contain glob metacharacters"
      ;;
  esac

  case "/$normalized/" in
    */../* | */./*)
      fail "$label must not contain . or .. path segments"
      ;;
  esac

  [ ! -L "$value" ] || fail "$label must not be a symlink"
  [ ! -e "$value" ] || fail "$label already exists; refusing to overwrite"
  [ -d "$parent_dir" ] || fail "$label parent directory must exist"
  [ ! -L "$parent_dir" ] || fail "$label parent directory must not be a symlink"
}

write_env_template() {
  local old_umask

  validate_local_output_file_path "$write_env_template_file" "env template output file"

  old_umask="$(umask)"
  umask 077
  if ! (set -C; print_env_template >"$write_env_template_file"); then
    umask "$old_umask"
    fail "unable to write env template output file: $write_env_template_file"
  fi
  umask "$old_umask"
  chmod 600 "$write_env_template_file"

  echo "Wrote release secret env template: $write_env_template_file"
  echo "File permissions set to 0600. Fill values locally; do not commit this file."
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

env_value_for_log() {
  key="$1"
  printf '%s\n' "env-file value for ${key}"
}

strip_wrapping_quotes() {
  value="$1"

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
  key="$1"
  value="$2"

  reject_unsafe_value "$value" "$(env_value_for_log "$key")"

  case "$key" in
    BUNNY_STORAGE_ZONE)
      [ "$storage_zone_explicit" = "true" ] || storage_zone="$value"
      ;;
    BUNNY_ACCESS_KEY)
      [ "$access_key_explicit" = "true" ] || access_key="$value"
      ;;
    BUNNY_STORAGE_ENDPOINT)
      [ "$storage_endpoint_explicit" = "true" ] || storage_endpoint="$value"
      ;;
    BUNNY_PULL_ZONE_HOSTNAME)
      [ "$pull_zone_hostname_explicit" = "true" ] || pull_zone_hostname="$value"
      ;;
    BUNNY_REMOTE_PREFIX)
      [ "$remote_prefix_explicit" = "true" ] || remote_prefix="$value"
      ;;
    LOOPWIRE_RELEASE_PRIVATE_KEY_FILE)
      [ "$release_private_key_file_explicit" = "true" ] || release_private_key_file="$value"
      ;;
    LOOPWIRE_RELEASE_PUBLIC_KEY_FILE)
      [ "$release_public_key_file_explicit" = "true" ] || release_public_key_file="$value"
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

  validate_local_file_path "$env_file" "env file"

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

resolve_repo() {
  if [ -z "$repo" ]; then
    repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
  fi

  if [ -z "$repo" ]; then
    usage >&2
    exit 2
  fi
}

required_secrets_for_scope() {
  if [ "$scope" = "final" ]; then
    printf '%s\n' "BUNNY_STORAGE_ZONE BUNNY_ACCESS_KEY BUNNY_PULL_ZONE_HOSTNAME LOOPWIRE_RELEASE_PRIVATE_KEY"
    return
  fi

  printf '%s\n' "BUNNY_STORAGE_ZONE BUNNY_ACCESS_KEY"
}

has_secret() {
  secret_name="$1"
  printf '%s\n' "$secret_names" | grep -Fxq "$secret_name"
}

classify_missing_secret() {
  secret_name="$1"

  case "$secret_name" in
    BUNNY_STORAGE_ZONE | BUNNY_ACCESS_KEY)
      missing_bunny="true"
      ;;
    BUNNY_PULL_ZONE_HOSTNAME)
      missing_docs_live="true"
      ;;
    LOOPWIRE_RELEASE_PRIVATE_KEY)
      missing_release_key="true"
      ;;
  esac
}

report_required_secret() {
  secret_name="$1"

  if has_secret "$secret_name"; then
    echo "ok: GitHub secret present: $secret_name"
    if [ "$secret_name" = "BUNNY_PULL_ZONE_HOSTNAME" ]; then
      docs_live_smoke_ready="true"
    fi
    return
  fi

  echo "missing: GitHub secret: $secret_name" >&2
  missing=1
  classify_missing_secret "$secret_name"
}

report_optional_secret() {
  secret_name="$1"
  ready_flag="${2:-false}"

  if has_secret "$secret_name"; then
    echo "ok: optional GitHub secret present: $secret_name"
    if [ "$ready_flag" = "docs-live-smoke" ]; then
      docs_live_smoke_ready="true"
    fi
  else
    echo "optional: GitHub secret not set: $secret_name"
  fi
}

print_missing_secret_next_steps() {
  if [ "$missing_bunny" = "true" ]; then
    if [ "$scope" = "deploy" ]; then
      cat >&2 <<EOF
next: set Bunny.net deployment secrets without printing values:
  bash scripts/setup-github-secrets.sh --repo ${repo} --scope deploy \\
    --storage-zone <zone> --access-key <key>
  # Or create, fill, and load a local uncommitted env file:
  bash scripts/setup-github-secrets.sh --write-env-template <secret-env-file>
  bash scripts/setup-github-secrets.sh --repo ${repo} --scope deploy --env-file <secret-env-file>
EOF
    else
      cat >&2 <<EOF
next: set Bunny.net deployment secrets without printing values:
  bash scripts/setup-github-secrets.sh --repo ${repo} --scope final \\
    --storage-zone <zone> --access-key <key> --pull-zone-hostname <host> \\
    --release-private-key-file <private-key> \\
    --release-public-key-file packaging/release-signing-public.pem
  # Or create, fill, and load Bunny values and release key file paths from a local uncommitted env file:
  bash scripts/setup-github-secrets.sh --write-env-template <secret-env-file>
  bash scripts/setup-github-secrets.sh --repo ${repo} --scope final --env-file <secret-env-file>
EOF
    fi
  fi
  if [ "$missing_bunny" != "true" ] && [ "$missing_docs_live" = "true" ]; then
    cat >&2 <<EOF
next: set the Bunny.net pull-zone hostname needed for live docs smoke and final proof:
  bash scripts/setup-github-secrets.sh --repo ${repo} --scope final \\
    --storage-zone <zone> --access-key <key> --pull-zone-hostname <host> \\
    --release-private-key-file <private-key> \\
    --release-public-key-file packaging/release-signing-public.pem
  # Or create, fill, and load it from a local uncommitted env file:
  bash scripts/setup-github-secrets.sh --write-env-template <secret-env-file>
  bash scripts/setup-github-secrets.sh --repo ${repo} --scope final --env-file <secret-env-file>
EOF
  fi
  if [ "$missing_release_key" = "true" ]; then
    cat >&2 <<EOF
next: set release signing secret from a local private key:
  bash scripts/setup-github-secrets.sh --repo ${repo} --scope final \\
    --storage-zone <zone> --access-key <key> --pull-zone-hostname <host> \\
    --release-private-key-file <private-key> \\
    --release-public-key-file packaging/release-signing-public.pem
  # Or create, fill, and load LOOPWIRE_RELEASE_PRIVATE_KEY_FILE from a local uncommitted env file:
  bash scripts/setup-github-secrets.sh --write-env-template <secret-env-file>
  bash scripts/setup-github-secrets.sh --repo ${repo} --scope final --env-file <secret-env-file>
EOF
  fi
}

check_secret_presence() {
  local docs_live_smoke_ready="false"
  local missing_bunny="false"
  local missing_docs_live="false"
  local missing_release_key="false"
  local required_secrets

  if [ -n "$secret_list_file" ]; then
    if ! secret_list_output="$(cat "$secret_list_file" 2>&1)"; then
      echo "unable to read GitHub secret names from ${secret_list_file}: ${secret_list_output}" >&2
      exit 1
    fi
  else
    if ! secret_list_output="$(gh secret list --repo "$repo" 2>&1)"; then
      echo "unable to read GitHub secret names for ${repo}: ${secret_list_output}" >&2
      exit 1
    fi
  fi

  secret_names="$(printf '%s\n' "$secret_list_output" | awk '{ print $1 }')"
  missing=0
  required_secrets="$(required_secrets_for_scope)"

  for secret in $required_secrets; do
    report_required_secret "$secret"
  done

  if [ "$scope" = "deploy" ]; then
    report_optional_secret "BUNNY_PULL_ZONE_HOSTNAME" "docs-live-smoke"
  fi

  report_optional_secret "BUNNY_STORAGE_ENDPOINT"
  report_optional_secret "BUNNY_REMOTE_PREFIX"

  if [ "$missing" -ne 0 ]; then
    print_missing_secret_next_steps
    exit 1
  fi

  if [ "$scope" = "deploy" ]; then
    echo "ok: Bunny.net docs deployment secrets are present"
  else
    echo "ok: final release proof secrets are present"
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

require_set_input() {
  value="$1"
  label="$2"
  hint="$3"

  [ -n "$value" ] || fail "${label} is required for ${scope}-scope secret setup; use ${hint} or --env-file"
}

has_explicit_or_env_input() {
  [ -n "$storage_zone" ] ||
    [ -n "$access_key" ] ||
    [ -n "$storage_endpoint" ] ||
    [ -n "$pull_zone_hostname" ] ||
    [ -n "$remote_prefix" ] ||
    [ -n "$release_private_key_file" ] ||
    [ -n "$release_public_key_file" ] ||
    [ "$storage_zone_explicit" = "true" ] ||
    [ "$access_key_explicit" = "true" ] ||
    [ "$storage_endpoint_explicit" = "true" ] ||
    [ "$pull_zone_hostname_explicit" = "true" ] ||
    [ "$remote_prefix_explicit" = "true" ] ||
    [ "$release_private_key_file_explicit" = "true" ] ||
    [ "$release_public_key_file_explicit" = "true" ]
}

prompt_line() {
  secret_name="$1"
  target_var="$2"
  required="$3"
  sensitive="$4"
  default_value="$5"
  instructions="$6"
  current_value="${!target_var}"
  answer=""

  [ -z "$current_value" ] || return 0

  printf '\n%s\n' "$secret_name" >&2
  printf '%s\n' "$instructions" >&2
  if [ -n "$default_value" ]; then
    printf 'Press Enter to use: %s\n' "$default_value" >&2
  elif [ "$required" != "true" ]; then
    printf 'Press Enter to skip this optional secret.\n' >&2
  fi

  while :; do
    if [ "$sensitive" = "true" ] && [ -t 0 ]; then
      printf 'Value: ' >&2
      if ! IFS= read -r -s answer; then
        printf '\n' >&2
        fail "missing input for ${secret_name}"
      fi
      printf '\n' >&2
    else
      printf 'Value: ' >&2
      if ! IFS= read -r answer; then
        fail "missing input for ${secret_name}"
      fi
    fi

    if [ -z "$answer" ] && [ -n "$default_value" ]; then
      answer="$default_value"
    fi

    if [ -n "$answer" ] || [ "$required" != "true" ]; then
      break
    fi

    printf '%s is required for %s-scope secret setup.\n' "$secret_name" "$scope" >&2
  done

  printf -v "$target_var" '%s' "$answer"
}

prompt_missing_inputs_for_set_scope() {
  local prompt_optional="false"

  if [ -z "$env_file" ] && ! has_explicit_or_env_input; then
    prompt_optional="true"
  fi

  prompt_line \
    "BUNNY_STORAGE_ZONE" \
    storage_zone \
    true \
    false \
    "" \
    "Bunny.net storage zone name used by the docs deploy workflow, for example loopwire-docs. This value is stored as the BUNNY_STORAGE_ZONE GitHub secret."

  prompt_line \
    "BUNNY_ACCESS_KEY" \
    access_key \
    true \
    true \
    "" \
    "Bunny.net API/access key that can upload to the storage zone. Input is hidden when a TTY is available and is stored as the BUNNY_ACCESS_KEY GitHub secret."

  if [ "$scope" = "final" ]; then
    prompt_line \
      "BUNNY_PULL_ZONE_HOSTNAME" \
      pull_zone_hostname \
      true \
      false \
      "" \
      "Public Bunny pull-zone hostname used by live docs smoke and final release proof, for example docs.example.test. Do not include https:// or a path."

    prompt_line \
      "LOOPWIRE_RELEASE_PRIVATE_KEY" \
      release_private_key_file \
      true \
      false \
      "" \
      "Path to the local PEM release private key. The helper validates it, then sends the file contents directly to the LOOPWIRE_RELEASE_PRIVATE_KEY GitHub secret."

    prompt_line \
      "LOOPWIRE_RELEASE_PUBLIC_KEY_FILE" \
      release_public_key_file \
      true \
      false \
      "packaging/release-signing-public.pem" \
      "Path to the public key used only to validate the private key before any secret is written. This is not stored as a GitHub secret."
  elif [ "$prompt_optional" = "true" ]; then
    prompt_line \
      "BUNNY_PULL_ZONE_HOSTNAME" \
      pull_zone_hostname \
      false \
      false \
      "" \
      "Optional live-docs hostname for deploy-scope smoke. Do not include https:// or a path."
  fi

  if [ "$prompt_optional" = "true" ]; then
    prompt_line \
      "BUNNY_STORAGE_ENDPOINT" \
      storage_endpoint \
      false \
      false \
      "" \
      "Optional Bunny storage endpoint override, for example ny.storage.bunnycdn.com."

    prompt_line \
      "BUNNY_REMOTE_PREFIX" \
      remote_prefix \
      false \
      false \
      "" \
      "Optional remote path prefix for docs deployment, without leading slash or traversal segments."
  fi
}

validate_required_inputs_for_set_scope() {
  require_set_input "$storage_zone" "BUNNY_STORAGE_ZONE" "--storage-zone"
  require_set_input "$access_key" "BUNNY_ACCESS_KEY" "--access-key"

  if [ "$scope" = "deploy" ]; then
    return
  fi

  require_set_input "$pull_zone_hostname" "BUNNY_PULL_ZONE_HOSTNAME" "--pull-zone-hostname"
  require_set_input "$release_private_key_file" "LOOPWIRE_RELEASE_PRIVATE_KEY_FILE" "--release-private-key-file"
  require_set_input "$release_public_key_file" "LOOPWIRE_RELEASE_PUBLIC_KEY_FILE" "--release-public-key-file"
}

validate_requested_secret_set() {
  validate_required_inputs_for_set_scope

  if [ -n "$storage_zone" ] || [ -n "$access_key" ]; then
    if [ -z "$storage_zone" ] || [ -z "$access_key" ]; then
      echo "Bunny.net deployment secrets require both storage zone and access key." >&2
      exit 2
    fi
  fi

  if [ -n "$release_private_key_file" ]; then
    validate_local_file_path "$release_private_key_file" "release private key file"
  fi

  if [ -n "$release_public_key_file" ]; then
    validate_local_file_path "$release_public_key_file" "release public key file"
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

validate_scope() {
  case "$scope" in
    deploy | final)
      ;;
    *)
      echo "--scope must be deploy or final." >&2
      exit 2
      ;;
  esac
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
      storage_zone_explicit="true"
      shift 2
      ;;
    --access-key)
      access_key="${2:?missing value for --access-key}"
      access_key_explicit="true"
      shift 2
      ;;
    --storage-endpoint)
      storage_endpoint="${2:?missing value for --storage-endpoint}"
      storage_endpoint_explicit="true"
      shift 2
      ;;
    --pull-zone-hostname)
      pull_zone_hostname="${2:?missing value for --pull-zone-hostname}"
      pull_zone_hostname_explicit="true"
      shift 2
      ;;
    --remote-prefix)
      remote_prefix="${2:?missing value for --remote-prefix}"
      remote_prefix_explicit="true"
      shift 2
      ;;
    --release-private-key-file)
      release_private_key_file="${2:?missing value for --release-private-key-file}"
      release_private_key_file_explicit="true"
      shift 2
      ;;
    --release-public-key-file)
      release_public_key_file="${2:?missing value for --release-public-key-file}"
      release_public_key_file_explicit="true"
      shift 2
      ;;
    --env-file)
      env_file="${2:?missing value for --env-file}"
      shift 2
      ;;
    --secret-list-file)
      secret_list_file="${2:?missing value for --secret-list-file}"
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
    --scope)
      scope="${2:?missing value for --scope}"
      shift 2
      ;;
    --print-required)
      print_required="true"
      shift
      ;;
    --print-env-template)
      print_env_template="true"
      shift
      ;;
    --write-env-template)
      write_env_template_file="${2:?missing value for --write-env-template}"
      shift 2
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

validate_scope

if [ "$print_env_template" = "true" ] && [ -n "$write_env_template_file" ]; then
  echo "--print-env-template and --write-env-template are mutually exclusive." >&2
  exit 2
fi

if [ -n "$write_env_template_file" ] &&
  { [ "$check_mode" = "true" ] ||
    [ "$dry_run" = "true" ] ||
    [ "$print_required" = "true" ] ||
    [ -n "$env_file" ] ||
    [ -n "$secret_list_file" ] ||
    [ "$storage_zone_explicit" = "true" ] ||
    [ "$access_key_explicit" = "true" ] ||
    [ "$storage_endpoint_explicit" = "true" ] ||
    [ "$pull_zone_hostname_explicit" = "true" ] ||
    [ "$remote_prefix_explicit" = "true" ] ||
    [ "$release_private_key_file_explicit" = "true" ] ||
    [ "$release_public_key_file_explicit" = "true" ]; }; then
  echo "--write-env-template cannot be combined with secret, check, or dry-run options." >&2
  exit 2
fi

if [ "$print_required" = "true" ]; then
  print_required
  exit 0
fi

if [ "$print_env_template" = "true" ]; then
  print_env_template
  exit 0
fi

if [ -n "$write_env_template_file" ]; then
  write_env_template
  exit 0
fi

if [ "$check_mode" = "true" ] && [ "$dry_run" = "true" ]; then
  echo "--check and --dry-run are mutually exclusive." >&2
  exit 2
fi

if [ -n "$secret_list_file" ] && [ "$check_mode" != "true" ]; then
  echo "--secret-list-file requires --check." >&2
  exit 2
fi

if [ -n "$secret_list_file" ]; then
  validate_local_file_path "$secret_list_file" "secret-list file"
fi

if [ -n "$env_file" ]; then
  load_env_file
fi

if [ -z "$repo" ] ||
  { [ "$check_mode" = "true" ] && [ -z "$secret_list_file" ]; } ||
  { [ "$check_mode" != "true" ] && [ "$dry_run" != "true" ]; }; then
  require_gh
fi

resolve_repo

if [ "$check_mode" = "true" ]; then
  check_secret_presence
  exit 0
fi

if [ "$dry_run" != "true" ]; then
  prompt_missing_inputs_for_set_scope
fi

validate_requested_secret_set

set_any="false"

if [ -n "$storage_zone" ] || [ -n "$access_key" ]; then
  if [ "$dry_run" = "true" ]; then
    echo "would set GitHub secret for ${repo}: BUNNY_STORAGE_ZONE"
    echo "would set GitHub secret for ${repo}: BUNNY_ACCESS_KEY"
  else
    printf '%s' "$storage_zone" | set_github_secret BUNNY_STORAGE_ZONE
    printf '%s' "$access_key" | set_github_secret BUNNY_ACCESS_KEY
  fi
  set_any="true"

fi

if [ -n "$pull_zone_hostname" ]; then
  if [ "$dry_run" = "true" ]; then
    echo "would set GitHub secret for ${repo}: BUNNY_PULL_ZONE_HOSTNAME"
  else
    printf '%s' "$pull_zone_hostname" | set_github_secret BUNNY_PULL_ZONE_HOSTNAME
  fi
  set_any="true"
fi

if [ -n "$storage_endpoint" ]; then
  if [ "$dry_run" = "true" ]; then
    echo "would set optional GitHub secret for ${repo}: BUNNY_STORAGE_ENDPOINT"
  else
    printf '%s' "$storage_endpoint" | set_github_secret BUNNY_STORAGE_ENDPOINT
  fi
  set_any="true"
fi

if [ -n "$remote_prefix" ]; then
  if [ "$dry_run" = "true" ]; then
    echo "would set optional GitHub secret for ${repo}: BUNNY_REMOTE_PREFIX"
  else
    printf '%s' "$remote_prefix" | set_github_secret BUNNY_REMOTE_PREFIX
  fi
  set_any="true"
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
