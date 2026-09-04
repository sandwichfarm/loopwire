#!/usr/bin/env bash
set -euo pipefail

if ! command -v makepkg >/dev/null 2>&1; then
  echo "makepkg not found; skipping AUR package smoke on this host."
  exit 0
fi

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

release_dir="$tmp_dir/release"
work_dir="$tmp_dir/aur-bin"
source_work_dir="$tmp_dir/aur-source"
git_work_dir="$tmp_dir/aur-git"
binary="$tmp_dir/loopwire"

pnpm --filter @loopwire/core build >/dev/null
pnpm --filter @loopwire/audio-host build >/dev/null

cat >"$binary" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "loopwire aur package smoke"
EOF
chmod 0755 "$binary"

bash scripts/package-release.sh \
  --binary "$binary" \
  --version "0.0.0" \
  --arch x86_64 \
  --output-dir "$release_dir" >/dev/null

bash scripts/package-release.sh \
  --binary "$binary" \
  --version "0.0.0" \
  --arch aarch64 \
  --output-dir "$release_dir" >/dev/null

mkdir -p "$work_dir" "$source_work_dir" "$git_work_dir"
cp packaging/aur/LICENSE-MIT "$work_dir/LICENSE-MIT"
cp packaging/aur/LICENSE-MIT "$source_work_dir/LICENSE-MIT"
cp packaging/aur/LICENSE-MIT "$git_work_dir/LICENSE-MIT"
bash scripts/render-aur-pkgbuild.sh \
  --package loopwire-bin \
  --version "0.0.0" \
  --pkgrel 1 \
  --release-dir "$release_dir" \
  --output "$work_dir/PKGBUILD" >/dev/null

(
  cd "$work_dir"
  makepkg --force --nodeps --noconfirm --cleanbuild --clean >/dev/null
)

package_file="$(
  find "$work_dir" \
    -maxdepth 1 \
    -type f \
    -name 'loopwire-bin-*.pkg.tar.*' \
    ! -name 'loopwire-bin-debug-*' \
    | head -n 1
)"
if [ -z "$package_file" ]; then
  echo "makepkg did not produce a loopwire-bin package archive." >&2
  exit 1
fi

package_members="$work_dir/package-members.txt"
tar -tf "$package_file" >"$package_members"

require_package_member() {
  member="$1"

  if grep -Fxq "$member" "$package_members"; then
    return 0
  fi

  echo "AUR package archive does not contain $member." >&2
  exit 1
}

require_package_member "usr/bin/loopwire"
require_package_member "usr/bin/loopwire-dsp-provider"
require_package_member "usr/bin/loopwire-jack-ports"
require_package_member "usr/bin/loopwire-detect-audio"
require_package_member "usr/lib/loopwire/loopwire-gui"
require_package_member "usr/lib/loopwire/scripts/restore-background.mjs"

namcap_log="$tmp_dir/namcap-bin.log"
namcap "$work_dir/PKGBUILD" "$package_file" | tee "$namcap_log"
if grep -Fq " E: " "$namcap_log"; then
  echo "namcap reported an error for loopwire-bin." >&2
  exit 1
fi

source_archive="$tmp_dir/loopwire-0.0.0.tar.gz"
mkdir -p "$tmp_dir/loopwire-0.0.0"
tar -czf "$source_archive" -C "$tmp_dir" loopwire-0.0.0
cp "$source_archive" "$source_work_dir/loopwire-0.0.0.tar.gz"
bash scripts/render-aur-pkgbuild.sh \
  --package loopwire \
  --version "0.0.0" \
  --pkgrel 1 \
  --source-archive "$source_archive" \
  --output "$source_work_dir/PKGBUILD" >/dev/null
(
  cd "$source_work_dir"
  makepkg --printsrcinfo >.SRCINFO
)
grep -Fqx "pkgbase = loopwire" "$source_work_dir/.SRCINFO"
grep -Fqx $'\tconflicts = loopwire-bin' "$source_work_dir/.SRCINFO"
grep -Fqx $'\tmakedepends = pnpm' "$source_work_dir/.SRCINFO"
grep -Fqx $'\tmakedepends = rust' "$source_work_dir/.SRCINFO"
namcap "$source_work_dir/PKGBUILD" | tee "$tmp_dir/namcap-source-metadata.log"
if grep -Fq " E: " "$tmp_dir/namcap-source-metadata.log"; then
  echo "namcap reported an error for the loopwire source PKGBUILD." >&2
  exit 1
fi

bash scripts/render-aur-pkgbuild.sh \
  --package loopwire-git \
  --version "0.1.0.r1.gabcdef0" \
  --default-branch master \
  --pkgrel 1 \
  --output "$git_work_dir/PKGBUILD" >/dev/null
(
  cd "$git_work_dir"
  makepkg --printsrcinfo >.SRCINFO
)
grep -Fqx "pkgbase = loopwire-git" "$git_work_dir/.SRCINFO"
grep -Fqx $'\tprovides = loopwire=0.1.0.r1.gabcdef0' "$git_work_dir/.SRCINFO"
grep -Fqx $'\tconflicts = loopwire' "$git_work_dir/.SRCINFO"
grep -Fqx $'\tmakedepends = git' "$git_work_dir/.SRCINFO"
if grep -Fq $'\treplaces = ' "$git_work_dir/.SRCINFO"; then
  echo "loopwire-git must not declare replaces." >&2
  exit 1
fi

echo "AUR binary build plus stable/VCS source metadata smokes passed."
