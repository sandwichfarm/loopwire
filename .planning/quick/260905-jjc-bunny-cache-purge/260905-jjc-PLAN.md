---
status: verified
---

# Purge the docs CDN after deployment

Tracking: https://github.com/sandwichfarm/loopwire/issues/43

1. Extend the existing uploader with an explicit --purge-cache option, enabled by Deploy Docs. Require a separate
   Bunny account API key and numeric Pull Zone ID before uploads. Preserve storage-only and dry-run CLI behavior.
2. After all uploads and manifest generation succeed, POST to the fixed Bunny purge endpoint using a private stdin
   header. Keep credentials out of arguments/logs, bound network waits/retries, and reject errors without fake success.
3. Update guided GitHub setup and documentation for BUNNY_API_KEY secret and BUNNY_PULL_ZONE_ID variable. The legacy
   upload-only rehearsal helper remains separate; no actual credentials are requested through chat or changed here.
4. Add regression tests for ordering, dry-run/no-purge, failed uploads/manifests, malformed/missing config, HTTP and
   network failures, and secret handling. Run relevant script/workflow/setup/docs checks and open a focused PR.

This branch starts from current master independently of pending CI-filter PR #42. Reuse deploy-docs-bunny.sh so #42's
existing deployment path filters cover the feature. No app/backend/package/dependency changes or actual cache purge.
The live API call remains dependent on the operator supplying the account key and zone ID.
