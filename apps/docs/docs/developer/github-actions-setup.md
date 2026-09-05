# GitHub Actions Setup

This guide is for the release operator who owns the Loopwire repository and Bunny account. After completing it, the
repository has the public configuration and private credentials needed by the docs deployment and final-release proof
workflows.

The setup command runs through Node.js and GitHub CLI, so the same command works on Windows, macOS, and Linux.

## Prerequisites

1. Install the repository's pinned Node.js and pnpm versions.
2. Install GitHub CLI, then authenticate with an account that can manage Actions variables and secrets:

```bash
gh auth login
gh auth status
```

3. Make sure you can administer the target repository.
4. For final-release setup, generate a dedicated signing pair first:

```bash
pnpm release:prepare-key
```

Keep the private PEM outside the repository. The public PEM may remain in the committed packaging location.

## Run the guided setup

For docs deployment only:

```bash
pnpm setup:github -- --repo OWNER/REPO --scope deploy
```

For docs deployment plus final-release proof:

```bash
pnpm setup:github -- --repo OWNER/REPO --scope final
```

The command gathers and validates every answer before it contacts GitHub. It then performs a read-only authentication,
repository, variable, and secret preflight. Review the displayed names and type `APPLY` before any value is written.

## Values and where to find them

| Name | GitHub storage | Required | Where to find or generate it |
| --- | --- | --- | --- |
| `BUNNY_STORAGE_ZONE` | Actions variable | Deploy and final | Bunny dashboard → Storage → select the Loopwire zone. Copy the zone name shown at the top. |
| `BUNNY_STORAGE_ENDPOINT` | Actions variable | Deploy and final | Bunny dashboard → Storage → select the zone → FTP & API Access. Use the API hostname with `https://`. The global default is `https://storage.bunnycdn.com`. |
| `BUNNY_PULL_ZONE_HOSTNAME` | Actions variable | Final; optional for deploy smoke | Bunny dashboard → CDN → Pull Zones → select the Loopwire zone → Hostnames. Copy only the hostname, without a scheme or path. Skipping it in deploy scope leaves existing configuration unchanged. |
| `BUNNY_REMOTE_PREFIX` | Actions variable | Optional | Choose a relative storage subdirectory only when the site should not deploy at the storage-zone root. Skipping it leaves existing configuration unchanged; an unset value means the root. |
| `BUNNY_ACCESS_KEY` | Actions secret | Deploy and final | Bunny dashboard → Storage → select the Loopwire zone → FTP & API Access → Password. Use the storage-zone password, not the account API key. |
| `BUNNY_PULL_ZONE_ID` | Actions variable | Deploy and final | Numeric CDN Pull Zone ID; see below. |
| `BUNNY_API_KEY` | Actions secret | Deploy and final | Bunny account API key for CDN purges; see below. |
| `LOOPWIRE_RELEASE_PRIVATE_KEY` | Actions secret | Final | Generate the local PEM with `pnpm release:prepare-key`. At the prompt, enter its file path; do not paste it into a shell argument. |

Public configuration uses the GitHub `vars` context. Credentials and signing material use the `secrets` context. During
migration, workflows still fall back to older repository secrets when the matching Actions variable is absent.

### CDN purge configuration

Get `BUNNY_API_KEY` from the [Bunny account API Keys page](https://dash.bunny.net/account/api-key).
This is the account API key used by Bunny's [CDN purge API](https://bunny.net/docs/cdn/purge-cache).
Keep `BUNNY_ACCESS_KEY` as the separate storage-zone password; it cannot authorize the CDN management request.

Find `BUNNY_PULL_ZONE_ID` under Bunny dashboard → CDN → Pull Zones → select the zone serving the site.
Copy the numeric Pull Zone ID, not the Storage Zone ID or hostname. The helper accepts decimal digits representing
an integer from 1 through 9223372036854775807 and preserves entered digits. API keys must be a single header line
without ASCII control characters, including tabs, carriage returns, and newlines.

The guided helper writes **repository-level** Actions variables and secrets; its `--check` checks that scope only.
The `Deploy Docs` job runs in the **docs-production** environment. To configure just the two new settings there, open
repository Settings → Environments → docs-production. Add `BUNNY_API_KEY` under **Environment secrets** and
`BUNNY_PULL_ZONE_ID` under **Environment variables**. Existing storage settings remain in their current scope.
Environment settings take precedence over matching repository settings, so update stale environment values there
instead of relying on a repository-level setup run to replace them.

Production deployment requests a full Pull Zone purge after all uploads and manifest generation succeed.
This includes every path in that CDN zone, even when `BUNNY_REMOTE_PREFIX` selects a storage subdirectory.
Acceptance by the purge API does not invalidate copies already cached in browsers or prove immediate refresh on
every CDN edge. Browser caches continue to follow the site's HTTP cache headers.

## AUR publication environment

The manually dispatched `Publish AUR` workflow uses a separate GitHub environment named `aur`. Configure required
reviewers on that environment, then add one environment secret named `AUR_SSH_PRIVATE_KEY`. Use a dedicated
passphrase-free automation key whose public half is registered on the maintainer's AUR account; do not reuse the
interactive, passphrase-protected local key and never commit either private key.

```bash
gh api --method PUT repos/OWNER/REPO/environments/aur
gh secret set AUR_SSH_PRIVATE_KEY --repo OWNER/REPO --env aur < ~/.ssh/loopwire-aur-actions
```

The environment gate is the authority boundary: pull requests and ordinary pushes only build the recipes, while an
approved manual dispatch can publish `loopwire`, `loopwire-bin`, `loopwire-git`, or all three. Stable variants remain
bound to an already-public release tag; the VCS variant resolves the current protected default branch.

## Input integrity and secrecy

- The command never accepts sensitive values as CLI flags or environment variables.
- Prompt answers are never trimmed, quote-stripped, normalized, joined, or given an extra newline. Invalid values are
  rejected with an explanation instead of being rewritten.
- Both variables and secrets are sent to GitHub CLI through standard input, not command arguments.
- Sensitive terminal input is hidden.
- The release private key is read from a regular, non-symlink file and sent byte-for-byte. Native Node cryptography
  verifies that it parses and matches the selected public key before the first GitHub write.
- GitHub variables are read back and compared exactly after each write. GitHub does not expose secret values, so the
  command verifies their registered names instead.
- If a remote write fails, the command reports only the names successfully written before the failure. It never prints
  their values and does not attempt later names.

GitHub limits Actions secret values to 48 KB. Oversized input is rejected; it is never truncated.

## Rehearse without changing GitHub

Dry-run performs the full prompt and local validation flow but does not invoke GitHub CLI:

```bash
pnpm setup:github -- --repo OWNER/REPO --scope final --dry-run
```

The output lists only variable and secret names.

## Verify GitHub configuration

After setup, check required names and variable read access:

```bash
pnpm setup:github -- --repo OWNER/REPO --scope final --check
```

The check does not and cannot read secret values. It verifies required variables through GitHub's variable API and
required secrets through the names-only secret list.

The production `Deploy Docs` workflow fails before upload when `BUNNY_STORAGE_ZONE`, `BUNNY_ACCESS_KEY`,
`BUNNY_API_KEY`, or `BUNNY_PULL_ZONE_ID` is absent. Malformed purge settings also fail before any upload.
A successful deployment requires every upload and acceptance of the CDN purge request. Configure
`BUNNY_PULL_ZONE_HOSTNAME` as well to make the workflow probe the public HTTPS site afterward; without it, the live
HTTP verification step is skipped. A failed purge leaves uploaded storage objects in place; correct the API key,
zone ID, or connectivity problem and rerun the deployment.

## Recover from a failed write

All local validation and GitHub access preflight happens before mutation, but GitHub does not provide a transaction
that spans several variable and secret writes. If a later write fails, read the names in the failure message, correct
the cause, and run the complete setup command again. Re-running is safe: each named value is replaced, never appended.

Common causes are insufficient repository administration permission, an expired GitHub CLI login, or a Bunny value
copied from the wrong dashboard field.
