# Schema — resume.json

Machine-readable resume pointers for one Task. **caveman:ultra field values only — no narrative** (ADR 0022: NOT a handoff doc, NOT a context checkpoint). Lives at Task root: `.e2e-engineering/tasks/<id>/resume.json`. Sole writer = orchestrator. Written **write-ahead** — BEFORE each phase transition and before every long-running gate step; updated after completion. Read at flight Step 2 before anything else.

Stale on resume is SAFE by construction: values are only written before an action, so a stale value can only cause an already-done step to be re-verified — never skipped unsafely.

```json
{
  "taskId": "payments-monetization",
  "headSha": "f9cc528",
  "phase": "dispatch",              // dispatch | review | merge | gate5
  "readySet": ["repair-webhook-source-ip-review-findings"],
  "dispatched": [                    // in-flight impl agents, written BEFORE spawn
    { "sliceId": "repair-webhook-source-ip-review-findings", "branch": "slice/repair-webhook-source-ip-review-findings", "manifestPath": "briefs/wave-6/ready-set-01.json", "attempt": 1 }
  ],
  "reviewWave": [                    // in-flight reviewers, written BEFORE spawn
    { "sliceId": "...", "reviewerId": "backend-architect", "bundlePath": "manifests/<id>/review-bundle.json" }
  ],
  "worktrees": [".claude/worktrees/slice-webhook-type-routing"],
  "stackState": "up",                // up | down | unknown
  "teardownOwed": false,             // true → run down -v FIRST on resume
  "gate5": {
    "strikes": 0,
    "phase": "full-suite",           // stack-up | full-suite | playwright | teardown | done
    "failureIds": []
  }
}
```

## Rules

- **Write-ahead.** Update BEFORE dispatch/spawn/merge/gate-step; the commit right after is the resume point. Death between write and commit → the manifest/brief on disk still replays (journal-before-dispatch, ADR 0034).
- **Sole writer.** Only orchestrator. Sub-agents never touch it.
- **Fields stay minimal.** Pointers only — shas, ids, paths, counts. No summaries, no learnings (those live in `progress.txt`).
- **Reconcile on resume:** `dispatched[]` entry with no manifest/sidecar on disk → follow the committed-but-unrecorded path (branch ahead → treat head as result; zero commits → reset to `todo`). `teardownOwed=true` → teardown first.
- **Delete or reset at task close** (with `progress.txt` + `prd.json` cleanup). Never carry into the next Task.
