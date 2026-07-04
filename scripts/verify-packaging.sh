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
require_contains packaging/aur/PKGBUILD.in "nodejs"
require_contains packaging/aur/PKGBUILD.in "usr/lib/loopwire"
require_contains packaging/nix/loopwire-bin.nix "loopwire-linux-x86_64.tar.gz"
require_contains packaging/nix/loopwire-bin.nix "loopwire-linux-aarch64.tar.gz"
require_contains packaging/nix/loopwire-bin.nix "github.com/sandwichfarm/loopwire"
require_contains packaging/nix/loopwire-bin.nix "install -Dm755 loopwire"
require_contains packaging/nix/loopwire-bin.nix "install -Dm755 loopwire-dsp-provider"
require_contains packaging/nix/loopwire-bin.nix 'wrapProgram "$out/bin/loopwire-dsp-provider"'
require_contains packaging/nix/loopwire-bin.nix "nodejs"
require_contains packaging/nix/loopwire-bin.nix '$out/lib/loopwire'
require_contains flake.nix "packages = forEachSystem"
require_contains flake.nix "loopwire-bin = loopwireBin"
require_contains flake.nix "default = loopwireBin"
require_contains flake.nix "pkgs.callPackage ./packaging/nix/loopwire-bin.nix"
require_contains flake.nix "nixpkgs.lib.fakeHash"
require_contains flake.nix "mkLoopwireBinPackage"
require_contains packaging/README.md "same release artifacts"
require_contains packaging/README.md "loopwire-dsp-provider"

bash scripts/install.sh --dry-run >/dev/null
bash scripts/vm-matrix.sh validate >/dev/null

echo "Packaging metadata smoke passed."
