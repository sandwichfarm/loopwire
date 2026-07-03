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
work_dir="$tmp_dir/aur"
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
  --version "0.0.0-smoke" \
  --arch x86_64 \
  --output-dir "$release_dir" >/dev/null

bash scripts/package-release.sh \
  --binary "$binary" \
  --version "0.0.0-smoke" \
  --arch aarch64 \
  --output-dir "$release_dir" >/dev/null

mkdir -p "$work_dir"
bash scripts/render-aur-pkgbuild.sh \
  --version "0.0.0_smoke" \
  --release-dir "$release_dir" \
  --output "$work_dir/PKGBUILD" >/dev/null

(
  cd "$work_dir"
  makepkg --force --nodeps --noconfirm --cleanbuild --clean >/dev/null
)

package_file="$(find "$work_dir" -maxdepth 1 -type f -name 'loopwire-bin-*.pkg.tar.*' | head -n 1)"
if [ -z "$package_file" ]; then
  echo "makepkg did not produce a loopwire-bin package archive." >&2
  exit 1
fi

if ! tar -tf "$package_file" | grep -Eq '(^|/)usr/bin/loopwire$'; then
  echo "AUR package archive does not contain usr/bin/loopwire." >&2
  exit 1
fi
if ! tar -tf "$package_file" | grep -Eq '(^|/)usr/lib/loopwire/loopwire-gui$'; then
  echo "AUR package archive does not contain usr/lib/loopwire/loopwire-gui." >&2
  exit 1
fi
if ! tar -tf "$package_file" | grep -Eq '(^|/)usr/lib/loopwire/scripts/restore-background.mjs$'; then
  echo "AUR package archive does not contain bundled background restore runner." >&2
  exit 1
fi

echo "AUR local package smoke passed."
