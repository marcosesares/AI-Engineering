# to-issues — PRD → vertical slices + DAG + test-cases

Splits PRD into vertical slices, emits `depends_on` DAG, authors test-case `.md` docs upfront, attaches `testCases[]` per story. Output born `ready-for-agent`, SKIPS triage.

## What to do
0. **Pin integration (brownfield, if ARCHITECTURE.md exists).** Read ARCHITECTURE.md §1–§2 (use §Index for offset/limit). Per story, decide WHICH existing owner/seam it extends; record in story's `integration` field in prd.json (e.g. "extend EnrollmentResource — completion endpoints, no new class"). One place brownfield ownership decided — once, by orchestrator — so N parallel sub-agents don't each guess differently. No ARCHITECTURE.md → skip.
1. **Slice** each PRD story into vertical slices ordered tracer → schema → logic → api → ui. Slice = shippable end-to-end through its layer, not horizontal layer. **Sizing bound (HARD — Gate 1 blocks):** every story gets `estimatedLoc` (prod-LoC estimate) inside its sliceType bound (tracer/schema/api/logic ≤300, ui ≤600, pure-CSS ≤300); PRD story oversized → SPLIT it here (new ids + `depends_on` edges). Story ≥10 ACs → split or add a test-coverage slice.
2. **Build DAG** — express ordering as `depends_on` edges, NOT fixed per-iteration count. Each feature sequential along chain; independent features/branches have no edge → fan out in parallel. Set `sliceType` per story.
3. **Author test-cases UPFRONT** from PRD testing-decisions. One `.md` per behavior in `<Task root>/test-cases/` — alongside Task's prd.json, never at base when Task root exists. Two shapes:
   - **feature** — story-level journey. Automated IN-SLICE by slice sub-agent.
   - **regression** — app-wide journey spanning stories. Automated by FINAL [e2e-loop](./e2e-loop.md) pass.
4. **Attach** — set each story's `testCases[]` to ids of cases it must satisfy. Each case: Automated (E2E exists/will exist) or Manual (human walks it → human-QA script).
5. Set every story `status: todo`. Born `ready-for-agent` — do NOT pass through triage.

## Test-case `.md` format
```markdown
# TC-<id> — <behavior>  (shape: feature | regression)

## Preconditions
## Steps
1. <real-interface action: UI click / HTTP call — not internal poking>
## Expected
<observable outcome>

Disposition: Automated | Manual
Maps to story: <story-id>
```

## DAG correctness matters
Wrong DAG = wrong ready set = broken parallelism or out-of-order builds. Verify: every story whose work depends on another's output has that edge?

## Same-file collision (serialize when unsure)
Two stories with no `depends_on` edge → same ready set → parallel worktrees. Both writing SAME file → branches diverge → merge duplicates or clobbers (produced two `LessonSidebar`s + duplicate `api.student` block). Estimate file overlap from blast-radius (codebase-map §1) + slice type. Overlap likely OR uncertain → add `depends_on` edge to serialize (safe default). Parallel safe ONLY across disjoint file sets.

## Red flags (stop)
- Horizontal slices ("schema for everything") instead of vertical.
- Stories with no DAG edges when real dependencies exist.
- Skipping upfront test-cases (slices have no testCases[] to satisfy).
- Routing forward-flow slices through triage (born ready-for-agent).
- Two file-overlapping stories edge-free in same ready set (serialize them).
- Skipping `integration` pin when ARCHITECTURE.md exists (sub-agents re-guess ownership).
- Emitting a story missing `estimatedLoc` or beyond its sliceType bound — split it here, never hand an oversized slice to flight.
