#!/usr/bin/env bash
set -euo pipefail

package_name=""
version=""
pkgrel="1"
release_dir=""
source_archive=""
output_path=""
published="false"
default_branch=""

usage() {
  cat <<'USAGE'
Render a Loopwire AUR PKGBUILD from verified local inputs.

Usage:
  render-aur-pkgbuild.sh --package loopwire-bin --version VERSION --release-dir DIR --output PATH [--pkgrel N] [--published]
  render-aur-pkgbuild.sh --package loopwire --version VERSION --source-archive FILE --output PATH [--pkgrel N] [--published]
  render-aur-pkgbuild.sh --package loopwire-git --version VERSION --default-branch BRANCH --output PATH [--pkgrel N] [--published]

Without --published, binary release URLs are rewritten to local file:// inputs.
Source builds keep their immutable tag URL and can be made offline by placing
the checksum-matching archive beside PKGBUILD. With --published, all rendered
URLs are the immutable GitHub tag/release URLs used by the AUR.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --) shift ;;
    --package) package_name="${2:?missing value for --package}"; shift 2 ;;
    --version) version="${2:?missing value for --version}"; shift 2 ;;
    --pkgrel) pkgrel="${2:?missing value for --pkgrel}"; shift 2 ;;
    --release-dir) release_dir="${2:?missing value for --release-dir}"; shift 2 ;;
    --source-archive) source_archive="${2:?missing value for --source-archive}"; shift 2 ;;
    --default-branch) default_branch="${2:?missing value for --default-branch}"; shift 2 ;;
    --output) output_path="${2:?missing value for --output}"; shift 2 ;;
    --published) published="true"; shift ;;
    -h | --help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -z "$package_name" ] || [ -z "$version" ] || [ -z "$output_path" ]; then
  usage >&2
  exit 2
fi
case "$package_name" in
  loopwire-git)
    [[ "$version" =~ ^[0-9]+([.][0-9]+)*[.]r[0-9]+[.]g[0-9a-f]+$ ]] || {
      echo "loopwire-git version must look like 1.2.3.r4.gabcdef0: $version" >&2
      exit 2
    }
    ;;
  *)
    [[ "$version" =~ ^[0-9]+([.][0-9]+)*$ ]] || {
      echo "Version must contain dot-separated integers: $version" >&2
      exit 2
    }
    ;;
esac
if [[ ! "$pkgrel" =~ ^[1-9][0-9]*$ ]]; then
  echo "pkgrel must be a positive integer: $pkgrel" >&2
  exit 2
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
license_file="$root/packaging/aur/LICENSE-MIT"
[ -f "$license_file" ] || {
  echo "Missing AUR license file: $license_file" >&2
  exit 1
}
license_hash="$(sha256sum "$license_file" | awk '{ print $1 }')"
tmp_output="$(mktemp)"
cleanup() {
  rm -f "$tmp_output" "${tmp_output}.local"
}
trap cleanup EXIT

case "$package_name" in
  loopwire-bin)
    template_path="$root/packaging/aur/loopwire-bin/PKGBUILD.in"
    release_dir="${release_dir%/}"
    x86_asset="$release_dir/loopwire-linux-x86_64.tar.gz"
    aarch64_asset="$release_dir/loopwire-linux-aarch64.tar.gz"
    if [ ! -f "$x86_asset" ] || [ ! -f "$aarch64_asset" ]; then
      echo "loopwire-bin requires both release tarballs in: $release_dir" >&2
      exit 1
    fi
    x86_hash="$(sha256sum "$x86_asset" | awk '{ print $1 }')"
    aarch64_hash="$(sha256sum "$aarch64_asset" | awk '{ print $1 }')"
    sed \
      -e "s/@VERSION@/${version}/g" \
      -e "s/@PKGREL@/${pkgrel}/g" \
      -e "s/@SHA256_LICENSE@/${license_hash}/g" \
      -e "s/@SHA256_X86_64@/${x86_hash}/g" \
      -e "s/@SHA256_AARCH64@/${aarch64_hash}/g" \
      "$template_path" >"$tmp_output"
    if [ "$published" = "false" ]; then
      release_dir_abs="$(cd "$release_dir" && pwd -P)"
      awk -v release_dir="$release_dir_abs" '
        /^source_x86_64=/ {
          print "source_x86_64=(\"loopwire-linux-x86_64.tar.gz::file://" release_dir "/loopwire-linux-x86_64.tar.gz\")"
          next
        }
        /^source_aarch64=/ {
          print "source_aarch64=(\"loopwire-linux-aarch64.tar.gz::file://" release_dir "/loopwire-linux-aarch64.tar.gz\")"
          next
        }
        { print }
      ' "$tmp_output" >"${tmp_output}.local"
      mv "${tmp_output}.local" "$tmp_output"
    fi
    ;;
  loopwire)
    template_path="$root/packaging/aur/loopwire/PKGBUILD.in"
    if [ ! -f "$source_archive" ]; then
      echo "loopwire requires --source-archive FILE" >&2
      exit 1
    fi
    source_hash="$(sha256sum "$source_archive" | awk '{ print $1 }')"
    sed \
      -e "s/@VERSION@/${version}/g" \
      -e "s/@PKGREL@/${pkgrel}/g" \
      -e "s/@SHA256_SOURCE@/${source_hash}/g" \
      -e "s/@SHA256_LICENSE@/${license_hash}/g" \
      "$template_path" >"$tmp_output"
    ;;
  loopwire-git)
    [ -n "$default_branch" ] || {
      echo "loopwire-git requires --default-branch BRANCH" >&2
      exit 2
    }
    git check-ref-format --branch "$default_branch" >/dev/null 2>&1 || {
      echo "Invalid default branch: $default_branch" >&2
      exit 2
    }
    template_path="$root/packaging/aur/loopwire-git/PKGBUILD.in"
    sed \
      -e "s/@VERSION@/${version}/g" \
      -e "s/@PKGREL@/${pkgrel}/g" \
      -e "s/@SHA256_LICENSE@/${license_hash}/g" \
      -e "s/@DEFAULT_BRANCH@/${default_branch}/g" \
      "$template_path" >"$tmp_output"
    ;;
  *) echo "Unsupported AUR package: $package_name" >&2; exit 2 ;;
esac

if grep -Eq '@[A-Z0-9_]+@' "$tmp_output"; then
  echo "Rendered PKGBUILD contains an unresolved placeholder." >&2
  exit 1
fi

mkdir -p "$(dirname "$output_path")"
cp "$tmp_output" "$output_path"
echo "Rendered $output_path"
