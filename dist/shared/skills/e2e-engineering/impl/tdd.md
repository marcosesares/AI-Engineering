# tdd — SLICE SUBAGENT

## 0. Empty-message bootstrap (runtime payload-drop fallback, ADR 0037)

Some runtimes deliver spawn/followup messages EMPTY (turn triggers, content lost). Do NOT idle-ask "what task". Self-brief from disk instead:

1. Read repo-root `.e2e-engineering/tasks/*/resume.json` — the in-flight Task has `phase: dispatch` and non-empty `dispatched[]`.
2. Pick your `dispatched[]` entry: the sliceId whose slug (hyphens → underscores) CONTAINS your own agent task-name slug; else the sole entry if exactly one exists.
3. Read `manifestPath` (relative to that Task root) — your slice's injection payload (workerBrief/story entry: acceptanceCriteria, `integration` decision, context, contracts incl. `compileCmd`/testCmd, environment, rules) is IN that manifest.
4. Work in the worktree path from that entry (never the repo root); branch from that entry.
5. No matching entry → return `status: blocked`, finding `type: blocker` "no-dispatch-entry" — never guess.

The orchestrator commits those files BEFORE spawning (journal-before-dispatch, ADR 0034) — disk IS the brief. Then run the sequence below with the workerBrief as the injected story.

**Post-compaction recovery:** a restarted/compacted worker resumes from its branch diff + slice status JSON + the journaled manifest — NEVER re-reads the full original brief (the brief is the context; recovery must not re-inflate it).

Runs INSIDE fan-out sub-agent, in own git worktree, for ONE story. Receives: [constitution](../constitution.md), [api-testing standard](../standards/api-testing.md), [command-execution](./command-execution.md) + the orchestrator's cached `compileCmd`, story (acceptanceCriteria, sliceType, depends_on, `integration` decision), feature test-cases, (brownfield) SCOPED slice of ARCHITECTURE.md (this layer's naming + ownership rules touching blast radius + relevant anti-patterns — via §Index offset/limit). **`ui` slices ALSO receive the [ui-design standard](../standards/ui-design.md) + the SCOPED slice of [DESIGN.md](../schemas/design.md)** (register + relevant tokens/components, via §Index offset/limit) — mirror of the api-testing-standard injection for API slices; DESIGN.md is READ-ONLY in flight. Follow `integration` decision and those conventions: EXTEND named owner, match naming pattern — do not invent parallel class/file. Returns evidence-pointer-first manifest only — never writes prd.json/progress.txt/ARCHITECTURE.md/DESIGN.md or authoritative sidecars (orchestrator is sole writer; ARCHITECTURE.md + DESIGN.md are human-phase-only).

**After returning green, orchestrator runs expert-review wave** (role agents: frontend-reviewer / backend-architect / dba / test-reviewer, by sliceType — ADR 0022) in this worktree before merge. For `ui` slices, **frontend-reviewer reviews against the approved DESIGN.md + ui-design.md** (deviation = Important: fix or justify; anti-slop defect = normal severity incl. Critical). Findings at ANY severity — Critical, Important, Minor — bounce back to YOU for fix, ALL open ones in ONE pass; then re-review (convergence v2, ADR 0035 amendment: Phase A while any Critical/Important is open, cap 5 absolute; Phase B one Minor fix pass + one review → survivors `state: carried` → `followups.json`, never `blocked`). GATE 3 (red tests) still blocks. Write slice to pass that review: follow `integration` decision, match conventions, give every acceptance criterion real-interface test.

## 0.5. Canary (FIRST tool call, before any briefing work)

Run ONE pwsh: `git rev-parse HEAD` in your worktree. Reply `CANARY-OK <sha>`. No other work until this reply is sent.

## Sequence

### 1. Slice gap-check (FIRST move, before any TDD)
Validate story is implementable:
- Acceptance criteria clear?
- `testCases[]` present?
- `depends_on` real and satisfied (upstream code exists in this worktree)?

**Complete brief — zero setup reads.** The workerBrief is the whole contract: constitution + command-execution + [testing standard](../standards/testing.md) + (per sliceType: [db](../standards/db.md) / [backend](../standards/backend.md) / [api-testing](../standards/api-testing.md) / [ui-design](../standards/ui-design.md) + scoped DESIGN.md) + ACs + integration + compileCmd + lint digest. These standards files are injected verbatim into the brief — do NOT open skill files (constitution.md, tdd.md, command-execution.md, api-testing.md, ARCHITECTURE slices). A rule the injected standards don't cover → the gap-check escalation above (one question). Never guess.

Gap found → escalate ONE question to orchestrator. DO NOT guess.

### 2. Red-green-refactor
- **RED** — write failing test FIRST for behavior in acceptance criteria. Run it; confirm fails for right reason. **HARD GATE 2: no production code before failing test.**
- **GREEN** — write minimum production code to pass. Constitution: simplicity-first (new code), surgical-changes (editing existing).
- **REFACTOR** — clean up with tests green. Stay in scope (no "while I'm here").
- **Lint contract:** write to the injected lint digest from line one — treat it as part of the ACs. Conforming code passes the commit-point check first try.
- **Checks at SEMANTIC COMMIT POINTS** (ADR 0037 amendment). Commit ONLY at: (1) red test (Gate 2), (2) green impl per AC, (3) refactor unit, (4) one commit per fix pass, (5) one commit per chunk, (6) one commit per cherry-pick sequence (restore). At each commit point run `compile-check.ps1` + `lint-check.ps1` with scope following the commit's changed files (frontend-only → tsc+eslint; backend-only → compile). Ad-hoc compiles between points are allowed while debugging; the gate fires at points. ~3–6 commits per in-bounds slice. The orchestrator's Step-3.4 gate stays authoritative.

### 3. Automate API/integration (Fork Y — ADR 0024)
For any API/endpoint this slice implements: write red-green **Playwright `request`** tests (part of gate 2) per [api-testing standard](../standards/api-testing.md) — but if the project already has API-test conventions (ARCHITECTURE.md §4), follow THOSE. M1: tests hit the running docker-compose stack; isolate/clean own data. **UI is NOT automated** (Fork Y): a UI feature test-case is disposition **Manual** — do NOT write Playwright browser/POM code; ensure the Manual test-case doc exists for the human-QA walk. Regression/cross-slice cases NOT yours.

### 4. Debug escalation (HARD GATE 3)
Fix fails 3 times → STOP. Do not blind-retry. Return to orchestrator reporting 3-strike. Orchestrator re-dispatches ONCE with [systematic-debugging](./systematic-debugging.md).

### 4b. Chunk-driver mode (ADR 0037)

The orchestrator may degrade a stalled slice into small chunks: you implement ONE narrow chunk (≤1 file, one AC) + self-compile; the orchestrator runs the focused tests and feeds the verdict back. **GATE 2 holds:** chunk 1 = the failing test (orchestrator confirms red), then the impl chunk (orchestrator confirms green). Return per-chunk status; the slice manifest comes after the last chunk.

**Every command you run is bounded + non-interactive** per [command-execution](./command-execution.md) (ADR 0033): compile with the injected `compileCmd` (never assume `mvn`), 6 min (focused gradle 12 min); test suite 20 min (full backend suite 30 min). A timeout counts as a failed fix (gate-3 strike) — log `TIMEOUT <cmd> @<budget>s`, add a `findings[]` `type:blocker` carrying cmd + budget, never re-run unchanged more than once. Never foreground a watch/serve/dev command or attach to logs — it never returns and no brake will catch it. All commands use the workdir param (never in-command `cd`); long producers redirect to a log file (never `Out-String`/`head`/`tail` pipe-filters); git always `commit -m` / `merge --no-edit`; tests always `npx vitest run` (bare `vitest` = watch = hang); never `./gradlew --stop`.

### 4c. Pre-return self-check (review contract)

Before returning the manifest: re-check the injected standards files (constitution + testing + your sliceType's standards) against your own diff. Fix violations now, or list unfixed ones as known deviations in `findings[]`. Your "done" should mean the reviewer's "clean" — only genuinely judgment-call findings survive to the review wave.

## Return manifest (to orchestrator)
Return compact JSON only: `sliceId`, `status`, one-line `summary`, `testsPassed`, `branch`, `evidencePaths[]`, `findings[]`.

- Put detailed logs in normal test/build report paths or assigned per-slice evidence paths; return pointers only. **Evidence = counts + ≤20-line excerpts (ADR 0036)** — full logs stay on disk (gitignored `*.log`), deleted at worktree removal, NEVER committed.

NEVER commit `evidence/` dirs — evidence files are untracked only, like env/config files. Evidence = manifest pointers + counts + ≤20-line excerpts.
- Include test-case ids and red→green proof in evidence artifacts, not chat.
- Durable learnings / architecture drift go in `findings[]` as concise warnings. Do NOT edit ARCHITECTURE.md — orchestrator stages it; human decides at QA gate.
- Blockers / gap-check escalations go in `findings[]` with `type:blocker`.
- Keep final response tiny — orchestrator reads manifests, not raw churn.

## Red flags (stop)
- Production code before failing test (gate 2 violation).
- Guessing past gap instead of escalating one question.
- Blind-retrying 4th time after 3 strikes (gate 3 violation).
- Running a command unbounded/interactive, or foregrounding a watch/serve/dev script — it never exits and hangs the whole spawn (ADR 0033).
- Writing prd.json / progress.txt (sole-writer violation).
- Returning raw test logs, full diffs, or long narrative instead of evidence paths.
- Automating regression/cross-slice journeys here (not this sub-agent's job).
- Writing Playwright browser/POM UI tests (Fork Y — UI is Manual; automate API via `request` only).
- Testing internal state instead of real interfaces (constitution testing principle 1).
- Creating parallel class/file when `integration` decision or ARCHITECTURE.md names existing owner to extend.
- Editing ARCHITECTURE.md or DESIGN.md (human-phase-only; propose drift in summary instead).
- Committing an `evidence/` dir or any log (untracked only — ADR 0037 amendment).
- Skipping the canary (first tool call must be `git rev-parse HEAD` + `CANARY-OK`).
- Committing outside a semantic commit point.
- Running a check with scope wider than the commit's changed files (never whole-repo lint — pre-existing debt is out of slice scope).
- Opening skill files instead of using the complete brief (gap-check escalation is the only exception path).
