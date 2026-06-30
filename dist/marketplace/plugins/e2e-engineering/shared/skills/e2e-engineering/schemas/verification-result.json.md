# Schema — verification-result.json

Evidence sidecar for GATE 5 (verification-before-completion). **ACTIVE — ADR 0024 (Fork Y) + ADR 0032:** = full automated suite (unit + independent API project) green against the live stack + AC-checklist-vs-code, no live-UI exercise. Written at gate 5 inside self-review. Lives at `tasks/<task-id>/manifests/<story-id>/verification-result.json` (or `manifests/_task/verification-result.json` for task-level verification).

```json
{
  "scope": "story-id | _task — story-scoped or task-level verification",
  "status": "passed | partial | failed",
  "suiteGreen": "boolean — full unit+API suite green from clean state",
  "gate5Strikes": "int — task-level fix-loop attempts spent (0..3); durable, NOT reset on resume",
  "gate5FailureIds": ["string — stable id of each still-failing test/AC (e.g. spec::test name, or AC index)"],
  "checklist": [
    {
      "criterion": "string — acceptance criteria text",
      "verified": "boolean",
      "method": "automated | manual | self-review"
    }
  ],
  "notes": "string — caveman-ultra; gaps or deferred items"
}
```

## Invariants
- **Active (Fork Y, ADR 0024).** `status: passed` requires `suiteGreen: true` AND every `checklist[]` item `verified: true`.
- **`status: partial`** = suite still red (or an AC unmapped) AFTER the bounded gate-5 loop — route to `pending-qa` + `## Gate 5 Failures` (ADR 0025/0032); NOT `blocked`.
- **`gate5Strikes` is durable.** A resumed flight reads the existing sidecar and continues from the recorded strike count; it does NOT reset to 0. `gate5FailureIds[]` lists the still-red tests/ACs so re-dispatch targets exactly them.
- `method: automated` = covered by unit/API test (green). `method: manual` = UI AC mapped to a Manual test-case (proven later in human-QA). `method: self-review` = code-path confirmed by reading code. **No live-UI exercise** — `/run`+`/verify` removed.
- `scope: _task` = task-level cross-slice verification (post-DAG-drain). `scope: <story-id>` = per-slice (future).
- Orchestrator writes this file at gate 5; updates prd.json with `verificationManifestPath`.
- `checklist[]` maps 1:1 to PRD `acceptanceCriteria[]` for traceability.
