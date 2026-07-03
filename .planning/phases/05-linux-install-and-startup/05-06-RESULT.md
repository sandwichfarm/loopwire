# Phase 5 Result: Signed Release Manifest Verification

**Completed:** 2026-07-03
**Requirements:** LINUX-03, QUAL-03, QUAL-05 support path

## Delivered

- Added `scripts/sign-release-artifacts.sh`.
- Added `scripts/verify-release-signature.sh`.
- Updated release staging to sign `SHA256SUMS` when a private key is provided.
- Updated the installer to require signed manifest verification by default.
- Updated install and release smoke tests to use temporary RSA signing keys.
- Updated the release workflow to require `LOOPWIRE_RELEASE_PRIVATE_KEY`.
- Updated the GitHub secret helper to set `LOOPWIRE_RELEASE_PRIVATE_KEY`.
- Updated release, install, and packaging docs.

## Boundaries

- No real project release key was generated or committed.
- No private key was committed.
- No GitHub Release was created.
- Public installer claims still require a committed project public key and a successful tagged release run.

## Next Phase 5 Work

- Generate the real release signing key pair outside the repo.
- Commit only `packaging/release-signing-public.pem`.
- Configure the private key through `scripts/setup-github-secrets.sh`.
- Run the release workflow on a protected tag.
