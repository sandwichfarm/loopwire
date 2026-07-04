#!/usr/bin/env bash
set -euo pipefail

tag=""
evidence_root="${LOOPWIRE_VM_EVIDENCE_ROOT:-.vm/evidence}"
output=""
require_published_release="false"
dry_run="false"
all_targets="false"
targets=()
source_date_epoch="${SOURCE_DATE_EPOCH:-0}"

usage() {
  cat <<'USAGE'
Package verified Loopwire VM evidence for final release proof.

Usage:
  package-vm-evidence.sh --tag vX.Y.Z [--evidence-root DIR] [--output FILE]
                         [--target TARGET ... | --all]
                         [--require-published-release] [--dry-run]

The archive layout is:
  vm-evidence/<target>/...

When no --target is provided, every target from vm/targets.tsv is packaged. Every target bundle is verified with
scripts/verify-vm-evidence.sh before it is copied into the archive. Use --require-published-release for final release
archives so every VM bundle proves installed-release smoke from published artifacts. The completed archive is also
validated with scripts/extract-safe-tar.sh so final release proof will reject unsafe member paths before upload.

SOURCE_DATE_EPOCH controls tar metadata timestamps and defaults to 0.
USAGE
}

fail() {
  echo "package-vm-evidence: $*" >&2
  exit 1
}

target_ids() {
  awk -F '\t' 'NF && $1 !~ /^#/ { print $1 }' vm/targets.tsv
}

validate_tag() {
  local value="$1"
  local pattern='^v[0-9]+[.][0-9]+[.][0-9]+([.-][0-9A-Za-z][0-9A-Za-z.-]*)?$'

  [[ "$value" =~ $pattern ]] || fail "tag must be v-prefixed semver without path separators: $value"
}

reject_unsafe_value() {
  local value="$1"
  local label="$2"

  case "$value" in
    *$'\n'* | *$'\r'*)
      fail "$label must be a single safe value"
      ;;
  esac
}

target_exists() {
  local target="$1"

  target_ids | grep -Fxq "$target"
}

quote_command() {
  local quoted=()
  local arg

  for arg in "$@"; do
    quoted+=("$(printf '%q' "$arg")")
  done

  printf '%s\n' "${quoted[*]}"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --tag)
      tag="${2:?missing value for --tag}"
      shift 2
      ;;
    --evidence-root)
      evidence_root="${2:?missing value for --evidence-root}"
      shift 2
      ;;
    --output)
      output="${2:?missing value for --output}"
      shift 2
      ;;
    --target)
      targets+=("${2:?missing value for --target}")
      shift 2
      ;;
    --all)
      all_targets="true"
      shift
      ;;
    --require-published-release)
      require_published_release="true"
      shift
      ;;
    --dry-run)
      dry_run="true"
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

[ -n "$tag" ] || fail "missing --tag"
validate_tag "$tag"
reject_unsafe_value "$evidence_root" "evidence root"

case "$source_date_epoch" in
  *[!0-9]* | "")
    fail "SOURCE_DATE_EPOCH must be an integer Unix timestamp"
    ;;
esac

if [ "$all_targets" = "true" ] && [ "${#targets[@]}" -gt 0 ]; then
  fail "use either --all or --target, not both"
fi

if [ "${#targets[@]}" -eq 0 ]; then
  while IFS= read -r target; do
    [ -n "$target" ] || continue
    targets+=("$target")
  done < <(target_ids)
fi

if [ "${#targets[@]}" -eq 0 ]; then
  fail "no VM targets selected"
fi

if [ -z "$output" ]; then
  output="dist/release/loopwire-vm-evidence-${tag}.tar.gz"
fi
reject_unsafe_value "$output" "output path"

verify_flags=()
if [ "$require_published_release" = "true" ]; then
  verify_flags+=(--require-published-release)
fi

for target in "${targets[@]}"; do
  target_exists "$target" || fail "unknown VM target: $target"
done

if [ "$dry_run" = "true" ]; then
  for target in "${targets[@]}"; do
    quote_command \
      bash scripts/verify-vm-evidence.sh \
      --target "$target" \
      --evidence-dir "${evidence_root%/}/${target}" \
      "${verify_flags[@]}"
  done
  printf 'dry-run: would write VM evidence archive: %s\n' "$output"
  exit 0
fi

[ -d "$evidence_root" ] || fail "missing evidence root: $evidence_root"

tmp_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir -p "$tmp_dir/vm-evidence" "$(dirname "$output")"

for target in "${targets[@]}"; do
  source_dir="${evidence_root%/}/${target}"
  bash scripts/verify-vm-evidence.sh \
    --target "$target" \
    --evidence-dir "$source_dir" \
    "${verify_flags[@]}"
  mkdir -p "$tmp_dir/vm-evidence/$target"
  cp -R "$source_dir"/. "$tmp_dir/vm-evidence/$target"/
done

tar \
  --sort=name \
  --mtime="@${source_date_epoch}" \
  --owner=0 \
  --group=0 \
  --numeric-owner \
  -czf "$output" \
  -C "$tmp_dir" \
  vm-evidence

bash scripts/extract-safe-tar.sh \
  --archive "$output" \
  --output-dir "$tmp_dir/archive-smoke" \
  --label "VM evidence archive" >/dev/null

for target in "${targets[@]}"; do
  tar -tzf "$output" "vm-evidence/${target}/command-results.tsv" >/dev/null || \
    fail "archive missing target command ledger: $target"
done

printf 'Wrote VM evidence archive: %s\n' "$output"
