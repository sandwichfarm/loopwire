#!/usr/bin/env bash
# Entrypoint for protected GitHub release publication and metadata maintenance.
set -euo pipefail

fail() { printf 'publish-apt-workflow: %s\n' "$*" >&2; exit 1; }
for name in APT_REPOSITORY_URL APT_REPOSITORY_HOST APT_REPOSITORY_ROOT APT_SIGNING_FINGERPRINT \
  APT_SSH_PRIVATE_KEY APT_SSH_KNOWN_HOSTS APT_SIGNING_KEY RUNNER_TEMP GITHUB_REPOSITORY GITHUB_SERVER_URL GITHUB_RUN_ID; do
  [ -n "${!name:-}" ] || fail "missing configuration: $name"
done
operation="${OPERATION:-refresh}"
case "$operation" in
  publish) [[ "${RELEASE_TAG:-}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "publish requires a stable vX.Y.Z release tag" ;;
  refresh) ;;
  rollback) [[ "${ROLLBACK_REVISION:-}" =~ ^[a-f0-9]{64}$ ]] || fail "rollback requires a retained revision SHA-256" ;;
  *) fail "unknown operation" ;;
esac
[[ "$APT_SIGNING_FINGERPRINT" =~ ^[A-F0-9]{40}$ ]] || fail "signing fingerprint must be complete uppercase hexadecimal"
[[ "${APT_SSH_PORT:-22}" =~ ^[0-9]+$ ]] || fail "SSH port must be numeric"
python3 - "$APT_REPOSITORY_URL" <<'PY'
import runpy, sys
validate = runpy.run_path('scripts/verify-apt-public.py')['validate_base_url']
try:
    validate(sys.argv[1])
except ValueError as error:
    sys.exit(f'publish-apt-workflow: {error}')
PY

work="$(mktemp -d "$RUNNER_TEMP/loopwire-apt.XXXXXX")"
cleanup() {
  gpgconf --homedir "$work/gnupg" --kill all >/dev/null 2>&1 || true
  rm -rf -- "$work"
}
trap cleanup EXIT
umask 077
mkdir "$work/gnupg"
printf '%s\n' "$APT_SSH_PRIVATE_KEY" >"$work/ssh-key"
printf '%s\n' "$APT_SSH_KNOWN_HOSTS" >"$work/known-hosts"
printf '%s\n' "$APT_SIGNING_KEY" >"$work/signing-key.asc"
gpg --no-options --batch --homedir "$work/gnupg" --import "$work/signing-key.asc"
gpg --no-options --batch --homedir "$work/gnupg" --armor --export "$APT_SIGNING_FINGERPRINT" >"$work/public-key.asc"
[ -s "$work/public-key.asc" ] || fail "configured key does not match the expected fingerprint"
sign_args=(--signing-key "$APT_SIGNING_FINGERPRINT" --gnupg-home "$work/gnupg" --valid-for-days 30)
if [ -n "${APT_SIGNING_PASSPHRASE:-}" ]; then
  printf '%s' "$APT_SIGNING_PASSPHRASE" >"$work/passphrase"
  sign_args+=(--passphrase-file "$work/passphrase")
fi
unset APT_SSH_PRIVATE_KEY APT_SSH_KNOWN_HOSTS APT_SIGNING_KEY APT_SIGNING_PASSPHRASE
transport=(--root "$APT_REPOSITORY_ROOT" --ssh "$APT_REPOSITORY_HOST" --ssh-port "${APT_SSH_PORT:-22}"
  --identity-file "$work/ssh-key" --known-hosts "$work/known-hosts"
  --public-key "$work/public-key.asc" --fingerprint "$APT_SIGNING_FINGERPRINT")

set +e
python3 scripts/publish-package-repository.py fetch "${transport[@]}" --output "$work/current"
fetch_status=$?
set -e
previous_args=()
if [ "$fetch_status" -eq 0 ]; then
  expected="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["revision"])' \
    "$work/current/repository-manifest.json")"
  previous_args=(--previous "$work/current")
elif [ "$fetch_status" -eq 3 ] && [ "$operation" = publish ]; then
  expected=empty
else
  fail "could not load the existing repository (status $fetch_status); no publication attempted"
fi

case "$operation" in
  publish)
    gh release view "$RELEASE_TAG" --repo "$GITHUB_REPOSITORY" --json isDraft,isPrerelease,tagName >"$work/release.json"
    python3 - "$work/release.json" "$RELEASE_TAG" <<'PY'
import json, sys
release = json.load(open(sys.argv[1]))
if release['isDraft'] or release['isPrerelease'] or release['tagName'] != sys.argv[2]:
    sys.exit('APT publication requires the requested published stable release')
PY
    mkdir "$work/release"
    gh release download "$RELEASE_TAG" --repo "$GITHUB_REPOSITORY" --dir "$work/release"
    release_commit="$(git rev-parse --verify "refs/tags/${RELEASE_TAG}^{commit}")"
    bash scripts/verify-release-signature.sh --release-dir "$work/release" --public-key packaging/release-signing-public.pem
    node scripts/release-asset-manifest.mjs verify --release-dir "$work/release" --tag "$RELEASE_TAG" \
      --git-head "$release_commit" --require-checksum --require-evidence
    python3 scripts/apt-repository.py build --release-dir "$work/release" --version "${RELEASE_TAG#v}" \
      --output "$work/candidate" "${sign_args[@]}" "${previous_args[@]}"
    ;;
  refresh)
    python3 scripts/apt-repository.py rollback --repository "$work/current" --output "$work/candidate" "${sign_args[@]}"
    ;;
  rollback)
    python3 scripts/publish-package-repository.py fetch "${transport[@]}" --revision "$ROLLBACK_REVISION" \
      --output "$work/rollback"
    python3 scripts/apt-repository.py rollback --repository "$work/rollback" --output "$work/candidate" "${sign_args[@]}"
    ;;
esac

mkdir -p dist/apt-publication
python3 scripts/publish-package-repository.py publish "${transport[@]}" --repository "$work/candidate" \
  --expected-revision "$expected" >dist/apt-publication/publication.json
python3 scripts/verify-apt-public.py --repository "$work/candidate" --public-key "$work/public-key.asc" \
  --fingerprint "$APT_SIGNING_FINGERPRINT" --base-url "$APT_REPOSITORY_URL" \
  --proof-url "$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" \
  --output dist/apt-publication/apt-channel.json
cp "$work/candidate/repository-manifest.json" dist/apt-publication/repository-manifest.json
printf 'APT repository published and verified; activation record is in the workflow artifact.\n'
