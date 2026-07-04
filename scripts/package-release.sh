#!/usr/bin/env bash
set -euo pipefail

name="loopwire"
version=""
arch=""
binary_path=""
output_dir="dist/release"
source_date_epoch="${SOURCE_DATE_EPOCH:-0}"

usage() {
  cat <<'USAGE'
Create a reproducible Loopwire binary release artifact and SHA256SUMS entry.

Usage:
  package-release.sh --binary PATH --version VERSION [--arch x86_64|aarch64] [--output-dir DIR] [--name loopwire]

The generated artifact name matches scripts/install.sh:
  loopwire-linux-x86_64.tar.gz
  loopwire-linux-aarch64.tar.gz

The tarball includes:
  loopwire                         Launcher for GUI and background restore
  loopwire-dsp-provider            File-backed command DSP provider
  libexec/loopwire/loopwire-gui    Tauri desktop binary
  libexec/loopwire/scripts         Background restore runner
  libexec/loopwire/packages        Compiled core/audio-host runtime assets

SOURCE_DATE_EPOCH controls tar metadata timestamps and defaults to 0.
USAGE
}

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

normalize_arch() {
  case "$1" in
    x86_64 | amd64)
      printf '%s\n' "x86_64"
      ;;
    aarch64 | arm64)
      printf '%s\n' "aarch64"
      ;;
    *)
      echo "Unsupported architecture: $1" >&2
      exit 1
      ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --binary)
      binary_path="${2:?missing value for --binary}"
      shift 2
      ;;
    --version)
      version="${2:?missing value for --version}"
      shift 2
      ;;
    --arch)
      arch="$(normalize_arch "${2:?missing value for --arch}")"
      shift 2
      ;;
    --output-dir)
      output_dir="${2:?missing value for --output-dir}"
      shift 2
      ;;
    --name)
      name="${2:?missing value for --name}"
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

if [ -z "$binary_path" ]; then
  echo "--binary is required." >&2
  usage >&2
  exit 2
fi

if [ -z "$version" ]; then
  echo "--version is required." >&2
  usage >&2
  exit 2
fi

if [ -z "$arch" ]; then
  arch="$(normalize_arch "$(uname -m)")"
fi

case "$name" in
  *[!A-Za-z0-9._-]* | "")
    echo "--name must contain only letters, numbers, dot, underscore, or dash." >&2
    exit 2
    ;;
esac

case "$source_date_epoch" in
  *[!0-9]* | "")
    echo "SOURCE_DATE_EPOCH must be an integer Unix timestamp." >&2
    exit 2
    ;;
esac

if [ ! -f "$binary_path" ]; then
  echo "Binary does not exist: $binary_path" >&2
  exit 1
fi

if [ ! -x "$binary_path" ]; then
  echo "Binary is not executable: $binary_path" >&2
  exit 1
fi

restore_script="$root/scripts/restore-background.mjs"
core_dist="$root/packages/core/dist"
audio_host_dist="$root/packages/audio-host/dist"

if [ ! -f "$restore_script" ]; then
  echo "Missing background restore script: $restore_script" >&2
  exit 1
fi

if [ ! -f "$core_dist/index.js" ] || [ ! -f "$audio_host_dist/index.js" ]; then
  echo "Compiled background restore assets are missing." >&2
  echo "Run: pnpm --filter @loopwire/core build && pnpm --filter @loopwire/audio-host build" >&2
  exit 1
fi

if [ ! -f "$audio_host_dist/dsp-provider-cli.js" ]; then
  echo "Compiled DSP provider CLI is missing." >&2
  echo "Run: pnpm --filter @loopwire/audio-host build" >&2
  exit 1
fi

asset="${name}-linux-${arch}.tar.gz"
artifact_path="${output_dir%/}/${asset}"
checksums_path="${output_dir%/}/SHA256SUMS"
tmp_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir -p \
  "$output_dir" \
  "$tmp_dir/payload/libexec/$name/scripts" \
  "$tmp_dir/payload/libexec/$name/packages/core" \
  "$tmp_dir/payload/libexec/$name/packages/audio-host"

install -m 0755 "$binary_path" "$tmp_dir/payload/libexec/$name/${name}-gui"
install -m 0644 "$restore_script" "$tmp_dir/payload/libexec/$name/scripts/restore-background.mjs"
cp -R "$core_dist" "$tmp_dir/payload/libexec/$name/packages/core/dist"
cp -R "$audio_host_dist" "$tmp_dir/payload/libexec/$name/packages/audio-host/dist"

cat >"$tmp_dir/payload/$name" <<'EOF'
#!/usr/bin/env sh
set -eu

script_dir="$(CDPATH= cd "$(dirname "$0")" && pwd -P)"
archive_libexec="$script_dir/libexec/@LOOPWIRE_NAME@"
installed_libexec="$script_dir/../lib/@LOOPWIRE_NAME@"

if [ -x "$archive_libexec/loopwire-gui" ]; then
  libexec_dir="${LOOPWIRE_LIBEXEC_DIR:-$archive_libexec}"
else
  libexec_dir="${LOOPWIRE_LIBEXEC_DIR:-$installed_libexec}"
fi

gui="$libexec_dir/@LOOPWIRE_NAME@-gui"
restore="$libexec_dir/scripts/restore-background.mjs"

case "${1:-}" in
  --background | restore-background)
    shift
    if ! command -v node >/dev/null 2>&1; then
      echo "loopwire: background restore requires node on PATH" >&2
      exit 127
    fi
    if [ ! -f "$restore" ]; then
      echo "loopwire: bundled background restore script is missing: $restore" >&2
      exit 1
    fi
    exec node "$restore" "$@"
    ;;
  --gui)
    shift
    ;;
esac

if [ ! -x "$gui" ]; then
  echo "loopwire: bundled GUI binary is missing or not executable: $gui" >&2
  exit 1
fi

exec "$gui" "$@"
EOF
sed -i "s/@LOOPWIRE_NAME@/$name/g" "$tmp_dir/payload/$name"
chmod 0755 "$tmp_dir/payload/$name"

cat >"$tmp_dir/payload/${name}-dsp-provider" <<'EOF'
#!/usr/bin/env sh
set -eu

script_dir="$(CDPATH= cd "$(dirname "$0")" && pwd -P)"
archive_libexec="$script_dir/libexec/@LOOPWIRE_NAME@"
installed_libexec="$script_dir/../lib/@LOOPWIRE_NAME@"

if [ -d "$archive_libexec/packages/audio-host/dist" ]; then
  libexec_dir="${LOOPWIRE_LIBEXEC_DIR:-$archive_libexec}"
else
  libexec_dir="${LOOPWIRE_LIBEXEC_DIR:-$installed_libexec}"
fi

provider="$libexec_dir/packages/audio-host/dist/dsp-provider-cli.js"

if ! command -v node >/dev/null 2>&1; then
  echo "@LOOPWIRE_NAME@-dsp-provider: node is required on PATH" >&2
  exit 127
fi

if [ ! -f "$provider" ]; then
  echo "@LOOPWIRE_NAME@-dsp-provider: bundled provider is missing: $provider" >&2
  exit 1
fi

exec node "$provider" "$@"
EOF
sed -i "s/@LOOPWIRE_NAME@/$name/g" "$tmp_dir/payload/${name}-dsp-provider"
chmod 0755 "$tmp_dir/payload/${name}-dsp-provider"

cat >"$tmp_dir/payload/RELEASE" <<EOF
name=$name
version=$version
arch=$arch
source_date_epoch=$source_date_epoch
EOF

tar \
  --sort=name \
  --mtime="@${source_date_epoch}" \
  --owner=0 \
  --group=0 \
  --numeric-owner \
  -C "$tmp_dir/payload" \
  -cf - \
  RELEASE "$name" "${name}-dsp-provider" libexec | gzip -n >"$artifact_path"

mkdir -p "$tmp_dir/check"
tar -xzf "$artifact_path" -C "$tmp_dir/check"

if [ ! -x "$tmp_dir/check/$name" ]; then
  echo "Generated artifact does not contain executable ${name}." >&2
  exit 1
fi

if [ ! -x "$tmp_dir/check/${name}-dsp-provider" ]; then
  echo "Generated artifact does not contain executable ${name}-dsp-provider." >&2
  exit 1
fi

if [ ! -x "$tmp_dir/check/libexec/$name/${name}-gui" ]; then
  echo "Generated artifact does not contain executable libexec/${name}/${name}-gui." >&2
  exit 1
fi

if [ ! -f "$tmp_dir/check/libexec/$name/scripts/restore-background.mjs" ]; then
  echo "Generated artifact does not contain bundled background restore script." >&2
  exit 1
fi

checksum="$(sha256sum "$artifact_path" | awk '{ print $1 }')"
tmp_sums="$tmp_dir/SHA256SUMS"

if [ -f "$checksums_path" ]; then
  awk -v asset="$asset" '$2 != asset { print }' "$checksums_path" >"$tmp_sums"
fi

printf '%s  %s\n' "$checksum" "$asset" >>"$tmp_sums"
sort -k2,2 "$tmp_sums" >"$checksums_path"

echo "Wrote $artifact_path"
echo "Updated $checksums_path"
