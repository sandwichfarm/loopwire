#!/usr/bin/env bash
set -euo pipefail

bash -n \
  scripts/install.sh \
  apps/docs/docs/public/install.sh \
  scripts/package-release.sh \
  scripts/sign-release-artifacts.sh \
  scripts/verify-release-signature.sh \
  scripts/stage-release-artifacts.sh \
  scripts/deploy-docs-bunny.sh \
  scripts/verify-docs-live.sh \
  scripts/fetch-docs-deployment-proof.sh \
  scripts/prepare-release-signing-key.sh \
  scripts/render-aur-pkgbuild.sh \
  scripts/render-nix-release-package.sh \
  scripts/verify-nix-release-package.sh \
  scripts/setup-github-secrets.sh \
  scripts/plan-final-release-handoff.sh \
  scripts/verify-agent-release-ready.sh \
  scripts/audit-final-release-state.sh \
  scripts/ct-host-check.sh \
  scripts/vm-matrix.sh \
  scripts/verify-github-workflows.sh \
  scripts/manage-autostart.sh \
  scripts/verify-runtime.sh \
  scripts/verify-tauri.sh \
  scripts/verify-autostart.sh \
  scripts/verify-install.sh \
  scripts/verify-release-artifacts.sh \
  scripts/verify-release-readiness.sh \
  scripts/verify-published-release.sh \
  scripts/verify-release-tag-ref.sh \
  scripts/verify-final-release-proof.sh \
  scripts/validate-release-asset-name.sh \
  scripts/verify-release-asset-checksum.sh \
  scripts/extract-safe-tar.sh \
  scripts/collect-dsp-provider-plan.sh \
  scripts/package-vm-evidence.sh \
  scripts/prepare-vm-evidence-release-asset.sh \
  scripts/verify-vm-evidence.sh \
  scripts/collect-vm-evidence.sh \
  scripts/collect-vm-evidence-ssh.sh \
  scripts/collect-vm-matrix-evidence.sh \
  scripts/verify-aur-package.sh \
  scripts/verify-packaging.sh \
  scripts/verify-requirements.sh \
  scripts/verify-docs.sh

node --check scripts/detect-audio-backends.mjs
node --check scripts/collect-release-evidence.mjs
node --check scripts/verify-release-evidence.mjs
node --check scripts/collect-support-bundle.mjs
node --check scripts/describe-jack-ports.mjs
node --check scripts/describe-dsp-provider.mjs
node --check scripts/promote-vm-evidence.mjs
node --check scripts/restore-background.mjs
node --check scripts/verify-docs-deployment-manifest.mjs
node --check scripts/verify-desktop-preview.mjs
node --check scripts/verify-support-matrix.mjs
node --check scripts/verify-vm-evidence-archive-manifest.mjs
node -e '
const root = require("./package.json");
const audioHost = require("./packages/audio-host/package.json");
if (!root.scripts["jack:provider"]) {
  console.error("verify-scripts: root package is missing jack:provider");
  process.exit(1);
}
if (!root.scripts["dsp:provider"]) {
  console.error("verify-scripts: root package is missing dsp:provider");
  process.exit(1);
}
if (root.scripts["verify:docs-deployment"] !== "node scripts/verify-docs-deployment-manifest.mjs") {
  console.error("verify-scripts: root package is missing verify:docs-deployment");
  process.exit(1);
}
if (root.scripts["verify:desktop-preview"] !== "node scripts/verify-desktop-preview.mjs") {
  console.error("verify-scripts: root package is missing verify:desktop-preview");
  process.exit(1);
}
if (root.scripts["release:handoff"] !== "bash scripts/plan-final-release-handoff.sh") {
  console.error("verify-scripts: root package is missing release:handoff");
  process.exit(1);
}
if (root.scripts["release:agent-ready"] !== "bash scripts/verify-agent-release-ready.sh") {
  console.error("verify-scripts: root package is missing release:agent-ready");
  process.exit(1);
}
if (root.scripts["release:status"] !== "bash scripts/audit-final-release-state.sh") {
  console.error("verify-scripts: root package is missing release:status");
  process.exit(1);
}
if (root.scripts["release:fetch-docs-proof"] !== "bash scripts/fetch-docs-deployment-proof.sh") {
  console.error("verify-scripts: root package is missing release:fetch-docs-proof");
  process.exit(1);
}
if (root.scripts["verify:final-release"] !== "bash scripts/verify-final-release-proof.sh") {
  console.error("verify-scripts: root package is missing verify:final-release");
  process.exit(1);
}
if (root.scripts["vm:package-evidence"] !== "bash scripts/package-vm-evidence.sh") {
  console.error("verify-scripts: root package is missing vm:package-evidence");
  process.exit(1);
}
if (root.scripts["vm:prepare-release-evidence"] !== "bash scripts/prepare-vm-evidence-release-asset.sh") {
  console.error("verify-scripts: root package is missing vm:prepare-release-evidence");
  process.exit(1);
}
if (audioHost.bin?.["loopwire-jack-ports"] !== "./dist/jack-ports-cli.js") {
  console.error("verify-scripts: audio-host package is missing loopwire-jack-ports bin");
  process.exit(1);
}
if (audioHost.bin?.["loopwire-dsp-provider"] !== "./dist/dsp-provider-cli.js") {
  console.error("verify-scripts: audio-host package is missing loopwire-dsp-provider bin");
  process.exit(1);
}
'
node scripts/promote-vm-evidence.mjs --help | grep -F -- "--require-published-release" >/dev/null || {
  echo "verify-scripts: VM evidence promotion help is missing published release requirement support" >&2
  exit 1
}
node scripts/promote-vm-evidence.mjs --help | grep -F -- "--release-tag vX.Y.Z" >/dev/null || {
  echo "verify-scripts: VM evidence promotion help is missing release tag support" >&2
  exit 1
}
node scripts/promote-vm-evidence.mjs --help | grep -F -- "--all" >/dev/null || {
  echo "verify-scripts: VM evidence promotion help is missing all-target support" >&2
  exit 1
}
node scripts/promote-vm-evidence.mjs --help | grep -F -- "--evidence-root DIR" >/dev/null || {
  echo "verify-scripts: VM evidence promotion help is missing evidence root support" >&2
  exit 1
}
node scripts/verify-support-matrix.mjs --help | grep -F -- "--matrix FILE" >/dev/null || {
  echo "verify-scripts: support matrix verifier help is missing matrix path support" >&2
  exit 1
}
node scripts/verify-desktop-preview.mjs --help | grep -F -- "--skip-if-missing" >/dev/null || {
  echo "verify-scripts: desktop preview verifier help is missing skip-if-missing support" >&2
  exit 1
}
awk 'NF != 1 || $1 !~ /^[A-Z0-9_]+$/ { exit 1 }' \
  scripts/fixtures/github-secret-list-final.tsv || {
    echo "verify-scripts: committed GitHub secret-list fixture must contain names only" >&2
    exit 1
  }
for required_secret in \
  BUNNY_STORAGE_ZONE \
  BUNNY_ACCESS_KEY \
  BUNNY_PULL_ZONE_HOSTNAME \
  LOOPWIRE_RELEASE_PRIVATE_KEY; do
  grep -Fx -- "$required_secret" scripts/fixtures/github-secret-list-final.tsv >/dev/null || {
    echo "verify-scripts: GitHub secret-list fixture is missing ${required_secret}" >&2
    exit 1
  }
done
bash scripts/setup-github-secrets.sh --repo sandwichfarm/loopwire --check --scope final \
  --secret-list-file scripts/fixtures/github-secret-list-final.tsv \
  | grep -F -- "ok: final release proof secrets are present" >/dev/null || {
    echo "verify-scripts: final secret-list fixture does not satisfy offline check mode" >&2
    exit 1
  }
node scripts/verify-support-matrix.mjs --help | grep -F -- "--require-published-release" >/dev/null || {
  echo "verify-scripts: support matrix verifier help is missing published release strictness support" >&2
  exit 1
}
node scripts/verify-support-matrix.mjs --help | grep -F -- "local, non-symlink artifacts" >/dev/null || {
  echo "verify-scripts: support matrix verifier help is missing path boundary guidance" >&2
  exit 1
}
bash scripts/verify-vm-evidence.sh --help | grep -F -- "--release-tag vX.Y.Z" >/dev/null || {
  echo "verify-scripts: VM evidence verifier help is missing release tag support" >&2
  exit 1
}
bash scripts/verify-vm-evidence.sh --help | grep -F -- "--require-github-release-source" >/dev/null || {
  echo "verify-scripts: VM evidence verifier help is missing GitHub release source strictness support" >&2
  exit 1
}
bash scripts/vm-matrix.sh evidence-status --help | grep -F -- "--release-tag vX.Y.Z" >/dev/null || {
  echo "verify-scripts: VM matrix helper help is missing release tag support" >&2
  exit 1
}
bash scripts/vm-matrix.sh evidence-status --help | grep -F -- "--start-port PORT" >/dev/null || {
  echo "verify-scripts: VM matrix helper help is missing evidence-status start port support" >&2
  exit 1
}
node scripts/verify-support-matrix.mjs --help | grep -F -- "--release-tag vX.Y.Z" >/dev/null || {
  echo "verify-scripts: support matrix verifier help is missing release tag support" >&2
  exit 1
}
collect_evidence_help="$(node scripts/collect-release-evidence.mjs --help)"
release_readiness_help="$(bash scripts/verify-release-readiness.sh --help)"
printf '%s\n' "$release_readiness_help" | grep -F -- "docs deployment manifest verifier" >/dev/null || {
  echo "verify-scripts: release readiness help is missing docs deployment verifier check" >&2
  exit 1
}
printf '%s\n' "$release_readiness_help" |
  grep -F -- "final release proof workflow, release tag-ref verifier" >/dev/null ||
  printf '%s\n' "$release_readiness_help" |
    grep -F -- "final release proof workflow, release tag-ref verifier, asset-name validator" \
      >/dev/null || {
    echo "verify-scripts: release readiness help is missing final proof wiring check" >&2
    exit 1
  }
printf '%s\n' "$release_readiness_help" |
  grep -F -- "asset checksum verifier" >/dev/null || {
    echo "verify-scripts: release readiness help is missing final proof checksum verifier check" >&2
    exit 1
  }
printf '%s\n' "$release_readiness_help" |
  grep -F -- "VM signed-release helper" >/dev/null || {
    echo "verify-scripts: release readiness help is missing VM signed-release helper check" >&2
    exit 1
  }
printf '%s\n' "$release_readiness_help" |
  grep -F -- "live-docs pull-zone hostname" >/dev/null || {
    echo "verify-scripts: release readiness help is missing live-docs hostname requirement" >&2
    exit 1
  }
pnpm verify:release-readiness -- --repo sandwichfarm/loopwire --tag v0.1.0 \
  --public-key packaging/release-signing-public.pem --skip-gh --skip-tag --skip-clean-git \
  --allow-candidate-notes \
  | grep -F -- "ok: final release proof workflow passes GitHub token to proof step" \
  >/dev/null || {
    echo "verify-scripts: release readiness output is missing final proof GitHub token check" >&2
    exit 1
  }
pnpm verify:release-readiness -- --repo sandwichfarm/loopwire --tag v0.1.0 \
  --public-key packaging/release-signing-public.pem --skip-gh --skip-tag --skip-clean-git \
  --allow-candidate-notes \
  | grep -F -- "ok: package script vm:prepare-release-evidence is wired" \
  >/dev/null || {
    echo "verify-scripts: release readiness output is missing VM signed-release helper check" >&2
    exit 1
  }
verify_published_release_help="$(bash scripts/verify-published-release.sh --help)"
verify_release_tag_ref_help="$(bash scripts/verify-release-tag-ref.sh --help)"
verify_final_release_help="$(bash scripts/verify-final-release-proof.sh --help)"
release_handoff_help="$(bash scripts/plan-final-release-handoff.sh --help)"
agent_release_ready_help="$(bash scripts/verify-agent-release-ready.sh --help)"
fetch_docs_proof_help="$(bash scripts/fetch-docs-deployment-proof.sh --help)"
bash scripts/plan-final-release-handoff.sh -- --help >/dev/null || {
  echo "verify-scripts: release handoff does not accept the package-script argument separator" >&2
  exit 1
}
printf '%s\n' "$agent_release_ready_help" |
  grep -F -- "Require commit-scoped CI and Deploy Docs workflow runs" >/dev/null || {
    echo "verify-scripts: agent-ready release help is missing commit-scoped hosted-check wording" >&2
    exit 1
  }
printf '%s\n' "$fetch_docs_proof_help" | grep -F -- "--run-id ID" >/dev/null || {
  echo "verify-scripts: docs deployment proof helper help is missing run id support" >&2
  exit 1
}
printf '%s\n' "$fetch_docs_proof_help" | grep -F -- "--manifest-artifact NAME" >/dev/null || {
  echo "verify-scripts: docs deployment proof helper help is missing manifest artifact support" >&2
  exit 1
}
printf '%s\n' "$verify_release_tag_ref_help" | grep -F -- "--git-head SHA" >/dev/null || {
  echo "verify-scripts: release tag ref verifier help is missing git-head support" >&2
  exit 1
}
printf '%s\n' "$fetch_docs_proof_help" | grep -F -- "--docs-dist DIR" >/dev/null || {
  echo "verify-scripts: docs deployment proof helper help is missing docs dist support" >&2
  exit 1
}
printf '%s\n' "$fetch_docs_proof_help" | grep -F -- "--env-file FILE" >/dev/null || {
  echo "verify-scripts: docs deployment proof helper help is missing env-file recovery support" >&2
  exit 1
}
printf '%s\n' "$release_handoff_help" | grep -F -- "--docs-deployment-run-id ID" >/dev/null || {
  echo "verify-scripts: release handoff help is missing docs deployment run id support" >&2
  exit 1
}
printf '%s\n' "$release_handoff_help" | grep -F -- "--release-private-key-file FILE" >/dev/null || {
  echo "verify-scripts: release handoff help is missing VM evidence private key support" >&2
  exit 1
}
printf '%s\n' "$release_handoff_help" | grep -F -- "--env-file FILE" >/dev/null || {
  echo "verify-scripts: release handoff help is missing env-file support" >&2
  exit 1
}
printf '%s\n' "$agent_release_ready_help" | grep -F -- "--skip-local-gates" >/dev/null || {
  echo "verify-scripts: agent-ready release help is missing skip-local-gates support" >&2
  exit 1
}
printf '%s\n' "$agent_release_ready_help" | grep -F -- "--require-hosted-checks" >/dev/null || {
  echo "verify-scripts: agent-ready release help is missing hosted-check support" >&2
  exit 1
}
printf '%s\n' "$agent_release_ready_help" | grep -F -- "--dsp-configuration FILE" >/dev/null || {
  echo "verify-scripts: agent-ready release help is missing DSP configuration support" >&2
  exit 1
}
printf '%s\n' "$agent_release_ready_help" | grep -F -- "--dsp-frame-count N" >/dev/null || {
  echo "verify-scripts: agent-ready release help is missing DSP frame-count support" >&2
  exit 1
}
printf '%s\n' "$agent_release_ready_help" | grep -F -- "operator-deferred release ceremony" >/dev/null || {
  echo "verify-scripts: agent-ready release help is missing operator-deferred wording" >&2
  exit 1
}
printf '%s\n' "$release_handoff_help" | grep -F -- "Operator-only activities" >/dev/null || {
  echo "verify-scripts: release handoff help is missing operator-deferred wording" >&2
  exit 1
}
release_handoff_env_file="$(mktemp)"
cat >"$release_handoff_env_file" <<'EOF'
BUNNY_STORAGE_ZONE=env-loopwire-docs
BUNNY_ACCESS_KEY=env-access-key-that-must-not-print
BUNNY_STORAGE_ENDPOINT=ny.storage.bunnycdn.com
BUNNY_PULL_ZONE_HOSTNAME=docs.env.example.test
BUNNY_REMOTE_PREFIX=env-preview
LOOPWIRE_RELEASE_PRIVATE_KEY_FILE=/secure/env-loopwire-release-private.pem
LOOPWIRE_RELEASE_PUBLIC_KEY_FILE=packaging/release-signing-public.pem
EOF
release_handoff_plan="$(
  bash scripts/plan-final-release-handoff.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --git-head 0123456789abcdef0123456789abcdef01234567 \
    --docs-deployment-run-id 123456 \
    --docs-hostname docs.example.test \
    --docs-remote-prefix preview \
    --release-private-key-file /secure/loopwire-release-private.pem \
    --vm-start-port 2700 \
    --secret-list-file release-secret-names.tsv
)"
release_handoff_env_plan="$(
  bash scripts/plan-final-release-handoff.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --git-head 0123456789abcdef0123456789abcdef01234567 \
    --docs-deployment-run-id 123456 \
    --env-file "$release_handoff_env_file"
)"
release_handoff_env_override_plan="$(
  bash scripts/plan-final-release-handoff.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --git-head 0123456789abcdef0123456789abcdef01234567 \
    --env-file "$release_handoff_env_file" \
    --release-private-key-file /secure/cli-loopwire-release-private.pem \
    --docs-hostname docs.cli.example.test \
    --docs-remote-prefix cli-preview
)"
rm -f "$release_handoff_env_file"
printf '%s\n' "$release_handoff_plan" | grep -F "bash scripts/setup-github-secrets.sh" >/dev/null || {
  echo "verify-scripts: release handoff plan is missing secret check" >&2
  exit 1
}
printf '%s\n' "$release_handoff_plan" | grep -F "Operator-deferred after agent delivery" >/dev/null || {
  echo "verify-scripts: release handoff plan is missing operator-deferred section" >&2
  exit 1
}
printf '%s\n' "$release_handoff_plan" |
  grep -F "bash scripts/setup-github-secrets.sh --write-env-template /secure/loopwire-release-secrets.env" >/dev/null || {
    echo "verify-scripts: release handoff plan is missing secret env-template setup" >&2
    exit 1
  }
printf '%s\n' "$release_handoff_plan" | grep -F "protected GitHub surfaces" >/dev/null || {
  echo "verify-scripts: release handoff plan is missing protected workflow dispatch wording" >&2
  exit 1
}
release_handoff_tag_command="git tag -a v0.1.0 0123456789abcdef0123456789abcdef"
release_handoff_tag_command+="01234567"
printf '%s\n' "$release_handoff_plan" | grep -F "$release_handoff_tag_command" >/dev/null || {
  echo "verify-scripts: release handoff plan is missing reviewed tag creation" >&2
  exit 1
}
printf '%s\n' "$release_handoff_plan" | grep -F "git push origin refs/tags/v0.1.0" >/dev/null || {
  echo "verify-scripts: release handoff plan is missing tag push" >&2
  exit 1
}
printf '%s\n' "$release_handoff_env_plan" | grep -F "bash scripts/setup-github-secrets.sh" |
  grep -F -- "--env-file $release_handoff_env_file" >/dev/null || {
    echo "verify-scripts: release handoff env-file plan did not preserve the secret setup env-file" >&2
    exit 1
  }
printf '%s\n' "$release_handoff_env_plan" | grep -F "pnpm release:fetch-docs-proof" |
  grep -F -- "--env-file $release_handoff_env_file" >/dev/null || {
    echo "verify-scripts: release handoff env-file plan did not preserve the docs proof env-file" >&2
    exit 1
  }
printf '%s\n' "$release_handoff_env_plan" | grep -F "pnpm vm:prepare-release-evidence" |
  grep -F -- "--env-file $release_handoff_env_file" >/dev/null || {
    echo "verify-scripts: release handoff env-file plan did not preserve the VM evidence env-file" >&2
    exit 1
  }
if printf '%s\n' "$release_handoff_env_plan" | grep -F "pnpm vm:prepare-release-evidence" |
  grep -F -- "--private-key /secure/env-loopwire-release-private.pem" >/dev/null; then
    echo "verify-scripts: release handoff env-file plan expanded the release private key path" >&2
    exit 1
fi
printf '%s\n' "$release_handoff_env_plan" | grep -F "gh workflow run final-release-proof.yml" |
  grep -F -- "-f docs_hostname=docs.env.example.test" |
  grep -F -- "-f docs_remote_prefix=env-preview" >/dev/null || {
    echo "verify-scripts: release handoff env-file plan did not use docs hostname/prefix" >&2
    exit 1
  }
if printf '%s\n' "$release_handoff_env_plan" | grep -F "env-access-key-that-must-not-print" >/dev/null; then
  echo "verify-scripts: release handoff env-file plan leaked the Bunny access key" >&2
  exit 1
fi
if printf '%s\n' "$release_handoff_env_plan" | grep -F "env-loopwire-docs" >/dev/null; then
  echo "verify-scripts: release handoff env-file plan leaked the Bunny storage zone" >&2
  exit 1
fi
printf '%s\n' "$release_handoff_env_override_plan" | grep -F "pnpm vm:prepare-release-evidence" |
  grep -F -- "--private-key /secure/cli-loopwire-release-private.pem" >/dev/null || {
    echo "verify-scripts: release handoff CLI private key did not override env-file value" >&2
    exit 1
  }
printf '%s\n' "$release_handoff_env_override_plan" | grep -F "gh workflow run final-release-proof.yml" |
  grep -F -- "-f docs_hostname=docs.cli.example.test" |
  grep -F -- "-f docs_remote_prefix=cli-preview" >/dev/null || {
    echo "verify-scripts: release handoff CLI docs fields did not override env-file values" >&2
    exit 1
  }
printf '%s\n' "$release_handoff_plan" | grep -F "gh workflow run release.yml" >/dev/null || {
  echo "verify-scripts: release handoff plan is missing release workflow dispatch" >&2
  exit 1
}
printf '%s\n' "$release_handoff_plan" | grep -F "gh workflow run deploy-docs.yml" >/dev/null || {
  echo "verify-scripts: release handoff plan is missing docs workflow dispatch" >&2
  exit 1
}
printf '%s\n' "$release_handoff_plan" | grep -F "pnpm release:fetch-docs-proof" |
  grep -F -- "--run-id 123456" |
  grep -F -- "--git-head 0123456789abcdef0123456789abcdef01234567" >/dev/null || {
    echo "verify-scripts: release handoff plan is missing docs deployment proof fetch" >&2
    exit 1
  }
printf '%s\n' "$release_handoff_plan" | grep -F "pnpm vm:host-setup -- --all" >/dev/null || {
  echo "verify-scripts: release handoff plan is missing all-target VM host setup preflight" >&2
  exit 1
}
printf '%s\n' "$release_handoff_plan" | grep -F "pnpm vm:doctor -- --all" >/dev/null || {
  echo "verify-scripts: release handoff plan is missing all-target VM doctor preflight" >&2
  exit 1
}
printf '%s\n' "$release_handoff_plan" | grep -F "pnpm vm:collect-matrix" | grep -F -- "--require-github-release-source" >/dev/null || {
  echo "verify-scripts: release handoff plan is missing GitHub-source VM evidence collection" >&2
  exit 1
}
printf '%s\n' "$release_handoff_plan" | grep -F "pnpm vm:prepare-release-evidence" | grep -F -- "--private-key" >/dev/null || {
  echo "verify-scripts: release handoff plan is missing signed VM evidence preparation" >&2
  exit 1
}
printf '%s\n' "$release_handoff_plan" | grep -F "gh workflow run final-release-proof.yml" >/dev/null || {
  echo "verify-scripts: release handoff plan is missing final proof workflow dispatch" >&2
  exit 1
}
printf '%s\n' "$release_handoff_plan" |
  grep -F "expected GitHub Actions run name: Final Release Proof v0.1.0 @ 0123456789abcdef0123456789abcdef01234567" >/dev/null || {
    echo "verify-scripts: release handoff plan is missing final proof run-name hint" >&2
    exit 1
  }
printf '%s\n' "$release_handoff_plan" | grep -F "pnpm verify:final-release" | grep -F -- "--plan-output" >/dev/null || {
  echo "verify-scripts: release handoff plan is missing local final-proof dry-run" >&2
  exit 1
}
printf '%s\n' "$release_handoff_plan" | grep -F "pnpm release:status" |
  grep -F -- "--docs-deployment-run-id 123456" |
  grep -F -- "--git-head 0123456789abcdef0123456789abcdef01234567" |
  grep -F -- "--vm-start-port 2700" >/dev/null || {
    echo "verify-scripts: release handoff plan is missing final release status audit" >&2
    exit 1
  }
release_handoff_placeholder_plan="$(
  bash scripts/plan-final-release-handoff.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --git-head 0123456789abcdef0123456789abcdef01234567
)"
printf '%s\n' "$release_handoff_placeholder_plan" |
  grep -F "1. Verify agent-ready release automation for this exact commit:" >/dev/null || {
    echo "verify-scripts: release handoff placeholder plan is missing agent-ready preflight step" >&2
    exit 1
  }
printf '%s\n' "$release_handoff_placeholder_plan" |
  grep -F "pnpm release:agent-ready -- --repo sandwichfarm/loopwire --tag v0.1.0 --git-head 0123456789abcdef0123456789abcdef01234567 --public-key packaging/release-signing-public.pem --require-hosted-checks" >/dev/null || {
    echo "verify-scripts: release handoff placeholder plan is missing commit-scoped hosted agent-ready command" >&2
    exit 1
  }
release_handoff_docs_run_reminder="operator-deferred: replace <docs-deployment-run-id> with the successful "
release_handoff_docs_run_reminder+="Deploy Docs workflow run id before steps 7, 9, and 11."
printf '%s\n' "$release_handoff_placeholder_plan" |
  grep -F "$release_handoff_docs_run_reminder" >/dev/null || {
    echo "verify-scripts: release handoff placeholder plan is missing docs-run operator-deferred reminder" >&2
    exit 1
  }
printf '%s\n' "$release_handoff_placeholder_plan" |
  grep -F "operator-deferred: pass --release-private-key-file or --env-file" >/dev/null || {
    echo "verify-scripts: release handoff placeholder plan is missing private-key operator-deferred reminder" >&2
    exit 1
  }
agent_release_ready_plan="$(
  bash scripts/verify-agent-release-ready.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --git-head 0123456789abcdef0123456789abcdef01234567 \
    --skip-local-gates
)"
printf '%s\n' "$agent_release_ready_plan" |
  grep -F "Agent-ready release status: ready for operator-deferred ceremony" >/dev/null || {
    echo "verify-scripts: agent-ready release smoke is missing ready status" >&2
    exit 1
  }
printf '%s\n' "$agent_release_ready_plan" |
  grep -F "skipped: local repo gates (--skip-local-gates)" >/dev/null || {
    echo "verify-scripts: agent-ready release smoke did not report skipped local gates" >&2
    exit 1
  }
printf '%s\n' "$agent_release_ready_plan" |
  grep -F "skipped: hosted workflow checks (--require-hosted-checks not set)" >/dev/null || {
    echo "verify-scripts: agent-ready release smoke did not report skipped hosted checks" >&2
    exit 1
  }
printf '%s\n' "$agent_release_ready_plan" |
  grep -F "Re-run strict final proof from published GitHub Release and Bunny.net surfaces." >/dev/null || {
    echo "verify-scripts: agent-ready release smoke is missing strict final-proof reminder" >&2
    exit 1
  }
agent_ready_fake_bin="$(mktemp -d)"
cat >"$agent_ready_fake_bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

workflow=""
commit=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --workflow)
      workflow="${2:?missing --workflow value}"
      shift 2
      ;;
    --commit)
      commit="${2:?missing --commit value}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

[ "$commit" = "0123456789abcdef0123456789abcdef01234567" ] || {
  echo "unexpected commit filter: $commit" >&2
  exit 1
}

case "$workflow" in
  ci.yml)
    printf '%s%s\n' \
      '[{"databaseId":111,"status":"completed","conclusion":"success",' \
      '"headSha":"0123456789abcdef0123456789abcdef01234567","url":"https://example.test/ci"}]'
    ;;
  deploy-docs.yml)
    printf '%s%s\n' \
      '[{"databaseId":222,"status":"completed","conclusion":"success",' \
      '"headSha":"0123456789abcdef0123456789abcdef01234567","url":"https://example.test/docs"}]'
    ;;
  *)
    echo "unexpected workflow: $workflow" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$agent_ready_fake_bin/gh"
agent_release_ready_hosted_plan="$(
  PATH="$agent_ready_fake_bin:$PATH" bash scripts/verify-agent-release-ready.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --git-head 0123456789abcdef0123456789abcdef01234567 \
    --require-hosted-checks \
    --skip-local-gates
)"
printf '%s\n' "$agent_release_ready_hosted_plan" |
  grep -F "ok: commit-scoped hosted CI workflow run" >/dev/null || {
    echo "verify-scripts: agent-ready release did not verify hosted CI" >&2
    exit 1
  }
printf '%s\n' "$agent_release_ready_hosted_plan" |
  grep -F "ok: commit-scoped hosted Deploy Docs workflow run" >/dev/null || {
    echo "verify-scripts: agent-ready release did not verify hosted docs" >&2
    exit 1
  }
printf '%s\n' "$agent_release_ready_hosted_plan" |
  grep -F "commit-scoped run verified: databaseId=111 headSha=0123456789abcdef0123456789abcdef01234567" >/dev/null || {
    echo "verify-scripts: agent-ready release hosted CI proof is missing run evidence" >&2
    exit 1
  }
printf '%s\n' "$agent_release_ready_hosted_plan" |
  grep -F "commit-scoped run verified: databaseId=222 headSha=0123456789abcdef0123456789abcdef01234567" >/dev/null || {
    echo "verify-scripts: agent-ready release hosted docs proof is missing run evidence" >&2
    exit 1
  }
rm -rf "$agent_ready_fake_bin"
if printf '%s\n' "$agent_release_ready_plan" |
  grep -F "allowed: release notes still carry candidate wording" >/dev/null; then
  echo "verify-scripts: agent-ready release still allows candidate release notes" >&2
  exit 1
fi
if bash scripts/verify-agent-release-ready.sh \
  --repo https://github.com/sandwichfarm/loopwire \
  --tag v0.1.0 \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --skip-local-gates >/dev/null 2>&1; then
  echo "verify-scripts: agent-ready release accepted a URL-like repository" >&2
  exit 1
fi
if bash scripts/verify-agent-release-ready.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --dsp-configuration ../unsafe.json \
  --skip-local-gates >/dev/null 2>&1; then
  echo "verify-scripts: agent-ready release accepted unsafe DSP configuration path" >&2
  exit 1
fi
if bash scripts/verify-agent-release-ready.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --dsp-frame-count nope \
  --skip-local-gates >/dev/null 2>&1; then
  echo "verify-scripts: agent-ready release accepted invalid DSP frame count" >&2
  exit 1
fi
if bash scripts/plan-final-release-handoff.sh \
  --repo https://github.com/sandwichfarm/loopwire \
  --tag v0.1.0 \
  --git-head 0123456789abcdef0123456789abcdef01234567 >/dev/null 2>&1; then
  echo "verify-scripts: release handoff accepted a URL-like repository" >&2
  exit 1
fi
if bash scripts/plan-final-release-handoff.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --git-head not-a-sha >/dev/null 2>&1; then
  echo "verify-scripts: release handoff accepted an invalid git head" >&2
  exit 1
fi
if bash scripts/plan-final-release-handoff.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --vm-evidence-asset ../loopwire-vm-evidence-v0.1.0.tar.gz >/dev/null 2>&1; then
  echo "verify-scripts: release handoff accepted an unsafe VM evidence asset name" >&2
  exit 1
fi
if bash scripts/plan-final-release-handoff.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --vm-ssh-plan /tmp/loopwire-vm-ssh-plan.tsv >/dev/null 2>&1; then
  echo "verify-scripts: release handoff accepted an absolute VM SSH plan path" >&2
  exit 1
fi
if bash scripts/plan-final-release-handoff.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --vm-runbook ../loopwire-vm-runbook.md >/dev/null 2>&1; then
  echo "verify-scripts: release handoff accepted a parent-traversing VM runbook path" >&2
  exit 1
fi
release_status_help="$(bash scripts/audit-final-release-state.sh --help)"
bash scripts/audit-final-release-state.sh -- --help >/dev/null || {
  echo "verify-scripts: release status does not accept the package-script argument separator" >&2
  exit 1
}
printf '%s\n' "$release_status_help" | grep -F -- "--secret-list-file FILE" >/dev/null || {
  echo "verify-scripts: release status help is missing secret-list artifact support" >&2
  exit 1
}
printf '%s\n' "$release_status_help" | grep -F -- "--docs-deployment-run-id ID" >/dev/null || {
  echo "verify-scripts: release status help is missing docs deployment run id support" >&2
  exit 1
}
printf '%s\n' "$release_status_help" | grep -F -- "--docs-deployment-manifest FILE" >/dev/null || {
  echo "verify-scripts: release status help is missing docs deployment manifest support" >&2
  exit 1
}
printf '%s\n' "$release_status_help" | grep -F -- "--docs-dist DIR" >/dev/null || {
  echo "verify-scripts: release status help is missing docs dist support" >&2
  exit 1
}
printf '%s\n' "$release_status_help" | grep -F -- "--vm-start-port PORT" >/dev/null || {
  echo "verify-scripts: release status help is missing VM start port support" >&2
  exit 1
}
printf '%s\n' "$release_status_help" | grep -F -- "--git-head SHA" >/dev/null || {
  echo "verify-scripts: release status help is missing expected git head support" >&2
  exit 1
}
printf '%s\n' "$release_status_help" | grep -F -- "--public-key FILE" >/dev/null || {
  echo "verify-scripts: release status help is missing public-key support" >&2
  exit 1
}
printf '%s\n' "$release_status_help" | grep -F -- "--env-file FILE" >/dev/null || {
  echo "verify-scripts: release status help is missing env-file handoff support" >&2
  exit 1
}
printf '%s\n' "$release_status_help" | grep -F -- "--skip-gh" >/dev/null || {
  echo "verify-scripts: release status help is missing offline support" >&2
  exit 1
}
if bash scripts/audit-final-release-state.sh \
  --repo https://github.com/sandwichfarm/loopwire \
  --tag v0.1.0 \
  --skip-gh >/dev/null 2>&1; then
  echo "verify-scripts: release status accepted a URL-like repository" >&2
  exit 1
fi
if bash scripts/audit-final-release-state.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --git-head not-a-sha \
  --skip-gh >/dev/null 2>&1; then
  echo "verify-scripts: release status accepted an invalid git head" >&2
  exit 1
fi
if bash scripts/audit-final-release-state.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --vm-start-port nope \
  --skip-gh >/dev/null 2>&1; then
  echo "verify-scripts: release status accepted an invalid VM start port" >&2
  exit 1
fi
if bash scripts/audit-final-release-state.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --docs-deployment-run-id nope \
  --skip-gh >/dev/null 2>&1; then
  echo "verify-scripts: release status accepted an invalid docs deployment run id" >&2
  exit 1
fi
if bash scripts/audit-final-release-state.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --docs-deployment-manifest ../deployment-manifest.json \
  --skip-gh >/dev/null 2>&1; then
  echo "verify-scripts: release status accepted traversal in docs deployment manifest" >&2
  exit 1
fi
if bash scripts/audit-final-release-state.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --docs-dist '~/loopwire-docs-dist' \
  --skip-gh >/dev/null 2>&1; then
  echo "verify-scripts: release status accepted home expansion in docs dist" >&2
  exit 1
fi
release_status_path_guard_root="$(mktemp -d)"
release_status_env_file_symlink="$release_status_path_guard_root/env-file-symlink"
release_status_secret_list_dir="$release_status_path_guard_root/secret-list-dir"
release_status_docs_dist_symlink="$release_status_path_guard_root/docs-dist-symlink"
release_status_support_matrix_dir="$release_status_path_guard_root/support-matrix-dir"
ln -s "$release_status_path_guard_root" "$release_status_env_file_symlink"
ln -s "$release_status_path_guard_root" "$release_status_docs_dist_symlink"
mkdir -p "$release_status_secret_list_dir"
mkdir -p "$release_status_support_matrix_dir"
if bash scripts/audit-final-release-state.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --env-file "$release_status_env_file_symlink" \
  --skip-gh >/dev/null 2>&1; then
  echo "verify-scripts: release status accepted a symlink env file" >&2
  rm -rf "$release_status_path_guard_root"
  exit 1
fi
if bash scripts/audit-final-release-state.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --secret-list-file "$release_status_secret_list_dir" \
  --skip-gh >/dev/null 2>&1; then
  echo "verify-scripts: release status accepted a directory secret-list file" >&2
  rm -rf "$release_status_path_guard_root"
  exit 1
fi
if bash scripts/audit-final-release-state.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --docs-dist "$release_status_docs_dist_symlink" \
  --skip-gh >/dev/null 2>&1; then
  echo "verify-scripts: release status accepted a symlink docs dist" >&2
  rm -rf "$release_status_path_guard_root"
  exit 1
fi
if bash scripts/audit-final-release-state.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --support-matrix "$release_status_support_matrix_dir" \
  --skip-gh >/dev/null 2>&1; then
  echo "verify-scripts: release status accepted a directory support matrix" >&2
  rm -rf "$release_status_path_guard_root"
  exit 1
fi
rm -rf "$release_status_path_guard_root"
node scripts/verify-release-evidence.mjs --help | grep -F -- "--require-all-vm-targets" >/dev/null || {
  echo "verify-scripts: release evidence verifier help is missing all-target support" >&2
  exit 1
}
node scripts/verify-release-evidence.mjs --help | grep -F -- "--require-clean-git" >/dev/null || {
  echo "verify-scripts: release evidence verifier help is missing clean git support" >&2
  exit 1
}
node scripts/verify-release-evidence.mjs --help | grep -F -- "--release-tag TAG" >/dev/null || {
  echo "verify-scripts: release evidence verifier help is missing tag binding support" >&2
  exit 1
}
node scripts/verify-release-evidence.mjs --help | grep -F -- "--repo OWNER/REPO" >/dev/null || {
  echo "verify-scripts: release evidence verifier help is missing repo binding support" >&2
  exit 1
}
node scripts/verify-release-evidence.mjs --help | grep -F -- "--public-key FILE" >/dev/null || {
  echo "verify-scripts: release evidence verifier help is missing public key binding support" >&2
  exit 1
}
node scripts/verify-release-evidence.mjs --help | grep -F -- "--git-head SHA" >/dev/null || {
  echo "verify-scripts: release evidence verifier help is missing git head binding support" >&2
  exit 1
}
node scripts/verify-release-evidence.mjs --help | grep -F -- "--require-live-docs" >/dev/null || {
  echo "verify-scripts: release evidence verifier help is missing live docs support" >&2
  exit 1
}
node scripts/verify-release-evidence.mjs --help | grep -F -- "--require-nix-release" >/dev/null || {
  echo "verify-scripts: release evidence verifier help is missing Nix release support" >&2
  exit 1
}
node scripts/verify-release-evidence.mjs --help | grep -F -- "--require-vm-launch-plan" >/dev/null || {
  echo "verify-scripts: release evidence verifier help is missing VM launch-plan support" >&2
  exit 1
}
node scripts/verify-release-evidence.mjs --help | grep -F -- "--require-dsp-provider-plan" >/dev/null || {
  echo "verify-scripts: release evidence verifier help is missing DSP provider plan support" >&2
  exit 1
}
printf '%s\n' "$verify_published_release_help" | grep -F -- "--require-release-evidence" >/dev/null || {
  echo "verify-scripts: published release verifier help is missing evidence asset support" >&2
  exit 1
}
printf '%s\n' "$verify_published_release_help" | grep -F -- "--require-github-release-source" >/dev/null || {
  echo "verify-scripts: published release verifier help is missing GitHub-source strictness support" >&2
  exit 1
}
printf '%s\n' "$verify_final_release_help" | grep -F -- "--release-evidence-dir DIR" >/dev/null || {
  echo "verify-scripts: final release verifier help is missing release evidence directory support" >&2
  exit 1
}
printf '%s\n' "$verify_final_release_help" | grep -F -- "--vm-evidence-root DIR" >/dev/null || {
  echo "verify-scripts: final release verifier help is missing VM evidence root support" >&2
  exit 1
}
printf '%s\n' "$verify_final_release_help" | grep -F -- "--support-matrix FILE" >/dev/null || {
  echo "verify-scripts: final release verifier help is missing support matrix path support" >&2
  exit 1
}
printf '%s\n' "$verify_final_release_help" | grep -F -- "--docs-deployment-manifest FILE" >/dev/null || {
  echo "verify-scripts: final release verifier help is missing docs deployment manifest support" >&2
  exit 1
}
printf '%s\n' "$verify_final_release_help" | grep -F -- "--plan-output FILE" >/dev/null || {
  echo "verify-scripts: final release verifier help is missing dry-run plan output support" >&2
  exit 1
}
final_release_dry_run="$(
  bash scripts/verify-final-release-proof.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --public-key packaging/release-signing-public.pem \
    --git-head 0123456789abcdef0123456789abcdef01234567 \
    --release-evidence-dir .release-evidence/v0.1.0-published \
    --docs-hostname docs.example.test \
    --docs-remote-prefix preview \
    --docs-deployment-manifest dist/docs-deployment/deployment-manifest.json \
    --vm-evidence-root .vm/evidence \
    --support-matrix apps/docs/docs/guide/support-matrix.md \
    --dry-run
)"
final_release_plan_output="dist/release/final-release-proof-plan.verify-scripts.txt"
rm -f "$final_release_plan_output"
bash scripts/verify-final-release-proof.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --public-key packaging/release-signing-public.pem \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --release-evidence-dir .release-evidence/v0.1.0-published \
  --docs-hostname docs.example.test \
  --docs-remote-prefix preview \
  --docs-deployment-manifest dist/docs-deployment/deployment-manifest.json \
  --vm-evidence-root .vm/evidence \
  --support-matrix apps/docs/docs/guide/support-matrix.md \
  --dry-run \
  --plan-output "$final_release_plan_output" >/dev/null
grep -F "dry-run: release evidence:" "$final_release_plan_output" >/dev/null || {
  echo "verify-scripts: final release plan output is missing release evidence command" >&2
  exit 1
}
grep -F "dry-run: Nix release package:" "$final_release_plan_output" >/dev/null || {
  echo "verify-scripts: final release plan output is missing Nix release package command" >&2
  exit 1
}
grep -F "dry-run: release tag ref:" "$final_release_plan_output" >/dev/null || {
  echo "verify-scripts: final release plan output is missing release tag ref command" >&2
  exit 1
}
grep -F "dry-run: docs deployment manifest:" "$final_release_plan_output" >/dev/null || {
  echo "verify-scripts: final release plan output is missing docs deployment manifest command" >&2
  exit 1
}
grep -F "dry-run: VM evidence arch-hyprland-pipewire:" "$final_release_plan_output" >/dev/null || {
  echo "verify-scripts: final release plan output is missing VM evidence command" >&2
  exit 1
}
grep -F "dry-run: package VM evidence archive:" "$final_release_plan_output" >/dev/null || {
  echo "verify-scripts: final release plan output is missing VM evidence archive packaging" >&2
  exit 1
}
grep -F "dry-run: upload VM evidence release assets:" "$final_release_plan_output" >/dev/null || {
  echo "verify-scripts: final release plan output is missing VM evidence release asset upload" >&2
  exit 1
}
grep -F "Final release proof dry-run complete." "$final_release_plan_output" >/dev/null || {
  echo "verify-scripts: final release plan output did not complete" >&2
  exit 1
}
rm -f "$final_release_plan_output"
printf '%s\n' "$final_release_dry_run" | grep -F "scripts/verify-published-release.sh" >/dev/null || {
  echo "verify-scripts: final release dry-run is missing published-release verification" >&2
  exit 1
}
printf '%s\n' "$final_release_dry_run" \
  | grep -F "scripts/verify-published-release.sh" \
  | grep -F -- "--require-github-release-source" >/dev/null || {
    echo "verify-scripts: final release dry-run is missing published-release GitHub-source strictness" >&2
    exit 1
  }
printf '%s\n' "$final_release_dry_run" | grep -F "scripts/verify-release-tag-ref.sh" >/dev/null || {
  echo "verify-scripts: final release dry-run is missing release tag ref verification" >&2
  exit 1
}
printf '%s\n' "$final_release_dry_run" | grep -F "scripts/verify-nix-release-package.sh" >/dev/null || {
  echo "verify-scripts: final release dry-run is missing Nix release package verification" >&2
  exit 1
}
printf '%s\n' "$final_release_dry_run" | grep -F "scripts/verify-docs-live.sh" >/dev/null || {
  echo "verify-scripts: final release dry-run is missing live docs verification" >&2
  exit 1
}
printf '%s\n' "$final_release_dry_run" | grep -F "scripts/verify-docs-deployment-manifest.mjs" >/dev/null || {
  echo "verify-scripts: final release dry-run is missing docs deployment manifest verification" >&2
  exit 1
}
printf '%s\n' "$final_release_dry_run" | grep -F "pnpm build:docs" >/dev/null || {
  echo "verify-scripts: final release dry-run is missing docs build before manifest verification" >&2
  exit 1
}
printf '%s\n' "$final_release_dry_run" | grep -F "scripts/verify-release-evidence.mjs" >/dev/null || {
  echo "verify-scripts: final release dry-run is missing release evidence verification" >&2
  exit 1
}
printf '%s\n' "$final_release_dry_run" | grep -F -- "--require-vm-launch-plan" >/dev/null || {
  echo "verify-scripts: final release dry-run is missing VM launch-plan strictness" >&2
  exit 1
}
printf '%s\n' "$final_release_dry_run" | grep -F -- "--require-dsp-provider-plan" >/dev/null || {
  echo "verify-scripts: final release dry-run is missing DSP provider strictness" >&2
  exit 1
}
printf '%s\n' "$final_release_dry_run" | grep -F "scripts/verify-support-matrix.mjs" >/dev/null || {
  echo "verify-scripts: final release dry-run is missing support matrix verification" >&2
  exit 1
}
printf '%s\n' "$final_release_dry_run" | grep -F "scripts/verify-vm-evidence.sh" >/dev/null || {
  echo "verify-scripts: final release dry-run is missing VM evidence verification" >&2
  exit 1
}
printf '%s\n' "$final_release_dry_run" \
  | grep -F "dry-run: VM evidence arch-hyprland-pipewire:" \
  | grep -F -- "--release-tag v0.1.0" >/dev/null || {
    echo "verify-scripts: final release dry-run is missing VM evidence release tag binding" >&2
    exit 1
  }
printf '%s\n' "$final_release_dry_run" | grep -F "scripts/package-vm-evidence.sh" >/dev/null || {
  echo "verify-scripts: final release dry-run is missing VM evidence archive packaging" >&2
  exit 1
}
printf '%s\n' "$final_release_dry_run" | grep -F "gh release upload" >/dev/null || {
  echo "verify-scripts: final release dry-run is missing VM evidence archive upload" >&2
  exit 1
}
printf '%s\n' "$final_release_dry_run" | grep -F -- "--require-live-docs" >/dev/null || {
  echo "verify-scripts: final release dry-run is missing strict live-docs evidence verification" >&2
  exit 1
}
printf '%s\n' "$final_release_dry_run" \
  | grep -F "dry-run: support matrix:" \
  | grep -F -- "--require-published-release" >/dev/null || {
    echo "verify-scripts: final release dry-run is missing strict support matrix verification" >&2
    exit 1
  }
printf '%s\n' "$final_release_dry_run" \
  | grep -F "dry-run: support matrix:" \
  | grep -F -- "--release-tag v0.1.0" >/dev/null || {
    echo "verify-scripts: final release dry-run is missing support matrix release tag binding" >&2
    exit 1
  }
printf '%s\n' "$final_release_dry_run" | grep -F "Final release proof dry-run complete." >/dev/null || {
  echo "verify-scripts: final release dry-run did not complete" >&2
  exit 1
}
printf '%s\n' "$final_release_dry_run" | node -e '
const fs = require("node:fs");
const output = fs.readFileSync(0, "utf8");
const targets = fs.readFileSync("vm/targets.tsv", "utf8")
  .split(/\r?\n/)
  .filter((line) => line && !line.startsWith("#"))
  .map((line) => line.split("\t")[0]);
for (const target of targets) {
  if (!output.includes(`--target ${target}`) || !output.includes(`.vm/evidence/${target}`)) {
    process.exit(1);
  }
}
' || {
  echo "verify-scripts: final release dry-run did not cover every VM target" >&2
  exit 1
}
if bash scripts/verify-final-release-proof.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --public-key packaging/release-signing-public.pem \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --release-evidence-dir .release-evidence/v0.1.0-published \
  --docs-deployment-manifest dist/docs-deployment/deployment-manifest.json \
  --vm-evidence-root .vm/evidence \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: final release verifier accepted missing live docs target" >&2
  exit 1
fi
if bash scripts/verify-final-release-proof.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --public-key packaging/release-signing-public.pem \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --release-evidence-dir .release-evidence/v0.1.0-published \
  --docs-base-url https://docs.example.test \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: final release verifier accepted missing docs deployment manifest" >&2
  exit 1
fi
if bash scripts/verify-final-release-proof.sh \
  --repo https://github.com/sandwichfarm/loopwire \
  --tag v0.1.0 \
  --public-key packaging/release-signing-public.pem \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --release-evidence-dir .release-evidence/v0.1.0-published \
  --docs-deployment-manifest dist/docs-deployment/deployment-manifest.json \
  --docs-base-url https://docs.example.test \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: final release verifier accepted a URL-like repository" >&2
  exit 1
fi
if bash scripts/verify-final-release-proof.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --public-key packaging/release-signing-public.pem \
  --git-head not-a-sha \
  --release-evidence-dir .release-evidence/v0.1.0-published \
  --docs-deployment-manifest dist/docs-deployment/deployment-manifest.json \
  --docs-base-url https://docs.example.test \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: final release verifier accepted an invalid git head" >&2
  exit 1
fi
if bash scripts/verify-final-release-proof.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --public-key packaging/release-signing-public.pem \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --release-evidence-dir .release-evidence/v0.1.0-published \
  --docs-deployment-manifest dist/docs-deployment/deployment-manifest.json \
  --docs-base-url https://docs.example.test \
  --plan-output /tmp/loopwire-final-proof-plan.txt >/dev/null 2>&1; then
  echo "verify-scripts: final release verifier accepted plan output without dry-run" >&2
  exit 1
fi
if bash scripts/verify-final-release-proof.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --public-key packaging/release-signing-public.pem \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --release-evidence-dir .release-evidence/v0.1.0-published \
  --docs-deployment-manifest dist/docs-deployment/deployment-manifest.json \
  --docs-base-url https://docs.example.test \
  --dry-run \
  --plan-output /tmp/loopwire-final-proof-plan-dry-run.txt >/dev/null 2>&1; then
  echo "verify-scripts: final release verifier accepted plan output outside dist/release" >&2
  exit 1
fi
if bash scripts/verify-final-release-proof.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --public-key packaging/release-signing-public.pem \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --release-evidence-dir .release-evidence/v0.1.0-published \
  --docs-deployment-manifest dist/docs-deployment/deployment-manifest.json \
  --docs-base-url https://docs.example.test \
  --dry-run \
  --plan-output dist/release/../final-release-proof-plan.txt >/dev/null 2>&1; then
  echo "verify-scripts: final release verifier accepted traversal in plan output" >&2
  exit 1
fi
if bash scripts/verify-final-release-proof.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --public-key packaging/release-signing-public.pem \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --release-dir ../release \
  --release-evidence-dir .release-evidence/v0.1.0-published \
  --docs-deployment-manifest dist/docs-deployment/deployment-manifest.json \
  --docs-base-url https://docs.example.test \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: final release verifier accepted traversal in release-dir" >&2
  exit 1
fi
if bash scripts/verify-final-release-proof.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --public-key packaging/release-signing-public.pem \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --release-dir '~/release' \
  --release-evidence-dir .release-evidence/v0.1.0-published \
  --docs-deployment-manifest dist/docs-deployment/deployment-manifest.json \
  --docs-base-url https://docs.example.test \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: final release verifier accepted home expansion in release-dir" >&2
  exit 1
fi
final_release_symlink_root="$(mktemp -d)"
final_release_symlink="$final_release_symlink_root/final-release-dir-symlink"
ln -s "$final_release_symlink_root" "$final_release_symlink"
if bash scripts/verify-final-release-proof.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --public-key packaging/release-signing-public.pem \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --release-dir "$final_release_symlink" \
  --release-evidence-dir .release-evidence/v0.1.0-published \
  --docs-deployment-manifest dist/docs-deployment/deployment-manifest.json \
  --docs-base-url https://docs.example.test \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: final release verifier accepted a symlink release-dir" >&2
  rm -rf "$final_release_symlink_root"
  exit 1
fi
printf '%s\n' "not a directory" >"$final_release_symlink_root/not-a-dir"
if bash scripts/verify-final-release-proof.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --public-key packaging/release-signing-public.pem \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --release-dir "$final_release_symlink_root/not-a-dir" \
  --release-evidence-dir .release-evidence/v0.1.0-published \
  --docs-deployment-manifest dist/docs-deployment/deployment-manifest.json \
  --docs-base-url https://docs.example.test \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: final release verifier accepted a file release-dir" >&2
  rm -rf "$final_release_symlink_root"
  exit 1
fi
rm -rf "$final_release_symlink_root"
final_release_local_path_root="$(mktemp -d)"
final_release_public_key_symlink="$final_release_local_path_root/public-key-symlink.pem"
final_release_release_evidence_file="$final_release_local_path_root/release-evidence-file"
final_release_docs_manifest_dir="$final_release_local_path_root/docs-manifest-dir"
final_release_vm_root_symlink="$final_release_local_path_root/vm-root-symlink"
final_release_support_matrix_dir="$final_release_local_path_root/support-matrix-dir"
ln -s "$PWD/packaging/release-signing-public.pem" "$final_release_public_key_symlink"
printf '%s\n' "not a release evidence directory" >"$final_release_release_evidence_file"
mkdir -p "$final_release_docs_manifest_dir"
ln -s "$final_release_local_path_root" "$final_release_vm_root_symlink"
mkdir -p "$final_release_support_matrix_dir"
if bash scripts/verify-final-release-proof.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --public-key "$final_release_public_key_symlink" \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --release-evidence-dir .release-evidence/v0.1.0-published \
  --docs-deployment-manifest dist/docs-deployment/deployment-manifest.json \
  --docs-base-url https://docs.example.test \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: final release verifier accepted a symlink public key" >&2
  rm -rf "$final_release_local_path_root"
  exit 1
fi
if bash scripts/verify-final-release-proof.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --public-key packaging/release-signing-public.pem \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --release-evidence-dir "$final_release_release_evidence_file" \
  --docs-deployment-manifest dist/docs-deployment/deployment-manifest.json \
  --docs-base-url https://docs.example.test \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: final release verifier accepted a file release evidence directory" >&2
  rm -rf "$final_release_local_path_root"
  exit 1
fi
if bash scripts/verify-final-release-proof.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --public-key packaging/release-signing-public.pem \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --release-evidence-dir .release-evidence/v0.1.0-published \
  --docs-deployment-manifest "$final_release_docs_manifest_dir" \
  --docs-base-url https://docs.example.test \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: final release verifier accepted a directory docs deployment manifest" >&2
  rm -rf "$final_release_local_path_root"
  exit 1
fi
if bash scripts/verify-final-release-proof.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --public-key packaging/release-signing-public.pem \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --release-evidence-dir .release-evidence/v0.1.0-published \
  --docs-deployment-manifest dist/docs-deployment/deployment-manifest.json \
  --docs-base-url https://docs.example.test \
  --vm-evidence-root "$final_release_vm_root_symlink" \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: final release verifier accepted a symlink VM evidence root" >&2
  rm -rf "$final_release_local_path_root"
  exit 1
fi
if bash scripts/verify-final-release-proof.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --public-key packaging/release-signing-public.pem \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --release-evidence-dir .release-evidence/v0.1.0-published \
  --docs-deployment-manifest dist/docs-deployment/deployment-manifest.json \
  --docs-base-url https://docs.example.test \
  --support-matrix "$final_release_support_matrix_dir" \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: final release verifier accepted a directory support matrix" >&2
  rm -rf "$final_release_local_path_root"
  exit 1
fi
rm -rf "$final_release_local_path_root"
bash scripts/validate-release-asset-name.sh \
  --kind release-evidence \
  --tag v0.1.0 \
  --asset loopwire-release-evidence-v0.1.0.tar.gz >/dev/null
bash scripts/validate-release-asset-name.sh \
  --kind vm-evidence \
  --tag v0.1.0 \
  --asset loopwire-vm-evidence-v0.1.0-operator-run.tar.gz >/dev/null
if bash scripts/validate-release-asset-name.sh \
  --kind release-evidence \
  --tag v0.1.0 \
  --asset ../loopwire-release-evidence-v0.1.0.tar.gz >/dev/null 2>&1; then
  echo "verify-scripts: release asset validator accepted path traversal" >&2
  exit 1
fi
if bash scripts/validate-release-asset-name.sh \
  --kind release-evidence \
  --tag v0.1.0 \
  --asset 'loopwire-release-evidence-v0.1.0*.tar.gz' >/dev/null 2>&1; then
  echo "verify-scripts: release asset validator accepted a glob pattern" >&2
  exit 1
fi
if bash scripts/validate-release-asset-name.sh \
  --kind vm-evidence \
  --tag v0.1.0 \
  --asset loopwire-release-evidence-v0.1.0.tar.gz >/dev/null 2>&1; then
  echo "verify-scripts: release asset validator accepted the wrong evidence kind" >&2
  exit 1
fi
if bash scripts/validate-release-asset-name.sh \
  --kind vm-evidence \
  --tag v0.1.0 \
  --asset loopwire-vm-evidence-v0.2.0.tar.gz >/dev/null 2>&1; then
  echo "verify-scripts: release asset validator accepted a mismatched tag" >&2
  exit 1
fi
printf '%s\n' "$release_readiness_help" | grep -F -- "--skip-clean-git" >/dev/null || {
  echo "verify-scripts: release readiness help is missing clean-git opt-out" >&2
  exit 1
}
printf '%s\n' "$collect_evidence_help" | grep -F -- "--release-tag TAG" >/dev/null || {
  echo "verify-scripts: release evidence help is missing release tag support" >&2
  exit 1
}
printf '%s\n' "$collect_evidence_help" | grep -F -- "--public-key FILE" >/dev/null || {
  echo "verify-scripts: release evidence help is missing public key support" >&2
  exit 1
}
printf '%s\n' "$collect_evidence_help" | grep -F -- "--require-published-release" >/dev/null || {
  echo "verify-scripts: release evidence help is missing published-release requirement support" >&2
  exit 1
}
printf '%s\n' "$collect_evidence_help" | grep -F -- "--docs-base-url URL" >/dev/null || {
  echo "verify-scripts: release evidence help is missing live docs URL support" >&2
  exit 1
}
printf '%s\n' "$collect_evidence_help" | grep -F -- "--docs-hostname HOST" >/dev/null || {
  echo "verify-scripts: release evidence help is missing live docs hostname support" >&2
  exit 1
}
printf '%s\n' "$collect_evidence_help" | grep -F -- "--require-live-docs" >/dev/null || {
  echo "verify-scripts: release evidence help is missing live docs requirement support" >&2
  exit 1
}
printf '%s\n' "$collect_evidence_help" | grep -F -- "--require-nix-release" >/dev/null || {
  echo "verify-scripts: release evidence help is missing Nix release requirement support" >&2
  exit 1
}
printf '%s\n' "$collect_evidence_help" | grep -F -- "--vm-target TARGET" >/dev/null || {
  echo "verify-scripts: release evidence help is missing VM target support" >&2
  exit 1
}
printf '%s\n' "$collect_evidence_help" | grep -F -- 'Use "all" to expand every target from vm/targets.tsv' >/dev/null || {
  echo "verify-scripts: release evidence help is missing all-target VM support" >&2
  exit 1
}
printf '%s\n' "$collect_evidence_help" | grep -F -- "--vm-evidence-dir DIR" >/dev/null || {
  echo "verify-scripts: release evidence help is missing VM evidence directory support" >&2
  exit 1
}
printf '%s\n' "$collect_evidence_help" | grep -F -- "--vm-launch-image-root DIR" >/dev/null || {
  echo "verify-scripts: release evidence help is missing VM launch image root support" >&2
  exit 1
}
printf '%s\n' "$collect_evidence_help" | grep -F -- "--vm-launch-start-port PORT" >/dev/null || {
  echo "verify-scripts: release evidence help is missing VM launch start port support" >&2
  exit 1
}
printf '%s\n' "$collect_evidence_help" | grep -F -- "--require-vm-evidence" >/dev/null || {
  echo "verify-scripts: release evidence help is missing VM evidence requirement support" >&2
  exit 1
}
printf '%s\n' "$collect_evidence_help" | grep -F -- "--dsp-configuration FILE" >/dev/null || {
  echo "verify-scripts: release evidence help is missing DSP configuration support" >&2
  exit 1
}
printf '%s\n' "$collect_evidence_help" | grep -F -- "--dsp-frame-count N" >/dev/null || {
  echo "verify-scripts: release evidence help is missing DSP frame-count support" >&2
  exit 1
}
printf '%s\n' "$collect_evidence_help" | grep -F -- "--require-dsp-provider-plan" >/dev/null || {
  echo "verify-scripts: release evidence help is missing DSP provider requirement support" >&2
  exit 1
}
printf '%s\n' "$collect_evidence_help" | grep -F -- "--summarize-release-readiness-log FILE" >/dev/null || {
  echo "verify-scripts: release evidence help is missing readiness log summary support" >&2
  exit 1
}
collect_evidence_full_plan="$(
  node scripts/collect-release-evidence.mjs \
    --list-commands \
    --profile full \
    --release-tag v0.1.0 \
    --repo sandwichfarm/loopwire \
    --public-key packaging/release-signing-public.pem
)"
printf '%s\n' "$collect_evidence_full_plan" | grep -F '"name": "published-release-smoke"' >/dev/null || {
  echo "verify-scripts: full release evidence plan is missing published-release smoke" >&2
  exit 1
}
printf '%s\n' "$collect_evidence_full_plan" | node -e '
const fs = require("node:fs");
const plan = JSON.parse(fs.readFileSync(0, "utf8"));
const readiness = plan.find((entry) => entry.name === "release-readiness-offline");
if (!readiness || !readiness.command.includes("--skip-clean-git")) process.exit(1);
if (readiness.command.includes("--allow-candidate-notes")) process.exit(1);
' || {
  echo "verify-scripts: full release evidence plan should keep offline readiness strict but dirty-git tolerant" >&2
  exit 1
}
printf '%s\n' "$collect_evidence_full_plan" | node -e '
const fs = require("node:fs");
const plan = JSON.parse(fs.readFileSync(0, "utf8"));
const launch = plan.find((entry) => entry.name === "vm-launch-plan");
if (!launch || launch.required !== true) process.exit(1);
if (!launch.command.includes("scripts/vm-matrix.sh")) process.exit(1);
if (!launch.command.includes("render-launch-plan")) process.exit(1);
if (!launch.command.includes("--all")) process.exit(1);
' || {
  echo "verify-scripts: full release evidence plan is missing VM launch plan" >&2
  exit 1
}
printf '%s\n' "$collect_evidence_full_plan" | node -e '
const fs = require("node:fs");
const plan = JSON.parse(fs.readFileSync(0, "utf8"));
const dsp = plan.find((entry) => entry.name === "dsp-provider-plan");
if (!dsp || dsp.required !== true) process.exit(1);
if (!dsp.command.includes("scripts/collect-dsp-provider-plan.sh")) process.exit(1);
if (!dsp.command.includes("--configuration")) process.exit(1);
if (!dsp.command.includes("scripts/fixtures/dsp-provider-configuration.json")) process.exit(1);
if (dsp.command.includes("--execute")) process.exit(1);
' || {
  echo "verify-scripts: full release evidence plan is missing required DSP provider plan" >&2
  exit 1
}
printf '%s\n' "$collect_evidence_full_plan" | node -e '
const fs = require("node:fs");
const plan = JSON.parse(fs.readFileSync(0, "utf8"));
const item = plan.find((entry) => entry.name === "published-release-smoke");
if (!item || item.required !== false) process.exit(1);
' || {
  echo "verify-scripts: full release evidence plan should keep published-release smoke optional by default" >&2
  exit 1
}
printf '%s\n' "$collect_evidence_full_plan" | node -e '
const fs = require("node:fs");
const plan = JSON.parse(fs.readFileSync(0, "utf8"));
const item = plan.find((entry) => entry.name === "nix-release-package");
if (!item || item.required !== false) process.exit(1);
if (!item.command.includes("scripts/verify-nix-release-package.sh")) process.exit(1);
if (!item.command.includes("--repo")) process.exit(1);
if (!item.command.includes("--tag")) process.exit(1);
if (item.command.includes("--skip-build-if-missing-nix")) process.exit(1);
if (item.command.includes("--render-only")) process.exit(1);
' || {
  echo "verify-scripts: full release evidence plan should include optional Nix release proof" >&2
  exit 1
}
printf '%s\n' "$collect_evidence_full_plan" | grep -F '"name": "vm-evidence"' >/dev/null || {
  echo "verify-scripts: full release evidence plan is missing VM evidence" >&2
  exit 1
}
printf '%s\n' "$collect_evidence_full_plan" | node -e '
const fs = require("node:fs");
const plan = JSON.parse(fs.readFileSync(0, "utf8"));
const item = plan.find((entry) => entry.name === "vm-evidence");
if (!item || item.required !== false) process.exit(1);
if (!item.command.includes("scripts/verify-vm-evidence.sh")) process.exit(1);
if (!item.command.includes(".vm/evidence/arch-hyprland-pipewire")) process.exit(1);
' || {
  echo "verify-scripts: full release evidence plan should keep VM evidence optional by default" >&2
  exit 1
}
collect_evidence_full_docs_plan="$(
  node scripts/collect-release-evidence.mjs \
    --list-commands \
    --profile full \
    --docs-base-url https://docs.example.test \
    --release-tag v0.1.0 \
    --repo sandwichfarm/loopwire \
    --public-key packaging/release-signing-public.pem
)"
printf '%s\n' "$collect_evidence_full_docs_plan" | node -e '
const fs = require("node:fs");
const plan = JSON.parse(fs.readFileSync(0, "utf8"));
const item = plan.find((entry) => entry.name === "docs-live-smoke");
if (!item || item.required !== false) process.exit(1);
if (!item.command.includes("scripts/verify-docs-live.sh")) process.exit(1);
if (!item.command.includes("--base-url")) process.exit(1);
' || {
  echo "verify-scripts: full release evidence plan should include optional live docs smoke when configured" >&2
  exit 1
}
collect_evidence_required_plan="$(
  node scripts/collect-release-evidence.mjs \
    --list-commands \
    --profile quick \
    --require-published-release \
    --require-nix-release \
    --release-tag v0.1.0 \
    --repo sandwichfarm/loopwire \
    --public-key packaging/release-signing-public.pem
)"
printf '%s\n' "$collect_evidence_required_plan" | grep -F '"name": "published-release-smoke"' >/dev/null || {
  echo "verify-scripts: required release evidence plan is missing published-release smoke" >&2
  exit 1
}
printf '%s\n' "$collect_evidence_required_plan" | node -e '
const fs = require("node:fs");
const plan = JSON.parse(fs.readFileSync(0, "utf8"));
const item = plan.find((entry) => entry.name === "published-release-smoke");
if (!item || item.required !== true) process.exit(1);
' || {
  echo "verify-scripts: required release evidence plan did not make published-release smoke required" >&2
  exit 1
}
printf '%s\n' "$collect_evidence_required_plan" | node -e '
const fs = require("node:fs");
const plan = JSON.parse(fs.readFileSync(0, "utf8"));
const item = plan.find((entry) => entry.name === "nix-release-package");
if (!item || item.required !== true) process.exit(1);
if (!item.command.includes("scripts/verify-nix-release-package.sh")) process.exit(1);
if (!item.command.includes("--public-key")) process.exit(1);
' || {
  echo "verify-scripts: required release evidence plan did not make Nix release proof required" >&2
  exit 1
}
collect_evidence_live_docs_required_plan="$(
  node scripts/collect-release-evidence.mjs \
    --list-commands \
    --profile quick \
    --require-live-docs \
    --docs-hostname docs.example.test \
    --docs-remote-prefix preview
)"
printf '%s\n' "$collect_evidence_live_docs_required_plan" | node -e '
const fs = require("node:fs");
const plan = JSON.parse(fs.readFileSync(0, "utf8"));
const item = plan.find((entry) => entry.name === "docs-live-smoke");
if (!item || item.required !== true) process.exit(1);
if (!item.command.includes("--hostname")) process.exit(1);
if (!item.command.includes("--remote-prefix")) process.exit(1);
' || {
  echo "verify-scripts: required release evidence plan did not make live docs smoke required" >&2
  exit 1
}
if node scripts/collect-release-evidence.mjs \
  --list-commands \
  --profile quick \
  --require-live-docs >/dev/null 2>&1; then
  echo "verify-scripts: release evidence accepted required live docs without a URL or hostname" >&2
  exit 1
fi
if node scripts/collect-release-evidence.mjs \
  --list-commands \
  --profile quick \
  --release-tag v0.1.0/preview >/dev/null 2>&1; then
  echo "verify-scripts: release evidence accepted a path-like release tag" >&2
  exit 1
fi
if node scripts/collect-release-evidence.mjs \
  --list-commands \
  --profile quick \
  --repo https://github.com/sandwichfarm/loopwire >/dev/null 2>&1; then
  echo "verify-scripts: release evidence accepted a URL-like repository" >&2
  exit 1
fi
if node scripts/collect-release-evidence.mjs \
  --list-commands \
  --profile quick \
  --vm-launch-start-port nope >/dev/null 2>&1; then
  echo "verify-scripts: release evidence accepted an invalid VM launch start port" >&2
  exit 1
fi
if node scripts/collect-release-evidence.mjs \
  --list-commands \
  --profile quick \
  --dsp-configuration ../unsafe.json >/dev/null 2>&1; then
  echo "verify-scripts: release evidence accepted an unsafe DSP configuration path" >&2
  exit 1
fi
if node scripts/collect-release-evidence.mjs \
  --list-commands \
  --profile quick \
  --dsp-frame-count nope >/dev/null 2>&1; then
  echo "verify-scripts: release evidence accepted an invalid DSP frame count" >&2
  exit 1
fi
collect_evidence_dsp_required_plan="$(
  node scripts/collect-release-evidence.mjs \
    --list-commands \
    --profile quick \
    --require-dsp-provider-plan \
    --dsp-configuration scripts/fixtures/dsp-provider-configuration.json \
    --dsp-frame-count 8
)"
printf '%s\n' "$collect_evidence_dsp_required_plan" | node -e '
const fs = require("node:fs");
const plan = JSON.parse(fs.readFileSync(0, "utf8"));
const dsp = plan.find((entry) => entry.name === "dsp-provider-plan");
if (!dsp || dsp.required !== true) process.exit(1);
if (!dsp.command.includes("--frame-count")) process.exit(1);
if (!dsp.command.includes("8")) process.exit(1);
' || {
  echo "verify-scripts: required release evidence plan did not make DSP provider plan required" >&2
  exit 1
}
collect_evidence_vm_required_plan="$(
  node scripts/collect-release-evidence.mjs \
    --list-commands \
    --profile quick \
    --require-vm-evidence \
    --vm-target arch-hyprland-pipewire \
    --vm-evidence-dir .vm/evidence/arch-hyprland-pipewire
)"
printf '%s\n' "$collect_evidence_vm_required_plan" | grep -F '"name": "vm-evidence"' >/dev/null || {
  echo "verify-scripts: required release evidence plan is missing VM evidence" >&2
  exit 1
}
printf '%s\n' "$collect_evidence_vm_required_plan" | node -e '
const fs = require("node:fs");
const plan = JSON.parse(fs.readFileSync(0, "utf8"));
const item = plan.find((entry) => entry.name === "vm-evidence");
if (!item || item.required !== true) process.exit(1);
' || {
  echo "verify-scripts: required release evidence plan did not make VM evidence required" >&2
  exit 1
}
collect_evidence_combined_required_plan="$(
  node scripts/collect-release-evidence.mjs \
    --list-commands \
    --profile quick \
    --require-published-release \
    --require-vm-evidence \
    --release-tag v0.1.0 \
    --repo sandwichfarm/loopwire \
    --public-key packaging/release-signing-public.pem \
    --vm-target arch-hyprland-pipewire \
    --vm-evidence-dir .vm/evidence/arch-hyprland-pipewire
)"
printf '%s\n' "$collect_evidence_combined_required_plan" | node -e '
const fs = require("node:fs");
const plan = JSON.parse(fs.readFileSync(0, "utf8"));
const item = plan.find((entry) => entry.name === "vm-evidence");
if (!item || !item.command.includes("--require-published-release")) process.exit(1);
if (!item.command.includes("--release-tag") || !item.command.includes("v0.1.0")) process.exit(1);
' || {
  echo "verify-scripts: VM evidence plan did not inherit published-release strictness" >&2
  exit 1
}
collect_evidence_all_vm_plan="$(
  node scripts/collect-release-evidence.mjs \
    --list-commands \
    --profile quick \
    --require-published-release \
    --require-vm-evidence \
    --release-tag v0.1.0 \
    --repo sandwichfarm/loopwire \
    --public-key packaging/release-signing-public.pem \
    --vm-target all \
    --vm-evidence-dir '.vm/evidence/{target}'
)"
printf '%s\n' "$collect_evidence_all_vm_plan" | node -e '
const fs = require("node:fs");
const plan = JSON.parse(fs.readFileSync(0, "utf8"));
const targets = fs.readFileSync("vm/targets.tsv", "utf8")
  .split(/\r?\n/)
  .filter((line) => line && !line.startsWith("#"));
const vmItems = plan.filter((entry) => entry.name.startsWith("vm-evidence"));
if (vmItems.length !== targets.length) process.exit(1);
if (!vmItems.every((entry) => entry.required === true)) process.exit(1);
if (!vmItems.some((entry) => entry.name === "vm-evidence:fedora-kde-jack")) process.exit(1);
if (!vmItems.every((entry) => entry.command.includes("--require-published-release"))) process.exit(1);
if (!vmItems.every((entry) => entry.command.includes("--release-tag") && entry.command.includes("v0.1.0"))) process.exit(1);
if (!vmItems.some((entry) => entry.command.includes(".vm/evidence/debian-xfce-pulseaudio"))) process.exit(1);
if (!vmItems.some((entry) => entry.name === "vm-evidence:opensuse-kde-pipewire")) process.exit(1);
if (!vmItems.some((entry) => entry.name === "vm-evidence:ubuntu-gnome-pipewire-aarch64")) process.exit(1);
' || {
  echo "verify-scripts: all-target VM release evidence plan is incomplete" >&2
  exit 1
}
if node scripts/collect-release-evidence.mjs \
  --list-commands \
  --profile quick \
  --require-vm-evidence \
  --vm-target not-a-target >/dev/null 2>&1; then
  echo "verify-scripts: release evidence accepted an unknown VM target" >&2
  exit 1
fi
if node scripts/collect-release-evidence.mjs \
  --list-commands \
  --profile quick \
  --require-vm-evidence \
  --vm-target all \
  --vm-evidence-dir .vm/evidence >/dev/null 2>&1; then
  echo "verify-scripts: release evidence accepted a shared VM evidence dir for multiple targets" >&2
  exit 1
fi
release_evidence_path_tmp="$(mktemp -d)"
bad_release_evidence_output_file="$release_evidence_path_tmp/release-evidence-output-file"
printf 'not a directory\n' >"$bad_release_evidence_output_file"
if node scripts/collect-release-evidence.mjs \
  --output-dir "$bad_release_evidence_output_file" \
  --profile quick >/dev/null 2>&1; then
  echo "verify-scripts: release evidence accepted a file-valued output dir" >&2
  rm -rf "$release_evidence_path_tmp"
  exit 1
fi
bad_release_evidence_output_link="$release_evidence_path_tmp/release-evidence-output-link"
ln -s "$release_evidence_path_tmp" "$bad_release_evidence_output_link"
if node scripts/collect-release-evidence.mjs \
  --output-dir "$bad_release_evidence_output_link" \
  --profile quick >/dev/null 2>&1; then
  echo "verify-scripts: release evidence accepted a symlinked output dir" >&2
  rm -rf "$release_evidence_path_tmp"
  exit 1
fi
bad_release_readiness_log_dir="$release_evidence_path_tmp/release-readiness-log-dir"
mkdir -p "$bad_release_readiness_log_dir"
if node scripts/collect-release-evidence.mjs \
  --summarize-release-readiness-log "$bad_release_readiness_log_dir" >/dev/null 2>&1; then
  echo "verify-scripts: release evidence accepted a directory readiness log" >&2
  rm -rf "$release_evidence_path_tmp"
  exit 1
fi
rm -rf "$release_evidence_path_tmp"
node scripts/restore-background.mjs --help | grep -F -- "--retry-pending-ms" >/dev/null || {
  echo "verify-scripts: restore background help is missing pending retry options" >&2
  exit 1
}
node scripts/restore-background.mjs --help | grep -F -- "--jack-provider-command" >/dev/null || {
  echo "verify-scripts: restore background help is missing JACK provider options" >&2
  exit 1
}
node scripts/restore-background.mjs --help | grep -F -- "--dsp-provider-command" >/dev/null || {
  echo "verify-scripts: restore background help is missing DSP provider options" >&2
  exit 1
}
node scripts/restore-background.mjs --help | grep -F -- "--dsp-provider-mode" >/dev/null || {
  echo "verify-scripts: restore background help is missing DSP provider mode option" >&2
  exit 1
}
grep -F "Open Loopwire, use Settings > Audio backend to save a verified backend" \
  scripts/restore-background.mjs >/dev/null || {
    echo "verify-scripts: restore background backend guidance is missing the Settings recovery path" >&2
    exit 1
  }
grep -F "Multiple backends are available (" scripts/restore-background.mjs >/dev/null || {
  echo "verify-scripts: restore background backend ambiguity error does not name candidates" >&2
  exit 1
}
restore_missing_tmp="$(mktemp -d)"
missing_restore_state_file="$restore_missing_tmp/missing-loopwire-state.json"
missing_restore_state_log="$restore_missing_tmp/restore-missing-state.log"
if node scripts/restore-background.mjs --state-file "$missing_restore_state_file" >"$missing_restore_state_log" 2>&1; then
  echo "verify-scripts: restore background accepted a missing persisted state file" >&2
  rm -rf "$restore_missing_tmp"
  exit 1
fi
grep -F "Could not read persisted Loopwire state at $missing_restore_state_file" \
  "$missing_restore_state_log" >/dev/null || {
    echo "verify-scripts: restore background missing-state error did not name the state file" >&2
    rm -rf "$restore_missing_tmp"
    exit 1
  }
grep -F "Open Loopwire once, choose a configuration, and enable Restore on boot again." \
  "$missing_restore_state_log" >/dev/null || {
    echo "verify-scripts: restore background missing-state error is not actionable" >&2
    rm -rf "$restore_missing_tmp"
    exit 1
  }
rm -rf "$restore_missing_tmp"
if node scripts/restore-background.mjs --mode preview --retry-pending-ms 1 >/dev/null 2>&1; then
  echo "verify-scripts: restore background accepted pending retries outside live mode" >&2
  exit 1
fi
if node scripts/restore-background.mjs --jack-provider-timeout-ms 0 >/dev/null 2>&1; then
  echo "verify-scripts: restore background accepted invalid JACK provider timeout" >&2
  exit 1
fi
if node scripts/restore-background.mjs --backend dsp >/dev/null 2>&1; then
  echo "verify-scripts: restore background accepted DSP backend without provider command" >&2
  exit 1
fi
if node scripts/restore-background.mjs --dsp-provider-command loopwire-dsp-provider >/dev/null 2>&1; then
  echo "verify-scripts: restore background accepted DSP provider command without DSP backend" >&2
  exit 1
fi
if node scripts/restore-background.mjs \
  --backend dsp \
  --dsp-provider-command loopwire-dsp-provider \
  --dsp-provider-timeout-ms 0 >/dev/null 2>&1; then
  echo "verify-scripts: restore background accepted invalid DSP provider timeout" >&2
  exit 1
fi
if node scripts/restore-background.mjs \
  --backend dsp \
  --dsp-provider-command loopwire-dsp-provider \
  --dsp-provider-mode banana >/dev/null 2>&1; then
  echo "verify-scripts: restore background accepted invalid DSP provider mode" >&2
  exit 1
fi
if node scripts/restore-background.mjs \
  --backend dsp \
  --mode live \
  --dsp-provider-command loopwire-dsp-provider >/dev/null 2>&1; then
  echo "verify-scripts: restore background accepted live DSP without explicit live provider mode" >&2
  exit 1
fi
if node scripts/restore-background.mjs \
  --backend dsp \
  --dsp-provider-command loopwire-dsp-provider \
  --dsp-frame-count 0 >/dev/null 2>&1; then
  echo "verify-scripts: restore background accepted invalid DSP frame count" >&2
  exit 1
fi
if node scripts/restore-background.mjs \
  --backend dsp \
  --dsp-provider-command loopwire-dsp-provider \
  --jack-provider-command loopwire-jack-ports >/dev/null 2>&1; then
  echo "verify-scripts: restore background accepted DSP and JACK provider commands together" >&2
  exit 1
fi
node scripts/collect-support-bundle.mjs --help >/dev/null
node scripts/collect-support-bundle.mjs --help | grep -F -- "--jack-ports-file FILE" >/dev/null || {
  echo "verify-scripts: support bundle help is missing JACK readiness options" >&2
  exit 1
}
node scripts/collect-support-bundle.mjs --help | grep -F -- "--include-dsp-provider-plan" >/dev/null || {
  echo "verify-scripts: support bundle help is missing DSP provider plan option" >&2
  exit 1
}
node scripts/collect-support-bundle.mjs --help | grep -F -- "--dsp-provider-command COMMAND" >/dev/null || {
  echo "verify-scripts: support bundle help is missing DSP provider command option" >&2
  exit 1
}
node scripts/describe-jack-ports.mjs --help | grep -F -- "--loopwire-owned-only" >/dev/null || {
  echo "verify-scripts: JACK port description help is missing Loopwire-owned filtering" >&2
  exit 1
}
node scripts/describe-jack-ports.mjs --help | grep -F -- "--verify" >/dev/null || {
  echo "verify-scripts: JACK port description help is missing readiness verification" >&2
  exit 1
}
node scripts/describe-dsp-provider.mjs --help | grep -F -- "--provider-command COMMAND" >/dev/null || {
  echo "verify-scripts: DSP provider description help is missing provider command option" >&2
  exit 1
}
node scripts/describe-dsp-provider.mjs --help | grep -F -- "--execute" >/dev/null || {
  echo "verify-scripts: DSP provider description help is missing execute option" >&2
  exit 1
}
node scripts/describe-dsp-provider.mjs --help | grep -F -- "--require-live-capability" >/dev/null || {
  echo "verify-scripts: DSP provider description help is missing live capability option" >&2
  exit 1
}
bash scripts/collect-vm-evidence.sh --help >/dev/null
bash scripts/collect-vm-evidence-ssh.sh --help >/dev/null
bash scripts/collect-vm-matrix-evidence.sh --help >/dev/null
bash scripts/package-vm-evidence.sh --help >/dev/null
collect_vm_help="$(bash scripts/collect-vm-evidence.sh --help)"
printf '%s\n' "$collect_vm_help" | grep -F -- "--published-release-dir DIR" >/dev/null || {
  echo "verify-scripts: VM evidence collector help is missing published release directory support" >&2
  exit 1
}
printf '%s\n' "$collect_vm_help" | grep -F -- "--require-published-release" >/dev/null || {
  echo "verify-scripts: VM evidence collector help is missing required published release support" >&2
  exit 1
}
printf '%s\n' "$collect_vm_help" | grep -F -- "--require-github-release-source" >/dev/null || {
  echo "verify-scripts: VM evidence collector help is missing GitHub release source support" >&2
  exit 1
}
collect_vm_ssh_help="$(bash scripts/collect-vm-evidence-ssh.sh --help)"
printf '%s\n' "$collect_vm_ssh_help" | grep -F -- "--published-release-dir DIR" >/dev/null || {
  echo "verify-scripts: SSH VM evidence collector help is missing published release directory support" >&2
  exit 1
}
printf '%s\n' "$collect_vm_ssh_help" | grep -F -- "--require-published-release" >/dev/null || {
  echo "verify-scripts: SSH VM evidence collector help is missing required published release support" >&2
  exit 1
}
printf '%s\n' "$collect_vm_ssh_help" | grep -F -- "--require-github-release-source" >/dev/null || {
  echo "verify-scripts: SSH VM evidence collector help is missing GitHub release source support" >&2
  exit 1
}
collect_vm_matrix_help="$(bash scripts/collect-vm-matrix-evidence.sh --help)"
printf '%s\n' "$collect_vm_matrix_help" | grep -F -- "--plan FILE" >/dev/null || {
  echo "verify-scripts: matrix VM evidence collector help is missing plan support" >&2
  exit 1
}
printf '%s\n' "$collect_vm_matrix_help" | grep -F -- "--require-published-release" >/dev/null || {
  echo "verify-scripts: matrix VM evidence collector help is missing required published release support" >&2
  exit 1
}
printf '%s\n' "$collect_vm_matrix_help" | grep -F -- "--require-github-release-source" >/dev/null || {
  echo "verify-scripts: matrix VM evidence collector help is missing GitHub release source support" >&2
  exit 1
}
printf '%s\n' "$collect_vm_matrix_help" | grep -F -- "--require-all-targets" >/dev/null || {
  echo "verify-scripts: matrix VM evidence collector help is missing all-target requirement support" >&2
  exit 1
}
package_vm_evidence_help="$(bash scripts/package-vm-evidence.sh --help)"
printf '%s\n' "$package_vm_evidence_help" | grep -F -- "scripts/extract-safe-tar.sh" >/dev/null || {
  echo "verify-scripts: VM evidence packager help is missing safe archive validation" >&2
  exit 1
}
printf '%s\n' "$package_vm_evidence_help" | grep -F -- "--require-published-release" >/dev/null || {
  echo "verify-scripts: VM evidence packager help is missing published release strictness support" >&2
  exit 1
}
printf '%s\n' "$package_vm_evidence_help" | grep -F -- "vm-evidence/<target>" >/dev/null || {
  echo "verify-scripts: VM evidence packager help is missing archive layout" >&2
  exit 1
}
printf '%s\n' "$package_vm_evidence_help" | grep -F -- "vm-evidence/manifest.json" >/dev/null || {
  echo "verify-scripts: VM evidence packager help is missing archive manifest layout" >&2
  exit 1
}
printf '%s\n' "$package_vm_evidence_help" | grep -F -- "scripts/validate-release-asset-name.sh" >/dev/null || {
  echo "verify-scripts: VM evidence packager help is missing output asset-name validation" >&2
  exit 1
}
prepare_vm_release_help="$(bash scripts/prepare-vm-evidence-release-asset.sh --help)"
bash scripts/prepare-vm-evidence-release-asset.sh -- --help >/dev/null || {
  echo "verify-scripts: VM evidence release helper does not accept the package-script argument separator" >&2
  exit 1
}
printf '%s\n' "$prepare_vm_release_help" | grep -F -- "--env-file FILE" >/dev/null || {
  echo "verify-scripts: VM evidence release helper help is missing env-file support" >&2
  exit 1
}
printf '%s\n' "$prepare_vm_release_help" | grep -F -- "regenerates SHA256SUMS" >/dev/null || {
  echo "verify-scripts: VM evidence release helper help is missing manifest refresh behavior" >&2
  exit 1
}
printf '%s\n' "$prepare_vm_release_help" | grep -F -- "gh release upload --clobber" >/dev/null || {
  echo "verify-scripts: VM evidence release helper help is missing upload handoff behavior" >&2
  exit 1
}
printf '%s\n' "$prepare_vm_release_help" | grep -F -- "Custom --release-dir values" >/dev/null || {
  echo "verify-scripts: VM evidence release helper help is missing release-dir safety contract" >&2
  exit 1
}
prepare_vm_release_dry_run="$(
  bash scripts/prepare-vm-evidence-release-asset.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --release-dir dist/release \
    --private-key '${LOOPWIRE_RELEASE_PRIVATE_KEY_FILE}' \
    --public-key packaging/release-signing-public.pem \
    --evidence-root .vm/evidence \
    --all \
    --dry-run
)"
printf '%s\n' "$prepare_vm_release_dry_run" | grep -F -- "dry-run: package VM evidence archive:" >/dev/null || {
  echo "verify-scripts: VM evidence release helper dry-run is missing package step" >&2
  exit 1
}
printf '%s\n' "$prepare_vm_release_dry_run" | grep -F -- "dry-run: refresh signed release manifest:" >/dev/null || {
  echo "verify-scripts: VM evidence release helper dry-run is missing manifest refresh step" >&2
  exit 1
}
printf '%s\n' "$prepare_vm_release_dry_run" | grep -F -- "dry-run: upload VM evidence release assets:" >/dev/null || {
  echo "verify-scripts: VM evidence release helper dry-run is missing upload step" >&2
  exit 1
}
if bash scripts/prepare-vm-evidence-release-asset.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --release-dir ../release \
  --private-key '${LOOPWIRE_RELEASE_PRIVATE_KEY_FILE}' \
  --evidence-root .vm/evidence \
  --all \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: VM evidence release helper accepted parent traversal in release-dir" >&2
  exit 1
fi
if bash scripts/prepare-vm-evidence-release-asset.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --release-dir '~/release' \
  --private-key '${LOOPWIRE_RELEASE_PRIVATE_KEY_FILE}' \
  --evidence-root .vm/evidence \
  --all \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: VM evidence release helper accepted home expansion in release-dir" >&2
  exit 1
fi
prepare_vm_release_symlink_root="$(mktemp -d)"
prepare_vm_release_symlink="$prepare_vm_release_symlink_root/prepare-vm-release-dir-symlink"
ln -s "$prepare_vm_release_symlink_root" "$prepare_vm_release_symlink"
if bash scripts/prepare-vm-evidence-release-asset.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --release-dir "$prepare_vm_release_symlink" \
  --private-key '${LOOPWIRE_RELEASE_PRIVATE_KEY_FILE}' \
  --evidence-root .vm/evidence \
  --all \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: VM evidence release helper accepted a symlink release-dir" >&2
  rm -rf "$prepare_vm_release_symlink_root"
  exit 1
fi
rm -rf "$prepare_vm_release_symlink_root"
prepare_vm_release_path_guard_root="$(mktemp -d)"
prepare_vm_release_env_file="$prepare_vm_release_path_guard_root/release.env"
prepare_vm_release_env_symlink="$prepare_vm_release_path_guard_root/release-env-symlink"
prepare_vm_release_private_key="$prepare_vm_release_path_guard_root/release-private.pem"
prepare_vm_release_private_key_symlink="$prepare_vm_release_path_guard_root/release-private-symlink.pem"
prepare_vm_release_public_key_dir="$prepare_vm_release_path_guard_root/release-public-dir"
prepare_vm_release_evidence_root_file="$prepare_vm_release_path_guard_root/evidence-root-file"
printf '%s\n' "LOOPWIRE_RELEASE_PRIVATE_KEY_FILE=/secure/env-loopwire-release-private.pem" \
  >"$prepare_vm_release_env_file"
ln -s "$prepare_vm_release_env_file" "$prepare_vm_release_env_symlink"
printf '%s\n' "not needed for dry-run" >"$prepare_vm_release_private_key"
ln -s "$prepare_vm_release_private_key" "$prepare_vm_release_private_key_symlink"
mkdir -p "$prepare_vm_release_public_key_dir"
printf '%s\n' "not a directory" >"$prepare_vm_release_evidence_root_file"
if bash scripts/prepare-vm-evidence-release-asset.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --release-dir dist/release \
  --env-file "$prepare_vm_release_env_symlink" \
  --evidence-root .vm/evidence \
  --all \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: VM evidence release helper accepted a symlink env file" >&2
  rm -rf "$prepare_vm_release_path_guard_root"
  exit 1
fi
if bash scripts/prepare-vm-evidence-release-asset.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --release-dir dist/release \
  --private-key "$prepare_vm_release_private_key_symlink" \
  --evidence-root .vm/evidence \
  --all \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: VM evidence release helper accepted a symlink private key" >&2
  rm -rf "$prepare_vm_release_path_guard_root"
  exit 1
fi
if bash scripts/prepare-vm-evidence-release-asset.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --release-dir dist/release \
  --private-key "$prepare_vm_release_private_key" \
  --public-key "$prepare_vm_release_public_key_dir" \
  --evidence-root .vm/evidence \
  --all \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: VM evidence release helper accepted a directory public key" >&2
  rm -rf "$prepare_vm_release_path_guard_root"
  exit 1
fi
if bash scripts/prepare-vm-evidence-release-asset.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --release-dir dist/release \
  --private-key "$prepare_vm_release_private_key" \
  --evidence-root "$prepare_vm_release_evidence_root_file" \
  --all \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: VM evidence release helper accepted a file evidence root" >&2
  rm -rf "$prepare_vm_release_path_guard_root"
  exit 1
fi
rm -rf "$prepare_vm_release_path_guard_root"
prepare_vm_release_env_file="$(mktemp)"
cat >"$prepare_vm_release_env_file" <<'EOF'
BUNNY_STORAGE_ZONE=env-loopwire-docs
BUNNY_ACCESS_KEY=env-access-key-that-must-not-print
BUNNY_STORAGE_ENDPOINT=ny.storage.bunnycdn.com
BUNNY_PULL_ZONE_HOSTNAME=docs.env.example.test
BUNNY_REMOTE_PREFIX=env-preview
LOOPWIRE_RELEASE_PRIVATE_KEY_FILE=/secure/env-loopwire-release-private.pem
LOOPWIRE_RELEASE_PUBLIC_KEY_FILE=packaging/release-signing-public.pem
EOF
prepare_vm_release_env_dry_run="$(
  bash scripts/prepare-vm-evidence-release-asset.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --release-dir dist/release \
    --env-file "$prepare_vm_release_env_file" \
    --evidence-root .vm/evidence \
    --all \
    --dry-run
)"
prepare_vm_release_env_override_dry_run="$(
  bash scripts/prepare-vm-evidence-release-asset.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --release-dir dist/release \
    --env-file "$prepare_vm_release_env_file" \
    --private-key /secure/cli-loopwire-release-private.pem \
    --public-key /secure/cli-loopwire-release-public.pem \
    --evidence-root .vm/evidence \
    --all \
    --dry-run
)"
rm -f "$prepare_vm_release_env_file"
printf '%s\n' "$prepare_vm_release_env_dry_run" | grep -F -- "--private-key /secure/env-loopwire-release-private.pem" \
  >/dev/null || {
    echo "verify-scripts: VM evidence release helper env-file dry-run did not use private key path" >&2
    exit 1
  }
printf '%s\n' "$prepare_vm_release_env_dry_run" | grep -F -- "--public-key packaging/release-signing-public.pem" \
  >/dev/null || {
    echo "verify-scripts: VM evidence release helper env-file dry-run did not use public key path" >&2
    exit 1
  }
if printf '%s\n' "$prepare_vm_release_env_dry_run" | grep -F "env-access-key-that-must-not-print" >/dev/null; then
  echo "verify-scripts: VM evidence release helper env-file dry-run leaked Bunny access key" >&2
  exit 1
fi
printf '%s\n' "$prepare_vm_release_env_override_dry_run" |
  grep -F -- "--private-key /secure/cli-loopwire-release-private.pem" >/dev/null || {
    echo "verify-scripts: VM evidence release helper CLI private key did not override env-file value" >&2
    exit 1
  }
printf '%s\n' "$prepare_vm_release_env_override_dry_run" |
  grep -F -- "--public-key /secure/cli-loopwire-release-public.pem" >/dev/null || {
    echo "verify-scripts: VM evidence release helper CLI public key did not override env-file value" >&2
    exit 1
  }
single_ssh_plan="$(
  bash scripts/vm-matrix.sh render-ssh-plan \
    --target fedora-kde-jack \
    --host 127.0.0.1 \
    --start-port 2322 \
    --desktop-port 5199
)"
printf '%s\n' "$single_ssh_plan" | node -e '
const fs = require("node:fs");
const rows = fs.readFileSync(0, "utf8").trim().split(/\r?\n/);
if (rows.length !== 2) process.exit(1);
const cells = rows[1].split("\t");
if (cells[0] !== "fedora-kde-jack") process.exit(1);
if (cells[2] !== "2322") process.exit(1);
if (cells[5] !== "5199") process.exit(1);
if (cells[7] !== ".vm/evidence/fedora-kde-jack") process.exit(1);
' || {
  echo "verify-scripts: single-target SSH VM plan output is malformed" >&2
  exit 1
}
all_ssh_plan="$(bash scripts/vm-matrix.sh render-ssh-plan --all --start-port 2400)"
printf '%s\n' "$all_ssh_plan" | node -e '
const fs = require("node:fs");
const rows = fs.readFileSync(0, "utf8").trim().split(/\r?\n/);
const targets = fs.readFileSync("vm/targets.tsv", "utf8")
  .split(/\r?\n/)
  .filter((line) => line && !line.startsWith("#"))
  .map((line) => line.split("\t")[0]);
const dataRows = rows.slice(1).map((line) => line.split("\t"));
if (dataRows.length !== targets.length) process.exit(1);
if (dataRows[0][2] !== "2400") process.exit(1);
if (dataRows[1][2] !== "2410") process.exit(1);
if (!dataRows.some((cells) => cells[0] === "opensuse-kde-pipewire")) process.exit(1);
if (!dataRows.every((cells) => cells[7] === `.vm/evidence/${cells[0]}`)) process.exit(1);
' || {
  echo "verify-scripts: all-target SSH VM plan output is malformed" >&2
  exit 1
}
if bash scripts/vm-matrix.sh render-ssh-plan --all --start-port 65500 >/dev/null 2>&1; then
  echo "verify-scripts: SSH VM plan accepted a start port that cannot cover all targets" >&2
  exit 1
fi
bash scripts/collect-vm-evidence-ssh.sh -- --target arch-hyprland-pipewire --host 127.0.0.1 >/dev/null
bash scripts/deploy-docs-bunny.sh --help >/dev/null
bash scripts/deploy-docs-bunny.sh --help | grep -F -- "--deployment-manifest FILE" >/dev/null || {
  echo "verify-scripts: Bunny docs deploy help is missing deployment manifest support" >&2
  exit 1
}
node scripts/verify-docs-deployment-manifest.mjs --help | grep -F -- "--expected-dry-run true|false" >/dev/null || {
  echo "verify-scripts: docs deployment manifest verifier help is missing dry-run binding" >&2
  exit 1
}
node scripts/verify-docs-deployment-manifest.mjs --help | grep -F -- "--git-head SHA" >/dev/null || {
  echo "verify-scripts: docs deployment manifest verifier help is missing git-head binding" >&2
  exit 1
}
bash scripts/prepare-release-signing-key.sh --help >/dev/null
setup_secrets_required="$(bash scripts/setup-github-secrets.sh --print-required)"
printf '%s\n' "$setup_secrets_required" | grep -F "Required final-proof GitHub secrets:" >/dev/null || {
  echo "verify-scripts: GitHub secret helper required output is missing final-proof heading" >&2
  exit 1
}
printf '%s\n' "$setup_secrets_required" | grep -F "BUNNY_PULL_ZONE_HOSTNAME" >/dev/null || {
  echo "verify-scripts: GitHub secret helper required output is missing pull-zone hostname" >&2
  exit 1
}
printf '%s\n' "$setup_secrets_required" | grep -F "BUNNY_REMOTE_PREFIX" >/dev/null || {
  echo "verify-scripts: GitHub secret helper required output is missing remote prefix" >&2
  exit 1
}
setup_secrets_deploy_required="$(bash scripts/setup-github-secrets.sh --print-required --scope deploy)"
printf '%s\n' "$setup_secrets_deploy_required" | grep -F "Required deploy GitHub secrets:" >/dev/null || {
  echo "verify-scripts: GitHub secret helper deploy-scope output is missing deploy heading" >&2
  exit 1
}
if printf '%s\n' "$setup_secrets_deploy_required" | grep -F "LOOPWIRE_RELEASE_PRIVATE_KEY" >/dev/null; then
  echo "verify-scripts: GitHub secret helper deploy-scope output included release key" >&2
  exit 1
fi
if bash scripts/setup-github-secrets.sh --print-required --scope invalid >/dev/null 2>&1; then
  echo "verify-scripts: GitHub secret helper accepted an invalid scope" >&2
  exit 1
fi
bash scripts/setup-github-secrets.sh --help | grep -F -- "--release-public-key-file FILE" >/dev/null || {
  echo "verify-scripts: GitHub secret helper help is missing release public key validation option" >&2
  exit 1
}
bash scripts/setup-github-secrets.sh --help | grep -F -- "--secret-list-file FILE" >/dev/null || {
  echo "verify-scripts: GitHub secret helper help is missing secret-list artifact support" >&2
  exit 1
}
bash scripts/setup-github-secrets.sh --help | grep -F -- "--env-file FILE" >/dev/null || {
  echo "verify-scripts: GitHub secret helper help is missing env-file support" >&2
  exit 1
}
release_readiness_help_for_secret_artifacts="$(bash scripts/verify-release-readiness.sh --help)"
printf '%s\n' "$release_readiness_help_for_secret_artifacts" | grep -F -- "--secret-list-file FILE" >/dev/null || {
  echo "verify-scripts: release readiness help is missing secret-list artifact support" >&2
  exit 1
}
pnpm --filter @loopwire/core build >/dev/null
pnpm --filter @loopwire/audio-host build >/dev/null

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

invalid_restore_state_file="$tmp_dir/corrupt-loopwire-state.json"
invalid_restore_state_log="$tmp_dir/restore-invalid-state.log"
printf '{not-json\n' >"$invalid_restore_state_file"
if node scripts/restore-background.mjs --state-file "$invalid_restore_state_file" >"$invalid_restore_state_log" 2>&1; then
  echo "verify-scripts: restore background accepted corrupt persisted state" >&2
  exit 1
fi
grep -F "Could not restore persisted Loopwire state at $invalid_restore_state_file" \
  "$invalid_restore_state_log" >/dev/null || {
    echo "verify-scripts: restore background invalid-state error did not name the state file" >&2
    exit 1
  }
grep -F "Open Loopwire once, choose a configuration, and enable Restore on boot again." \
  "$invalid_restore_state_log" >/dev/null || {
    echo "verify-scripts: restore background invalid-state error is not actionable" >&2
    exit 1
  }

nix_evidence_dir="$tmp_dir/nix-release-evidence"
mkdir -p "$nix_evidence_dir"
printf '%s\n' "Nix release package build passed for Loopwire 0.1.0." >"$nix_evidence_dir/nix-release-package.log"
cat >"$nix_evidence_dir/release-evidence.json" <<'EOF'
{
  "generatedAt": "2026-07-04T00:00:00.000Z",
  "profile": "quick",
  "git": {
    "head": "0123456789abcdef0123456789abcdef01234567",
    "branch": "main",
    "origin": "git@github.com:sandwichfarm/loopwire.git",
    "statusShort": ""
  },
  "release": {
    "repo": "o/r",
    "tag": "v0.1.0",
    "publicKey": "k",
    "findings": [],
    "blockers": []
  },
  "ok": true,
  "commands": [
    {
      "name": "nix-release-package",
      "command": "'bash' 'scripts/verify-nix-release-package.sh' '--repo' 'o/r' '--tag' 'v0.1.0' '--public-key' 'k'",
      "log": "nix-release-package.log",
      "required": true,
      "startedAt": "2026-07-04T00:00:00.000Z",
      "finishedAt": "2026-07-04T00:00:01.000Z",
      "exitCode": 0,
      "signal": null,
      "bytes": 57
    }
  ]
}
EOF
node scripts/verify-release-evidence.mjs \
  --evidence-dir "$nix_evidence_dir" \
  --release-tag v0.1.0 \
  --repo o/r \
  --public-key k \
  --require-nix-release >/dev/null
nix_unsafe_evidence_dir="$tmp_dir/nix-release-evidence-unsafe"
cp -R "$nix_evidence_dir" "$nix_unsafe_evidence_dir"
node -e '
const fs = require("node:fs");
const path = process.argv[1];
const payload = JSON.parse(fs.readFileSync(path, "utf8"));
payload.commands[0].command += " --render-only";
fs.writeFileSync(path, `${JSON.stringify(payload, null, 2)}\n`);
' "$nix_unsafe_evidence_dir/release-evidence.json"
if node scripts/verify-release-evidence.mjs \
  --evidence-dir "$nix_unsafe_evidence_dir" \
  --release-tag v0.1.0 \
  --repo o/r \
  --public-key k \
  --require-nix-release >/dev/null 2>&1; then
  echo "verify-scripts: release evidence accepted render-only Nix proof" >&2
  exit 1
fi

safe_tar_src="$tmp_dir/safe-tar-src"
safe_tar_extract="$tmp_dir/safe-tar-extract"
unsafe_tar_src="$tmp_dir/unsafe-tar-src"
safe_archive="$tmp_dir/safe.tar.gz"
unsafe_archive="$tmp_dir/unsafe.tar.gz"
link_archive="$tmp_dir/link.tar.gz"
mkdir -p "$safe_tar_src/v0.1.0" "$unsafe_tar_src"
printf '%s\n' "{}" >"$safe_tar_src/v0.1.0/release-evidence.json"
tar -C "$safe_tar_src" -czf "$safe_archive" v0.1.0
bash scripts/extract-safe-tar.sh \
  --archive "$safe_archive" \
  --output-dir "$safe_tar_extract" \
  --label "safe test archive"
[ -f "$safe_tar_extract/v0.1.0/release-evidence.json" ] || {
  echo "verify-scripts: safe tar extractor did not extract the expected file" >&2
  exit 1
}
printf '%s\n' "unsafe" >"$unsafe_tar_src/payload"
tar -C "$unsafe_tar_src" \
  --transform='s#payload#../payload#' \
  -czf "$unsafe_archive" \
  payload 2>/dev/null
if bash scripts/extract-safe-tar.sh \
  --archive "$unsafe_archive" \
  --output-dir "$tmp_dir/unsafe-tar-extract" \
  --label "unsafe test archive" >/dev/null 2>&1; then
  echo "verify-scripts: safe tar extractor accepted a parent-traversal member" >&2
  exit 1
fi
ln -s /tmp "$unsafe_tar_src/link"
tar -C "$unsafe_tar_src" -czf "$link_archive" link 2>/dev/null
if bash scripts/extract-safe-tar.sh \
  --archive "$link_archive" \
  --output-dir "$tmp_dir/link-tar-extract" \
  --label "link test archive" >/dev/null 2>&1; then
  echo "verify-scripts: safe tar extractor accepted a link member" >&2
  exit 1
fi

jack_configuration="$tmp_dir/jack-configuration.json"
cat >"$jack_configuration" <<'EOF'
{
  "kind": "loopwire.configuration",
  "version": 1,
  "configuration": {
    "id": "jack-mix",
    "name": "JACK Mix",
    "description": "JACK verification fixture",
    "updatedAt": "2026-07-04T00:00:00.000Z",
    "inputs": [
      { "id": "mic", "role": "input", "label": "Studio Mic", "channels": 2 },
      { "id": "player", "role": "input", "label": "Music Player", "channels": 2, "deviceName": "mpd" }
    ],
    "outputs": [
      { "id": "program", "role": "output", "label": "Program", "channels": 2 }
    ],
    "monitors": [
      { "id": "phones", "role": "monitor", "label": "Headphones", "channels": 2 }
    ],
    "routes": [
      { "id": "mic-program", "from": "mic", "to": "program", "gain": 1, "muted": false },
      { "id": "player-program", "from": "player", "to": "program", "gain": 1, "muted": false }
    ]
  }
}
EOF
jack_ports_json="$(node scripts/describe-jack-ports.mjs --configuration "$jack_configuration" --pretty)"
printf '%s\n' "$jack_ports_json" | node -e '
const fs = require("node:fs");
const payload = JSON.parse(fs.readFileSync(0, "utf8"));
const devices = payload.requirements.map((item) => item.deviceName);
if (payload.configurationId !== "jack-mix") process.exit(1);
if (!devices.includes("loopwire_jack-mix_input_mic")) process.exit(1);
if (!devices.includes("mpd")) process.exit(1);
if (!devices.includes("loopwire_jack-mix_monitor_phones")) process.exit(1);
' || {
  echo "verify-scripts: JACK port description JSON output is malformed" >&2
  exit 1
}
jack_ports_tsv="$(node scripts/describe-jack-ports.mjs --configuration "$jack_configuration" --format tsv --loopwire-owned-only)"
printf '%s\n' "$jack_ports_tsv" | grep -F "loopwire_jack-mix_input_mic:capture_1" >/dev/null || {
  echo "verify-scripts: JACK port description TSV output is missing route source ports" >&2
  exit 1
}
printf '%s\n' "$jack_ports_tsv" | grep -F "mpd" >/dev/null && {
  echo "verify-scripts: JACK port description TSV filter included configured ports" >&2
  exit 1
}
jack_ports_file="$tmp_dir/jack-ports.txt"
cat >"$jack_ports_file" <<'EOF'
loopwire_jack-mix_input_mic:capture_1
loopwire_jack-mix_input_mic:capture_2
mpd:out_l
mpd:out_r
loopwire_jack-mix_program:playback_1
loopwire_jack-mix_program:playback_2
loopwire_jack-mix_program:monitor_1
loopwire_jack-mix_program:monitor_2
loopwire_jack-mix_monitor_phones:playback_1
loopwire_jack-mix_monitor_phones:playback_2
EOF
jack_verify_json="$(
  node scripts/describe-jack-ports.mjs \
    --configuration "$jack_configuration" \
    --verify \
    --ports-file "$jack_ports_file" \
    --pretty
)"
printf '%s\n' "$jack_verify_json" | node -e '
const fs = require("node:fs");
const payload = JSON.parse(fs.readFileSync(0, "utf8"));
if (payload.ok !== true) process.exit(1);
const configured = payload.requirements.find((item) => item.deviceName === "mpd");
if (!configured || configured.matchedPorts.join(",") !== "mpd:out_l,mpd:out_r") process.exit(1);
' || {
  echo "verify-scripts: JACK port readiness JSON output is malformed" >&2
  exit 1
}
jack_verify_tsv="$(
  node scripts/describe-jack-ports.mjs \
    --configuration "$jack_configuration" \
    --verify \
    --ports-file "$jack_ports_file" \
    --format tsv \
    --loopwire-owned-only
)"
printf '%s\n' "$jack_verify_tsv" | grep -F $'\tready\tmatchedPorts\tmissingPorts' >/dev/null || {
  echo "verify-scripts: JACK port readiness TSV output is missing verification columns" >&2
  exit 1
}
printf '%s\n' "$jack_verify_tsv" | grep -F $'\tyes\tloopwire_jack-mix_input_mic:capture_1' >/dev/null || {
  echo "verify-scripts: JACK port readiness TSV output did not mark present ports ready" >&2
  exit 1
}
jack_missing_ports_file="$tmp_dir/jack-ports-missing.txt"
grep -Fv "loopwire_jack-mix_monitor_phones:playback_2" "$jack_ports_file" >"$jack_missing_ports_file"
if node scripts/describe-jack-ports.mjs \
  --configuration "$jack_configuration" \
  --verify \
  --ports-file "$jack_missing_ports_file" >/dev/null 2>&1; then
  echo "verify-scripts: JACK port readiness accepted a missing monitor target port" >&2
  exit 1
fi
dsp_plan_json="$(node scripts/describe-dsp-provider.mjs --configuration "$jack_configuration" --frame-count 2 --pretty)"
printf '%s\n' "$dsp_plan_json" | node -e '
const fs = require("node:fs");
const payload = JSON.parse(fs.readFileSync(0, "utf8"));
const operations = payload.operations.map((item) => `${item.operation}:${item.target}:${item.channels}:${item.frames}`);
if (payload.mode !== "plan") process.exit(1);
if (payload.configurationId !== "jack-mix") process.exit(1);
if (!operations.includes("read-source:mic:2:2")) process.exit(1);
if (!operations.includes("read-source:player:2:2")) process.exit(1);
if (!operations.includes("write-output:program:2:2")) process.exit(1);
if (!operations.includes("verify-output:program:2:2")) process.exit(1);
' || {
  echo "verify-scripts: DSP provider plan JSON output is malformed" >&2
  exit 1
}
dsp_plan_tsv="$(node scripts/describe-dsp-provider.mjs --configuration "$jack_configuration" --frame-count 2 --format tsv)"
printf '%s\n' "$dsp_plan_tsv" | grep -F $'read-source\tmic\tStudio Mic\t2\t2' >/dev/null || {
  echo "verify-scripts: DSP provider plan TSV output is missing source rows" >&2
  exit 1
}
dsp_provider="$tmp_dir/dsp-provider.js"
dsp_provider_log="$tmp_dir/dsp-provider.log"
cat >"$dsp_provider" <<'EOF'
#!/usr/bin/env node
const fs = require("node:fs");

const args = process.argv.slice(2);
const logPath = process.env.LOOPWIRE_DSP_PROVIDER_LOG;
if (logPath) {
  fs.appendFileSync(logPath, `${args.join(" ")}\n`);
}

function value(name) {
  const index = args.indexOf(name);
  return index === -1 ? undefined : args[index + 1];
}

if (args[0] === "capabilities") {
  const supportsLiveGraph = process.env.LOOPWIRE_DSP_PROVIDER_SUPPORTS_LIVE !== "false";
  const providerKind = supportsLiveGraph ? "verify-live" : "file-backed";
  const operations = ["read-source", "write-output", "verify-output"];
  if (process.env.LOOPWIRE_DSP_PROVIDER_OMIT_CLEAR !== "true") {
    operations.push("clear-output");
  }
  process.stdout.write(`${JSON.stringify({ ok: true, providerKind, supportsLiveGraph, operations })}\n`);
} else if (args[0] === "read-source") {
  const channels = Number(value("--channels"));
  const frames = Number(value("--frames"));
  const payload = {
    channels: Array.from({ length: channels }, (_unused, channel) =>
      Array.from({ length: frames }, () => channel + 1)
    )
  };
  process.stdout.write(`${JSON.stringify(payload)}\n`);
} else if (args[0] === "write-output" || args[0] === "verify-output") {
  const input = fs.readFileSync(0, "utf8");
  const payload = JSON.parse(input);
  if (value("--configuration-id") !== payload.configurationId) {
    console.error("DSP provider configuration id mismatch");
    process.exit(2);
  }
  if (logPath) {
    fs.appendFileSync(logPath, `${args[0]} payload ${payload.configurationId} ${payload.outputId} ${payload.channels.length}\n`);
  }
  if (args[0] === "verify-output" && process.env.LOOPWIRE_DSP_PROVIDER_FAIL_VERIFY === "true") {
    process.stdout.write(`${JSON.stringify({ ok: false, message: "provider verify failed" })}\n`);
  } else {
    process.stdout.write(`${JSON.stringify({ ok: true })}\n`);
  }
} else if (args[0] === "clear-output") {
  process.stdout.write("cleared\n");
} else {
  console.error(`unexpected operation: ${args[0]}`);
  process.exit(2);
}
EOF
chmod +x "$dsp_provider"
dsp_verify_json="$(
  LOOPWIRE_DSP_PROVIDER_LOG="$dsp_provider_log" \
    node scripts/describe-dsp-provider.mjs \
      --configuration "$jack_configuration" \
      --provider-command "$dsp_provider" \
      --require-live-capability \
      --execute \
      --frame-count 2 \
      --pretty
)"
printf '%s\n' "$dsp_verify_json" | node -e '
const fs = require("node:fs");
const payload = JSON.parse(fs.readFileSync(0, "utf8"));
if (payload.ok !== true) process.exit(1);
if (payload.mode !== "execute") process.exit(1);
if (payload.execution.apply.ok !== true) process.exit(1);
if (payload.execution.verify.ok !== true) process.exit(1);
if (payload.providerCapability?.supportsLiveGraph !== true) process.exit(1);
' || {
  echo "verify-scripts: DSP provider execute JSON output is malformed" >&2
  exit 1
}
grep -F "capabilities" "$dsp_provider_log" >/dev/null || {
  echo "verify-scripts: DSP provider execute did not check provider capabilities" >&2
  exit 1
}
grep -F "read-source --source-id mic --channels 2 --frames 2" "$dsp_provider_log" >/dev/null || {
  echo "verify-scripts: DSP provider execute did not read mic source" >&2
  exit 1
}
grep -F "write-output --output-id program --channels 2 --frames 2" "$dsp_provider_log" >/dev/null || {
  echo "verify-scripts: DSP provider execute did not write program output" >&2
  exit 1
}
grep -F "verify-output --output-id program --channels 2 --frames 2" "$dsp_provider_log" >/dev/null || {
  echo "verify-scripts: DSP provider execute did not verify program output" >&2
  exit 1
}
if node scripts/describe-dsp-provider.mjs \
  --configuration "$jack_configuration" \
  --execute >/dev/null 2>&1; then
  echo "verify-scripts: DSP provider execute accepted a missing provider command" >&2
  exit 1
fi
if node scripts/describe-dsp-provider.mjs \
  --configuration "$jack_configuration" \
  --require-live-capability >/dev/null 2>&1; then
  echo "verify-scripts: DSP provider live capability check accepted a missing provider command" >&2
  exit 1
fi
if LOOPWIRE_DSP_PROVIDER_SUPPORTS_LIVE=false \
  node scripts/describe-dsp-provider.mjs \
    --configuration "$jack_configuration" \
    --provider-command "$dsp_provider" \
    --require-live-capability \
    --frame-count 2 >/dev/null 2>&1; then
  echo "verify-scripts: DSP provider live capability check accepted a file-backed provider" >&2
  exit 1
fi
if LOOPWIRE_DSP_PROVIDER_OMIT_CLEAR=true \
  node scripts/describe-dsp-provider.mjs \
    --configuration "$jack_configuration" \
    --provider-command "$dsp_provider" \
    --require-live-capability \
    --frame-count 2 >/dev/null 2>&1; then
  echo "verify-scripts: DSP provider live capability check accepted a provider without clear-output" >&2
  exit 1
fi
if LOOPWIRE_DSP_PROVIDER_FAIL_VERIFY=true \
  node scripts/describe-dsp-provider.mjs \
    --configuration "$jack_configuration" \
    --provider-command "$dsp_provider" \
    --execute \
    --frame-count 2 >/dev/null 2>&1; then
  echo "verify-scripts: DSP provider execute accepted a provider verification failure" >&2
  exit 1
fi
readiness_log="$tmp_dir/release-readiness.log"
cat >"$readiness_log" <<'EOF'
ok: versioned release notes: apps/docs/docs/release-notes/0.1.0.md
missing: release public key: packaging/release-signing-public.pem
invalid: release notes still look like a candidate: apps/docs/docs/release-notes/0.1.0.md
skipped: tag existence check
EOF
readiness_summary="$(node scripts/collect-release-evidence.mjs --summarize-release-readiness-log "$readiness_log")"
printf '%s\n' "$readiness_summary" | node -e '
const fs = require("node:fs");
const summary = JSON.parse(fs.readFileSync(0, "utf8"));
const messages = summary.blockers.map((finding) => finding.message);
if (summary.blockers.length !== 2) process.exit(1);
if (!messages.includes("release public key: packaging/release-signing-public.pem")) process.exit(1);
if (!messages.includes("release notes still look like a candidate: apps/docs/docs/release-notes/0.1.0.md")) {
  process.exit(1);
}
if (!summary.findings.some((finding) => finding.severity === "info" && finding.kind === "skipped")) {
  process.exit(1);
}
' || {
  echo "verify-scripts: release readiness summary did not preserve blocker details" >&2
  exit 1
}

release_evidence_dir="$tmp_dir/release-evidence-final"
release_evidence_partial_dir="$tmp_dir/release-evidence-partial"
release_evidence_blocked_dir="$tmp_dir/release-evidence-blocked"
release_evidence_empty_log_dir="$tmp_dir/release-evidence-empty-log"
release_evidence_parent_log_dir="$tmp_dir/release-evidence-parent-log"
release_evidence_symlink_log_dir="$tmp_dir/release-evidence-symlink-log"
release_evidence_bad_vm_dir="$tmp_dir/release-evidence-bad-vm-dir"
release_evidence_duplicate_vm_dir="$tmp_dir/release-evidence-duplicate-vm"
release_evidence_bad_vm_command_dir="$tmp_dir/release-evidence-bad-vm-command"
release_evidence_missing_docs_live_dir="$tmp_dir/release-evidence-missing-docs-live"
release_evidence_bad_docs_command_dir="$tmp_dir/release-evidence-bad-docs-command"
release_evidence_bad_docs_binding_dir="$tmp_dir/release-evidence-bad-docs-binding"
release_evidence_missing_git_dir="$tmp_dir/release-evidence-missing-git"
release_evidence_dirty_git_dir="$tmp_dir/release-evidence-dirty-git"
release_evidence_bad_published_command_dir="$tmp_dir/release-evidence-bad-published-command"
release_evidence_local_published_command_dir="$tmp_dir/release-evidence-local-published-command"
release_evidence_bad_public_key_dir="$tmp_dir/release-evidence-bad-public-key"
release_evidence_bad_tag_dir="$tmp_dir/release-evidence-bad-tag"
release_evidence_bad_repo_dir="$tmp_dir/release-evidence-bad-repo"
release_evidence_missing_launch_plan_dir="$tmp_dir/release-evidence-missing-launch-plan"
release_evidence_bad_launch_plan_command_dir="$tmp_dir/release-evidence-bad-launch-plan-command"
release_evidence_bad_launch_plan_log_dir="$tmp_dir/release-evidence-bad-launch-plan-log"
release_evidence_missing_dsp_plan_dir="$tmp_dir/release-evidence-missing-dsp-plan"
release_evidence_bad_dsp_plan_command_dir="$tmp_dir/release-evidence-bad-dsp-plan-command"
release_evidence_bad_dsp_plan_log_dir="$tmp_dir/release-evidence-bad-dsp-plan-log"
release_evidence_wrong_dsp_plan_target_dir="$tmp_dir/release-evidence-wrong-dsp-plan-target"
node - "$release_evidence_dir" "$release_evidence_partial_dir" "$release_evidence_blocked_dir" \
  "$release_evidence_empty_log_dir" "$release_evidence_parent_log_dir" "$release_evidence_symlink_log_dir" \
  "$release_evidence_bad_vm_dir" "$release_evidence_duplicate_vm_dir" "$release_evidence_bad_vm_command_dir" \
  "$release_evidence_missing_docs_live_dir" "$release_evidence_bad_docs_command_dir" \
  "$release_evidence_bad_docs_binding_dir" "$release_evidence_missing_git_dir" "$release_evidence_dirty_git_dir" \
  "$release_evidence_bad_published_command_dir" "$release_evidence_local_published_command_dir" \
  "$release_evidence_bad_public_key_dir" "$release_evidence_bad_tag_dir" "$release_evidence_bad_repo_dir" \
  "$release_evidence_missing_launch_plan_dir" \
  "$release_evidence_bad_launch_plan_command_dir" "$release_evidence_bad_launch_plan_log_dir" \
  "$release_evidence_missing_dsp_plan_dir" "$release_evidence_bad_dsp_plan_command_dir" \
  "$release_evidence_bad_dsp_plan_log_dir" "$release_evidence_wrong_dsp_plan_target_dir" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");
const [
  completeDir,
  partialDir,
  blockedDir,
  emptyLogDir,
  parentLogDir,
  symlinkLogDir,
  badVmDir,
  duplicateVmDir,
  badVmCommandDir,
  missingDocsLiveDir,
  badDocsCommandDir,
  badDocsBindingDir,
  missingGitDir,
  dirtyGitDir,
  badPublishedCommandDir,
  localPublishedCommandDir,
  badPublicKeyDir,
  badTagDir,
  badRepoDir,
  missingLaunchPlanDir,
  badLaunchPlanCommandDir,
  badLaunchPlanLogDir,
  missingDspPlanDir,
  badDspPlanCommandDir,
  badDspPlanLogDir,
  wrongDspPlanTargetDir
] = process.argv.slice(2);
const targets = fs.readFileSync("vm/targets.tsv", "utf8")
  .split(/\r?\n/)
  .filter((line) => line && !line.startsWith("#"))
  .map((line) => line.split("\t")[0]);

function command(name, log) {
  return {
    name,
    command: `echo ${name}`,
    log,
    required: true,
    startedAt: "2026-07-04T00:00:00.000Z",
    finishedAt: "2026-07-04T00:00:01.000Z",
    exitCode: 0,
    signal: null,
    bytes: 10,
    findings: []
  };
}

function vmCommand(target) {
  return {
    ...command(`vm-evidence:${target}`, `vm-evidence-${target}.log`),
    command: `bash scripts/verify-vm-evidence.sh --target ${target} --evidence-dir .vm/evidence/${target} --require-published-release --release-tag v0.1.0 --require-github-release-source`
  };
}

function publishedReleaseCommand() {
  return {
    ...command("published-release-smoke", "published-release-smoke.log"),
    command: [
      "bash scripts/verify-published-release.sh",
      "--repo sandwichfarm/loopwire",
      "--tag v0.1.0",
      "--public-key packaging/release-signing-public.pem"
    ].join(" ")
  };
}

function docsLiveCommand() {
  return {
    ...command("docs-live-smoke", "docs-live-smoke.log"),
    command: [
      "bash scripts/verify-docs-live.sh",
      "--hostname docs.example.test",
      "--remote-prefix preview",
      "--expected-installer apps/docs/docs/public/install.sh"
    ].join(" ")
  };
}

function vmLaunchPlanCommand() {
  return {
    ...command("vm-launch-plan", "vm-launch-plan.tsv"),
    command: [
      "bash scripts/vm-matrix.sh render-launch-plan",
      "--all",
      "--image-root .vm/images",
      "--start-port 2222"
    ].join(" ")
  };
}

function dspProviderPlanCommand() {
  return {
    ...command("dsp-provider-plan", "dsp-provider-plan.tsv"),
    command: [
      "bash scripts/collect-dsp-provider-plan.sh",
      "--configuration scripts/fixtures/dsp-provider-configuration.json",
      "--frame-count 16"
    ].join(" ")
  };
}

function vmLaunchPlanLog(selectedTargets) {
  const rows = [
    "# target\timage\timage_format\tfirmware\tssh_port\tmemory\tcpus\tlaunch_command\tevidence_pull_command"
  ];

  for (const [index, target] of selectedTargets.entries()) {
    const sshPort = String(2222 + index * 10);
    const image = `.vm/images/${target}.qcow2`;
    const launch = [
      "bash scripts/vm-matrix.sh launch",
      `--target ${target}`,
      `--image ${image}`,
      "--image-format qcow2",
      `--ssh-port ${sshPort}`,
      "--memory 4096",
      "--cpus 4"
    ].join(" ");
    const evidence = [
      "bash scripts/collect-vm-evidence-ssh.sh",
      `--target ${target}`,
      "--host 127.0.0.1",
      `--port ${sshPort}`,
      "--execute"
    ].join(" ");

    rows.push([target, image, "qcow2", "default", sshPort, "4096", "4", launch, evidence].join("\t"));
  }

  return `${rows.join("\n")}\n`;
}

function dspProviderPlanLog() {
  return [
    "operation\ttarget\tlabel\tchannels\tframes",
    "read-source\tmic\tStudio Mic\t2\t16",
    "read-source\tbrowser\tBrowser Audio\t2\t16",
    "write-output\tmix\tMain Mix\t2\t16",
    "verify-output\tmix\tMain Mix\t2\t16",
    "clear-output\tmix\tMain Mix\t2\t16"
  ].join("\n") + "\n";
}

function writeBundle(dir, selectedTargets, blockers = [], emptyLog = null) {
  fs.mkdirSync(dir, { recursive: true });
  const commands = [
    publishedReleaseCommand(),
    docsLiveCommand(),
    vmLaunchPlanCommand(),
    dspProviderPlanCommand(),
    ...selectedTargets.map(vmCommand)
  ];
  const manifest = {
    generatedAt: "2026-07-04T00:00:00.000Z",
    profile: "full",
    git: {
      head: "0123456789abcdef0123456789abcdef01234567",
      branch: "release/v0.1.0",
      origin: "https://github.com/sandwichfarm/loopwire.git",
      statusShort: ""
    },
    release: {
      repo: "sandwichfarm/loopwire",
      tag: "v0.1.0",
      publicKey: "packaging/release-signing-public.pem",
      docsLive: {
        baseUrl: "",
        hostname: "docs.example.test",
        remotePrefix: "preview",
        required: true
      },
      vmEvidence: {
        targets: selectedTargets.map((target) => ({ target, evidenceDir: `.vm/evidence/${target}` })),
        required: true
      },
      vmLaunchPlan: {
        imageRoot: ".vm/images",
        startPort: "2222"
      },
      dspProviderPlan: {
        configuration: "scripts/fixtures/dsp-provider-configuration.json",
        frameCount: "16",
        required: true
      },
      findings: blockers,
      blockers
    },
    ok: true,
    commands
  };
  fs.writeFileSync(path.join(dir, "release-evidence.json"), `${JSON.stringify(manifest, null, 2)}\n`);
  for (const item of commands) {
    const content = emptyLog === item.log
      ? ""
      : item.name === "vm-launch-plan"
        ? vmLaunchPlanLog(targets)
        : item.name === "dsp-provider-plan"
          ? dspProviderPlanLog()
        : `ok: ${item.name}\n`;
    fs.writeFileSync(path.join(dir, item.log), content);
  }
}

writeBundle(completeDir, targets);
writeBundle(partialDir, targets.slice(0, 1));
writeBundle(blockedDir, targets, [{ source: "release-readiness", severity: "blocker", message: "missing tag" }]);
writeBundle(emptyLogDir, targets, [], `vm-evidence-${targets[0]}.log`);

fs.mkdirSync(parentLogDir, { recursive: true });
writeBundle(parentLogDir, targets);
fs.writeFileSync(path.join(parentLogDir, "..", "outside.log"), "outside\n");
{
  const manifestPath = path.join(parentLogDir, "release-evidence.json");
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  manifest.commands[0].log = "../outside.log";
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
}

fs.mkdirSync(symlinkLogDir, { recursive: true });
writeBundle(symlinkLogDir, targets);
fs.writeFileSync(path.join(symlinkLogDir, "..", "symlink-target.log"), "symlink target\n");
fs.unlinkSync(path.join(symlinkLogDir, "published-release-smoke.log"));
fs.symlinkSync(path.join(symlinkLogDir, "..", "symlink-target.log"), path.join(symlinkLogDir, "published-release-smoke.log"));

writeBundle(badVmDir, targets);
{
  const manifestPath = path.join(badVmDir, "release-evidence.json");
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  manifest.release.vmEvidence.targets[0].evidenceDir = `../evidence/${targets[0]}`;
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
}

writeBundle(duplicateVmDir, targets);
{
  const manifestPath = path.join(duplicateVmDir, "release-evidence.json");
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  manifest.release.vmEvidence.targets.push({ ...manifest.release.vmEvidence.targets[0] });
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
}

writeBundle(missingGitDir, targets);
{
  const manifestPath = path.join(missingGitDir, "release-evidence.json");
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  delete manifest.git;
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
}

writeBundle(dirtyGitDir, targets);
{
  const manifestPath = path.join(dirtyGitDir, "release-evidence.json");
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  manifest.git.statusShort = " M scripts/verify-release-evidence.mjs";
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
}

writeBundle(badVmCommandDir, targets);
{
  const manifestPath = path.join(badVmCommandDir, "release-evidence.json");
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  const item = manifest.commands.find((entry) => entry.name === `vm-evidence:${targets[0]}`);
  item.command = [
    "echo bash scripts/verify-vm-evidence.sh",
    `--target ${targets[0]}`,
    `--evidence-dir .vm/evidence/${targets[0]}`,
    "--require-published-release"
  ].join(" ");
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
}

writeBundle(missingDocsLiveDir, targets);
{
  const manifestPath = path.join(missingDocsLiveDir, "release-evidence.json");
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  manifest.commands = manifest.commands.filter((entry) => entry.name !== "docs-live-smoke");
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
}

writeBundle(badDocsCommandDir, targets);
{
  const manifestPath = path.join(badDocsCommandDir, "release-evidence.json");
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  const item = manifest.commands.find((entry) => entry.name === "docs-live-smoke");
  item.command = [
    "echo bash scripts/verify-docs-live.sh",
    "--hostname docs.example.test",
    "--remote-prefix preview",
    "--expected-installer apps/docs/docs/public/install.sh"
  ].join(" ");
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
}

writeBundle(badDocsBindingDir, targets);
{
  const manifestPath = path.join(badDocsBindingDir, "release-evidence.json");
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  const item = manifest.commands.find((entry) => entry.name === "docs-live-smoke");
  item.command = [
    "bash scripts/verify-docs-live.sh",
    "--hostname wrong-docs.example.test",
    "--remote-prefix preview",
    "--expected-installer apps/docs/docs/public/install.sh"
  ].join(" ");
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
}

writeBundle(badPublishedCommandDir, targets);
{
  const manifestPath = path.join(badPublishedCommandDir, "release-evidence.json");
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  const item = manifest.commands.find((entry) => entry.name === "published-release-smoke");
  item.command = [
    "echo bash scripts/verify-published-release.sh",
    "--repo sandwichfarm/loopwire",
    "--tag v0.1.0",
    "--public-key packaging/release-signing-public.pem"
  ].join(" ");
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
}

writeBundle(localPublishedCommandDir, targets);
{
  const manifestPath = path.join(localPublishedCommandDir, "release-evidence.json");
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  const item = manifest.commands.find((entry) => entry.name === "published-release-smoke");
  item.command += " --release-dir dist/release";
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
}

writeBundle(badPublicKeyDir, targets);
{
  const manifestPath = path.join(badPublicKeyDir, "release-evidence.json");
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  manifest.release.publicKey = "packaging/other-release-signing-public.pem";
  const item = manifest.commands.find((entry) => entry.name === "published-release-smoke");
  item.command = [
    "bash scripts/verify-published-release.sh",
    "--repo sandwichfarm/loopwire",
    "--tag v0.1.0",
    "--public-key packaging/other-release-signing-public.pem"
  ].join(" ");
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
}

writeBundle(badTagDir, targets);
{
  const manifestPath = path.join(badTagDir, "release-evidence.json");
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  manifest.release.tag = "v0.1.0/preview";
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
}

writeBundle(badRepoDir, targets);
{
  const manifestPath = path.join(badRepoDir, "release-evidence.json");
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  manifest.release.repo = "https://github.com/sandwichfarm/loopwire";
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
}

writeBundle(missingLaunchPlanDir, targets);
{
  const manifestPath = path.join(missingLaunchPlanDir, "release-evidence.json");
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  manifest.commands = manifest.commands.filter((entry) => entry.name !== "vm-launch-plan");
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
}

writeBundle(badLaunchPlanCommandDir, targets);
{
  const manifestPath = path.join(badLaunchPlanCommandDir, "release-evidence.json");
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  const item = manifest.commands.find((entry) => entry.name === "vm-launch-plan");
  item.command = [
    "echo bash scripts/vm-matrix.sh render-launch-plan",
    "--all",
    "--image-root .vm/images",
    "--start-port 2222"
  ].join(" ");
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
}

writeBundle(badLaunchPlanLogDir, targets);
{
  fs.writeFileSync(path.join(badLaunchPlanLogDir, "vm-launch-plan.tsv"), vmLaunchPlanLog(targets.slice(0, -1)));
}

writeBundle(missingDspPlanDir, targets);
{
  const manifestPath = path.join(missingDspPlanDir, "release-evidence.json");
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  manifest.commands = manifest.commands.filter((entry) => entry.name !== "dsp-provider-plan");
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
}

writeBundle(badDspPlanCommandDir, targets);
{
  const manifestPath = path.join(badDspPlanCommandDir, "release-evidence.json");
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  const item = manifest.commands.find((entry) => entry.name === "dsp-provider-plan");
  item.command = [
    "echo bash scripts/collect-dsp-provider-plan.sh",
    "--configuration scripts/fixtures/dsp-provider-configuration.json",
    "--frame-count 16"
  ].join(" ");
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
}

writeBundle(badDspPlanLogDir, targets);
{
  fs.writeFileSync(path.join(badDspPlanLogDir, "dsp-provider-plan.tsv"), [
    "operation\ttarget\tlabel\tchannels\tframes",
    "read-source\tmic\tStudio Mic\t2\t16",
    "read-source\tbrowser\tBrowser Audio\t2\t16",
    "write-output\tmix\tMain Mix\t2\t16",
    "verify-output\tmix\tMain Mix\t2\t16"
  ].join("\n") + "\n");
}

writeBundle(wrongDspPlanTargetDir, targets);
{
  fs.writeFileSync(path.join(wrongDspPlanTargetDir, "dsp-provider-plan.tsv"), [
    "operation\ttarget\tlabel\tchannels\tframes",
    "read-source\tmic\tStudio Mic\t2\t16",
    "read-source\tbrowser\tBrowser Audio\t2\t16",
    "write-output\tpreview\tMain Mix\t2\t16",
    "verify-output\tpreview\tMain Mix\t2\t16",
    "clear-output\tpreview\tMain Mix\t2\t16"
  ].join("\n") + "\n");
}
NODE
node scripts/verify-release-evidence.mjs \
  --evidence-dir "$release_evidence_dir" \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --release-tag v0.1.0 \
  --repo sandwichfarm/loopwire \
  --public-key packaging/release-signing-public.pem \
  --require-published-release \
  --require-live-docs \
  --require-vm-evidence \
  --require-all-vm-targets \
  --require-vm-launch-plan \
  --require-dsp-provider-plan \
  --require-no-release-blockers \
  --require-clean-git >/dev/null
if node scripts/verify-release-evidence.mjs \
  --evidence-dir "$release_evidence_missing_git_dir" >/dev/null 2>&1; then
  echo "verify-scripts: release evidence verifier accepted missing git metadata" >&2
  exit 1
fi
if node scripts/verify-release-evidence.mjs \
  --evidence-dir "$release_evidence_dirty_git_dir" \
  --require-clean-git >/dev/null 2>&1; then
  echo "verify-scripts: release evidence verifier accepted dirty git status" >&2
  exit 1
fi
node scripts/verify-release-evidence.mjs \
  --evidence-dir "$release_evidence_dirty_git_dir" >/dev/null
if node scripts/verify-release-evidence.mjs \
  --evidence-dir "$release_evidence_dir" \
  --git-head ffffffffffffffffffffffffffffffffffffffff >/dev/null 2>&1; then
  echo "verify-scripts: release evidence verifier accepted the wrong git head" >&2
  exit 1
fi
if node scripts/verify-release-evidence.mjs \
  --evidence-dir "$release_evidence_dir" \
  --release-tag v9.9.9 >/dev/null 2>&1; then
  echo "verify-scripts: release evidence verifier accepted the wrong release tag" >&2
  exit 1
fi
if node scripts/verify-release-evidence.mjs \
  --evidence-dir "$release_evidence_dir" \
  --release-tag v0.1.0/preview >/dev/null 2>&1; then
  echo "verify-scripts: release evidence verifier accepted a path-like expected tag" >&2
  exit 1
fi
if node scripts/verify-release-evidence.mjs \
  --evidence-dir "$release_evidence_bad_tag_dir" >/dev/null 2>&1; then
  echo "verify-scripts: release evidence verifier accepted a path-like manifest tag" >&2
  exit 1
fi
if node scripts/verify-release-evidence.mjs \
  --evidence-dir "$release_evidence_dir" \
  --repo other-owner/loopwire >/dev/null 2>&1; then
  echo "verify-scripts: release evidence verifier accepted the wrong repo" >&2
  exit 1
fi
if node scripts/verify-release-evidence.mjs \
  --evidence-dir "$release_evidence_dir" \
  --repo sandwichfarm/loopwire/releases >/dev/null 2>&1; then
  echo "verify-scripts: release evidence verifier accepted a path-like expected repo" >&2
  exit 1
fi
if node scripts/verify-release-evidence.mjs \
  --evidence-dir "$release_evidence_bad_repo_dir" >/dev/null 2>&1; then
  echo "verify-scripts: release evidence verifier accepted a URL-like manifest repo" >&2
  exit 1
fi
if node scripts/verify-release-evidence.mjs \
  --evidence-dir "$release_evidence_partial_dir" \
  --require-vm-evidence \
  --require-all-vm-targets >/dev/null 2>&1; then
  echo "verify-scripts: release evidence verifier accepted incomplete VM target coverage" >&2
  exit 1
fi
if node scripts/verify-release-evidence.mjs \
  --evidence-dir "$release_evidence_blocked_dir" \
  --require-no-release-blockers >/dev/null 2>&1; then
  echo "verify-scripts: release evidence verifier accepted release blockers" >&2
  exit 1
fi
if node scripts/verify-release-evidence.mjs \
  --evidence-dir "$release_evidence_empty_log_dir" \
  --require-vm-evidence \
  --require-all-vm-targets >/dev/null 2>&1; then
  echo "verify-scripts: release evidence verifier accepted an empty command log" >&2
  exit 1
fi
if node scripts/verify-release-evidence.mjs \
  --evidence-dir "$release_evidence_parent_log_dir" >/dev/null 2>&1; then
  echo "verify-scripts: release evidence verifier accepted a parent-directory command log path" >&2
  exit 1
fi
if node scripts/verify-release-evidence.mjs \
  --evidence-dir "$release_evidence_symlink_log_dir" >/dev/null 2>&1; then
  echo "verify-scripts: release evidence verifier accepted a symlinked command log escape" >&2
  exit 1
fi
if node scripts/verify-release-evidence.mjs \
  --evidence-dir "$release_evidence_bad_vm_dir" \
  --require-vm-evidence >/dev/null 2>&1; then
  echo "verify-scripts: release evidence verifier accepted unsafe VM evidenceDir" >&2
  exit 1
fi
if node scripts/verify-release-evidence.mjs \
  --evidence-dir "$release_evidence_duplicate_vm_dir" \
  --require-vm-evidence >/dev/null 2>&1; then
  echo "verify-scripts: release evidence verifier accepted duplicate VM targets" >&2
  exit 1
fi
if node scripts/verify-release-evidence.mjs \
  --evidence-dir "$release_evidence_bad_vm_command_dir" \
  --require-published-release \
  --require-vm-evidence >/dev/null 2>&1; then
  echo "verify-scripts: release evidence verifier accepted a VM command without verifier args" >&2
  exit 1
fi
if node scripts/verify-release-evidence.mjs \
  --evidence-dir "$release_evidence_missing_docs_live_dir" \
  --require-live-docs >/dev/null 2>&1; then
  echo "verify-scripts: release evidence verifier accepted missing live docs smoke" >&2
  exit 1
fi
if node scripts/verify-release-evidence.mjs \
  --evidence-dir "$release_evidence_bad_docs_command_dir" \
  --require-live-docs >/dev/null 2>&1; then
  echo "verify-scripts: release evidence verifier accepted a fake live docs smoke command" >&2
  exit 1
fi
if node scripts/verify-release-evidence.mjs \
  --evidence-dir "$release_evidence_bad_docs_binding_dir" \
  --require-live-docs >/dev/null 2>&1; then
  echo "verify-scripts: release evidence verifier accepted a live docs smoke command for the wrong host" >&2
  exit 1
fi
if node scripts/verify-release-evidence.mjs \
  --evidence-dir "$release_evidence_bad_published_command_dir" \
  --require-published-release >/dev/null 2>&1; then
  echo "verify-scripts: release evidence verifier accepted a fake published-release smoke command" >&2
  exit 1
fi
if node scripts/verify-release-evidence.mjs \
  --evidence-dir "$release_evidence_local_published_command_dir" \
  --require-published-release >/dev/null 2>&1; then
  echo "verify-scripts: release evidence verifier accepted local release-dir as published-release proof" >&2
  exit 1
fi
if node scripts/verify-release-evidence.mjs \
  --evidence-dir "$release_evidence_bad_public_key_dir" \
  --public-key packaging/release-signing-public.pem \
  --require-published-release >/dev/null 2>&1; then
  echo "verify-scripts: release evidence verifier accepted the wrong release public key" >&2
  exit 1
fi
if node scripts/verify-release-evidence.mjs \
  --evidence-dir "$release_evidence_missing_launch_plan_dir" \
  --require-vm-launch-plan >/dev/null 2>&1; then
  echo "verify-scripts: release evidence verifier accepted missing VM launch-plan evidence" >&2
  exit 1
fi
if node scripts/verify-release-evidence.mjs \
  --evidence-dir "$release_evidence_bad_launch_plan_command_dir" \
  --require-vm-launch-plan >/dev/null 2>&1; then
  echo "verify-scripts: release evidence verifier accepted a fake VM launch-plan command" >&2
  exit 1
fi
if node scripts/verify-release-evidence.mjs \
  --evidence-dir "$release_evidence_bad_launch_plan_log_dir" \
  --require-vm-launch-plan >/dev/null 2>&1; then
  echo "verify-scripts: release evidence verifier accepted incomplete VM launch-plan rows" >&2
  exit 1
fi
if node scripts/verify-release-evidence.mjs \
  --evidence-dir "$release_evidence_missing_dsp_plan_dir" \
  --require-dsp-provider-plan >/dev/null 2>&1; then
  echo "verify-scripts: release evidence verifier accepted missing DSP provider evidence" >&2
  exit 1
fi
if node scripts/verify-release-evidence.mjs \
  --evidence-dir "$release_evidence_bad_dsp_plan_command_dir" \
  --require-dsp-provider-plan >/dev/null 2>&1; then
  echo "verify-scripts: release evidence verifier accepted a fake DSP provider command" >&2
  exit 1
fi
if node scripts/verify-release-evidence.mjs \
  --evidence-dir "$release_evidence_bad_dsp_plan_log_dir" \
  --require-dsp-provider-plan >/dev/null 2>&1; then
  echo "verify-scripts: release evidence verifier accepted incomplete DSP provider rows" >&2
  exit 1
fi
if node scripts/verify-release-evidence.mjs \
  --evidence-dir "$release_evidence_wrong_dsp_plan_target_dir" \
  --require-dsp-provider-plan >/dev/null 2>&1; then
  echo "verify-scripts: release evidence verifier accepted DSP provider rows for the wrong target" >&2
  exit 1
fi

vm_doctor_output="$(bash scripts/vm-matrix.sh doctor --target arch-hyprland-pipewire 2>&1 || true)"
vm_doctor_separator_output="$(bash scripts/vm-matrix.sh doctor -- --target arch-hyprland-pipewire 2>&1 || true)"
vm_doctor_all_output="$(bash scripts/vm-matrix.sh doctor --all 2>&1 || true)"
vm_nix_doctor_output="$(bash scripts/vm-matrix.sh doctor --target nixos-gnome-pipewire 2>&1 || true)"
vm_arm_doctor_output="$(bash scripts/vm-matrix.sh doctor --target ubuntu-gnome-pipewire-aarch64 2>&1 || true)"
vm_host_plan_output="$(bash scripts/vm-matrix.sh host-plan --target fedora-sway-pipewire)"
vm_arm_host_plan_output="$(bash scripts/vm-matrix.sh host-plan --target ubuntu-gnome-pipewire-aarch64)"
vm_host_setup_all_output="$(bash scripts/vm-matrix.sh host-setup --family pacman --all)"
vm_host_setup_dnf_all_output="$(bash scripts/vm-matrix.sh host-setup --family dnf --all)"
vm_host_setup_zypper_all_output="$(bash scripts/vm-matrix.sh host-setup --family zypper --all)"
vm_host_setup_apt_output="$(bash scripts/vm-matrix.sh host-setup --family apt --target ubuntu-gnome-pipewire-aarch64)"
vm_host_setup_zypper_output="$(pnpm vm:host-setup -- --family zypper --target opensuse-kde-pipewire)"
vm_empty_status_root="$tmp_dir/vm-evidence-empty"
mkdir -p "$vm_empty_status_root"
vm_empty_status_output="$(
  bash scripts/vm-matrix.sh evidence-status \
    --target arch-hyprland-pipewire \
    --evidence-root "$vm_empty_status_root"
)"
pnpm_vm_empty_status_output="$(
  pnpm vm:evidence-status -- \
    --target arch-hyprland-pipewire \
    --evidence-root "$vm_empty_status_root"
)"
vm_all_empty_status_output="$(
  bash scripts/vm-matrix.sh evidence-status \
    --all \
    --evidence-root "$vm_empty_status_root" \
    --host 192.0.2.10 \
    --user operator \
    --identity /operator/keys/loopwire-vm \
    --start-port 2600
)"
vm_launch_root="$tmp_dir/vm-launch-root"
vm_launch_output="$(
  LOOPWIRE_VM_ROOT="$vm_launch_root" \
    bash scripts/vm-matrix.sh launch --target arch-hyprland-pipewire --image /operator/images/arch.qcow2 --ssh-port 2322
)"
pnpm_vm_launch_output="$(
  LOOPWIRE_VM_ROOT="$vm_launch_root" \
    pnpm vm:launch -- --target arch-hyprland-pipewire --image /operator/images/arch.qcow2 --ssh-port 2322
)"
vm_launch_plan_output="$(
  bash scripts/vm-matrix.sh render-launch-plan \
    --target arch-hyprland-pipewire \
    --image-root /operator/images \
    --start-port 2600 \
    --memory 8192 \
    --cpus 6
)"
pnpm_vm_launch_plan_output="$(
  pnpm vm:render-launch-plan -- \
    --all \
    --image-root /operator/images \
    --start-port 2600
)"
vm_launch_plan_file="$tmp_dir/vm-launch-plan.tsv"
bash scripts/vm-matrix.sh render-launch-plan \
  --target arch-hyprland-pipewire \
  --image-root /operator/images \
  --output "$vm_launch_plan_file" >/dev/null
vm_runbook_output="$(
  bash scripts/vm-matrix.sh render-runbook \
    --target arch-hyprland-pipewire \
    --image-root /operator/images \
    --start-port 2600
)"
pnpm_vm_runbook_output="$(
  pnpm vm:render-runbook -- \
    --all \
    --image-root /operator/images \
    --start-port 2600
)"
vm_runbook_file="$tmp_dir/vm-runbook.md"
bash scripts/vm-matrix.sh render-runbook \
  --target arch-hyprland-pipewire \
  --image-root /operator/images \
  --output "$vm_runbook_file" >/dev/null
vm_arm_launch_root="$tmp_dir/vm-arm-launch-root"
vm_arm_launch_output="$(
  LOOPWIRE_VM_ROOT="$vm_arm_launch_root" \
    bash scripts/vm-matrix.sh launch \
      --target ubuntu-gnome-pipewire-aarch64 \
      --image /operator/images/ubuntu-aarch64.qcow2 \
      --ssh-port 2422
)"
printf '%s\n' "$vm_doctor_output" | grep -F "target=arch-hyprland-pipewire" >/dev/null || {
  echo "verify-scripts: vm doctor target context missing" >&2
  exit 1
}
printf '%s\n' "$vm_doctor_all_output" | grep -F "VM doctor all targets" >/dev/null || {
  echo "verify-scripts: vm doctor all-target banner missing" >&2
  exit 1
}
printf '%s\n' "$vm_doctor_all_output" | grep -F "target-check=arch-hyprland-pipewire" >/dev/null || {
  echo "verify-scripts: vm doctor --all missing x86 target check" >&2
  exit 1
}
printf '%s\n' "$vm_doctor_all_output" | grep -F "target=ubuntu-gnome-pipewire-aarch64" >/dev/null || {
  echo "verify-scripts: vm doctor --all missing AArch64 target context" >&2
  exit 1
}
printf '%s\n' "$vm_doctor_all_output" | grep -F "qemu-system-aarch64=" >/dev/null || {
  echo "verify-scripts: vm doctor --all missing AArch64 QEMU check" >&2
  exit 1
}
printf '%s\n' "$vm_doctor_all_output" \
  | grep -F "guest-evidence-command=nix develop --command bash scripts/collect-vm-evidence.sh" >/dev/null || {
    echo "verify-scripts: vm doctor --all missing Nix evidence handoff" >&2
    exit 1
  }
printf '%s\n' "$vm_doctor_separator_output" | grep -F "target=arch-hyprland-pipewire" >/dev/null || {
  echo "verify-scripts: vm doctor rejected a pnpm-style argument separator" >&2
  exit 1
}
printf '%s\n' "$vm_doctor_output" | grep -F "qemu-system-x86_64=" >/dev/null || {
  echo "verify-scripts: vm doctor architecture-specific QEMU check missing" >&2
  exit 1
}
printf '%s\n' "$vm_doctor_output" | grep -F "cloud-localds=" >/dev/null || {
  echo "verify-scripts: vm doctor cloud-init seed media check missing" >&2
  exit 1
}
printf '%s\n' "$vm_doctor_output" | grep -F "host-install-hint=" >/dev/null || {
  echo "verify-scripts: vm doctor host install hint missing" >&2
  exit 1
}
printf '%s\n' "$vm_doctor_output" | grep -F "guest-evidence-command=" >/dev/null || {
  echo "verify-scripts: vm doctor guest evidence handoff missing" >&2
  exit 1
}
printf '%s\n' "$vm_nix_doctor_output" \
  | grep -F "guest-evidence-command=nix develop --command bash scripts/collect-vm-evidence.sh" >/dev/null || {
    echo "verify-scripts: vm doctor Nix evidence handoff does not use nix develop" >&2
    exit 1
  }
printf '%s\n' "$vm_arm_doctor_output" | grep -F "target-arch=aarch64" >/dev/null || {
  echo "verify-scripts: vm doctor AArch64 target context missing" >&2
  exit 1
}
printf '%s\n' "$vm_arm_doctor_output" | grep -F "qemu-system-aarch64=" >/dev/null || {
  echo "verify-scripts: vm doctor AArch64 QEMU check missing" >&2
  exit 1
}
if bash scripts/vm-matrix.sh doctor --target not-a-target >/dev/null 2>&1; then
  echo "verify-scripts: vm doctor accepted an unknown target" >&2
  exit 1
fi
if bash scripts/vm-matrix.sh doctor --all --target arch-hyprland-pipewire >/dev/null 2>&1; then
  echo "verify-scripts: vm doctor accepted --all with --target" >&2
  exit 1
fi
printf '%s\n' "$vm_empty_status_output" | grep -F "VM evidence status" >/dev/null || {
  echo "verify-scripts: vm evidence-status banner missing" >&2
  exit 1
}
printf '%s\n' "$vm_empty_status_output" | grep -F "status=missing" >/dev/null || {
  echo "verify-scripts: vm evidence-status did not report missing evidence" >&2
  exit 1
}
printf '%s\n' "$vm_empty_status_output" \
  | grep -F "summary=checked:1 verified:0 missing:1 invalid:0" >/dev/null || {
    echo "verify-scripts: vm evidence-status missing summary is wrong" >&2
    exit 1
  }
printf '%s\n' "$vm_empty_status_output" \
  | grep -F "collect-command=bash scripts/collect-vm-evidence-ssh.sh" >/dev/null || {
    echo "verify-scripts: vm evidence-status missing collect handoff" >&2
    exit 1
  }
printf '%s\n' "$vm_empty_status_output" | grep -F "collect-port=2222" >/dev/null || {
  echo "verify-scripts: vm evidence-status default collect port missing" >&2
  exit 1
}
printf '%s\n' "$vm_empty_status_output" \
  | grep -F -- "--local-output-dir $vm_empty_status_root/arch-hyprland-pipewire" >/dev/null || {
    echo "verify-scripts: vm evidence-status collect handoff did not preserve evidence root" >&2
    exit 1
  }
printf '%s\n' "$pnpm_vm_empty_status_output" | grep -F "status=missing" >/dev/null || {
  echo "verify-scripts: pnpm vm:evidence-status did not forward arguments" >&2
  exit 1
}
printf '%s\n' "$vm_all_empty_status_output" | grep -F "collect-host=192.0.2.10" >/dev/null || {
  echo "verify-scripts: vm evidence-status did not report collect host" >&2
  exit 1
}
printf '%s\n' "$vm_all_empty_status_output" | grep -F "collect-user=operator" >/dev/null || {
  echo "verify-scripts: vm evidence-status did not report collect user" >&2
  exit 1
}
printf '%s\n' "$vm_all_empty_status_output" | grep -F "collect-start-port=2600" >/dev/null || {
  echo "verify-scripts: vm evidence-status did not report collect start port" >&2
  exit 1
}
printf '%s\n' "$vm_all_empty_status_output" | grep -F "target=arch-hyprland-pipewire" >/dev/null || {
  echo "verify-scripts: vm evidence-status all-target output missing first target" >&2
  exit 1
}
printf '%s\n' "$vm_all_empty_status_output" | grep -F "collect-port=2600" >/dev/null || {
  echo "verify-scripts: vm evidence-status all-target first collect port wrong" >&2
  exit 1
}
printf '%s\n' "$vm_all_empty_status_output" | grep -F "target=fedora-kde-pipewire" >/dev/null || {
  echo "verify-scripts: vm evidence-status all-target output missing second target" >&2
  exit 1
}
printf '%s\n' "$vm_all_empty_status_output" | grep -F "collect-port=2610" >/dev/null || {
  echo "verify-scripts: vm evidence-status all-target second collect port wrong" >&2
  exit 1
}
printf '%s\n' "$vm_all_empty_status_output" \
  | grep -F -- "--identity /operator/keys/loopwire-vm" >/dev/null || {
    echo "verify-scripts: vm evidence-status collect command did not include identity" >&2
    exit 1
  }
printf '%s\n' "$vm_all_empty_status_output" \
  | grep -F "summary=checked:9 verified:0 missing:9 invalid:0" >/dev/null || {
    echo "verify-scripts: vm evidence-status all-target summary is wrong" >&2
    exit 1
  }
if bash scripts/vm-matrix.sh evidence-status \
  --target arch-hyprland-pipewire \
  --evidence-root "$vm_empty_status_root" \
  --release-tag v0.1.0 >/dev/null 2>&1; then
  echo "verify-scripts: vm evidence-status accepted --release-tag without published-release strictness" >&2
  exit 1
fi
if bash scripts/vm-matrix.sh evidence-status \
  --target arch-hyprland-pipewire \
  --evidence-root "$vm_empty_status_root" \
  --require-published-release \
  --release-tag v0.1.0/preview >/dev/null 2>&1; then
  echo "verify-scripts: vm evidence-status accepted an invalid release tag" >&2
  exit 1
fi
if bash scripts/vm-matrix.sh evidence-status --target not-a-target --evidence-root "$vm_empty_status_root" \
  >/dev/null 2>&1; then
  echo "verify-scripts: vm evidence-status accepted an unknown target" >&2
  exit 1
fi
if bash scripts/vm-matrix.sh evidence-status --all --target arch-hyprland-pipewire --evidence-root "$vm_empty_status_root" \
  >/dev/null 2>&1; then
  echo "verify-scripts: vm evidence-status accepted --all with --target" >&2
  exit 1
fi
printf '%s\n' "$vm_host_plan_output" | grep -F "Target: fedora-sway-pipewire" >/dev/null || {
  echo "verify-scripts: vm host-plan target output missing" >&2
  exit 1
}
printf '%s\n' "$vm_host_plan_output" | grep -F "Host install hints:" >/dev/null || {
  echo "verify-scripts: vm host-plan install hints missing" >&2
  exit 1
}
printf '%s\n' "$vm_host_plan_output" | grep -F "qemu-system-x86_64" >/dev/null || {
  echo "verify-scripts: vm host-plan QEMU command missing" >&2
  exit 1
}
printf '%s\n' "$vm_host_plan_output" | grep -F "Use an operator-owned x86_64 cloud image" >/dev/null || {
  echo "verify-scripts: vm host-plan image policy missing" >&2
  exit 1
}
printf '%s\n' "$vm_arm_host_plan_output" | grep -F "Use an operator-owned aarch64 cloud image" >/dev/null || {
  echo "verify-scripts: vm host-plan AArch64 image policy missing" >&2
  exit 1
}
printf '%s\n' "$vm_arm_host_plan_output" | grep -F "qemu-system-aarch64" >/dev/null || {
  echo "verify-scripts: vm host-plan AArch64 QEMU command missing" >&2
  exit 1
}
printf '%s\n' "$vm_arm_host_plan_output" | grep -F "qemu-system-aarch64 qemu-img" >/dev/null || {
  echo "verify-scripts: vm host-plan Fedora AArch64 package hint missing" >&2
  exit 1
}
printf '%s\n' "$vm_arm_host_plan_output" | grep -F "qemu-arm qemu-tools" >/dev/null || {
  echo "verify-scripts: vm host-plan openSUSE AArch64 package hint missing" >&2
  exit 1
}
printf '%s\n' "$vm_host_setup_all_output" | grep -F "target-scope=all" >/dev/null || {
  echo "verify-scripts: vm host-setup --all scope missing" >&2
  exit 1
}
printf '%s\n' "$vm_host_setup_all_output" | grep -F "required-tool=qemu-system-x86_64" >/dev/null || {
  echo "verify-scripts: vm host-setup --all x86 QEMU tool missing" >&2
  exit 1
}
printf '%s\n' "$vm_host_setup_all_output" | grep -F "required-tool=qemu-system-aarch64" >/dev/null || {
  echo "verify-scripts: vm host-setup --all AArch64 QEMU tool missing" >&2
  exit 1
}
printf '%s\n' "$vm_host_setup_all_output" \
  | grep -F "verify-command=bash scripts/vm-matrix.sh doctor --all" >/dev/null || {
    echo "verify-scripts: vm host-setup --all verify command missing" >&2
    exit 1
  }
printf '%s\n' "$vm_host_setup_dnf_all_output" | grep -F "qemu-system-aarch64" >/dev/null || {
  echo "verify-scripts: vm host-setup dnf --all missing AArch64 package" >&2
  exit 1
}
printf '%s\n' "$vm_host_setup_zypper_all_output" | grep -F "qemu-x86 qemu-arm qemu-tools" >/dev/null || {
  echo "verify-scripts: vm host-setup zypper --all missing x86 and ARM packages" >&2
  exit 1
}
printf '%s\n' "$vm_host_setup_apt_output" | grep -F "package-family=apt" >/dev/null || {
  echo "verify-scripts: vm host-setup apt family missing" >&2
  exit 1
}
printf '%s\n' "$vm_host_setup_apt_output" | grep -F "target=ubuntu-gnome-pipewire-aarch64" >/dev/null || {
  echo "verify-scripts: vm host-setup target context missing" >&2
  exit 1
}
printf '%s\n' "$vm_host_setup_apt_output" | grep -F "required-tool=qemu-system-aarch64" >/dev/null || {
  echo "verify-scripts: vm host-setup did not print architecture-specific QEMU tool" >&2
  exit 1
}
printf '%s\n' "$vm_host_setup_apt_output" \
  | grep -F "install-command=sudo apt-get install -y qemu-system qemu-utils cloud-image-utils openssh-client" \
    >/dev/null || {
      echo "verify-scripts: vm host-setup apt install command missing" >&2
      exit 1
    }
printf '%s\n' "$vm_host_setup_apt_output" \
  | grep -F "verify-command=bash scripts/vm-matrix.sh doctor --target ubuntu-gnome-pipewire-aarch64" >/dev/null || {
    echo "verify-scripts: vm host-setup verify command missing" >&2
    exit 1
  }
printf '%s\n' "$vm_host_setup_apt_output" | grep -F "Dry run complete. No packages were installed." >/dev/null || {
  echo "verify-scripts: vm host-setup did not stay dry-run-only" >&2
  exit 1
}
printf '%s\n' "$vm_host_setup_zypper_output" | grep -F "package-family=zypper" >/dev/null || {
  echo "verify-scripts: pnpm vm:host-setup did not forward zypper family" >&2
  exit 1
}
printf '%s\n' "$vm_host_setup_zypper_output" | grep -F "qemu-x86 qemu-tools cloud-utils openssh" >/dev/null || {
  echo "verify-scripts: vm host-setup zypper install command missing" >&2
  exit 1
}
if bash scripts/vm-matrix.sh host-setup --family apt --target arch-hyprland-pipewire --execute >/dev/null 2>&1; then
  echo "verify-scripts: vm host-setup accepted --execute" >&2
  exit 1
fi
if bash scripts/vm-matrix.sh host-setup --all --target arch-hyprland-pipewire >/dev/null 2>&1; then
  echo "verify-scripts: vm host-setup accepted --all with --target" >&2
  exit 1
fi
if bash scripts/vm-matrix.sh host-setup --family not-a-family >/dev/null 2>&1; then
  echo "verify-scripts: vm host-setup accepted an unknown package family" >&2
  exit 1
fi
printf '%s\n' "$vm_arm_launch_output" | grep -F "Base image: /operator/images/ubuntu-aarch64.qcow2" >/dev/null || {
  echo "verify-scripts: AArch64 launch dry-run did not print the operator image path" >&2
  exit 1
}
printf '%s\n' "$vm_arm_launch_output" | grep -F "qemu-system-aarch64" >/dev/null || {
  echo "verify-scripts: AArch64 launch dry-run did not use qemu-system-aarch64" >&2
  exit 1
}
printf '%s\n' "$vm_arm_launch_output" | grep -F -- "-machine" >/dev/null || {
  echo "verify-scripts: AArch64 launch dry-run did not print the virt machine" >&2
  exit 1
}
printf '%s\n' "$vm_arm_launch_output" | grep -F -- "virt" >/dev/null || {
  echo "verify-scripts: AArch64 launch dry-run did not print the virt machine value" >&2
  exit 1
}
printf '%s\n' "$vm_arm_launch_output" | grep -F -- "-cpu" >/dev/null || {
  echo "verify-scripts: AArch64 launch dry-run did not print the CPU model" >&2
  exit 1
}
printf '%s\n' "$vm_arm_launch_output" | grep -F -- "max" >/dev/null || {
  echo "verify-scripts: AArch64 launch dry-run did not print the CPU model value" >&2
  exit 1
}
printf '%s\n' "$vm_arm_launch_output" | grep -F "Firmware: required for --execute" >/dev/null || {
  echo "verify-scripts: AArch64 launch dry-run did not print the firmware requirement" >&2
  exit 1
}
printf '%s\n' "$vm_arm_launch_output" | grep -F -- "--port 2422 --execute" >/dev/null || {
  echo "verify-scripts: AArch64 launch dry-run did not print the matching evidence pull command" >&2
  exit 1
}
[ ! -e "$vm_arm_launch_root" ] || {
  echo "verify-scripts: AArch64 launch dry-run wrote VM state" >&2
  exit 1
}
printf '%s\n' "$vm_launch_output" | grep -F "Base image: /operator/images/arch.qcow2" >/dev/null || {
  echo "verify-scripts: vm launch dry-run did not print the operator image path" >&2
  exit 1
}
printf '%s\n' "$pnpm_vm_launch_output" | grep -F "Base image: /operator/images/arch.qcow2" >/dev/null || {
  echo "verify-scripts: pnpm vm:launch did not forward launch arguments" >&2
  exit 1
}
printf '%s\n' "$vm_launch_plan_output" | grep -F "arch-hyprland-pipewire" >/dev/null || {
  echo "verify-scripts: vm launch plan missing selected target" >&2
  exit 1
}
printf '%s\n' "$vm_launch_plan_output" | grep -F "/operator/images/arch-hyprland-pipewire.qcow2" >/dev/null || {
  echo "verify-scripts: vm launch plan missing target image path" >&2
  exit 1
}
printf '%s\n' "$vm_launch_plan_output" | grep -F -- "--ssh-port 2600 --memory 8192 --cpus 6" >/dev/null || {
  echo "verify-scripts: vm launch plan missing resource arguments" >&2
  exit 1
}
printf '%s\n' "$vm_launch_plan_output" | grep -F -- "--port 2600 --execute" >/dev/null || {
  echo "verify-scripts: vm launch plan missing evidence pull handoff" >&2
  exit 1
}
printf '%s\n' "$pnpm_vm_launch_plan_output" | grep -F "ubuntu-gnome-pipewire-aarch64" >/dev/null || {
  echo "verify-scripts: pnpm vm:render-launch-plan did not include AArch64 target" >&2
  exit 1
}
printf '%s\n' "$pnpm_vm_launch_plan_output" | grep -F -- "--ssh-port 2640" >/dev/null || {
  echo "verify-scripts: all-target VM launch plan did not assign deterministic ports" >&2
  exit 1
}
grep -F "/operator/images/arch-hyprland-pipewire.qcow2" "$vm_launch_plan_file" >/dev/null || {
  echo "verify-scripts: vm launch plan output file was not written" >&2
  exit 1
}
printf '%s\n' "$vm_runbook_output" | grep -F "# Loopwire VM Evidence Runbook" >/dev/null || {
  echo "verify-scripts: vm runbook is missing its title" >&2
  exit 1
}
printf '%s\n' "$vm_runbook_output" \
  | grep -F "bash scripts/vm-matrix.sh doctor --target arch-hyprland-pipewire" >/dev/null || {
    echo "verify-scripts: vm runbook is missing target doctor command" >&2
    exit 1
  }
printf '%s\n' "$vm_runbook_output" \
  | grep -F "pnpm vm:render-launch-plan -- --target arch-hyprland-pipewire" >/dev/null || {
    echo "verify-scripts: vm runbook is missing target launch-plan command" >&2
    exit 1
  }
printf '%s\n' "$vm_runbook_output" \
  | grep -F -- "--local-output-dir .vm/evidence/arch-hyprland-pipewire --execute" >/dev/null || {
    echo "verify-scripts: vm runbook is missing target-scoped evidence pull command" >&2
    exit 1
  }
printf '%s\n' "$vm_runbook_output" \
  | grep -F "Final-release collection after the signed public GitHub Release exists" >/dev/null || {
    echo "verify-scripts: vm runbook is missing final-release collection guidance" >&2
    exit 1
  }
printf '%s\n' "$vm_runbook_output" \
  | grep -F -- "--published-release-repo sandwichfarm/loopwire --published-release-tag v0.1.0" >/dev/null || {
    echo "verify-scripts: vm runbook is missing published release coordinates" >&2
    exit 1
  }
printf '%s\n' "$vm_runbook_output" \
  | grep -F -- "--release-public-key packaging/release-signing-public.pem --require-published-release --require-github-release-source --execute" >/dev/null || {
    echo "verify-scripts: vm runbook is missing strict published-release VM evidence flags" >&2
    exit 1
  }
printf '%s\n' "$vm_runbook_output" \
  | grep -F -- "pnpm vm:evidence-status -- --target arch-hyprland-pipewire" \
  | grep -F -- "--require-published-release --release-tag v0.1.0" >/dev/null || {
    echo "verify-scripts: vm runbook is missing tag-bound evidence status command" >&2
    exit 1
  }
printf '%s\n' "$vm_runbook_output" \
  | grep -F -- "pnpm vm:promote-evidence -- --target arch-hyprland-pipewire" \
  | grep -F -- "--require-published-release --release-tag v0.1.0 --dry-run" >/dev/null || {
    echo "verify-scripts: vm runbook is missing tag-bound promotion dry-run command" >&2
    exit 1
  }
printf '%s\n' "$pnpm_vm_runbook_output" | grep -F "### ubuntu-gnome-pipewire-aarch64" >/dev/null || {
  echo "verify-scripts: pnpm vm:render-runbook did not include the AArch64 target" >&2
  exit 1
}
printf '%s\n' "$pnpm_vm_runbook_output" \
  | grep -F -- "--require-published-release --require-github-release-source --require-all-targets --execute" >/dev/null || {
    echo "verify-scripts: all-target VM runbook is missing strict all-target collection command" >&2
    exit 1
  }
printf '%s\n' "$pnpm_vm_runbook_output" \
  | grep -F -- "pnpm vm:evidence-status -- --all" \
  | grep -F -- "--require-published-release --release-tag v0.1.0" >/dev/null || {
    echo "verify-scripts: all-target VM runbook is missing tag-bound evidence status command" >&2
    exit 1
  }
printf '%s\n' "$pnpm_vm_runbook_output" | grep -F -- "--ssh-port 2640" >/dev/null || {
  echo "verify-scripts: all-target VM runbook did not assign deterministic ports" >&2
  exit 1
}
printf '%s\n' "$pnpm_vm_runbook_output" | grep -F -- "--firmware /path/to/QEMU_EFI.fd" >/dev/null || {
  echo "verify-scripts: all-target VM runbook is missing AArch64 firmware guidance" >&2
  exit 1
}
grep -F "# Loopwire VM Evidence Runbook" "$vm_runbook_file" >/dev/null || {
  echo "verify-scripts: vm runbook output file was not written" >&2
  exit 1
}
printf '%s\n' "$vm_launch_output" | grep -F "Planned overlay disk: $vm_launch_root/run/arch-hyprland-pipewire" \
  >/dev/null || {
    echo "verify-scripts: vm launch dry-run did not print the planned overlay path" >&2
    exit 1
  }
printf '%s\n' "$vm_launch_output" | grep -F "Forwarded SSH port: 2322" >/dev/null || {
  echo "verify-scripts: vm launch dry-run did not print the configured SSH port" >&2
  exit 1
}
printf '%s\n' "$vm_launch_output" | grep -F "hostfwd=tcp::2322-:22" >/dev/null || {
  echo "verify-scripts: vm launch dry-run did not forward the configured SSH port" >&2
  exit 1
}
printf '%s\n' "$vm_launch_output" | grep -F -- "--port 2322 --execute" >/dev/null || {
  echo "verify-scripts: vm launch dry-run did not print the matching evidence pull command" >&2
  exit 1
}
printf '%s\n' "$vm_launch_output" | grep -F "Dry run complete. Add --execute" >/dev/null || {
  echo "verify-scripts: vm launch dry-run did not finish as a dry run" >&2
  exit 1
}
[ ! -e "$vm_launch_root" ] || {
  echo "verify-scripts: vm launch dry-run wrote VM state" >&2
  exit 1
}
if LOOPWIRE_VM_ROOT="$vm_launch_root" \
  bash scripts/vm-matrix.sh launch --target arch-hyprland-pipewire --image "$tmp_dir/missing.qcow2" --execute \
    >/dev/null 2>&1; then
  echo "verify-scripts: vm launch --execute accepted a missing image" >&2
  exit 1
fi
touch "$tmp_dir/arm-image.qcow2"
if LOOPWIRE_VM_ROOT="$vm_arm_launch_root" \
  bash scripts/vm-matrix.sh launch \
    --target ubuntu-gnome-pipewire-aarch64 \
    --image "$tmp_dir/arm-image.qcow2" \
    --execute >/dev/null 2>&1; then
  echo "verify-scripts: AArch64 launch --execute accepted missing firmware" >&2
  exit 1
fi
if bash scripts/vm-matrix.sh launch --target arch-hyprland-pipewire --image /operator/images/arch.qcow2 --ssh-port 70000 \
  >/dev/null 2>&1; then
  echo "verify-scripts: vm launch accepted an invalid SSH port" >&2
  exit 1
fi
if bash scripts/vm-matrix.sh launch --target arch-hyprland-pipewire --image /operator/images/arch.qcow2 --memory nope \
  >/dev/null 2>&1; then
  echo "verify-scripts: vm launch accepted a non-numeric memory value" >&2
  exit 1
fi
if bash scripts/vm-matrix.sh launch --target arch-hyprland-pipewire --image /operator/images/arch.qcow2 --memory 256 \
  >/dev/null 2>&1; then
  echo "verify-scripts: vm launch accepted a too-small memory value" >&2
  exit 1
fi
if bash scripts/vm-matrix.sh launch --target arch-hyprland-pipewire --image /operator/images/arch.qcow2 --cpus 0 \
  >/dev/null 2>&1; then
  echo "verify-scripts: vm launch accepted an invalid CPU count" >&2
  exit 1
fi
if bash scripts/vm-matrix.sh launch \
  --target arch-hyprland-pipewire \
  --image /operator/images/arch.qcow2 \
  --image-format vmdk >/dev/null 2>&1; then
  echo "verify-scripts: vm launch accepted an unsupported image format" >&2
  exit 1
fi
if bash scripts/vm-matrix.sh render-launch-plan --all --target arch-hyprland-pipewire >/dev/null 2>&1; then
  echo "verify-scripts: vm launch plan accepted --all with --target" >&2
  exit 1
fi
if bash scripts/vm-matrix.sh render-launch-plan --all --start-port 65500 >/dev/null 2>&1; then
  echo "verify-scripts: vm launch plan accepted an exhausted port range" >&2
  exit 1
fi
if bash scripts/vm-matrix.sh render-runbook --all --target arch-hyprland-pipewire >/dev/null 2>&1; then
  echo "verify-scripts: vm runbook accepted --all with --target" >&2
  exit 1
fi
if bash scripts/vm-matrix.sh render-runbook --all --start-port 65500 >/dev/null 2>&1; then
  echo "verify-scripts: vm runbook accepted an exhausted port range" >&2
  exit 1
fi
if bash scripts/vm-matrix.sh render-launch-plan --target arch-hyprland-pipewire --memory 256 >/dev/null 2>&1; then
  echo "verify-scripts: vm launch plan accepted a too-small memory value" >&2
  exit 1
fi
if bash scripts/collect-vm-evidence-ssh.sh --target arch-hyprland-pipewire --host 127.0.0.1 --port nope \
  >/dev/null 2>&1; then
  echo "verify-scripts: SSH VM evidence collector accepted an invalid SSH port" >&2
  exit 1
fi
if bash scripts/collect-vm-evidence-ssh.sh \
  --target arch-hyprland-pipewire \
  --host 127.0.0.1 \
  --local-output-dir ../arch-hyprland-pipewire >/dev/null 2>&1; then
  echo "verify-scripts: SSH VM evidence collector accepted parent traversal in local output" >&2
  exit 1
fi
if bash scripts/collect-vm-evidence-ssh.sh \
  --target arch-hyprland-pipewire \
  --host 127.0.0.1 \
  --local-output-dir "$tmp_dir/shared-vm-evidence" >/dev/null 2>&1; then
  echo "verify-scripts: SSH VM evidence collector accepted a non-target-scoped local output" >&2
  exit 1
fi
if bash scripts/collect-vm-evidence-ssh.sh \
  --target arch-hyprland-pipewire \
  --host 127.0.0.1 \
  --remote-output-dir ../arch-hyprland-pipewire >/dev/null 2>&1; then
  echo "verify-scripts: SSH VM evidence collector accepted parent traversal in remote output" >&2
  exit 1
fi
if bash scripts/collect-vm-evidence-ssh.sh \
  --target arch-hyprland-pipewire \
  --host 127.0.0.1 \
  --remote-output-dir /tmp/shared-vm-evidence >/dev/null 2>&1; then
  echo "verify-scripts: SSH VM evidence collector accepted a non-target-scoped remote output" >&2
  exit 1
fi
bad_matrix_plan="$tmp_dir/bad-vm-ssh-plan.tsv"
printf '%s\t%s\t%s\n' "arch-hyprland-pipewire" "127.0.0.1" "nope" >"$bad_matrix_plan"
if bash scripts/collect-vm-matrix-evidence.sh --plan "$bad_matrix_plan" >/dev/null 2>&1; then
  echo "verify-scripts: matrix VM evidence collector accepted an invalid SSH port" >&2
  exit 1
fi
duplicate_matrix_plan="$tmp_dir/duplicate-vm-ssh-plan.tsv"
printf '%s\t%s\n%s\t%s\n' \
  "arch-hyprland-pipewire" \
  "127.0.0.1" \
  "arch-hyprland-pipewire" \
  "127.0.0.1" >"$duplicate_matrix_plan"
if bash scripts/collect-vm-matrix-evidence.sh --plan "$duplicate_matrix_plan" >/dev/null 2>&1; then
  echo "verify-scripts: matrix VM evidence collector accepted duplicate targets" >&2
  exit 1
fi
traversal_matrix_plan="$tmp_dir/traversal-vm-ssh-plan.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "arch-hyprland-pipewire" \
  "127.0.0.1" \
  "2222" \
  "loopwire" \
  "-" \
  "-" \
  "-" \
  "../arch-hyprland-pipewire" >"$traversal_matrix_plan"
if bash scripts/collect-vm-matrix-evidence.sh --plan "$traversal_matrix_plan" >/dev/null 2>&1; then
  echo "verify-scripts: matrix VM evidence collector accepted parent traversal in local output" >&2
  exit 1
fi
shared_output_matrix_plan="$tmp_dir/shared-output-vm-ssh-plan.tsv"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "arch-hyprland-pipewire" \
  "127.0.0.1" \
  "2222" \
  "loopwire" \
  "-" \
  "-" \
  "-" \
  "$tmp_dir/shared-vm-evidence" >"$shared_output_matrix_plan"
if bash scripts/collect-vm-matrix-evidence.sh --plan "$shared_output_matrix_plan" >/dev/null 2>&1; then
  echo "verify-scripts: matrix VM evidence collector accepted a non-target-scoped local output" >&2
  exit 1
fi
if bash scripts/collect-vm-evidence-ssh.sh \
  --target arch-hyprland-pipewire \
  --host 127.0.0.1 \
  --desktop-port 70000 >/dev/null 2>&1; then
  echo "verify-scripts: SSH VM evidence collector accepted an invalid desktop port" >&2
  exit 1
fi
if bash scripts/collect-vm-evidence.sh \
  --target arch-hyprland-pipewire \
  --output-dir "$tmp_dir/bad-vm-evidence" \
  --desktop-port 0 >/dev/null 2>&1; then
  echo "verify-scripts: guest VM evidence collector accepted an invalid desktop port" >&2
  exit 1
fi
if bash scripts/collect-vm-evidence.sh \
  --target arch-hyprland-pipewire \
  --output-dir "$tmp_dir/bad-release-required" \
  --require-published-release >/dev/null 2>&1; then
  echo "verify-scripts: guest VM evidence collector accepted required published-release smoke without release input" >&2
  exit 1
fi
if bash scripts/collect-vm-evidence.sh \
  --target arch-hyprland-pipewire \
  --output-dir "$tmp_dir/bad-github-source-required" \
  --published-release-dir /guest/release \
  --published-release-tag v0.1.0 \
  --release-public-key /guest/release-public.pem \
  --require-published-release \
  --require-github-release-source >/dev/null 2>&1; then
  echo "verify-scripts: guest VM evidence collector accepted GitHub-source proof with a release directory" >&2
  exit 1
fi
if bash scripts/collect-vm-evidence-ssh.sh \
  --target arch-hyprland-pipewire \
  --host 127.0.0.1 \
  --published-release-dir /guest/release >/dev/null 2>&1; then
  echo "verify-scripts: SSH VM evidence collector accepted published-release smoke without public key" >&2
  exit 1
fi
if bash scripts/collect-vm-evidence-ssh.sh \
  --target arch-hyprland-pipewire \
  --host 127.0.0.1 \
  --published-release-dir /guest/release \
  --published-release-tag v0.1.0 \
  --release-public-key /guest/release-public.pem \
  --require-published-release \
  --require-github-release-source >/dev/null 2>&1; then
  echo "verify-scripts: SSH VM evidence collector accepted GitHub-source proof with a release directory" >&2
  exit 1
fi
cloud_init_dir="$tmp_dir/all-cloud-init"
bash scripts/vm-matrix.sh render-cloud-init --all --output "$cloud_init_dir" >/dev/null
[ -x "$cloud_init_dir/arch-hyprland-pipewire/guest-commands.sh" ] || {
  echo "verify-scripts: render-cloud-init --all did not render arch target commands" >&2
  exit 1
}
[ -s "$cloud_init_dir/fedora-sway-pipewire/user-data" ] || {
  echo "verify-scripts: render-cloud-init --all did not render fedora sway user-data" >&2
  exit 1
}
grep -F "sudo npm install -g pnpm@11.3.0" "$cloud_init_dir/ubuntu-gnome-pipewire/guest-commands.sh" >/dev/null || {
  echo "verify-scripts: Ubuntu cloud-init bootstrap does not install pnpm" >&2
  exit 1
}
grep -F "sudo npm install -g pnpm@11.3.0" \
  "$cloud_init_dir/ubuntu-gnome-pipewire-aarch64/guest-commands.sh" >/dev/null || {
    echo "verify-scripts: Ubuntu AArch64 cloud-init bootstrap does not install pnpm" >&2
    exit 1
  }
grep -F "sudo npm install -g pnpm@11.3.0" "$cloud_init_dir/debian-xfce-pulseaudio/guest-commands.sh" >/dev/null || {
  echo "verify-scripts: Debian cloud-init bootstrap does not install pnpm" >&2
  exit 1
}
grep -F "nix develop --command bash scripts/collect-vm-evidence.sh" \
  "$cloud_init_dir/nixos-gnome-pipewire/guest-commands.sh" >/dev/null || {
    echo "verify-scripts: NixOS cloud-init evidence collector does not use nix develop" >&2
    exit 1
  }
grep -F "sudo zypper --non-interactive install" \
  "$cloud_init_dir/opensuse-kde-pipewire/guest-commands.sh" >/dev/null || {
    echo "verify-scripts: openSUSE cloud-init bootstrap does not use zypper" >&2
    exit 1
  }
grep -F "webkit2gtk3-devel" "$cloud_init_dir/opensuse-kde-pipewire/guest-commands.sh" >/dev/null || {
  echo "verify-scripts: openSUSE cloud-init bootstrap does not install WebKitGTK" >&2
  exit 1
}
if bash scripts/vm-matrix.sh render-cloud-init --all --target arch-hyprland-pipewire >/dev/null 2>&1; then
  echo "verify-scripts: render-cloud-init accepted both --all and --target" >&2
  exit 1
fi
vm_verify_output="$(bash scripts/vm-matrix.sh verify-cloud-init)"
printf '%s\n' "$vm_verify_output" | grep -F "Verified rendered cloud-init assets for 9 VM target(s)." >/dev/null || {
  echo "verify-scripts: verify-cloud-init did not verify all targets" >&2
  exit 1
}
target_cloud_init_dir="$tmp_dir/target-cloud-init"
bash scripts/vm-matrix.sh verify-cloud-init --target fedora-kde-jack --output "$target_cloud_init_dir" >/dev/null
[ -x "$target_cloud_init_dir/fedora-kde-jack/guest-commands.sh" ] || {
  echo "verify-scripts: verify-cloud-init target output did not render guest commands" >&2
  exit 1
}
if bash scripts/vm-matrix.sh verify-cloud-init --all >/dev/null 2>&1; then
  echo "verify-scripts: verify-cloud-init accepted unnecessary --all flag" >&2
  exit 1
fi

tmp_secret_file="$tmp_dir/release-key.pem"
tmp_secret_public_key="$tmp_dir/release-key-public.pem"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$tmp_secret_file" >/dev/null 2>&1
openssl pkey -in "$tmp_secret_file" -pubout -out "$tmp_secret_public_key" >/dev/null 2>&1
docs_dist="$tmp_dir/docs-dist"
mkdir -p "$docs_dist/assets"
printf '%s\n' "<!doctype html><title>Loopwire</title>" >"$docs_dist/index.html"
printf '%s\n' "body{color:#111}" >"$docs_dist/assets/site.css"
cp apps/docs/docs/public/install.sh "$docs_dist/install.sh"
bunny_manifest="$tmp_dir/docs-deployment-manifest.json"
bunny_git_head="$(git rev-parse HEAD)"
bunny_dry_run="$(
  bash scripts/deploy-docs-bunny.sh \
    --dist "$docs_dist" \
    --storage-zone loopwire-docs \
    --storage-endpoint ny.storage.bunnycdn.com \
    --remote-prefix preview \
    --deployment-manifest "$bunny_manifest" \
    --dry-run
)"
printf '%s\n' "$bunny_dry_run" | grep -F "would upload index.html -> https://ny.storage.bunnycdn.com/loopwire-docs/preview/index.html" >/dev/null || {
  echo "verify-scripts: Bunny docs deploy dry-run did not use the regional endpoint" >&2
  exit 1
}
printf '%s\n' "$bunny_dry_run" | grep -F "would upload install.sh -> https://ny.storage.bunnycdn.com/loopwire-docs/preview/install.sh" >/dev/null || {
  echo "verify-scripts: Bunny docs deploy dry-run did not upload the public installer" >&2
  exit 1
}
printf '%s\n' "$bunny_dry_run" | grep -F "Dry run complete; 3 docs file(s) would be uploaded" >/dev/null || {
  echo "verify-scripts: Bunny docs deploy dry-run did not count files" >&2
  exit 1
}
pnpm verify:docs-deployment -- \
  --manifest "$bunny_manifest" \
  --dist "$docs_dist" \
  --storage-zone loopwire-docs \
  --storage-endpoint ny.storage.bunnycdn.com \
  --remote-prefix preview \
  --git-head "$bunny_git_head" \
  --expected-dry-run true >/dev/null
node - "$bunny_manifest" "$bunny_git_head" <<'NODE' || {
const { readFileSync } = require("node:fs");

const manifest = JSON.parse(readFileSync(process.argv[2], "utf8"));
const expectedGitHead = process.argv[3];
const uploads = new Map(manifest.uploads.map((upload) => [upload.relativePath, upload]));

if (manifest.schema !== "loopwire.docs-deployment.v1") process.exit(1);
if (manifest.source?.gitHead !== expectedGitHead) process.exit(1);
if (manifest.dryRun !== true) process.exit(1);
if (manifest.fileCount !== 3) process.exit(1);
if (manifest.storage.zone !== "loopwire-docs") process.exit(1);
if (manifest.storage.endpoint !== "https://ny.storage.bunnycdn.com") process.exit(1);
if (manifest.storage.remotePrefix !== "preview") process.exit(1);
if (!manifest.requiredFiles.includes("index.html")) process.exit(1);
if (!manifest.requiredFiles.includes("install.sh")) process.exit(1);
if (uploads.get("install.sh")?.remotePath !== "preview/install.sh") process.exit(1);
if (uploads.get("assets/site.css")?.remotePath !== "preview/assets/site.css") process.exit(1);
if (JSON.stringify(manifest).includes("accessKey")) process.exit(1);
NODE
  echo "verify-scripts: Bunny docs deploy manifest is malformed" >&2
  exit 1
}
if pnpm verify:docs-deployment -- \
  --manifest "$bunny_manifest" \
  --dist "$docs_dist" \
  --git-head 0000000000000000000000000000000000000000 \
  --expected-dry-run true >/dev/null 2>&1; then
  echo "verify-scripts: docs deployment manifest verifier accepted a mismatched git head" >&2
  exit 1
fi
printf '%s\n' "body{color:#222}" >"$docs_dist/assets/site.css"
if pnpm verify:docs-deployment -- \
  --manifest "$bunny_manifest" \
  --dist "$docs_dist" \
  --storage-zone loopwire-docs \
  --storage-endpoint ny.storage.bunnycdn.com \
  --remote-prefix preview \
  --expected-dry-run true >/dev/null 2>&1; then
  echo "verify-scripts: docs deployment manifest verifier accepted stale checksums" >&2
  exit 1
fi
printf '%s\n' "body{color:#111}" >"$docs_dist/assets/site.css"
docs_dist_missing_installer="$tmp_dir/docs-dist-missing-installer"
mkdir -p "$docs_dist_missing_installer"
printf '%s\n' "<!doctype html><title>Loopwire</title>" >"$docs_dist_missing_installer/index.html"
if bash scripts/deploy-docs-bunny.sh \
  --dist "$docs_dist_missing_installer" \
  --storage-zone loopwire-docs \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: Bunny docs deploy accepted a dist without install.sh" >&2
  exit 1
fi
docs_dist_missing_home="$tmp_dir/docs-dist-missing-home"
mkdir -p "$docs_dist_missing_home"
cp apps/docs/docs/public/install.sh "$docs_dist_missing_home/install.sh"
if bash scripts/deploy-docs-bunny.sh \
  --dist "$docs_dist_missing_home" \
  --storage-zone loopwire-docs \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: Bunny docs deploy accepted a dist without index.html" >&2
  exit 1
fi
if bash scripts/deploy-docs-bunny.sh \
  --dist "$docs_dist" \
  --storage-zone loopwire-docs \
  --remote-prefix "../escape" \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: Bunny docs deploy accepted an unsafe remote prefix" >&2
  exit 1
fi
docs_live_bin="$tmp_dir/docs-live-bin"
mkdir -p "$docs_live_bin"
cat >"$docs_live_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

output=""
url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      output="${2:?missing output}"
      shift 2
      ;;
    --max-time)
      shift 2
      ;;
    -*)
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done

[ -n "$output" ] || {
  echo "missing -o output" >&2
  exit 64
}

case "$url" in
  */install.sh)
    cp "${LOOPWIRE_FAKE_INSTALLER:?}" "$output"
    ;;
  */ | */preview)
    printf '%s\n' "<!doctype html><title>Loopwire</title><main>Loopwire</main>" >"$output"
    ;;
  *)
    echo "unexpected URL: $url" >&2
    exit 65
    ;;
esac
EOF
chmod +x "$docs_live_bin/curl"
docs_live_output="$(
  PATH="$docs_live_bin:$PATH" \
    LOOPWIRE_FAKE_INSTALLER="apps/docs/docs/public/install.sh" \
    bash scripts/verify-docs-live.sh --hostname docs.example.test --remote-prefix preview
)"
printf '%s\n' "$docs_live_output" | grep -F "Live docs smoke passed for https://docs.example.test/preview." >/dev/null || {
  echo "verify-scripts: live docs smoke did not verify the expected pull-zone URL" >&2
  exit 1
}
bad_live_installer="$tmp_dir/bad-live-install.sh"
printf '%s\n' "#!/usr/bin/env bash" "echo stale" >"$bad_live_installer"
if PATH="$docs_live_bin:$PATH" \
  LOOPWIRE_FAKE_INSTALLER="$bad_live_installer" \
  bash scripts/verify-docs-live.sh --hostname docs.example.test --remote-prefix preview >/dev/null 2>&1; then
  echo "verify-scripts: live docs smoke accepted a stale deployed installer" >&2
  exit 1
fi
if PATH="$docs_live_bin:$PATH" \
  LOOPWIRE_FAKE_INSTALLER="apps/docs/docs/public/install.sh" \
  bash scripts/verify-docs-live.sh --hostname docs.example.test --remote-prefix "../escape" >/dev/null 2>&1; then
  echo "verify-scripts: live docs smoke accepted an unsafe remote prefix" >&2
  exit 1
fi
github_secret_dry_run="$(
  bash scripts/setup-github-secrets.sh \
    --repo sandwichfarm/loopwire \
    --storage-zone loopwire-docs \
    --access-key dry-run-access-key \
    --storage-endpoint ny.storage.bunnycdn.com \
    --remote-prefix private-prefix-value \
    --release-private-key-file "$tmp_secret_file" \
    --release-public-key-file "$tmp_secret_public_key" \
    --dry-run
)"
printf '%s\n' "$github_secret_dry_run" | grep -F "would set optional GitHub secret for sandwichfarm/loopwire: BUNNY_REMOTE_PREFIX" \
  >/dev/null || {
    echo "verify-scripts: GitHub secret helper dry-run did not include remote prefix" >&2
    exit 1
  }
printf '%s\n' "$github_secret_dry_run" | grep -F "private-prefix-value" >/dev/null && {
  echo "verify-scripts: GitHub secret helper dry-run leaked a secret value" >&2
  exit 1
}
github_secret_env_file="$tmp_dir/setup-github-secrets.env"
cat >"$github_secret_env_file" <<EOF
# Local release-secret inputs. Values must never be committed.
BUNNY_STORAGE_ZONE=env-loopwire-docs
BUNNY_ACCESS_KEY=env-access-key
BUNNY_STORAGE_ENDPOINT=ny.storage.bunnycdn.com
BUNNY_PULL_ZONE_HOSTNAME=docs.env.example.test
BUNNY_REMOTE_PREFIX=env-private-prefix
LOOPWIRE_RELEASE_PRIVATE_KEY_FILE=$tmp_secret_file
LOOPWIRE_RELEASE_PUBLIC_KEY_FILE=$tmp_secret_public_key
EOF
for required_env_example_key in \
  BUNNY_STORAGE_ZONE \
  BUNNY_ACCESS_KEY \
  BUNNY_STORAGE_ENDPOINT \
  BUNNY_PULL_ZONE_HOSTNAME \
  BUNNY_REMOTE_PREFIX \
  LOOPWIRE_RELEASE_PRIVATE_KEY_FILE \
  LOOPWIRE_RELEASE_PUBLIC_KEY_FILE; do
  grep -E "^${required_env_example_key}=" .env.example >/dev/null || {
    echo "verify-scripts: .env.example is missing ${required_env_example_key}" >&2
    exit 1
  }
done
github_secret_env_dry_run="$(
  bash scripts/setup-github-secrets.sh \
    --repo sandwichfarm/loopwire \
    --env-file "$github_secret_env_file" \
    --dry-run
)"
printf '%s\n' "$github_secret_env_dry_run" |
  grep -F "would set GitHub secret for sandwichfarm/loopwire: BUNNY_STORAGE_ZONE" >/dev/null || {
    echo "verify-scripts: GitHub secret helper env-file dry-run did not include storage zone" >&2
    exit 1
  }
printf '%s\n' "$github_secret_env_dry_run" |
  grep -F "would set GitHub secret for sandwichfarm/loopwire: LOOPWIRE_RELEASE_PRIVATE_KEY" >/dev/null || {
    echo "verify-scripts: GitHub secret helper env-file dry-run did not include release private key" >&2
    exit 1
  }
if printf '%s\n' "$github_secret_env_dry_run" | grep -F "env-access-key" >/dev/null; then
  echo "verify-scripts: GitHub secret helper env-file dry-run leaked access key" >&2
  exit 1
fi
if printf '%s\n' "$github_secret_env_dry_run" | grep -F "env-private-prefix" >/dev/null; then
  echo "verify-scripts: GitHub secret helper env-file dry-run leaked remote prefix" >&2
  exit 1
fi
github_secret_env_override_dry_run="$(
  bash scripts/setup-github-secrets.sh \
    --repo sandwichfarm/loopwire \
    --env-file "$github_secret_env_file" \
    --access-key cli-access-key \
    --dry-run
)"
if printf '%s\n' "$github_secret_env_override_dry_run" | grep -F "cli-access-key" >/dev/null; then
  echo "verify-scripts: GitHub secret helper env-file override dry-run leaked CLI access key" >&2
  exit 1
fi
github_secret_bad_env_file="$tmp_dir/setup-github-secrets-bad.env"
printf '%s\n' "BUNNY_STORAGE_TOKEN=typo" >"$github_secret_bad_env_file"
if bash scripts/setup-github-secrets.sh \
  --repo sandwichfarm/loopwire \
  --env-file "$github_secret_bad_env_file" \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: GitHub secret helper accepted an unsupported env-file key" >&2
  exit 1
fi
github_secret_env_symlink="$tmp_dir/setup-github-secrets-env-symlink"
ln -s "$github_secret_env_file" "$github_secret_env_symlink"
if bash scripts/setup-github-secrets.sh \
  --repo sandwichfarm/loopwire \
  --env-file "$github_secret_env_symlink" \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: GitHub secret helper accepted a symlink env file" >&2
  exit 1
fi
github_secret_private_key_symlink="$tmp_dir/setup-github-secrets-private-key-symlink"
ln -s "$tmp_secret_file" "$github_secret_private_key_symlink"
if bash scripts/setup-github-secrets.sh \
  --repo sandwichfarm/loopwire \
  --release-private-key-file "$github_secret_private_key_symlink" \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: GitHub secret helper accepted a symlink release private key" >&2
  exit 1
fi
github_secret_public_key_dir="$tmp_dir/setup-github-secrets-public-key-dir"
mkdir -p "$github_secret_public_key_dir"
if bash scripts/setup-github-secrets.sh \
  --repo sandwichfarm/loopwire \
  --release-private-key-file "$tmp_secret_file" \
  --release-public-key-file "$github_secret_public_key_dir" \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: GitHub secret helper accepted a directory release public key" >&2
  exit 1
fi
if bash scripts/setup-github-secrets.sh \
  --repo sandwichfarm/loopwire \
  --storage-zone "loopwire/docs" \
  --access-key dry-run-access-key \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: GitHub secret helper accepted a storage zone with slashes" >&2
  exit 1
fi
if bash scripts/setup-github-secrets.sh \
  --repo sandwichfarm/loopwire \
  --storage-zone loopwire-docs \
  --access-key dry-run-access-key \
  --remote-prefix "../escape" \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: GitHub secret helper accepted an unsafe remote prefix" >&2
  exit 1
fi
if bash scripts/setup-github-secrets.sh \
  --repo sandwichfarm/loopwire \
  --storage-zone loopwire-docs \
  --access-key dry-run-access-key \
  --pull-zone-hostname "https://docs.example.test" \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: GitHub secret helper accepted a URL as pull-zone hostname" >&2
  exit 1
fi
hostname_only_secret_dry_run="$(
  bash scripts/setup-github-secrets.sh \
    --repo sandwichfarm/loopwire \
    --pull-zone-hostname docs.example.test \
    --dry-run
)"
printf '%s\n' "$hostname_only_secret_dry_run" |
  grep -F "would set GitHub secret for sandwichfarm/loopwire: BUNNY_PULL_ZONE_HOSTNAME" >/dev/null || {
    echo "verify-scripts: GitHub secret helper did not allow hostname-only dry-run setup" >&2
    exit 1
  }
if printf '%s\n' "$hostname_only_secret_dry_run" | grep -F "BUNNY_STORAGE_ZONE" >/dev/null; then
  echo "verify-scripts: GitHub secret helper required storage secrets for hostname-only setup" >&2
  exit 1
fi
if bash scripts/setup-github-secrets.sh \
  --repo sandwichfarm/loopwire \
  --storage-zone loopwire-docs \
  --access-key dry-run-access-key \
  --storage-endpoint $'ny.storage.bunnycdn.com\nescape' \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: GitHub secret helper accepted a newline in storage endpoint" >&2
  exit 1
fi
bad_secret_public_key="$tmp_dir/bad-release-key-public.pem"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$tmp_dir/bad-release-key.pem" >/dev/null 2>&1
openssl pkey -in "$tmp_dir/bad-release-key.pem" -pubout -out "$bad_secret_public_key" >/dev/null 2>&1
if bash scripts/setup-github-secrets.sh \
  --repo sandwichfarm/loopwire \
  --release-private-key-file "$tmp_secret_file" \
  --release-public-key-file "$bad_secret_public_key" \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: GitHub secret helper accepted mismatched release signing keys" >&2
  exit 1
fi
printf '%s\n' "not a private key" >"$tmp_dir/not-a-private-key.pem"
if bash scripts/setup-github-secrets.sh \
  --repo sandwichfarm/loopwire \
  --release-private-key-file "$tmp_dir/not-a-private-key.pem" \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: GitHub secret helper accepted an invalid release private key" >&2
  exit 1
fi
fake_gh_dir="$tmp_dir/fake-gh"
mkdir -p "$fake_gh_dir"
cat >"$fake_gh_dir/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "$1 ${2:-}" in
  "repo view")
    exit 0
    ;;
  "secret list")
    if [ "${LOOPWIRE_FAKE_GH_SECRET_MODE:-ok}" = "fail" ]; then
      echo "api denied" >&2
      exit 42
    fi
    if [ "${LOOPWIRE_FAKE_GH_SECRET_MODE:-ok}" = "missing-required" ]; then
      printf '%s\t%s\n' "LOOPWIRE_RELEASE_PRIVATE_KEY" "2026-07-04T00:00:00Z"
      exit 0
    fi
    if [ "${LOOPWIRE_FAKE_GH_SECRET_MODE:-ok}" = "missing-live-docs" ]; then
      printf '%s\t%s\n' "BUNNY_STORAGE_ZONE" "2026-07-04T00:00:00Z"
      printf '%s\t%s\n' "BUNNY_ACCESS_KEY" "2026-07-04T00:00:00Z"
      printf '%s\t%s\n' "LOOPWIRE_RELEASE_PRIVATE_KEY" "2026-07-04T00:00:00Z"
      exit 0
    fi
    if [ "${LOOPWIRE_FAKE_GH_SECRET_MODE:-ok}" = "missing-release-key" ]; then
      printf '%s\t%s\n' "BUNNY_STORAGE_ZONE" "2026-07-04T00:00:00Z"
      printf '%s\t%s\n' "BUNNY_ACCESS_KEY" "2026-07-04T00:00:00Z"
      printf '%s\t%s\n' "BUNNY_PULL_ZONE_HOSTNAME" "2026-07-04T00:00:00Z"
      exit 0
    fi
    printf '%s\t%s\n' "BUNNY_STORAGE_ZONE" "2026-07-04T00:00:00Z"
    printf '%s\t%s\n' "BUNNY_ACCESS_KEY" "2026-07-04T00:00:00Z"
    printf '%s\t%s\n' "BUNNY_PULL_ZONE_HOSTNAME" "2026-07-04T00:00:00Z"
    printf '%s\t%s\n' "LOOPWIRE_RELEASE_PRIVATE_KEY" "2026-07-04T00:00:00Z"
    printf '%s\t%s\n' "BUNNY_STORAGE_ENDPOINT" "2026-07-04T00:00:00Z"
    printf '%s\t%s\n' "BUNNY_REMOTE_PREFIX" "2026-07-04T00:00:00Z"
    exit 0
    ;;
  "secret set")
    secret_name="${3:?missing fake secret name}"
    shift 3
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --repo)
          shift 2
          ;;
        *)
          echo "unexpected fake gh secret set arg: $1" >&2
          exit 64
          ;;
      esac
    done
    mkdir -p "${LOOPWIRE_FAKE_GH_SET_DIR:?}"
    cat >"${LOOPWIRE_FAKE_GH_SET_DIR}/${secret_name}"
    exit 0
    ;;
  "release view")
    case "${LOOPWIRE_FAKE_GH_RELEASE_MODE:-missing}" in
      ok)
        release_tag="v0.1.0"
        release_draft="false"
        release_prerelease="false"
        release_assets="full"
        ;;
      wrong-tag)
        release_tag="v0.2.0"
        release_draft="false"
        release_prerelease="false"
        release_assets="full"
        ;;
      draft)
        release_tag="v0.1.0"
        release_draft="true"
        release_prerelease="false"
        release_assets="full"
        ;;
      prerelease)
        release_tag="v0.1.0"
        release_draft="false"
        release_prerelease="true"
        release_assets="full"
        ;;
      missing-asset)
        release_tag="v0.1.0"
        release_draft="false"
        release_prerelease="false"
        release_assets="missing-vm"
        ;;
      missing)
        exit 1
        ;;
      *)
        echo "unexpected LOOPWIRE_FAKE_GH_RELEASE_MODE: ${LOOPWIRE_FAKE_GH_RELEASE_MODE}" >&2
        exit 64
        ;;
    esac
    node - "$release_tag" "$release_draft" "$release_prerelease" "$release_assets" <<'NODE'
const [tagName, draftRaw, prereleaseRaw, assetMode] = process.argv.slice(2);
const assets = [
  "loopwire-linux-x86_64.tar.gz",
  "loopwire-linux-aarch64.tar.gz",
  "SHA256SUMS",
  "SHA256SUMS.sig",
  `loopwire-release-evidence-${tagName}.tar.gz`,
  `loopwire-vm-evidence-${tagName}.tar.gz`
];
const filtered = assetMode === "missing-vm"
  ? assets.filter((name) => !name.startsWith("loopwire-vm-evidence-"))
  : assets;
const release = {
  tagName,
  url: `https://github.example/releases/${tagName}`,
  targetCommitish: "main",
  isDraft: draftRaw === "true",
  isPrerelease: prereleaseRaw === "true",
  assets: filtered.map((name) => ({ name }))
};

console.log(JSON.stringify(release, null, 2));
NODE
    exit 0
    ;;
  "release download")
    release_tag="${3:?missing fake release tag}"
    shift 3
    output_dir=""
    pattern=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --repo)
          shift 2
          ;;
        --dir)
          output_dir="${2:?missing fake release download dir}"
          shift 2
          ;;
        --pattern)
          pattern="${2:?missing fake release download pattern}"
          shift 2
          ;;
        --clobber)
          shift
          ;;
        *)
          echo "unexpected fake gh release download arg: $1" >&2
          exit 64
          ;;
      esac
    done
    [ "$release_tag" = "v0.1.0" ] || {
      echo "unexpected fake release download tag: $release_tag" >&2
      exit 64
    }
    [ -n "$output_dir" ] || {
      echo "missing fake release download dir" >&2
      exit 64
    }
    [ -n "$pattern" ] || {
      echo "missing fake release download pattern" >&2
      exit 64
    }
    [ -n "${LOOPWIRE_FAKE_GH_RELEASE_DIR:-}" ] || {
      echo "fake release download dir is not configured" >&2
      exit 1
    }
    [ -f "${LOOPWIRE_FAKE_GH_RELEASE_DIR}/${pattern}" ] || {
      echo "fake release asset not found: $pattern" >&2
      exit 1
    }
    mkdir -p "$output_dir"
    cp "${LOOPWIRE_FAKE_GH_RELEASE_DIR}/${pattern}" "$output_dir/$pattern"
    exit 0
    ;;
  "run list")
    workflow_name=""
    commit_filter=""
    json_fields=""
    shift 2
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --repo | --workflow | --limit | --json | --commit)
          if [ "$1" = "--workflow" ]; then
            workflow_name="${2:?missing fake workflow name}"
          fi
          if [ "$1" = "--commit" ]; then
            commit_filter="${2:?missing fake commit filter}"
          fi
          if [ "$1" = "--json" ]; then
            json_fields="${2:?missing fake json fields}"
          fi
          shift 2
          ;;
        *)
          echo "unexpected fake gh run list arg: $1" >&2
          exit 64
          ;;
      esac
    done
    if printf '%s\n' "$json_fields" | grep -F "headSha" >/dev/null; then
      [[ "$commit_filter" =~ ^[0-9a-fA-F]{40}$ ]] || {
        echo "unexpected or missing fake run commit filter: $commit_filter" >&2
        exit 64
      }
    fi
    run_mode="${LOOPWIRE_FAKE_GH_RUN_MODE:-empty}"
    if [ "$workflow_name" = "ci.yml" ] && [ -n "${LOOPWIRE_FAKE_GH_CI_RUN_MODE:-}" ]; then
      run_mode="$LOOPWIRE_FAKE_GH_CI_RUN_MODE"
    fi
    if [ -n "${LOOPWIRE_FAKE_GH_TRACE:-}" ]; then
      printf '%s\t%s\t%s\n' "run list" "$workflow_name" "$commit_filter" >>"$LOOPWIRE_FAKE_GH_TRACE"
    fi
    run_title="$workflow_name"
    if [ "$workflow_name" = "final-release-proof.yml" ]; then
      case "${LOOPWIRE_FAKE_GH_FINAL_PROOF_TITLE_MODE:-ok}" in
        ok)
          run_title="Final Release Proof v0.1.0 @ 0123456789abcdef0123456789abcdef01234567"
          ;;
        wrong-tag)
          run_title="Final Release Proof v0.2.0 @ 0123456789abcdef0123456789abcdef01234567"
          ;;
        *)
          echo "unexpected LOOPWIRE_FAKE_GH_FINAL_PROOF_TITLE_MODE: ${LOOPWIRE_FAKE_GH_FINAL_PROOF_TITLE_MODE}" >&2
          exit 64
          ;;
      esac
    fi
    case "$run_mode" in
      empty)
        printf '%s\n' '[]'
        ;;
      success)
        node - "$run_title" "completed" "success" <<'NODE'
const [displayTitle, status, conclusion] = process.argv.slice(2);
console.log(JSON.stringify([{
  databaseId: 123456,
  status,
  conclusion,
  headBranch: "master",
  headSha: "0123456789abcdef0123456789abcdef01234567",
  displayTitle,
  createdAt: "2026-07-04T00:00:00Z",
  url: "https://github.example/actions/runs/123456"
}], null, 2));
NODE
        ;;
      failed)
        node - "$run_title" "completed" "failure" <<'NODE'
const [displayTitle, status, conclusion] = process.argv.slice(2);
console.log(JSON.stringify([{
  databaseId: 123456,
  status,
  conclusion,
  headBranch: "master",
  headSha: "0123456789abcdef0123456789abcdef01234567",
  displayTitle,
  createdAt: "2026-07-04T00:00:00Z",
  url: "https://github.example/actions/runs/123456"
}], null, 2));
NODE
        ;;
      running)
        node - "$run_title" "in_progress" "" <<'NODE'
const [displayTitle, status, conclusion] = process.argv.slice(2);
console.log(JSON.stringify([{
  databaseId: 123456,
  status,
  conclusion: conclusion === "" ? null : conclusion,
  headBranch: "master",
  headSha: "0123456789abcdef0123456789abcdef01234567",
  displayTitle,
  createdAt: "2026-07-04T00:00:00Z",
  url: "https://github.example/actions/runs/123456"
}], null, 2));
NODE
        ;;
      *)
        echo "unexpected fake gh run mode: ${run_mode}" >&2
        exit 64
        ;;
    esac
    exit 0
    ;;
  "run view")
    run_id="${3:?missing fake run id}"
    shift 3
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --repo | --json)
          shift 2
          ;;
        *)
          echo "unexpected fake gh run view arg: $1" >&2
          exit 64
          ;;
      esac
    done
    case "${LOOPWIRE_FAKE_GH_RUN_MODE:-empty}" in
      empty)
        exit 1
        ;;
      success)
        run_status="completed"
        run_conclusion="success"
        ;;
      failed)
        run_status="completed"
        run_conclusion="failure"
        ;;
      running)
        run_status="in_progress"
        run_conclusion=""
        ;;
      *)
        echo "unexpected LOOPWIRE_FAKE_GH_RUN_MODE: ${LOOPWIRE_FAKE_GH_RUN_MODE}" >&2
        exit 64
        ;;
    esac
    node - "$run_id" "$run_status" "$run_conclusion" <<'NODE'
const [databaseId, status, conclusion] = process.argv.slice(2);
console.log(JSON.stringify({
  databaseId: Number(databaseId),
  status,
  conclusion: conclusion === "" ? null : conclusion,
  headBranch: "master",
  headSha: "0123456789abcdef0123456789abcdef01234567",
  displayTitle: "Deploy Docs",
  createdAt: "2026-07-04T00:00:00Z",
  url: `https://github.example/actions/runs/${databaseId}`
}, null, 2));
NODE
    exit 0
    ;;
  api\ *)
    api_path="$2"
    shift 2
    jq_expr=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --jq)
          jq_expr="${2:?missing fake jq expression}"
          shift 2
          ;;
        *)
          echo "unexpected fake gh api arg: $1" >&2
          exit 64
        ;;
      esac
    done
    if [[ "$api_path" =~ ^repos/sandwichfarm/loopwire/git/ref/tags/v0[.]1[.]0$ ]]; then
      case "${LOOPWIRE_FAKE_GH_TAG_MODE:-matching}" in
        matching)
          cat <<'JSON'
{
  "ref": "refs/tags/v0.1.0",
  "object": {
    "type": "commit",
    "sha": "0123456789abcdef0123456789abcdef01234567"
  }
}
JSON
          ;;
        annotated)
          cat <<'JSON'
{
  "ref": "refs/tags/v0.1.0",
  "object": {
    "type": "tag",
    "sha": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  }
}
JSON
          ;;
        wrong-commit)
          cat <<'JSON'
{
  "ref": "refs/tags/v0.1.0",
  "object": {
    "type": "commit",
    "sha": "ffffffffffffffffffffffffffffffffffffffff"
  }
}
JSON
          ;;
        missing)
          echo "tag ref not found" >&2
          exit 1
          ;;
        *)
          echo "unexpected LOOPWIRE_FAKE_GH_TAG_MODE: ${LOOPWIRE_FAKE_GH_TAG_MODE}" >&2
          exit 64
          ;;
      esac
      exit 0
    fi
    if [[ "$api_path" =~ ^repos/sandwichfarm/loopwire/git/tags/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa$ ]]; then
      case "${LOOPWIRE_FAKE_GH_TAG_MODE:-matching}" in
        annotated)
          cat <<'JSON'
{
  "tag": "v0.1.0",
  "object": {
    "type": "commit",
    "sha": "0123456789abcdef0123456789abcdef01234567"
  }
}
JSON
          ;;
        *)
          echo "unexpected annotated tag dereference mode: ${LOOPWIRE_FAKE_GH_TAG_MODE}" >&2
          exit 64
          ;;
      esac
      exit 0
    fi
    [[ "$api_path" =~ ^repos/sandwichfarm/loopwire/actions/runs/[0-9]+/artifacts$ ]] || {
      echo "unexpected fake gh api path: $api_path" >&2
      exit 64
    }
    [ "$jq_expr" = ".artifacts[].name" ] || {
      echo "unexpected fake gh api jq expression: $jq_expr" >&2
      exit 64
    }
    case "${LOOPWIRE_FAKE_GH_ARTIFACT_MODE:-ok}" in
      ok)
        printf '%s\n' "loopwire-docs" "loopwire-docs-deployment"
        ;;
      missing-deployment)
        printf '%s\n' "loopwire-docs"
        ;;
      empty)
        ;;
      fail)
        echo "artifact api denied" >&2
        exit 42
        ;;
      *)
        echo "unexpected LOOPWIRE_FAKE_GH_ARTIFACT_MODE: ${LOOPWIRE_FAKE_GH_ARTIFACT_MODE}" >&2
        exit 64
        ;;
    esac
    exit 0
    ;;
  "run download")
    run_id="${3:?missing fake run id}"
    shift 3
    artifact_name=""
    output_dir=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --repo)
          shift 2
          ;;
        --name)
          artifact_name="${2:?missing fake artifact name}"
          shift 2
          ;;
        --dir)
          output_dir="${2:?missing fake artifact output dir}"
          shift 2
          ;;
        *)
          echo "unexpected fake gh run download arg: $1" >&2
          exit 64
          ;;
      esac
    done
    [ "$run_id" = "123456" ] || {
      echo "unexpected fake run id: $run_id" >&2
      exit 64
    }
    [ -n "$artifact_name" ] || {
      echo "missing fake artifact name" >&2
      exit 64
    }
    [ -n "$output_dir" ] || {
      echo "missing fake artifact output dir" >&2
      exit 64
    }
    mkdir -p "$output_dir"
    case "$artifact_name" in
      loopwire-docs)
        printf '%s\n' '<!doctype html><title>Loopwire</title>' >"$output_dir/index.html"
        printf '%s\n' '#!/usr/bin/env bash' 'echo install loopwire' >"$output_dir/install.sh"
        ;;
      loopwire-docs-deployment)
        node - "$output_dir" "${LOOPWIRE_FAKE_DOCS_DIST:-}" <<'NODE'
const { createHash } = require("node:crypto");
const { existsSync, readdirSync, readFileSync, writeFileSync } = require("node:fs");
const { dirname, join } = require("node:path");

const [outputDir, docsDistArg] = process.argv.slice(2);
const stagedDocsDist = join(dirname(outputDir), "docs-dist");
const docsDist = docsDistArg && existsSync(docsDistArg) ? docsDistArg : stagedDocsDist;
const uploads = readdirSync(docsDist)
  .sort()
  .map((relativePath) => {
    const bytes = readFileSync(join(docsDist, relativePath));
    return {
      relativePath,
      remotePath: relativePath,
      checksumSha256: createHash("sha256").update(bytes).digest("hex").toUpperCase()
    };
  });

writeFileSync(join(outputDir, "deployment-manifest.json"), `${JSON.stringify({
  schema: "loopwire.docs-deployment.v1",
  generatedAt: "2026-07-04T00:00:00.000Z",
  dryRun: false,
  distDir: docsDist,
  storage: {
    zone: "loopwire-docs",
    endpoint: "https://storage.bunnycdn.com",
    remotePrefix: ""
  },
  source: {
    gitHead: "0123456789abcdef0123456789abcdef01234567"
  },
  requiredFiles: ["index.html", "install.sh"],
  fileCount: uploads.length,
  uploads
}, null, 2)}\n`);
NODE
        ;;
      *)
        echo "artifact not found: $artifact_name" >&2
        exit 1
        ;;
    esac
    exit 0
    ;;
esac

echo "unexpected fake gh args: $*" >&2
exit 64
EOF
chmod +x "$fake_gh_dir/gh"
fetch_docs_proof_root="dist/verify-scripts/fetch-docs-proof"
fetch_docs_proof_dist="$fetch_docs_proof_root/docs-dist"
fetch_docs_proof_manifest="$fetch_docs_proof_root/docs-deployment/deployment-manifest.json"
rm -rf "$fetch_docs_proof_root"
LOOPWIRE_FAKE_DOCS_DIST="$fetch_docs_proof_dist" PATH="$fake_gh_dir:$PATH" \
  bash scripts/fetch-docs-deployment-proof.sh \
    --repo sandwichfarm/loopwire \
    --run-id 123456 \
    --git-head 0123456789abcdef0123456789abcdef01234567 \
    --docs-dist "$fetch_docs_proof_dist" \
    --manifest "$fetch_docs_proof_manifest" >"$tmp_dir/fetch-docs-proof.log"
grep -F "Docs deployment manifest verified: $fetch_docs_proof_manifest" "$tmp_dir/fetch-docs-proof.log" >/dev/null || {
  echo "verify-scripts: docs deployment proof helper did not verify the fetched manifest" >&2
  exit 1
}
grep -F "Docs deployment proof ready:" "$tmp_dir/fetch-docs-proof.log" >/dev/null || {
  echo "verify-scripts: docs deployment proof helper did not report ready proof" >&2
  exit 1
}
if PATH="$fake_gh_dir:$PATH" bash scripts/fetch-docs-deployment-proof.sh \
  --repo sandwichfarm/loopwire \
  --run-id not-a-run \
  --git-head 0123456789abcdef0123456789abcdef01234567 >/dev/null 2>&1; then
  echo "verify-scripts: docs deployment proof helper accepted an invalid run id" >&2
  exit 1
fi
if PATH="$fake_gh_dir:$PATH" bash scripts/fetch-docs-deployment-proof.sh \
  --repo sandwichfarm/loopwire \
  --run-id 123456 \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --docs-dist /tmp/loopwire-docs-dist >/dev/null 2>&1; then
  echo "verify-scripts: docs deployment proof helper accepted an absolute docs dist path" >&2
  exit 1
fi
if PATH="$fake_gh_dir:$PATH" bash scripts/fetch-docs-deployment-proof.sh \
  --repo sandwichfarm/loopwire \
  --run-id 123456 \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --manifest ../deployment-manifest.json >/dev/null 2>&1; then
  echo "verify-scripts: docs deployment proof helper accepted a parent-traversal manifest path" >&2
  exit 1
fi
fetch_docs_path_guard_root="dist/verify-scripts/fetch-docs-proof-path-guard"
fetch_docs_dist_symlink="$fetch_docs_path_guard_root/docs-dist-symlink"
fetch_docs_manifest_dir="$fetch_docs_path_guard_root/manifest-dir"
fetch_docs_guard_env_file="$fetch_docs_path_guard_root/env-file"
fetch_docs_env_file_symlink="$fetch_docs_path_guard_root/env-file-symlink"
rm -rf "$fetch_docs_path_guard_root"
mkdir -p "$fetch_docs_path_guard_root"
ln -s "$fetch_docs_path_guard_root" "$fetch_docs_dist_symlink"
mkdir -p "$fetch_docs_manifest_dir"
printf '%s\n' "BUNNY_STORAGE_ZONE=loopwire-docs" >"$fetch_docs_guard_env_file"
ln -s "$fetch_docs_guard_env_file" "$fetch_docs_env_file_symlink"
if PATH="$fake_gh_dir:$PATH" bash scripts/fetch-docs-deployment-proof.sh \
  --repo sandwichfarm/loopwire \
  --run-id 123456 \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --docs-dist "$fetch_docs_dist_symlink" >/dev/null 2>&1; then
  echo "verify-scripts: docs deployment proof helper accepted a symlink docs dist path" >&2
  rm -rf "$fetch_docs_path_guard_root"
  exit 1
fi
if PATH="$fake_gh_dir:$PATH" bash scripts/fetch-docs-deployment-proof.sh \
  --repo sandwichfarm/loopwire \
  --run-id 123456 \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --manifest "$fetch_docs_manifest_dir" >/dev/null 2>&1; then
  echo "verify-scripts: docs deployment proof helper accepted a directory manifest path" >&2
  rm -rf "$fetch_docs_path_guard_root"
  exit 1
fi
if PATH="$fake_gh_dir:$PATH" bash scripts/fetch-docs-deployment-proof.sh \
  --repo sandwichfarm/loopwire \
  --run-id 123456 \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --env-file "$fetch_docs_env_file_symlink" >/dev/null 2>&1; then
  echo "verify-scripts: docs deployment proof helper accepted a symlink env-file path" >&2
  rm -rf "$fetch_docs_path_guard_root"
  exit 1
fi
rm -rf "$fetch_docs_path_guard_root"
fetch_docs_missing_root="dist/verify-scripts/fetch-docs-proof-missing-artifact"
fetch_docs_missing_dist="$fetch_docs_missing_root/docs-dist"
fetch_docs_missing_manifest="$fetch_docs_missing_root/docs-deployment/deployment-manifest.json"
rm -rf "$fetch_docs_missing_root"
fetch_docs_missing_env_file="$tmp_dir/fetch-docs-proof-release-secrets.env"
cat >"$fetch_docs_missing_env_file" <<'EOF'
BUNNY_STORAGE_ZONE=loopwire-docs
BUNNY_ACCESS_KEY=env-access-key-that-must-not-print
BUNNY_PULL_ZONE_HOSTNAME=docs.env.example.test
LOOPWIRE_RELEASE_PRIVATE_KEY_FILE=/secure/env-loopwire-release-private.pem
LOOPWIRE_RELEASE_PUBLIC_KEY_FILE=packaging/release-signing-public.pem
EOF
if LOOPWIRE_FAKE_DOCS_DIST="$fetch_docs_missing_dist" LOOPWIRE_FAKE_GH_ARTIFACT_MODE=missing-deployment \
  PATH="$fake_gh_dir:$PATH" \
  bash scripts/fetch-docs-deployment-proof.sh \
    --repo sandwichfarm/loopwire \
    --run-id 123456 \
    --git-head 0123456789abcdef0123456789abcdef01234567 \
    --docs-dist "$fetch_docs_missing_dist" \
    --manifest "$fetch_docs_missing_manifest" \
    --env-file "$fetch_docs_missing_env_file" \
    --manifest-artifact missing-docs-deployment >"$tmp_dir/fetch-docs-proof-missing-artifact.log" 2>&1; then
  echo "verify-scripts: docs deployment proof helper accepted a missing deployment artifact" >&2
  exit 1
fi
grep -F "missing: docs deployment manifest artifact: missing-docs-deployment" \
  "$tmp_dir/fetch-docs-proof-missing-artifact.log" >/dev/null || {
    echo "verify-scripts: docs deployment proof helper did not report the missing deployment artifact" >&2
    exit 1
  }
grep -F "found artifact(s):" "$tmp_dir/fetch-docs-proof-missing-artifact.log" >/dev/null || {
  echo "verify-scripts: docs deployment proof helper did not print artifact inventory" >&2
  exit 1
}
grep -F "loopwire-docs" "$tmp_dir/fetch-docs-proof-missing-artifact.log" >/dev/null || {
  echo "verify-scripts: docs deployment proof helper did not print the available docs artifact" >&2
  exit 1
}
grep -F "bash scripts/setup-github-secrets.sh --repo sandwichfarm/loopwire" \
  "$tmp_dir/fetch-docs-proof-missing-artifact.log" >/dev/null || {
    echo "verify-scripts: docs deployment proof helper did not print the Bunny secret recovery command" >&2
    exit 1
  }
grep -F -- "--env-file $fetch_docs_missing_env_file" "$tmp_dir/fetch-docs-proof-missing-artifact.log" >/dev/null || {
  echo "verify-scripts: docs deployment proof helper did not preserve the env-file recovery route" >&2
  exit 1
}
if grep -F "env-access-key-that-must-not-print" "$tmp_dir/fetch-docs-proof-missing-artifact.log" >/dev/null; then
  echo "verify-scripts: docs deployment proof helper leaked the env-file Bunny access key" >&2
  exit 1
fi
if [ -e "$fetch_docs_missing_dist/index.html" ] || [ -e "$fetch_docs_missing_manifest" ]; then
  echo "verify-scripts: docs deployment proof helper left partial proof files after a missing deployment artifact" >&2
  exit 1
fi
rm -rf "$fetch_docs_proof_root" "$fetch_docs_missing_root"
secret_list_release_key_only="$tmp_dir/secret-list-release-key-only.tsv"
secret_list_all_final="$tmp_dir/secret-list-all-final.tsv"
printf '%s\t%s\n' "LOOPWIRE_RELEASE_PRIVATE_KEY" "2026-07-04T00:00:00Z" >"$secret_list_release_key_only"
{
  printf '%s\t%s\n' "BUNNY_STORAGE_ZONE" "2026-07-04T00:00:00Z"
  printf '%s\t%s\n' "BUNNY_ACCESS_KEY" "2026-07-04T00:00:00Z"
  printf '%s\t%s\n' "BUNNY_PULL_ZONE_HOSTNAME" "2026-07-04T00:00:00Z"
  printf '%s\t%s\n' "LOOPWIRE_RELEASE_PRIVATE_KEY" "2026-07-04T00:00:00Z"
} >"$secret_list_all_final"
release_status_private_key="$tmp_dir/release-status-private.pem"
release_status_public_key="$tmp_dir/release-status-public.pem"
release_status_bad_public_key="$tmp_dir/release-status-bad-public.pem"
release_status_docs_dist="$tmp_dir/release-status-docs-dist"
release_status_docs_manifest="$tmp_dir/release-status-docs-manifest.json"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$release_status_private_key" >/dev/null 2>&1
openssl pkey -in "$release_status_private_key" -pubout -out "$release_status_public_key" >/dev/null 2>&1
printf '%s\n' "not a public key" >"$release_status_bad_public_key"
mkdir -p "$release_status_docs_dist"
printf '%s\n' "<!doctype html><title>Loopwire</title>" >"$release_status_docs_dist/index.html"
printf '%s\n' "#!/usr/bin/env bash" "echo install loopwire" >"$release_status_docs_dist/install.sh"
node - "$release_status_docs_dist" "$release_status_docs_manifest" <<'NODE'
const { createHash } = require("node:crypto");
const { readdirSync, readFileSync, writeFileSync } = require("node:fs");
const { join } = require("node:path");

const [distDir, manifestPath] = process.argv.slice(2);
const uploads = readdirSync(distDir)
  .sort()
  .map((relativePath) => {
    const bytes = readFileSync(join(distDir, relativePath));
    return {
      relativePath,
      remotePath: relativePath,
      checksumSha256: createHash("sha256").update(bytes).digest("hex").toUpperCase()
    };
  });

writeFileSync(manifestPath, `${JSON.stringify({
  schema: "loopwire.docs-deployment.v1",
  generatedAt: "2026-07-04T00:00:00.000Z",
  dryRun: false,
  distDir,
  storage: {
    zone: "loopwire-docs",
    endpoint: "https://storage.bunnycdn.com",
    remotePrefix: ""
  },
  source: {
    gitHead: "0123456789abcdef0123456789abcdef01234567"
  },
  requiredFiles: ["index.html", "install.sh"],
  fileCount: uploads.length,
  uploads
}, null, 2)}\n`);
NODE
release_status_bad_public_key_log="$tmp_dir/release-status-bad-public-key.log"
if bash scripts/audit-final-release-state.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --public-key "$release_status_bad_public_key" \
  --secret-list-file "$secret_list_all_final" \
  --skip-gh >"$release_status_bad_public_key_log" 2>&1; then
  echo "verify-scripts: release status accepted an invalid release signing public key" >&2
  exit 1
fi
grep -F "invalid: release signing public key: $release_status_bad_public_key" \
  "$release_status_bad_public_key_log" >/dev/null || {
    echo "verify-scripts: release status did not block an invalid release signing public key" >&2
    exit 1
  }
release_status_env_file="$tmp_dir/release-status-release-secrets.env"
cat >"$release_status_env_file" <<'EOF'
BUNNY_STORAGE_ZONE=loopwire-docs
BUNNY_ACCESS_KEY=env-access-key-that-must-not-print
BUNNY_PULL_ZONE_HOSTNAME=docs.env.example.test
LOOPWIRE_RELEASE_PRIVATE_KEY_FILE=/secure/env-loopwire-release-private.pem
LOOPWIRE_RELEASE_PUBLIC_KEY_FILE=packaging/release-signing-public.pem
EOF
release_status_missing_docs_manifest_log="$tmp_dir/release-status-missing-docs-manifest.log"
if bash scripts/audit-final-release-state.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --public-key "$release_status_public_key" \
  --env-file "$release_status_env_file" \
  --secret-list-file "$secret_list_all_final" \
  --docs-deployment-manifest "$tmp_dir/missing-docs-deployment-manifest.json" \
  --docs-dist "$release_status_docs_dist" \
  --skip-gh >"$release_status_missing_docs_manifest_log" 2>&1; then
  echo "verify-scripts: release status accepted a missing docs deployment manifest" >&2
  exit 1
fi
grep -F "missing: docs deployment manifest: $tmp_dir/missing-docs-deployment-manifest.json" \
  "$release_status_missing_docs_manifest_log" >/dev/null || {
    echo "verify-scripts: release status did not report the missing docs deployment manifest" >&2
    exit 1
  }
grep -F "pnpm release:fetch-docs-proof" "$release_status_missing_docs_manifest_log" |
  grep -F -- "--repo sandwichfarm/loopwire" |
  grep -F -- "--git-head 0123456789abcdef0123456789abcdef01234567" >/dev/null || {
    echo "verify-scripts: release status did not print the docs proof fetch command" >&2
    exit 1
  }
grep -F -- "--env-file $release_status_env_file" "$release_status_missing_docs_manifest_log" >/dev/null || {
  echo "verify-scripts: release status did not preserve the docs proof env-file recovery route" >&2
  exit 1
}
grep -F "pnpm vm:prepare-release-evidence" "$release_status_missing_docs_manifest_log" |
  grep -F -- "--env-file $release_status_env_file" |
  grep -F -- "--public-key $release_status_public_key" >/dev/null || {
    echo "verify-scripts: release status did not preserve the explicit public key override in the VM evidence env-file handoff" >&2
    exit 1
  }
if grep -F "env-access-key-that-must-not-print" "$release_status_missing_docs_manifest_log" >/dev/null; then
  echo "verify-scripts: release status leaked the env-file Bunny access key" >&2
  exit 1
fi
release_status_env_default_public_key_log="$tmp_dir/release-status-env-default-public-key.log"
if bash scripts/audit-final-release-state.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --env-file "$release_status_env_file" \
  --secret-list-file "$secret_list_all_final" \
  --docs-deployment-manifest "$tmp_dir/missing-docs-deployment-manifest.json" \
  --docs-dist "$release_status_docs_dist" \
  --skip-gh >"$release_status_env_default_public_key_log" 2>&1; then
  echo "verify-scripts: release status accepted a missing docs deployment manifest with env-file defaults" >&2
  exit 1
fi
grep -F "pnpm vm:prepare-release-evidence" "$release_status_env_default_public_key_log" |
  grep -F -- "--env-file $release_status_env_file" >/dev/null || {
    echo "verify-scripts: release status did not preserve the VM evidence env-file handoff without a public key override" >&2
    exit 1
  }
if grep -F "pnpm vm:prepare-release-evidence" "$release_status_env_default_public_key_log" |
  grep -F -- "--public-key packaging/release-signing-public.pem" >/dev/null; then
    echo "verify-scripts: release status expanded the default public key into the VM evidence env-file handoff" >&2
    exit 1
fi
if grep -F "env-access-key-that-must-not-print" "$release_status_env_default_public_key_log" >/dev/null; then
  echo "verify-scripts: release status env-file default handoff leaked the Bunny access key" >&2
  exit 1
fi
release_status_missing_docs_manifest_artifacts_log="$tmp_dir/release-status-missing-docs-manifest-artifacts.log"
release_status_docs_run_trace="$tmp_dir/release-status-docs-run-trace.tsv"
if LOOPWIRE_FAKE_GH_RELEASE_MODE=ok \
  LOOPWIRE_FAKE_GH_RUN_MODE=success \
  LOOPWIRE_FAKE_GH_ARTIFACT_MODE=missing-deployment \
  LOOPWIRE_FAKE_GH_TRACE="$release_status_docs_run_trace" \
  PATH="$fake_gh_dir:$PATH" \
  bash scripts/audit-final-release-state.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --git-head 0123456789abcdef0123456789abcdef01234567 \
    --public-key "$release_status_public_key" \
    --env-file "$release_status_env_file" \
    --secret-list-file "$secret_list_all_final" \
    --docs-deployment-manifest "$tmp_dir/missing-docs-deployment-manifest.json" \
    --docs-dist "$release_status_docs_dist" >"$release_status_missing_docs_manifest_artifacts_log" 2>&1; then
  echo "verify-scripts: release status accepted a missing docs deployment manifest with only docs artifact present" >&2
  exit 1
fi
docs_run_list_count="$(
  awk -F '\t' '$1 == "run list" && $2 == "deploy-docs.yml" { count++ } END { print count + 0 }' \
    "$release_status_docs_run_trace"
)"
if [ "$docs_run_list_count" != "1" ]; then
  echo "verify-scripts: release status re-queried Deploy Docs instead of reusing verified run id" >&2
  exit 1
fi
if awk -F '\t' '$1 == "run list" && $2 == "deploy-docs.yml" && $3 != "0123456789abcdef0123456789abcdef01234567" { bad++ } END { exit bad ? 0 : 1 }' \
  "$release_status_docs_run_trace"; then
  echo "verify-scripts: release status queried Deploy Docs without the expected commit filter" >&2
  exit 1
fi
grep -F "Deploy Docs artifacts visible:" "$release_status_missing_docs_manifest_artifacts_log" >/dev/null || {
  echo "verify-scripts: release status did not print docs artifact inventory" >&2
  exit 1
}
grep -F "loopwire-docs" "$release_status_missing_docs_manifest_artifacts_log" >/dev/null || {
  echo "verify-scripts: release status did not print the available docs artifact" >&2
  exit 1
}
grep -F "missing workflow artifact: loopwire-docs-deployment" \
  "$release_status_missing_docs_manifest_artifacts_log" >/dev/null || {
    echo "verify-scripts: release status did not report the missing deployment artifact" >&2
    exit 1
  }
grep -F "likely cause: Deploy Docs skipped Bunny.net deployment because required Bunny secrets are absent." \
  "$release_status_missing_docs_manifest_artifacts_log" >/dev/null || {
    echo "verify-scripts: release status did not explain the likely Bunny skip cause" >&2
    exit 1
  }
grep -F "pnpm release:fetch-docs-proof -- --repo sandwichfarm/loopwire --run-id 123456 --git-head 0123456789abcdef0123456789abcdef01234567" \
  "$release_status_missing_docs_manifest_artifacts_log" >/dev/null || {
    echo "verify-scripts: release status did not print the concrete docs proof fetch command" >&2
    exit 1
  }
grep -F -- "--env-file $release_status_env_file" "$release_status_missing_docs_manifest_artifacts_log" >/dev/null || {
  echo "verify-scripts: release status did not preserve the concrete docs proof env-file recovery route" >&2
  exit 1
}
if grep -F "env-access-key-that-must-not-print" "$release_status_missing_docs_manifest_artifacts_log" >/dev/null; then
  echo "verify-scripts: release status artifact hint leaked the env-file Bunny access key" >&2
  exit 1
fi
release_status_log="$tmp_dir/release-status-blocked.log"
if bash scripts/audit-final-release-state.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --public-key "$release_status_public_key" \
  --secret-list-file "$secret_list_release_key_only" \
  --docs-deployment-manifest "$release_status_docs_manifest" \
  --docs-dist "$release_status_docs_dist" \
  --skip-gh >"$release_status_log" 2>&1; then
  echo "verify-scripts: release status accepted missing final proof surfaces" >&2
  exit 1
fi
release_status_vm_start_port_log="$tmp_dir/release-status-vm-start-port.log"
if bash scripts/audit-final-release-state.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --public-key "$release_status_public_key" \
  --secret-list-file "$secret_list_release_key_only" \
  --docs-deployment-manifest "$release_status_docs_manifest" \
  --docs-dist "$release_status_docs_dist" \
  --vm-start-port 2700 \
  --skip-gh >"$release_status_vm_start_port_log" 2>&1; then
  echo "verify-scripts: release status accepted missing final proof surfaces with custom VM start port" >&2
  exit 1
fi
grep -F "Final release status for sandwichfarm/loopwire@v0.1.0" "$release_status_log" >/dev/null || {
  echo "verify-scripts: release status output is missing heading" >&2
  exit 1
}
grep -F "blocked: required GitHub secrets" "$release_status_log" >/dev/null || {
  echo "verify-scripts: release status did not report blocked secrets" >&2
  exit 1
}
grep -F "ok: release signing public key parses: $release_status_public_key" "$release_status_log" >/dev/null || {
  echo "verify-scripts: release status did not report a valid release signing public key" >&2
  exit 1
}
grep -F "Docs deployment manifest verified: $release_status_docs_manifest" "$release_status_log" >/dev/null || {
  echo "verify-scripts: release status did not verify the docs deployment manifest" >&2
  exit 1
}
grep -F "published-release-bound VM evidence" "$release_status_log" >/dev/null || {
  echo "verify-scripts: release status did not audit VM evidence" >&2
  exit 1
}
grep -F "blocked: published-release-bound VM evidence" "$release_status_log" >/dev/null || {
  echo "verify-scripts: release status did not block missing VM evidence" >&2
  exit 1
}
grep -F "collect-start-port=2600" "$release_status_log" >/dev/null || {
  echo "verify-scripts: release status did not use handoff-aligned VM start port" >&2
  exit 1
}
grep -F "collect-port=2600" "$release_status_log" >/dev/null || {
  echo "verify-scripts: release status did not report first VM collect port from default start port" >&2
  exit 1
}
grep -F "collect-port=2610" "$release_status_log" >/dev/null || {
  echo "verify-scripts: release status did not report second VM collect port from default start port" >&2
  exit 1
}
grep -F -- "pnpm vm:render-ssh-plan -- --all --start-port 2600" "$release_status_log" >/dev/null || {
  echo "verify-scripts: release status handoff plan did not keep VM start port aligned" >&2
  exit 1
}
grep -F "collect-start-port=2700" "$release_status_vm_start_port_log" >/dev/null || {
  echo "verify-scripts: release status did not honor custom VM start port" >&2
  exit 1
}
grep -F "collect-port=2700" "$release_status_vm_start_port_log" >/dev/null || {
  echo "verify-scripts: release status did not report first VM collect port from custom start port" >&2
  exit 1
}
grep -F -- "pnpm vm:render-ssh-plan -- --all --start-port 2700" "$release_status_vm_start_port_log" >/dev/null || {
  echo "verify-scripts: release status handoff plan did not honor custom VM start port" >&2
  exit 1
}
grep -F "local final release handoff plan" "$release_status_log" >/dev/null || {
  echo "verify-scripts: release status did not include the handoff planner" >&2
  exit 1
}
release_status_draft_release_log="$tmp_dir/release-status-draft-release.log"
if LOOPWIRE_FAKE_GH_RELEASE_MODE=draft \
  LOOPWIRE_FAKE_GH_RUN_MODE=success \
  PATH="$fake_gh_dir:$PATH" \
  bash scripts/audit-final-release-state.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --git-head 0123456789abcdef0123456789abcdef01234567 \
    --secret-list-file "$secret_list_all_final" >"$release_status_draft_release_log" 2>&1; then
  echo "verify-scripts: release status accepted a draft GitHub Release" >&2
  exit 1
fi
grep -F "GitHub Release object is still a draft release" "$release_status_draft_release_log" >/dev/null || {
  echo "verify-scripts: release status did not block a draft GitHub Release" >&2
  exit 1
}
grep -F -- "-f docs_deployment_run_id=123456" "$release_status_draft_release_log" >/dev/null || {
  echo "verify-scripts: release status handoff did not reuse the verified Deploy Docs run id" >&2
  exit 1
}
release_status_pinned_docs_run_log="$tmp_dir/release-status-pinned-docs-run.log"
if LOOPWIRE_FAKE_GH_RELEASE_MODE=draft \
  LOOPWIRE_FAKE_GH_RUN_MODE=success \
  PATH="$fake_gh_dir:$PATH" \
  bash scripts/audit-final-release-state.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --git-head 0123456789abcdef0123456789abcdef01234567 \
    --docs-deployment-run-id 654321 \
    --secret-list-file "$secret_list_all_final" >"$release_status_pinned_docs_run_log" 2>&1; then
  echo "verify-scripts: release status accepted a draft GitHub Release with pinned docs run" >&2
  exit 1
fi
grep -F "databaseId=654321" "$release_status_pinned_docs_run_log" >/dev/null || {
  echo "verify-scripts: release status did not verify the pinned Deploy Docs run id" >&2
  exit 1
}
grep -F "selected run verified: databaseId=654321" "$release_status_pinned_docs_run_log" >/dev/null || {
  echo "verify-scripts: release status did not label pinned Deploy Docs evidence as selected-run proof" >&2
  exit 1
}
if grep -F "latest run verified: databaseId=654321" "$release_status_pinned_docs_run_log" >/dev/null; then
  echo "verify-scripts: release status mislabeled pinned Deploy Docs evidence as latest-run proof" >&2
  exit 1
fi
grep -F -- "--run-id 654321" "$release_status_pinned_docs_run_log" >/dev/null || {
  echo "verify-scripts: release status docs proof command did not use the pinned run id" >&2
  exit 1
}
grep -F -- "-f docs_deployment_run_id=654321" "$release_status_pinned_docs_run_log" >/dev/null || {
  echo "verify-scripts: release status final proof handoff did not use the pinned run id" >&2
  exit 1
}
release_status_prerelease_log="$tmp_dir/release-status-prerelease.log"
if LOOPWIRE_FAKE_GH_RELEASE_MODE=prerelease \
  LOOPWIRE_FAKE_GH_RUN_MODE=success \
  PATH="$fake_gh_dir:$PATH" \
  bash scripts/audit-final-release-state.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --git-head 0123456789abcdef0123456789abcdef01234567 \
    --secret-list-file "$secret_list_all_final" >"$release_status_prerelease_log" 2>&1; then
  echo "verify-scripts: release status accepted a prerelease GitHub Release" >&2
  exit 1
fi
grep -F "GitHub Release object is still marked prerelease" "$release_status_prerelease_log" >/dev/null || {
  echo "verify-scripts: release status did not block a prerelease GitHub Release" >&2
  exit 1
}
release_status_wrong_tag_log="$tmp_dir/release-status-wrong-tag.log"
if LOOPWIRE_FAKE_GH_RELEASE_MODE=wrong-tag \
  LOOPWIRE_FAKE_GH_RUN_MODE=success \
  PATH="$fake_gh_dir:$PATH" \
  bash scripts/audit-final-release-state.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --git-head 0123456789abcdef0123456789abcdef01234567 \
    --secret-list-file "$secret_list_all_final" >"$release_status_wrong_tag_log" 2>&1; then
  echo "verify-scripts: release status accepted a mismatched release tag" >&2
  exit 1
fi
grep -F "GitHub Release object returned tag v0.2.0, not v0.1.0" \
  "$release_status_wrong_tag_log" >/dev/null || {
    echo "verify-scripts: release status did not block a mismatched release tag" >&2
    exit 1
  }
release_status_missing_asset_log="$tmp_dir/release-status-missing-asset.log"
if LOOPWIRE_FAKE_GH_RELEASE_MODE=missing-asset \
  LOOPWIRE_FAKE_GH_RUN_MODE=success \
  PATH="$fake_gh_dir:$PATH" \
  bash scripts/audit-final-release-state.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --git-head 0123456789abcdef0123456789abcdef01234567 \
    --secret-list-file "$secret_list_all_final" >"$release_status_missing_asset_log" 2>&1; then
  echo "verify-scripts: release status accepted missing release assets" >&2
  exit 1
fi
grep -F "GitHub Release object is missing required asset(s): loopwire-vm-evidence-v0.1.0.tar.gz" \
  "$release_status_missing_asset_log" >/dev/null || {
    echo "verify-scripts: release status did not block missing release assets" >&2
    exit 1
  }
release_tag_ref_wrong_log="$tmp_dir/release-tag-ref-wrong.log"
if LOOPWIRE_FAKE_GH_TAG_MODE=wrong-commit \
  PATH="$fake_gh_dir:$PATH" \
  bash scripts/verify-release-tag-ref.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --git-head 0123456789abcdef0123456789abcdef01234567 >"$release_tag_ref_wrong_log" 2>&1; then
  echo "verify-scripts: release tag ref verifier accepted the wrong commit" >&2
  exit 1
fi
grep -F "release tag ref resolves to ffffffffffffffffffffffffffffffffffffffff" \
  "$release_tag_ref_wrong_log" >/dev/null || {
    echo "verify-scripts: release tag ref verifier did not report the mismatched commit" >&2
    exit 1
  }
release_tag_ref_annotated_log="$tmp_dir/release-tag-ref-annotated.log"
LOOPWIRE_FAKE_GH_TAG_MODE=annotated \
  PATH="$fake_gh_dir:$PATH" \
  bash scripts/verify-release-tag-ref.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --git-head 0123456789abcdef0123456789abcdef01234567 >"$release_tag_ref_annotated_log"
grep -F "release tag ref verified: v0.1.0 -> 0123456789abcdef0123456789abcdef01234567" \
  "$release_tag_ref_annotated_log" >/dev/null || {
    echo "verify-scripts: release tag ref verifier did not accept the annotated tag target commit" >&2
    exit 1
  }
final_release_wrong_tag_ref_root="$tmp_dir/final-release-wrong-tag-ref"
mkdir -p "$final_release_wrong_tag_ref_root/release-evidence" "$final_release_wrong_tag_ref_root/vm-evidence"
printf '%s\n' '{"gitHead":"0123456789abcdef0123456789abcdef01234567"}' \
  >"$final_release_wrong_tag_ref_root/deployment-manifest.json"
final_release_wrong_tag_ref_log="$tmp_dir/final-release-wrong-tag-ref.log"
if LOOPWIRE_FAKE_GH_TAG_MODE=wrong-commit \
  PATH="$fake_gh_dir:$PATH" \
  bash scripts/verify-final-release-proof.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --public-key packaging/release-signing-public.pem \
    --git-head 0123456789abcdef0123456789abcdef01234567 \
    --release-evidence-dir "$final_release_wrong_tag_ref_root/release-evidence" \
    --docs-base-url https://docs.example.test \
    --docs-deployment-manifest "$final_release_wrong_tag_ref_root/deployment-manifest.json" \
    --vm-evidence-root "$final_release_wrong_tag_ref_root/vm-evidence" \
    --support-matrix apps/docs/docs/guide/support-matrix.md >"$final_release_wrong_tag_ref_log" 2>&1; then
  echo "verify-scripts: final release proof accepted a tag ref that resolves to the wrong commit" >&2
  exit 1
fi
grep -F "release tag ref resolves to ffffffffffffffffffffffffffffffffffffffff" \
  "$final_release_wrong_tag_ref_log" >/dev/null || {
    echo "verify-scripts: final release proof did not report the mismatched release tag ref" >&2
    exit 1
  }
release_status_wrong_tag_ref_log="$tmp_dir/release-status-wrong-tag-ref.log"
if LOOPWIRE_FAKE_GH_RELEASE_MODE=ok \
  LOOPWIRE_FAKE_GH_RUN_MODE=success \
  LOOPWIRE_FAKE_GH_TAG_MODE=wrong-commit \
  PATH="$fake_gh_dir:$PATH" \
  bash scripts/audit-final-release-state.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --git-head 0123456789abcdef0123456789abcdef01234567 \
    --secret-list-file "$secret_list_all_final" >"$release_status_wrong_tag_ref_log" 2>&1; then
  echo "verify-scripts: release status accepted a GitHub Release whose tag ref points at the wrong commit" >&2
  exit 1
fi
grep -F "blocked: release tag ref" "$release_status_wrong_tag_ref_log" >/dev/null || {
  echo "verify-scripts: release status did not block a mismatched release tag ref" >&2
  exit 1
}
grep -F "release tag ref resolves to ffffffffffffffffffffffffffffffffffffffff" \
  "$release_status_wrong_tag_ref_log" >/dev/null || {
    echo "verify-scripts: release status did not report the mismatched release tag commit" >&2
    exit 1
  }
release_status_annotated_tag_ref_log="$tmp_dir/release-status-annotated-tag-ref.log"
if LOOPWIRE_FAKE_GH_RELEASE_MODE=ok \
  LOOPWIRE_FAKE_GH_RUN_MODE=success \
  LOOPWIRE_FAKE_GH_TAG_MODE=annotated \
  PATH="$fake_gh_dir:$PATH" \
  bash scripts/audit-final-release-state.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --git-head 0123456789abcdef0123456789abcdef01234567 \
    --secret-list-file "$secret_list_all_final" >"$release_status_annotated_tag_ref_log" 2>&1; then
  echo "verify-scripts: release status accepted missing evidence archives after annotated tag ref smoke" >&2
  exit 1
fi
grep -F "ok: release tag ref" "$release_status_annotated_tag_ref_log" >/dev/null || {
  echo "verify-scripts: release status did not accept an annotated release tag targeting the expected commit" >&2
  exit 1
}
grep -F "release tag ref verified: v0.1.0 -> 0123456789abcdef0123456789abcdef01234567" \
  "$release_status_annotated_tag_ref_log" >/dev/null || {
    echo "verify-scripts: release status did not report the annotated tag target commit" >&2
    exit 1
  }
release_status_missing_release_archive_asset_log="$tmp_dir/release-status-missing-release-archive-asset.log"
if LOOPWIRE_FAKE_GH_RELEASE_MODE=ok \
  LOOPWIRE_FAKE_GH_RUN_MODE=success \
  PATH="$fake_gh_dir:$PATH" \
  bash scripts/audit-final-release-state.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --git-head 0123456789abcdef0123456789abcdef01234567 \
    --public-key "$release_status_public_key" \
    --secret-list-file "$secret_list_all_final" >"$release_status_missing_release_archive_asset_log" 2>&1; then
  echo "verify-scripts: release status accepted missing downloadable release evidence archive asset" >&2
  exit 1
fi
grep -F "blocked: published release evidence archive asset" \
  "$release_status_missing_release_archive_asset_log" >/dev/null || {
    echo "verify-scripts: release status did not block missing downloadable release evidence archive asset" >&2
    exit 1
  }
grep -F "fake release download dir is not configured" \
  "$release_status_missing_release_archive_asset_log" >/dev/null || {
    echo "verify-scripts: release status did not preserve release archive download failure details" >&2
    exit 1
  }
grep -F "ok: release tag ref" "$release_status_missing_release_archive_asset_log" >/dev/null || {
  echo "verify-scripts: release status did not verify the release tag ref before release archive download" >&2
  exit 1
}
release_status_release_only_dir="$tmp_dir/release-status-release-only-dir"
release_status_release_archive_root="$tmp_dir/release-status-release-archive-root"
mkdir -p "$release_status_release_only_dir" "$release_status_release_archive_root"
cp -R "$release_evidence_dir" "$release_status_release_archive_root/v0.1.0"
node - "$release_status_release_archive_root/v0.1.0/release-evidence.json" "$release_status_public_key" <<'NODE'
const fs = require("node:fs");

const [manifestPath, publicKey] = process.argv.slice(2);
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
const command = manifest.commands.find((entry) => entry.name === "published-release-smoke");

manifest.release.publicKey = publicKey;
if (!command) {
  throw new Error("missing published-release-smoke command");
}
command.command = [
  "bash scripts/verify-published-release.sh",
  "--repo sandwichfarm/loopwire",
  "--tag v0.1.0",
  `--public-key ${publicKey}`
].join(" ");

fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
NODE
tar -C "$release_status_release_archive_root" \
  -czf "$release_status_release_only_dir/loopwire-release-evidence-v0.1.0.tar.gz" \
  v0.1.0
(
  cd "$release_status_release_only_dir"
  sha256sum loopwire-release-evidence-v0.1.0.tar.gz >SHA256SUMS
  sha256sum --check SHA256SUMS >/dev/null
)
bash scripts/sign-release-artifacts.sh \
  --release-dir "$release_status_release_only_dir" \
  --private-key "$release_status_private_key" >/dev/null
release_status_missing_vm_archive_asset_log="$tmp_dir/release-status-missing-vm-archive-asset.log"
if LOOPWIRE_FAKE_GH_RELEASE_MODE=ok \
  LOOPWIRE_FAKE_GH_RUN_MODE=success \
  LOOPWIRE_FAKE_GH_RELEASE_DIR="$release_status_release_only_dir" \
  PATH="$fake_gh_dir:$PATH" \
  bash scripts/audit-final-release-state.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --git-head 0123456789abcdef0123456789abcdef01234567 \
    --public-key "$release_status_public_key" \
    --secret-list-file "$secret_list_all_final" >"$release_status_missing_vm_archive_asset_log" 2>&1; then
  echo "verify-scripts: release status accepted missing downloadable VM evidence archive asset" >&2
  exit 1
fi
grep -F "ok: published release evidence archive asset" \
  "$release_status_missing_vm_archive_asset_log" >/dev/null || {
    echo "verify-scripts: release status did not verify the signed release evidence archive asset first" >&2
    exit 1
  }
grep -F "Release evidence verified:" "$release_status_missing_vm_archive_asset_log" >/dev/null || {
  echo "verify-scripts: release status did not run the release evidence verifier" >&2
  exit 1
}
grep -F "blocked: published VM evidence archive asset" \
  "$release_status_missing_vm_archive_asset_log" >/dev/null || {
    echo "verify-scripts: release status did not block missing downloadable VM evidence archive asset" >&2
    exit 1
  }
grep -F "fake release asset not found: loopwire-vm-evidence-v0.1.0.tar.gz" \
  "$release_status_missing_vm_archive_asset_log" >/dev/null || {
    echo "verify-scripts: release status did not preserve VM archive download failure details" >&2
    exit 1
  }
release_status_empty_workflow_log="$tmp_dir/release-status-empty-workflow.log"
if LOOPWIRE_FAKE_GH_RELEASE_MODE=ok \
  LOOPWIRE_FAKE_GH_RUN_MODE=empty \
  PATH="$fake_gh_dir:$PATH" \
  bash scripts/audit-final-release-state.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --secret-list-file "$secret_list_all_final" >"$release_status_empty_workflow_log" 2>&1; then
  echo "verify-scripts: release status accepted an empty workflow run list" >&2
  exit 1
fi
grep -F "commit-scoped Deploy Docs workflow run did not return any workflow runs" \
  "$release_status_empty_workflow_log" >/dev/null || {
    echo "verify-scripts: release status did not block an empty workflow run list" >&2
    exit 1
  }
release_status_failed_workflow_log="$tmp_dir/release-status-failed-workflow.log"
if LOOPWIRE_FAKE_GH_RELEASE_MODE=ok \
  LOOPWIRE_FAKE_GH_RUN_MODE=failed \
  PATH="$fake_gh_dir:$PATH" \
  bash scripts/audit-final-release-state.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --secret-list-file "$secret_list_all_final" >"$release_status_failed_workflow_log" 2>&1; then
  echo "verify-scripts: release status accepted a failed workflow run" >&2
  exit 1
fi
grep -F "commit-scoped Deploy Docs workflow run commit-scoped completed run did not succeed: failure" \
  "$release_status_failed_workflow_log" >/dev/null || {
    echo "verify-scripts: release status did not block a failed workflow run" >&2
    exit 1
  }
release_status_failed_ci_log="$tmp_dir/release-status-failed-ci.log"
if LOOPWIRE_FAKE_GH_RELEASE_MODE=ok \
  LOOPWIRE_FAKE_GH_RUN_MODE=success \
  LOOPWIRE_FAKE_GH_CI_RUN_MODE=failed \
  PATH="$fake_gh_dir:$PATH" \
  bash scripts/audit-final-release-state.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --git-head 0123456789abcdef0123456789abcdef01234567 \
    --secret-list-file "$secret_list_all_final" >"$release_status_failed_ci_log" 2>&1; then
  echo "verify-scripts: release status accepted a failed CI workflow run" >&2
  exit 1
fi
grep -F "commit-scoped CI workflow run commit-scoped completed run did not succeed: failure" \
  "$release_status_failed_ci_log" >/dev/null || {
    echo "verify-scripts: release status did not block a failed CI workflow run" >&2
    exit 1
  }
release_status_stale_workflow_log="$tmp_dir/release-status-stale-workflow.log"
if LOOPWIRE_FAKE_GH_RELEASE_MODE=ok \
  LOOPWIRE_FAKE_GH_RUN_MODE=success \
  PATH="$fake_gh_dir:$PATH" \
  bash scripts/audit-final-release-state.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --git-head ffffffffffffffffffffffffffffffffffffffff \
    --secret-list-file "$secret_list_all_final" >"$release_status_stale_workflow_log" 2>&1; then
  echo "verify-scripts: release status accepted a workflow run from the wrong commit" >&2
  exit 1
fi
grep -F "commit-scoped Deploy Docs workflow run commit-scoped run is for 0123456789abcdef0123456789abcdef01234567" \
  "$release_status_stale_workflow_log" >/dev/null || {
    echo "verify-scripts: release status did not block stale workflow SHA evidence" >&2
    exit 1
  }
release_status_wrong_final_proof_title_log="$tmp_dir/release-status-wrong-final-proof-title.log"
if LOOPWIRE_FAKE_GH_RELEASE_MODE=ok \
  LOOPWIRE_FAKE_GH_RUN_MODE=success \
  LOOPWIRE_FAKE_GH_FINAL_PROOF_TITLE_MODE=wrong-tag \
  PATH="$fake_gh_dir:$PATH" \
  bash scripts/audit-final-release-state.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --git-head 0123456789abcdef0123456789abcdef01234567 \
    --secret-list-file "$secret_list_all_final" >"$release_status_wrong_final_proof_title_log" 2>&1; then
  echo "verify-scripts: release status accepted a final proof workflow run titled for the wrong tag" >&2
  exit 1
fi
grep -F "commit-scoped Final Release Proof workflow run commit-scoped run is titled Final Release Proof v0.2.0" \
  "$release_status_wrong_final_proof_title_log" >/dev/null || {
    echo "verify-scripts: release status did not block mismatched final proof run title" >&2
    exit 1
  }
release_status_matching_workflow_log="$tmp_dir/release-status-matching-workflow.log"
release_status_fake_release_dir="$tmp_dir/release-status-fake-release-dir"
release_status_fake_vm_archive_root="$tmp_dir/release-status-fake-vm-archive-root"
mkdir -p "$release_status_fake_release_dir" "$release_status_fake_vm_archive_root"
cp \
  "$release_status_release_only_dir/loopwire-release-evidence-v0.1.0.tar.gz" \
  "$release_status_fake_release_dir/loopwire-release-evidence-v0.1.0.tar.gz"
node - "$release_status_fake_vm_archive_root/manifest.json" <<'NODE'
const fs = require("node:fs");
const output = process.argv[2];
const targets = [
  "arch-hyprland-pipewire",
  "fedora-kde-pipewire",
  "fedora-kde-jack",
  "ubuntu-gnome-pipewire",
  "ubuntu-gnome-pipewire-aarch64",
  "debian-xfce-pulseaudio",
  "nixos-gnome-pipewire",
  "fedora-sway-pipewire",
  "opensuse-kde-pipewire"
];
const manifest = {
  kind: "loopwire.vm-evidence-archive",
  version: 1,
  tag: "v0.1.0",
  generatedAt: "2026-07-04T00:00:00.000Z",
  requirePublishedRelease: true,
  layout: "vm-evidence/<target>",
  targetCount: targets.length,
  targets
};
fs.writeFileSync(output, `${JSON.stringify(manifest, null, 2)}\n`);
NODE
tar -C "$release_status_fake_vm_archive_root" \
  -czf "$release_status_fake_release_dir/loopwire-vm-evidence-v0.1.0.tar.gz" \
  manifest.json
(
  cd "$release_status_fake_release_dir"
  sha256sum \
    loopwire-release-evidence-v0.1.0.tar.gz \
    loopwire-vm-evidence-v0.1.0.tar.gz >SHA256SUMS
  sha256sum --check SHA256SUMS >/dev/null
)
bash scripts/sign-release-artifacts.sh \
  --release-dir "$release_status_fake_release_dir" \
  --private-key "$release_status_private_key" >/dev/null
if LOOPWIRE_FAKE_GH_RELEASE_MODE=ok \
  LOOPWIRE_FAKE_GH_RUN_MODE=success \
  LOOPWIRE_FAKE_GH_RELEASE_DIR="$release_status_fake_release_dir" \
  PATH="$fake_gh_dir:$PATH" \
  bash scripts/audit-final-release-state.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --git-head 0123456789abcdef0123456789abcdef01234567 \
    --public-key "$release_status_public_key" \
    --secret-list-file "$secret_list_all_final" >"$release_status_matching_workflow_log" 2>&1; then
  echo "verify-scripts: release status unexpectedly passed without VM evidence" >&2
  exit 1
fi
grep -F "commit-scoped run verified: databaseId=123456 headSha=0123456789abcdef0123456789abcdef01234567" \
  "$release_status_matching_workflow_log" >/dev/null || {
    echo "verify-scripts: release status did not accept matching workflow SHA evidence" >&2
    exit 1
  }
grep -F "ok: published release evidence archive asset" "$release_status_matching_workflow_log" >/dev/null || {
  echo "verify-scripts: release status did not verify the signed release evidence archive asset" >&2
  exit 1
}
grep -F "Release evidence verified:" "$release_status_matching_workflow_log" >/dev/null || {
  echo "verify-scripts: release status did not verify the release evidence archive contents" >&2
  exit 1
}
grep -F "ok: published VM evidence archive asset" "$release_status_matching_workflow_log" >/dev/null || {
  echo "verify-scripts: release status did not verify the signed VM evidence archive asset" >&2
  exit 1
}
grep -F "VM evidence archive manifest verified: 9 target(s) for v0.1.0." \
  "$release_status_matching_workflow_log" >/dev/null || {
    echo "verify-scripts: release status did not verify the VM archive manifest" >&2
    exit 1
  }
grep -F "==> commit-scoped CI workflow run" "$release_status_matching_workflow_log" >/dev/null || {
  echo "verify-scripts: release status did not audit the commit-scoped CI workflow run" >&2
  exit 1
}
secret_artifact_missing_bunny_log="$tmp_dir/setup-github-secrets-artifact-missing-bunny.log"
if bash scripts/setup-github-secrets.sh \
  --repo sandwichfarm/loopwire \
  --check \
  --secret-list-file "$secret_list_release_key_only" >"$secret_artifact_missing_bunny_log" 2>&1; then
  echo "verify-scripts: GitHub secret artifact check accepted missing Bunny secrets" >&2
  exit 1
fi
grep -F "ok: GitHub secret present: LOOPWIRE_RELEASE_PRIVATE_KEY" "$secret_artifact_missing_bunny_log" >/dev/null || {
  echo "verify-scripts: GitHub secret artifact check did not report release key presence" >&2
  exit 1
}
grep -F "missing: GitHub secret: BUNNY_STORAGE_ZONE" "$secret_artifact_missing_bunny_log" >/dev/null || {
  echo "verify-scripts: GitHub secret artifact check did not report missing Bunny storage zone" >&2
  exit 1
}
if grep -F "next: set release signing secret from a local private key" "$secret_artifact_missing_bunny_log" >/dev/null; then
  echo "verify-scripts: GitHub secret artifact check printed release key guidance for Bunny-only gap" >&2
  exit 1
fi
if bash scripts/setup-github-secrets.sh \
  --repo sandwichfarm/loopwire \
  --secret-list-file "$secret_list_all_final" >/dev/null 2>&1; then
  echo "verify-scripts: GitHub secret helper accepted a secret-list artifact outside check mode" >&2
  exit 1
fi
github_secret_secret_list_dir="$tmp_dir/setup-github-secrets-secret-list-dir"
mkdir -p "$github_secret_secret_list_dir"
if bash scripts/setup-github-secrets.sh \
  --repo sandwichfarm/loopwire \
  --check \
  --secret-list-file "$github_secret_secret_list_dir" >/dev/null 2>&1; then
  echo "verify-scripts: GitHub secret helper accepted a directory secret-list artifact" >&2
  exit 1
fi
github_secret_env_template="$tmp_dir/setup-github-secrets-env-template"
bash scripts/setup-github-secrets.sh --print-env-template >"$github_secret_env_template"
cmp -s .env.example "$github_secret_env_template" || {
  echo "verify-scripts: GitHub secret helper env template drifted from .env.example" >&2
  exit 1
}
github_secret_written_env_template="$tmp_dir/setup-github-secrets-written.env"
github_secret_write_template_output="$(
  bash scripts/setup-github-secrets.sh --write-env-template "$github_secret_written_env_template"
)"
cmp -s .env.example "$github_secret_written_env_template" || {
  echo "verify-scripts: GitHub secret helper written env template drifted from .env.example" >&2
  exit 1
}
github_secret_written_env_template_mode="$(stat -c '%a' "$github_secret_written_env_template")"
[ "$github_secret_written_env_template_mode" = "600" ] || {
  echo "verify-scripts: GitHub secret helper wrote env template with mode $github_secret_written_env_template_mode" >&2
  exit 1
}
printf '%s\n' "$github_secret_write_template_output" | grep -F "File permissions set to 0600" >/dev/null || {
  echo "verify-scripts: GitHub secret helper did not report 0600 env-template permissions" >&2
  exit 1
}
github_secret_existing_env_template="$tmp_dir/setup-github-secrets-existing.env"
printf '%s\n' "existing" >"$github_secret_existing_env_template"
if bash scripts/setup-github-secrets.sh --write-env-template "$github_secret_existing_env_template" >/dev/null 2>&1; then
  echo "verify-scripts: GitHub secret helper overwrote an existing env template" >&2
  exit 1
fi
grep -Fx "existing" "$github_secret_existing_env_template" >/dev/null || {
  echo "verify-scripts: GitHub secret helper changed an existing env template while rejecting overwrite" >&2
  exit 1
}
github_secret_env_template_symlink="$tmp_dir/setup-github-secrets-template-link.env"
ln -s "$github_secret_written_env_template" "$github_secret_env_template_symlink"
if bash scripts/setup-github-secrets.sh --write-env-template "$github_secret_env_template_symlink" >/dev/null 2>&1; then
  echo "verify-scripts: GitHub secret helper wrote env template through a symlink" >&2
  exit 1
fi
if bash scripts/setup-github-secrets.sh \
  --write-env-template "$tmp_dir/setup-github-secrets-combined.env" \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: GitHub secret helper accepted env-template write with dry-run" >&2
  exit 1
fi
secret_check_ok="$(
  PATH="$fake_gh_dir:$PATH" \
    bash scripts/setup-github-secrets.sh --repo sandwichfarm/loopwire --check
)"
printf '%s\n' "$secret_check_ok" | grep -F "ok: GitHub secret present: LOOPWIRE_RELEASE_PRIVATE_KEY" >/dev/null || {
  echo "verify-scripts: GitHub secret check did not report release secret presence" >&2
  exit 1
}
printf '%s\n' "$secret_check_ok" | grep -F "ok: GitHub secret present: BUNNY_PULL_ZONE_HOSTNAME" >/dev/null || {
  echo "verify-scripts: GitHub secret check did not report pull-zone hostname presence" >&2
  exit 1
}
printf '%s\n' "$secret_check_ok" | grep -F "ok: optional GitHub secret present: BUNNY_STORAGE_ENDPOINT" >/dev/null || {
  echo "verify-scripts: GitHub secret check did not report optional endpoint presence" >&2
  exit 1
}
printf '%s\n' "$secret_check_ok" | grep -F "ok: optional GitHub secret present: BUNNY_REMOTE_PREFIX" >/dev/null || {
  echo "verify-scripts: GitHub secret check did not report optional remote-prefix presence" >&2
  exit 1
}
printf '%s\n' "$secret_check_ok" | grep -F "ok: docs deploy workflow can run post-upload live smoke" >/dev/null || {
  echo "verify-scripts: GitHub secret check did not report live-smoke readiness" >&2
  exit 1
}
secret_missing_required_log="$tmp_dir/setup-github-secrets-missing-required.log"
secret_deploy_missing_required_log="$tmp_dir/setup-github-secrets-deploy-missing-required.log"
if LOOPWIRE_FAKE_GH_SECRET_MODE=missing-required \
  PATH="$fake_gh_dir:$PATH" \
  bash scripts/setup-github-secrets.sh --repo sandwichfarm/loopwire --check >"$secret_missing_required_log" 2>&1; then
  echo "verify-scripts: GitHub secret check accepted missing Bunny secrets" >&2
  exit 1
fi
grep -F "missing: GitHub secret: BUNNY_STORAGE_ZONE" "$secret_missing_required_log" >/dev/null || {
  echo "verify-scripts: GitHub secret check did not report missing storage zone" >&2
  exit 1
}
grep -F "next: set Bunny.net deployment secrets without printing values" "$secret_missing_required_log" >/dev/null || {
  echo "verify-scripts: GitHub secret check did not print Bunny next step" >&2
  exit 1
}
grep -F -- "--env-file <secret-env-file>" "$secret_missing_required_log" >/dev/null || {
  echo "verify-scripts: GitHub secret check did not print env-file Bunny next step" >&2
  exit 1
}
grep -F -- "--write-env-template <secret-env-file>" "$secret_missing_required_log" >/dev/null || {
  echo "verify-scripts: GitHub secret check did not print env-template write step for Bunny secrets" >&2
  exit 1
}
if grep -F "next: set release signing secret from a local private key" "$secret_missing_required_log" >/dev/null; then
  echo "verify-scripts: GitHub secret check printed release key next step when only Bunny secrets were missing" >&2
  exit 1
fi
if LOOPWIRE_FAKE_GH_SECRET_MODE=missing-required \
  PATH="$fake_gh_dir:$PATH" \
  bash scripts/setup-github-secrets.sh --repo sandwichfarm/loopwire --check --scope deploy \
    >"$secret_deploy_missing_required_log" 2>&1; then
  echo "verify-scripts: GitHub deploy-scope secret check accepted missing Bunny secrets" >&2
  exit 1
fi
grep -F -- "--storage-zone <zone> --access-key <key>" "$secret_deploy_missing_required_log" >/dev/null || {
  echo "verify-scripts: GitHub deploy-scope check did not print deploy-only Bunny setup" >&2
  exit 1
}
grep -F -- "--env-file <secret-env-file>" "$secret_deploy_missing_required_log" >/dev/null || {
  echo "verify-scripts: GitHub deploy-scope check did not print env-file Bunny setup" >&2
  exit 1
}
grep -F -- "--write-env-template <secret-env-file>" "$secret_deploy_missing_required_log" >/dev/null || {
  echo "verify-scripts: GitHub deploy-scope check did not print env-template write setup" >&2
  exit 1
}
if grep -F -- "--pull-zone-hostname <host>" "$secret_deploy_missing_required_log" >/dev/null; then
  echo "verify-scripts: GitHub deploy-scope check required pull-zone hostname in Bunny setup" >&2
  exit 1
fi
secret_missing_live_docs_log="$tmp_dir/setup-github-secrets-missing-live-docs.log"
if LOOPWIRE_FAKE_GH_SECRET_MODE=missing-live-docs \
  PATH="$fake_gh_dir:$PATH" \
  bash scripts/setup-github-secrets.sh --repo sandwichfarm/loopwire --check >"$secret_missing_live_docs_log" 2>&1; then
  echo "verify-scripts: GitHub secret check accepted missing pull-zone hostname" >&2
  exit 1
fi
grep -F "missing: GitHub secret: BUNNY_PULL_ZONE_HOSTNAME" "$secret_missing_live_docs_log" >/dev/null || {
  echo "verify-scripts: GitHub secret check did not report missing pull-zone hostname" >&2
  exit 1
}
grep -F "next: set the Bunny.net pull-zone hostname needed for live docs smoke and final proof" \
  "$secret_missing_live_docs_log" >/dev/null || {
    echo "verify-scripts: GitHub secret check did not print pull-zone hostname next step" >&2
    exit 1
  }
grep -F -- "--env-file <secret-env-file>" "$secret_missing_live_docs_log" >/dev/null || {
  echo "verify-scripts: GitHub secret check did not print env-file pull-zone hostname next step" >&2
  exit 1
}
grep -F -- "--write-env-template <secret-env-file>" "$secret_missing_live_docs_log" >/dev/null || {
  echo "verify-scripts: GitHub secret check did not print env-template write step for pull-zone hostname" >&2
  exit 1
}
if grep -F "next: set Bunny.net deployment secrets without printing values" \
  "$secret_missing_live_docs_log" >/dev/null; then
  echo "verify-scripts: GitHub secret check printed storage setup when only pull-zone hostname was missing" >&2
  exit 1
fi
secret_deploy_scope_log="$tmp_dir/setup-github-secrets-deploy-scope.log"
LOOPWIRE_FAKE_GH_SECRET_MODE=missing-live-docs \
  PATH="$fake_gh_dir:$PATH" \
  bash scripts/setup-github-secrets.sh --repo sandwichfarm/loopwire --check --scope deploy \
    >"$secret_deploy_scope_log" 2>&1
grep -F "ok: Bunny.net docs deployment secrets are present" "$secret_deploy_scope_log" >/dev/null || {
  echo "verify-scripts: GitHub deploy-scope check did not accept configured storage secrets" >&2
  exit 1
}
grep -F "optional: GitHub secret not set: BUNNY_PULL_ZONE_HOSTNAME" "$secret_deploy_scope_log" >/dev/null || {
  echo "verify-scripts: GitHub deploy-scope check did not report pull-zone hostname as optional" >&2
  exit 1
}
if grep -F "LOOPWIRE_RELEASE_PRIVATE_KEY" "$secret_deploy_scope_log" >/dev/null; then
  echo "verify-scripts: GitHub deploy-scope check mentioned release signing secret" >&2
  exit 1
fi
secret_missing_release_log="$tmp_dir/setup-github-secrets-missing-release.log"
if LOOPWIRE_FAKE_GH_SECRET_MODE=missing-release-key \
  PATH="$fake_gh_dir:$PATH" \
  bash scripts/setup-github-secrets.sh --repo sandwichfarm/loopwire --check >"$secret_missing_release_log" 2>&1; then
  echo "verify-scripts: GitHub secret check accepted missing release signing secret" >&2
  exit 1
fi
grep -F "missing: GitHub secret: LOOPWIRE_RELEASE_PRIVATE_KEY" "$secret_missing_release_log" >/dev/null || {
  echo "verify-scripts: GitHub secret check did not report missing release signing secret" >&2
  exit 1
}
grep -F "next: set release signing secret from a local private key" "$secret_missing_release_log" >/dev/null || {
  echo "verify-scripts: GitHub secret check did not print release key next step" >&2
  exit 1
}
grep -F -- "--write-env-template <secret-env-file>" "$secret_missing_release_log" >/dev/null || {
  echo "verify-scripts: GitHub secret check did not print env-template write step for release key" >&2
  exit 1
}
if grep -F "next: set Bunny.net deployment secrets without printing values" \
  "$secret_missing_release_log" >/dev/null; then
  echo "verify-scripts: GitHub secret check printed Bunny next step when only release key was missing" >&2
  exit 1
fi
LOOPWIRE_FAKE_GH_SECRET_MODE=missing-release-key \
  PATH="$fake_gh_dir:$PATH" \
  bash scripts/setup-github-secrets.sh --repo sandwichfarm/loopwire --check --scope deploy >/dev/null
secret_check_failure_log="$tmp_dir/setup-github-secrets-check-failure.log"
if LOOPWIRE_FAKE_GH_SECRET_MODE=fail \
  PATH="$fake_gh_dir:$PATH" \
  bash scripts/setup-github-secrets.sh --repo sandwichfarm/loopwire --check >"$secret_check_failure_log" 2>&1; then
  echo "verify-scripts: GitHub secret check accepted a gh secret list failure" >&2
  exit 1
fi
grep -F "unable to read GitHub secret names for sandwichfarm/loopwire: api denied" \
  "$secret_check_failure_log" >/dev/null || {
    echo "verify-scripts: GitHub secret check did not preserve gh failure details" >&2
    exit 1
  }
fake_secret_set_dir="$tmp_dir/fake-gh-secret-set"
secret_set_output="$(
  LOOPWIRE_FAKE_GH_SET_DIR="$fake_secret_set_dir" \
    PATH="$fake_gh_dir:$PATH" \
    bash scripts/setup-github-secrets.sh \
      --repo sandwichfarm/loopwire \
      --storage-zone loopwire-docs \
      --access-key dry-run-access-key \
      --pull-zone-hostname docs.example.test \
      --storage-endpoint ny.storage.bunnycdn.com \
      --remote-prefix private-prefix-value \
      --release-private-key-file "$tmp_secret_file" \
      --release-public-key-file "$tmp_secret_public_key"
)"
printf '%s\n' "$secret_set_output" | grep -F "GitHub deployment/release secrets set for sandwichfarm/loopwire." \
  >/dev/null || {
    echo "verify-scripts: GitHub secret helper did not report successful fake writes" >&2
    exit 1
  }
cmp -s "$tmp_secret_file" "$fake_secret_set_dir/LOOPWIRE_RELEASE_PRIVATE_KEY" || {
  echo "verify-scripts: GitHub secret helper did not write the release private key through stdin" >&2
  exit 1
}
grep -F "loopwire-docs" "$fake_secret_set_dir/BUNNY_STORAGE_ZONE" >/dev/null || {
  echo "verify-scripts: GitHub secret helper did not write the storage zone through stdin" >&2
  exit 1
}
grep -F "dry-run-access-key" "$fake_secret_set_dir/BUNNY_ACCESS_KEY" >/dev/null || {
  echo "verify-scripts: GitHub secret helper did not write the access key through stdin" >&2
  exit 1
}
grep -F "docs.example.test" "$fake_secret_set_dir/BUNNY_PULL_ZONE_HOSTNAME" >/dev/null || {
  echo "verify-scripts: GitHub secret helper did not write the pull-zone hostname through stdin" >&2
  exit 1
}
grep -F "https://ny.storage.bunnycdn.com" "$fake_secret_set_dir/BUNNY_STORAGE_ENDPOINT" >/dev/null || {
  echo "verify-scripts: GitHub secret helper did not normalize and write the storage endpoint" >&2
  exit 1
}
grep -F "private-prefix-value" "$fake_secret_set_dir/BUNNY_REMOTE_PREFIX" >/dev/null || {
  echo "verify-scripts: GitHub secret helper did not write the remote prefix through stdin" >&2
  exit 1
}
fake_secret_env_set_dir="$tmp_dir/fake-gh-secret-env-set"
env_secret_set_output="$(
  LOOPWIRE_FAKE_GH_SET_DIR="$fake_secret_env_set_dir" \
    PATH="$fake_gh_dir:$PATH" \
    bash scripts/setup-github-secrets.sh \
      --repo sandwichfarm/loopwire \
      --env-file "$github_secret_env_file" \
      --access-key cli-access-key
)"
printf '%s\n' "$env_secret_set_output" | grep -F "GitHub deployment/release secrets set for sandwichfarm/loopwire." \
  >/dev/null || {
    echo "verify-scripts: GitHub secret helper did not report successful env-file fake writes" >&2
    exit 1
  }
grep -F "env-loopwire-docs" "$fake_secret_env_set_dir/BUNNY_STORAGE_ZONE" >/dev/null || {
  echo "verify-scripts: GitHub secret helper did not write env-file storage zone through stdin" >&2
  exit 1
}
grep -F "cli-access-key" "$fake_secret_env_set_dir/BUNNY_ACCESS_KEY" >/dev/null || {
  echo "verify-scripts: GitHub secret helper did not let CLI access key override env-file access key" >&2
  exit 1
}
if grep -F "env-access-key" "$fake_secret_env_set_dir/BUNNY_ACCESS_KEY" >/dev/null; then
  echo "verify-scripts: GitHub secret helper wrote env-file access key despite CLI override" >&2
  exit 1
fi
grep -F "docs.env.example.test" "$fake_secret_env_set_dir/BUNNY_PULL_ZONE_HOSTNAME" >/dev/null || {
  echo "verify-scripts: GitHub secret helper did not write env-file pull-zone hostname through stdin" >&2
  exit 1
}
cmp -s "$tmp_secret_file" "$fake_secret_env_set_dir/LOOPWIRE_RELEASE_PRIVATE_KEY" || {
  echo "verify-scripts: GitHub secret helper did not write env-file release private key through stdin" >&2
  exit 1
}
release_readiness_secret_failure_log="$tmp_dir/release-readiness-secret-failure.log"
if LOOPWIRE_FAKE_GH_SECRET_MODE=fail \
  PATH="$fake_gh_dir:$PATH" \
  bash scripts/verify-release-readiness.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --skip-tag \
    --skip-public-key \
    --skip-clean-git \
    --allow-candidate-notes >"$release_readiness_secret_failure_log" 2>&1; then
  echo "verify-scripts: release readiness accepted a gh secret list failure" >&2
  exit 1
fi
grep -F "error: unable to read GitHub secret names for sandwichfarm/loopwire: api denied" \
  "$release_readiness_secret_failure_log" >/dev/null || {
    echo "verify-scripts: release readiness did not preserve gh secret-list failure details" >&2
    exit 1
  }
release_readiness_secret_artifact_log="$tmp_dir/release-readiness-secret-artifact.log"
LOOPWIRE_FAKE_GH_SECRET_MODE=fail \
  PATH="$fake_gh_dir:$PATH" \
  bash scripts/verify-release-readiness.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --secret-list-file "$secret_list_all_final" \
    --skip-tag \
    --skip-public-key \
    --skip-clean-git \
    --allow-candidate-notes >"$release_readiness_secret_artifact_log" 2>&1
grep -F "ok: GitHub secret names loaded from artifact: $secret_list_all_final" \
  "$release_readiness_secret_artifact_log" >/dev/null || {
    echo "verify-scripts: release readiness did not use the secret-list artifact" >&2
    exit 1
  }
grep -F "Release readiness checks passed for sandwichfarm/loopwire@v0.1.0." \
  "$release_readiness_secret_artifact_log" >/dev/null || {
    echo "verify-scripts: release readiness artifact check did not pass" >&2
    exit 1
  }
release_readiness_next_steps_log="$tmp_dir/release-readiness-next-steps.log"
if LOOPWIRE_FAKE_GH_SECRET_MODE=missing-required \
  PATH="$fake_gh_dir:$PATH" \
  bash scripts/verify-release-readiness.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --skip-public-key \
    --skip-clean-git >"$release_readiness_next_steps_log" 2>&1; then
  echo "verify-scripts: release readiness accepted missing Bunny secrets and tag" >&2
  exit 1
fi
grep -F "next: set Bunny.net deployment and live-docs secrets without printing values" \
  "$release_readiness_next_steps_log" >/dev/null || {
    echo "verify-scripts: release readiness did not print Bunny next step" >&2
    exit 1
  }
grep -F -- "--pull-zone-hostname <host>" "$release_readiness_next_steps_log" >/dev/null || {
  echo "verify-scripts: release readiness Bunny next step is missing pull-zone hostname" >&2
  exit 1
}
grep -F -- "--write-env-template <secret-env-file>" "$release_readiness_next_steps_log" >/dev/null || {
  echo "verify-scripts: release readiness Bunny next step is missing env-template write command" >&2
  exit 1
}
grep -F -- "--env-file <secret-env-file>" "$release_readiness_next_steps_log" >/dev/null || {
  echo "verify-scripts: release readiness Bunny next step is missing env-file load command" >&2
  exit 1
}
grep -F "next: after required secrets are configured and readiness passes, create and push the release tag" \
  "$release_readiness_next_steps_log" >/dev/null || {
    echo "verify-scripts: release readiness did not print release tag next step" >&2
    exit 1
  }
grep -F "git tag -a v0.1.0 -m \"Loopwire v0.1.0\"" "$release_readiness_next_steps_log" >/dev/null || {
  echo "verify-scripts: release readiness tag next step is missing tag command" >&2
  exit 1
}
release_readiness_live_docs_log="$tmp_dir/release-readiness-live-docs.log"
if LOOPWIRE_FAKE_GH_SECRET_MODE=missing-live-docs \
  PATH="$fake_gh_dir:$PATH" \
  bash scripts/verify-release-readiness.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --skip-tag \
    --skip-public-key \
    --skip-clean-git >"$release_readiness_live_docs_log" 2>&1; then
  echo "verify-scripts: release readiness accepted missing pull-zone hostname" >&2
  exit 1
fi
grep -F "missing: GitHub secret: BUNNY_PULL_ZONE_HOSTNAME" "$release_readiness_live_docs_log" >/dev/null || {
  echo "verify-scripts: release readiness did not report missing pull-zone hostname" >&2
  exit 1
}
grep -F "next: set the Bunny.net pull-zone hostname needed for live docs smoke and final proof" \
  "$release_readiness_live_docs_log" >/dev/null || {
    echo "verify-scripts: release readiness did not print pull-zone hostname next step" >&2
    exit 1
  }
grep -F -- "--write-env-template <secret-env-file>" "$release_readiness_live_docs_log" >/dev/null || {
  echo "verify-scripts: release readiness live-docs next step is missing env-template write command" >&2
  exit 1
}
grep -F -- "--env-file <secret-env-file>" "$release_readiness_live_docs_log" >/dev/null || {
  echo "verify-scripts: release readiness live-docs next step is missing env-file load command" >&2
  exit 1
}

refresh_published_release_manifest() {
  local release_dir="$1"
  local private_key_file="$2"

  (
    cd "$release_dir"
    find . -maxdepth 1 -type f ! -name SHA256SUMS ! -name SHA256SUMS.sig -printf '%f\n' \
      | sort \
      | xargs sha256sum >SHA256SUMS
    sha256sum --check SHA256SUMS >/dev/null
  )
  bash scripts/sign-release-artifacts.sh --release-dir "$release_dir" --private-key "$private_key_file" >/dev/null
}

bind_release_evidence_public_key() {
  local evidence_dir="$1"
  local expected_public_key="$2"

  node - "$evidence_dir/release-evidence.json" "$expected_public_key" <<'NODE'
const fs = require("node:fs");

const [manifestPath, expectedPublicKey] = process.argv.slice(2);
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
const command = manifest.commands.find((entry) => entry.name === "published-release-smoke");

manifest.release.publicKey = expectedPublicKey;
if (!command) {
  throw new Error("missing published-release-smoke command");
}

command.command = [
  "bash scripts/verify-published-release.sh",
  "--repo sandwichfarm/loopwire",
  "--tag v0.1.0",
  `--public-key ${expectedPublicKey}`
].join(" ");

fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
NODE
}

private_key_dir="$(mktemp -d /tmp/loopwire-release-key.XXXXXX)"
trap 'rm -rf "$tmp_dir" "$private_key_dir"' EXIT
private_key_file="$private_key_dir/loopwire-release-private.pem"
public_key_file="$tmp_dir/release-signing-public.pem"
bash scripts/prepare-release-signing-key.sh \
  --private-key-out "$private_key_file" \
  --public-key-out "$public_key_file" >/dev/null
[ -s "$private_key_file" ] || {
  echo "verify-scripts: release private key was not generated" >&2
  exit 1
}
[ -s "$public_key_file" ] || {
  echo "verify-scripts: release public key was not generated" >&2
  exit 1
}
openssl pkey -in "$private_key_file" -noout >/dev/null
openssl pkey -pubin -in "$public_key_file" -noout >/dev/null
if ! bash scripts/verify-release-readiness.sh -- \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --public-key "$public_key_file" \
  --skip-gh \
  --skip-tag \
  --skip-clean-git >/dev/null 2>&1; then
  echo "verify-scripts: release readiness rejected publishable v0.1.0 release notes" >&2
  exit 1
fi
if bash scripts/verify-release-readiness.sh -- \
  --repo https://github.com/sandwichfarm/loopwire \
  --tag v0.1.0 \
  --public-key "$public_key_file" \
  --skip-gh \
  --skip-tag \
  --skip-clean-git \
  --allow-candidate-notes >/dev/null 2>&1; then
  echo "verify-scripts: release readiness accepted a URL-like repository" >&2
  exit 1
fi
if bash scripts/verify-release-readiness.sh -- \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0/preview \
  --public-key "$public_key_file" \
  --skip-gh \
  --skip-tag \
  --skip-clean-git \
  --allow-candidate-notes >/dev/null 2>&1; then
  echo "verify-scripts: release readiness accepted a path-like release tag" >&2
  exit 1
fi
bad_readiness_public_key="$tmp_dir/release-readiness-public-key-link.pem"
ln -s "$public_key_file" "$bad_readiness_public_key"
release_readiness_public_key_log="$tmp_dir/release-readiness-public-key-path.log"
if bash scripts/verify-release-readiness.sh -- \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --public-key "$bad_readiness_public_key" \
  --skip-gh \
  --skip-tag \
  --skip-clean-git \
  --allow-candidate-notes >"$release_readiness_public_key_log" 2>&1; then
  echo "verify-scripts: release readiness accepted a symlinked public key" >&2
  exit 1
fi
grep -F "verify-release-readiness: release public key must not be a symlink" \
  "$release_readiness_public_key_log" >/dev/null || {
    echo "verify-scripts: release readiness did not reject symlinked public key" >&2
    exit 1
  }
bad_readiness_secret_list="$tmp_dir/release-readiness-secret-list-dir"
mkdir -p "$bad_readiness_secret_list"
release_readiness_secret_list_log="$tmp_dir/release-readiness-secret-list-path.log"
if bash scripts/verify-release-readiness.sh -- \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --secret-list-file "$bad_readiness_secret_list" \
  --skip-tag \
  --skip-public-key \
  --skip-clean-git \
  --allow-candidate-notes >"$release_readiness_secret_list_log" 2>&1; then
  echo "verify-scripts: release readiness accepted a directory secret-list file" >&2
  exit 1
fi
grep -F "verify-release-readiness: secret-list file must be a file when it exists" \
  "$release_readiness_secret_list_log" >/dev/null || {
    echo "verify-scripts: release readiness did not reject directory secret-list file" >&2
    exit 1
  }
bash scripts/verify-release-readiness.sh -- \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --public-key "$public_key_file" \
  --skip-gh \
  --skip-tag \
  --skip-clean-git >"$tmp_dir/release-readiness-offline.log"
if grep -F "allowed: release notes still carry candidate wording" \
  "$tmp_dir/release-readiness-offline.log" >/dev/null; then
  echo "verify-scripts: release readiness offline proof still allowed candidate notes" >&2
  exit 1
fi
grep -F "ok: public docs installer matches canonical installer" "$tmp_dir/release-readiness-offline.log" >/dev/null || {
    echo "verify-scripts: release readiness did not verify public installer sync" >&2
    exit 1
  }
grep -F "ok: docs deployment manifest verifier parses" "$tmp_dir/release-readiness-offline.log" >/dev/null || {
  echo "verify-scripts: release readiness did not verify docs deployment verifier syntax" >&2
  exit 1
}
grep -F "ok: package script verify:docs-deployment is wired" "$tmp_dir/release-readiness-offline.log" >/dev/null || {
  echo "verify-scripts: release readiness did not verify docs deployment package script" >&2
  exit 1
}
grep -F "ok: final proof scripts parse" "$tmp_dir/release-readiness-offline.log" >/dev/null || {
  echo "verify-scripts: release readiness did not verify final proof script syntax" >&2
  exit 1
}
grep -F "ok: release tag-ref verifier: scripts/verify-release-tag-ref.sh" \
  "$tmp_dir/release-readiness-offline.log" >/dev/null || {
  echo "verify-scripts: release readiness did not require the release tag-ref verifier" >&2
  exit 1
}
grep -F "ok: VM evidence packager supports published-release strictness" \
  "$tmp_dir/release-readiness-offline.log" >/dev/null || {
    echo "verify-scripts: release readiness did not verify VM evidence packager strictness" >&2
    exit 1
  }
grep -F "ok: package script verify:final-release is wired" "$tmp_dir/release-readiness-offline.log" >/dev/null || {
  echo "verify-scripts: release readiness did not verify final release package script" >&2
  exit 1
}
grep -F "ok: package script vm:package-evidence is wired" "$tmp_dir/release-readiness-offline.log" >/dev/null || {
  echo "verify-scripts: release readiness did not verify VM evidence package script" >&2
  exit 1
}
grep -F "ok: package script vm:prepare-release-evidence is wired" \
  "$tmp_dir/release-readiness-offline.log" >/dev/null || {
    echo "verify-scripts: release readiness did not verify VM signed-release helper package script" >&2
    exit 1
  }
grep -F "ok: docs deployment workflow verifies manifest before artifact upload" \
  "$tmp_dir/release-readiness-offline.log" >/dev/null || {
    echo "verify-scripts: release readiness did not verify docs deployment workflow wiring" >&2
    exit 1
  }
grep -F "ok: final release proof workflow verifies release tag refs, docs deployment, and VM evidence archives" \
  "$tmp_dir/release-readiness-offline.log" >/dev/null || {
    echo "verify-scripts: release readiness did not verify final release proof workflow wiring" >&2
    exit 1
  }
grep -F "ok: final release proof workflow installs Nix for package proof" \
  "$tmp_dir/release-readiness-offline.log" >/dev/null || {
    echo "verify-scripts: release readiness did not verify final release Nix setup" >&2
    exit 1
  }
bad_public_installer="$tmp_dir/bad-public-install.sh"
printf '%s\n' "#!/usr/bin/env bash" "echo stale" >"$bad_public_installer"
if LOOPWIRE_PUBLIC_INSTALLER="$bad_public_installer" \
  bash scripts/verify-release-readiness.sh -- \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --skip-gh \
    --skip-tag \
    --skip-public-key \
    --skip-clean-git \
    --allow-candidate-notes >/dev/null 2>&1; then
  echo "verify-scripts: release readiness accepted a stale public installer" >&2
  exit 1
fi
release_tag_repo="$tmp_dir/release-tag-readiness"
mkdir -p "$release_tag_repo/scripts" \
  "$release_tag_repo/.github/workflows" \
  "$release_tag_repo/apps/docs/docs/public" \
  "$release_tag_repo/apps/docs/docs/release-notes"
cp scripts/verify-release-readiness.sh "$release_tag_repo/scripts/verify-release-readiness.sh"
cp scripts/verify-docs-deployment-manifest.mjs "$release_tag_repo/scripts/verify-docs-deployment-manifest.mjs"
cp scripts/verify-vm-evidence-archive-manifest.mjs "$release_tag_repo/scripts/verify-vm-evidence-archive-manifest.mjs"
cp scripts/verify-final-release-proof.sh "$release_tag_repo/scripts/verify-final-release-proof.sh"
cp scripts/verify-release-tag-ref.sh "$release_tag_repo/scripts/verify-release-tag-ref.sh"
cp scripts/validate-release-asset-name.sh "$release_tag_repo/scripts/validate-release-asset-name.sh"
cp scripts/verify-release-asset-checksum.sh "$release_tag_repo/scripts/verify-release-asset-checksum.sh"
cp scripts/verify-nix-release-package.sh "$release_tag_repo/scripts/verify-nix-release-package.sh"
cp scripts/extract-safe-tar.sh "$release_tag_repo/scripts/extract-safe-tar.sh"
cp scripts/package-vm-evidence.sh "$release_tag_repo/scripts/package-vm-evidence.sh"
cp scripts/prepare-vm-evidence-release-asset.sh "$release_tag_repo/scripts/prepare-vm-evidence-release-asset.sh"
cp scripts/install.sh "$release_tag_repo/scripts/install.sh"
cp scripts/install.sh "$release_tag_repo/apps/docs/docs/public/install.sh"
cp package.json "$release_tag_repo/package.json"
cp .github/workflows/deploy-docs.yml "$release_tag_repo/.github/workflows/deploy-docs.yml"
cp .github/workflows/final-release-proof.yml "$release_tag_repo/.github/workflows/final-release-proof.yml"
printf '%s\n' "# v0.1.0" "" "Release notes for tag readiness smoke." \
  >"$release_tag_repo/apps/docs/docs/release-notes/0.1.0.md"
(
  cd "$release_tag_repo"
  git init -q
  git config user.email "loopwire@example.invalid"
  git config user.name "Loopwire Test"
  git add .
  git commit -qm "initial release state"
  git tag v0.1.0
  bash scripts/verify-release-readiness.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --skip-gh \
    --skip-public-key \
    | grep -F "ok: local tag points at current HEAD: v0.1.0" >/dev/null
  printf '%s\n' "dirty working tree marker" >>apps/docs/docs/release-notes/0.1.0.md
  if bash scripts/verify-release-readiness.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --skip-gh \
    --skip-public-key >/dev/null 2>&1; then
    echo "verify-scripts: release readiness accepted a dirty checkout" >&2
    exit 1
  fi
  bash scripts/verify-release-readiness.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --skip-gh \
    --skip-public-key \
    --skip-clean-git \
    | grep -F "skipped: clean git status check" >/dev/null
  git checkout -- apps/docs/docs/release-notes/0.1.0.md
  printf '%s\n' "stale tag marker" >>README.md
  git add README.md
  git commit -qm "advance head after tag"
  if bash scripts/verify-release-readiness.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --skip-gh \
    --skip-public-key >/dev/null 2>&1; then
    echo "verify-scripts: release readiness accepted a tag that does not point at HEAD" >&2
    exit 1
  fi
)
published_binary="$tmp_dir/published-loopwire"
published_release_dir="$tmp_dir/published-release"
published_prefix="$tmp_dir/published-prefix"
case "$(uname -m)" in
  x86_64 | amd64)
    published_current_arch="x86_64"
    published_secondary_arch="aarch64"
    ;;
  aarch64 | arm64)
    published_current_arch="aarch64"
    published_secondary_arch="x86_64"
    ;;
  *)
    echo "verify-scripts: unsupported architecture for published release smoke: $(uname -m)" >&2
    exit 1
    ;;
esac
cat >"$published_binary" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "loopwire published verifier smoke"
EOF
chmod 0755 "$published_binary"
bash scripts/package-release.sh \
  --binary "$published_binary" \
  --version "0.1.0-smoke" \
  --arch "$published_current_arch" \
  --output-dir "$published_release_dir" >/dev/null
bash scripts/package-release.sh \
  --binary "$published_binary" \
  --version "0.1.0-smoke" \
  --arch "$published_secondary_arch" \
  --output-dir "$published_release_dir" >/dev/null
bash scripts/sign-release-artifacts.sh --release-dir "$published_release_dir" --private-key "$private_key_file" >/dev/null
bash scripts/verify-release-asset-checksum.sh \
  --release-dir "$published_release_dir" \
  --asset "loopwire-linux-${published_current_arch}.tar.gz" \
  --public-key "$public_key_file" \
  --label "published release smoke asset" >/dev/null
missing_checksum_release_dir="$tmp_dir/missing-checksum-release"
cp -R "$published_release_dir" "$missing_checksum_release_dir"
grep -Fv "loopwire-linux-${published_current_arch}.tar.gz" \
  "$published_release_dir/SHA256SUMS" >"$missing_checksum_release_dir/SHA256SUMS"
bash scripts/sign-release-artifacts.sh --release-dir "$missing_checksum_release_dir" --private-key "$private_key_file" \
  >/dev/null
if bash scripts/verify-release-asset-checksum.sh \
  --release-dir "$missing_checksum_release_dir" \
  --asset "loopwire-linux-${published_current_arch}.tar.gz" \
  --public-key "$public_key_file" >/dev/null 2>&1; then
  echo "verify-scripts: release asset checksum verifier accepted a missing checksum entry" >&2
  exit 1
fi
duplicate_checksum_release_dir="$tmp_dir/duplicate-checksum-release"
cp -R "$published_release_dir" "$duplicate_checksum_release_dir"
grep -F "loopwire-linux-${published_current_arch}.tar.gz" "$published_release_dir/SHA256SUMS" \
  >>"$duplicate_checksum_release_dir/SHA256SUMS"
bash scripts/sign-release-artifacts.sh \
  --release-dir "$duplicate_checksum_release_dir" \
  --private-key "$private_key_file" >/dev/null
if bash scripts/verify-release-asset-checksum.sh \
  --release-dir "$duplicate_checksum_release_dir" \
  --asset "loopwire-linux-${published_current_arch}.tar.gz" \
  --public-key "$public_key_file" >/dev/null 2>&1; then
  echo "verify-scripts: release asset checksum verifier accepted duplicate checksum entries" >&2
  exit 1
fi
tampered_checksum_release_dir="$tmp_dir/tampered-checksum-release"
cp -R "$published_release_dir" "$tampered_checksum_release_dir"
printf '%s\n' "tamper" >>"$tampered_checksum_release_dir/loopwire-linux-${published_current_arch}.tar.gz"
if bash scripts/verify-release-asset-checksum.sh \
  --release-dir "$tampered_checksum_release_dir" \
  --asset "loopwire-linux-${published_current_arch}.tar.gz" \
  --public-key "$public_key_file" >/dev/null 2>&1; then
  echo "verify-scripts: release asset checksum verifier accepted a tampered asset" >&2
  exit 1
fi
bash scripts/verify-published-release.sh \
  --release-dir "$published_release_dir" \
  --public-key "$public_key_file" \
  --prefix "$published_prefix" >/dev/null
if bash scripts/verify-published-release.sh \
  --release-dir "$published_release_dir" \
  --public-key "$public_key_file" \
  --require-github-release-source >/dev/null 2>&1; then
  echo "verify-scripts: published release verifier accepted local release-dir with GitHub-source strictness" >&2
  exit 1
fi
if bash scripts/verify-published-release.sh \
  --repo sandwichfarm/loopwire/releases \
  --tag v0.1.0 \
  --public-key "$public_key_file" >/dev/null 2>&1; then
  echo "verify-scripts: published release verifier accepted a path-like repository" >&2
  exit 1
fi
if [ "$("$published_prefix/loopwire")" != "loopwire published verifier smoke" ]; then
  echo "verify-scripts: published release verifier did not install the expected binary" >&2
  exit 1
fi
if bash scripts/verify-published-release.sh \
  --release-dir "$published_release_dir" \
  --public-key "$public_key_file" \
  --tag v0.1.0 \
  --require-release-evidence >/dev/null 2>&1; then
  echo "verify-scripts: published release verifier accepted missing release evidence asset" >&2
  exit 1
fi
release_evidence_archive_src="$tmp_dir/release-evidence-archive-src"
mkdir -p "$release_evidence_archive_src"
cp -R "$release_evidence_dir" "$release_evidence_archive_src/v0.1.0"
bind_release_evidence_public_key "$release_evidence_archive_src/v0.1.0" "$public_key_file"
tar -C "$release_evidence_archive_src" \
  -czf "$published_release_dir/loopwire-release-evidence-v0.1.0.tar.gz" \
  v0.1.0
if bash scripts/verify-published-release.sh \
  --release-dir "$published_release_dir" \
  --public-key "$public_key_file" \
  --tag v0.1.0 \
  --require-release-evidence >/dev/null 2>&1; then
  echo "verify-scripts: published release verifier accepted evidence missing from SHA256SUMS" >&2
  exit 1
fi
refresh_published_release_manifest "$published_release_dir" "$private_key_file"
bash scripts/verify-published-release.sh \
  --release-dir "$published_release_dir" \
  --public-key "$public_key_file" \
  --tag v0.1.0 \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --require-release-evidence >/dev/null
if bash scripts/verify-published-release.sh \
  --release-dir "$published_release_dir" \
  --public-key "$public_key_file" \
  --tag v0.1.0 \
  --git-head ffffffffffffffffffffffffffffffffffffffff \
  --require-release-evidence >/dev/null 2>&1; then
  echo "verify-scripts: published release verifier accepted release evidence from the wrong git head" >&2
  exit 1
fi
bash scripts/verify-published-release.sh \
  --release-dir "$published_release_dir" \
  --public-key "$public_key_file" \
  --require-release-evidence >/dev/null
wrong_tag_evidence_release_dir="$tmp_dir/wrong-tag-evidence-published-release"
wrong_tag_evidence_archive_src="$tmp_dir/wrong-tag-evidence-archive-src"
cp -R "$published_release_dir" "$wrong_tag_evidence_release_dir"
mkdir -p "$wrong_tag_evidence_archive_src"
cp -R "$release_evidence_dir" "$wrong_tag_evidence_archive_src/v0.1.0"
bind_release_evidence_public_key "$wrong_tag_evidence_archive_src/v0.1.0" "$public_key_file"
node -e '
const fs = require("node:fs");
const path = process.argv[1];
const manifest = JSON.parse(fs.readFileSync(path, "utf8"));
manifest.release.tag = "v9.9.9";
fs.writeFileSync(path, `${JSON.stringify(manifest, null, 2)}\n`);
' "$wrong_tag_evidence_archive_src/v0.1.0/release-evidence.json"
tar -C "$wrong_tag_evidence_archive_src" \
  -czf "$wrong_tag_evidence_release_dir/loopwire-release-evidence-v0.1.0.tar.gz" \
  v0.1.0
refresh_published_release_manifest "$wrong_tag_evidence_release_dir" "$private_key_file"
if bash scripts/verify-published-release.sh \
  --release-dir "$wrong_tag_evidence_release_dir" \
  --public-key "$public_key_file" \
  --tag v0.1.0 \
  --require-release-evidence >/dev/null 2>&1; then
  echo "verify-scripts: published release verifier accepted a mismatched evidence tag" >&2
  exit 1
fi
archive_name_mismatch_release_dir="$tmp_dir/archive-name-mismatch-published-release"
cp -R "$published_release_dir" "$archive_name_mismatch_release_dir"
rm -f "$archive_name_mismatch_release_dir/loopwire-release-evidence-v0.1.0.tar.gz"
tar -C "$release_evidence_archive_src" \
  -czf "$archive_name_mismatch_release_dir/loopwire-release-evidence-v9.9.9.tar.gz" \
  v0.1.0
refresh_published_release_manifest "$archive_name_mismatch_release_dir" "$private_key_file"
if bash scripts/verify-published-release.sh \
  --release-dir "$archive_name_mismatch_release_dir" \
  --public-key "$public_key_file" \
  --require-release-evidence >/dev/null 2>&1; then
  echo "verify-scripts: published release verifier accepted an evidence archive name/manifest tag mismatch" >&2
  exit 1
fi
unsafe_evidence_release_dir="$tmp_dir/unsafe-evidence-published-release"
unsafe_evidence_archive_src="$tmp_dir/unsafe-evidence-archive-src"
cp -R "$published_release_dir" "$unsafe_evidence_release_dir"
mkdir -p "$unsafe_evidence_archive_src"
printf '%s\n' "unsafe" >"$unsafe_evidence_archive_src/payload"
tar -C "$unsafe_evidence_archive_src" \
  --transform='s#payload#../payload#' \
  -czf "$unsafe_evidence_release_dir/loopwire-release-evidence-v0.1.0.tar.gz" \
  payload 2>/dev/null
refresh_published_release_manifest "$unsafe_evidence_release_dir" "$private_key_file"
if bash scripts/verify-published-release.sh \
  --release-dir "$unsafe_evidence_release_dir" \
  --public-key "$public_key_file" \
  --tag v0.1.0 \
  --require-release-evidence >/dev/null 2>&1; then
  echo "verify-scripts: published release verifier accepted an unsafe evidence archive path" >&2
  exit 1
fi
link_evidence_release_dir="$tmp_dir/link-evidence-published-release"
link_evidence_archive_src="$tmp_dir/link-evidence-archive-src"
cp -R "$published_release_dir" "$link_evidence_release_dir"
mkdir -p "$link_evidence_archive_src/v0.1.0"
ln -s release-evidence.json "$link_evidence_archive_src/v0.1.0/release-evidence.json"
tar -C "$link_evidence_archive_src" \
  -czf "$link_evidence_release_dir/loopwire-release-evidence-v0.1.0.tar.gz" \
  v0.1.0
refresh_published_release_manifest "$link_evidence_release_dir" "$private_key_file"
if bash scripts/verify-published-release.sh \
  --release-dir "$link_evidence_release_dir" \
  --public-key "$public_key_file" \
  --tag v0.1.0 \
  --require-release-evidence >/dev/null 2>&1; then
  echo "verify-scripts: published release verifier accepted a linked evidence archive member" >&2
  exit 1
fi
blocked_evidence_release_dir="$tmp_dir/blocked-evidence-published-release"
blocked_evidence_archive_src="$tmp_dir/blocked-evidence-archive-src"
cp -R "$published_release_dir" "$blocked_evidence_release_dir"
mkdir -p "$blocked_evidence_archive_src"
cp -R "$release_evidence_blocked_dir" "$blocked_evidence_archive_src/v0.1.0"
bind_release_evidence_public_key "$blocked_evidence_archive_src/v0.1.0" "$public_key_file"
tar -C "$blocked_evidence_archive_src" \
  -czf "$blocked_evidence_release_dir/loopwire-release-evidence-v0.1.0.tar.gz" \
  v0.1.0
refresh_published_release_manifest "$blocked_evidence_release_dir" "$private_key_file"
if bash scripts/verify-published-release.sh \
  --release-dir "$blocked_evidence_release_dir" \
  --public-key "$public_key_file" \
  --tag v0.1.0 \
  --require-release-evidence >/dev/null 2>&1; then
  echo "verify-scripts: published release verifier accepted blocked release evidence asset" >&2
  exit 1
fi
missing_arch_release_dir="$tmp_dir/missing-arch-published-release"
mkdir -p "$missing_arch_release_dir"
cp \
  "$published_release_dir/SHA256SUMS" \
  "$published_release_dir/SHA256SUMS.sig" \
  "$published_release_dir/loopwire-linux-${published_current_arch}.tar.gz" \
  "$missing_arch_release_dir/"
if bash scripts/verify-published-release.sh \
  --release-dir "$missing_arch_release_dir" \
  --public-key "$public_key_file" \
  --prefix "$tmp_dir/missing-arch-prefix" >/dev/null 2>&1; then
  echo "verify-scripts: published release verifier accepted a release missing ${published_secondary_arch}" >&2
  exit 1
fi
tampered_release_dir="$tmp_dir/tampered-published-release"
cp -R "$published_release_dir" "$tampered_release_dir"
printf '%s\n' "tamper" >>"$tampered_release_dir/loopwire-linux-${published_current_arch}.tar.gz"
if bash scripts/verify-published-release.sh \
  --release-dir "$tampered_release_dir" \
  --public-key "$public_key_file" \
  --prefix "$tmp_dir/tampered-prefix" >/dev/null 2>&1; then
  echo "verify-scripts: published release verifier accepted a tampered tarball" >&2
  exit 1
fi
if bash scripts/prepare-release-signing-key.sh \
  --private-key-out scripts/.unsafe-private.pem \
  --public-key-out "$tmp_dir/unsafe-public.pem" >/dev/null 2>&1; then
  echo "verify-scripts: release key helper allowed a private key inside the repo temp area" >&2
  exit 1
fi

support_dir="$tmp_dir/support-bundle"
node scripts/collect-support-bundle.mjs --output-dir "$support_dir" --profile quick >/dev/null
[ -s "$support_dir/support-bundle.json" ] || {
  echo "verify-scripts: support bundle manifest missing" >&2
  exit 1
}
[ -s "$support_dir/detect-audio.json" ] || {
  echo "verify-scripts: support bundle audio detection missing" >&2
  exit 1
}
[ -s "$support_dir/ct-host-check.log" ] || {
  echo "verify-scripts: support bundle host diagnostics missing" >&2
  exit 1
}
[ -s "$support_dir/notes.md" ] || {
  echo "verify-scripts: support bundle notes missing" >&2
  exit 1
}
node -e '
const fs = require("node:fs");
const manifest = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
if (manifest.profile !== "quick" || manifest.redacted !== true || !Array.isArray(manifest.commands)) {
  process.exit(1);
}
if (manifest.audio?.status !== "parsed" || !Array.isArray(manifest.audio.backends) || manifest.audio.backends.length === 0) {
  process.exit(1);
}
if (manifest.jack?.status !== "not_requested") {
  process.exit(1);
}
if (manifest.dspProvider?.status !== "not_requested") {
  process.exit(1);
}
if (!manifest.audio.backends.some((backend) => backend.kind === "pipewire" && Array.isArray(backend.gaps))) {
  process.exit(1);
}
' "$support_dir/support-bundle.json" || {
  echo "verify-scripts: support bundle manifest shape invalid" >&2
  exit 1
}
host_name="$(node -e 'process.stdout.write(require("node:os").hostname())')"
if [ "${#host_name}" -ge 5 ] && grep -R "$host_name" "$support_dir" >/dev/null 2>&1; then
  echo "verify-scripts: support bundle leaked hostname" >&2
  exit 1
fi
support_jack_dir="$tmp_dir/support-bundle-jack"
node scripts/collect-support-bundle.mjs \
  --output-dir "$support_jack_dir" \
  --profile quick \
  --configuration "$jack_configuration" \
  --jack-ports-file "$jack_ports_file" >/dev/null
[ -s "$support_jack_dir/jack-port-requirements.json" ] || {
  echo "verify-scripts: support bundle JACK readiness log missing" >&2
  exit 1
}
node -e '
const fs = require("node:fs");
const manifest = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
if (manifest.jack?.status !== "parsed" || manifest.jack.ok !== true || manifest.jack.missingCount !== 0) {
  process.exit(1);
}
if (!manifest.jack.requirements.some((item) => item.deviceName === "loopwire_jack-mix_input_mic" && item.ready)) {
  process.exit(1);
}
if (!manifest.commands.some((command) => command.name === "jack-readiness" && command.exitCode === 0)) {
  process.exit(1);
}
' "$support_jack_dir/support-bundle.json" || {
  echo "verify-scripts: support bundle JACK readiness summary invalid" >&2
  exit 1
}
support_dsp_dir="$tmp_dir/support-bundle-dsp"
node scripts/collect-support-bundle.mjs \
  --output-dir "$support_dsp_dir" \
  --profile quick \
  --configuration "$jack_configuration" \
  --jack-ports-file "$jack_ports_file" \
  --include-dsp-provider-plan \
  --dsp-frame-count 2 >/dev/null
[ -s "$support_dsp_dir/dsp-provider-plan.json" ] || {
  echo "verify-scripts: support bundle DSP provider plan log missing" >&2
  exit 1
}
node -e '
const fs = require("node:fs");
const manifest = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
if (manifest.dspProvider?.status !== "parsed" || manifest.dspProvider.ok !== true) {
  process.exit(1);
}
if (manifest.dspProvider.frameCount !== 2 || manifest.dspProvider.providerCommand !== "not_provided") {
  process.exit(1);
}
if (manifest.dspProvider.providerCapability?.status !== "not_requested") {
  process.exit(1);
}
if (!manifest.dspProvider.operations.some((item) => item.operation === "clear-output" && item.frames === 2)) {
  process.exit(1);
}
const command = manifest.commands.find((item) => item.name === "dsp-provider-plan");
if (!command || command.exitCode !== 0 || !command.command.includes("scripts/describe-dsp-provider.mjs")) {
  process.exit(1);
}
if (command.command.includes("--execute")) {
  process.exit(1);
}
' "$support_dsp_dir/support-bundle.json" || {
  echo "verify-scripts: support bundle DSP provider summary invalid" >&2
  exit 1
}

evidence_dir="$tmp_dir/vm-evidence"
mkdir -p "$evidence_dir"
printf '%s\n' "pnpm check passed" >"$evidence_dir/pnpm-check.log"
printf '%s\n' "Loopwire desktop launch smoke passed: http://127.0.0.1:5181/" >"$evidence_dir/desktop-launch.log"
printf '%s\n' "audio host build passed" >"$evidence_dir/audio-host-build.log"
printf '%s\n' '{"platform":"linux","reports":[{"kind":"pipewire","availability":"available"}]}' >"$evidence_dir/detect-audio.json"
node - "$evidence_dir/environment.json" <<'NODE'
const fs = require("node:fs");
const output = process.argv[2];
const manifest = {
  kind: "loopwire.vm-environment",
  version: 1,
  generatedAt: "2026-07-03T00:00:00.000Z",
  target: {
    id: "arch-hyprland-pipewire",
    distro: "Arch Linux",
    family: "pacman",
    desktop: "Hyprland",
    session: "Wayland",
    audio: "PipeWire/WirePlumber",
    arch: "x86_64",
    tier: "manual-vm",
    notes: "Reference rolling WM path."
  },
  observed: {
    platform: "linux",
    architecture: "x86_64",
    kernel: "Linux 6.0.0 x86_64",
    osRelease: { id: "arch", name: "Arch Linux" },
    sessionType: "wayland",
    desktop: "Hyprland",
    hasWaylandDisplay: true,
    hasX11Display: false
  }
};
fs.writeFileSync(output, `${JSON.stringify(manifest, null, 2)}\n`);
NODE
printf '%s\n' "ct host check passed" >"$evidence_dir/ct-host-check.log"
printf '%s\n' "autostart passed" >"$evidence_dir/autostart.log"
printf '%s\n' "Support bundle written to support-bundle" >"$evidence_dir/support-bundle.log"
printf '%s\n' "# VM Evidence" >"$evidence_dir/notes.md"
mkdir -p "$evidence_dir/support-bundle"
cp "$evidence_dir/detect-audio.json" "$evidence_dir/support-bundle/detect-audio.json"
printf '%s\n' "ct host check passed" >"$evidence_dir/support-bundle/ct-host-check.log"
printf '%s\n' "autostart status passed" >"$evidence_dir/support-bundle/autostart-status.log"
write_test_png() {
  node - "$1" "$2" "$3" <<'NODE'
const fs = require("node:fs");
const zlib = require("node:zlib");

const output = process.argv[2];
const width = Number(process.argv[3]);
const height = Number(process.argv[4]);

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const byte of buffer) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const typeBuffer = Buffer.from(type, "ascii");
  const output = Buffer.alloc(12 + data.length);
  output.writeUInt32BE(data.length, 0);
  typeBuffer.copy(output, 4);
  data.copy(output, 8);
  output.writeUInt32BE(crc32(Buffer.concat([typeBuffer, data])), 8 + data.length);
  return output;
}

const signature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(width, 0);
ihdr.writeUInt32BE(height, 4);
ihdr[8] = 8;
ihdr[9] = 2;
ihdr[10] = 0;
ihdr[11] = 0;
ihdr[12] = 0;

const rowBytes = 1 + width * 3;
const raw = Buffer.alloc(rowBytes * height);
for (let y = 0; y < height; y += 1) {
  const row = y * rowBytes;
  raw[row] = 0;
  for (let x = 0; x < width; x += 1) {
    const pixel = row + 1 + x * 3;
    raw[pixel] = x % 256;
    raw[pixel + 1] = y % 256;
    raw[pixel + 2] = (x + y) % 256;
  }
}

fs.writeFileSync(output, Buffer.concat([
  signature,
  chunk("IHDR", ihdr),
  chunk("IDAT", zlib.deflateSync(raw)),
  chunk("IEND", Buffer.alloc(0))
]));
NODE
}
node - "$evidence_dir/support-bundle/support-bundle.json" <<'NODE'
const fs = require("node:fs");
const output = process.argv[2];
const manifest = {
  kind: "loopwire.support-bundle",
  version: 1,
  redacted: true,
  audio: {
    status: "parsed",
    backends: [
      {
        kind: "pipewire",
        availability: "available",
        controlScope: "link-only",
        supportsPerEdgeGain: false,
        supportsPerEdgeMute: true,
        gaps: ["per-edge gain controls"]
      }
    ]
  },
  commands: [{ name: "detect-audio", exitCode: 0 }]
};
manifest.commands.push({ name: "ct-host-check", exitCode: 0 });
manifest.commands.push({ name: "autostart-status", exitCode: 0 });
fs.writeFileSync(output, `${JSON.stringify(manifest, null, 2)}\n`);
NODE
printf '%s\n' 'name	exitCode	startedAt	finishedAt	log' \
  'detect-audio	0	2026-07-03T00:00:02+00:00	2026-07-03T00:00:03+00:00	detect-audio.json' \
  'ct-host-check	0	2026-07-03T00:00:03+00:00	2026-07-03T00:00:04+00:00	ct-host-check.log' \
  'autostart-status	0	2026-07-03T00:00:04+00:00	2026-07-03T00:00:05+00:00	autostart-status.log' \
  >"$evidence_dir/support-bundle/command-results.tsv"
printf '%s\n' "# Loopwire Support Bundle" >"$evidence_dir/support-bundle/notes.md"
write_test_png "$evidence_dir/screenshot.png" 1280 720
{
  printf 'pnpm-check\t0\t2026-07-03T00:00:00+00:00\t2026-07-03T00:00:01+00:00\tpnpm-check.log\n'
  printf 'desktop-launch\t0\t2026-07-03T00:00:01+00:00\t2026-07-03T00:00:02+00:00\tdesktop-launch.log\n'
  printf 'audio-host-build\t0\t2026-07-03T00:00:01+00:00\t2026-07-03T00:00:02+00:00\taudio-host-build.log\n'
  printf 'detect-audio\t0\t2026-07-03T00:00:02+00:00\t2026-07-03T00:00:03+00:00\tdetect-audio.json\n'
  printf 'ct-host-check\t0\t2026-07-03T00:00:03+00:00\t2026-07-03T00:00:04+00:00\tct-host-check.log\n'
  printf 'autostart\t0\t2026-07-03T00:00:04+00:00\t2026-07-03T00:00:05+00:00\tautostart.log\n'
  printf 'support-bundle\t0\t2026-07-03T00:00:05+00:00\t2026-07-03T00:00:06+00:00\tsupport-bundle.log\n'
} >"$evidence_dir/command-results.tsv"
bash scripts/verify-vm-evidence.sh --target arch-hyprland-pipewire --evidence-dir "$evidence_dir" >/dev/null
status_root="$tmp_dir/vm-status-root"
mkdir -p "$status_root"
cp -R "$evidence_dir" "$status_root/arch-hyprland-pipewire"
vm_verified_status_output="$(
  bash scripts/vm-matrix.sh evidence-status \
    --target arch-hyprland-pipewire \
    --evidence-root "$status_root"
)"
printf '%s\n' "$vm_verified_status_output" | grep -F "status=verified" >/dev/null || {
  echo "verify-scripts: vm evidence-status did not report verified evidence" >&2
  exit 1
}
printf '%s\n' "$vm_verified_status_output" \
  | grep -F "summary=checked:1 verified:1 missing:0 invalid:0" >/dev/null || {
    echo "verify-scripts: vm evidence-status verified summary is wrong" >&2
    exit 1
  }
if bash scripts/vm-matrix.sh evidence-status \
  --target arch-hyprland-pipewire \
  --evidence-root "$status_root" \
  --require-published-release >"$tmp_dir/vm-status-strict-missing.log" 2>&1; then
  echo "verify-scripts: vm evidence-status accepted missing published-release smoke" >&2
  exit 1
fi
grep -F "status=invalid" "$tmp_dir/vm-status-strict-missing.log" >/dev/null || {
  echo "verify-scripts: vm evidence-status did not report invalid strict evidence" >&2
  exit 1
}
grep -F "published-release-smoke.log" "$tmp_dir/vm-status-strict-missing.log" >/dev/null || {
  echo "verify-scripts: vm evidence-status strict failure reason missing" >&2
  exit 1
}
missing_audio_summary_dir="$tmp_dir/vm-evidence-missing-audio-summary"
cp -R "$evidence_dir" "$missing_audio_summary_dir"
node - "$missing_audio_summary_dir/support-bundle/support-bundle.json" <<'NODE'
const fs = require("node:fs");
const path = process.argv[2];
const manifest = JSON.parse(fs.readFileSync(path, "utf8"));
delete manifest.audio;
fs.writeFileSync(path, `${JSON.stringify(manifest, null, 2)}\n`);
NODE
if bash scripts/verify-vm-evidence.sh \
  --target arch-hyprland-pipewire \
  --evidence-dir "$missing_audio_summary_dir" >/dev/null 2>&1; then
  echo "verify-scripts: verify-vm-evidence accepted support bundle without audio backend summary" >&2
  exit 1
fi
if bash scripts/verify-vm-evidence.sh \
  --target arch-hyprland-pipewire \
  --evidence-dir "$evidence_dir" \
  --require-published-release >/dev/null 2>&1; then
  echo "verify-scripts: verify-vm-evidence accepted missing required published-release smoke" >&2
  exit 1
fi
small_screenshot_dir="$tmp_dir/vm-evidence-small-screenshot"
cp -R "$evidence_dir" "$small_screenshot_dir"
write_test_png "$small_screenshot_dir/screenshot.png" 1 1
if bash scripts/verify-vm-evidence.sh \
  --target arch-hyprland-pipewire \
  --evidence-dir "$small_screenshot_dir" >/dev/null 2>&1; then
  echo "verify-scripts: verify-vm-evidence accepted a too-small screenshot" >&2
  exit 1
fi
truncated_screenshot_dir="$tmp_dir/vm-evidence-truncated-screenshot"
cp -R "$evidence_dir" "$truncated_screenshot_dir"
node -e '
const fs = require("node:fs");
const output = process.argv[1];
const header = Buffer.alloc(33);
Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(header, 0);
header.writeUInt32BE(13, 8);
header.write("IHDR", 12, "ascii");
header.writeUInt32BE(1280, 16);
header.writeUInt32BE(720, 20);
header[24] = 8;
header[25] = 2;
fs.writeFileSync(output, header);
' "$truncated_screenshot_dir/screenshot.png"
if bash scripts/verify-vm-evidence.sh \
  --target arch-hyprland-pipewire \
  --evidence-dir "$truncated_screenshot_dir" >/dev/null 2>&1; then
  echo "verify-scripts: verify-vm-evidence accepted a truncated screenshot" >&2
  exit 1
fi
bad_crc_screenshot_dir="$tmp_dir/vm-evidence-bad-crc-screenshot"
cp -R "$evidence_dir" "$bad_crc_screenshot_dir"
node -e '
const fs = require("node:fs");
const path = process.argv[1];
const data = fs.readFileSync(path);
let offset = 8;
while (offset < data.length) {
  const length = data.readUInt32BE(offset);
  const type = data.toString("ascii", offset + 4, offset + 8);
  const crcOffset = offset + 8 + length;
  if (type === "IDAT") {
    data[crcOffset + 3] ^= 0xff;
    fs.writeFileSync(path, data);
    process.exit(0);
  }
  offset = crcOffset + 4;
}
throw new Error("test PNG did not contain an IDAT chunk");
' "$bad_crc_screenshot_dir/screenshot.png"
if bash scripts/verify-vm-evidence.sh \
  --target arch-hyprland-pipewire \
  --evidence-dir "$bad_crc_screenshot_dir" >/dev/null 2>&1; then
  echo "verify-scripts: verify-vm-evidence accepted a screenshot with a bad PNG CRC" >&2
  exit 1
fi
matrix_release_copy="$tmp_dir/support-matrix-release-required.md"
cp apps/docs/docs/guide/support-matrix.md "$matrix_release_copy"
if node scripts/promote-vm-evidence.mjs \
  --target arch-hyprland-pipewire \
  --evidence-dir "$evidence_dir" \
  --matrix "$matrix_release_copy" \
  --require-published-release \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: promote-vm-evidence accepted missing required published-release smoke" >&2
  exit 1
fi
matrix_strict_missing_release="$tmp_dir/support-matrix-strict-missing-release.md"
matrix_strict_missing_root="$tmp_dir/support-matrix-strict-missing-root"
cp apps/docs/docs/guide/support-matrix.md "$matrix_strict_missing_release"
node - "$matrix_strict_missing_release" <<'NODE'
const fs = require("node:fs");
const path = process.argv[2];
const before = "| `arch-hyprland-pipewire` | Hyprland on Wayland | PipeWire/WirePlumber | Manual VM |";
const after = "| `arch-hyprland-pipewire` | Hyprland on Wayland | PipeWire/WirePlumber | Verified |";
const content = fs.readFileSync(path, "utf8");
if (!content.includes(before)) process.exit(1);
fs.writeFileSync(path, content.replace(before, after));
NODE
mkdir -p "$matrix_strict_missing_root"
cp -R "$evidence_dir" "$matrix_strict_missing_root/arch-hyprland-pipewire"
if node scripts/verify-support-matrix.mjs \
  --matrix "$matrix_strict_missing_release" \
  --evidence-root "$matrix_strict_missing_root" \
  --require-published-release >/dev/null 2>&1; then
  echo "verify-scripts: verify-support-matrix accepted Verified row without published-release smoke" >&2
  exit 1
fi
printf '%s\n' "Published release verification passed for /tmp/fake-release." >"$evidence_dir/published-release-smoke.log"
cat >"$evidence_dir/published-release.json" <<'JSON'
{
  "kind": "loopwire.vm-published-release",
  "version": 1,
  "generatedAt": "2026-07-03T00:00:00.000Z",
  "source": "github",
  "release": {
    "repo": "sandwichfarm/loopwire",
    "tag": "v0.1.0",
    "publicKey": "packaging/release-signing-public.pem"
  }
}
JSON
printf 'published-release-smoke\t0\t2026-07-03T00:00:06+00:00\t2026-07-03T00:00:07+00:00\tpublished-release-smoke.log\n' \
  >>"$evidence_dir/command-results.tsv"
bash scripts/verify-vm-evidence.sh \
  --target arch-hyprland-pipewire \
  --evidence-dir "$evidence_dir" \
  --require-published-release >/dev/null
bash scripts/verify-vm-evidence.sh \
  --target arch-hyprland-pipewire \
  --evidence-dir "$evidence_dir" \
  --require-published-release \
  --release-tag v0.1.0 >/dev/null
bash scripts/verify-vm-evidence.sh \
  --target arch-hyprland-pipewire \
  --evidence-dir "$evidence_dir" \
  --require-published-release \
  --release-tag v0.1.0 \
  --require-github-release-source >/dev/null
release_status_custom_vm_root="$tmp_dir/release-status-custom-vm-root"
release_status_custom_matrix="$tmp_dir/release-status-custom-support-matrix.md"
release_status_custom_root_log="$tmp_dir/release-status-custom-vm-root.log"
mkdir -p "$release_status_custom_vm_root"
cp -R "$evidence_dir" "$release_status_custom_vm_root/arch-hyprland-pipewire"
cp apps/docs/docs/guide/support-matrix.md "$release_status_custom_matrix"
node - "$release_status_custom_matrix" <<'NODE'
const fs = require("node:fs");
const path = process.argv[2];
const before = "| `arch-hyprland-pipewire` | Hyprland on Wayland | PipeWire/WirePlumber | Manual VM |";
const after = "| `arch-hyprland-pipewire` | Hyprland on Wayland | PipeWire/WirePlumber | Verified |";
const content = fs.readFileSync(path, "utf8");
if (!content.includes(before)) process.exit(1);
fs.writeFileSync(path, content.replace(before, after));
NODE
if bash scripts/audit-final-release-state.sh \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --git-head 0123456789abcdef0123456789abcdef01234567 \
  --public-key "$release_status_public_key" \
  --secret-list-file "$secret_list_all_final" \
  --docs-deployment-manifest "$release_status_docs_manifest" \
  --docs-dist "$release_status_docs_dist" \
  --vm-evidence-root "$release_status_custom_vm_root" \
  --support-matrix "$release_status_custom_matrix" \
  --skip-gh >"$release_status_custom_root_log" 2>&1; then
  echo "verify-scripts: release status accepted incomplete custom VM evidence root" >&2
  exit 1
fi
grep -F "blocked: published-release-bound VM evidence" "$release_status_custom_root_log" >/dev/null || {
  echo "verify-scripts: release status did not block incomplete custom VM evidence root" >&2
  exit 1
}
grep -F "ok: support matrix published-release claims" "$release_status_custom_root_log" >/dev/null || {
  echo "verify-scripts: release status did not pass the custom-root support matrix gate" >&2
  exit 1
}
if grep -F "blocked: support matrix published-release claims" "$release_status_custom_root_log" >/dev/null; then
  echo "verify-scripts: release status support matrix gate ignored the custom VM evidence root" >&2
  exit 1
fi
if bash scripts/verify-vm-evidence.sh \
  --target arch-hyprland-pipewire \
  --evidence-dir "$evidence_dir" \
  --require-published-release \
  --release-tag v0.2.0 >/dev/null 2>&1; then
  echo "verify-scripts: verify-vm-evidence accepted a mismatched release tag" >&2
  exit 1
fi
directory_source_evidence_dir="$tmp_dir/vm-evidence-directory-source"
cp -R "$evidence_dir" "$directory_source_evidence_dir"
node - "$directory_source_evidence_dir/published-release.json" <<'NODE'
const fs = require("node:fs");
const path = process.argv[2];
const manifest = JSON.parse(fs.readFileSync(path, "utf8"));
manifest.source = "directory";
delete manifest.release.repo;
manifest.release.directory = "/guest/release";
fs.writeFileSync(path, `${JSON.stringify(manifest, null, 2)}\n`);
NODE
bash scripts/verify-vm-evidence.sh \
  --target arch-hyprland-pipewire \
  --evidence-dir "$directory_source_evidence_dir" \
  --require-published-release \
  --release-tag v0.1.0 >/dev/null
if bash scripts/verify-vm-evidence.sh \
  --target arch-hyprland-pipewire \
  --evidence-dir "$directory_source_evidence_dir" \
  --require-published-release \
  --release-tag v0.1.0 \
  --require-github-release-source >/dev/null 2>&1; then
  echo "verify-scripts: verify-vm-evidence accepted directory source as final GitHub release proof" >&2
  exit 1
fi
rm -rf "$status_root/arch-hyprland-pipewire"
cp -R "$evidence_dir" "$status_root/arch-hyprland-pipewire"
vm_evidence_archive="$tmp_dir/loopwire-vm-evidence-v0.1.0.tar.gz"
bash scripts/package-vm-evidence.sh \
  --tag v0.1.0 \
  --evidence-root "$status_root" \
  --target arch-hyprland-pipewire \
  --require-published-release \
  --output "$vm_evidence_archive" >/dev/null
tar -tzf "$vm_evidence_archive" "vm-evidence/arch-hyprland-pipewire/command-results.tsv" >/dev/null || {
  echo "verify-scripts: VM evidence packager archive is missing target command ledger" >&2
  exit 1
}
tar -tzf "$vm_evidence_archive" "vm-evidence/manifest.json" >/dev/null || {
  echo "verify-scripts: VM evidence packager archive is missing root manifest" >&2
  exit 1
}
mkdir -p "$tmp_dir/vm-evidence-archive-extract"
bash scripts/extract-safe-tar.sh \
  --archive "$vm_evidence_archive" \
  --output-dir "$tmp_dir/vm-evidence-archive-extract" \
  --label "VM evidence archive" >/dev/null
node scripts/verify-vm-evidence-archive-manifest.mjs \
  --manifest "$tmp_dir/vm-evidence-archive-extract/vm-evidence/manifest.json" \
  --tag v0.1.0 \
  --target arch-hyprland-pipewire \
  --require-published-release >/dev/null
node - "$tmp_dir/vm-evidence-archive-extract/vm-evidence/manifest.json" <<'NODE'
const fs = require("node:fs");
const path = process.argv[2];
const manifest = JSON.parse(fs.readFileSync(path, "utf8"));
manifest.tag = "v0.2.0";
fs.writeFileSync(path, `${JSON.stringify(manifest, null, 2)}\n`);
NODE
if node scripts/verify-vm-evidence-archive-manifest.mjs \
  --manifest "$tmp_dir/vm-evidence-archive-extract/vm-evidence/manifest.json" \
  --tag v0.1.0 \
  --target arch-hyprland-pipewire \
  --require-published-release >/dev/null 2>&1; then
  echo "verify-scripts: VM evidence archive manifest verifier accepted a mismatched tag" >&2
  exit 1
fi
vm_release_dir="$tmp_dir/vm-evidence-release-dir"
mkdir -p "$vm_release_dir"
printf '%s\n' "fake release payload" >"$vm_release_dir/loopwire-linux-x86_64.tar.gz"
refresh_published_release_manifest "$vm_release_dir" "$private_key_file"
vm_release_env_file="$tmp_dir/vm-evidence-release.env"
cat >"$vm_release_env_file" <<EOF
BUNNY_STORAGE_ZONE=env-loopwire-docs
BUNNY_ACCESS_KEY=env-access-key-that-must-not-print
BUNNY_STORAGE_ENDPOINT=ny.storage.bunnycdn.com
BUNNY_PULL_ZONE_HOSTNAME=docs.env.example.test
BUNNY_REMOTE_PREFIX=env-preview
LOOPWIRE_RELEASE_PRIVATE_KEY_FILE=$private_key_file
LOOPWIRE_RELEASE_PUBLIC_KEY_FILE=$public_key_file
EOF
vm_release_prepare_output="$(
  bash scripts/prepare-vm-evidence-release-asset.sh \
    --repo sandwichfarm/loopwire \
    --tag v0.1.0 \
    --release-dir "$vm_release_dir" \
    --env-file "$vm_release_env_file" \
    --evidence-root "$status_root" \
    --target arch-hyprland-pipewire
)"
printf '%s\n' "$vm_release_prepare_output" | grep -F "Prepared signed VM evidence release asset:" >/dev/null || {
  echo "verify-scripts: VM evidence release helper did not report prepared asset" >&2
  exit 1
}
printf '%s\n' "$vm_release_prepare_output" | grep -F "gh release upload v0.1.0" >/dev/null || {
  echo "verify-scripts: VM evidence release helper did not print upload command" >&2
  exit 1
}
if printf '%s\n' "$vm_release_prepare_output" | grep -F "env-access-key-that-must-not-print" >/dev/null; then
  echo "verify-scripts: VM evidence release helper leaked Bunny access key" >&2
  exit 1
fi
bash scripts/verify-release-asset-checksum.sh \
  --release-dir "$vm_release_dir" \
  --asset loopwire-vm-evidence-v0.1.0.tar.gz \
  --public-key "$public_key_file" \
  --label "VM evidence archive" >/dev/null
unsafe_vm_evidence_root="$tmp_dir/unsafe-vm-evidence-root"
mkdir -p "$unsafe_vm_evidence_root"
cp -R "$evidence_dir" "$unsafe_vm_evidence_root/arch-hyprland-pipewire"
ln -s /tmp "$unsafe_vm_evidence_root/arch-hyprland-pipewire/unsafe-link"
if bash scripts/package-vm-evidence.sh \
  --tag v0.1.0 \
  --evidence-root "$unsafe_vm_evidence_root" \
  --target arch-hyprland-pipewire \
  --require-published-release \
  --output "$tmp_dir/loopwire-vm-evidence-v0.1.0-unsafe-member.tar.gz" >/dev/null 2>&1; then
  echo "verify-scripts: VM evidence packager accepted an unsafe archive member" >&2
  exit 1
fi
if bash scripts/package-vm-evidence.sh \
  --tag v0.1.0 \
  --evidence-root "$status_root" \
  --target arch-hyprland-pipewire \
  --require-published-release \
  --output "$tmp_dir/not-loopwire-vm-evidence.tar.gz" >/dev/null 2>&1; then
  echo "verify-scripts: VM evidence packager accepted a non-release-asset output basename" >&2
  exit 1
fi
if bash scripts/package-vm-evidence.sh \
  --tag v0.1.0 \
  --evidence-root "$status_root" \
  --target arch-hyprland-pipewire \
  --require-published-release \
  --output "../loopwire-vm-evidence-v0.1.0.tar.gz" >/dev/null 2>&1; then
  echo "verify-scripts: VM evidence packager accepted parent traversal in output path" >&2
  exit 1
fi
if bash scripts/package-vm-evidence.sh \
  --tag v0.1.0 \
  --evidence-root "$status_root" \
  --target arch-hyprland-pipewire \
  --all \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: VM evidence packager accepted --all with --target" >&2
  exit 1
fi
vm_strict_status_output="$(
  bash scripts/vm-matrix.sh evidence-status \
    --target arch-hyprland-pipewire \
    --evidence-root "$status_root" \
    --require-published-release \
    --release-tag v0.1.0
)"
printf '%s\n' "$vm_strict_status_output" | grep -F "require-published-release=true" >/dev/null || {
  echo "verify-scripts: vm evidence-status strict mode banner missing" >&2
  exit 1
}
printf '%s\n' "$vm_strict_status_output" | grep -F "release-tag=v0.1.0" >/dev/null || {
  echo "verify-scripts: vm evidence-status strict release tag banner missing" >&2
  exit 1
}
printf '%s\n' "$vm_strict_status_output" \
  | grep -F -- "--require-published-release --release-tag v0.1.0" >/dev/null || {
    echo "verify-scripts: vm evidence-status verify command is missing release tag strictness" >&2
    exit 1
  }
printf '%s\n' "$vm_strict_status_output" \
  | grep -F "summary=checked:1 verified:1 missing:0 invalid:0" >/dev/null || {
    echo "verify-scripts: vm evidence-status strict summary is wrong" >&2
    exit 1
  }
matrix_copy="$tmp_dir/support-matrix.md"
cp apps/docs/docs/guide/support-matrix.md "$matrix_copy"
promote_dry_run="$(
  node scripts/promote-vm-evidence.mjs \
    --target arch-hyprland-pipewire \
    --evidence-dir "$evidence_dir" \
    --matrix "$matrix_copy" \
    --require-published-release \
    --dry-run
)"
printf '%s\n' "$promote_dry_run" | grep -F "would promote arch-hyprland-pipewire" >/dev/null || {
  echo "verify-scripts: promote-vm-evidence dry-run did not preview promotion" >&2
  exit 1
}
grep -F '| `arch-hyprland-pipewire` | Hyprland on Wayland | PipeWire/WirePlumber | Manual VM |' \
  "$matrix_copy" >/dev/null || {
    echo "verify-scripts: promote-vm-evidence dry-run mutated the matrix" >&2
    exit 1
  }
node scripts/promote-vm-evidence.mjs \
  --target arch-hyprland-pipewire \
  --evidence-dir "$evidence_dir" \
  --matrix "$matrix_copy" >/dev/null
grep -F '| `arch-hyprland-pipewire` | Hyprland on Wayland | PipeWire/WirePlumber | Verified |' \
  "$matrix_copy" >/dev/null || {
    echo "verify-scripts: promote-vm-evidence did not promote the matrix row" >&2
    exit 1
  }
matrix_strict_root="$tmp_dir/support-matrix-strict-root"
mkdir -p "$matrix_strict_root"
cp -R "$evidence_dir" "$matrix_strict_root/arch-hyprland-pipewire"
node scripts/verify-support-matrix.mjs \
  --matrix "$matrix_copy" \
  --evidence-root "$matrix_strict_root" \
  --require-published-release >/dev/null
support_matrix_link="$tmp_dir/support-matrix-link.md"
ln -s "$matrix_copy" "$support_matrix_link"
if node scripts/verify-support-matrix.mjs \
  --matrix "$support_matrix_link" \
  --evidence-root "$matrix_strict_root" >/dev/null 2>&1; then
  echo "verify-scripts: verify-support-matrix accepted a symlinked matrix path" >&2
  exit 1
fi
support_matrix_bad_root="$tmp_dir/support-matrix-root-file"
printf 'not a directory\n' >"$support_matrix_bad_root"
if node scripts/verify-support-matrix.mjs \
  --matrix "$matrix_copy" \
  --evidence-root "$support_matrix_bad_root" >/dev/null 2>&1; then
  echo "verify-scripts: verify-support-matrix accepted a file-valued evidence root" >&2
  exit 1
fi
if node scripts/verify-support-matrix.mjs \
  --matrix ../support-matrix.md \
  --evidence-root "$matrix_strict_root" >/dev/null 2>&1; then
  echo "verify-scripts: verify-support-matrix accepted parent traversal in matrix path" >&2
  exit 1
fi
matrix_all_copy="$tmp_dir/support-matrix-all.md"
matrix_all_root="$tmp_dir/support-matrix-all-root"
cp apps/docs/docs/guide/support-matrix.md "$matrix_all_copy"
mkdir -p "$matrix_all_root"
cp -R "$evidence_dir" "$matrix_all_root/arch-hyprland-pipewire"
promote_all_dry_run="$(
  node scripts/promote-vm-evidence.mjs \
    --all \
    --evidence-root "$matrix_all_root" \
    --matrix "$matrix_all_copy" \
    --require-published-release \
    --dry-run
)"
printf '%s\n' "$promote_all_dry_run" | grep -F "would promote arch-hyprland-pipewire" >/dev/null || {
  echo "verify-scripts: promote-vm-evidence --all dry-run did not preview verified evidence" >&2
  exit 1
}
printf '%s\n' "$promote_all_dry_run" | grep -F "missing evidence: fedora-kde-pipewire" >/dev/null || {
  echo "verify-scripts: promote-vm-evidence --all did not report missing target evidence" >&2
  exit 1
}
grep -F '| `arch-hyprland-pipewire` | Hyprland on Wayland | PipeWire/WirePlumber | Manual VM |' \
  "$matrix_all_copy" >/dev/null || {
    echo "verify-scripts: promote-vm-evidence --all dry-run mutated the matrix" >&2
    exit 1
  }
node scripts/promote-vm-evidence.mjs \
  --all \
  --evidence-root "$matrix_all_root" \
  --matrix "$matrix_all_copy" \
  --require-published-release >/dev/null
grep -F '| `arch-hyprland-pipewire` | Hyprland on Wayland | PipeWire/WirePlumber | Verified |' \
  "$matrix_all_copy" >/dev/null || {
    echo "verify-scripts: promote-vm-evidence --all did not promote verified target evidence" >&2
    exit 1
  }
if node scripts/promote-vm-evidence.mjs --all --target arch-hyprland-pipewire >/dev/null 2>&1; then
  echo "verify-scripts: promote-vm-evidence accepted --all with --target" >&2
  exit 1
fi
if node scripts/promote-vm-evidence.mjs --all --evidence-dir "$evidence_dir" >/dev/null 2>&1; then
  echo "verify-scripts: promote-vm-evidence accepted --all with --evidence-dir" >&2
  exit 1
fi
promote_noop="$(
  node scripts/promote-vm-evidence.mjs \
    --target arch-hyprland-pipewire \
    --evidence-dir "$evidence_dir" \
    --matrix "$matrix_copy"
)"
printf '%s\n' "$promote_noop" | grep -F "already marks arch-hyprland-pipewire as Verified" >/dev/null || {
  echo "verify-scripts: promote-vm-evidence did not no-op an already verified row" >&2
  exit 1
}

ssh_dry_run="$(bash scripts/collect-vm-evidence-ssh.sh \
  --target arch-hyprland-pipewire \
  --host 127.0.0.1 \
  --screenshot-command 'grim "$LOOPWIRE_SCREENSHOT_PATH"')"
printf '%s\n' "$ssh_dry_run" | grep -F "SSH collector command:" >/dev/null
printf '%s\n' "$ssh_dry_run" | grep -F "SCP evidence command:" >/dev/null
printf '%s\n' "$ssh_dry_run" | grep -F "Dry run complete. Add --execute" >/dev/null
ssh_port_dry_run="$(bash scripts/collect-vm-evidence-ssh.sh \
  --target arch-hyprland-pipewire \
  --host 127.0.0.1 \
  --desktop-port 5199)"
printf '%s\n' "$ssh_port_dry_run" | grep -F -- "--desktop-port" >/dev/null
printf '%s\n' "$ssh_port_dry_run" | grep -F -- "5199" >/dev/null
ssh_release_dry_run="$(bash scripts/collect-vm-evidence-ssh.sh \
  --target arch-hyprland-pipewire \
  --host 127.0.0.1 \
  --published-release-dir /guest/release \
  --published-release-tag v0.1.0 \
  --release-public-key /guest/release-public.pem \
  --require-published-release)"
printf '%s\n' "$ssh_release_dry_run" | grep -F -- "--published-release-dir" >/dev/null
printf '%s\n' "$ssh_release_dry_run" | grep -F -- "--published-release-tag" >/dev/null
printf '%s\n' "$ssh_release_dry_run" | grep -F -- "--release-public-key" >/dev/null
printf '%s\n' "$ssh_release_dry_run" | grep -F -- "--require-published-release" >/dev/null
ssh_github_release_dry_run="$(bash scripts/collect-vm-evidence-ssh.sh \
  --target arch-hyprland-pipewire \
  --host 127.0.0.1 \
  --published-release-repo sandwichfarm/loopwire \
  --published-release-tag v0.1.0 \
  --release-public-key /guest/release-public.pem \
  --require-published-release \
  --require-github-release-source)"
printf '%s\n' "$ssh_github_release_dry_run" | grep -F -- "--published-release-repo" >/dev/null
printf '%s\n' "$ssh_github_release_dry_run" | grep -F -- "--require-github-release-source" >/dev/null

matrix_plan="$tmp_dir/vm-ssh-plan.tsv"
{
  printf '%s\n' '# target	host	port	user	identity	desktop_port	screenshot_command	local_output_dir'
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    'arch-hyprland-pipewire' \
    '127.0.0.1' \
    '2222' \
    'loopwire' \
    '-' \
    '5199' \
    '-' \
    '-'
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    'ubuntu-gnome-pipewire-aarch64' \
    '127.0.0.1' \
    '2422' \
    'loopwire' \
    '/tmp/loopwire-key' \
    '-' \
    'grim "$LOOPWIRE_SCREENSHOT_PATH"' \
    '.vm/evidence/ubuntu-gnome-pipewire-aarch64'
} >"$matrix_plan"
if bash scripts/collect-vm-matrix-evidence.sh \
  --plan "$matrix_plan" \
  --published-release-dir /guest/release \
  --published-release-tag v0.1.0 \
  --release-public-key /guest/release-public.pem \
  --require-published-release \
  --require-github-release-source >/dev/null 2>&1; then
  echo "verify-scripts: matrix VM evidence collector accepted GitHub-source proof with a release directory" >&2
  exit 1
fi
matrix_dry_run="$(bash scripts/collect-vm-matrix-evidence.sh --plan "$matrix_plan")"
printf '%s\n' "$matrix_dry_run" | grep -F "Dry run complete for 2 target(s)." >/dev/null || {
  echo "verify-scripts: matrix VM evidence collector did not report both plan rows" >&2
  exit 1
}
printf '%s\n' "$matrix_dry_run" | grep -F -- "--target ubuntu-gnome-pipewire-aarch64" >/dev/null || {
  echo "verify-scripts: matrix VM evidence collector did not forward the AArch64 target" >&2
  exit 1
}
printf '%s\n' "$matrix_dry_run" | grep -F -- "--identity /tmp/loopwire-key" >/dev/null || {
  echo "verify-scripts: matrix VM evidence collector did not forward identity files" >&2
  exit 1
}
matrix_release_dry_run="$(
  bash scripts/collect-vm-matrix-evidence.sh \
    --plan "$matrix_plan" \
    --published-release-dir /guest/release \
    --published-release-tag v0.1.0 \
    --release-public-key /guest/release-public.pem \
    --require-published-release
)"
printf '%s\n' "$matrix_release_dry_run" | grep -F -- "--require-published-release" >/dev/null || {
  echo "verify-scripts: matrix VM evidence collector did not forward published release strictness" >&2
  exit 1
}
printf '%s\n' "$matrix_release_dry_run" | grep -F -- "--published-release-tag v0.1.0" >/dev/null || {
  echo "verify-scripts: matrix VM evidence collector did not forward the published release tag" >&2
  exit 1
}
matrix_github_release_dry_run="$(
  bash scripts/collect-vm-matrix-evidence.sh \
    --plan "$matrix_plan" \
    --published-release-repo sandwichfarm/loopwire \
    --published-release-tag v0.1.0 \
    --release-public-key /guest/release-public.pem \
    --require-published-release \
    --require-github-release-source
)"
printf '%s\n' "$matrix_github_release_dry_run" | grep -F -- "--published-release-repo sandwichfarm/loopwire" >/dev/null || {
  echo "verify-scripts: matrix VM evidence collector did not forward GitHub release coordinates" >&2
  exit 1
}
printf '%s\n' "$matrix_github_release_dry_run" | grep -F -- "--require-github-release-source" >/dev/null || {
  echo "verify-scripts: matrix VM evidence collector did not forward GitHub release source strictness" >&2
  exit 1
}
if bash scripts/collect-vm-matrix-evidence.sh \
  --plan "$matrix_plan" \
  --require-all-targets >/dev/null 2>&1; then
  echo "verify-scripts: matrix VM evidence collector accepted incomplete all-target plan" >&2
  exit 1
fi
matrix_all_plan="$tmp_dir/vm-ssh-all-targets.tsv"
bash scripts/vm-matrix.sh render-ssh-plan --all --start-port 2600 >"$matrix_all_plan"
matrix_all_dry_run="$(bash scripts/collect-vm-matrix-evidence.sh --plan "$matrix_all_plan" --require-all-targets)"
printf '%s\n' "$matrix_all_dry_run" | grep -F "Require all targets: true" >/dev/null || {
  echo "verify-scripts: matrix VM evidence collector did not report all-target strictness" >&2
  exit 1
}
printf '%s\n' "$matrix_all_dry_run" | grep -F "Dry run complete for " >/dev/null || {
  echo "verify-scripts: matrix VM evidence collector did not accept all-target plan" >&2
  exit 1
}

fake_bin="$tmp_dir/fake-bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${FAKE_VM_SSH_LOG:?}"
FAKE_SSH
cat >"$fake_bin/scp" <<'FAKE_SCP'
#!/usr/bin/env bash
set -euo pipefail
dest="${@: -1}"
dest="${dest%/}"
mkdir -p "$dest"
cp -R "${FAKE_VM_EVIDENCE_SOURCE:?}"/. "$dest"/
FAKE_SCP
chmod 0755 "$fake_bin/ssh" "$fake_bin/scp"

if PATH="$fake_bin:$PATH" \
  FAKE_VM_SSH_LOG="$tmp_dir/strict-matrix-ssh.log" \
  FAKE_VM_EVIDENCE_SOURCE="$evidence_dir" \
  bash scripts/collect-vm-matrix-evidence.sh \
    --plan "$matrix_plan" \
    --require-all-targets \
    --execute >/dev/null 2>&1; then
  echo "verify-scripts: strict matrix VM collector executed an incomplete plan" >&2
  exit 1
fi
if [ -e "$tmp_dir/strict-matrix-ssh.log" ]; then
  echo "verify-scripts: strict matrix VM collector invoked SSH before all-target validation" >&2
  exit 1
fi

copied_evidence_dir="$tmp_dir/copied-vm-evidence/arch-hyprland-pipewire"
PATH="$fake_bin:$PATH" \
FAKE_VM_SSH_LOG="$tmp_dir/fake-ssh.log" \
FAKE_VM_EVIDENCE_SOURCE="$evidence_dir" \
  bash scripts/collect-vm-evidence-ssh.sh \
    --target arch-hyprland-pipewire \
    --host 127.0.0.1 \
    --local-output-dir "$copied_evidence_dir" \
    --execute >/dev/null
[ -s "$copied_evidence_dir/detect-audio.json" ] || {
  echo "verify-scripts: collect-vm-evidence-ssh did not copy evidence" >&2
  exit 1
}
[ -s "$tmp_dir/fake-ssh.log" ] || {
  echo "verify-scripts: collect-vm-evidence-ssh did not invoke ssh" >&2
  exit 1
}

matrix_execute_plan="$tmp_dir/vm-matrix-execute-plan.tsv"
matrix_copied_evidence_dir="$tmp_dir/copied-vm-matrix-evidence/arch-hyprland-pipewire"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "arch-hyprland-pipewire" \
  "127.0.0.1" \
  "2222" \
  "loopwire" \
  "-" \
  "5199" \
  "-" \
  "$matrix_copied_evidence_dir" >"$matrix_execute_plan"
PATH="$fake_bin:$PATH" \
FAKE_VM_SSH_LOG="$tmp_dir/fake-matrix-ssh.log" \
FAKE_VM_EVIDENCE_SOURCE="$evidence_dir" \
  bash scripts/collect-vm-matrix-evidence.sh \
    --plan "$matrix_execute_plan" \
    --execute >/dev/null
[ -s "$matrix_copied_evidence_dir/detect-audio.json" ] || {
  echo "verify-scripts: collect-vm-matrix-evidence did not copy evidence" >&2
  exit 1
}
[ -s "$tmp_dir/fake-matrix-ssh.log" ] || {
  echo "verify-scripts: collect-vm-matrix-evidence did not invoke ssh" >&2
  exit 1
}

failed_evidence_dir="$tmp_dir/vm-evidence-failed"
cp -R "$evidence_dir" "$failed_evidence_dir"
node -e '
const fs = require("node:fs");
const path = process.argv[1];
const rows = fs.readFileSync(path, "utf8").split(/\r?\n/).map((line) => {
  if (!line.startsWith("detect-audio\t")) {
    return line;
  }

  const cells = line.split("\t");
  cells[1] = "1";
  return cells.join("\t");
});
fs.writeFileSync(path, rows.join("\n"));
' "$failed_evidence_dir/command-results.tsv"
if bash scripts/verify-vm-evidence.sh --target arch-hyprland-pipewire --evidence-dir "$failed_evidence_dir" >/dev/null 2>&1; then
  echo "verify-scripts: verify-vm-evidence accepted a failed detect-audio command" >&2
  exit 1
fi
failed_support_bundle_dir="$tmp_dir/vm-evidence-failed-support-bundle"
cp -R "$evidence_dir" "$failed_support_bundle_dir"
node -e '
const fs = require("node:fs");
const path = process.argv[1];
const rows = fs.readFileSync(path, "utf8").split(/\r?\n/).map((line) => {
  if (!line.startsWith("ct-host-check\t")) {
    return line;
  }

  const cells = line.split("\t");
  cells[1] = "1";
  return cells.join("\t");
});
fs.writeFileSync(path, rows.join("\n"));
' "$failed_support_bundle_dir/support-bundle/command-results.tsv"
if bash scripts/verify-vm-evidence.sh \
  --target arch-hyprland-pipewire \
  --evidence-dir "$failed_support_bundle_dir" >/dev/null 2>&1; then
  echo "verify-scripts: verify-vm-evidence accepted a failed nested support-bundle command" >&2
  exit 1
fi
failed_matrix_copy="$tmp_dir/support-matrix-failed.md"
cp apps/docs/docs/guide/support-matrix.md "$failed_matrix_copy"
if node scripts/promote-vm-evidence.mjs \
  --target arch-hyprland-pipewire \
  --evidence-dir "$failed_evidence_dir" \
  --matrix "$failed_matrix_copy" \
  --dry-run >/dev/null 2>&1; then
  echo "verify-scripts: promote-vm-evidence accepted failed VM evidence" >&2
  exit 1
fi

wrong_environment_dir="$tmp_dir/vm-evidence-wrong-environment"
cp -R "$evidence_dir" "$wrong_environment_dir"
node -e '
const fs = require("node:fs");
const path = process.argv[1];
const manifest = JSON.parse(fs.readFileSync(path, "utf8"));
manifest.observed.desktop = "GNOME";
fs.writeFileSync(path, `${JSON.stringify(manifest, null, 2)}\n`);
' "$wrong_environment_dir/environment.json"
if bash scripts/verify-vm-evidence.sh \
  --target arch-hyprland-pipewire \
  --evidence-dir "$wrong_environment_dir" >/dev/null 2>&1; then
  echo "verify-scripts: verify-vm-evidence accepted mismatched guest environment" >&2
  exit 1
fi

wrong_audio_dir="$tmp_dir/vm-evidence-wrong-audio"
cp -R "$evidence_dir" "$wrong_audio_dir"
printf '%s\n' '{"platform":"linux","reports":[{"kind":"pipewire","availability":"unavailable"}]}' \
  >"$wrong_audio_dir/detect-audio.json"
if bash scripts/verify-vm-evidence.sh \
  --target arch-hyprland-pipewire \
  --evidence-dir "$wrong_audio_dir" >/dev/null 2>&1; then
  echo "verify-scripts: verify-vm-evidence accepted unavailable target audio backend" >&2
  exit 1
fi
