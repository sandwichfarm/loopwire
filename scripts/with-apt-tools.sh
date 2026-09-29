#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="${LOOPWIRE_APT_TOOLS_IMAGE:-loopwire-apt-tools:debian-13}"
force_container=false
mounts=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --container) force_container=true; shift ;;
    --read-only-path)
      path="$(realpath -e "${2:?missing --read-only-path value}")"
      mounts+=(--volume "$path:$path:ro")
      shift 2
      ;;
    *) break ;;
  esac
done
[ "$#" -gt 0 ] || { echo 'Usage: with-apt-tools.sh [--container] [--read-only-path PATH] COMMAND [ARG ...]' >&2; exit 2; }
available=true
for command in python3 dpkg dpkg-deb gpg gpgv openssl; do
  command -v "$command" >/dev/null 2>&1 || available=false
done
export PYTHONDONTWRITEBYTECODE=1
if [ "$available" = true ] && [ "$force_container" = false ]; then
  exec "$@"
fi
command -v docker >/dev/null 2>&1 || { echo 'APT tools or Docker are required; see the APT developer guide.' >&2; exit 1; }
if ! docker image inspect "$image" >/dev/null 2>&1; then
  docker build --file "$root/packaging/repositories/Dockerfile.apt-tools" --tag "$image" "$root" >&2
fi
# Keep absolute source/evidence paths valid for callers. Test writes belong in the disposable /tmp tree.
exec docker run --rm --network none --env PYTHONDONTWRITEBYTECODE=1 \
  --volume "$root:$root:ro" "${mounts[@]}" --workdir "$root" "$image" "$@"
