#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ "${1:-}" != --inside ]; then
  exec bash "$root/scripts/with-apt-tools.sh" --container bash "$root/scripts/verify-apt-repository.sh" --inside
fi
cd "$root"
export PYTHONDONTWRITEBYTECODE=1
python3 scripts/test-apt-repository.py
python3 scripts/test-publish-package-repository.py --with-ssh
python3 scripts/test-apt-bootstrap.py
python3 scripts/test-apt-public.py
python3 scripts/test-apt-workflow-preflight.py
node scripts/test-apt-repository-vm-proof.mjs
node --test apps/site/src/lib/aptChannel.test.mjs
echo 'APT repository development verification passed.'
