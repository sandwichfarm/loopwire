#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace_root="$(cd "$repo_root/.." && pwd)"
package_selection="loopwire"
checkout_root="$workspace_root/aur"
key_path="${AUR_SSH_KEY:-$HOME/.ssh/aur}"
tag=""

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Build, validate, and publish Loopwire AUR recipes.

Usage:
  deploy-aur-package.sh [--package loopwire|loopwire-bin|all] [--tag vX.Y.Z]
                        [--checkout-root DIR] [--key PATH]

Defaults:
  --package        loopwire
  --tag            newest v-prefixed tag reachable from HEAD
  --checkout-root  ../aur relative to the repository root
  --key            ~/.ssh/aur

The stable `loopwire` recipe builds the tagged source archive. `loopwire-bin`
consumes the signed architecture-specific release artifacts. Each recipe is
fully built with makepkg and inspected with namcap before its AUR Git push.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --) shift ;;
    --package) package_selection="${2:?missing value for --package}"; shift 2 ;;
    --tag) tag="${2:?missing value for --tag}"; shift 2 ;;
    --checkout-root) checkout_root="${2:?missing value for --checkout-root}"; shift 2 ;;
    --key) key_path="${2:?missing value for --key}"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

case "$package_selection" in
  loopwire) packages=(loopwire) ;;
  loopwire-bin) packages=(loopwire-bin) ;;
  all) packages=(loopwire loopwire-bin) ;;
  *) die "--package must be loopwire, loopwire-bin, or all" ;;
esac

for command_name in awk curl git makepkg namcap openssl sed sha256sum ssh ssh-add ssh-agent ssh-keygen tar; do
  command -v "$command_name" >/dev/null 2>&1 || die "required command is missing: $command_name"
done
[[ -d "$repo_root/.git" ]] || die "Loopwire checkout not found: $repo_root"
[[ -f "$repo_root/packaging/release-signing-public.pem" ]] || die "release public key not found"
[[ -f "$repo_root/scripts/verify-release-signature.sh" ]] || die "release signature verifier not found"
known_hosts_path="$repo_root/packaging/aur/known_hosts"
[[ -f "$known_hosts_path" ]] || die "pinned AUR known_hosts file not found"
expected_host_fingerprint="SHA256:RFzBCUItH9LZS0cKB5UE6ceAYhBD5C8GeOBip8Z11+4"
actual_host_fingerprint="$(ssh-keygen -lf "$known_hosts_path" | awk '{ print $2 }')"
[[ "$actual_host_fingerprint" = "$expected_host_fingerprint" ]] || \
  die "pinned AUR host key does not match the official Ed25519 fingerprint"
[[ -f "$key_path" ]] || die "expected SSH private key at $key_path"
[[ "$(stat -c '%a' "$key_path")" == "600" ]] || die "$key_path must have mode 600"

git -C "$repo_root" diff --quiet || die "Loopwire has tracked unstaged changes"
git -C "$repo_root" diff --cached --quiet || die "Loopwire has staged changes"
if [ -z "$tag" ]; then
  tag="$(git -C "$repo_root" describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null)" || \
    die "no v-prefixed release tag is reachable from HEAD"
fi
[[ "$tag" =~ ^v([0-9]+([.][0-9]+)*)$ ]] || die "release tag must look like v1.2.3; got $tag"
version="${tag#v}"

tmp_dir="$(mktemp -d -t loopwire-aur-deploy.XXXXXXXX)"
started_agent=0
cleanup() {
  rm -rf -- "$tmp_dir"
  if [ "$started_agent" = "1" ]; then
    ssh-agent -k >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [[ ! -S "${SSH_AUTH_SOCK:-}" ]]; then
  eval "$(ssh-agent -s)" >/dev/null
  started_agent=1
fi
public_key_path="$key_path.pub"
if [ ! -f "$public_key_path" ]; then
  public_key_path="$tmp_dir/aur.pub"
  ssh-keygen -y -f "$key_path" >"$public_key_path"
fi
key_fingerprint="$(ssh-keygen -lf "$public_key_path" | awk '{ print $2 }')"
if ! ssh-add -l 2>/dev/null | grep -Fq "$key_fingerprint"; then
  printf 'Unlocking AUR key %s...\n' "$key_fingerprint"
  ssh-add "$key_path"
fi
auth_output="$(
  ssh -i "$key_path" \
    -o IdentitiesOnly=yes \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=yes \
    -o "UserKnownHostsFile=$known_hosts_path" \
    -T aur@aur.archlinux.org 2>&1 || true
)"
printf '%s\n' "$auth_output"
[[ "$auth_output" == *"Welcome to AUR"* ]] || die "AUR did not accept $key_path"
printf -v git_ssh_command \
  'ssh -i %q -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=%q' \
  "$key_path" "$known_hosts_path"

release_dir="$tmp_dir/release"
mkdir -p "$release_dir"
if [[ " ${packages[*]} " == *" loopwire "* ]]; then
  source_archive="$release_dir/loopwire-${version}.tar.gz"
  curl --fail --location --retry 3 --silent --show-error \
    "https://github.com/sandwichfarm/loopwire/archive/refs/tags/${tag}.tar.gz" \
    --output "$source_archive"
fi
if [[ " ${packages[*]} " == *" loopwire-bin "* ]]; then
  release_base="https://github.com/sandwichfarm/loopwire/releases/download/$tag"
  for asset in SHA256SUMS SHA256SUMS.sig loopwire-linux-x86_64.tar.gz loopwire-linux-aarch64.tar.gz; do
    curl --fail --location --retry 3 --silent --show-error \
      "$release_base/$asset" --output "$release_dir/$asset"
  done
  bash "$repo_root/scripts/verify-release-signature.sh" \
    --release-dir "$release_dir" \
    --public-key "$repo_root/packaging/release-signing-public.pem"
  (
    cd "$release_dir"
    sha256sum --check --ignore-missing SHA256SUMS
  )
fi

render_pkgbuild() {
  local package_name="$1"
  local package_rel="$2"
  local output="$3"
  local source_mode="$4"
  local args=(
    --package "$package_name"
    --version "$version"
    --pkgrel "$package_rel"
    --output "$output"
  )
  if [ "$package_name" = "loopwire" ]; then
    args+=(--source-archive "$source_archive")
  else
    args+=(--release-dir "$release_dir")
  fi
  if [ "$source_mode" = "published" ]; then
    args+=(--published)
  fi
  bash "$repo_root/scripts/render-aur-pkgbuild.sh" "${args[@]}" >/dev/null
}

generate_srcinfo() {
  local pkgbuild="$1"
  local output="$2"
  local metadata_dir
  metadata_dir="$(mktemp -d "$tmp_dir/srcinfo.XXXXXXXX")"
  cp "$pkgbuild" "$metadata_dir/PKGBUILD"
  (
    cd "$metadata_dir"
    makepkg --printsrcinfo
  ) >"$output"
}

prepare_checkout() {
  local package_name="$1"
  local checkout="$checkout_root/$package_name"
  local remote="aur@aur.archlinux.org:${package_name}.git"
  mkdir -p "$checkout_root"
  if [ -e "$checkout" ] && [ ! -d "$checkout/.git" ]; then
    die "AUR checkout path exists but is not a Git repository: $checkout"
  fi
  if [ ! -d "$checkout/.git" ]; then
    if GIT_SSH_COMMAND="$git_ssh_command" \
      git ls-remote --exit-code "$remote" refs/heads/master >/dev/null 2>&1; then
      GIT_SSH_COMMAND="$git_ssh_command" git clone "$remote" "$checkout" >/dev/null
    else
      mkdir -p "$checkout"
      git -C "$checkout" init --initial-branch=master >/dev/null
      git -C "$checkout" remote add origin "$remote"
    fi
  fi
  [[ -z "$(git -C "$checkout" status --porcelain)" ]] || die "AUR checkout has uncommitted changes: $checkout"
  existing_remote="$(git -C "$checkout" remote get-url origin 2>/dev/null || true)"
  [ "$existing_remote" = "$remote" ] || die "AUR checkout origin is $existing_remote, expected $remote"
  git -C "$checkout" config core.sshCommand "$git_ssh_command"
  if git -C "$checkout" ls-remote --exit-code origin refs/heads/master >/dev/null 2>&1; then
    git -C "$checkout" fetch origin master
    if git -C "$checkout" rev-parse --verify HEAD >/dev/null 2>&1; then
      git -C "$checkout" merge --ff-only FETCH_HEAD >/dev/null
    else
      git -C "$checkout" checkout -B master FETCH_HEAD >/dev/null
    fi
  fi
  printf '%s\n' "$checkout"
}

publish_package() {
  local package_name="$1"
  local checkout package_dir candidate_pkgbuild candidate_srcinfo current_version current_rel package_rel
  checkout="$(prepare_checkout "$package_name")"
  package_dir="$tmp_dir/$package_name"
  mkdir -p "$package_dir"
  candidate_pkgbuild="$package_dir/PKGBUILD.published"
  candidate_srcinfo="$package_dir/.SRCINFO.published"
  current_version=""
  current_rel="0"
  if [ -f "$checkout/.SRCINFO" ]; then
    current_version="$(awk '$1 == "pkgver" && $2 == "=" { print $3; exit }' "$checkout/.SRCINFO")"
    current_rel="$(awk '$1 == "pkgrel" && $2 == "=" { print $3; exit }' "$checkout/.SRCINFO")"
  fi
  package_rel="1"
  if [ "$current_version" = "$version" ] && [[ "$current_rel" =~ ^[0-9]+$ ]]; then
    package_rel="$current_rel"
  fi
  render_pkgbuild "$package_name" "$package_rel" "$candidate_pkgbuild" published
  generate_srcinfo "$candidate_pkgbuild" "$candidate_srcinfo"
  if [ -f "$checkout/PKGBUILD" ] && [ -f "$checkout/.SRCINFO" ] && \
    [ -f "$checkout/LICENSE-MIT" ] && \
    cmp -s "$candidate_pkgbuild" "$checkout/PKGBUILD" && \
    cmp -s "$candidate_srcinfo" "$checkout/.SRCINFO" && \
    cmp -s "$repo_root/packaging/aur/LICENSE-MIT" "$checkout/LICENSE-MIT"; then
    printf '%s is already current at %s-%s.\n' "$package_name" "$version" "$package_rel"
    return
  fi
  if [ "$current_version" = "$version" ] && [[ "$current_rel" =~ ^[0-9]+$ ]]; then
    package_rel="$((current_rel + 1))"
    render_pkgbuild "$package_name" "$package_rel" "$candidate_pkgbuild" published
    generate_srcinfo "$candidate_pkgbuild" "$candidate_srcinfo"
  fi

  build_dir="$package_dir/build"
  mkdir -p "$build_dir"
  render_pkgbuild "$package_name" "$package_rel" "$build_dir/PKGBUILD" local
  cp "$repo_root/packaging/aur/LICENSE-MIT" "$build_dir/LICENSE-MIT"
  if [ "$package_name" = "loopwire" ]; then
    cp "$source_archive" "$build_dir/loopwire-${version}.tar.gz"
  else
    cp "$release_dir/loopwire-linux-x86_64.tar.gz" "$build_dir/"
    cp "$release_dir/loopwire-linux-aarch64.tar.gz" "$build_dir/"
  fi
  printf 'Building %s %s-%s...\n' "$package_name" "$version" "$package_rel"
  (
    cd "$build_dir"
    makepkg --force --nodeps --noconfirm --cleanbuild --clean
  )
  package_file="$(find "$build_dir" -maxdepth 1 -type f -name "${package_name}-*.pkg.tar.*" ! -name "${package_name}-debug-*" -print -quit)"
  [ -n "$package_file" ] || die "makepkg did not produce the $package_name package"
  namcap_log="$package_dir/namcap.log"
  namcap "$candidate_pkgbuild" "$package_file" | tee "$namcap_log"
  grep -Fq " E: " "$namcap_log" && die "namcap reported an error for $package_name"

  install -m 0644 "$candidate_pkgbuild" "$checkout/PKGBUILD"
  install -m 0644 "$candidate_srcinfo" "$checkout/.SRCINFO"
  install -m 0644 "$repo_root/packaging/aur/LICENSE-MIT" "$checkout/LICENSE-MIT"
  git -C "$checkout" add PKGBUILD .SRCINFO LICENSE-MIT
  git -C "$checkout" diff --cached --quiet && return

  author_name="$(git -C "$repo_root" config user.name || true)"
  author_email="$(git -C "$repo_root" config user.email || true)"
  git -C "$checkout" config user.name "${author_name:-Loopwire release bot}"
  git -C "$checkout" config user.email "${author_email:-aur@loopwire.app}"
  recipe_kind="source-built"
  [ "$package_name" = "loopwire-bin" ] && recipe_kind="release-binary"
  commit_message="$package_dir/commit-message"
  cat >"$commit_message" <<EOF
Publish Loopwire $version as the $recipe_kind AUR variant

Keep the package base aligned with how its artifacts are produced while both
stable installation choices expose the same Loopwire commands.

Constraint: AUR metadata must reference immutable, checksum-bound release inputs
Confidence: high
Scope-risk: narrow
Reversibility: clean
Directive: Keep loopwire and loopwire-bin as separate package bases
Tested: makepkg build, .SRCINFO generation, namcap
Not-tested: Installation into a clean Arch Linux guest
EOF
  git -C "$checkout" commit --file "$commit_message"
  git -C "$checkout" push --set-upstream origin master

  local_head="$(git -C "$checkout" rev-parse HEAD)"
  remote_head="$(git -C "$checkout" ls-remote origin refs/heads/master | awk '{ print $1 }')"
  [ "$local_head" = "$remote_head" ] || die "$package_name remote HEAD does not match the local commit"
  aur_page="https://aur.archlinux.org/packages/${package_name}"
  aur_page_file="$package_dir/aur-page.html"
  published="false"
  for _ in {1..10}; do
    if curl --fail --silent --show-error "$aur_page" --output "$aur_page_file" && \
      grep -Fq "Package Details: $package_name $version-$package_rel" "$aur_page_file"; then
      published="true"
      break
    fi
    sleep 3
  done
  [ "$published" = "true" ] || die "$package_name push succeeded, but its AUR package page is not visible yet"
  printf 'Published %s %s-%s: https://aur.archlinux.org/packages/%s\n' \
    "$package_name" "$version" "$package_rel" "$package_name"
}

for package_name in "${packages[@]}"; do
  publish_package "$package_name"
done
