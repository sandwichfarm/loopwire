#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "verify-native-packaging: $*" >&2
  exit 1
}

for command in cmp node sha256sum tar; do
  command -v "$command" >/dev/null 2>&1 || fail "$command is required"
done

root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$root" ] || fail "run from inside the Loopwire git repository"
cd "$root"

case "$(uname -m)" in
  x86_64 | amd64) ;;
  *)
    echo "Native package build smoke skipped: target matrix is x86_64 and this host is $(uname -m)."
    exit 0
    ;;
esac

tmp_dir="$(mktemp -d)"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT

release_dir="$tmp_dir/release"
payload="$tmp_dir/payload"
mkdir -p \
  "$release_dir" \
  "$payload/libexec/loopwire/scripts" \
  "$payload/libexec/loopwire/packages/core/dist" \
  "$payload/libexec/loopwire/packages/audio-host/dist"

for launcher in loopwire loopwire-dsp-provider loopwire-jack-ports loopwire-detect-audio; do
  printf '#!/bin/sh\nexit 0\n' >"$payload/$launcher"
  chmod 0755 "$payload/$launcher"
done
printf '#!/bin/sh\nexit 0\n' >"$payload/libexec/loopwire/loopwire-gui"
chmod 0755 "$payload/libexec/loopwire/loopwire-gui"
printf 'export {};\n' >"$payload/libexec/loopwire/scripts/restore-background.mjs"
printf 'export {};\n' >"$payload/libexec/loopwire/scripts/detect-audio-backends.mjs"
printf 'export {};\n' >"$payload/libexec/loopwire/packages/core/dist/index.js"
printf 'export {};\n' >"$payload/libexec/loopwire/packages/audio-host/dist/index.js"
printf '%s\n' '{"private":true,"type":"module"}' >"$payload/libexec/loopwire/package.json"
printf 'name=loopwire\nversion=0.1.0\narchitecture=x86_64\n' >"$payload/RELEASE"
find "$payload" -print0 | xargs -0 touch -h -d '@1700000000'
tar --sort=name --mtime='@1700000000' --owner=0 --group=0 --numeric-owner \
  -C "$payload" -czf "$release_dir/loopwire-linux-x86_64.tar.gz" \
  RELEASE loopwire loopwire-dsp-provider loopwire-jack-ports loopwire-detect-audio libexec
(
  cd "$release_dir"
  sha256sum loopwire-linux-x86_64.tar.gz >SHA256SUMS
)

if command -v dpkg-deb >/dev/null 2>&1; then
  for pass in first second; do
    output="$tmp_dir/$pass"
    SOURCE_DATE_EPOCH=1700000000 bash scripts/build-deb-package.sh \
      --target ubuntu-24.04 --version 0.1.0 --arch x86_64 \
      --release-dir "$release_dir" --output-dir "$output" >/dev/null
    SOURCE_DATE_EPOCH=1700000000 bash scripts/build-deb-package.sh \
      --target debian-13 --version 0.1.0 --arch x86_64 \
      --release-dir "$release_dir" --output-dir "$output" >/dev/null
  done
else
  command -v docker >/dev/null 2>&1 || fail "dpkg-deb or docker is required"
  docker run --rm \
    -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    -v "$root:/src:ro" -v "$tmp_dir:/work" -w /src ubuntu:24.04 bash -lc '
      set -euo pipefail
      apt-get update >/dev/null
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends dpkg-dev xz-utils >/dev/null
      for pass in first second; do
        for target in ubuntu-24.04 debian-13; do
          SOURCE_DATE_EPOCH=1700000000 bash scripts/build-deb-package.sh \
            --target "$target" --version 0.1.0 --arch x86_64 \
            --release-dir /work/release --output-dir "/work/$pass" >/dev/null
        done
      done
      chown -R "$HOST_UID:$HOST_GID" /work
    '
fi

if command -v rpm >/dev/null 2>&1 && command -v rpmbuild >/dev/null 2>&1; then
  for pass in first second; do
    output="$tmp_dir/$pass"
    SOURCE_DATE_EPOCH=1700000000 bash scripts/build-rpm-package.sh \
      --target fedora-44 --version 0.1.0 --arch x86_64 \
      --release-dir "$release_dir" --output-dir "$output" >/dev/null
    SOURCE_DATE_EPOCH=1700000000 bash scripts/build-rpm-package.sh \
      --target opensuse-tumbleweed --version 0.1.0 --arch x86_64 \
      --release-dir "$release_dir" --output-dir "$output" >/dev/null
  done
else
  command -v docker >/dev/null 2>&1 || fail "rpmbuild/rpm or docker is required"
  docker run --rm \
    -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    -v "$root:/src:ro" -v "$tmp_dir:/work" -w /src fedora:44 bash -lc '
      set -euo pipefail
      dnf install -y rpm-build tar gzip findutils >/dev/null
      for pass in first second; do
        for target in fedora-44 opensuse-tumbleweed; do
          SOURCE_DATE_EPOCH=1700000000 bash scripts/build-rpm-package.sh \
            --target "$target" --version 0.1.0 --arch x86_64 \
            --release-dir /work/release --output-dir "/work/$pass" >/dev/null
        done
      done
      chown -R "$HOST_UID:$HOST_GID" /work
    '
fi

for package in \
  loopwire_0.1.0-1ubuntu24.04_amd64.deb \
  loopwire_0.1.0-1debian13_amd64.deb \
  loopwire-0.1.0-1.fc44.x86_64.rpm \
  loopwire-0.1.0-1.x86_64.rpm; do
  [ -f "$tmp_dir/first/$package" ] || fail "missing expected package: $package"
  cmp "$tmp_dir/first/$package" "$tmp_dir/second/$package" >/dev/null ||
    fail "package is not reproducible: $package"
done

if command -v dpkg-deb >/dev/null 2>&1; then
  ubuntu_version="$(dpkg-deb -f "$tmp_dir/first/loopwire_0.1.0-1ubuntu24.04_amd64.deb" Version)"
  debian_version="$(dpkg-deb -f "$tmp_dir/first/loopwire_0.1.0-1debian13_amd64.deb" Version)"
else
  readarray -t deb_versions < <(docker run --rm -v "$tmp_dir:/work:ro" ubuntu:24.04 bash -lc '
    dpkg-deb -f /work/first/loopwire_0.1.0-1ubuntu24.04_amd64.deb Version
    dpkg-deb -f /work/first/loopwire_0.1.0-1debian13_amd64.deb Version
  ')
  ubuntu_version="${deb_versions[0]}"
  debian_version="${deb_versions[1]}"
fi
[ "$ubuntu_version" = "0.1.0-1ubuntu24.04" ] || fail "Ubuntu package version mismatch"
[ "$debian_version" = "0.1.0-1debian13" ] || fail "Debian package version mismatch"

if command -v rpm >/dev/null 2>&1; then
  fedora_version="$(rpm -qp --qf '%{VERSION}-%{RELEASE}\n' "$tmp_dir/first/loopwire-0.1.0-1.fc44.x86_64.rpm")"
  opensuse_version="$(rpm -qp --qf '%{VERSION}-%{RELEASE}\n' "$tmp_dir/first/loopwire-0.1.0-1.x86_64.rpm")"
else
  readarray -t rpm_versions < <(docker run --rm -v "$tmp_dir:/work:ro" fedora:44 bash -lc '
    rpm -qp --qf "%{VERSION}-%{RELEASE}\\n" /work/first/loopwire-0.1.0-1.fc44.x86_64.rpm
    rpm -qp --qf "%{VERSION}-%{RELEASE}\\n" /work/first/loopwire-0.1.0-1.x86_64.rpm
  ')
  fedora_version="${rpm_versions[0]}"
  opensuse_version="${rpm_versions[1]}"
fi
[ "$fedora_version" = "0.1.0-1.fc44" ] || fail "Fedora package version mismatch"
[ "$opensuse_version" = "0.1.0-1" ] || fail "openSUSE package version mismatch"

duplicate_release="$tmp_dir/duplicate-release"
cp -R "$release_dir" "$duplicate_release"
cat "$release_dir/SHA256SUMS" >>"$duplicate_release/SHA256SUMS"
set +e
if command -v dpkg-deb >/dev/null 2>&1; then
  duplicate_deb_output="$(bash scripts/build-deb-package.sh \
    --target ubuntu-24.04 --version 0.1.0 --arch x86_64 \
    --release-dir "$duplicate_release" --output-dir "$tmp_dir/rejected" 2>&1)"
  duplicate_deb_status=$?
else
  duplicate_deb_output="$(docker run --rm -v "$root:/src:ro" -v "$tmp_dir:/work" -w /src \
    ubuntu:24.04 bash -lc '
      set -euo pipefail
      apt-get update >/dev/null
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends dpkg-dev xz-utils >/dev/null
      bash scripts/build-deb-package.sh --target ubuntu-24.04 --version 0.1.0 --arch x86_64 \
        --release-dir /work/duplicate-release --output-dir /work/rejected
    ' 2>&1)"
  duplicate_deb_status=$?
fi
set -e
[ "$duplicate_deb_status" -ne 0 ] ||
  fail "Debian builder accepted duplicate checksum entries"
printf '%s\n' "$duplicate_deb_output" | grep -Fq 'exactly one entry' ||
  fail "Debian duplicate-checksum test failed for the wrong reason"

set +e
if command -v rpm >/dev/null 2>&1 && command -v rpmbuild >/dev/null 2>&1; then
  duplicate_rpm_output="$(bash scripts/build-rpm-package.sh \
    --target fedora-44 --version 0.1.0 --arch x86_64 \
    --release-dir "$duplicate_release" --output-dir "$tmp_dir/rejected" 2>&1)"
  duplicate_rpm_status=$?
else
  duplicate_rpm_output="$(docker run --rm -v "$root:/src:ro" -v "$tmp_dir:/work" -w /src \
    fedora:44 bash -lc '
      set -euo pipefail
      dnf install -y rpm-build tar gzip findutils >/dev/null
      bash scripts/build-rpm-package.sh --target fedora-44 --version 0.1.0 --arch x86_64 \
        --release-dir /work/duplicate-release --output-dir /work/rejected
    ' 2>&1)"
  duplicate_rpm_status=$?
fi
set -e
[ "$duplicate_rpm_status" -ne 0 ] ||
  fail "RPM builder accepted duplicate checksum entries"
printf '%s\n' "$duplicate_rpm_output" | grep -Fq 'exactly one entry' ||
  fail "RPM duplicate-checksum test failed for the wrong reason"

git_head="0123456789abcdef0123456789abcdef01234567"
while IFS=$'\t' read -r target distro package_target format image_url algorithm checksum _port firmware; do
  proof="$tmp_dir/proof/$target"
  mkdir -p "$proof"
  case "$target" in
    ubuntu-24.04)
      os_id=ubuntu; version_id=24.04; package="loopwire_0.1.0-1ubuntu24.04_amd64.deb"
      metadata=$'loopwire\t0.1.0-1ubuntu24.04\tamd64\tinstall ok installed'
      ;;
    debian-13)
      os_id=debian; version_id=13; package="loopwire_0.1.0-1debian13_amd64.deb"
      metadata=$'loopwire\t0.1.0-1debian13\tamd64\tinstall ok installed'
      ;;
    fedora-44)
      os_id=fedora; version_id=44; package="loopwire-0.1.0-1.fc44.x86_64.rpm"
      metadata=$'loopwire\t0.1.0-1.fc44\tx86_64'
      ;;
    opensuse-tumbleweed)
      os_id=opensuse-tumbleweed; version_id=20260830; package="loopwire-0.1.0-1.x86_64.rpm"
      metadata=$'loopwire\t0.1.0-1\tx86_64'
      ;;
  esac
  cp "$tmp_dir/first/$package" "$proof/$package"
  package_sha="$(sha256sum "$proof/$package" | awk '{ print $1 }')"
  printf '%s  %s\n' "$package_sha" "$package" >"$proof/package.sha256"
  printf '%s\t%s\n' \
    schema loopwire.native-package-vm-proof.v1 \
    target "$target" \
    package_target "$package_target" \
    format "$format" \
    version 0.1.0 \
    git_head "$git_head" \
    package "$package" \
    package_sha256 "$package_sha" \
    virtualization kvm \
    background_help pass \
    backend_detection pass \
    gui_linkage pass \
    gui_launch pass \
    uninstall pass >"$proof/summary.tsv"
  printf '%s\t%s\n' \
    schema loopwire.native-package-image.v1 \
    target "$target" \
    distro "$distro" \
    url "$image_url" \
    checksum_algorithm "$algorithm" \
    checksum "$checksum" \
    actual_checksum "$checksum" \
    firmware "$firmware" >"$proof/image.tsv"
  printf '%s\n' "$git_head" >"$proof/git-head.txt"
  printf 'ID=%s\nVERSION_ID="%s"\nPRETTY_NAME="Fixture %s"\n' "$os_id" "$version_id" "$distro" >"$proof/os-release"
  printf 'Linux fixture 6.0 x86_64 GNU/Linux\n' >"$proof/uname.txt"
  printf 'kvm\n' >"$proof/virtualization.txt"
  printf '%s\n' "$metadata" >"$proof/package-metadata.tsv"
  printf '%s\n' \
    /usr/bin/loopwire \
    /usr/bin/loopwire-dsp-provider \
    /usr/bin/loopwire-jack-ports \
    /usr/bin/loopwire-detect-audio \
    /usr/lib/loopwire/loopwire-gui \
    /usr/share/applications/loopwire.desktop \
    /usr/share/icons/hicolor/scalable/apps/loopwire.svg >"$proof/package-files.txt"
  printf 'usage\n' >"$proof/background-help.txt"
  printf 'usage\n' >"$proof/dsp-provider-help.txt"
  printf 'usage\n' >"$proof/jack-provider-help.txt"
  printf '{}\n' >"$proof/detect-audio.json"
  printf 'linux-vdso.so.1\n' >"$proof/gui-ldd.txt"
  : >"$proof/gui-launch.log"
  printf '0\n' >"$proof/gui-launch-status.txt"
  printf '4194305\n' >"$proof/gui-window-ids.txt"
  printf 'loopwire-gui\n' >"$proof/gui-window-names.txt"
  printf 'removed\n' >"$proof/uninstall-status.txt"
  node scripts/verify-native-package-vm-proof.mjs \
    --target "$target" --evidence-dir "$proof" --git-head "$git_head" >/dev/null
done < <(grep -vE '^[[:space:]]*(#|$)' packaging/vm/native-package-targets.tsv)

printf 'tampered\n' >>"$tmp_dir/proof/ubuntu-24.04/loopwire_0.1.0-1ubuntu24.04_amd64.deb"
if node scripts/verify-native-package-vm-proof.mjs \
  --target ubuntu-24.04 --evidence-dir "$tmp_dir/proof/ubuntu-24.04" --git-head "$git_head" \
  >/dev/null 2>&1; then
  fail "VM proof verifier accepted a tampered package"
fi

echo "Native package builders and proof verifier passed."
