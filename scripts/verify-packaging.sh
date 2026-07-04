#!/usr/bin/env bash
set -euo pipefail

require_contains() {
  file="$1"
  pattern="$2"

  if ! grep -Fq "$pattern" "$file"; then
    echo "Expected $file to contain: $pattern" >&2
    exit 1
  fi
}

require_contains packaging/aur/PKGBUILD.in "loopwire-linux-x86_64.tar.gz"
require_contains packaging/aur/PKGBUILD.in "loopwire-linux-aarch64.tar.gz"
require_contains packaging/aur/PKGBUILD.in "github.com/sandwichfarm/loopwire"
require_contains packaging/aur/PKGBUILD.in "install -Dm755 loopwire"
require_contains packaging/aur/PKGBUILD.in "install -Dm755 loopwire-dsp-provider"
require_contains packaging/aur/PKGBUILD.in "install -Dm755 loopwire-jack-ports"
require_contains packaging/aur/PKGBUILD.in "nodejs"
require_contains packaging/aur/PKGBUILD.in "usr/lib/loopwire"
require_contains packaging/nix/loopwire-bin.nix "loopwire-linux-x86_64.tar.gz"
require_contains packaging/nix/loopwire-bin.nix "loopwire-linux-aarch64.tar.gz"
require_contains packaging/nix/loopwire-bin.nix "github.com/sandwichfarm/loopwire"
require_contains packaging/nix/loopwire-bin.nix "install -Dm755 loopwire"
require_contains packaging/nix/loopwire-bin.nix "install -Dm755 loopwire-dsp-provider"
require_contains packaging/nix/loopwire-bin.nix "install -Dm755 loopwire-jack-ports"
require_contains packaging/nix/loopwire-bin.nix 'wrapProgram "$out/bin/loopwire-dsp-provider"'
require_contains packaging/nix/loopwire-bin.nix 'wrapProgram "$out/bin/loopwire-jack-ports"'
require_contains packaging/nix/loopwire-bin.nix "nodejs"
require_contains packaging/nix/loopwire-bin.nix '$out/lib/loopwire'
require_contains flake.nix "packages = forEachSystem"
require_contains flake.nix "loopwire-bin = loopwireBin"
require_contains flake.nix "default = loopwireBin"
require_contains flake.nix "pkgs.callPackage ./packaging/nix/loopwire-bin.nix"
require_contains flake.nix "nixpkgs.lib.fakeHash"
require_contains flake.nix "mkLoopwireBinPackage"
require_contains package.json '"nix:render-release": "bash scripts/render-nix-release-package.sh"'
require_contains scripts/render-nix-release-package.sh "loopwire-linux-x86_64.tar.gz"
require_contains scripts/render-nix-release-package.sh "loopwire-linux-aarch64.tar.gz"
require_contains scripts/render-nix-release-package.sh "verify-release-asset-checksum.sh"
require_contains packaging/README.md "same release artifacts"
require_contains packaging/README.md "loopwire-dsp-provider"
require_contains packaging/README.md "loopwire-jack-ports"

bash scripts/install.sh --dry-run >/dev/null
bash scripts/vm-matrix.sh validate >/dev/null

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

release_dir="$tmp_dir/release"
mkdir -p "$release_dir"
printf '%s\n' "x86 release artifact" >"$release_dir/loopwire-linux-x86_64.tar.gz"
printf '%s\n' "aarch64 release artifact" >"$release_dir/loopwire-linux-aarch64.tar.gz"
(
  cd "$release_dir"
  sha256sum loopwire-linux-x86_64.tar.gz loopwire-linux-aarch64.tar.gz >SHA256SUMS
)

nix_render="$tmp_dir/loopwire-release.nix"
bash scripts/render-nix-release-package.sh \
  --version 0.1.0 \
  --release-dir "$release_dir" \
  --output "$nix_render" >/dev/null
require_contains "$nix_render" 'version = "0.1.0";'
require_contains "$nix_render" 'x86_64-linux = "sha256-'
require_contains "$nix_render" 'aarch64-linux = "sha256-'
require_contains "$nix_render" 'packaging/nix/loopwire-bin.nix'
if grep -Fq "fakeHash" "$nix_render"; then
  echo "Rendered Nix release package must not contain fakeHash" >&2
  exit 1
fi

duplicate_release_dir="$tmp_dir/duplicate-release"
cp -R "$release_dir" "$duplicate_release_dir"
grep -F "loopwire-linux-x86_64.tar.gz" "$release_dir/SHA256SUMS" >>"$duplicate_release_dir/SHA256SUMS"
if bash scripts/render-nix-release-package.sh \
  --version 0.1.0 \
  --release-dir "$duplicate_release_dir" \
  --output "$tmp_dir/duplicate.nix" >/dev/null 2>&1; then
  echo "Nix release renderer accepted duplicate checksum entries" >&2
  exit 1
fi

echo "Packaging metadata smoke passed."
