#!/usr/bin/env bash
set -euo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
manifest="${LOOPWIRE_NATIVE_VM_TARGETS:-packaging/vm/native-package-targets.tsv}"
vm_root="${LOOPWIRE_NATIVE_VM_ROOT:-.vm/native-packages}"
image_root="$vm_root"
proof_kind="native"
qemu_image="${LOOPWIRE_QEMU_IMAGE:-loopwire-native-package-qemu:ubuntu-24.04}"
ssh_user="loopwire"
active_vm_container=""
active_vm_console=""

usage() {
  cat <<'USAGE'
Build and verify Loopwire packages inside matching KVM/QEMU distro guests.

Usage:
  native-package-vm.sh list
  native-package-vm.sh download --target TARGET
  native-package-vm.sh download-all
  native-package-vm.sh run --target TARGET --version VERSION --release-dir DIR
  native-package-vm.sh run-all --version VERSION --release-dir DIR
  native-package-vm.sh verify --target TARGET [--git-head COMMIT]
  native-package-vm.sh verify-all [--git-head COMMIT]
  native-package-vm.sh run-apt --target ubuntu-24.04|debian-13 --version VERSION --release-dir DIR
  native-package-vm.sh verify-apt --target ubuntu-24.04|debian-13 [--git-head COMMIT]

Environment:
  LOOPWIRE_NATIVE_VM_ROOT      Cache/run/evidence root (default: .vm/native-packages)
  LOOPWIRE_APT_VM_ROOT         APT run/evidence root (default: .vm/apt-repository)
  LOOPWIRE_NATIVE_VM_TARGETS   Target manifest override
  LOOPWIRE_QEMU_IMAGE          Docker QEMU tool image tag

The host needs Docker, OpenSSH, /dev/kvm access, and enough disk for the official
cloud images. Containers only provide QEMU tools; every proof is collected from
a separately booted guest kernel. APT proofs use verify-apt-repository-vm-proof.mjs;
the original native-package proofs use verify-native-package-vm-proof.mjs.
USAGE
}

fail() {
  echo "native-package-vm: $*" >&2
  exit 1
}

cleanup_active_vm() {
  if [ -n "$active_vm_container" ]; then
    if [ -n "$active_vm_console" ]; then
      docker logs "$active_vm_container" >"$active_vm_console" 2>&1 || true
    fi
    docker rm -f "$active_vm_container" >/dev/null 2>&1 || true
  fi
}

rows() {
  [ -f "$manifest" ] || fail "missing target manifest: $manifest"
  grep -vE '^[[:space:]]*(#|$)' "$manifest"
}

target_row() {
  local selected="$1"
  rows | awk -F '\t' -v id="$selected" '$1 == id { print; count++ } END { if (count != 1) exit 1 }' ||
    fail "target must occur exactly once in manifest: $selected"
}

target_ids() {
  rows | awk -F '\t' '{ print $1 }'
}

validate_target_value() {
  case "$1" in
    ubuntu-24.04 | debian-13 | fedora-44 | opensuse-tumbleweed) ;;
    *) fail "unsupported target: $1" ;;
  esac
}

require_host() {
  local command
  for command in curl docker node scp sha256sum sha512sum ssh ssh-keygen tar; do
    command -v "$command" >/dev/null 2>&1 || fail "$command is required"
  done
  [ -e /dev/kvm ] || fail "/dev/kvm is missing"
  [ -r /dev/kvm ] && [ -w /dev/kvm ] || fail "/dev/kvm is not readable and writable"
  docker info >/dev/null 2>&1 || fail "docker daemon is unavailable"
}

validate_manifest() {
  local count=0 seen="" id distro package_target format image_url algorithm checksum port firmware extra
  while IFS=$'\t' read -r id distro package_target format image_url algorithm checksum port firmware extra; do
    count=$((count + 1))
    [ -z "$extra" ] || fail "$id manifest row has extra fields"
    validate_target_value "$id"
    [ "$package_target" = "$id" ] || fail "$id package target must match its id"
    case "$format" in deb | rpm) ;; *) fail "$id has invalid format: $format" ;; esac
    case "$image_url" in https://*) ;; *) fail "$id image URL must use HTTPS" ;; esac
    case "$algorithm" in sha256) [ "${#checksum}" -eq 64 ] ;; sha512) [ "${#checksum}" -eq 128 ] ;;
      *) fail "$id has unsupported checksum algorithm: $algorithm" ;;
    esac || fail "$id has invalid $algorithm checksum"
    case "$checksum" in *[!0-9a-f]*) fail "$id checksum must be lowercase hexadecimal" ;; esac
    case "$port" in *[!0-9]* | "") fail "$id has invalid SSH port" ;; esac
    [ "$port" -ge 1024 ] && [ "$port" -le 65535 ] || fail "$id SSH port is out of range"
    [ "$firmware" = "bios" ] || fail "$id has unsupported firmware mode: $firmware"
    case " $seen " in *" $id "*) fail "duplicate target id: $id" ;; esac
    seen="$seen $id"
  done < <(rows)
  [ "$count" -eq 4 ] || fail "expected four native package VM targets, found $count"
}

checksum_file() {
  local algorithm="$1" path="$2"
  case "$algorithm" in
    sha256) sha256sum "$path" | awk '{ print $1 }' ;;
    sha512) sha512sum "$path" | awk '{ print $1 }' ;;
  esac
}

image_path_for() {
  local id="$1" url="$2"
  local suffix="${url##*.}"
  case "$suffix" in img | qcow2) ;; *) suffix="qcow2" ;; esac
  printf '%s/images/%s.%s\n' "$image_root" "$id" "$suffix"
}

download_target() {
  local selected="$1" row id distro package_target format image_url algorithm checksum port firmware
  validate_target_value "$selected"
  row="$(target_row "$selected")"
  IFS=$'\t' read -r id distro package_target format image_url algorithm checksum port firmware <<<"$row"
  local image_path partial actual
  image_path="$(image_path_for "$id" "$image_url")"
  mkdir -p "$(dirname "$image_path")"
  if [ -f "$image_path" ]; then
    actual="$(checksum_file "$algorithm" "$image_path")"
    if [ "$actual" = "$checksum" ]; then
      echo "Verified cached image: $id ($image_path)"
      return
    fi
    fail "cached image checksum mismatch for $id; remove $image_path before retrying"
  fi
  partial="${image_path}.partial"
  rm -f "$partial"
  echo "Downloading official image: $distro"
  curl --fail --location --proto '=https' --tlsv1.2 --retry 3 --output "$partial" "$image_url"
  actual="$(checksum_file "$algorithm" "$partial")"
  [ "$actual" = "$checksum" ] || {
    rm -f "$partial"
    fail "$algorithm checksum mismatch for downloaded $id image"
  }
  mv "$partial" "$image_path"
  echo "Downloaded and verified: $image_path"
}

ensure_qemu_image() {
  if ! docker image inspect "$qemu_image" >/dev/null 2>&1; then
    docker build --file packaging/vm/Dockerfile.qemu --tag "$qemu_image" .
  fi
}

ensure_ssh_key() {
  local key="$vm_root/ssh/id_ed25519"
  if [ ! -f "$key" ]; then
    mkdir -p "$(dirname "$key")"
    ssh-keygen -q -t ed25519 -N '' -C 'loopwire-native-package-vm' -f "$key"
  fi
  chmod 0600 "$key"
  printf '%s\n' "$key"
}

write_cloud_init() {
  local target_dir="$1" public_key="$2" id="$3"
  cat >"$target_dir/user-data" <<EOF
#cloud-config
users:
  - default
  - name: $ssh_user
    groups: [adm, sudo, wheel]
    shell: /bin/bash
    lock_passwd: true
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - $public_key
ssh_pwauth: false
disable_root: true
package_update: false
runcmd:
  - [sh, -c, 'mkdir -p /var/lib/cloud/instance && touch /var/lib/cloud/instance/loopwire-ready']
EOF
  cat >"$target_dir/meta-data" <<EOF
instance-id: loopwire-native-$id
local-hostname: loopwire-$id
EOF
}

ssh_args_for() {
  local key="$1" port="$2" known_hosts="$3"
  printf '%s\0' \
    -i "$key" \
    -p "$port" \
    -o BatchMode=yes \
    -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=accept-new \
    -o "UserKnownHostsFile=$known_hosts" \
    -o LogLevel=ERROR \
    -o ConnectTimeout=5
}

wait_for_guest() {
  local key="$1" port="$2" known_hosts="$3" container="$4" attempt
  local -a ssh_args=()
  mapfile -d '' -t ssh_args < <(ssh_args_for "$key" "$port" "$known_hosts")
  for attempt in $(seq 1 120); do
    if [ "$(docker inspect --format '{{.State.Running}}' "$container" 2>/dev/null || true)" != "true" ]; then
      echo "Guest container exited before SSH became ready: $container" >&2
      return 1
    fi
    if ssh "${ssh_args[@]}" "$ssh_user@127.0.0.1" \
      'test -f /var/lib/cloud/instance/loopwire-ready' >/dev/null 2>&1; then
      echo "Guest SSH and cloud-init are ready after attempt $attempt."
      return
    fi
    if [ $((attempt % 12)) -eq 0 ]; then
      echo "Waiting for guest readiness: attempt $attempt/120"
    fi
    sleep 5
  done
  return 1
}

copy_to_guest() {
  local key="$1" port="$2" known_hosts="$3" source="$4" destination="$5"
  scp -q -r -i "$key" -P "$port" \
    -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new \
    -o "UserKnownHostsFile=$known_hosts" -o LogLevel=ERROR \
    "$source" "$ssh_user@127.0.0.1:$destination"
}

require_committed_implementation() {
  git diff --quiet -- . ':!.playwright-mcp' || fail "tracked changes must be committed before VM proof"
  git diff --cached --quiet -- . ':!.playwright-mcp' || fail "staged changes must be committed before VM proof"
  if git status --porcelain --untracked-files=all | awk '{ print $2 }' |
    grep -v '^\.playwright-mcp/' | grep -q .; then
    fail "untracked implementation files must be committed before VM proof"
  fi
}

run_target() {
  local selected="$1" version="$2" release_dir="$3"
  validate_target_value "$selected"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.+~_-][0-9A-Za-z.+~_-]+)?$ ]] ||
    fail "version must be SemVer-compatible package text"
  [ -d "$release_dir" ] || fail "release directory does not exist: $release_dir"
  [ -f "$release_dir/loopwire-linux-x86_64.tar.gz" ] || fail "release tarball is missing"
  [ -f "$release_dir/SHA256SUMS" ] || fail "release checksum manifest is missing"
  require_host
  require_committed_implementation
  download_target "$selected"
  ensure_qemu_image

  local row id distro package_target format image_url algorithm checksum port firmware
  row="$(target_row "$selected")"
  IFS=$'\t' read -r id distro package_target format image_url algorithm checksum port firmware <<<"$row"
  local git_head image_path target_dir evidence_parent evidence_dir key public_key container base_format known_hosts
  git_head="$(git rev-parse HEAD)"
  image_path="$(realpath "$(image_path_for "$id" "$image_url")")"
  release_dir="$(realpath "$release_dir")"
  target_dir="$(realpath -m "$vm_root/run/$id")"
  evidence_parent="$(realpath -m "$vm_root/evidence/$id")"
  evidence_dir="$evidence_parent/$git_head"
  container="loopwire-native-$id"
  if [ "$proof_kind" = "apt" ]; then
    container="loopwire-apt-$id"
    port=$((port + 10))
  fi
  key="$(ensure_ssh_key)"
  public_key="$(cat "${key}.pub")"
  known_hosts="$target_dir/known_hosts"

  rm -rf "$target_dir" "$evidence_dir"
  mkdir -p "$target_dir/kit/release" "$evidence_parent"
  : >"$known_hosts"
  chmod 0600 "$known_hosts"
  git archive --format=tar HEAD | tar -xf - -C "$target_dir/kit"
  cp "$release_dir/loopwire-linux-x86_64.tar.gz" "$target_dir/kit/release/"
  cp "$release_dir/SHA256SUMS" "$target_dir/kit/release/"
  write_cloud_init "$target_dir" "$public_key" "$id"

  docker run --rm -v "$target_dir:/vm" "$qemu_image" \
    cloud-localds /vm/seed.img /vm/user-data /vm/meta-data
  base_format="$(docker run --rm -v "$image_path:/base.img:ro" "$qemu_image" \
    qemu-img info --output=json /base.img | node -e \
    "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>console.log(JSON.parse(s).format))")"
  [ -n "$base_format" ] || fail "could not determine the base image format for $id"
  docker run --rm -v "$target_dir:/vm" -v "$image_path:/base.img:ro" "$qemu_image" \
    qemu-img create -f qcow2 -F "$base_format" -b /base.img /vm/overlay.qcow2 24G >/dev/null

  docker rm -f "$container" >/dev/null 2>&1 || true
  docker run --detach --name "$container" --device /dev/kvm --network host \
    -v "$target_dir:/vm" -v "$image_path:/base.img:ro" "$qemu_image" \
    qemu-system-x86_64 \
      -machine accel=kvm -cpu host -smp 4 -m 4096 \
      -nographic -serial mon:stdio -no-reboot \
      -drive file=/vm/overlay.qcow2,if=virtio,format=qcow2 \
      -drive file=/vm/seed.img,if=virtio,format=raw,readonly=on \
      -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:${port}-:22" \
      -device virtio-net-pci,netdev=net0 >/dev/null

  active_vm_container="$container"
  active_vm_console="$target_dir/console.log"
  trap cleanup_active_vm EXIT INT TERM

  if ! wait_for_guest "$key" "$port" "$known_hosts" "$container"; then
    fail "$id guest did not become ready; inspect $target_dir/console.log"
  fi
  local -a ssh_args=()
  mapfile -d '' -t ssh_args < <(ssh_args_for "$key" "$port" "$known_hosts")
  ssh "${ssh_args[@]}" "$ssh_user@127.0.0.1" 'rm -rf /home/loopwire/loopwire-native-kit'
  copy_to_guest "$key" "$port" "$known_hosts" "$target_dir/kit" '/home/loopwire/loopwire-native-kit'
  local guest_script="packaging/vm/guest-native-package-smoke.sh"
  local verifier="scripts/verify-native-package-vm-proof.mjs"
  if [ "$proof_kind" = "apt" ]; then
    guest_script="packaging/vm/guest-apt-repository-smoke.sh"
    verifier="scripts/verify-apt-repository-vm-proof.mjs"
  fi
  local guest_status=0
  # Script paths are fixed and all client-expanded arguments are validated above.
  # shellcheck disable=SC2029
  ssh "${ssh_args[@]}" "$ssh_user@127.0.0.1" \
    "cd /home/loopwire/loopwire-native-kit && bash '$guest_script' '$id' '$package_target' '$format' '$version' '$git_head' \"\$PWD\"" || guest_status=$?
  mkdir -p "$evidence_dir"
  ssh "${ssh_args[@]}" "$ssh_user@127.0.0.1" \
    'tar -C /home/loopwire/loopwire-native-kit/proof -cf - .' | tar -xf - -C "$evidence_dir"
  docker logs "$container" >"$evidence_dir/console.log" 2>&1 || true
  printf '%s\n' "$git_head" >"$evidence_dir/git-head.txt"
  printf '%s\t%s\n' \
    schema loopwire.native-package-image.v1 \
    target "$id" \
    distro "$distro" \
    url "$image_url" \
    checksum_algorithm "$algorithm" \
    checksum "$checksum" \
    actual_checksum "$(checksum_file "$algorithm" "$image_path")" \
    firmware "$firmware" >"$evidence_dir/image.tsv"
  [ "$guest_status" -eq 0 ] || fail "$id guest smoke failed ($guest_status); evidence: $evidence_dir"
  node "$verifier" \
    --target "$id" --evidence-dir "$evidence_dir" --git-head "$git_head"
  cleanup_active_vm
  active_vm_container=""
  active_vm_console=""
  trap - EXIT INT TERM
  local proof_label="native package"
  [ "$proof_kind" != "apt" ] || proof_label="APT repository lifecycle"
  echo "Verified $proof_label in matching KVM guest: $id"
  echo "Evidence: $evidence_dir"
}

verify_target() {
  local selected="$1" git_head="$2"
  validate_target_value "$selected"
  [ -n "$git_head" ] || git_head="$(git rev-parse HEAD)"
  local verifier="scripts/verify-native-package-vm-proof.mjs"
  [ "$proof_kind" != "apt" ] || verifier="scripts/verify-apt-repository-vm-proof.mjs"
  node "$verifier" \
    --target "$selected" --evidence-dir "$vm_root/evidence/$selected/$git_head" --git-head "$git_head"
}

[ -n "$root" ] || fail "run from inside the Loopwire git repository"
cd "$root"
validate_manifest

if [ "${1:-}" = "--" ]; then
  shift
fi
command="${1:-}"
[ -n "$command" ] || { usage; exit 2; }
shift
selected=""
version=""
release_dir=""
git_head=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --) shift ;;
    --target) selected="${2:?missing value for --target}"; shift 2 ;;
    --version) version="${2:?missing value for --version}"; shift 2 ;;
    --release-dir) release_dir="${2:?missing value for --release-dir}"; shift 2 ;;
    --git-head) git_head="${2:?missing value for --git-head}"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

case "$command" in
  run-apt | verify-apt)
    case "$selected" in ubuntu-24.04 | debian-13) ;; *) fail "$command requires an Ubuntu 24.04 or Debian 13 target" ;; esac
    proof_kind="apt"
    vm_root="${LOOPWIRE_APT_VM_ROOT:-.vm/apt-repository}"
    [ "$(realpath -m "$vm_root")" != "$(realpath -m "$image_root")" ] ||
      fail "APT VM state must use a different root from native-package state"
    ;;
esac

case "$command" in
  list)
    printf '%-22s %-24s %-5s %-5s\n' TARGET DISTRO TYPE PORT
    while IFS=$'\t' read -r id distro _package_target format _url _algorithm _checksum port _firmware; do
      printf '%-22s %-24s %-5s %-5s\n' "$id" "$distro" "$format" "$port"
    done < <(rows)
    ;;
  download)
    [ -n "$selected" ] || fail "download requires --target"
    require_host
    download_target "$selected"
    ;;
  download-all)
    require_host
    while read -r id; do download_target "$id"; done < <(target_ids)
    ;;
  run | run-apt)
    [ -n "$selected" ] || fail "run requires --target"
    [ -n "$version" ] || fail "run requires --version"
    [ -n "$release_dir" ] || fail "run requires --release-dir"
    run_target "$selected" "$version" "$release_dir"
    ;;
  run-all)
    [ -n "$version" ] || fail "run-all requires --version"
    [ -n "$release_dir" ] || fail "run-all requires --release-dir"
    while read -r id; do run_target "$id" "$version" "$release_dir"; done < <(target_ids)
    ;;
  verify | verify-apt)
    [ -n "$selected" ] || fail "verify requires --target"
    verify_target "$selected" "$git_head"
    ;;
  verify-all)
    [ -n "$git_head" ] || git_head="$(git rev-parse HEAD)"
    while read -r id; do verify_target "$id" "$git_head"; done < <(target_ids)
    ;;
  -h | --help) usage ;;
  *) usage >&2; fail "unknown command: $command" ;;
esac
