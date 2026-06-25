# tdd — SLICE SUBAGENT

Runs INSIDE fan-out sub-agent, in own git worktree, for ONE story. Receives: [constitution](../constitution.md), [api-testing standard](../standards/api-testing.md), story (acceptanceCriteria, sliceType, depends_on, `integration` decision), feature test-cases, (brownfield) SCOPED slice of ARCHITECTURE.md (this layer's naming + ownership rules touching blast radius + relevant anti-patterns — via §Index offset/limit). **`ui` slices ALSO receive the [ui-design standard](../standards/ui-design.md) + the SCOPED slice of [DESIGN.md](../schemas/design.md)** (register + relevant tokens/components, via §Index offset/limit) — mirror of the api-testing-standard injection for API slices; DESIGN.md is READ-ONLY in flight. Follow `integration` decision and those conventions: EXTEND named owner, match naming pattern — do not invent parallel class/file. Returns evidence-pointer-first manifest only — never writes prd.json/progress.txt/ARCHITECTURE.md/DESIGN.md or authoritative sidecars (orchestrator is sole writer; ARCHITECTURE.md + DESIGN.md are human-phase-only).

**After returning green, orchestrator runs expert-review wave** (role agents: frontend-reviewer / backend-architect / dba / test-reviewer, by sliceType — ADR 0022) in this worktree before merge. For `ui` slices, **frontend-reviewer reviews against the approved DESIGN.md + ui-design.md** (deviation = Important: fix or justify; anti-slop defect = normal severity incl. Critical). Critical/Important findings bounce back to YOU for fix, then re-review (cap 3 round-trips, then slice marked `blocked`). Write slice to pass that review: follow `integration` decision, match conventions, give every acceptance criterion real-interface test.

## Sequence

### 1. Slice gap-check (FIRST move, before any TDD)
Validate story is implementable:
- Acceptance criteria clear?
- `testCases[]` present?
- `depends_on` real and satisfied (upstream code exists in this worktree)?
Gap found → escalate ONE question to orchestrator. DO NOT guess.

### 2. Red-green-refactor
- **RED** — write failing test FIRST for behavior in acceptance criteria. Run it; confirm fails for right reason. **HARD GATE 2: no production code before failing test.**
- **GREEN** — write minimum production code to pass. Constitution: simplicity-first (new code), surgical-changes (editing existing).
- **REFACTOR** — clean up with tests green. Stay in scope (no "while I'm here").

### 3. Automate API/integration (Fork Y — ADR 0024)
For any API/endpoint this slice implements: write red-green **Playwright `request`** tests (part of gate 2) per [api-testing standard](../standards/api-testing.md) — but if the project already has API-test conventions (ARCHITECTURE.md §4), follow THOSE. M1: tests hit the running docker-compose stack; isolate/clean own data. **UI is NOT automated** (Fork Y): a UI feature test-case is disposition **Manual** — do NOT write Playwright browser/POM code; ensure the Manual test-case doc exists for the human-QA walk. Regression/cross-slice cases NOT yours.

### 4. Debug escalation (HARD GATE 3)
Fix fails 3 times → STOP. Do not blind-retry. Return to orchestrator reporting 3-strike. Orchestrator re-dispatches ONCE with [systematic-debugging](./systematic-debugging.md).

## Return manifest (to orchestrator)
Return compact JSON only: `sliceId`, `status`, one-line `summary`, `testsPassed`, `branch`, `evidencePaths[]`, `findings[]`.

- Put detailed logs in normal test/build report paths or assigned per-slice evidence paths; return pointers only.
- Include test-case ids and red→green proof in evidence artifacts, not chat.
- Durable learnings / architecture drift go in `findings[]` as concise warnings. Do NOT edit ARCHITECTURE.md — orchestrator stages it; human decides at QA gate.
- Blockers / gap-check escalations go in `findings[]` with `type:blocker`.
- Keep final response tiny — orchestrator reads manifests, not raw churn.

## Red flags (stop)
- Production code before failing test (gate 2 violation).
- Guessing past gap instead of escalating one question.
- Blind-retrying 4th time after 3 strikes (gate 3 violation).
- Writing prd.json / progress.txt (sole-writer violation).
- Returning raw test logs, full diffs, or long narrative instead of evidence paths.
- Automating regression/cross-slice journeys here (not this sub-agent's job).
- Writing Playwright browser/POM UI tests (Fork Y — UI is Manual; automate API via `request` only).
- Testing internal state instead of real interfaces (constitution testing principle 1).
- Creating parallel class/file when `integration` decision or ARCHITECTURE.md names existing owner to extend.
- Editing ARCHITECTURE.md or DESIGN.md (human-phase-only; propose drift in summary instead).
