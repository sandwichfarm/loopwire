#!/usr/bin/env bash
set -Eeuo pipefail

repo="${LOOPWIRE_REPO:-sandwichfarm/loopwire}"
version="${LOOPWIRE_VERSION:-latest}"
prefix="${PREFIX:-$HOME/.local/bin}"
portable_requested="${PREFIX:+true}"
base_url_override="${LOOPWIRE_BASE_URL:-}"
public_key_file="${LOOPWIRE_RELEASE_PUBLIC_KEY_FILE:-}"
skip_signature="${LOOPWIRE_SKIP_SIGNATURE:-false}"
method=auto
method_explicit=false
dry_run=false
assume_yes=false
step=arguments
tmp_dir=""
bin_stage=""
lib_stage=""
lock_dir=""
committing=false
committed=false
changed_commands=()
lib_changed=false
commands=(loopwire loopwire-dsp-provider loopwire-jack-ports loopwire-detect-audio)

usage() {
  cat <<'USAGE'
Install or upgrade Loopwire for Linux.

Usage:
  install.sh [--method auto|portable|native|aur|nix] [--yes] [--dry-run]
             [--repo owner/name] [--version vX.Y.Z|latest] [--base-url URL]
             [--prefix DIR] [--public-key FILE] [--skip-signature]

Auto selects matching native packages on Debian 13, Ubuntu 24.04, Fedora 44,
and openSUSE Tumbleweed (x86_64). Arch uses an existing yay/paru helper.
Existing ~/.local portable installations are upgraded in place instead.
NixOS uses the release-bound Nix flake. Other Linux targets use a signed
x86_64/aarch64 tarball; the portable runtime still needs distro GUI libraries.
For Nix, the flake owns the pinned release version; --version is not supported.
Use --method portable for a user-local installation without a package manager.
Explicit --prefix/PREFIX or --base-url defaults to portable unless --method is set.
Native/AUR installs show their command and use terminal package-manager prompts.
--yes accepts those prompts; without a terminal it is required for these methods.
--dry-run prints the plan without downloading or changing any files.

Environment:
  LOOPWIRE_REPO       Repository, default sandwichfarm/loopwire
  LOOPWIRE_VERSION    Release tag, default latest
  LOOPWIRE_BASE_URL   Asset base URL override, including file:// fixtures
  LOOPWIRE_RELEASE_PUBLIC_KEY_FILE
                      Override the embedded release verification key
  LOOPWIRE_SKIP_SIGNATURE
                      true only for unsigned local development (portable only)
  LOOPWIRE_OS_RELEASE_FILE
                      os-release fixture override, default /etc/os-release
  PREFIX              Portable command directory, default ~/.local/bin

Release downloads require SHA256SUMS and SHA256SUMS.sig. Portable assets are
loopwire-linux-x86_64.tar.gz and loopwire-linux-aarch64.tar.gz.
The GUI launcher can start without Node.js, but loopwire --background,
loopwire-dsp-provider, loopwire-jack-ports, and loopwire-detect-audio require node on PATH.
USAGE
}

fail() { printf 'Loopwire installer failed during %s: %s\n' "$step" "$*" >&2; exit 1; }
progress() { step="$2"; printf '\n[%s/7] %s\n' "$1" "$step"; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"; }
print_command() { printf 'Command:'; printf ' %q' "$@"; printf '\n'; }

detect_arch() {
  case "$(uname -m)" in
    x86_64 | amd64) printf '%s\n' x86_64 ;;
    aarch64 | arm64) printf '%s\n' aarch64 ;;
    *) fail "Unsupported architecture: $(uname -m). Available: x86_64, aarch64." ;;
  esac
}

cleanup() {
  local status=$? command changed remove_command rollback_failed=false
  trap - EXIT ERR
  # A second interrupt must not abort recovery halfway through restoring backups.
  trap '' INT TERM
  if [ "$committing" = true ] && [ "$committed" != true ]; then
    printf 'Restoring previous portable installation after failure.\n' >&2
    for command in "${commands[@]}"; do
      # A signal can arrive after mv succeeds and before shell flags are updated.
      # The backup on disk is authoritative evidence that restoration is needed.
      if [ -e "$bin_stage/backup/$command" ] || [ -L "$bin_stage/backup/$command" ]; then
        if ! rm -f -- "$prefix/$command" || ! mv -- "$bin_stage/backup/$command" "$prefix/$command"; then
          rollback_failed=true
        fi
      else
        remove_command=false
        for changed in "${changed_commands[@]}"; do
          [ "$command" != "$changed" ] || remove_command=true
        done
        if [ "$remove_command" = true ] && ! rm -f -- "$prefix/$command"; then rollback_failed=true; fi
      fi
    done
    if [ -e "$lib_stage/backup" ] || [ -L "$lib_stage/backup" ]; then
      if ! rm -rf -- "$lib_target" || ! mv -- "$lib_stage/backup" "$lib_target"; then
        rollback_failed=true
      fi
    elif [ "$lib_changed" = true ] && ! rm -rf -- "$lib_target"; then
      rollback_failed=true
    fi
  fi
  if [ "$rollback_failed" = true ]; then
    status=1
    printf 'Rollback incomplete. Recovery files are retained; do not rerun installation until restored.\n' >&2
    printf 'Command backups: %s/backup\nSupport backup: %s/backup\n' "$bin_stage" "$lib_stage" >&2
    printf 'Restore commands to %s and support files to %s, then remove the retained lock: %s\n' \
      "$prefix" "$lib_target" "$lock_dir" >&2
  else
    if [ -n "$bin_stage" ] && ! rm -rf -- "$bin_stage"; then status=1; fi
    if [ -n "$lib_stage" ] && ! rm -rf -- "$lib_stage"; then status=1; fi
    if [ -n "$lock_dir" ] && ! rmdir -- "$lock_dir"; then status=1; fi
  fi
  # Download cleanup is independent of recovery; its failure never removes backups.
  if [ -n "$tmp_dir" ] && ! rm -rf -- "$tmp_dir"; then
    printf 'Could not remove temporary downloads: %s\n' "$tmp_dir" >&2
    status=1
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'printf "Loopwire installer failed during %s (exit %s).\n" "$step" "$?" >&2' ERR
trap 'exit 130' INT
trap 'exit 143' TERM

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) repo="${2:?missing value for --repo}"; shift 2 ;;
    --version) version="${2:?missing value for --version}"; shift 2 ;;
    --prefix) prefix="${2:?missing value for --prefix}"; portable_requested=true; shift 2 ;;
    --base-url) base_url_override="${2:?missing value for --base-url}"; shift 2 ;;
    --public-key) public_key_file="${2:?missing value for --public-key}"; shift 2 ;;
    --method) method="${2:?missing value for --method}"; method_explicit=true; shift 2 ;;
    --skip-signature) skip_signature=true; shift ;;
    --yes) assume_yes=true; shift ;;
    --dry-run) dry_run=true; shift ;;
    -h | --help) usage; exit 0 ;;
    *) fail "Unknown argument: $1 (use --help)" ;;
  esac
done
case "$method" in auto | portable | native | aur | nix) ;; *) fail "Unknown method: $method" ;; esac
case "$skip_signature" in true | false) ;; *) fail 'LOOPWIRE_SKIP_SIGNATURE must be true or false' ;; esac

progress 1 'Detecting Linux platform and architecture'
[ "$(uname -s)" = Linux ] || fail 'Linux only: Loopwire does not provide macOS or Windows builds.'
arch="$(detect_arch)"
# Read only data fields. Do not execute os-release as shell code.
os_id=unknown
os_version=""
os_release="${LOOPWIRE_OS_RELEASE_FILE:-/etc/os-release}"
if [ -r "$os_release" ]; then
  while IFS='=' read -r key value; do
    value="${value%\"}"; value="${value#\"}"
    value="${value%\'}"; value="${value#\'}"
    case "$key" in ID) os_id="$value" ;; VERSION_ID) os_version="$value" ;; esac
  done <"$os_release"
fi
printf 'Platform: %s %s (%s)\n' "$os_id" "$os_version" "$arch"

progress 2 'Selecting an installation method'
default_portable_prefix="$HOME/.local/bin"
existing_portable=false
if [ -f "$default_portable_prefix/loopwire" ] && [ -x "$default_portable_prefix/loopwire" ] &&
  [ -d "$HOME/.local/lib/loopwire" ]; then
  existing_portable=true
fi
native_target=""
manager=""
if [ "$arch" = x86_64 ]; then
  case "$os_id:$os_version" in
    debian:13) native_target=debian13; manager=apt-get ;;
    ubuntu:24.04) native_target=ubuntu24.04; manager=apt-get ;;
    fedora:44) native_target=fc44; manager=dnf ;;
    opensuse-tumbleweed:*) native_target=opensuse; manager=zypper ;;
  esac
fi
if [ "$method_explicit" = false ] && { [ "$portable_requested" = true ] || [ -n "$base_url_override" ]; }; then
  method=portable
fi
if [ "$method" = auto ]; then
  if [ "$os_id" = nixos ]; then
    method=nix
  elif [ "$existing_portable" = true ] && [ "$prefix" = "$default_portable_prefix" ]; then
    method=portable
    printf 'Upgrading existing portable installation at %s; keeping the current installation method.\n' "$default_portable_prefix"
  elif [ "$os_id" = arch ] && [ "$version" = latest ] && [ "$repo" = sandwichfarm/loopwire ] &&
    { command -v yay >/dev/null 2>&1 || command -v paru >/dev/null 2>&1; }; then
    method=aur
  elif [ -n "$native_target" ] && command -v "$manager" >/dev/null 2>&1; then
    method=native
  else
    method=portable
    printf 'No matching native package/helper for this platform; using portable release.\n'
  fi
fi
if [ "$os_id" = nixos ] && [ "$method" != nix ]; then
  fail 'NixOS requires --method nix; generic Linux binaries need Nix runtime wrapping.'
fi
if [ "$skip_signature" = true ] && [ "$method" != portable ]; then
  fail '--skip-signature is restricted to --method portable local development installs.'
fi
printf 'Selected method: %s\n' "$method"
if [ "$portable_requested" = true ] && [ "$method" != portable ]; then
  fail '--prefix/PREFIX applies only to --method portable; package managers own their install paths.'
fi
if [ "$existing_portable" = true ] && [ "$method" = nix ]; then
  fail "A portable Loopwire installation exists at $default_portable_prefix and could hide the Nix profile version on PATH." \
    'Migrate the existing portable installation explicitly before using the Nix method;' \
    'existing files and the Nix profile are unchanged.'
fi
if [ "$existing_portable" = true ] && { [ "$method" = native ] || [ "$method" = aur ]; }; then
  fail "A portable Loopwire installation exists at $default_portable_prefix and could hide the package version on PATH." \
    'Use --method portable to upgrade it, or migrate that installation explicitly before switching package methods.'
fi

run_package_command() {
  print_command "$@"
  [ "$dry_run" = false ] || return 0
  # bash may itself be reading a curl pipe. Package managers must not consume it.
  if [ "$assume_yes" = true ]; then
    "$@" </dev/null
  elif { true </dev/tty; } 2>/dev/null; then
    "$@" </dev/tty
  else
    fail 'No interactive terminal. Rerun with --yes to accept package-manager prompts, or --method portable.'
  fi
}

if [ "$method" = aur ]; then
  [ "$os_id" = arch ] || fail 'The AUR method requires Arch Linux.'
  [ "$version" = latest ] && [ "$repo" = sandwichfarm/loopwire ] && [ -z "$base_url_override" ] ||
    fail 'AUR installs the official current loopwire-bin package; use --method portable for custom releases.'
  [ "$(id -u)" != 0 ] || fail 'Run the AUR installer as your regular user, not root.'
  if command -v yay >/dev/null 2>&1; then manager=yay
  elif command -v paru >/dev/null 2>&1; then manager=paru
  else fail 'Install yay/paru yourself, or select --method portable.'; fi
  args=("$manager" -S --needed)
  [ "$assume_yes" = false ] || args+=(--noconfirm)
  args+=(loopwire-bin)
  progress 3 'Using AUR package verification and dependency resolution'
  printf 'The installed helper builds loopwire-bin and checks its pinned release hashes.\n'
  progress 6 'Installing or upgrading the AUR package'
  run_package_command "${args[@]}"
elif [ "$method" = nix ]; then
  require_cmd nix
  [ -z "$base_url_override" ] && [ "$portable_requested" != true ] ||
    fail 'Nix uses your Nix profile; --prefix and --base-url apply only to portable installs.'
  [ "$version" = latest ] ||
    fail 'Nix uses the release version pinned by the repository flake; --version is not supported for Nix. Use --method nix without --version.'
  flake="github:$repo"
  nix_cmd=(nix --extra-experimental-features 'nix-command flakes')
  progress 3 'Inspecting the Nix profile for the release-bound flake'
  printf 'Nix flake: %s#loopwire-bin (uses the release version and hashes pinned by the flake).\n' "$flake"
  if [ "$dry_run" = true ]; then
    printf 'Will inspect the current profile, install if absent, or upgrade only the matching Loopwire entry.\n'
    print_command "${nix_cmd[@]}" profile install "$flake#loopwire-bin"
  else
    tmp_dir="$(mktemp -d)"
    "${nix_cmd[@]}" profile list --json >"$tmp_dir/profile.json"
    # Nix parses its own structured output, without a jq/Node/Python prerequisite.
    # shellcheck disable=SC2016 # ${name} is Nix interpolation, not shell expansion.
    nix_entry="$(LOOPWIRE_NIX_PROFILE_JSON="$tmp_dir/profile.json" LOOPWIRE_NIX_FLAKE="$flake" \
      "${nix_cmd[@]}" eval --impure --raw --expr '
        let
          profile = builtins.fromJSON (builtins.readFile (builtins.getEnv "LOOPWIRE_NIX_PROFILE_JSON"));
          elements = profile.elements or {};
          flake = builtins.getEnv "LOOPWIRE_NIX_FLAKE";
          hasPrefix = prefix: value: builtins.substring 0 (builtins.stringLength prefix) value == prefix;
          isLoopwire = e: builtins.match "packages\\..*\\.loopwire-bin" (e.attrPath or "") != null;
          matches = name: let e = elements.${name}; in
            (e.originalUrl or "") == flake && isLoopwire e;
          differentReference = name: let e = elements.${name}; ref = e.originalUrl or ""; in
            isLoopwire e && (hasPrefix (flake + "/") ref || hasPrefix (flake + "?") ref);
          conflicts = builtins.filter differentReference (builtins.attrNames elements);
        in if !builtins.isAttrs elements then
          throw "Loopwire requires a Nix profile with named entries; upgrade Nix before using this installer."
        else if conflicts != [] then "conflict:" + builtins.concatStringsSep ", " conflicts
        else builtins.concatStringsSep "\n" (builtins.filter matches (builtins.attrNames elements))
      ')"
    case "$nix_entry" in
      conflict:*)
        fail "Loopwire is already installed from another flake reference (${nix_entry#conflict:})." \
          'Inspect nix profile list and migrate that entry explicitly before retrying; the existing profile is unchanged.'
        ;;
    esac
    [[ "$nix_entry" != *$'\n'* ]] || fail 'Multiple matching Loopwire profile entries; inspect nix profile list before retrying.'
    progress 6 'Installing or upgrading Loopwire in the Nix profile'
    if [ -n "$nix_entry" ]; then args=("${nix_cmd[@]}" profile upgrade "$nix_entry")
    else args=("${nix_cmd[@]}" profile install "$flake#loopwire-bin"); fi
    print_command "${args[@]}"
    "${args[@]}" </dev/null
    printf 'Nix checks the pinned hashes and keeps the previous profile generation for nix profile rollback.\n'
  fi
else
  asset="loopwire-linux-$arch.tar.gz"
  if [ "$method" = native ]; then
    [ -n "$native_target" ] || fail 'No native release package matches this exact distro/version/architecture; use --method portable.'
    require_cmd "$manager"
  else
    printf 'Install prefix: %s\n' "$prefix"
    printf 'Portable installs need system GTK/WebKitGTK libraries; Node.js is required for background/provider commands.\n'
  fi
  if [ -n "$base_url_override" ]; then base_url="${base_url_override%/}"
  elif [ "$version" = latest ]; then base_url="https://github.com/$repo/releases/latest/download"
  else base_url="https://github.com/$repo/releases/download/$version"; fi
  printf 'Release source: %s\n' "$base_url"
  if [ "$dry_run" = true ]; then
    if [ "$method" = native ]; then
      printf 'Will verify the signed SHA256SUMS, select the %s package, then use %s install.\n' "$native_target" "$manager"
    else printf 'Release artifact: %s/%s\n' "$base_url" "$asset"; fi
  else
    for tool in curl sha256sum awk mktemp; do require_cmd "$tool"; done
    tmp_dir="$(mktemp -d)"
    progress 3 'Downloading and verifying the release checksum signature'
    download() {
      printf 'Downloading: %s/%s\n' "$base_url" "$1"
      curl --fail --location --show-error --progress-bar --retry 2 --connect-timeout 20 \
        "$base_url/$1" --output "$tmp_dir/$1" || fail "Download failed: $1"
    }
    if [ "$skip_signature" != true ]; then
      require_cmd openssl
      if [ -z "$public_key_file" ]; then
        public_key_file="$tmp_dir/release-public.pem"
        cat >"$public_key_file" <<'PUBLIC_KEY'
-----BEGIN PUBLIC KEY-----
MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAzd9A1ugDjETYPd5LnRGM
GHLLd/1UVllNlqSJIhAgg1iZopVFSRTtFeJQGLKQ/J6qvAE7rQQ/vHm7Q/fQCsQr
2USDXom9LBy6HPF1APzZNWLlwmt3555VAqtbi62sRm1bbZSO7gtKQx7vb06TF/CL
+IQjIcP60vmz3Vx1b+qN1qaMeOsXnquAQiiqRce5EA4Ds5Xn/5bk7nbvig//3KHQ
Vi0+BNVfUIzxsgNoxzSZyOt2MG1npfpjLL3Es4f00hPuJrAKMQWOaY3ex92WXxse
7tlfa6krmScafE21fCFxmhj8TTdx+SJjKCiGg8R9YvsPfE8faY+mGWRNvI5O2K26
fexaV20aRLE/druxGOQSZpNpr7m79LCP6+9JKgWuKCUyicNnrl5VGuEss3vR0wXJ
2ocq/7jCjmMD8Ucm+ejqp3EnXCKFptFh8YFAgPVcF6gTPWl6nylHGdr6nuQQATbh
IxTm9Q9BIciww9Jx1998UpygckxKmMICsypbwhv7zENbAgMBAAE=
-----END PUBLIC KEY-----
PUBLIC_KEY
      fi
      [ -f "$public_key_file" ] || fail "Release public key does not exist: $public_key_file"
    fi
    download SHA256SUMS
    if [ "$skip_signature" != true ]; then
      download SHA256SUMS.sig
      openssl dgst -sha256 -verify "$public_key_file" -signature "$tmp_dir/SHA256SUMS.sig" \
        "$tmp_dir/SHA256SUMS" >/dev/null || fail 'Release signature verification failed.'
      printf 'Signature verified.\n'
    else printf 'WARNING: Signature verification skipped by explicit request.\n' >&2; fi
    if [ "$method" = native ]; then
      case "$native_target" in
        debian13) pattern='^loopwire_[0-9][A-Za-z0-9.+~-]*-1debian13_amd64[.]deb$' ;;
        ubuntu24.04) pattern='^loopwire_[0-9][A-Za-z0-9.+~-]*-1ubuntu24[.]04_amd64[.]deb$' ;;
        fc44) pattern='^loopwire-[0-9][A-Za-z0-9.+~_-]*-1[.]fc44[.]x86_64[.]rpm$' ;;
        opensuse) pattern='^loopwire-[0-9][A-Za-z0-9.+~_-]*-1[.]x86_64[.]rpm$' ;;
      esac
      asset="$(awk -v pattern="$pattern" '$2 ~ pattern { print $2 }' "$tmp_dir/SHA256SUMS")"
      [ -n "$asset" ] && [[ "$asset" != *$'\n'* ]] ||
        fail 'Signed manifest must contain exactly one matching native package; use --method portable if unavailable.'
    fi
    # Check only the selected artifact, rejecting absent/duplicate/malformed records.
    awk -v asset="$asset" '$2 == asset { n++; if (NF != 2 || length($1) != 64 || $1 ~ /[^0-9a-fA-F]/) bad=1; print } END { exit (n != 1 || bad) }' \
      "$tmp_dir/SHA256SUMS" >"$tmp_dir/selected.sha256" || fail "SHA256SUMS must contain one valid checksum for $asset."
    progress 4 'Downloading the selected release artifact'
    download "$asset"
    progress 5 'Verifying the artifact checksum'
    (cd "$tmp_dir" && sha256sum --check selected.sha256) || fail "Checksum verification failed: $asset"
    if [ "$method" = native ]; then
      privilege=()
      if [ "$(id -u)" != 0 ]; then
        require_cmd sudo
        privilege=(sudo)
        [ "$assume_yes" = false ] || privilege+=(-n)
      fi
      case "$manager" in
        apt-get) args=(apt-get install); [ "$assume_yes" = false ] || args+=(-y) ;;
        dnf) args=(dnf install); [ "$assume_yes" = false ] || args+=(-y); args+=(--setopt=localpkg_gpgcheck=0) ;;
        zypper) args=(zypper); [ "$assume_yes" = false ] || args+=(--non-interactive); args+=(install --allow-unsigned-rpm) ;;
      esac
      args+=("$tmp_dir/$asset")
      progress 6 'Installing or upgrading the verified native package'
      printf 'Package manager handles dependencies and repeat installs; no repositories or services are added.\n'
      if [ "$manager" != apt-get ]; then
        printf 'RPM payloads use the verified release signature and SHA256 checksum instead of an embedded RPM signature.\n'
      fi
      run_package_command "${privilege[@]}" "${args[@]}"
    else
      for tool in tar install cp find mv chmod; do require_cmd "$tool"; done
      printf 'Checking archive paths and entry types before extraction.\n'
      tar -tzf "$tmp_dir/$asset" >"$tmp_dir/members"
      [ -s "$tmp_dir/members" ] || fail "Release artifact is empty: $asset"
      while IFS= read -r entry; do
        case "$entry" in /*) fail "Release artifact contains an absolute path: $entry" ;; esac
        case "/$entry/" in *'/../'*) fail "Release artifact contains a parent path component: $entry" ;; esac
        case "$entry" in *\\*) fail 'Release artifact contains an escaped or backslash path.' ;; esac
      done <"$tmp_dir/members"
      tar -tvzf "$tmp_dir/$asset" >"$tmp_dir/types"
      if awk 'substr($0,1,1) != "-" && substr($0,1,1) != "d" { bad=1 } END { exit !bad }' "$tmp_dir/types"; then
        fail 'Release artifact contains a link or special file; only regular files/directories are allowed.'
      fi
      mkdir "$tmp_dir/payload"
      tar -xzf "$tmp_dir/$asset" --no-same-owner --no-same-permissions -C "$tmp_dir/payload"
      [ -f "$tmp_dir/payload/loopwire" ] && [ -x "$tmp_dir/payload/loopwire" ] ||
        fail 'Release artifact did not contain an executable named loopwire at its root.'
      progress 6 'Staging and replacing the portable installation'
      mkdir -p -- "$prefix"
      prefix="$(cd "$prefix" && pwd -P)"
      candidate_lock="$prefix/.loopwire-install.lock"
      mkdir "$candidate_lock" 2>/dev/null || fail "Another install may be running; inspect $candidate_lock before removing a stale lock."
      lock_dir="$candidate_lock"
      lib_target="$(dirname "$prefix")/lib/loopwire"
      mkdir -p -- "$(dirname "$lib_target")"
      bin_stage="$(mktemp -d "$prefix/.loopwire-stage.XXXXXXXX")"
      lib_stage="$(mktemp -d "$(dirname "$lib_target")/.loopwire-stage.XXXXXXXX")"
      mkdir "$bin_stage/backup"
      for command in "${commands[@]}"; do
        if [ -f "$tmp_dir/payload/$command" ]; then
          [ -x "$tmp_dir/payload/$command" ] || fail "Bundled command is not executable: $command"
          install -m 0755 "$tmp_dir/payload/$command" "$bin_stage/$command"
        fi
        [ ! -d "$prefix/$command" ] || fail "Refusing to replace a directory at $prefix/$command"
      done
      if [ -d "$tmp_dir/payload/libexec/loopwire" ]; then
        cp -R "$tmp_dir/payload/libexec/loopwire" "$lib_stage/new"
        find "$lib_stage/new" -type d -exec chmod 0755 {} +
        find "$lib_stage/new" -type f -exec chmod 0644 {} +
        [ ! -f "$lib_stage/new/loopwire-gui" ] || chmod 0755 "$lib_stage/new/loopwire-gui"
      fi
      committing=true
      if [ -e "$lib_target" ] || [ -L "$lib_target" ]; then mv -- "$lib_target" "$lib_stage/backup"; fi
      lib_changed=true
      [ ! -d "$lib_stage/new" ] || mv -- "$lib_stage/new" "$lib_target"
      for command in "${commands[@]}"; do
        if [ -e "$prefix/$command" ] || [ -L "$prefix/$command" ]; then mv -- "$prefix/$command" "$bin_stage/backup/$command"; fi
        changed_commands+=("$command")
        [ ! -f "$bin_stage/$command" ] || mv -- "$bin_stage/$command" "$prefix/$command"
      done
      committed=true
      printf 'Loopwire installed to %s/loopwire\n' "$prefix"
      printf 'Obsolete Loopwire commands/support files were replaced; unrelated files are preserved.\n'
      case ":$PATH:" in *":$prefix:"*) ;; *) printf 'Add %s to PATH to run loopwire by name.\n' "$prefix" ;; esac
      if command -v node >/dev/null 2>&1; then
        printf 'Background restore dependency: node found at %s\n' "$(command -v node)"
      else
        printf '%s\n' 'WARNING: Background restore requires node on PATH.' \
          'Install nodejs before enabling Restore on boot or using bundled provider commands.' >&2
      fi
    fi
  fi
fi
if [ "$dry_run" = true ]; then progress 7 'Dry run complete. No files changed.'
else progress 7 'Installation complete. Run loopwire to launch.'; fi
