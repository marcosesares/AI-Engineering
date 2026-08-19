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
          "severity": "Critical | Important | Minor",
          "location": "string — file:line or component/area",
          "message": "string"
        }
      ]
    }
  ]
}
```

Individual reviewer return shape (never written to disk by reviewer — passed back to orchestrator):
```json
{ "reviewerId": "string", "sliceId": "string", "findings": [...] }
```

## Invariants
- `reviews[]` contains one entry per reviewer dispatched for this slice.
- `findings[]` empty array if reviewer found nothing. Absence of entry means reviewer was not dispatched (sliceType routing).
- `notes` records orchestrator-side anomalies only (hung reviewer proceeded-past, unavailable slot, downgraded severity misuse). Absent when nothing to record.
- Written after all dispatched reviewers return — orchestrator holds findings in memory until fan-in complete.
- Orchestrator updates `prd.json` story's `reviewManifestPath` after writing this file.
- Path in prd.json is relative to Task root: `manifests/<story-id>/review-result.json`.
- Critical/Important bounces are tracked in `progress.txt`, not re-written to this sidecar per bounce; final post-bounce state is persisted once.
