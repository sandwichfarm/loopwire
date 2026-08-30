#!/usr/bin/env bash
set -euo pipefail

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

normalize_arch() {
  case "$(uname -m)" in
    x86_64 | amd64)
      printf '%s\n' "x86_64"
      ;;
    aarch64 | arm64)
      printf '%s\n' "aarch64"
      ;;
    *)
      echo "Unsupported architecture for release smoke: $(uname -m)" >&2
      exit 1
      ;;
  esac
}

current_arch="$(normalize_arch)"
if [ "$current_arch" = "x86_64" ]; then
  secondary_arch="aarch64"
else
  secondary_arch="x86_64"
fi

binary="$tmp_dir/loopwire"
release_dir="$tmp_dir/release"
staged_dir="$tmp_dir/staged-release"
appimage_only_dir="$tmp_dir/appimage-only-release"
manifest_dir="$tmp_dir/manifest-release"
bundle_dir="$tmp_dir/bundles"
prefix="$tmp_dir/prefix"
private_key="$tmp_dir/release-private.pem"
public_key="$tmp_dir/release-public.pem"
provider_store="$tmp_dir/provider-store"
jack_manifest="$tmp_dir/jack-ports-provision.json"
installed_jack_manifest="$tmp_dir/installed-jack-ports-provision.json"

pnpm --filter @loopwire/core build >/dev/null
pnpm --filter @loopwire/audio-host build >/dev/null

cat >"$binary" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "loopwire release smoke"
EOF
chmod 0755 "$binary"

openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out "$private_key" >/dev/null 2>&1
openssl pkey -in "$private_key" -pubout -out "$public_key" >/dev/null

bash scripts/package-release.sh \
  --binary "$binary" \
  --version "0.0.0-smoke" \
  --arch "$current_arch" \
  --output-dir "$release_dir"

asset="loopwire-linux-${current_arch}.tar.gz"
first_hash="$(sha256sum "$release_dir/$asset" | awk '{ print $1 }')"

bash scripts/package-release.sh \
  --binary "$binary" \
  --version "0.0.0-smoke" \
  --arch "$current_arch" \
  --output-dir "$release_dir" >/dev/null

second_hash="$(sha256sum "$release_dir/$asset" | awk '{ print $1 }')"
if [ "$first_hash" != "$second_hash" ]; then
  echo "Release artifact is not reproducible for identical input." >&2
  exit 1
fi

if [ "$(grep -c "  ${asset}$" "$release_dir/SHA256SUMS")" -ne 1 ]; then
  echo "SHA256SUMS contains duplicate or missing entries for ${asset}." >&2
  exit 1
fi

bash scripts/package-release.sh \
  --binary "$binary" \
  --version "0.0.0-smoke" \
  --arch "$secondary_arch" \
  --output-dir "$release_dir" >/dev/null

if ! grep -q "  loopwire-linux-${secondary_arch}.tar.gz$" "$release_dir/SHA256SUMS"; then
  echo "SHA256SUMS missing secondary architecture artifact." >&2
  exit 1
fi

(
  cd "$release_dir"
  sha256sum --check SHA256SUMS
) >/dev/null

bash scripts/sign-release-artifacts.sh --release-dir "$release_dir" --private-key "$private_key" >/dev/null
bash scripts/verify-release-signature.sh --release-dir "$release_dir" --public-key "$public_key" >/dev/null

check_dir="$tmp_dir/check"
mkdir -p "$check_dir"
tar -xzf "$release_dir/$asset" -C "$check_dir"

if [ "$("$check_dir/loopwire")" != "loopwire release smoke" ]; then
  echo "Packaged Loopwire binary did not run as expected." >&2
  exit 1
fi
if [ ! -x "$check_dir/loopwire-dsp-provider" ]; then
  echo "Packaged Loopwire artifact is missing loopwire-dsp-provider." >&2
  exit 1
fi
if [ ! -x "$check_dir/loopwire-jack-ports" ]; then
  echo "Packaged Loopwire artifact is missing loopwire-jack-ports." >&2
  exit 1
fi
if [ ! -x "$check_dir/loopwire-detect-audio" ]; then
  echo "Packaged Loopwire artifact is missing loopwire-detect-audio." >&2
  exit 1
fi
if [ ! -x "$check_dir/libexec/loopwire/loopwire-gui" ]; then
  echo "Packaged Loopwire artifact is missing libexec/loopwire/loopwire-gui." >&2
  exit 1
fi
if [ ! -f "$check_dir/libexec/loopwire/scripts/restore-background.mjs" ]; then
  echo "Packaged Loopwire artifact is missing the background restore runner." >&2
  exit 1
fi
grep -Fq '"type":"module"' "$check_dir/libexec/loopwire/package.json" || {
  echo "Packaged Loopwire artifact is missing the ES module runtime marker." >&2
  exit 1
}
"$check_dir/loopwire" --background --help | grep -F -- "--state-file" >/dev/null || {
  echo "Packaged Loopwire background restore help did not run." >&2
  exit 1
}
"$check_dir/loopwire-dsp-provider" --help | grep -F -- "seed-source" >/dev/null || {
  echo "Packaged Loopwire DSP provider help did not run." >&2
  exit 1
}
"$check_dir/loopwire-dsp-provider" capabilities | grep -F -- '"supportsLiveGraph":false' >/dev/null || {
  echo "Packaged Loopwire DSP provider did not declare file-backed capabilities." >&2
  exit 1
}
"$check_dir/loopwire-jack-ports" --help | grep -F -- "LOOPWIRE_JACK_PORTS_DELEGATE" >/dev/null || {
  echo "Packaged Loopwire JACK ports provider help did not run." >&2
  exit 1
}
"$check_dir/loopwire-detect-audio" --pretty | node -e '
  let input = "";
  process.stdin.on("data", (chunk) => input += chunk);
  process.stdin.on("end", () => {
    const value = JSON.parse(input);
    if (!value || typeof value !== "object") process.exit(1);
  });
' || {
  echo "Packaged Loopwire backend detector did not return JSON." >&2
  exit 1
}
if "$check_dir/loopwire-jack-ports" \
  ensure \
  --configuration-id smoke \
  --requirement route-source:loopwire-owned:mic:loopwire_smoke_input_mic:1 \
  --port loopwire_smoke_input_mic:capture_1 \
  --manifest-file "$jack_manifest" >/dev/null 2>&1; then
  echo "Packaged Loopwire JACK ports provider did not fail closed without a delegate." >&2
  exit 1
fi
grep -F '"configurationId": "smoke"' "$jack_manifest" >/dev/null || {
  echo "Packaged Loopwire JACK ports provider did not record a provision manifest." >&2
  exit 1
}
"$check_dir/loopwire-dsp-provider" \
  seed-source \
  --source-id mic \
  --channels 2 \
  --frames 2 \
  --store-dir "$provider_store" >/dev/null
"$check_dir/loopwire-dsp-provider" \
  read-source \
  --source-id mic \
  --channels 2 \
  --frames 2 \
  --store-dir "$provider_store" | grep -F -- '"channels"' >/dev/null || {
  echo "Packaged Loopwire DSP provider source read failed." >&2
  exit 1
}

bash scripts/install.sh --base-url "file://$release_dir" --prefix "$prefix" --public-key "$public_key" >/dev/null

if [ "$("$prefix/loopwire")" != "loopwire release smoke" ]; then
  echo "Installer did not install the generated release artifact correctly." >&2
  exit 1
fi
if [ ! -x "$prefix/loopwire-dsp-provider" ]; then
  echo "Installer did not install loopwire-dsp-provider." >&2
  exit 1
fi
if [ ! -x "$prefix/loopwire-jack-ports" ]; then
  echo "Installer did not install loopwire-jack-ports." >&2
  exit 1
fi
if [ ! -x "$prefix/loopwire-detect-audio" ]; then
  echo "Installer did not install loopwire-detect-audio." >&2
  exit 1
fi
if [ ! -x "$(dirname "$prefix")/lib/loopwire/loopwire-gui" ]; then
  echo "Installer did not install libexec GUI support files." >&2
  exit 1
fi
"$prefix/loopwire" --background --help | grep -F -- "--state-file" >/dev/null || {
  echo "Installed Loopwire background restore help did not run." >&2
  exit 1
}
"$prefix/loopwire-dsp-provider" --help | grep -F -- "seed-source" >/dev/null || {
  echo "Installed Loopwire DSP provider help did not run." >&2
  exit 1
}
"$prefix/loopwire-dsp-provider" capabilities | grep -F -- '"supportsLiveGraph":false' >/dev/null || {
  echo "Installed Loopwire DSP provider did not declare file-backed capabilities." >&2
  exit 1
}
"$prefix/loopwire-jack-ports" --help | grep -F -- "LOOPWIRE_JACK_PORTS_DELEGATE" >/dev/null || {
  echo "Installed Loopwire JACK ports provider help did not run." >&2
  exit 1
}
"$prefix/loopwire-detect-audio" --pretty | node -e '
  let input = "";
  process.stdin.on("data", (chunk) => input += chunk);
  process.stdin.on("end", () => JSON.parse(input));
' || {
  echo "Installed Loopwire backend detector did not return JSON." >&2
  exit 1
}
if "$prefix/loopwire-jack-ports" \
  ensure \
  --configuration-id installed-smoke \
  --requirement route-source:loopwire-owned:mic:loopwire_installed_input_mic:1 \
  --port loopwire_installed_input_mic:capture_1 \
  --manifest-file "$installed_jack_manifest" >/dev/null 2>&1; then
  echo "Installed Loopwire JACK ports provider did not fail closed without a delegate." >&2
  exit 1
fi
grep -F '"configurationId": "installed-smoke"' "$installed_jack_manifest" >/dev/null || {
  echo "Installed Loopwire JACK ports provider did not record a provision manifest." >&2
  exit 1
}
"$prefix/loopwire-dsp-provider" \
  seed-source \
  --source-id browser \
  --channels 2 \
  --frames 2 \
  --store-dir "$provider_store" >/dev/null
"$prefix/loopwire-dsp-provider" \
  read-source \
  --source-id browser \
  --channels 2 \
  --frames 2 \
  --store-dir "$provider_store" | grep -F -- '"channels"' >/dev/null || {
  echo "Installed Loopwire DSP provider source read failed." >&2
  exit 1
}

mkdir -p "$bundle_dir/appimage" "$bundle_dir/deb" "$bundle_dir/rpm"
printf '%s\n' "fake appimage" >"$bundle_dir/appimage/Loopwire_0.0.0_amd64.AppImage"
printf '%s\n' "fake arm appimage" >"$bundle_dir/appimage/Loopwire_0.1.0_aarch64.AppImage"
printf '%s\n' "fake deb" >"$bundle_dir/deb/Loopwire_0.0.0_amd64.deb"
printf '%s\n' "fake rpm" >"$bundle_dir/rpm/Loopwire-0.0.0-1.x86_64.rpm"

mkdir -p "$appimage_only_dir"
printf '%s\n' "stale signature" >"$appimage_only_dir/SHA256SUMS.sig"
bash scripts/stage-release-artifacts.sh \
  --binary "$binary" \
  --version "0.0.0-smoke" \
  --arch "$current_arch" \
  --bundle-dir "$bundle_dir" \
  --private-key "$private_key" \
  --output-dir "$staged_dir" >/dev/null

for staged_file in \
  "loopwire-linux-${current_arch}.tar.gz" \
  "Loopwire_0.0.0_amd64.AppImage" \
  "Loopwire_0.0.0_amd64.deb" \
  "Loopwire-0.0.0-1.x86_64.rpm"; do
  if [ ! -f "$staged_dir/$staged_file" ]; then
    echo "Staged release is missing $staged_file." >&2
    exit 1
  fi
done

(
  cd "$staged_dir"
  sha256sum --check SHA256SUMS
) >/dev/null

bash scripts/verify-release-signature.sh --release-dir "$staged_dir" --public-key "$public_key" >/dev/null

bash scripts/stage-release-artifacts.sh \
  --binary "$binary" \
  --version "0.1.0" \
  --arch aarch64 \
  --bundle-dir "$bundle_dir" \
  --appimage-only \
  --output-dir "$appimage_only_dir" >/dev/null

for staged_file in loopwire-linux-aarch64.tar.gz Loopwire_0.1.0_aarch64.AppImage SHA256SUMS; do
  [ -f "$appimage_only_dir/$staged_file" ] || {
    echo "AppImage-only staging is missing $staged_file." >&2
    exit 1
  }
done
if find "$appimage_only_dir" -maxdepth 1 -type f \( -name '*.deb' -o -name '*.rpm' \) | grep -q .; then
  echo "AppImage-only staging included an unverified native package." >&2
  exit 1
fi
if [ -e "$appimage_only_dir/SHA256SUMS.sig" ]; then
  echo "Unsigned staging preserved a stale checksum signature." >&2
  exit 1
fi

mkdir -p "$manifest_dir"
cp "$release_dir/loopwire-linux-x86_64.tar.gz" "$manifest_dir/"
cp "$release_dir/loopwire-linux-aarch64.tar.gz" "$manifest_dir/"
printf '%s\n' "x86 AppImage" >"$manifest_dir/Loopwire_0.1.0_amd64.AppImage"
printf '%s\n' "arm AppImage" >"$manifest_dir/Loopwire_0.1.0_aarch64.AppImage"
printf '%s\n' "Ubuntu deb" >"$manifest_dir/loopwire_0.1.0-1ubuntu24.04_amd64.deb"
printf '%s\n' "Debian deb" >"$manifest_dir/loopwire_0.1.0-1debian13_amd64.deb"
printf '%s\n' "Fedora rpm" >"$manifest_dir/loopwire-0.1.0-1.fc44.x86_64.rpm"
printf '%s\n' "openSUSE rpm" >"$manifest_dir/loopwire-0.1.0-1.x86_64.rpm"
manifest_head="0123456789abcdef0123456789abcdef01234567"
node scripts/release-asset-manifest.mjs write \
  --release-dir "$manifest_dir" --tag v0.1.0 --git-head "$manifest_head" >/dev/null
(
  cd "$manifest_dir"
  find . -maxdepth 1 -type f ! -name SHA256SUMS ! -name SHA256SUMS.sig -printf '%f\n' |
    sort | xargs sha256sum >SHA256SUMS
)
node scripts/release-asset-manifest.mjs verify \
  --release-dir "$manifest_dir" --tag v0.1.0 --git-head "$manifest_head" --require-checksum >/dev/null

printf '%s\n' "tampered" >>"$manifest_dir/Loopwire_0.1.0_amd64.AppImage"
if node scripts/release-asset-manifest.mjs verify \
  --release-dir "$manifest_dir" --tag v0.1.0 --git-head "$manifest_head" >/dev/null 2>&1; then
  echo "Release asset manifest accepted a tampered payload." >&2
  exit 1
fi
printf '%s\n' "x86 AppImage" >"$manifest_dir/Loopwire_0.1.0_amd64.AppImage"

rm "$manifest_dir/Loopwire_0.1.0_aarch64.AppImage"
if node scripts/release-asset-manifest.mjs write \
  --release-dir "$manifest_dir" --tag v0.1.0 --git-head "$manifest_head" >/dev/null 2>&1; then
  echo "Release asset manifest accepted a missing required payload." >&2
  exit 1
fi
printf '%s\n' "arm AppImage" >"$manifest_dir/Loopwire_0.1.0_aarch64.AppImage"

mv "$manifest_dir/loopwire_0.1.0-1debian13_amd64.deb" \
  "$tmp_dir/debian-package.real"
ln -s ../debian-package.real \
  "$manifest_dir/loopwire_0.1.0-1debian13_amd64.deb"
if node scripts/release-asset-manifest.mjs write \
  --release-dir "$manifest_dir" --tag v0.1.0 --git-head "$manifest_head" >/dev/null 2>&1; then
  echo "Release asset manifest accepted a linked payload." >&2
  exit 1
fi
rm "$manifest_dir/loopwire_0.1.0-1debian13_amd64.deb"
mv "$tmp_dir/debian-package.real" "$manifest_dir/loopwire_0.1.0-1debian13_amd64.deb"

printf '%s\n' "wrong version" >"$manifest_dir/Loopwire_0.0.0_amd64.AppImage"
if node scripts/release-asset-manifest.mjs write \
  --release-dir "$manifest_dir" --tag v0.1.0 --git-head "$manifest_head" >/dev/null 2>&1; then
  echo "Release asset manifest accepted an unrecognized or mis-versioned artifact." >&2
  exit 1
fi
rm "$manifest_dir/Loopwire_0.0.0_amd64.AppImage"

printf '%s\n' "release evidence" >"$manifest_dir/loopwire-release-evidence-v0.1.0.tar.gz"
node scripts/release-asset-manifest.mjs write \
  --release-dir "$manifest_dir" --tag v0.1.0 --git-head "$manifest_head" >/dev/null
(
  cd "$manifest_dir"
  find . -maxdepth 1 -type f ! -name SHA256SUMS ! -name SHA256SUMS.sig -printf '%f\n' |
    sort | xargs sha256sum >SHA256SUMS
)
node scripts/release-asset-manifest.mjs verify \
  --release-dir "$manifest_dir" --tag v0.1.0 --git-head "$manifest_head" \
  --require-checksum --require-evidence >/dev/null
bash scripts/sign-release-artifacts.sh --release-dir "$manifest_dir" --private-key "$private_key" >/dev/null
bash scripts/verify-release-signature.sh --release-dir "$manifest_dir" --public-key "$public_key" >/dev/null

echo "Release artifact smoke passed."
