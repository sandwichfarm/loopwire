#!/usr/bin/env bash
set -euo pipefail

bash -n \
  scripts/install.sh \
  scripts/package-release.sh \
  scripts/sign-release-artifacts.sh \
  scripts/verify-release-signature.sh \
  scripts/stage-release-artifacts.sh \
  scripts/deploy-docs-bunny.sh \
  scripts/prepare-release-signing-key.sh \
  scripts/render-aur-pkgbuild.sh \
  scripts/setup-github-secrets.sh \
  scripts/ct-host-check.sh \
  scripts/vm-matrix.sh \
  scripts/verify-github-workflows.sh \
  scripts/manage-autostart.sh \
  scripts/verify-runtime.sh \
  scripts/verify-autostart.sh \
  scripts/verify-install.sh \
  scripts/verify-release-artifacts.sh \
  scripts/verify-release-readiness.sh \
  scripts/verify-published-release.sh \
  scripts/verify-vm-evidence.sh \
  scripts/collect-vm-evidence.sh \
  scripts/collect-vm-evidence-ssh.sh \
  scripts/verify-aur-package.sh \
  scripts/verify-packaging.sh \
  scripts/verify-docs.sh

node --check scripts/detect-audio-backends.mjs
node --check scripts/collect-release-evidence.mjs
node --check scripts/collect-support-bundle.mjs
node --check scripts/promote-vm-evidence.mjs
node --check scripts/restore-background.mjs
node --check scripts/verify-support-matrix.mjs
collect_evidence_help="$(node scripts/collect-release-evidence.mjs --help)"
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
const item = plan.find((entry) => entry.name === "published-release-smoke");
if (!item || item.required !== false) process.exit(1);
' || {
  echo "verify-scripts: full release evidence plan should keep published-release smoke optional by default" >&2
  exit 1
}
collect_evidence_required_plan="$(
  node scripts/collect-release-evidence.mjs \
    --list-commands \
    --profile quick \
    --require-published-release \
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
node scripts/restore-background.mjs --help | grep -F -- "--retry-pending-ms" >/dev/null || {
  echo "verify-scripts: restore background help is missing pending retry options" >&2
  exit 1
}
if node scripts/restore-background.mjs --mode preview --retry-pending-ms 1 >/dev/null 2>&1; then
  echo "verify-scripts: restore background accepted pending retries outside live mode" >&2
  exit 1
fi
node scripts/collect-support-bundle.mjs --help >/dev/null
bash scripts/collect-vm-evidence.sh --help >/dev/null
bash scripts/collect-vm-evidence-ssh.sh --help >/dev/null
bash scripts/collect-vm-evidence-ssh.sh -- --target arch-hyprland-pipewire --host 127.0.0.1 >/dev/null
bash scripts/deploy-docs-bunny.sh --help >/dev/null
bash scripts/prepare-release-signing-key.sh --help >/dev/null
bash scripts/setup-github-secrets.sh --print-required >/dev/null
pnpm --filter @loopwire/core build >/dev/null
pnpm --filter @loopwire/audio-host build >/dev/null

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
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

vm_doctor_output="$(bash scripts/vm-matrix.sh doctor --target arch-hyprland-pipewire 2>&1 || true)"
vm_doctor_separator_output="$(bash scripts/vm-matrix.sh doctor -- --target arch-hyprland-pipewire 2>&1 || true)"
vm_nix_doctor_output="$(bash scripts/vm-matrix.sh doctor --target nixos-gnome-pipewire 2>&1 || true)"
vm_host_plan_output="$(bash scripts/vm-matrix.sh host-plan --target fedora-sway-pipewire)"
vm_launch_root="$tmp_dir/vm-launch-root"
vm_launch_output="$(
  LOOPWIRE_VM_ROOT="$vm_launch_root" \
    bash scripts/vm-matrix.sh launch --target arch-hyprland-pipewire --image /operator/images/arch.qcow2 --ssh-port 2322
)"
printf '%s\n' "$vm_doctor_output" | grep -F "target=arch-hyprland-pipewire" >/dev/null || {
  echo "verify-scripts: vm doctor target context missing" >&2
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
if bash scripts/vm-matrix.sh doctor --target not-a-target >/dev/null 2>&1; then
  echo "verify-scripts: vm doctor accepted an unknown target" >&2
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
printf '%s\n' "$vm_launch_output" | grep -F "Base image: /operator/images/arch.qcow2" >/dev/null || {
  echo "verify-scripts: vm launch dry-run did not print the operator image path" >&2
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
if bash scripts/vm-matrix.sh launch --target arch-hyprland-pipewire --image /operator/images/arch.qcow2 --ssh-port 70000 \
  >/dev/null 2>&1; then
  echo "verify-scripts: vm launch accepted an invalid SSH port" >&2
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
grep -F "sudo npm install -g pnpm@11.3.0" "$cloud_init_dir/debian-xfce-pulseaudio/guest-commands.sh" >/dev/null || {
  echo "verify-scripts: Debian cloud-init bootstrap does not install pnpm" >&2
  exit 1
}
grep -F "nix develop --command bash scripts/collect-vm-evidence.sh" \
  "$cloud_init_dir/nixos-gnome-pipewire/guest-commands.sh" >/dev/null || {
    echo "verify-scripts: NixOS cloud-init evidence collector does not use nix develop" >&2
    exit 1
  }
if bash scripts/vm-matrix.sh render-cloud-init --all --target arch-hyprland-pipewire >/dev/null 2>&1; then
  echo "verify-scripts: render-cloud-init accepted both --all and --target" >&2
  exit 1
fi
vm_verify_output="$(bash scripts/vm-matrix.sh verify-cloud-init)"
printf '%s\n' "$vm_verify_output" | grep -F "Verified rendered cloud-init assets for 7 VM target(s)." >/dev/null || {
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
printf '%s\n' "dry-run-placeholder" >"$tmp_secret_file"
docs_dist="$tmp_dir/docs-dist"
mkdir -p "$docs_dist/assets"
printf '%s\n' "<!doctype html><title>Loopwire</title>" >"$docs_dist/index.html"
printf '%s\n' "body{color:#111}" >"$docs_dist/assets/site.css"
bunny_dry_run="$(
  bash scripts/deploy-docs-bunny.sh \
    --dist "$docs_dist" \
    --storage-zone loopwire-docs \
    --storage-endpoint ny.storage.bunnycdn.com \
    --remote-prefix preview \
    --dry-run
)"
printf '%s\n' "$bunny_dry_run" | grep -F "would upload index.html -> https://ny.storage.bunnycdn.com/loopwire-docs/preview/index.html" >/dev/null || {
  echo "verify-scripts: Bunny docs deploy dry-run did not use the regional endpoint" >&2
  exit 1
}
printf '%s\n' "$bunny_dry_run" | grep -F "Dry run complete; 2 docs file(s) would be uploaded" >/dev/null || {
  echo "verify-scripts: Bunny docs deploy dry-run did not count files" >&2
  exit 1
}
bash scripts/setup-github-secrets.sh \
  --repo sandwichfarm/loopwire \
  --storage-zone loopwire-docs \
  --access-key dry-run-access-key \
  --storage-endpoint ny.storage.bunnycdn.com \
  --release-private-key-file "$tmp_secret_file" \
  --dry-run >/dev/null

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
if bash scripts/verify-release-readiness.sh -- \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --public-key "$public_key_file" \
  --skip-gh \
  --skip-tag >/dev/null 2>&1; then
  echo "verify-scripts: release readiness accepted candidate release notes by default" >&2
  exit 1
fi
bash scripts/verify-release-readiness.sh -- \
  --repo sandwichfarm/loopwire \
  --tag v0.1.0 \
  --public-key "$public_key_file" \
  --skip-gh \
  --skip-tag \
  --allow-candidate-notes >/dev/null
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
bash scripts/verify-published-release.sh \
  --release-dir "$published_release_dir" \
  --public-key "$public_key_file" \
  --prefix "$published_prefix" >/dev/null
if [ "$("$published_prefix/loopwire")" != "loopwire published verifier smoke" ]; then
  echo "verify-scripts: published release verifier did not install the expected binary" >&2
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
' "$support_dir/support-bundle.json" || {
  echo "verify-scripts: support bundle manifest shape invalid" >&2
  exit 1
}
host_name="$(node -e 'process.stdout.write(require("node:os").hostname())')"
if [ "${#host_name}" -ge 5 ] && grep -R "$host_name" "$support_dir" >/dev/null 2>&1; then
  echo "verify-scripts: support bundle leaked hostname" >&2
  exit 1
fi

evidence_dir="$tmp_dir/vm-evidence"
mkdir -p "$evidence_dir"
printf '%s\n' "pnpm check passed" >"$evidence_dir/pnpm-check.log"
printf '%s\n' "Loopwire desktop launch smoke passed: http://127.0.0.1:5181/" >"$evidence_dir/desktop-launch.log"
printf '%s\n' "audio host build passed" >"$evidence_dir/audio-host-build.log"
printf '%s\n' '{"platform":"linux","reports":[{"kind":"pipewire"}]}' >"$evidence_dir/detect-audio.json"
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
printf '%s\n' '{"kind":"loopwire.support-bundle","version":1,"redacted":true,"commands":[{"name":"detect-audio","exitCode":0}]}' \
  >"$evidence_dir/support-bundle/support-bundle.json"
printf '%s\n' 'name	exitCode	startedAt	finishedAt	log' \
  >"$evidence_dir/support-bundle/command-results.tsv"
printf '%s\n' "# Loopwire Support Bundle" >"$evidence_dir/support-bundle/notes.md"
node -e '
const fs = require("node:fs");
fs.writeFileSync(process.argv[1], Buffer.from([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00
]));
' "$evidence_dir/screenshot.png"
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
matrix_copy="$tmp_dir/support-matrix.md"
cp apps/docs/docs/guide/support-matrix.md "$matrix_copy"
promote_dry_run="$(
  node scripts/promote-vm-evidence.mjs \
    --target arch-hyprland-pipewire \
    --evidence-dir "$evidence_dir" \
    --matrix "$matrix_copy" \
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

copied_evidence_dir="$tmp_dir/copied-vm-evidence"
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
