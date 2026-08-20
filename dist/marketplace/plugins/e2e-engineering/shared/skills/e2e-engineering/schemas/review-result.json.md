# Schema — review-result.json

Evidence sidecar. Written by orchestrator at expert-review fan-in. Lives at `tasks/<task-id>/manifests/<story-id>/review-result.json`. Reviewer agents return individual `ReviewerResult` shapes; orchestrator combines + persists as this envelope.

```json
{
  "sliceId": "string — story id slug",
  "notes": "string — optional orchestrator notes (e.g. reviewer-slot gap: re-dispatch exhausted, proceeded without <role>)",
  "reviews": [
    {
      "reviewerId": "string — backend-architect | dba | frontend-reviewer | test-reviewer",
      "findings": [
        {
          "id": "string — stable slug, unique within this file; the verify wave and suppressed[] key off it",
          "severity": "Critical | Important | Minor",
          "location": "string — file:line or component/area",
          "message": "string",
          "evidence": "string — file:line | test name | log path | explicit searched-absence scope. null ONLY while pre-verify",
          "state": "open | fixed | dropped-refuted | open-at-cap",
          "verification": {
            "resolution": "confirmed | refuted | inconclusive",
            "verifierEvidence": "string | null",
            "reason": "string — one line"
          }
        }
      ]
    }
  ]
}
```

Individual reviewer return shape (never written to disk by reviewer — passed back to orchestrator). Reviewers set `severity`, `location`, `message`, `evidence`; the ORCHESTRATOR assigns `id` and `state` at fan-in and fills `verification` after the verify wave.
```json
{ "reviewerId": "string", "sliceId": "string", "findings": [ { "severity", "location", "message", "evidence" } ] }
```

Verifier return shape (one per unproven finding, `finding-verifier` — never written to disk by the verifier):
```json
{ "findingId": "string", "resolution": "confirmed | refuted | inconclusive", "severity": "Critical | Important | Minor | null", "evidence": "string | null", "reason": "string" }
```

## Invariants
- `reviews[]` contains one entry per reviewer dispatched for this slice.
- `findings[]` empty array if reviewer found nothing. Absence of entry means reviewer was not dispatched (sliceType routing).
- **`severity` is exactly `Critical | Important | Minor`.** `NeedsVerification` and `Unsubstantiated` are NOT severities. `NeedsVerification` is a pre-verify signal a reviewer raises in place of an unproven Critical; `Unsubstantiated` is RETIRED (ADR 0035) — an un-cited claim is now spent on a `finding-verifier` and lands as `dropped-refuted` or `open`.
- **`state` transitions (ADR 0035):** `open` → `fixed` (a bounce round resolved it and the re-review no longer raises it) · `open` → `dropped-refuted` (verifier returned `refuted`, or `inconclusive` which counts as refuted) · `open` → `open-at-cap` (still open when bounce round 5 was entered; carried into `followups.json`).
- **`evidence` is non-null for every terminal finding.** Un-cited `Critical`/`Important` go to the verify wave; un-cited `Minor` is dropped without verifier spend; a finding with no action is downgraded (`Important`→`Minor`) or dropped (`Minor`).
- `verification` is null until the verify wave runs on that finding, and each finding is verified AT MOST ONCE per slice.
- `notes` records orchestrator-side anomalies only (hung reviewer proceeded-past, unavailable slot, downgraded severity misuse, dropped un-cited Minors). Absent when nothing to record.
- Written after all dispatched reviewers return — orchestrator holds findings in memory until fan-in complete.
- Orchestrator updates `prd.json` story's `reviewManifestPath` after writing this file.
- Path in prd.json is relative to Task root: `manifests/<story-id>/review-result.json`.
- Bounce rounds are tracked in `progress.txt` + `resume.json` `bounce.rounds`, not re-written to this sidecar per round; final post-loop state is persisted once.
