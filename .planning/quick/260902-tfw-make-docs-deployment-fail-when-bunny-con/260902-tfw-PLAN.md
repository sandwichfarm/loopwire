---
quick_id: 260902-tfw
status: in_progress
issue: 24
---

# Fail closed when production docs cannot deploy

1. Change the Bunny deployment job so missing required configuration exits non-zero instead of marking uploads as skipped.
2. Lock the fail-closed behavior into workflow contract checks and document the operator-visible failure semantics.
3. Run focused workflow/docs validation, then verify the remaining live-site blocker explicitly.
