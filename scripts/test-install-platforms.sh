#!/usr/bin/env bash
set -euo pipefail

# All host and package-manager interaction is stubbed; no installed packages change.
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
cleanup() {
  local status=$?
  if [ "$status" != 0 ] && [ -f "$work/log" ]; then cat "$work/log" >&2; fi
  rm -rf "$work"
}
trap cleanup EXIT
real_curl="$(command -v curl)"
real_mv="$(command -v mv)"
real_rm="$(command -v rm)"
mkdir -p "$work/tools" "$work/release" "$work/payload/libexec/loopwire" "$work/home"
for tool in bash cat chmod cmp cp dirname find grep gzip head install ln mkdir mktemp mv openssl rm rmdir setsid sha256sum tar touch awk; do
  ln -s "$(command -v "$tool")" "$work/tools/$tool"
done
export FIXTURE_ROOT="$work" REAL_CURL="$real_curl" REAL_MV="$real_mv" REAL_RM="$real_rm"
export PATH="$work/tools" HOME="$work/home" LOOPWIRE_OS_RELEASE_FILE="$work/os-release"
unset PREFIX LOOPWIRE_BASE_URL LOOPWIRE_RELEASE_PUBLIC_KEY_FILE LOOPWIRE_SKIP_SIGNATURE LOOPWIRE_VERSION LOOPWIRE_REPO
export FIXTURE_ARCH=x86_64 FIXTURE_SYSTEM=Linux

cat >"$work/tools/uname" <<'EOF'
#!/bin/bash
case "$1" in -s) echo "$FIXTURE_SYSTEM";; -m) echo "$FIXTURE_ARCH";; esac
EOF
cat >"$work/tools/curl" <<'EOF'
#!/bin/bash
args=()
for arg in "$@"; do
  case "$arg" in https://github.com/*/download/*) arg="file://$FIXTURE_ROOT/release/${arg##*/}";; esac
  args+=("$arg")
done
exec "$REAL_CURL" "${args[@]}"
EOF
cat >"$work/tools/id" <<'EOF'
#!/bin/bash
echo 1000
EOF
cat >"$work/tools/sudo" <<'EOF'
#!/bin/bash
printf '%s\n' "sudo $*" >>"$FIXTURE_ROOT/commands"
[ "${1:-}" != -n ] || shift
exec "$@"
EOF
cat >"$work/tools/manager" <<'EOF'
#!/bin/bash
printf '%s\n' "${0##*/} $*" >>"$FIXTURE_ROOT/commands"
if IFS= read -r unexpected_input; then
  printf 'Package manager consumed installer stdin: %s\n' "$unexpected_input" >&2
  exit 77
fi
exit "${FIXTURE_MANAGER_STATUS:-0}"
EOF
for manager in apt-get dnf zypper yay paru; do cp "$work/tools/manager" "$work/tools/$manager"; done
find "$work/tools" -type f -exec chmod +x {} +
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$work/private.pem" >/dev/null 2>&1
openssl pkey -in "$work/private.pem" -pubout -out "$work/public.pem" >/dev/null 2>&1

fail() { echo "Installer regression failed: $*" >&2; cat "$work/log" >&2; exit 1; }
contains() { grep -F -- "$1" "$work/log" >/dev/null || fail "missing diagnostic: $1"; }
command_contains() { grep -F -- "$1" "$work/commands" >/dev/null || fail "missing command: $1"; }
os() { printf 'ID=%s\nVERSION_ID="%s"\n' "$1" "$2" >"$work/os-release"; : >"$work/commands"; }
run() { bash "$root/scripts/install.sh" --public-key "$work/public.pem" "$@" >"$work/log" 2>&1; }
reject() { if run "$@"; then fail "unexpected success: $*"; fi; }
sign() {
  (cd "$work/release" && sha256sum loopwire* >SHA256SUMS)
  openssl dgst -sha256 -sign "$work/private.pem" -out "$work/release/SHA256SUMS.sig" "$work/release/SHA256SUMS"
}
payload() {
  printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$1" >"$work/payload/loopwire"
  chmod +x "$work/payload/loopwire"
  for arch in x86_64 aarch64; do tar -C "$work/payload" -czf "$work/release/loopwire-linux-$arch.tar.gz" .; done
  sign
}
for asset in loopwire_9.8.7-1debian13_amd64.deb loopwire_9.8.7-1ubuntu24.04_amd64.deb \
  loopwire-9.8.7-1.fc44.x86_64.rpm loopwire-9.8.7-1.x86_64.rpm; do
  printf 'fixture package\n' >"$work/release/$asset"
done
printf 'obsolete\n' >"$work/payload/libexec/loopwire/obsolete.js"
cp "$work/tools/manager" "$work/payload/loopwire-dsp-provider"
payload old

# Existing curl installs must remain the upgraded executable when Auto gains a
# native package/helper option. A second installation could be hidden on PATH.
for migration_distro in debian arch; do
  migration_home="$work/migration-$migration_distro"
  os ubuntu 26.04
  HOME="$migration_home" run --method portable
  [ "$("$migration_home/.local/bin/loopwire")" = old ] || fail 'legacy portable setup failed'
  payload upgraded
  if [ "$migration_distro" = debian ]; then os debian 13; requested_method=native
  else os arch rolling; requested_method=aur; fi
  HOME="$migration_home" run --yes
  [ "$("$migration_home/.local/bin/loopwire")" = upgraded ] || fail "Auto on $migration_distro left the previous portable version active"
  [ ! -s "$work/commands" ] || fail "Auto on $migration_distro created a competing package installation"
  contains 'Upgrading existing portable installation'
  HOME="$migration_home" reject --method "$requested_method" --yes
  contains 'Use --method portable to upgrade it'
  [ ! -s "$work/commands" ] || fail 'explicit package method ignored the portable installation conflict'
  payload old
done

os debian 13
run --yes || fail 'automatic Debian installation failed'
command_contains 'apt-get install -y'
command_contains 'loopwire_9.8.7-1debian13_amd64.deb'
contains '[1/'
contains 'Signature verified'
[ ! -e "$HOME/.local/bin/loopwire" ] || fail 'native route installed a portable binary'
cat "$root/scripts/install.sh" | bash -s -- --public-key "$work/public.pem" --yes >"$work/log" 2>&1
contains '[7/7] Installation complete'
os ubuntu 24.04; run --yes; command_contains 'loopwire_9.8.7-1ubuntu24.04_amd64.deb'
os fedora 44; run --yes; command_contains 'dnf install -y --setopt=localpkg_gpgcheck=0'; command_contains 'loopwire-9.8.7-1.fc44.x86_64.rpm'
os opensuse-tumbleweed 20260901; run --yes
command_contains 'zypper --non-interactive install --allow-unsigned-rpm'
command_contains 'loopwire-9.8.7-1.x86_64.rpm'
os ubuntu 26.04; run --yes; contains 'portable'; [ ! -s "$work/commands" ] || fail 'unsupported Ubuntu used a native manager'
[ "$("$HOME/.local/bin/loopwire")" = old ] || fail 'portable install failed'
run; [ "$("$HOME/.local/bin/loopwire")" = old ] || fail 'repeat install failed'
rm "$work/payload/libexec/loopwire/obsolete.js" "$work/payload/loopwire-dsp-provider"
printf 'new support\n' >"$work/payload/libexec/loopwire/current.js"
payload new
run
[ "$("$HOME/.local/bin/loopwire")" = new ] || fail 'upgrade failed'
[ ! -e "$HOME/.local/lib/loopwire/obsolete.js" ] || fail 'upgrade retained obsolete support file'
[ ! -e "$HOME/.local/bin/loopwire-dsp-provider" ] || fail 'upgrade retained obsolete command'

# A failure after support replacement and command backup must restore both.
rm "$work/tools/mv"
cat >"$work/tools/mv" <<'EOF'
#!/bin/bash
source_path="${2:-}"
source_parent="${source_path%/*}"
if [ "${FIXTURE_FAIL_MOVE:-false}" = true ] && [[ "${source_parent##*/}" = .loopwire-stage.* ]] &&
  [ "${source_path##*/}" = loopwire ] && [ ! -e "$FIXTURE_ROOT/move-failed" ]; then
  touch "$FIXTURE_ROOT/move-failed"
  exit 55
fi
if [ "${FIXTURE_FAIL_ROLLBACK:-false}" = true ]; then
  case "$source_path" in */backup/loopwire | */.loopwire-stage.*/backup) exit 56 ;; esac
fi
case "${FIXTURE_SIGNAL_BACKUP:-}:${3:-}" in
  lib:*/.loopwire-stage.*/backup | command:*/backup/loopwire)
    "$REAL_MV" "$@" || exit "$?"
    kill -TERM "$PPID"
    exit 0
    ;;
esac
exec "$REAL_MV" "$@"
EOF
chmod +x "$work/tools/mv"
printf 'different support\n' >"$work/payload/libexec/loopwire/current.js"
payload next
FIXTURE_FAIL_MOVE=true reject --method portable
contains 'Restoring previous portable installation'
[ "$("$HOME/.local/bin/loopwire")" = new ] || fail 'failed replacement lost old executable'
[ "$(cat "$HOME/.local/lib/loopwire/current.js")" = 'new support' ] || fail 'failed replacement lost old support files'

# If recovery also fails, the only remaining old files must survive cleanup.
mkdir -p "$work/recovery/bin" "$work/recovery/lib"
cp "$HOME/.local/bin/loopwire" "$work/recovery/bin/loopwire"
cp -R "$HOME/.local/lib/loopwire" "$work/recovery/lib/loopwire"
rm "$work/move-failed"
FIXTURE_FAIL_MOVE=true FIXTURE_FAIL_ROLLBACK=true reject --prefix "$work/recovery/bin"
command_backup="$(find "$work/recovery/bin" -path '*/backup/loopwire' -type f)"
support_backup="$(find "$work/recovery/lib" -path '*/backup/current.js' -type f)"
[ -n "$command_backup" ] && [ -n "$support_backup" ] || fail 'failed rollback deleted recoverable backups'
[ "$("$command_backup")" = new ] || fail 'retained command backup changed'
[ "$(cat "$support_backup")" = 'new support' ] || fail 'retained support backup changed'
contains "${command_backup%/*}"
contains "${support_backup%/*}"
contains 'Rollback incomplete'
[ -d "$work/recovery/bin/.loopwire-install.lock" ] || fail 'incomplete rollback must block another automatic overwrite'

# Signals immediately after successful backup moves precede shell flag updates.
for interrupted_target in lib command; do
  recovery_root="$work/signal-$interrupted_target"
  mkdir -p "$recovery_root/bin" "$recovery_root/lib"
  cp "$HOME/.local/bin/loopwire" "$recovery_root/bin/loopwire"
  cp -R "$HOME/.local/lib/loopwire" "$recovery_root/lib/loopwire"
  FIXTURE_SIGNAL_BACKUP="$interrupted_target" reject --prefix "$recovery_root/bin"
  contains 'Restoring previous portable installation'
  [ "$("$recovery_root/bin/loopwire")" = new ] || fail "signal after $interrupted_target backup lost old command"
  [ "$(cat "$recovery_root/lib/loopwire/current.js")" = 'new support' ] || fail "signal after $interrupted_target backup lost old support"
  [ ! -e "$recovery_root/bin/.loopwire-install.lock" ] || fail 'successful signal recovery retained a lock'
done

# Failure to delete the failed new support tree must also preserve the old tree.
rm "$work/tools/rm"
cat >"$work/tools/rm" <<'EOF'
#!/bin/bash
if [ -n "${FIXTURE_FAIL_REMOVE_TARGET:-}" ] && [ "${!#}" = "$FIXTURE_FAIL_REMOVE_TARGET" ]; then exit 57; fi
if [ "${FIXTURE_FAIL_TMP_CLEANUP:-false}" = true ] && [[ "${!#}" = /tmp/tmp.* ]] && [ -f "${!#}/SHA256SUMS" ]; then exit 58; fi
exec "$REAL_RM" "$@"
EOF
chmod +x "$work/tools/rm"
recovery_root="$work/remove-failure"
mkdir -p "$recovery_root/bin" "$recovery_root/lib"
cp "$HOME/.local/bin/loopwire" "$recovery_root/bin/loopwire"
cp -R "$HOME/.local/lib/loopwire" "$recovery_root/lib/loopwire"
rm "$work/move-failed"
FIXTURE_FAIL_MOVE=true FIXTURE_FAIL_REMOVE_TARGET="$recovery_root/lib/loopwire" FIXTURE_FAIL_TMP_CLEANUP=true \
  reject --prefix "$recovery_root/bin"
contains 'Rollback incomplete'
contains 'Could not remove temporary downloads:'
support_backup="$(find "$recovery_root/lib" -path '*/backup/current.js' -type f)"
[ -n "$support_backup" ] && [ "$(cat "$support_backup")" = 'new support' ] || fail 'cleanup error deleted recovery support files'
[ "$("$recovery_root/bin/loopwire")" = new ] || fail 'support rollback failure damaged recovered command'
# This failure was deliberate; remove the exact download temp folder reported by the installer.
download_leftover="$(awk '/^Could not remove temporary downloads: / { sub(/^Could not remove temporary downloads: /, ""); print }' "$work/log")"
[ -z "$download_leftover" ] || rm -rf "$download_leftover"
payload new

os debian 13
run --prefix "$work/custom/bin"
[ -x "$work/custom/bin/loopwire" ] || fail '--prefix did not preserve portable mode'
[ ! -s "$work/commands" ] || fail '--prefix ran manager'
PREFIX="$work/env/bin" run; [ -x "$work/env/bin/loopwire" ] || fail 'PREFIX did not preserve portable mode'
run --base-url "file://$work/release"; [ ! -s "$work/commands" ] || fail '--base-url ran manager'
run --method portable; [ ! -s "$work/commands" ] || fail '--method portable ran manager'
reject --method native --prefix "$work/custom/bin"; contains '--prefix/PREFIX applies only'
run --dry-run; contains 'Dry run'; [ ! -s "$work/commands" ] || fail 'dry-run ran manager'
FIXTURE_ARCH=aarch64 run --yes; contains 'loopwire-linux-aarch64.tar.gz'; [ ! -s "$work/commands" ] || fail 'aarch64 ran x86 native manager'
FIXTURE_ARCH=riscv64 reject; contains 'Unsupported architecture'
FIXTURE_SYSTEM=Darwin reject; contains 'Linux only'
HOME="$work/package-home" FIXTURE_MANAGER_STATUS=42 reject --yes; contains 'failed'
mv "$work/tools/openssl" "$work/openssl"
reject --method portable; contains 'Required command not found: openssl'
mv "$work/openssl" "$work/tools/openssl"
if command -v setsid >/dev/null 2>&1; then
  if HOME="$work/package-home" setsid bash "$root/scripts/install.sh" --public-key "$work/public.pem" >"$work/log" 2>&1; then
    fail 'noninteractive native install accepted without --yes'
  fi
  contains 'No interactive terminal'
fi

os arch rolling; HOME="$work/package-home" run --yes; command_contains 'yay -S --needed --noconfirm loopwire-bin'
mv "$work/tools/yay" "$work/yay"
os arch rolling; HOME="$work/package-home" run --yes; command_contains 'paru -S --needed --noconfirm loopwire-bin'
mv "$work/tools/paru" "$work/paru"
os arch rolling; HOME="$work/arch-fallback-home" run; contains 'portable'; [ ! -s "$work/commands" ] || fail 'Arch without helper ran manager'

cat >"$work/tools/nix" <<'EOF'
#!/bin/bash
printf '%s\n' "nix $*" >>"$FIXTURE_ROOT/commands"
case "$*" in
  *'profile list --json'*) printf '%s\n' '{"elements":{},"version":3}'; exit "${FIXTURE_NIX_LIST_STATUS:-0}" ;;
  *'eval --impure --raw --expr'*) printf '%s' "${FIXTURE_NIX_ENTRY:-}" ;;
  *'profile install '* | *'profile upgrade '*) exit "${FIXTURE_MANAGER_STATUS:-0}" ;;
  *) exit 99 ;;
esac
EOF
chmod +x "$work/tools/nix"
# Nix must not create a second package hidden by a previous portable launcher.
os nixos 26.05; reject
contains 'Migrate the existing portable installation explicitly'
[ ! -s "$work/commands" ] || fail 'NixOS portable conflict reached profile operations'
os ubuntu 26.04; reject --method nix
contains 'Migrate the existing portable installation explicitly'
[ ! -s "$work/commands" ] || fail 'explicit Nix portable conflict reached profile operations'
[ "$("$HOME/.local/bin/loopwire")" = new ] || fail 'Nix migration conflict changed the portable installation'

nix_run() { HOME="$work/nix-home" run; }
nix_reject() { HOME="$work/nix-home" reject "$@"; }
os nixos 26.05; nix_run
command_contains 'profile install github:sandwichfarm/loopwire#loopwire-bin'
os nixos 26.05; FIXTURE_NIX_ENTRY=loopwire-bin nix_run
command_contains 'profile upgrade loopwire-bin'
if grep -F 'profile install ' "$work/commands" >/dev/null; then fail 'Nix upgrade duplicated package'; fi
FIXTURE_NIX_ENTRY=$'loopwire-bin\nloopwire-bin-1' nix_reject; contains 'Multiple matching Loopwire'
os nixos 26.05; FIXTURE_NIX_ENTRY=conflict:loopwire-bin nix_reject
contains 'another flake reference'
if grep -E 'profile (install|upgrade) ' "$work/commands" >/dev/null; then fail 'Nix reference conflict reached mutation'; fi
FIXTURE_NIX_LIST_STATUS=1 nix_reject
FIXTURE_MANAGER_STATUS=33 nix_reject; contains 'failed'
nix_reject --method portable; contains 'NixOS requires'
nix_reject --prefix "$work/nix-prefix"; contains 'NixOS requires'
os nixos 26.05; nix_reject --version v1.2.3; contains '--version is not supported for Nix'
[ ! -s "$work/commands" ] || fail 'unsupported Nix version reached profile operations'
mv "$work/tools/nix" "$work/nix"
nix_reject; contains 'Required command not found: nix'

os debian 13
cp "$work/release/SHA256SUMS.sig" "$work/good.sig"
printf 'bad signature\n' >"$work/release/SHA256SUMS.sig"
HOME="$work/package-home" reject --yes; contains 'signature'; [ ! -s "$work/commands" ] || fail 'invalid signature reached manager'
mv "$work/good.sig" "$work/release/SHA256SUMS.sig"
printf 'tampered\n' >>"$work/release/loopwire_9.8.7-1debian13_amd64.deb"
HOME="$work/package-home" reject --yes; [ ! -s "$work/commands" ] || fail 'invalid checksum reached manager'
reject --method portable --public-key "$work/missing.pem"; contains 'public key'
mv "$work/release/loopwire-linux-x86_64.tar.gz" "$work/archive"
reject --method portable; contains 'Download'
mv "$work/archive" "$work/release/loopwire-linux-x86_64.tar.gz"
printf 'bad\n' >>"$work/release/loopwire-linux-x86_64.tar.gz"
reject --method portable
[ "$("$HOME/.local/bin/loopwire")" = new ] || fail 'verification failure damaged existing installation'

# Signed archives must still reject links that could escape during extraction.
payload new
ln -s /tmp "$work/payload/escape"
payload unsafe
reject --method portable; contains 'link or special file'
rm "$work/payload/escape"
payload new
cp "$work/release/SHA256SUMS" "$work/good-sums"
cat "$work/good-sums" >>"$work/release/SHA256SUMS"
openssl dgst -sha256 -sign "$work/private.pem" -out "$work/release/SHA256SUMS.sig" "$work/release/SHA256SUMS"
reject --method portable; contains 'one valid checksum'
HOME="$work/package-home" reject --yes; contains 'exactly one matching native package'
payload new
run --method portable --skip-signature; contains 'Signature verification skipped'
HOME="$work/package-home" reject --yes --skip-signature; contains 'restricted to --method portable'

# Public curl target and built-in trust root must stay synchronized with source.
cmp "$root/scripts/install.sh" "$root/apps/docs/docs/public/install.sh"
awk '/^-----BEGIN PUBLIC KEY-----$/ { key=1 } key { print } /^-----END PUBLIC KEY-----$/ { exit }' \
  "$root/scripts/install.sh" >"$work/embedded.pem"
cmp "$work/embedded.pem" "$root/packaging/release-signing-public.pem"

echo 'Installer platform, upgrade, dry-run and failure regressions passed.'
