#!/usr/bin/env bash
set -euo pipefail

target="${1:?target is required}"
package_target="${2:?package target is required}"
format="${3:?package format is required}"
version="${4:?version is required}"
git_head="${5:?git head is required}"
kit_dir="${6:-$PWD}"
proof_dir="$kit_dir/proof"
output_dir="$kit_dir/out"

case "$target" in
  ubuntu-24.04 | debian-13 | fedora-44 | opensuse-tumbleweed) ;;
  *) echo "unsupported VM proof target: $target" >&2; exit 2 ;;
esac
case "$format" in deb | rpm) ;; *) echo "unsupported package format: $format" >&2; exit 2 ;; esac
case "$git_head" in *[!0-9a-f]* | "") echo "git head must be lowercase hexadecimal" >&2; exit 2 ;; esac
[ "${#git_head}" -eq 40 ] || { echo "git head must be 40 characters" >&2; exit 2; }

mkdir -p "$proof_dir" "$output_dir"
find "$output_dir" -mindepth 1 -maxdepth 1 -type f -delete
exec > >(tee "$proof_dir/commands.log") 2>&1
set -x

cat /etc/os-release >"$proof_dir/os-release"
uname -a >"$proof_dir/uname.txt"
systemd-detect-virt --vm >"$proof_dir/virtualization.txt"
grep -Eq '^(kvm|qemu)$' "$proof_dir/virtualization.txt"

case "$target" in
  ubuntu-24.04 | debian-13)
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y dpkg-dev xdotool xz-utils xvfb
    SOURCE_DATE_EPOCH=0 bash "$kit_dir/scripts/build-deb-package.sh" \
      --target "$package_target" \
      --version "$version" \
      --arch x86_64 \
      --release-dir "$kit_dir/release" \
      --output-dir "$output_dir"
    case "$target" in
      ubuntu-24.04) expected_package="loopwire_${version}-1ubuntu24.04_amd64.deb" ;;
      debian-13) expected_package="loopwire_${version}-1debian13_amd64.deb" ;;
    esac
    package="$output_dir/$expected_package"
    [ -f "$package" ]
    [ "$(find "$output_dir" -maxdepth 1 -type f -name '*.deb' | wc -l)" -eq 1 ]
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$package"
    dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\t${Status}\n' loopwire \
      >"$proof_dir/package-metadata.tsv"
    dpkg -L loopwire | sort >"$proof_dir/package-files.txt"
    uninstall_command=(sudo DEBIAN_FRONTEND=noninteractive apt-get remove -y loopwire)
    ;;
  fedora-44)
    sudo dnf install -y rpm-build tar gzip findutils nodejs xdotool xorg-x11-server-Xvfb
    SOURCE_DATE_EPOCH=0 bash "$kit_dir/scripts/build-rpm-package.sh" \
      --target "$package_target" \
      --version "$version" \
      --arch x86_64 \
      --release-dir "$kit_dir/release" \
      --output-dir "$output_dir"
    package="$output_dir/loopwire-${version}-1.fc44.x86_64.rpm"
    [ -f "$package" ]
    [ "$(find "$output_dir" -maxdepth 1 -type f -name '*.rpm' | wc -l)" -eq 1 ]
    sudo dnf install -y "$package"
    rpm -q --qf '%{NAME}\t%{VERSION}-%{RELEASE}\t%{ARCH}\n' loopwire >"$proof_dir/package-metadata.tsv"
    rpm -ql loopwire | sort >"$proof_dir/package-files.txt"
    uninstall_command=(sudo dnf remove -y loopwire)
    ;;
  opensuse-tumbleweed)
    sudo zypper --non-interactive install rpm-build tar gzip findutils nodejs xdotool xorg-x11-server-Xvfb
    SOURCE_DATE_EPOCH=0 bash "$kit_dir/scripts/build-rpm-package.sh" \
      --target "$package_target" \
      --version "$version" \
      --arch x86_64 \
      --release-dir "$kit_dir/release" \
      --output-dir "$output_dir"
    package="$output_dir/loopwire-${version}-1.x86_64.rpm"
    [ -f "$package" ]
    [ "$(find "$output_dir" -maxdepth 1 -type f -name '*.rpm' | wc -l)" -eq 1 ]
    sudo zypper --non-interactive --no-gpg-checks install "$package"
    rpm -q --qf '%{NAME}\t%{VERSION}-%{RELEASE}\t%{ARCH}\n' loopwire >"$proof_dir/package-metadata.tsv"
    rpm -ql loopwire | sort >"$proof_dir/package-files.txt"
    uninstall_command=(sudo zypper --non-interactive remove loopwire)
    ;;
esac

sha256sum "$package" >"$proof_dir/package.sha256"
cp "$package" "$proof_dir/"

for installed_file in \
  /usr/bin/loopwire \
  /usr/bin/loopwire-dsp-provider \
  /usr/bin/loopwire-jack-ports \
  /usr/bin/loopwire-detect-audio \
  /usr/lib/loopwire/loopwire-gui \
  /usr/share/applications/loopwire.desktop; do
  test -e "$installed_file"
done

loopwire --background --help >"$proof_dir/background-help.txt"
loopwire-dsp-provider --help >"$proof_dir/dsp-provider-help.txt"
loopwire-jack-ports --help >"$proof_dir/jack-provider-help.txt"
loopwire-detect-audio --pretty >"$proof_dir/detect-audio.json"
ldd /usr/lib/loopwire/loopwire-gui >"$proof_dir/gui-ldd.txt"
if grep -Fq 'not found' "$proof_dir/gui-ldd.txt"; then
  echo "GUI binary has unresolved shared libraries" >&2
  exit 1
fi

set +e
timeout 30s sh -c '
  proof_dir="$1"
  Xvfb :99 -screen 0 1280x720x24 -nolisten tcp >"$proof_dir/xvfb.log" 2>&1 &
  xvfb_pid=$!
  cleanup() {
    kill "$app_pid" 2>/dev/null || true
    kill "$xvfb_pid" 2>/dev/null || true
  }
  trap cleanup EXIT
  sleep 1
  DISPLAY=:99 GDK_BACKEND=x11 WEBKIT_DISABLE_DMABUF_RENDERER=1 \
    /usr/lib/loopwire/loopwire-gui >"$proof_dir/gui-launch.log" 2>&1 &
  app_pid=$!
  attempt=1
  while [ "$attempt" -le 20 ]; do
    if ! kill -0 "$app_pid" 2>/dev/null; then
      wait "$app_pid"
      exit $?
    fi
    if DISPLAY=:99 xdotool search --name "^(Loopwire|loopwire-gui)$" \
      >"$proof_dir/gui-window-ids.txt" 2>/dev/null; then
      while read -r window_id; do
        DISPLAY=:99 xdotool getwindowname "$window_id"
      done <"$proof_dir/gui-window-ids.txt" >"$proof_dir/gui-window-names.txt"
      exit 0
    fi
    sleep 1
    attempt=$((attempt + 1))
  done
  exit 124
' sh "$proof_dir"
gui_status=$?
set -e
printf '%s\n' "$gui_status" >"$proof_dir/gui-launch-status.txt"
case "$gui_status" in 0) ;; *) cat "$proof_dir/gui-launch.log" >&2; exit 1 ;; esac
[ -s "$proof_dir/gui-window-ids.txt" ]
if grep -Eiq 'error while loading shared libraries|panic|protocol error|missing acquire timeline' \
  "$proof_dir/gui-launch.log"; then
  cat "$proof_dir/gui-launch.log" >&2
  exit 1
fi

"${uninstall_command[@]}"
case "$format" in
  deb) ! dpkg-query -W loopwire >/dev/null 2>&1 ;;
  rpm) ! rpm -q loopwire >/dev/null 2>&1 ;;
esac
for removed_file in \
  /usr/bin/loopwire \
  /usr/bin/loopwire-dsp-provider \
  /usr/bin/loopwire-jack-ports \
  /usr/bin/loopwire-detect-audio \
  /usr/lib/loopwire \
  /usr/share/applications/loopwire.desktop \
  /usr/share/icons/hicolor/scalable/apps/loopwire.svg; do
  test ! -e "$removed_file"
done
printf 'removed\n' >"$proof_dir/uninstall-status.txt"

package_name="$(basename "$package")"
package_sha256="$(awk '{ print $1 }' "$proof_dir/package.sha256")"
cat >"$proof_dir/summary.tsv" <<EOF
schema	loopwire.native-package-vm-proof.v1
target	$target
package_target	$package_target
format	$format
version	$version
git_head	$git_head
package	$package_name
package_sha256	$package_sha256
virtualization	$(cat "$proof_dir/virtualization.txt")
background_help	pass
backend_detection	pass
gui_linkage	pass
gui_launch	pass
uninstall	pass
EOF

set +x
echo "Native package VM proof passed: $target"
