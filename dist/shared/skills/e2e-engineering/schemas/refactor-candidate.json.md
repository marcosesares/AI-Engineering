# Schema — refactor-candidate.json (refactor-candidate manifest)

Structured output an [[architecture-scout]] returns to `/e2e-deslop` for ONE [[scan area]]. The orchestrator persists it at `.e2e-engineering/deslop/<area-slug>/refactor-candidates.json` and points the area's [[scan ledger]] entry at it (`candidateManifestPath`). Distinct from `slice-result.json` (impl evidence) and `review-result.json` (defect findings) — these are deepening OPPORTUNITIES, not defects.

```json
{
  "area": "string — module / subtree the scout scanned",
  "verdict": "candidate | clean",
  "candidates": [
    {
      "smell": "shallow-module | dup-rule | missing-seam | poor-locality | untestable",
      "location": "string — file:line(s) the candidate is anchored to",
      "rationale": "string — why shallow / what is duplicated / which seam is absent",
      "proposedBoundary": "string — the deeper interface / seam / co-location to introduce",
      "blastRadius": "S | M | L",
      "priority": "high | med | low",
      "behaviorPreserved": "string — one line; what must stay true through the refactor"
    }
  ]
}
```

## Invariants
- **Opportunities, not defects.** No Critical/Important/Minor — rank by `priority` + `blastRadius`. Review severities belong to `review-result.json`, not here.
- **Surface-only / walled.** Every candidate is `NOT THIS SCAN` — scouts never edit code; `/e2e-deslop` routes candidates through `triage`; a human picks which become [[refactor Task]]s.
- `verdict: clean` → empty `candidates` array (area is deep enough). Orchestrator writes `verdict: clean` to the [[scan ledger]] for that area.
- Every candidate cites a concrete `location` (`file:line`). Un-anchored candidates are rejected.
- `behaviorPreserved` is mandatory — refactor Tasks are behavior-preserving (ADR 0012); it becomes the refactor Task's safety-net acceptance criterion.
