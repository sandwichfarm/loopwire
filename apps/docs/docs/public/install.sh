#!/usr/bin/env bash
set -euo pipefail

repo="${LOOPWIRE_REPO:-sandwichfarm/loopwire}"
version="${LOOPWIRE_VERSION:-latest}"
prefix="${PREFIX:-$HOME/.local/bin}"
dry_run="false"
base_url_override="${LOOPWIRE_BASE_URL:-}"
public_key_file="${LOOPWIRE_RELEASE_PUBLIC_KEY_FILE:-}"
skip_signature="${LOOPWIRE_SKIP_SIGNATURE:-false}"

usage() {
  cat <<'USAGE'
Install Loopwire from a GitHub release artifact.

Usage:
  install.sh [--repo owner/name] [--version vX.Y.Z|latest] [--base-url URL] [--prefix DIR] [--public-key FILE] [--skip-signature] [--dry-run]

Environment:
  LOOPWIRE_REPO      GitHub repository, default sandwichfarm/loopwire
  LOOPWIRE_VERSION   Release tag, default latest
  LOOPWIRE_BASE_URL  Override release asset base URL, useful for local file:// smoke tests
  LOOPWIRE_RELEASE_PUBLIC_KEY_FILE
                     Public key used to verify SHA256SUMS.sig
  LOOPWIRE_SKIP_SIGNATURE
                     Set true only for explicit unsigned local development installs
  PREFIX             Install directory, default ~/.local/bin

The installer expects release assets named:
  loopwire-linux-x86_64.tar.gz
  loopwire-linux-aarch64.tar.gz

It also expects SHA256SUMS and SHA256SUMS.sig in the release assets.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      repo="${2:?missing value for --repo}"
      shift 2
      ;;
    --version)
      version="${2:?missing value for --version}"
      shift 2
      ;;
    --base-url)
      base_url_override="${2:?missing value for --base-url}"
      shift 2
      ;;
    --prefix)
      prefix="${2:?missing value for --prefix}"
      shift 2
      ;;
    --public-key)
      public_key_file="${2:?missing value for --public-key}"
      shift 2
      ;;
    --skip-signature)
      skip_signature="true"
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
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

validate_archive_members() {
  archive="$1"
  listing="$tmp_dir/archive-members.txt"

  tar -tzf "$archive" >"$listing"
  if [ ! -s "$listing" ]; then
    echo "Release artifact is empty: $(basename "$archive")" >&2
    exit 1
  fi

  while IFS= read -r entry; do
    [ -n "$entry" ] || {
      echo "Release artifact contains an empty path." >&2
      exit 1
    }

    case "$entry" in
      /*)
        echo "Release artifact contains an absolute path: $entry" >&2
        exit 1
        ;;
    esac

    case "/$entry/" in
      *"/../"*)
        echo "Release artifact contains a parent path component: $entry" >&2
        exit 1
        ;;
    esac
  done <"$listing"
}

detect_arch() {
  case "$(uname -m)" in
    x86_64 | amd64)
      printf '%s\n' "x86_64"
      ;;
    aarch64 | arm64)
      printf '%s\n' "aarch64"
      ;;
    *)
      echo "Unsupported architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac
}

if [ "$(uname -s)" != "Linux" ]; then
  echo "Loopwire installer currently supports Linux only." >&2
  exit 1
fi

require_cmd curl
require_cmd tar
require_cmd sha256sum
require_cmd install
require_cmd cp

arch="$(detect_arch)"
asset="loopwire-linux-${arch}.tar.gz"

if [ -n "$base_url_override" ]; then
  base_url="${base_url_override%/}"
elif [ "$version" = "latest" ]; then
  base_url="https://github.com/${repo}/releases/latest/download"
else
  base_url="https://github.com/${repo}/releases/download/${version}"
fi

echo "Loopwire release source: ${base_url}/${asset}"
echo "Install prefix: ${prefix}"
if [ "$skip_signature" = "true" ]; then
  echo "Signature verification: skipped by explicit request"
else
  echo "Signature verification: required"
fi

if [ "$dry_run" = "true" ]; then
  echo "Dry run complete. No files changed."
  exit 0
fi

if [ -z "$public_key_file" ] && [ -f "packaging/release-signing-public.pem" ]; then
  public_key_file="packaging/release-signing-public.pem"
fi

if [ "$skip_signature" != "true" ]; then
  require_cmd openssl
  if [ -z "$public_key_file" ]; then
    echo "Signed release verification requires --public-key or LOOPWIRE_RELEASE_PUBLIC_KEY_FILE." >&2
    echo "Use --skip-signature only for explicit unsigned local development installs." >&2
    exit 1
  fi
  if [ ! -f "$public_key_file" ]; then
    echo "Release public key does not exist: $public_key_file" >&2
    exit 1
  fi
  public_key_file="$(cd "$(dirname "$public_key_file")" && pwd -P)/$(basename "$public_key_file")"
fi

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

curl -fsSL "${base_url}/SHA256SUMS" -o "$tmp_dir/SHA256SUMS"
if [ "$skip_signature" != "true" ]; then
  curl -fsSL "${base_url}/SHA256SUMS.sig" -o "$tmp_dir/SHA256SUMS.sig"
fi
curl -fsSL "${base_url}/${asset}" -o "$tmp_dir/${asset}"

(
  cd "$tmp_dir"
  if [ "$skip_signature" != "true" ]; then
    openssl dgst -sha256 -verify "$public_key_file" -signature SHA256SUMS.sig SHA256SUMS >/dev/null
  fi
  awk -v asset="$asset" '$2 == asset { found = 1 } END { exit found ? 0 : 1 }' SHA256SUMS || {
    echo "SHA256SUMS does not contain ${asset}." >&2
    exit 1
  }
  sha256sum --check --ignore-missing SHA256SUMS
  validate_archive_members "$asset"
  tar -xzf "$asset"
)

binary_path="$(find "$tmp_dir" -type f -name loopwire -perm -111 | head -n 1)"
provider_path="$(find "$tmp_dir" -type f -name loopwire-dsp-provider -perm -111 | head -n 1)"
jack_provider_path="$(find "$tmp_dir" -type f -name loopwire-jack-ports -perm -111 | head -n 1)"

if [ -z "$binary_path" ]; then
  echo "Release artifact did not contain an executable named loopwire." >&2
  exit 1
fi

mkdir -p "$prefix"
install -m 0755 "$binary_path" "$prefix/loopwire"
if [ -n "$provider_path" ]; then
  install -m 0755 "$provider_path" "$prefix/loopwire-dsp-provider"
fi
if [ -n "$jack_provider_path" ]; then
  install -m 0755 "$jack_provider_path" "$prefix/loopwire-jack-ports"
fi

libexec_source="$tmp_dir/libexec/loopwire"
if [ -d "$libexec_source" ]; then
  libexec_target="$(dirname "$prefix")/lib/loopwire"
  mkdir -p "$libexec_target"
  cp -R "$libexec_source/." "$libexec_target/"
  find "$libexec_target" -type d -exec chmod 0755 {} +
  find "$libexec_target" -type f -exec chmod 0644 {} +
  if [ -f "$libexec_target/loopwire-gui" ]; then
    chmod 0755 "$libexec_target/loopwire-gui"
  fi
  echo "Loopwire support files installed to ${libexec_target}"
fi

echo "Loopwire installed to ${prefix}/loopwire"
if [ -n "$provider_path" ]; then
  echo "Loopwire DSP provider installed to ${prefix}/loopwire-dsp-provider"
fi
if [ -n "$jack_provider_path" ]; then
  echo "Loopwire JACK ports provider installed to ${prefix}/loopwire-jack-ports"
fi
