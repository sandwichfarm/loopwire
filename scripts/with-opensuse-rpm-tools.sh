#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="${LOOPWIRE_OPENSUSE_RPM_TOOLS_IMAGE:-loopwire-rpm-tools:opensuse-tumbleweed}"
force_container=false
mounts=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --container) force_container=true; shift ;;
    --read-only-path)
      input="$(realpath -e "${2:?missing --read-only-path value}")"
      mounts+=(--volume "$input:$input:ro")
      shift 2
      ;;
    *) break ;;
  esac
done
[ "$#" -gt 0 ] || {
  echo 'Usage: with-opensuse-rpm-tools.sh [--container] [--read-only-path PATH] COMMAND [ARG ...]' >&2
  exit 2
}
available=true
for command in createrepo_c gpg gpgv openssl python3 rpm rpmkeys rpmsign zypper; do
  command -v "$command" >/dev/null 2>&1 || available=false
done
export PYTHONDONTWRITEBYTECODE=1
if [ "$available" = true ] && [ "$force_container" = false ]; then
  exec "$@"
fi
command -v docker >/dev/null 2>&1 || {
  echo 'openSUSE repository tools or Docker are required; see the openSUSE repository guide.' >&2
  exit 1
}
if ! docker image inspect "$image" >/dev/null 2>&1; then
  docker build --file "$root/packaging/repositories/Dockerfile.opensuse-rpm-tools" --tag "$image" "$root" >&2
fi
exec docker run --rm --network none --env PYTHONDONTWRITEBYTECODE=1 \
  --volume "$root:$root:ro" "${mounts[@]}" --workdir "$root" "$image" "$@"
