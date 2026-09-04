---
quick_id: 260902-tfw
status: complete
issue: 24
implementation_commit: 2d1e697
---

# Summary

The production docs workflow now fails with an explicit error when the Bunny storage zone or access key is missing.
Upload and deployment-manifest steps are unconditional after that guard, so a successful deployment job can no longer
mean that the site was only built while publication was skipped. Operator documentation and workflow contract checks
cover the new behavior.

Focused validation passed: the workflow parses as YAML, direct fail-closed contract assertions pass, `pnpm
verify:docs` passes, and `git diff --check` passes. The broader workflow verifier is blocked by the pre-existing invalid
`awk` expression `node scripts[/]verify-vm-evidence-archive-manifest[.]mjs` on current `master`. Full `pnpm check` is
also blocked by the user's existing signing-key edit causing `verify:scripts` to report that the generated private-key
path is missing.

The live site remains blocked on operator-owned Bunny credentials. Repository and `docs-production` environment checks
found no `BUNNY_STORAGE_ZONE`, `BUNNY_STORAGE_ENDPOINT`, or `BUNNY_ACCESS_KEY`; `https://loopwire.app` still returns
HTTP 404 from Bunny CDN.
