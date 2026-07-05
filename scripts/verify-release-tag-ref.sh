#!/usr/bin/env bash
set -euo pipefail

repo=""
tag=""
git_head=""

usage() {
  cat <<'USAGE'
Verify that a GitHub release tag ref resolves to an expected commit.

Usage:
  verify-release-tag-ref.sh --repo OWNER/REPO --tag vX.Y.Z --git-head SHA

The verifier accepts lightweight tags and annotated tags. Annotated tags are dereferenced once and must point at a
commit object. The command uses `gh api` and requires GitHub credentials with repository read access.
USAGE
}

fail() {
  echo "verify-release-tag-ref: $*" >&2
  exit 1
}

validate_repo() {
  local pattern='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'

  [[ "$repo" =~ $pattern ]] || fail "repository must use OWNER/REPO without URLs, spaces, or extra path segments: $repo"
}

validate_release_tag() {
  local pattern='^v[0-9]+[.][0-9]+[.][0-9]+([.-][0-9A-Za-z][0-9A-Za-z.-]*)?$'

  [[ "$tag" =~ $pattern ]] || fail "tag must be v-prefixed semver without path separators: $tag"
}

validate_git_head() {
  [[ "$git_head" =~ ^[0-9a-fA-F]{40}$ ]] || fail "git head must be a 40-character SHA: $git_head"
}

resolve_ref_object() {
  local ref_json="$1"

  node - "$ref_json" <<'NODE'
const raw = process.argv[2];
const ref = JSON.parse(raw);
const object = ref?.object;
if (!object || typeof object.sha !== "string" || typeof object.type !== "string") {
  console.error("release tag ref did not include object.type and object.sha");
  process.exit(1);
}
if (object.type === "commit") {
  console.log(`commit\t${object.sha}`);
} else if (object.type === "tag") {
  console.log(`tag\t${object.sha}`);
} else {
  console.error(`release tag ref points at unsupported object type: ${object.type}`);
  process.exit(1);
}
NODE
}

resolve_annotated_tag_object() {
  local tag_json="$1"

  node - "$tag_json" <<'NODE'
const raw = process.argv[2];
const tag = JSON.parse(raw);
const object = tag?.object;
if (!object || typeof object.sha !== "string" || typeof object.type !== "string") {
  console.error("annotated release tag did not include target object.type and object.sha");
  process.exit(1);
}
if (object.type !== "commit") {
  console.error(`annotated release tag points at unsupported object type: ${object.type}`);
  process.exit(1);
}
console.log(object.sha);
NODE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --)
      shift
      ;;
    --repo)
      repo="${2:?missing value for --repo}"
      shift 2
      ;;
    --tag)
      tag="${2:?missing value for --tag}"
      shift 2
      ;;
    --git-head)
      git_head="${2:?missing value for --git-head}"
      shift 2
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

[ -n "$repo" ] || fail "missing --repo OWNER/REPO"
[ -n "$tag" ] || fail "missing --tag vX.Y.Z"
[ -n "$git_head" ] || fail "missing --git-head SHA"
validate_repo
validate_release_tag
validate_git_head

command -v gh >/dev/null 2>&1 || fail "gh is required to verify the release tag ref"

ref_json="$(gh api "repos/${repo}/git/ref/tags/${tag}")"
resolved="$(resolve_ref_object "$ref_json")"

case "$resolved" in
  commit$'\t'*)
    resolved="${resolved#*$'\t'}"
    ;;
  tag$'\t'*)
    tag_json="$(gh api "repos/${repo}/git/tags/${resolved#*$'\t'}")"
    resolved="$(resolve_annotated_tag_object "$tag_json")"
    ;;
  *)
    fail "release tag ref parser returned unexpected output: $resolved"
    ;;
esac

if [ "${resolved,,}" != "${git_head,,}" ]; then
  fail "release tag ref resolves to ${resolved}, not expected commit ${git_head}"
fi

echo "release tag ref verified: ${tag} -> ${resolved}"
