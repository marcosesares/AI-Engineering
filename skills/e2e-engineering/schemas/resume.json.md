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
  "bounce": {                        // review convergence loop state, PER SLICE (ADR 0035)
    "repair-webhook-source-ip-review-findings": { "rounds": 2, "cap": 5, "carried": 0 }
  },
  "verifyWave": [                    // in-flight finding-verifiers, written BEFORE spawn
    { "sliceId": "...", "findingId": "ac-3-no-real-stack-test", "verifierId": "finding-verifier" }
  ],
  "suppressed": {                    // dropped-refuted finding keys, PER SLICE
    "repair-webhook-source-ip-review-findings": ["Critical|src/Webhook.java:88|9f2c1a7e"]
  },
  "worktrees": [".claude/worktrees/slice-webhook-type-routing"],
  "stackState": "up",                // up | down | unknown
  "ports": { "nextFree": 8431 },
  "concurrency": { "workers": 2, "reviewers": 4 },
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
- **`bounce.rounds` is DURABLE and never reset** (ADR 0035). Not on resume, and not when a re-review surfaces brand-new findings — the counter is absolute per slice. Losing it restarts the count and the slice churns unbounded; same failure class as `gate5Strikes`. Write-ahead before every bounce dispatch.
- **`verifyWave[]` written BEFORE verifier dispatch.** On resume, an entry with no `verification` recorded in that slice's `review-result.json` → re-dispatch that verifier ONCE; still nothing → record `inconclusive`, which counts as `refuted`.
- **`suppressed[]` holds `dropped-refuted` finding keys** for the slice in flight, formatted `"<severity>|<location>|<first 8 hex of sha1(message)>"`. A later re-review may NOT re-raise a suppressed finding — without this the convergence loop never terminates. Cleared when the slice merges.
- `ports.nextFree` — the port allocator ledger (conditional docker/Testcontainers projects). `run-focused-tests.ps1`/`carrier-smoke.ps1` claim a port by incrementing write-ahead and release it on exit; never hand-assign.
- `concurrency` — the Step-0 RAM/CPU probe result; caps concurrent `subagent` dispatch + workflow parallelism for this flight.
- **`bounce`, `verifyWave[]` and `suppressed` are keyed PER SLICE** — the impl wave dispatches the whole ready set in parallel, so two slices can be in their review waves at once. A single shared counter would let one slice reset another's `rounds` (unbounded churn) or clear another's `suppressed` (refuted findings re-enter and the loop never converges). Delete a slice's entry when that slice merges; never reset the whole object.
