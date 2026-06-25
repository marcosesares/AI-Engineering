# to-prd — formal PRD → prd.json

Converts grill-with-docs notes (+ research / prototype / codebase-map findings) into formal PRD, writes `prd.json` at **Task root** (`.e2e-engineering/tasks/<id>/` multi-Task, `.e2e-engineering/` single-Task legacy — established in SKILL.md Step 1). Write THERE directly; never base then copy. Owns its OWN interview step — fill gaps directly, no double-interview with grill-with-docs. Schema: [prd.json](../schemas/prd.json.md).

## What to do
1. Synthesize grill-with-docs notes + research.md / prototype conclusions / codebase-map (§1–§4) into coherent product spec.
2. Interview ONLY to close remaining gaps (don't re-ask what grill-with-docs settled).
3. Write `prd.json`: task-level fields + `stories[]`. Set `taskType`, `baseBranch`.
4. Per story: id, title, description, `acceptanceCriteria[]`, `priority`, `sliceType` (tracer|schema|logic|api|ui), `depends_on` (seed obvious edges; to-issues finalizes DAG), `status: todo`, `testCases: []` (to-issues authors these), notes.
5. **Testing-decisions** — capture per story what behaviors must be verified and their shape (feature = story-level journey, regression = cross-slice journey). Become test-case `.md` docs to-issues authors and attaches.
6. **ARCHITECTURE.md seed/update (if creating or amending it)** — write §Index line numbers AFTER writing all five sections. Required by schema so readers can use `offset/limit`.
7. **Test architecture → §4.1 (Fork Y, ADR 0024).** Task implements any API/endpoint → §4.1 MUST be filled: unit runner, Playwright `request` config + `baseURL`, M1 stack-up (docker-compose), auth, data isolation. Recognize existing project API-test conventions and record them (they override the baseline). Empty §4.1 on an API-bearing task → gate-1 blocks launch.
8. **UI lens (ADR 0030).** UI-bearing task → read [DESIGN.md](../schemas/design.md) (register + north star + tokens) and consult the [product-designer](../agents/product-designer.md) advisor — it acts on the spec pre-build, baking design requirements (register coverage, states, a11y, reuse, anti-slop) into acceptanceCriteria. **Capture audience + anti-references into the PRD** (the strategy half — DESIGN.md holds register/voice, the PRD holds who-for/what-to-avoid; one durable design file, not two). The `design` pre-impl step seeds DESIGN.md; to-prd READS it.

## Refactor-shaped stories (taskType: refactor)
Do NOT force `As a user…`. Refactor story = **behavior-preservation statement + structural goal**. Capture old-code transformation (modified OR removed) as explicit acceptance criteria + migration-step ordering (introduce new → migrate callers → modify/remove old). e2e = mandatory safety net. See ADR 0012.

## Exit → HARD GATE 1
Present PRD to user. Require EXPLICIT consent before implementation. Do not proceed on silence. Highest-fidelity gate — refactors and features alike are high blast radius.

## Red flags (stop)
- Re-interviewing on questions grill-with-docs already resolved.
- Writing implementation detail into PRD (PRD = what + acceptance, not how).
- Proceeding to implementation without explicit human approval.
- Omitting testing-decisions (downstream test-cases have nothing to derive from).
- Leaving ARCHITECTURE.md §4.1 test architecture empty on an API-bearing task (gate-1 blocks; slices have no stack/auth/isolation contract).
- UI-bearing task with empty/missing DESIGN.md — run the [design](design.md) step first to set register + seed it (mirror of the §4.1 test-architecture stall; UI slices otherwise have no design contract).
- Creating/amending ARCHITECTURE.md without updating §Index.
