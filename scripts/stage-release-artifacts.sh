#!/usr/bin/env bash
set -euo pipefail

binary_path=""
version=""
arch=""
bundle_dir=""
output_dir="dist/release"
private_key_file=""
native_packages="false"

usage() {
  cat <<'USAGE'
Stage Loopwire release artifacts into one directory and write SHA256SUMS for every attachment.

Usage:
  stage-release-artifacts.sh --binary PATH --version VERSION --bundle-dir DIR [--arch x86_64|aarch64] [--output-dir DIR] [--private-key FILE] [--native-packages]

With --native-packages on x86_64, Tauri's GUI-only deb/rpm outputs are replaced by the repository-owned Ubuntu,
Debian, Fedora, and openSUSE packages built from the canonical release tarball. The bundle directory must contain an
AppImage; without --native-packages, legacy Tauri deb/rpm bundles are staged unchanged.
USAGE
}

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
    --bundle-dir)
      bundle_dir="${2:?missing value for --bundle-dir}"
      shift 2
      ;;
    --output-dir)
      output_dir="${2:?missing value for --output-dir}"
      shift 2
      ;;
    --private-key)
      private_key_file="${2:?missing value for --private-key}"
      shift 2
      ;;
    --native-packages)
      native_packages="true"
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

if [ -z "$binary_path" ] || [ -z "$version" ] || [ -z "$bundle_dir" ]; then
  usage >&2
  exit 2
fi

if [ -z "$arch" ]; then
  arch="$(normalize_arch "$(uname -m)")"
fi

if [ ! -d "$bundle_dir" ]; then
  echo "Bundle directory does not exist: $bundle_dir" >&2
  exit 1
fi

mkdir -p "$output_dir"
bash scripts/package-release.sh \
  --binary "$binary_path" \
  --version "$version" \
  --arch "$arch" \
  --output-dir "$output_dir" >/dev/null

bundle_count=0
while IFS= read -r -d '' bundle_file; do
  cp "$bundle_file" "$output_dir/"
  bundle_count=$((bundle_count + 1))
done < <(
  if [ "$native_packages" = "true" ]; then
    find "$bundle_dir" -type f -name "*.AppImage" -print0
  else
    find "$bundle_dir" -type f \( -name "*.AppImage" -o -name "*.deb" -o -name "*.rpm" \) -print0
  fi
)

if [ "$bundle_count" -eq 0 ]; then
  echo "No Tauri bundle artifacts were found in $bundle_dir." >&2
  exit 1
fi

if [ "$native_packages" = "true" ]; then
  if [ "$arch" != "x86_64" ]; then
    echo "Native distro packages are currently verified only for x86_64." >&2
    exit 1
  fi
  node scripts/verify-native-package-proof-snapshot.mjs >/dev/null
  for target in ubuntu-24.04 debian-13; do
    bash scripts/build-deb-package.sh \
      --target "$target" \
      --version "$version" \
      --arch "$arch" \
      --release-dir "$output_dir" \
      --output-dir "$output_dir" >/dev/null
  done
  for target in fedora-44 opensuse-tumbleweed; do
    bash scripts/build-rpm-package.sh \
      --target "$target" \
      --version "$version" \
      --arch "$arch" \
      --release-dir "$output_dir" \
      --output-dir "$output_dir" >/dev/null
  done
fi

(
  cd "$output_dir"
  find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\n' \
    | sort \
    | xargs sha256sum >SHA256SUMS
  sha256sum --check SHA256SUMS
) >/dev/null

if [ -n "$private_key_file" ]; then
  bash scripts/sign-release-artifacts.sh --release-dir "$output_dir" --private-key "$private_key_file" >/dev/null
fi

echo "Staged release artifacts in $output_dir"
