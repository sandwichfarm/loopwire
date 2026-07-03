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
  vm-matrix.sh doctor [--target TARGET]
  vm-matrix.sh plan [--target TARGET]
  vm-matrix.sh render-cloud-init --target TARGET|--all [--output DIR]
  vm-matrix.sh verify-cloud-init [--target TARGET] [--output DIR]
  vm-matrix.sh launch --target TARGET --image IMAGE.qcow2 [--image-format qcow2] [--memory 4096] [--cpus 4] [--ssh-port 2222] [--execute]

Commands are non-mutating unless explicitly noted:
  list               Print supported VM targets.
  validate           Validate target metadata and known package families.
  host-plan          Print host setup, image, render, launch, and evidence handoff instructions.
  doctor             Check local virtualization prerequisites.
  plan               Print guest setup and validation commands for each target.
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
    pacman | apt | dnf | nix)
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
      printf '%s\n' "sudo pacman -Syu --needed git nodejs pnpm pipewire wireplumber pipewire-pulse alsa-utils"
      ;;
    apt)
      cat <<'COMMANDS'
sudo apt-get update
sudo apt-get install -y git nodejs npm pipewire pipewire-pulse pulseaudio-utils alsa-utils
sudo npm install -g pnpm@11.3.0
COMMANDS
      ;;
    dnf)
      jack_package=""
      case "$audio" in
        *JACK*)
          jack_package=" jack-audio-connection-kit"
          ;;
      esac
      printf '%s\n' "sudo dnf install -y git nodejs pnpm pipewire wireplumber pipewire-pulseaudio alsa-utils${jack_package}"
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

host_install_hint() {
  if command -v pacman >/dev/null 2>&1; then
    echo "host-install-hint=$(host_install_hint_for_family pacman)"
  elif command -v apt-get >/dev/null 2>&1; then
    echo "host-install-hint=$(host_install_hint_for_family apt)"
  elif command -v dnf >/dev/null 2>&1; then
    echo "host-install-hint=$(host_install_hint_for_family dnf)"
  elif command -v nix >/dev/null 2>&1; then
    echo "host-install-hint=$(host_install_hint_for_family nix)"
  else
    echo "host-install-hint=install QEMU, qemu-img, cloud-localds/cloud-image-utils, and an OpenSSH client"
  fi
}

host_install_hint_for_family() {
  family="$1"

  case "$family" in
    pacman)
      printf '%s\n' "sudo pacman -Syu --needed qemu-full cloud-image-utils openssh"
      ;;
    apt)
      printf '%s\n' "sudo apt-get install -y qemu-system qemu-utils cloud-image-utils openssh-client"
      ;;
    dnf)
      printf '%s\n' "sudo dnf install -y qemu-kvm qemu-img cloud-utils openssh-clients"
      ;;
    nix)
      printf '%s\n' "nix shell nixpkgs#qemu_kvm nixpkgs#cloud-utils nixpkgs#openssh"
      ;;
    *)
      fail "unsupported host package family: $family"
      ;;
  esac
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
  missing=0
  qemu_system_command="qemu-system-x86_64"

  if [ -n "${target_filter:-}" ]; then
    row="$(get_target_row "$target_filter")"
    distro="$(field "$row" 2)"
    family="$(field "$row" 3)"
    desktop="$(field "$row" 4)"
    session="$(field "$row" 5)"
    audio="$(field "$row" 6)"
    arch="$(field "$row" 7)"
    qemu_system_command="$(qemu_system_command_for_arch "$arch")"

    echo "target=$target_filter"
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

  host_install_hint

  if [ -n "${target_filter:-}" ]; then
    echo "guest-bootstrap=$(guest_bootstrap_command "$family" "$audio" | tr '\n' ';' | sed 's/;$//')"
    echo "guest-evidence-command=$(guest_evidence_command "$family" "$target_filter")"
    echo "host-pull-command=bash scripts/collect-vm-evidence-ssh.sh --target $target_filter --host 127.0.0.1 --port 2222 --execute"
  fi

  [ "$missing" -eq 0 ] || exit 1
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

  case "$port" in
    "" | *[!0-9]*)
      fail "SSH port must be a number from 1 to 65535"
      ;;
  esac

  if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    fail "SSH port must be a number from 1 to 65535"
  fi
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
    - readable and writable /dev/kvm for accelerated local runs

  Host install hints:
    Arch: $(host_install_hint_for_family pacman)
    Debian/Ubuntu: $(host_install_hint_for_family apt)
    Fedora: $(host_install_hint_for_family dnf)
    Nix shell: $(host_install_hint_for_family nix)

  Image policy:
    Use an operator-owned ${arch} cloud image for $distro. The helper does not download distro images.

  Render guest assets:
    bash scripts/vm-matrix.sh render-cloud-init --target $id

  Dry-run launch:
    bash scripts/vm-matrix.sh launch --target $id --image /path/to/${id}.qcow2

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

  while IFS=$'\t' read -r id _distro family _desktop _session _audio _arch _tier _notes; do
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
        ;;
      nix)
        grep -Fq "nix develop --command" "$guest_commands" || fail "$id nix guest commands must use nix develop"
        ;;
      pacman | dnf)
        grep -Fq "pnpm check" "$guest_commands" || fail "$id guest commands missing pnpm check"
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
  memory="$4"
  cpus="$5"
  ssh_port="$6"
  execute="$7"
  run_dir="${vm_root}/run/${target}"
  disk="${run_dir}/${target}.qcow2"
  seed="${run_dir}/seed.iso"
  cloud_dir="${run_dir}/cloud-init"
  row="$(get_target_row "$target")"
  arch="$(field "$row" 7)"
  qemu_system_command="$(qemu_system_command_for_arch "$arch")"

  qemu_cmd=(
    "$qemu_system_command"
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
memory="4096"
cpus="4"
ssh_port="2222"
execute="false"
output_dir=""
all_targets="false"

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
  doctor)
    if [ -n "$target_filter" ]; then
      get_target_row "$target_filter" >/dev/null
    fi
    doctor
    ;;
  plan)
    print_plan
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
    validate_tcp_port "$ssh_port"
    launch_target "$target_filter" "$image" "$image_format" "$memory" "$cpus" "$ssh_port" "$execute"
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
