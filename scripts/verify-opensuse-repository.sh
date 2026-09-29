#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ "${1:-}" != --inside ]; then
  exec bash "$root/scripts/with-opensuse-rpm-tools.sh" --container \
    bash "$root/scripts/verify-opensuse-repository.sh" --inside
fi
cd "$root"
export PYTHONDONTWRITEBYTECODE=1
bash -n scripts/setup-opensuse-repository.sh scripts/publish-opensuse-workflow.sh \
  scripts/with-opensuse-rpm-tools.sh packaging/vm/guest-opensuse-repository-smoke.sh
shellcheck scripts/setup-opensuse-repository.sh scripts/publish-opensuse-workflow.sh \
  scripts/with-opensuse-rpm-tools.sh packaging/vm/guest-opensuse-repository-smoke.sh \
  scripts/verify-opensuse-repository.sh
node --check scripts/verify-opensuse-repository-vm-proof.mjs
node --check scripts/test-opensuse-repository-vm-proof.mjs
for script in scripts/rpm-repository.py scripts/publish-rpm-repository.py \
  scripts/verify-opensuse-public.py scripts/test-opensuse-bootstrap.py scripts/test-opensuse-public.py \
  scripts/test-opensuse-workflow-preflight.py; do
  python3 - "$script" <<'PY'
import ast
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
PY
done
python3 scripts/test-rpm-repository.py
python3 scripts/test-publish-rpm-repository.py --with-ssh
python3 scripts/test-opensuse-bootstrap.py
python3 scripts/test-opensuse-public.py
python3 scripts/test-opensuse-workflow-preflight.py
ruby scripts/test-opensuse-workflow.rb
node scripts/test-opensuse-repository-vm-proof.mjs
node --test apps/site/src/lib/opensuseChannel.test.mjs
echo 'openSUSE repository development verification passed.'
