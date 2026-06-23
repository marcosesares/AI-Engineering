# Schema — scan-ledger.json

Durable, **repo-scoped** coverage record for [[De-slop scan]] (`/e2e-deslop`). Sibling to `queue.json` at `.e2e-engineering/scan-ledger.json`. **Does NOT rot or reset per Task** (unlike `codebase-map.md`/`research.md`). Sole writer = the `/e2e-deslop` orchestrator. One entry per [[scan area]].

```json
{
  "version": 1,
  "areas": {
    "<area key — ARCHITECTURE.md §1 module name, or top-level source subtree path>": {
      "scannedAtCommit": "string — hash over the area's file subtree at last scan",
      "verdict": "candidate | clean | accepted",
      "candidateManifestPath": "string | null — relative path to the area's refactor-candidate manifest when verdict=candidate; null for clean/accepted",
      "scannedAt": "string — ISO date of the last scan (human-readable; do not use for eligibility)"
    }
  }
}
```

## Eligibility (scanned-since-change)
An area is **eligible to scan** when ANY holds:
- absent from `areas`, OR
- its current subtree hash ≠ `scannedAtCommit` (files changed since last scan), OR
- `verdict: candidate` and the candidates were not yet actioned into refactor Tasks.

An area is **muted** when `verdict: accepted` (human "won't-fix") — skipped until a human manually reopens it (deletes the entry or flips the verdict). Change-detection still applies on reopen.

## Invariants
- **Durable + repo-scoped.** Never written under a Task root; never reset on new Task. Lives beside `queue.json`.
- **Sole writer = `/e2e-deslop`.** Scouts return [[refactor-candidate manifest]]s; the orchestrator alone writes ledger entries (`verdict: candidate` when a manifest has ≥1 candidate, `verdict: clean` when none).
- `verdict: accepted` is set ONLY by human action (a de-slop run never writes `accepted`).
- `scannedAtCommit` is the change-detection key; `scannedAt` is informational only.
- Eligibility is computed fresh each run from current subtree hashes — a permanent "scanned" latch is forbidden (it would go blind to re-rot).
