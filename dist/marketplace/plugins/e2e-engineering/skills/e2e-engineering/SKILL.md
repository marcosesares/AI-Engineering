---
name: e2e-engineering
description: Interactive front door for the e2e-engineering flow — drives a Task from idea to an approved PRD (pre-implementation), launches headless implementation via /e2e-flight, and runs the human QA sign-off. Detects phase and task type, sequences sub-skills, plans the PRD with expert agents (UI designer / backend architect / DBA) so it is architecture-aware, and enforces the hard gates. Handles greenfield, feature, bugfix, and refactor on new or existing codebases, plus a one-time `adopt` mode for onboarding an in-progress project. Implementation itself runs in /e2e-flight (ADR 0022 — one Task per spawn, no loop, no context monitoring). Use when the user says "e2e-engineering", "e2e-eng", "ship-it", "ship it", "/e2e-engineering", "implement feature <name>", "write e2e for <feature>", "build this end to end", "run the full flow", or otherwise wants the complete engineering pipeline rather than a single isolated step.
---

# e2e-engineering — orchestrator

Master skill. Detect phase + task type, route mode, sequence sub-skills, drive loop, enforce gates. Read CONTEXT.md for any term.

State lives under `.e2e-engineering/`. Multi-Task layout (default): `queue.json` at root, each Task body under `tasks/<id>/` — `prd.json`, `progress.txt`, `codebase-map.md` (brownfield), `research.md`, `test-cases/*.md`, `qa-signoff.md`, `manifests/<story-id>/` (evidence sidecars). Single-Task legacy keeps files directly under `.e2e-engineering/`. Schemas: [queue.json](../../shared/skills/e2e-engineering/schemas/queue.json.md), [prd.json](../../shared/skills/e2e-engineering/schemas/prd.json.md), [progress.txt](../../shared/skills/e2e-engineering/schemas/progress.txt.md), [qa-signoff](../../shared/skills/e2e-engineering/schemas/qa-signoff.md), [codebase-map](../../shared/skills/e2e-engineering/schemas/codebase-map.md), [slice-result](../../shared/skills/e2e-engineering/schemas/slice-result.json.md), [review-bundle](../../shared/skills/e2e-engineering/schemas/review-bundle.json.md), [review-result](../../shared/skills/e2e-engineering/schemas/review-result.json.md), [verification-result](../../shared/skills/e2e-engineering/schemas/verification-result.json.md).

**Task root (write artifacts THERE from start — no base-then-copy).** Every per-Task artifact lives at **Task root**: `.e2e-engineering/tasks/<id>/` multi-Task, `.e2e-engineering/` single-Task legacy. Orchestrator establishes Task root ONCE at pre-impl start (Step 1); every sub-skill writes directly into it. Do NOT write to base `.e2e-engineering/` then copy — leaves dirty duplicates. Gate-1 queueing only appends `queue.json` entry; body already in place. See ADR 0021.

Interactive front door (human-driven pre-implementation + batched QA sign-off). Automated implementation drain = [/e2e-flight](../e2e-flight/SKILL.md). See ADR 0016 (split), 0017 (queue), 0018 (QA deferral).

Durable project docs at repo ROOT: `CONTEXT.md` (glossary), [constitution](../../shared/skills/e2e-engineering/constitution.md) (generic engineering standards), `ARCHITECTURE.md` (project-specific structure + conventions — schema: [architecture](../../shared/skills/e2e-engineering/schemas/architecture.md)). ARCHITECTURE.md written ONLY in human phases (pre-impl seed + post-impl human-QA amend); implementation loop reads it, never writes it. See ADR 0013.

**Sole-writer rule:** ONLY orchestrator writes `prd.json` + `progress.txt` + evidence sidecars (`manifests/<story-id>/`). Sub-agents return slice result manifests; never touch shared state.

---

## Step 0 — route mode

- User invoked `/e2e-engineering adopt` → run [adopt](../../shared/skills/e2e-engineering/adopt.md). One-time onboarding, not per-task flow. Stop here.
- User invoked `/e2e-engineering qa`, OR `queue.json` has any Task `status:pending-qa` → run **QA sign-off session** ([human-qa](../../shared/skills/e2e-engineering/post-impl/human-qa.md) multi-Task mode): walk every pending-qa Task's [qa-signoff.md](../../shared/skills/e2e-engineering/schemas/qa-signoff.md), sign off (→ `done`), route findings through [triage](../../shared/skills/e2e-engineering/impl/triage.md) into new queue Tasks, and forward each Task's [flow-retro](../../shared/skills/e2e-engineering/schemas/flow-retro.md) §Skill-improvement candidates upstream to the e2e-engineering repo (three distinct lanes — ADR 0027). Offer this first when pending-qa work exists. Stop here when done.
- Otherwise → per-feature flow below (spec → gate 1 → queue → launch flight).

## Step 1 — detect phase + task type

Determine where to enter (phase-adaptive — user may start mid-flow):

1. Does `prd.json` exist at relevant Task root (multi-Task: in-progress Task under `tasks/<id>/` via queue.json; legacy: `.e2e-engineering/prd.json`)?
   - **No** → start Pre-implementation from top.
   - **Yes** → read it. Any story `status != done` → resume Implementation. All `done` → Post-implementation.
2. Resuming fresh session reads state, not handoff (ADR 0022): `queue.json` (which Task) → `tasks/<id>/prd.json` (which slices done/todo/blocked) → `progress.txt` (tail for current state), then continue.
3. **Task type** (set/confirm `taskType` in prd.json): `greenfield`, `feature`, `bugfix`, `refactor`. Refactor runs FULL flow — no lite path (ADR 0012).
4. **Greenfield vs brownfield**: greenfield skips map-codebase; brownfield (feature/bugfix/refactor on existing code) runs it.
5. **Establish Task root NOW (new feature, front-door flow).** Derive `<id>` = kebab-case feature slug, confirm with user, `mkdir .e2e-engineering/tasks/<id>/`. All pre-impl sub-skills write INTO it. Set id before first artifact produced (map-codebase is first writer on brownfield). Single-Task legacy keeps base root.

Confirm detected entry with user in one line before proceeding.

---

## Pre-implementation phase

Sequence (bracketed = conditional): **[map-codebase? (brownfield)] → grill-with-docs → [research?] → [prototype?] → to-prd**. (ADR 0019.)

1. [map-codebase](../../shared/skills/e2e-engineering/pre-impl/map-codebase.md) — brownfield only (gated by `taskType`, NOT by grilling). Runs FIRST. Produces `codebase-map.md` (5 sections + §Index, scoped). §5 refactor candidates WALLED. Greenfield skips it.
2. [grill-with-docs](../../shared/skills/e2e-engineering/pre-impl/grill-with-docs.md) — single doc-aware brainstorm loop. Reads CONTEXT.md + ARCHITECTURE.md (§Index for offset/limit) + (brownfield) codebase-map §1–§4 BEFORE asking. Reconciles language inline. Gates research/prototype. Loops until user approves direction. Implementation skips re-grill (language settled here).
3. [research](../../shared/skills/e2e-engineering/pre-impl/research.md) — only if task leans on external APIs / unfamiliar libs. Produces `research.md` (rots).
4. [prototype](../../shared/skills/e2e-engineering/pre-impl/prototype.md) — only if taste/UX/state-machine uncertainty needs concrete feedback. Throwaway. ui-branch or logic-branch.
5. [to-prd](../../shared/skills/e2e-engineering/pre-impl/to-prd.md) — convert grill-with-docs notes into formal PRD → writes `prd.json`. Owns own interview step (no double-interview). Refactor-shaped stories allowed. Captures testing-decisions → test-cases.
   - **Plan with expert agents → architecture-aware PRD.** Before finalizing, consult expert reviewer agents as advisors against `ARCHITECTURE.md` + `constitution`: [backend-architect](../../agents/backend-architect.md), [dba](../../agents/dba.md), [frontend-reviewer](../../agents/frontend-reviewer.md). Same agents later review built slices in [/e2e-flight](../e2e-flight/SKILL.md).
   - **Seed test architecture → ARCHITECTURE.md §4 (Fork Y, ADR 0024).** Recognize (brownfield: from code) or define (greenfield) how the project runs tests: unit runner (Vitest/Jest) + layout; API/integration via Playwright `request` (config path, test dir, auth/setup). UI = Manual (no automation). Write into ARCHITECTURE.md (human phase). Flight READS this; never writes it.

**HARD GATE 1 — PRD approved → implementation.** Present PRD; require explicit human consent before any code. Do not proceed on silence. STOP + WAIT. Never infer approval from "looks good" on earlier draft.

**→ On consent: queue Task, then batch or launch.** Steps IN ORDER — each is human chokepoint, none auto-resolved:

1. **Task body + brownfield check.** Verify task body complete at `.e2e-engineering/tasks/<id>/`. Do NOT copy/move from base. `<id>` fixed at Step 1. **Brownfield only:** verify `tasks/<id>/codebase-map.md` exists — missing → stall: `"Pre-impl incomplete — run map-codebase first."` Do not queue without it. **API-bearing task (any api/logic story hitting an endpoint):** verify `ARCHITECTURE.md §4.1` test architecture filled (stack-up, baseURL, auth, data isolation) — empty → stall: `"Fill ARCHITECTURE.md §4.1 test architecture before launch (ADR 0024)."` Do not queue without it.
2. **Append to [queue.json](../../shared/skills/e2e-engineering/schemas/queue.json.md)** — entry `{ id, title, priority, dependsOn, status:todo, selected:false, parentTask:null }`. Ask human for `priority` + cross-Task `dependsOn` (camelCase). **New Tasks born `selected:false`** — selection only at checkbox in step 3.
3. **Batch or launch?** Ask: *"Spec another feature, or launch flight now?"* — STOP for answer.
   - **Another** → loop back to Pre-implementation for next feature — establish NEW Task root first. Queue grows.
   - **Launch** → **Run-selection checkbox (HARD interactive STOP).** Present every `status:todo` Task with priority + dependsOn as unchecked checklist; ASK human which to drain THIS flight. **Do NOT pre-check all, do NOT assume "all", do NOT launch until human returns checked subset.** Only auto-addition allowed: unmet `dependsOn` of checked Task (warn: "billing-export needs auth-login — adding it"). Set `selected:true` ONLY on human-chosen set (+ pulled-in deps). Human checks nothing → do not launch.
4. **Invoke [/e2e-flight](../e2e-flight/SKILL.md)** for first selected Task. **Flight implements ONE Task per invocation, then exits (ADR 0022).** Tell human: "Flight implements one Task per `/e2e-flight` run. I've kicked off `<id>`; re-run `/e2e-flight` for each remaining selected Task, then `/e2e-engineering` to QA sign-off. Watch progress tailing `tasks/<id>/progress.txt`."

Each `/e2e-flight` invocation is fresh context — pre-impl grilling never contaminates implementation.

---

## Implementation phase

Entry: PRD approved (gate 1 passed). **Implementation runs in [/e2e-flight](../e2e-flight/SKILL.md)** — one Task per spawn, headless, no loop, no context monitoring (ADR 0022). Flight owns canonical per-spawn process; see its SKILL.md. Sub-steps below are shared building blocks flight uses. Single-Task legacy may still run simplified inline version — NO 65%/gate-reset checkpoint machinery (ADR 0022).

1. [to-issues](../../shared/skills/e2e-engineering/impl/to-issues.md) — split PRD into vertical slices, emit `depends_on` DAG, author test-case `.md` docs upfront, attach `testCases[]` per story. Reads `ARCHITECTURE.md` §1–§2 (§Index for offset/limit) to pin each story's `integration` decision. Output born `ready-for-agent` (skips triage).
2. [triage](../../shared/skills/e2e-engineering/impl/triage.md) — only for EXTERNALLY-sourced work + walled refactor candidates. Forward-flow slices skip it.

(Language reconciled in pre-impl grill-with-docs — Implementation does NOT re-grill. Per-slice gap-finding = [slice gap-check](../../shared/skills/e2e-engineering/impl/tdd.md).)

### The loop (skill-driven, in-session — ADR 0005)

**Worktree reconciliation (FIRST, every loop entry — incl. fresh-session resume).** Run `git worktree list`, reconcile against prd.json before computing ready set:
- Worktree whose story is `done` → already merged; remove it (`ExitWorktree`).
- Worktree whose story is `todo`/`in-progress` → abandoned in-flight slice. Tear down (discard un-merged branch if no committed work; if commits exist, note + remove — story re-dispatches clean). Reset story to `todo`.
- Story marked in-flight in prd.json but NO worktree on disk → reset to `todo`.

Repeat until COMPLETE (all stories `status: done`):

1. **Compute ready set** — stories whose `depends_on` all `done` AND own `status: todo`.
2. **Fan-out** — dispatch each ready story to OWN git worktree + subagent (`EnterWorktree`). Inject [constitution](../../shared/skills/e2e-engineering/constitution.md) + [api-testing standard](../../shared/skills/e2e-engineering/standards/api-testing.md) + story (incl. `integration` decision) + testCases. Brownfield / ARCHITECTURE.md exists → also inject story's SCOPED slice of ARCHITECTURE.md (§Index for offset/limit — this layer's naming + ownership + anti-patterns, NOT whole doc). Subagent runs [tdd](../../shared/skills/e2e-engineering/impl/tdd.md): gap-check → red-green-refactor (unit + API/integration via Playwright `request`; UI Manual, no automation — Fork Y) → return compact manifest with `evidencePaths[]`.
   - **HARD GATE 2 — TDD red before green.** Each subagent writes failing test before production code. Enforced inside tdd.md.
   - **HARD GATE 3 — debug escalation.** Subagent 3 failed fixes → orchestrator re-dispatches ONCE with [systematic-debugging](../../shared/skills/e2e-engineering/impl/systematic-debugging.md). Still red → mark story `blocked`, append `## Blocked` in progress.txt, keep draining. Escalate to human ONLY on stall. Emit `<e2e-stall reason="all-stories-blocked" />` before escalating.
3. **Fan-in (orchestrator, serial — sole writer):** per returned summary, run per-slice review's two ordered stages, then merge-readiness check, then merge.
   - **Stage 1 — spec-compliance check.** Slice satisfies story's acceptanceCriteria EXACTLY? Verdict `✅ spec-compliant` or `❌ issues found`. Issues → bounce back to slice subagent, re-run stage 1 after fix. Do NOT advance to stage 2 until spec-compliant.
   - **Stage 2 — quality check.** Slice checked against [constitution](../../shared/skills/e2e-engineering/constitution.md) AND (ARCHITECTURE.md exists) ownership/naming/integration rules — catches new class at URL existing class owns, duplicate component file, second API-client key, naming break. Findings Critical / Important / Minor. Critical/Important → bounce back, re-run after fix. Minor → note. Do NOT advance to merge-readiness until stage 2 clears.
   - **Bounce ceiling (token-runaway guard).** Stage-1 or stage-2 bounce capped at **3 round-trips**. Still failing after 3 → STOP: mark story `blocked`, append `## Blocked` in progress.txt, tear down worktree, keep draining.
   - **Merge-readiness check.** Worktree no uncommitted changes; slice's feature E2E + affected tests pass; branch ahead of baseBranch. Any fail → bounce back (same 3-round-trip ceiling), do not merge.
   - Merge worktree branch into baseBranch. Resolve conflicts (never discard work).
   - **Remove worktree** (`ExitWorktree`) immediately after successful merge — life ends at merge.
   - **Persist sidecars + pointers** (sole writer): write `manifests/<story-id>/slice-result.json` ([schema](../../shared/skills/e2e-engineering/schemas/slice-result.json.md)) from sub-agent manifest; write `manifests/<story-id>/review-bundle.json` ([schema](../../shared/skills/e2e-engineering/schemas/review-bundle.json.md)) before expert review; write `manifests/<story-id>/review-result.json` ([schema](../../shared/skills/e2e-engineering/schemas/review-result.json.md)) from reviewer results. Update prd.json story `resultManifestPath` + `reviewManifestPath`. **Status authority:** reconcile sidecar `status` at fan-in; prd.json is sole source of truth.
   - Write `status: done` in prd.json.
   - Append `## Story Log` line to progress.txt. Stage durable learnings under `## Pending Amendments`.
4. Loop. (No checkpoint / context monitoring — ADR 0022.)

### After COMPLETE

No context monitoring, no checkpoint, no gate reset (ADR 0022).

4. [e2e-loop](../../shared/skills/e2e-engineering/impl/e2e-loop.md) — author cross-slice **UI regression test-case DOCS** (Manual → human-QA walk). **GATE 4 RETIRED (ADR 0024, Fork Y)** — UI not automated; no "E2E green" exit.
5. [verification](../../shared/skills/e2e-engineering/impl/verification.md) — **HARD GATE 5 (ADR 0024, ADR 0025):** full automated suite (unit + API) run + AC-checklist-vs-code. NO live-UI exercise. Failures recorded in `qa-signoff.md ## Gate 5 Failures` → Task proceeds to `pending-qa`; human routes each to a repair Task at QA sign-off. Does NOT mark `blocked` on test failure (ADR 0025).

---

## Post-implementation phase

Entry: gate 5 passed.

1. [review](../../shared/skills/e2e-engineering/post-impl/review.md) — fresh-context, full-diff, cross-slice audit. Findings ranked by severity. **Multi-Task mode: flight runs this headless per Task** before parking QA.
2. [human-qa](../../shared/skills/e2e-engineering/post-impl/human-qa.md) — walk Manual test-case set. Single human-approval chokepoint: ONE touch approves QA sign-off AND batched `## Pending Amendments` → promote to [constitution](../../shared/skills/e2e-engineering/constitution.md) (bump version) or drop. **Multi-Task mode: batched QA sign-off session** (Step 0): flight deferred per Task to `pending-qa` + qa-signoff.md; human clears all pending-qa Tasks in one pass, routes findings → [triage](../../shared/skills/e2e-engineering/impl/triage.md) → new queue Tasks (ADR 0018).

Task close (single-Task): extract durable learnings, ensure amendments resolved, progress.txt resets on NEXT task. Emit `<e2e-complete stories="N" />`. Multi-Task: flight emits `<e2e-complete>` when selected queue drained; QA sign-off session flips pending-qa → done.

---

## Gates summary

| # | Gate | Type | Where |
|---|------|------|-------|
| 1 | PRD approved → impl | HARD | end of pre-impl |
| 2 | TDD red before green | HARD | in tdd.md per slice |
| 3 | debug escalation (3 strikes → systematic-debugging → blocked → stall→human) | HARD | in loop |
| 4 | ~~E2E suite green → post-impl~~ | RETIRED (ADR 0024, Fork Y — UI not automated, verified in human-QA) | — |
| 5 | verify-before-completion = full unit+API suite run + AC-vs-code (no live-UI); failures → pending-qa + qa-signoff Gate 5 Failures, NOT blocked (ADR 0025) | HARD | verification, in self-review |
| — | coverage / lint / style | SOFT | overridable WITH logged justification; silent skip not allowed |

Hard gates need explicit human consent, surface as red-flags line in sub-skill. Never rationalize past hard gate.

---

## Cross-cutting

- **No context monitoring (ADR 0022).** No 65% checkpoint, no gate reset, no handoff/respawn. Token fix = forced fan-out, not checkpointing. Supersedes ADR 0002 + 0014.
- **Resume via state, not handoff.** Fresh session: `queue.json` (which Task) → `tasks/<id>/prd.json` (slices done/todo/blocked) → `progress.txt` (tail). No handoff doc.
- **ARCHITECTURE.md governance** (schema: [architecture](../../shared/skills/e2e-engineering/schemas/architecture.md)). Written ONLY in human phases; implementation loop READ-ONLY. Sub-agent spots drift → PROPOSES in summary → staged as `## Pending Amendment` — orchestrator never edits mid-loop. Use §Index for offset/limit when reading. See ADR 0013.
- **Writing style:** state artifacts (progress.txt) = caveman:ultra. Skill files (SKILL.md, schemas, sub-skills) = caveman:ultra. User-facing conversation = caveman:full. Code, commits, PRs = normal prose.
