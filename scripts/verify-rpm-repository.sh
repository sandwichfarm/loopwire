#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ "${1:-}" != --inside ]; then
  exec bash "$root/scripts/with-rpm-tools.sh" --container bash "$root/scripts/verify-rpm-repository.sh" --inside
fi
cd "$root"
export PYTHONDONTWRITEBYTECODE=1
bash -n scripts/setup-fedora-repository.sh scripts/publish-fedora-workflow.sh \
  scripts/with-rpm-tools.sh packaging/vm/guest-fedora-repository-smoke.sh
node --check scripts/verify-fedora-repository-vm-proof.mjs
node --check scripts/test-fedora-repository-vm-proof.mjs
python3 scripts/test-rpm-repository.py
python3 scripts/test-publish-rpm-repository.py --with-ssh
python3 scripts/test-fedora-bootstrap.py
python3 scripts/test-rpm-public.py
python3 scripts/test-fedora-workflow-preflight.py
node scripts/test-fedora-repository-vm-proof.mjs
node --test apps/site/src/lib/rpmChannel.test.mjs
node --test apps/site/src/lib/opensuseChannel.test.mjs
echo 'Fedora repository development verification passed.'
