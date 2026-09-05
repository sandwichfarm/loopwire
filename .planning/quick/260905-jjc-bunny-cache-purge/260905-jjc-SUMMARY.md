---
status: verified
issue: 43
---

# Purge the docs CDN after deployment

Tracking: https://github.com/sandwichfarm/loopwire/issues/43

## Result

The existing uploader accepts `--purge-cache`; Deploy Docs always enables it. Purge configuration is validated before
uploads. After all files and the local deployment manifest are written successfully, the uploader requests a full
CDN Pull Zone purge. It accepts only HTTP 2xx and hides response bodies and raw transport errors. The account key is
passed through stdin, curl config files and redirects are disabled, and connection/request/retry waits are bounded.

The guarded setup helper requires `BUNNY_API_KEY` and `BUNNY_PULL_ZONE_ID` in deploy and final scopes, with hidden
prompts and exact stdin transport. The signed-int64 ID check preserves leading zeros without integer overflow.
Existing storage-only CLI behavior, storage-password handling, and legacy Unix setup/config templates are unchanged.
No dependencies or audio/backend/UI behavior changed. Existing upload and setup machinery was reused.

Docs explain the new settings, environment precedence, repository-only setup checks, error recovery, full-zone purge
scope, and the browser-cache limitation. The docs contract no longer requires obsolete skip-on-missing-secret prose.

## Validation

- Existing setup baseline: 11 transport cases passed before edits. New required-name assertions first failed because
  `BUNNY_PULL_ZONE_ID` was missing; the expanded 14-case suite now passes.
- `node scripts/test-docs-cache-purge.mjs`: first failed on unknown `--purge-cache`, then passed. Covers upload/manifest
  ordering, dry run, legacy upload-only use, required config, control characters, int64 bounds and leading zeros,
  prefix-independent full-zone purge, response errors, bounded curl flags, and account-key secrecy.
- Independent real-curl loopback checks passed for successful upload/purge, a 503-to-204 retry preserving the private
  header, rejected redirects, and hidden authentication-error bodies. Only local fixture servers were contacted.
- `node scripts/test-setup-github-actions.mjs`: all 14 cases passed, including both configuration scopes,
  stdin-only secret writes, control rejection, exact bytes, dry run, readback failure, and idempotent repeat setup.
- `bash scripts/verify-scripts.sh`: passed the full script regression suite.
- `bash scripts/verify-github-workflows.sh` and `bash scripts/verify-docs.sh`: passed.
- Node syntax checks, Bash syntax checks, actionlint on Deploy Docs, and ShellCheck on the uploader passed.
  ShellCheck ran from an existing offline container image because no host binary was installed.
- `pnpm lint`: workspace typechecks and Svelte checks passed with no errors or warnings.
- `pnpm build:web && pnpm verify:site`: production Astro/VitePress builds and combined site checks passed.
- `git diff --check` and the 150-character limit for added lines passed.

## Operator configuration and limits

In repository Settings → Environments → docs-production, add `BUNNY_API_KEY` as an environment secret and
`BUNNY_PULL_ZONE_ID` as an environment variable. Obtain the account key from
https://dash.bunny.net/account/api-key and the numeric CDN ID from the Pull Zone dashboard. Keep the existing
`BUNNY_ACCESS_KEY` storage password. The guided helper writes/checks repository settings; environment values override
matching repository settings and are not inspected by that helper.

No production credentials were read or changed, no Bunny API request was made, and no deployment was triggered.
Production purge acceptance remains an operator validation after setting the new values. Purging the full zone
does not clear browser caches or prove immediate refresh at every edge. Native app/audio tests were not needed
for this deployment-only change.
