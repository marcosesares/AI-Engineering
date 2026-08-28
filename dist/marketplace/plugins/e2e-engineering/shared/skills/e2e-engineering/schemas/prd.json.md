# Schema — prd.json

Structured state for one Task. Written and owned by orchestrator (sole writer). New task → overwrite fresh. Lives at **Task root**: `.e2e-engineering/tasks/<id>/prd.json` multi-Task, `.e2e-engineering/prd.json` single-Task legacy. Written there directly — never base-then-copy.

```json
{
  "project": "string — repo/product name",
  "description": "string — one-paragraph intent of THIS task",
  "taskType": "greenfield | feature | bugfix | refactor",
  "baseBranch": "string — branch slices fork from and merge back into",
  "stories": [
    {
      "id": "string — stable slug, referenced by depends_on and testCases",
      "title": "string",
      "description": "string — refactor-shaped allowed (behavior-preservation + structural goal), not forced 'As a user…'",
      "acceptanceCriteria": ["string", "..."],
      "priority": "number — lower = sooner within ready set",
      "sliceType": "tracer | schema | logic | api | ui",
      "estimatedLoc": "number — REQUIRED, prod-LoC estimate for this slice, set by to-prd. MUST sit inside the sizing bounds for its sliceType (tracer/schema/api/logic ≤300, ui ≤600, pure-CSS/styling ≤300; story with ≥10 ACs → split or add a test-coverage slice). Gate 1 blocks oversized — split, never queue.",
      "depends_on": ["story-id", "..."],
      "status": "todo | done | blocked",
      "branch": "string — worktree branch for this slice",
      "testCases": ["test-case-id", "..."],
      "integration": "string — brownfield ownership/seam decision pinned by to-issues from ARCHITECTURE.md §1–§2. e.g. 'extend EnrollmentResource — completion endpoints, no new class'. Empty for greenfield / no ARCHITECTURE.md. Injected into slice sub-agent at fan-out.",
      "notes": "string — free, e.g. blocked reason, gap-check escalation. Cap-exhaustion form (ADR 0035): '<n> open findings at cap: <severities>' — e.g. '2 open findings at cap: Critical, Minor'",
      "resultManifestPath": "string — path relative to Task root; null until impl fan-in. e.g. 'manifests/auth-login/slice-result.json'",
      "reviewManifestPath": "string — path relative to Task root; null until review fan-in. e.g. 'manifests/auth-login/review-result.json'"
    }
  ]
}
```

## Evidence sidecar layout
Sidecar files at Task root: `manifests/<story-id>/`. Written by orchestrator at fan-in, NEVER by sub-agents.
- `slice-result.json` ([schema](slice-result.json.md)) — written after impl fan-in; pointer in `resultManifestPath`
- `review-bundle.json` ([schema](review-bundle.json.md)) — written before expert-review dispatch; prompt input, not status authority
- `review-result.json` ([schema](review-result.json.md)) — written after review fan-in; pointer in `reviewManifestPath`
- `verification-result.json` ([schema](verification-result.json.md)) — GATE 5 (active, ADR 0024); written at gate 5 (`manifests/_task/`); pointer in `verificationManifestPath`

## Invariants
- **COMPLETE** = every story `status: "done"`. (Replaces Ralph's `passes: true`.)
- `status` enum: exactly three values. `blocked` only after debug escalation (GATE 3 — 3 failed fixes + systematic-debugging failed, red tests). **Expert-review findings NEVER produce `blocked`** (ADR 0035): a slice that exhausts its 5 bounce rounds MERGES as `done`, its open findings recorded in `notes` and carried into `followups.json` ([schema](followups.json.md)).
- `depends_on` edges encode tracer→schema→logic→api→ui ordering. Each feature sequential along chain; independent chains parallel.
- **Ready set** = stories whose `depends_on` all `done` AND own `status` is `todo`.
- Sub-agents NEVER write this file. Return slice result manifest; orchestrator reconciles + writes `status` at fan-in. Sidecar `status` fields (slice-result.json, review-result.json) are NEVER authoritative — prd.json is sole source of truth for story status.
- `resultManifestPath` + `reviewManifestPath` set by orchestrator after fan-in (null until then). Path relative to Task root.
- `testCases[]` ids point at `.md` test-case docs authored upfront by to-issues.
- `estimatedLoc` required per story; out-of-bounds for its sliceType = Gate 1 block (to-prd sizing table). Flight Step 2 re-checks fail-closed: missing or out-of-bounds `estimatedLoc` → stall `oversized-slice` (revert slice to `ready-for-flight`) unless `gate1SizingOverride: true` + `sizingOverrideNote`.
- `gate1SizingOverride` optional bool + `sizingOverrideNote` string — deliberate human exception for an out-of-bounds slice (who/why). Flight Step 2 refuses out-of-bounds slices unless this is `true`; override-approved slices get subsystem-scoped reviewer evidence.
- `integration` set by to-issues (reading ARCHITECTURE.md §1–§2 via §Index offset/limit), not by sub-agent. Single place brownfield ownership decided — once, by orchestrator. See ADR 0013.
