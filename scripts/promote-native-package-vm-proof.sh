#!/usr/bin/env bash
set -euo pipefail

git_head=""
evidence_root="${LOOPWIRE_NATIVE_VM_ROOT:-.vm/native-packages}/evidence"
output_root="vm/native-package-proof"

usage() {
  cat <<'USAGE'
Promote a review-safe subset of already verified native-package VM proof.

Usage:
  promote-native-package-vm-proof.sh --git-head COMMIT [--evidence-root DIR] [--output-root DIR]

The raw package, command transcript, console log, disks, and SSH state remain under ignored .vm state. The promoted
snapshot keeps the image/package hashes, guest identity, installed metadata/files, runtime outputs, GUI window proof,
and uninstall result required for review. It never substitutes for the full raw proof verifier.
USAGE
}

fail() {
  echo "promote-native-package-vm-proof: $*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --) shift ;;
    --git-head) git_head="${2:?missing value for --git-head}"; shift 2 ;;
    --evidence-root) evidence_root="${2:?missing value for --evidence-root}"; shift 2 ;;
    --output-root) output_root="${2:?missing value for --output-root}"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[[ "$git_head" =~ ^[0-9a-f]{40}$ ]] || fail "--git-head must be a full lowercase commit hash"
case "$output_root" in
  vm/native-package-proof | vm/native-package-proof/*) ;;
  *) fail "--output-root must stay below vm/native-package-proof" ;;
esac

targets=(ubuntu-24.04 debian-13 fedora-44 opensuse-tumbleweed)
allowlist=(
  background-help.txt
  detect-audio.json
  dsp-provider-help.txt
  git-head.txt
  gui-launch-status.txt
  gui-ldd.txt
  gui-window-ids.txt
  gui-window-names.txt
  image.tsv
  jack-provider-help.txt
  os-release
  package-files.txt
  package-metadata.tsv
  summary.tsv
  uname.txt
  uninstall-status.txt
  virtualization.txt
)

mkdir -p "$output_root"
for target in "${targets[@]}"; do
  source_dir="$evidence_root/$target/$git_head"
  [ -d "$source_dir" ] || fail "missing raw evidence: $source_dir"
  node scripts/verify-native-package-vm-proof.mjs \
    --target "$target" --evidence-dir "$source_dir" --git-head "$git_head" >/dev/null
  target_dir="$output_root/$target"
  mkdir -p "$target_dir"
  for file in "${allowlist[@]}"; do
    [ -f "$source_dir/$file" ] || fail "$target raw evidence is missing $file"
    install -m 0644 "$source_dir/$file" "$target_dir/$file"
  done
  package_name="$(awk -F '\t' '$1 == "package" { print $2 }' "$source_dir/summary.tsv")"
  package_sha="$(awk -F '\t' '$1 == "package_sha256" { print $2 }' "$source_dir/summary.tsv")"
  printf '%s  %s\n' "$package_sha" "$package_name" >"$target_dir/package.sha256"
done

cat >"$output_root/README.md" <<EOF
# Native package VM proof

This review snapshot was promoted only after the full raw proof verifier passed for all four targets.

- Tested commit: \`$git_head\`
- Raw proof location: ignored \`.vm/native-packages/evidence/<target>/$git_head/\`
- Full verifier: \`pnpm verify:native-vm-proof -- --git-head $git_head\`
- Snapshot verifier: \`node scripts/verify-native-package-proof-snapshot.mjs\`

The snapshot deliberately excludes VM disks, SSH state, package binaries, serial consoles, and full package-manager
transcripts. Every target directory retains the official image URL/digest, package filename/digest, guest OS and KVM
identity, installed metadata/files, packaged command output, ELF linkage, X11 application-window proof, and uninstall
result. Package binaries are reproducibly rebuilt from the canonical release tarball and are not committed.
EOF

node scripts/verify-native-package-proof-snapshot.mjs --root "$output_root"
echo "Promoted native package VM proof snapshot: $output_root"
