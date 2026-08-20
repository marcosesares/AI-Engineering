# Schema — followups.json

Carry-forward record for expert-review findings still `open` when a slice's bounce cap (4) was exhausted (ADR 0035). Written by orchestrator at cap exhaustion, one entry per open finding. Lives at Task root: `.e2e-engineering/tasks/<id>/followups.json`. Sole writer = orchestrator. Read by the human at QA sign-off and routed through [triage](../impl/triage.md) into new queue Tasks.

```json
{
  "taskId": "payments-monetization",
  "followups": [
    {
      "id": "string — stable slug, unique in this file",
      "sliceId": "string — story id the finding came from",
      "reviewerId": "backend-architect | dba | frontend-reviewer | test-reviewer | finding-verifier",
      "severity": "Critical | Important | Minor",
      "location": "string — file:line or component/area",
      "message": "string — the defect, one line",
      "evidence": "string — file:line | test name | log path | searched-absence scope",
      "bounceRounds": "number — rounds spent before the cap exhausted (4)",
      "suggestedPriority": "number — per entry, from its own severity: Critical -> 1, Important/Minor -> 3"
    }
  ]
}
```

## Invariants
- Written ONLY at bounce-cap exhaustion. A slice whose convergence loop reached zero open findings writes nothing here.
- **Every entry has non-null `evidence`.** An un-cited finding never reaches this file — the hygiene gate drops it or the verify wave refutes it.
- `suggestedPriority` is PER ENTRY, derived from that entry's own severity: `Critical` → `1`, `Important`/`Minor` → `3`. A file may hold a mix. It is a RECOMMENDATION; triage and the front door set the real queue priority.
- **Flight NEVER writes `queue.json` from this file.** ADR 0017's writer table is intact: `/e2e-engineering` triage (intake source #4) creates the Task at QA sign-off.
- Mirrored into `qa-signoff.md`: `## Followups` always when this file is non-empty; `## Release Blockers` iff any entry is `Critical`.
- Lives on the task branch. Delete or reset at task close alongside `resume.json`.
- Distinct from `## Gate 5 Failures` (ADR 0025 — red suite or unmapped AC, task-level) and from QA findings (human-authored during the sign-off session).
