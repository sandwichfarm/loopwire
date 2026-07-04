#!/usr/bin/env bash
set -euo pipefail

target_file="${LOOPWIRE_VM_TARGETS:-vm/targets.tsv}"
vm_root="${LOOPWIRE_VM_ROOT:-.vm}"

usage() {
  cat <<'USAGE'
Loopwire VM compatibility matrix helper.

Usage:
  vm-matrix.sh list
  vm-matrix.sh validate
  vm-matrix.sh host-plan [--target TARGET]
  vm-matrix.sh host-setup [--family pacman|apt|dnf|zypper|nix] [--target TARGET|--all]
  vm-matrix.sh doctor [--target TARGET|--all]
  vm-matrix.sh evidence-status [--target TARGET|--all] [--evidence-root DIR] [--require-published-release]
  vm-matrix.sh plan [--target TARGET]
  vm-matrix.sh render-ssh-plan [--target TARGET|--all] [--host HOST] [--user USER]
                               [--identity FILE] [--start-port PORT]
                               [--desktop-port PORT] [--output FILE]
  vm-matrix.sh render-launch-plan [--target TARGET|--all] [--image-root DIR]
                               [--image-format qcow2|raw] [--start-port PORT]
                               [--memory 4096] [--cpus 4] [--firmware FILE]
                               [--output FILE]
  vm-matrix.sh render-runbook [--target TARGET|--all] [--image-root DIR]
                               [--image-format qcow2|raw] [--start-port PORT]
                               [--memory 4096] [--cpus 4] [--firmware FILE]
                               [--evidence-root DIR] [--output FILE]
  vm-matrix.sh render-cloud-init --target TARGET|--all [--output DIR]
  vm-matrix.sh verify-cloud-init [--target TARGET] [--output DIR]
  vm-matrix.sh launch --target TARGET --image IMAGE.qcow2 [--image-format qcow2]
                   [--firmware QEMU_EFI.fd] [--memory 4096] [--cpus 4]
                   [--ssh-port 2222] [--execute]

Commands are non-mutating unless explicitly noted:
  list               Print supported VM targets.
  validate           Validate target metadata and known package families.
  host-plan          Print host setup, image, render, launch, and evidence handoff instructions.
  host-setup         Print local host install and verification commands. Dry-run only.
  doctor             Check local virtualization prerequisites for one target, all targets, or the default x86 host.
  evidence-status    Report missing, invalid, and verified VM evidence without promoting support claims.
  plan               Print guest setup and validation commands for each target.
  render-ssh-plan    Print or write a TSV plan for collect-vm-matrix-evidence.sh.
  render-launch-plan Print or write target-scoped dry-run QEMU launch handoffs.
  render-runbook     Print or write a markdown operator runbook for matrix execution.
  render-cloud-init  Write user-data, meta-data, and guest-commands.sh under .vm/cloud-init/TARGET.
  verify-cloud-init  Render cloud-init assets to a temp dir and validate every target handoff.
  launch             Print a qemu launch command. With --execute, create .vm/run/TARGET assets and start qemu.

Actual distro image download and license/compliance decisions are intentionally operator-owned.
USAGE
}

fail() {
  echo "vm-matrix: $*" >&2
  exit 1
}

rows() {
  [ -f "$target_file" ] || fail "missing target file: $target_file"
  grep -vE '^[[:space:]]*(#|$)' "$target_file"
}

get_target_row() {
  target="$1"
  rows | awk -F '\t' -v id="$target" '$1 == id { print; found = 1 } END { if (!found) exit 1 }'
}

field() {
  row="$1"
  index="$2"
  printf '%s\n' "$row" | awk -F '\t' -v idx="$index" '{ print $idx }'
}

target_ids() {
  rows | awk -F '\t' '{ print $1 }'
}

each_target() {
  if [ -n "${target_filter:-}" ]; then
    get_target_row "$target_filter"
  else
    rows
  fi
}

known_family() {
  case "$1" in
    pacman | apt | dnf | zypper | nix)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

guest_bootstrap_command() {
  family="$1"
  audio="${2:-}"

  case "$family" in
    pacman)
      cat <<'COMMANDS'
sudo pacman -Syu --needed \
  git \
  nodejs \
  pnpm \
  rust \
  pkgconf \
  pipewire \
  wireplumber \
  pipewire-pulse \
  alsa-utils \
  webkit2gtk-4.1 \
  base-devel \
  curl \
  wget \
  file \
  openssl \
  appmenu-gtk-module \
  libayatana-appindicator \
  librsvg \
  xdotool
COMMANDS
      ;;
    apt)
      cat <<'COMMANDS'
sudo apt-get update
sudo apt-get install -y \
  git \
  nodejs \
  npm \
  rustc \
  cargo \
  pkg-config \
  pipewire \
  pipewire-pulse \
  pulseaudio-utils \
  alsa-utils \
  libwebkit2gtk-4.1-dev \
  build-essential \
  curl \
  wget \
  file \
  libxdo-dev \
  libssl-dev \
  libayatana-appindicator3-dev \
  librsvg2-dev
sudo npm install -g pnpm@11.3.0
COMMANDS
      ;;
    dnf)
      cat <<'COMMANDS'
sudo dnf install -y \
  git \
  nodejs \
  pnpm \
  rust \
  cargo \
  pkgconf-pkg-config \
  pipewire \
  wireplumber \
  pipewire-pulseaudio \
  alsa-utils \
  webkit2gtk4.1-devel \
  openssl-devel \
  curl \
  wget \
  file \
  libappindicator-gtk3-devel \
  librsvg2-devel \
  libxdo-devel
sudo dnf group install -y "c-development" || sudo dnf install -y gcc gcc-c++ make
COMMANDS
      case "$audio" in
        *JACK*)
          printf '%s\n' "sudo dnf install -y jack-audio-connection-kit"
          ;;
      esac
      ;;
    zypper)
      cat <<'COMMANDS'
sudo zypper --non-interactive refresh
sudo zypper --non-interactive install \
  git \
  nodejs \
  npm \
  rust \
  cargo \
  pkgconf-pkg-config \
  pipewire \
  pipewire-pulseaudio \
  pipewire-alsa \
  wireplumber \
  alsa-utils \
  webkit2gtk3-devel \
  libopenssl-devel \
  curl \
  wget \
  file \
  libappindicator3-1 \
  librsvg-devel
sudo zypper --non-interactive install -t pattern devel_basis
sudo npm install -g pnpm@11.3.0
COMMANDS
      ;;
    nix)
      printf '%s\n' "nix develop --command bash -lc 'pnpm install --frozen-lockfile && pnpm check'"
      ;;
    *)
      fail "unsupported package family: $family"
      ;;
  esac
}

qemu_system_command_for_arch() {
  arch="${1:-x86_64}"

  case "$arch" in
    x86_64 | amd64)
      printf '%s\n' "qemu-system-x86_64"
      ;;
    aarch64 | arm64)
      printf '%s\n' "qemu-system-aarch64"
      ;;
    *)
      fail "unsupported VM architecture for QEMU preflight: $arch"
      ;;
  esac
}

arch_requires_firmware() {
  case "$1" in
    aarch64 | arm64)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

host_install_hint() {
  local arch_scope="${1:-x86_64}"
  local detected_family

  if detected_family="$(detect_host_family)"; then
    echo "host-install-hint=$(host_install_hint_for_family "$detected_family" "$arch_scope")"
  else
    echo "host-install-hint=install QEMU, qemu-img, cloud-localds/cloud-image-utils, and an OpenSSH client"
  fi
}

detect_host_family() {
  if command -v pacman >/dev/null 2>&1; then
    echo "pacman"
  elif command -v apt-get >/dev/null 2>&1; then
    echo "apt"
  elif command -v dnf >/dev/null 2>&1; then
    echo "dnf"
  elif command -v zypper >/dev/null 2>&1; then
    echo "zypper"
  elif command -v nix >/dev/null 2>&1; then
    echo "nix"
  else
    return 1
  fi
}

host_install_hint_for_family() {
  local family="$1"
  local arch_scope="${2:-x86_64}"

  case "$family" in
    pacman)
      printf '%s\n' "sudo pacman -Syu --needed qemu-full cloud-image-utils openssh"
      ;;
    apt)
      printf '%s\n' "sudo apt-get install -y qemu-system qemu-utils cloud-image-utils openssh-client"
      ;;
    dnf)
      case "$arch_scope" in
        all | aarch64 | arm64)
          printf '%s\n' "sudo dnf install -y qemu-kvm qemu-system-aarch64 qemu-img cloud-utils openssh-clients"
          ;;
        *)
          printf '%s\n' "sudo dnf install -y qemu-kvm qemu-img cloud-utils openssh-clients"
          ;;
      esac
      ;;
    zypper)
      case "$arch_scope" in
        all)
          printf '%s\n' "sudo zypper --non-interactive install qemu-x86 qemu-arm qemu-tools cloud-utils openssh"
          ;;
        aarch64 | arm64)
          printf '%s\n' "sudo zypper --non-interactive install qemu-arm qemu-tools cloud-utils openssh"
          ;;
        *)
          printf '%s\n' "sudo zypper --non-interactive install qemu-x86 qemu-tools cloud-utils openssh"
          ;;
      esac
      ;;
    nix)
      printf '%s\n' "nix shell nixpkgs#qemu_kvm nixpkgs#cloud-utils nixpkgs#openssh"
      ;;
    *)
      fail "unsupported host package family: $family"
      ;;
  esac
}

print_host_setup() {
  local family="$1"
  local qemu_system_command="qemu-system-x86_64"
  local row
  local arch="x86_64"

  if [ "$all_targets" = "true" ]; then
    [ -z "${target_filter:-}" ] || fail "host-setup accepts either --target or --all, not both"
    print_all_host_setup "$family"
    return
  fi

  if [ -z "$family" ]; then
    family="$(detect_host_family)" || fail "could not detect host package family; pass --family"
  fi

  known_family "$family" || fail "unsupported host package family: $family"

  echo "VM host setup dry-run"
  echo "package-family=$family"

  if [ -n "${target_filter:-}" ]; then
    row="$(get_target_row "$target_filter")"
    arch="$(field "$row" 7)"
    qemu_system_command="$(qemu_system_command_for_arch "$arch")"
    echo "target=$target_filter"
    echo "target-arch=$arch"
  fi

  echo "install-command=$(host_install_hint_for_family "$family" "$arch")"
  echo "required-tool=$qemu_system_command"
  echo "required-tool=qemu-img"
  echo "required-tool=cloud-localds"
  echo "required-tool=ssh"

  if [ -n "${target_filter:-}" ]; then
    echo "verify-command=bash scripts/vm-matrix.sh doctor --target $target_filter"
  else
    echo "verify-command=bash scripts/vm-matrix.sh doctor"
  fi

  echo "Dry run complete. No packages were installed. Run the install command manually, then rerun the verify command."
}

print_all_host_setup() {
  local family="$1"
  local qemu_system_command

  if [ -z "$family" ]; then
    family="$(detect_host_family)" || fail "could not detect host package family; pass --family"
  fi

  known_family "$family" || fail "unsupported host package family: $family"

  echo "VM host setup dry-run"
  echo "package-family=$family"
  echo "target-scope=all"
  echo "install-command=$(host_install_hint_for_family "$family" all)"

  all_required_qemu_tools | while read -r qemu_system_command; do
    echo "required-tool=$qemu_system_command"
  done

  echo "required-tool=qemu-img"
  echo "required-tool=cloud-localds"
  echo "required-tool=ssh"
  echo "verify-command=bash scripts/vm-matrix.sh doctor --all"
  echo "Dry run complete. No packages were installed. Run the install command manually, then rerun the verify command."
}

all_required_qemu_tools() {
  rows | while IFS=$'\t' read -r _id _distro _family _desktop _session _audio arch _tier _notes; do
    qemu_system_command_for_arch "$arch"
  done | sort -u
}

print_validation_commands() {
  family="$1"

  if [ "$family" != "nix" ]; then
    cat <<'COMMANDS'
pnpm install --frozen-lockfile
pnpm check
pnpm detect:audio
bash scripts/ct-host-check.sh
COMMANDS
  else
    cat <<'COMMANDS'
nix develop --command pnpm detect:audio
nix develop --command bash scripts/ct-host-check.sh
COMMANDS
  fi
}

guest_evidence_command() {
  family="$1"
  target="$2"
  command="bash scripts/collect-vm-evidence.sh --target $target --output-dir .vm/evidence/$target"

  if [ "$family" = "nix" ]; then
    printf '%s\n' "nix develop --command $command"
  else
    printf '%s\n' "$command"
  fi
}

list_targets() {
  printf '%-28s %-14s %-10s %-12s %-8s %-30s\n' "TARGET" "DISTRO" "DESKTOP" "SESSION" "ARCH" "AUDIO"
  each_target | while IFS=$'\t' read -r id distro _family desktop session audio arch _tier _notes; do
    printf '%-28s %-14s %-10s %-12s %-8s %-30s\n' "$id" "$distro" "$desktop" "$session" "$arch" "$audio"
  done
}

validate_targets() {
  ids_seen=""
  count=0

  while IFS=$'\t' read -r id distro family desktop session audio arch tier notes; do
    count=$((count + 1))

    [ -n "$id" ] || fail "row $count missing id"
    [ -n "$distro" ] || fail "$id missing distro"
    [ -n "$desktop" ] || fail "$id missing desktop"
    [ -n "$session" ] || fail "$id missing session"
    [ -n "$audio" ] || fail "$id missing audio"
    [ -n "$arch" ] || fail "$id missing arch"
    [ -n "$tier" ] || fail "$id missing tier"
    [ -n "$notes" ] || fail "$id missing notes"
    known_family "$family" || fail "$id has unsupported package family: $family"

    case "$ids_seen" in
      *" $id "*)
        fail "duplicate target id: $id"
        ;;
    esac

    ids_seen="${ids_seen} ${id} "
  done <<EOF
$(rows)
EOF

  [ "$count" -gt 0 ] || fail "target matrix is empty"
  echo "Validated $count VM targets."
}

doctor() {
  if [ "$all_targets" = "true" ]; then
    [ -z "${target_filter:-}" ] || fail "doctor accepts either --target or --all, not both"
    doctor_all_targets
    return
  fi

  doctor_target "${target_filter:-}"
}

doctor_all_targets() {
  local missing=0
  local count=0
  local id

  echo "VM doctor all targets"

  while IFS=$'\t' read -r id _distro _family _desktop _session _audio _arch _tier _notes; do
    count=$((count + 1))
    echo "target-check=$id"

    if ! doctor_target "$id"; then
      missing=1
    fi

    echo
  done <<EOF
$(rows)
EOF

  [ "$count" -gt 0 ] || fail "target matrix is empty"
  [ "$missing" -eq 0 ] || return 1
}

doctor_target() {
  local selected_target="$1"
  local missing=0
  local qemu_system_command="qemu-system-x86_64"
  local row
  local distro
  local family
  local desktop
  local session
  local audio
  local arch="x86_64"

  if [ -n "$selected_target" ]; then
    row="$(get_target_row "$selected_target")"
    distro="$(field "$row" 2)"
    family="$(field "$row" 3)"
    desktop="$(field "$row" 4)"
    session="$(field "$row" 5)"
    audio="$(field "$row" 6)"
    arch="$(field "$row" 7)"
    qemu_system_command="$(qemu_system_command_for_arch "$arch")"

    echo "target=$selected_target"
    echo "target-distro=$distro"
    echo "target-desktop=$desktop"
    echo "target-session=$session"
    echo "target-audio=$audio"
    echo "target-arch=$arch"
    echo "target-guest-family=$family"
  fi

  check_required "$qemu_system_command" || missing=1
  check_required qemu-img || missing=1
  check_required ssh || missing=1
  check_required cloud-localds || missing=1

  if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    echo "kvm=available"
  elif [ -e /dev/kvm ]; then
    echo "kvm=present-but-not-user-accessible"
  else
    echo "kvm=missing"
  fi

  host_install_hint "$arch"

  if [ -n "$selected_target" ]; then
    echo "guest-bootstrap=$(guest_bootstrap_command "$family" "$audio" | tr '\n' ';' | sed 's/;$//')"
    echo "guest-evidence-command=$(guest_evidence_command "$family" "$selected_target")"
    echo "host-pull-command=bash scripts/collect-vm-evidence-ssh.sh --target $selected_target --host 127.0.0.1 --port 2222 --execute"
  fi

  [ "$missing" -eq 0 ] || return 1
}

check_required() {
  name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    echo "${name}=present"
    return 0
  fi

  echo "${name}=missing"
  return 1
}

single_line() {
  tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//'
}

verify_evidence_bundle() {
  local id="$1"
  local dir="$2"
  local verify_args=(bash scripts/verify-vm-evidence.sh --target "$id" --evidence-dir "$dir")

  if [ "$require_published_release" = "true" ]; then
    verify_args+=(--require-published-release)
  fi

  "${verify_args[@]}"
}

evidence_status() {
  local checked=0
  local verified=0
  local missing=0
  local invalid=0
  local id
  local dir
  local output
  local verify_command

  if [ "$all_targets" = "true" ] && [ -n "${target_filter:-}" ]; then
    fail "evidence-status accepts either --target or --all, not both"
  fi

  echo "VM evidence status"
  echo "evidence-root=$evidence_root"
  echo "require-published-release=$require_published_release"

  while IFS=$'\t' read -r id _distro _family _desktop _session _audio _arch _tier _notes; do
    checked=$((checked + 1))
    dir="$evidence_root/$id"
    verify_command="bash scripts/verify-vm-evidence.sh --target $id --evidence-dir $dir"
    if [ "$require_published_release" = "true" ]; then
      verify_command="$verify_command --require-published-release"
    fi

    echo "target=$id"
    echo "evidence-dir=$dir"
    echo "verify-command=$verify_command"

    if [ ! -d "$dir" ]; then
      missing=$((missing + 1))
      echo "status=missing"
      echo "collect-command=bash scripts/collect-vm-evidence-ssh.sh --target $id --host 127.0.0.1 --port 2222 --execute"
      echo
      continue
    fi

    if output="$(verify_evidence_bundle "$id" "$dir" 2>&1)"; then
      verified=$((verified + 1))
      echo "status=verified"
    else
      invalid=$((invalid + 1))
      echo "status=invalid"
      echo "reason=$(printf '%s' "$output" | single_line)"
    fi

    echo
  done <<EOF
$(each_target)
EOF

  [ "$checked" -gt 0 ] || fail "target matrix is empty"
  echo "summary=checked:$checked verified:$verified missing:$missing invalid:$invalid"

  [ "$invalid" -eq 0 ] || return 1
}

check_optional() {
  name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    echo "${name}=present"
  else
    echo "${name}=missing-optional"
  fi
}

validate_tcp_port() {
  port="$1"
  label="${2:-SSH port}"

  case "$port" in
    "" | *[!0-9]*)
      fail "$label must be a number from 1 to 65535"
      ;;
  esac

  if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    fail "$label must be a number from 1 to 65535"
  fi
}

validate_int_range() {
  value="$1"
  label="$2"
  min="$3"
  max="$4"

  case "$value" in
    "" | *[!0-9]*)
      fail "$label must be a number from $min to $max"
      ;;
  esac

  if [ "$value" -lt "$min" ] || [ "$value" -gt "$max" ]; then
    fail "$label must be a number from $min to $max"
  fi
}

validate_image_format() {
  case "$1" in
    qcow2 | raw)
      ;;
    *)
      fail "image format must be qcow2 or raw"
      ;;
  esac
}

print_host_plan() {
  each_target | while IFS=$'\t' read -r id distro family desktop session audio arch tier notes; do
    qemu_system_command="$(qemu_system_command_for_arch "$arch")"

    cat <<EOF
Target: $id
  Distro: $distro
  Desktop/session: $desktop / $session
  Audio: $audio
  Architecture: $arch
  Tier: $tier
  Notes: $notes

  Required host tools:
    - $qemu_system_command
    - qemu-img
    - ssh
    - cloud-localds or equivalent cloud-image-utils package
    - AArch64 targets also need an operator-owned UEFI firmware file for --execute
    - readable and writable /dev/kvm for accelerated local runs

  Host install hints:
    Arch: $(host_install_hint_for_family pacman "$arch")
    Debian/Ubuntu: $(host_install_hint_for_family apt "$arch")
    Fedora: $(host_install_hint_for_family dnf "$arch")
    openSUSE: $(host_install_hint_for_family zypper "$arch")
    Nix shell: $(host_install_hint_for_family nix "$arch")

  Image policy:
    Use an operator-owned ${arch} cloud image for $distro. The helper does not download distro images.

  Render guest assets:
    bash scripts/vm-matrix.sh render-cloud-init --target $id

  Dry-run launch:
    pnpm vm:launch -- --target $id --image /path/to/${id}.qcow2

  Pull evidence after SSH is reachable:
    bash scripts/collect-vm-evidence-ssh.sh --target $id --host 127.0.0.1 --port 2222 --execute

EOF
  done
}

print_plan() {
  each_target | while IFS=$'\t' read -r id distro family desktop session audio arch tier notes; do
    cat <<EOF
Target: $id
  Distro: $distro
  Desktop/session: $desktop / $session
  Audio: $audio
  Architecture: $arch
  Tier: $tier
  Notes: $notes

  Host prerequisites:
    scripts/vm-matrix.sh doctor --target $id

  Guest bootstrap:
    $(guest_bootstrap_command "$family" "$audio")

  Guest validation:
$(print_validation_commands "$family" | sed 's/^/    /')
    $(guest_evidence_command "$family" "$id")

  Host-side evidence pull after guest SSH is reachable:
    bash scripts/collect-vm-evidence-ssh.sh --target $id --host 127.0.0.1 --port 2222 --execute

  Evidence to attach:
    - .vm/evidence/$id/pnpm-check.log
    - .vm/evidence/$id/detect-audio.json
    - .vm/evidence/$id/ct-host-check.log
    - .vm/evidence/$id/autostart.log
    - .vm/evidence/$id/screenshot.png
    - .vm/evidence/$id/notes.md

EOF
  done
}

emit_ssh_plan() {
  local index=0
  local identity_cell
  local desktop_cell
  local port

  echo "# target	host	port	user	identity	desktop_port	screenshot_command	local_output_dir"
  each_target | while IFS=$'\t' read -r id _distro _family _desktop _session _audio _arch _tier _notes; do
    port=$((ssh_plan_start_port + (index * 10)))
    identity_cell="${ssh_plan_identity:-"-"}"
    desktop_cell="${ssh_plan_desktop_port:-"-"}"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t-\t.vm/evidence/%s\n' \
      "$id" "$ssh_plan_host" "$port" "$ssh_plan_user" "$identity_cell" "$desktop_cell" "$id"
    index=$((index + 1))
  done
}

render_ssh_plan() {
  local destination="$1"
  local target_count
  local max_port

  validate_tcp_port "$ssh_plan_start_port" "start port"
  if [ -n "$ssh_plan_desktop_port" ]; then
    validate_tcp_port "$ssh_plan_desktop_port" "desktop port"
  fi

  target_count="$(each_target | wc -l | tr -d ' ')"
  [ "$target_count" -gt 0 ] || fail "target matrix is empty"
  max_port=$((ssh_plan_start_port + ((target_count - 1) * 10)))
  [ "$max_port" -le 65535 ] || fail "start port leaves too few valid ports for $target_count target(s)"

  if [ -n "$destination" ]; then
    mkdir -p "$(dirname "$destination")"
    emit_ssh_plan >"$destination"
    echo "Rendered SSH evidence plan for $target_count target(s) to $destination."
    return 0
  fi

  emit_ssh_plan
}

shell_join() {
  local first="true"
  local arg

  for arg in "$@"; do
    if [ "$first" = "true" ]; then
      first="false"
    else
      printf ' '
    fi

    printf '%q' "$arg"
  done
}

launch_command_cell() {
  local target="$1"
  local image_path="$2"
  local image_format_value="$3"
  local port="$4"
  local memory_value="$5"
  local cpus_value="$6"
  local firmware_value="$7"
  local args=(
    bash
    scripts/vm-matrix.sh
    launch
    --target
    "$target"
    --image
    "$image_path"
    --image-format
    "$image_format_value"
    --ssh-port
    "$port"
    --memory
    "$memory_value"
    --cpus
    "$cpus_value"
  )

  if [ "$firmware_value" != "-" ]; then
    args+=(--firmware "$firmware_value")
  fi

  shell_join "${args[@]}"
}

evidence_pull_command_cell() {
  local target="$1"
  local port="$2"

  shell_join \
    bash \
    scripts/collect-vm-evidence-ssh.sh \
    --target \
    "$target" \
    --host \
    127.0.0.1 \
    --port \
    "$port" \
    --execute
}

emit_launch_plan() {
  local index=0
  local id
  local arch
  local firmware_cell
  local image_path
  local launch_command
  local evidence_command
  local port

  echo "# target	image	image_format	firmware	ssh_port	memory	cpus	launch_command	evidence_pull_command"
  while IFS=$'\t' read -r id _distro _family _desktop _session _audio arch _tier _notes; do
    port=$((ssh_plan_start_port + (index * 10)))
    image_path="${image_root%/}/${id}.${image_format}"
    firmware_cell="-"

    if arch_requires_firmware "$arch" && [ -n "$firmware" ]; then
      firmware_cell="$firmware"
    fi

    launch_command="$(
      launch_command_cell "$id" "$image_path" "$image_format" "$port" "$memory" "$cpus" "$firmware_cell"
    )"
    evidence_command="$(evidence_pull_command_cell "$id" "$port")"

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$id" \
      "$image_path" \
      "$image_format" \
      "$firmware_cell" \
      "$port" \
      "$memory" \
      "$cpus" \
      "$launch_command" \
      "$evidence_command"
    index=$((index + 1))
  done <<EOF
$(each_target)
EOF
}

render_launch_plan() {
  local destination="$1"
  local target_count
  local max_port

  validate_tcp_port "$ssh_plan_start_port" "start port"
  validate_int_range "$memory" "memory" 512 262144
  validate_int_range "$cpus" "CPU count" 1 256
  validate_image_format "$image_format"

  target_count="$(each_target | wc -l | tr -d ' ')"
  [ "$target_count" -gt 0 ] || fail "target matrix is empty"
  max_port=$((ssh_plan_start_port + ((target_count - 1) * 10)))
  [ "$max_port" -le 65535 ] || fail "start port leaves too few valid ports for $target_count target(s)"

  if [ -n "$destination" ]; then
    mkdir -p "$(dirname "$destination")"
    emit_launch_plan >"$destination"
    echo "Rendered launch plan for $target_count target(s) to $destination."
    return 0
  fi

  emit_launch_plan
}

runbook_collect_command_cell() {
  local target="$1"
  local port="$2"
  local evidence_dir="$3"

  shell_join \
    bash \
    scripts/collect-vm-evidence-ssh.sh \
    --target \
    "$target" \
    --host \
    127.0.0.1 \
    --port \
    "$port" \
    --local-output-dir \
    "$evidence_dir" \
    --execute
}

runbook_verify_command_cell() {
  local target="$1"
  local evidence_dir="$2"

  shell_join bash scripts/verify-vm-evidence.sh --target "$target" --evidence-dir "$evidence_dir"
}

runbook_promote_command_cell() {
  local target="$1"

  shell_join pnpm vm:promote-evidence -- --target "$target" --dry-run
}

emit_runbook() {
  local index=0
  local id
  local distro
  local family
  local desktop
  local session
  local audio
  local arch
  local tier
  local notes
  local firmware_cell
  local image_path
  local port
  local evidence_dir
  local launch_command
  local collect_command
  local verify_command
  local promote_command
  local host_setup_command
  local doctor_command
  local cloud_init_command
  local launch_plan_command
  local ssh_plan_command
  local matrix_collect_command
  local final_matrix_collect_command
  local evidence_status_command
  local matrix_promote_command

  if [ -n "${target_filter:-}" ]; then
    host_setup_command="$(shell_join bash scripts/vm-matrix.sh host-setup --target "$target_filter")"
    doctor_command="$(shell_join bash scripts/vm-matrix.sh doctor --target "$target_filter")"
    cloud_init_command="$(shell_join pnpm vm:render-cloud-init -- --target "$target_filter")"
    launch_plan_command="$(
      shell_join \
        pnpm \
        vm:render-launch-plan \
        -- \
        --target \
        "$target_filter" \
        --image-root \
        "$image_root" \
        --start-port \
        "$ssh_plan_start_port"
    )"
    ssh_plan_command="$(
      shell_join \
        pnpm \
        vm:render-ssh-plan \
        -- \
        --target \
        "$target_filter" \
        --start-port \
        "$ssh_plan_start_port" \
        --output \
        .vm/ssh-targets.tsv
    )"
    matrix_collect_command="$(shell_join pnpm vm:collect-matrix -- --plan .vm/ssh-targets.tsv --execute)"
    final_matrix_collect_command="$(
      shell_join \
        pnpm \
        vm:collect-matrix \
        -- \
        --plan \
        .vm/ssh-targets.tsv \
        --published-release-repo \
        sandwichfarm/loopwire \
        --published-release-tag \
        v0.1.0 \
        --release-public-key \
        packaging/release-signing-public.pem \
        --require-published-release \
        --execute
    )"
    evidence_status_command="$(
      shell_join pnpm vm:evidence-status -- --target "$target_filter" --evidence-root "$evidence_root"
    )"
    matrix_promote_command="$(
      shell_join pnpm vm:promote-evidence -- --target "$target_filter" --evidence-root "$evidence_root" --dry-run
    )"
  else
    host_setup_command="$(shell_join bash scripts/vm-matrix.sh host-setup --all)"
    doctor_command="$(shell_join bash scripts/vm-matrix.sh doctor --all)"
    cloud_init_command="$(shell_join pnpm vm:render-cloud-init -- --all)"
    launch_plan_command="$(
      shell_join \
        pnpm \
        vm:render-launch-plan \
        -- \
        --all \
        --image-root \
        "$image_root" \
        --start-port \
        "$ssh_plan_start_port"
    )"
    ssh_plan_command="$(
      shell_join pnpm vm:render-ssh-plan -- --all --start-port "$ssh_plan_start_port" --output .vm/ssh-targets.tsv
    )"
    matrix_collect_command="$(shell_join pnpm vm:collect-matrix -- --plan .vm/ssh-targets.tsv --execute)"
    final_matrix_collect_command="$(
      shell_join \
        pnpm \
        vm:collect-matrix \
        -- \
        --plan \
        .vm/ssh-targets.tsv \
        --published-release-repo \
        sandwichfarm/loopwire \
        --published-release-tag \
        v0.1.0 \
        --release-public-key \
        packaging/release-signing-public.pem \
        --require-published-release \
        --require-all-targets \
        --execute
    )"
    evidence_status_command="$(shell_join pnpm vm:evidence-status -- --all --evidence-root "$evidence_root")"
    matrix_promote_command="$(
      shell_join pnpm vm:promote-evidence -- --all --evidence-root "$evidence_root" --dry-run
    )"
  fi

  cat <<EOF
# Loopwire VM Evidence Runbook

Generated from \`$target_file\`. This runbook is operator-facing and non-mutating until commands with \`--execute\`
are run manually. Distro images, package installation, VM launch, and support-matrix promotion remain operator-owned.

## Matrix Setup

\`\`\`bash
$host_setup_command
$doctor_command
$cloud_init_command
$launch_plan_command
$ssh_plan_command
$matrix_collect_command
# Final-release collection after the signed public GitHub Release exists:
$final_matrix_collect_command
$evidence_status_command
$matrix_promote_command
\`\`\`

## Target Runbooks

EOF

  while IFS=$'\t' read -r id distro family desktop session audio arch tier notes; do
    port=$((ssh_plan_start_port + (index * 10)))
    firmware_cell="-"
    image_path="${image_root%/}/${id}.${image_format}"
    evidence_dir="${evidence_root%/}/${id}"

    if arch_requires_firmware "$arch" && [ -n "$firmware" ]; then
      firmware_cell="$firmware"
    fi

    launch_command="$(
      launch_command_cell "$id" "$image_path" "$image_format" "$port" "$memory" "$cpus" "$firmware_cell"
    )"
    collect_command="$(runbook_collect_command_cell "$id" "$port" "$evidence_dir")"
    verify_command="$(runbook_verify_command_cell "$id" "$evidence_dir")"
    promote_command="$(runbook_promote_command_cell "$id")"

    cat <<EOF
### $id

- Distro: $distro
- Desktop/session: $desktop / $session
- Audio target: $audio
- Architecture: $arch
- Tier: $tier
- Notes: $notes
- Evidence directory: \`$evidence_dir\`

\`\`\`bash
$(shell_join bash scripts/vm-matrix.sh host-setup --target "$id")
$(shell_join bash scripts/vm-matrix.sh doctor --target "$id")
$(shell_join bash scripts/vm-matrix.sh render-cloud-init --target "$id")
$launch_command
$collect_command
$verify_command
$promote_command
\`\`\`

EOF

    if arch_requires_firmware "$arch" && [ -z "$firmware" ]; then
      cat <<EOF
Before adding \`--execute\` for this AArch64 target, append
\`--firmware /path/to/QEMU_EFI.fd\` to the launch command above.

EOF
    fi

    index=$((index + 1))
  done <<EOF
$(each_target)
EOF
}

render_runbook() {
  local destination="$1"
  local target_count
  local max_port

  validate_tcp_port "$ssh_plan_start_port" "start port"
  validate_int_range "$memory" "memory" 512 262144
  validate_int_range "$cpus" "CPU count" 1 256
  validate_image_format "$image_format"

  target_count="$(each_target | wc -l | tr -d ' ')"
  [ "$target_count" -gt 0 ] || fail "target matrix is empty"
  max_port=$((ssh_plan_start_port + ((target_count - 1) * 10)))
  [ "$max_port" -le 65535 ] || fail "start port leaves too few valid ports for $target_count target(s)"

  if [ -n "$destination" ]; then
    mkdir -p "$(dirname "$destination")"
    emit_runbook >"$destination"
    echo "Rendered VM evidence runbook for $target_count target(s) to $destination."
    return 0
  fi

  emit_runbook
}

render_cloud_init() {
  target="$1"
  output_dir="$2"
  row="$(get_target_row "$target")"
  family="$(field "$row" 3)"
  distro="$(field "$row" 2)"
  desktop="$(field "$row" 4)"
  session="$(field "$row" 5)"
  audio="$(field "$row" 6)"

  mkdir -p "$output_dir"

  ssh_key="# paste an operator-owned public key here"
  if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
    ssh_key="$(sed -n '1p' "$HOME/.ssh/id_ed25519.pub")"
  fi

  cat >"$output_dir/user-data" <<EOF
#cloud-config
hostname: loopwire-${target}
users:
  - name: loopwire
    groups: [adm, wheel, sudo]
    shell: /bin/bash
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    ssh_authorized_keys:
      - ${ssh_key}
package_update: false
write_files:
  - path: /etc/loopwire-vm-target
    permissions: "0644"
    content: |
      target=${target}
      distro=${distro}
      desktop=${desktop}
      session=${session}
      audio=${audio}
EOF

  cat >"$output_dir/meta-data" <<EOF
instance-id: loopwire-${target}
local-hostname: loopwire-${target}
EOF

  {
    echo "#!/usr/bin/env bash"
    echo "set -euo pipefail"
    echo "git clone https://github.com/sandwichfarm/loopwire.git"
    echo "cd loopwire"
    guest_bootstrap_command "$family" "$audio"
    print_validation_commands "$family"
    guest_evidence_command "$family" "$target"
  } >"$output_dir/guest-commands.sh"
  chmod 0755 "$output_dir/guest-commands.sh"

  echo "Rendered cloud-init and guest commands under $output_dir"
}

render_all_cloud_init() {
  output_root="$1"

  mkdir -p "$output_root"
  rows | while IFS=$'\t' read -r id _distro _family _desktop _session _audio _arch _tier _notes; do
    render_cloud_init "$id" "$output_root/$id"
  done
}

verify_cloud_init() {
  output_root="$1"
  created_temp="${2:-false}"
  target_count=0

  if [ -n "${target_filter:-}" ]; then
    get_target_row "$target_filter" >/dev/null
    render_cloud_init "$target_filter" "$output_root/$target_filter" >/dev/null
  else
    render_all_cloud_init "$output_root" >/dev/null
  fi

  while IFS=$'\t' read -r id _distro family _desktop _session audio _arch _tier _notes; do
    target_count=$((target_count + 1))
    target_dir="$output_root/$id"
    user_data="$target_dir/user-data"
    meta_data="$target_dir/meta-data"
    guest_commands="$target_dir/guest-commands.sh"

    [ -s "$user_data" ] || fail "$id missing rendered user-data"
    [ -s "$meta_data" ] || fail "$id missing rendered meta-data"
    [ -x "$guest_commands" ] || fail "$id missing executable guest-commands.sh"

    grep -Fq "hostname: loopwire-${id}" "$user_data" || fail "$id user-data missing target hostname"
    grep -Fq "target=${id}" "$user_data" || fail "$id user-data missing target marker"
    grep -Fq "instance-id: loopwire-${id}" "$meta_data" || fail "$id meta-data missing instance id"
    grep -Fq "git clone https://github.com/sandwichfarm/loopwire.git" "$guest_commands" ||
      fail "$id guest commands missing repository clone"
    grep -Fq "pnpm detect:audio" "$guest_commands" || fail "$id guest commands missing backend detection"
    grep -Fq "scripts/collect-vm-evidence.sh --target $id" "$guest_commands" ||
      fail "$id guest commands missing target evidence collection"

    case "$family" in
      apt)
        grep -Fq "pnpm@11.3.0" "$guest_commands" || fail "$id apt guest commands must pin pnpm"
        grep -Fq "libwebkit2gtk-4.1-dev" "$guest_commands" || fail "$id apt guest commands missing WebKitGTK"
        grep -Fq "cargo" "$guest_commands" || fail "$id apt guest commands missing Rust cargo"
        ;;
      nix)
        grep -Fq "nix develop --command" "$guest_commands" || fail "$id nix guest commands must use nix develop"
        ;;
      pacman)
        grep -Fq "pnpm check" "$guest_commands" || fail "$id guest commands missing pnpm check"
        grep -Fq "webkit2gtk-4.1" "$guest_commands" || fail "$id pacman guest commands missing WebKitGTK"
        grep -Fq "rust" "$guest_commands" || fail "$id pacman guest commands missing Rust"
        ;;
      dnf)
        grep -Fq "pnpm check" "$guest_commands" || fail "$id guest commands missing pnpm check"
        grep -Fq "webkit2gtk4.1-devel" "$guest_commands" || fail "$id dnf guest commands missing WebKitGTK"
        grep -Fq "cargo" "$guest_commands" || fail "$id dnf guest commands missing Rust cargo"
        case "$audio" in
          *JACK*)
            grep -Fq "jack-audio-connection-kit" "$guest_commands" ||
              fail "$id dnf JACK guest commands missing JACK package"
            ;;
        esac
        ;;
      zypper)
        grep -Fq "pnpm check" "$guest_commands" || fail "$id guest commands missing pnpm check"
        grep -Fq "pnpm@11.3.0" "$guest_commands" || fail "$id zypper guest commands must pin pnpm"
        grep -Fq "webkit2gtk3-devel" "$guest_commands" || fail "$id zypper guest commands missing WebKitGTK"
        grep -Fq "devel_basis" "$guest_commands" || fail "$id zypper guest commands missing build pattern"
        grep -Fq "cargo" "$guest_commands" || fail "$id zypper guest commands missing Rust cargo"
        ;;
      *)
        fail "$id has unsupported package family: $family"
        ;;
    esac
  done <<EOF
$(each_target)
EOF

  [ "$target_count" -gt 0 ] || fail "no VM targets verified"

  if [ "$created_temp" = "true" ]; then
    echo "Verified rendered cloud-init assets for $target_count VM target(s)."
  else
    echo "Verified rendered cloud-init assets for $target_count VM target(s) under $output_root."
  fi
}

launch_target() {
  target="$1"
  image="$2"
  image_format="$3"
  firmware="$4"
  memory="$5"
  cpus="$6"
  ssh_port="$7"
  execute="$8"
  run_dir="${vm_root}/run/${target}"
  disk="${run_dir}/${target}.qcow2"
  seed="${run_dir}/seed.iso"
  cloud_dir="${run_dir}/cloud-init"
  row="$(get_target_row "$target")"
  arch="$(field "$row" 7)"
  qemu_system_command="$(qemu_system_command_for_arch "$arch")"
  qemu_arch_args=()

  case "$arch" in
    aarch64 | arm64)
      qemu_arch_args=(-machine virt -cpu max)
      if [ -n "$firmware" ]; then
        qemu_arch_args+=(-bios "$firmware")
      fi
      ;;
  esac

  qemu_cmd=(
    "$qemu_system_command"
    "${qemu_arch_args[@]}"
    -enable-kvm
    -m "$memory"
    -smp "$cpus"
    -drive "file=${disk},if=virtio,format=qcow2"
    -drive "file=${seed},if=virtio,format=raw,readonly=on"
    -netdev "user,id=net0,hostfwd=tcp::${ssh_port}-:22"
    -device virtio-net-pci,netdev=net0
    -display gtk
  )

  printf 'Base image: %s\n' "$image"
  printf 'Planned overlay disk: %s\n' "$disk"
  printf 'Planned seed ISO: %s\n' "$seed"
  printf 'Forwarded SSH port: %s\n' "$ssh_port"
  if arch_requires_firmware "$arch"; then
    if [ -n "$firmware" ]; then
      printf 'Firmware: %s\n' "$firmware"
    else
      printf 'Firmware: required for --execute; pass --firmware /path/to/QEMU_EFI.fd\n'
    fi
  fi
  printf 'Launch command:\n'
  printf '  %q' "${qemu_cmd[@]}"
  printf '\n'
  printf 'Evidence pull command:\n'
  printf '  bash scripts/collect-vm-evidence-ssh.sh --target %q --host 127.0.0.1 --port %q --execute\n' \
    "$target" "$ssh_port"

  if [ "$execute" != "true" ]; then
    echo "Dry run complete. Add --execute to render cloud-init, create the overlay/seed, and launch the VM."
    return 0
  fi

  [ -f "$image" ] || fail "image not found: $image"
  if arch_requires_firmware "$arch"; then
    [ -n "$firmware" ] || fail "AArch64 launch requires --firmware /path/to/QEMU_EFI.fd"
    [ -f "$firmware" ] || fail "firmware not found: $firmware"
  elif [ -n "$firmware" ] && [ ! -f "$firmware" ]; then
    fail "firmware not found: $firmware"
  fi
  command -v "$qemu_system_command" >/dev/null 2>&1 || fail "$qemu_system_command is required for launch"
  command -v qemu-img >/dev/null 2>&1 || fail "qemu-img is required for launch"
  command -v cloud-localds >/dev/null 2>&1 ||
    fail "cloud-localds is required for launch; run render-cloud-init for non-launch planning"

  mkdir -p "$run_dir"
  render_cloud_init "$target" "$cloud_dir" >/dev/null

  if [ ! -f "$disk" ]; then
    qemu-img create -f qcow2 -F "$image_format" -b "$image" "$disk" >/dev/null
  fi

  cloud-localds "$seed" "$cloud_dir/user-data" "$cloud_dir/meta-data"
  "${qemu_cmd[@]}"
}

target_filter=""
command="${1:-}"
[ -n "$command" ] || {
  usage
  exit 2
}
shift || true

image=""
image_format="qcow2"
image_root="${LOOPWIRE_VM_IMAGE_ROOT:-${vm_root}/images}"
firmware=""
memory="4096"
cpus="4"
ssh_port="2222"
execute="false"
output_dir=""
all_targets="false"
host_family=""
evidence_root="${LOOPWIRE_VM_EVIDENCE_ROOT:-.vm/evidence}"
require_published_release="false"
ssh_plan_host="127.0.0.1"
ssh_plan_user="loopwire"
ssh_plan_identity=""
ssh_plan_start_port="2222"
ssh_plan_desktop_port=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --)
      shift
      ;;
    --target)
      target_filter="${2:?missing value for --target}"
      shift 2
      ;;
    --all)
      all_targets="true"
      shift
      ;;
    --image)
      image="${2:?missing value for --image}"
      shift 2
      ;;
    --image-format)
      image_format="${2:?missing value for --image-format}"
      shift 2
      ;;
    --image-root)
      image_root="${2:?missing value for --image-root}"
      shift 2
      ;;
    --firmware)
      firmware="${2:?missing value for --firmware}"
      shift 2
      ;;
    --memory)
      memory="${2:?missing value for --memory}"
      shift 2
      ;;
    --cpus)
      cpus="${2:?missing value for --cpus}"
      shift 2
      ;;
    --ssh-port)
      ssh_port="${2:?missing value for --ssh-port}"
      shift 2
      ;;
    --output)
      output_dir="${2:?missing value for --output}"
      shift 2
      ;;
    --evidence-root)
      evidence_root="${2:?missing value for --evidence-root}"
      shift 2
      ;;
    --family)
      host_family="${2:?missing value for --family}"
      shift 2
      ;;
    --require-published-release)
      require_published_release="true"
      shift
      ;;
    --host)
      ssh_plan_host="${2:?missing value for --host}"
      shift 2
      ;;
    --user)
      ssh_plan_user="${2:?missing value for --user}"
      shift 2
      ;;
    --identity)
      ssh_plan_identity="${2:?missing value for --identity}"
      shift 2
      ;;
    --start-port)
      ssh_plan_start_port="${2:?missing value for --start-port}"
      shift 2
      ;;
    --desktop-port)
      ssh_plan_desktop_port="${2:?missing value for --desktop-port}"
      shift 2
      ;;
    --execute)
      execute="true"
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

case "$command" in
  list)
    list_targets
    ;;
  validate)
    validate_targets
    ;;
  host-plan)
    if [ -n "$target_filter" ]; then
      get_target_row "$target_filter" >/dev/null
    fi
    print_host_plan
    ;;
  host-setup)
    [ "$execute" != "true" ] || fail "host-setup is dry-run only; run the printed install command manually"
    if [ "$all_targets" = "true" ] && [ -n "$target_filter" ]; then
      fail "host-setup accepts either --target or --all, not both"
    fi
    if [ -n "$target_filter" ]; then
      get_target_row "$target_filter" >/dev/null
    fi
    print_host_setup "$host_family"
    ;;
  doctor)
    if [ "$all_targets" = "true" ] && [ -n "$target_filter" ]; then
      fail "doctor accepts either --target or --all, not both"
    fi
    if [ -n "$target_filter" ]; then
      get_target_row "$target_filter" >/dev/null
    fi
    doctor
    ;;
  evidence-status)
    if [ -n "$target_filter" ]; then
      get_target_row "$target_filter" >/dev/null
    fi
    evidence_status
    ;;
  plan)
    print_plan
    ;;
  render-ssh-plan)
    if [ "$all_targets" = "true" ] && [ -n "$target_filter" ]; then
      fail "render-ssh-plan accepts either --target or --all, not both"
    fi
    if [ -n "$target_filter" ]; then
      get_target_row "$target_filter" >/dev/null
    fi
    render_ssh_plan "$output_dir"
    ;;
  render-launch-plan)
    if [ "$all_targets" = "true" ] && [ -n "$target_filter" ]; then
      fail "render-launch-plan accepts either --target or --all, not both"
    fi
    if [ -n "$target_filter" ]; then
      get_target_row "$target_filter" >/dev/null
    fi
    render_launch_plan "$output_dir"
    ;;
  render-runbook)
    if [ "$all_targets" = "true" ] && [ -n "$target_filter" ]; then
      fail "render-runbook accepts either --target or --all, not both"
    fi
    if [ -n "$target_filter" ]; then
      get_target_row "$target_filter" >/dev/null
    fi
    render_runbook "$output_dir"
    ;;
  render-cloud-init)
    if [ "$all_targets" = "true" ] && [ -n "$target_filter" ]; then
      fail "render-cloud-init accepts either --target or --all, not both"
    fi

    if [ "$all_targets" = "true" ]; then
      output_dir="${output_dir:-${vm_root}/cloud-init}"
      render_all_cloud_init "$output_dir"
    else
      [ -n "$target_filter" ] || fail "render-cloud-init requires --target or --all"
      output_dir="${output_dir:-${vm_root}/cloud-init/${target_filter}}"
      render_cloud_init "$target_filter" "$output_dir"
    fi
    ;;
  verify-cloud-init)
    [ "$all_targets" != "true" ] || fail "verify-cloud-init verifies all targets by default; omit --all"

    if [ -n "$output_dir" ]; then
      mkdir -p "$output_dir"
      verify_cloud_init "$output_dir" false
    else
      tmp_dir="$(mktemp -d)"
      trap 'rm -rf "$tmp_dir"' EXIT
      verify_cloud_init "$tmp_dir" true
    fi
    ;;
  launch)
    [ -n "$target_filter" ] || fail "launch requires --target"
    [ -n "$image" ] || fail "launch requires --image"
    get_target_row "$target_filter" >/dev/null
    validate_tcp_port "$ssh_port" "SSH port"
    validate_int_range "$memory" "memory" 512 262144
    validate_int_range "$cpus" "CPU count" 1 256
    validate_image_format "$image_format"
    launch_target "$target_filter" "$image" "$image_format" "$firmware" "$memory" "$cpus" "$ssh_port" "$execute"
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
