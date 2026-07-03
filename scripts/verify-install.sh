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
      echo "Unsupported architecture for installer smoke: $(uname -m)" >&2
      exit 1
      ;;
  esac
}

arch="$(normalize_arch)"
asset="loopwire-linux-${arch}.tar.gz"
release_dir="$tmp_dir/release"
payload_dir="$tmp_dir/payload"
prefix="$tmp_dir/prefix"
private_key="$tmp_dir/release-private.pem"
public_key="$tmp_dir/release-public.pem"

mkdir -p "$release_dir" "$payload_dir/bin"

cat >"$payload_dir/bin/loopwire" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "loopwire installer smoke"
EOF
chmod 0755 "$payload_dir/bin/loopwire"

tar -C "$payload_dir/bin" -czf "$release_dir/$asset" loopwire
(
  cd "$release_dir"
  sha256sum "$asset" >SHA256SUMS
)

openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out "$private_key" >/dev/null 2>&1
openssl pkey -in "$private_key" -pubout -out "$public_key" >/dev/null
bash scripts/sign-release-artifacts.sh --release-dir "$release_dir" --private-key "$private_key" >/dev/null

bash scripts/install.sh --base-url "file://$release_dir" --prefix "$prefix" --public-key "$public_key"

if [ ! -x "$prefix/loopwire" ]; then
  echo "Installed Loopwire binary is missing or not executable." >&2
  exit 1
fi

if [ "$("$prefix/loopwire")" != "loopwire installer smoke" ]; then
  echo "Installed Loopwire binary did not run as expected." >&2
  exit 1
fi

bad_release="$tmp_dir/bad-release"
mkdir -p "$bad_release"
cp "$release_dir/$asset" "$bad_release/$asset"
cp "$release_dir/SHA256SUMS" "$bad_release/SHA256SUMS"
cp "$release_dir/SHA256SUMS.sig" "$bad_release/SHA256SUMS.sig"
printf '%s\n' "tamper" >>"$bad_release/$asset"

if bash scripts/install.sh --base-url "file://$bad_release" --prefix "$tmp_dir/bad-prefix" --public-key "$public_key" >/dev/null 2>&1; then
  echo "Installer accepted an artifact with a bad checksum." >&2
  exit 1
fi

echo "Installer local artifact smoke passed."
