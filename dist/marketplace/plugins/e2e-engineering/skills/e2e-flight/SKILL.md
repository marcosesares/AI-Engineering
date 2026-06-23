---
name: e2e-flight
description: >-
  Headless implementation worker for the e2e-engineering flow. Implements exactly ONE Task from the queue then exits — no external loop, no context monitoring. Within the spawn it IS the orchestrator: fans out each slice to a sub-agent in its own worktree (impl wave), runs an expert-review wave before merge, then self-reviews and parks human-QA. Headless counterpart to the interactive front door /e2e-engineering. Use when the user says "e2e-flight", "/e2e-flight", "flight", "drain the queue", "run the flight loop", or "implement the selected tasks".
---

# e2e-flight — one-Task implementation worker

Sibling to [/e2e-engineering](../e2e-engineering/SKILL.md). Headless implementation. Read CONTEXT.md for any term. Governed by ADR 0022 and the e2e-flight process spec in the source repository.

**One Task per invocation, then exit.** No loop, no respawn, no context monitoring. Re-invoke `/e2e-flight` for next Task. Task finishes in one spawn or stays resumable via `queue.json`/`prd.json` status.

**Token rule.** Blowup cause: fan-out not firing → 126 inline calls → 227-turn O(N²) chain. Fix: fan-out FORCED (Step 0), inline slice-impl = hard STOP (Step 3). Sub-agents hold heavy tool calls, return summaries — keeps orchestrator context small without checkpoint.

---

## Step 0 — bootstrap + forcing mechanism (FIRST, always)

1. Load dispatch tools. `ToolSearch` → load `Agent` + `EnterWorktree`. Either fails → `<e2e-stall reason="fanout-unavailable" />` + EXIT. NEVER fall back to inline slice work.
2. No driver, no lock, no context monitoring. No handoff docs, no checkpoint, no respawn.
3. Orchestrator output = caveman-ultra, essential only (token discipline).
4. **Init flow-retro tally (ADR 0027).** Start counters accumulated across this spawn for the [flow-retro](../../shared/skills/e2e-engineering/schemas/flow-retro.md): bounces (by tier), blocked slices + cause, gate-5 failures, stalls, fan-out waves (impl + review), rejected un-evidenced Criticals. Bump them as they occur in Steps 3/5; emit at Step 6.

---

## Step 1 — pick ONE Task

Read `.e2e-engineering/queue.json` (offset/limit — only what you need).

- User named Task → take it.
- Else pick: `status:todo` AND every `dependsOn` in {done, pending-qa}, highest priority first.
- No pickable Task → `<e2e-complete />` + EXIT.

**Master-clean check.** `git status` on master — any uncommitted changes → `<e2e-stall reason="master-dirty — commit or clean before flight" />` + EXIT.

**Task lock + branch.** Commit `queue.json` status `todo→in-progress` to master. Then `git checkout -b task/<id>` from master. Orchestrator works on `task/<id>` throughout. Sub-agents work in isolated worktrees. Master not touched again until Step 5.1.

Task root: `.e2e-engineering/tasks/<id>/`.

---

## Step 2 — reconcile + read state

Read (offset/limit, only needed sections): `tasks/<id>/prd.json` (slice DAG) + `tasks/<id>/progress.txt`.

- **2.1 — structure missing/invalid** (no prd.json, no DAG, no test-cases): do NOT improvise. Tell user to plan via `/e2e-engineering`, EXIT.
- **2.2 — prior in-progress/stall mess** (worktrees on disk, slices in-flight with no commit): propose reconciliation, EXIT — never blindly resume dirty state.
- **Clean reconcile**: slice in-flight with no commit → reset to `todo`. Proceed.

**Docker env cache (brownfield/docker projects).** Read `docker-compose.yml` (+ `docker-compose.override.yml` if present) ONCE. Extract required env/config files: `env_file` entries + volume-mounted config paths. Cache this list — used by every `EnterWorktree` call in Step 3. Do NOT re-read per slice.

**Codebase-map (brownfield only).** Missing `tasks/<id>/codebase-map.md` → `<e2e-stall reason="codebase-map-missing — pre-impl incomplete, run /e2e-engineering" />` + EXIT. Do NOT cold-read source files to compensate. If present: read §1–§3 ONCE (§Index for offset/limit). Hold in context. Do NOT re-read in Steps 3 or 4.

---

## Step 3 — per-slice loop (flight IS the orchestrator)

Sole writer: only orchestrator writes `prd.json` + `progress.txt` + evidence sidecars (`manifests/<story-id>/`). Sub-agents return slice result manifests ([schema](../../shared/skills/e2e-engineering/schemas/slice-result.json.md)); never touch shared state.

Repeat until DAG drained (every slice `done` or `blocked`):

1. **Compute ready set** — slices whose `depends_on` are all `done` AND own `status: todo`.
2. **Fan-out impl wave** — dispatch each ready slice to its OWN git worktree + sub-agent (`EnterWorktree` + `Agent`). Run [tdd](../../shared/skills/e2e-engineering/impl/tdd.md). Parallel ONLY across disjoint file sets (same-file slices serialized by `depends_on` in to-issues). Inject: [constitution](../../shared/skills/e2e-engineering/constitution.md) + [api-testing standard](../../shared/skills/e2e-engineering/standards/api-testing.md) + slice (acceptanceCriteria, sliceType, `integration` decision) + testCases + (brownfield) SCOPED slice of `ARCHITECTURE.md` (use §Index for offset/limit on the relevant sections).

   **Worktree env/config bootstrap** (immediately after `EnterWorktree`, before sub-agent dispatch). Copy cached docker env file list (from Step 2) into the worktree. Use `cp`/`Copy-Item`. Do NOT stage/commit these files — untracked, cleaned by `ExitWorktree`. Required file missing from main tree → sub-agent surfaces it as a blocker in slice result manifest, does not silently skip.

   Sub-agents complete by returning evidence-pointer-first **slice result manifest** ([schema](../../shared/skills/e2e-engineering/schemas/slice-result.json.md)): `{ sliceId, status, summary, testsPassed, branch, evidencePaths[], findings[] }`. Worker NEVER merges into the Task branch. Final worker message must not contain raw logs/diffs or long narrative.

   - **GATE 2 (hard)** — failing test before production code (inside tdd).
   - **GATE 3 (hard)** — 3 failed fixes → re-dispatch ONCE with [systematic-debugging](../../shared/skills/e2e-engineering/impl/systematic-debugging.md); still red → mark slice `blocked`, keep draining.
   - **DO NOT do slice-impl inline.** Orchestrator writing slice production code = hard red-flag STOP.

3. **Expert-review wave (in worktree, BEFORE merge).** Slice green → dispatch role reviewer agents **in parallel** by `sliceType` (all agents for a given slice fire simultaneously in one message):
   - schema/db → [dba](../../agents/dba.md) + [backend-architect](../../agents/backend-architect.md)
   - api/logic → [backend-architect](../../agents/backend-architect.md) + [test-reviewer](../../agents/test-reviewer.md)
   - ui → [frontend-reviewer](../../agents/frontend-reviewer.md) + frontend lens of [backend-architect](../../agents/backend-architect.md)
   - every slice → [test-reviewer](../../agents/test-reviewer.md) (AC coverage)

   **Reviewer context injection.** Before dispatching, read method signatures (not bodies) of existing test files touched by this slice. Inject as `existingTests[]` in each reviewer prompt. Reviewers must cite a specific line/test proving a coverage gap before assigning Critical — orchestrator rejects un-evidenced Criticals without bounce.

   Reviewers are read-only and independent — always parallel, never serial. Each reviews slice vs PRD + [constitution](../../shared/skills/e2e-engineering/constitution.md) + (brownfield) ARCHITECTURE slice + `existingTests[]`. Each returns **reviewer result**: `{ reviewerId, sliceId, findings[] }`. Findings: **Critical / Important / Minor**.

   **Three-tier bounce.** On Critical/Important finding requiring a fix:
   - **Mechanical** (rename/reformat/comment only — zero logic lines changed, verifiable by diff) → impl worker fixes; orchestrator logs `"skip re-review: mechanical, diff confirms no logic change"`. No re-review dispatched.
   - **Limited** (non-mechanical, no logic change) → re-dispatch triggering reviewer only.
   - **Logic change** → full re-review wave.

   Reviewers never fix or merge. **Bounce cap = 3 round-trips** → still failing → mark slice `blocked`, tear down worktree, keep draining. Minor → note, don't block.

4. **lint + compile** — orchestrator commands (not agents). Run project lint + build/typecheck; reconcile failures before merge.
5. **Merge** slice branch → Task branch. Orchestrator owns this merge (resolve conflicts, never discard work). Remove worktree immediately (`ExitWorktree`) — life ends at merge.
6. **Record + persist sidecars** (sole writer):
   - Write `tasks/<id>/manifests/<story-id>/slice-result.json` ([schema](../../shared/skills/e2e-engineering/schemas/slice-result.json.md)) from sub-agent's returned manifest.
   - Write `tasks/<id>/manifests/<story-id>/review-result.json` ([schema](../../shared/skills/e2e-engineering/schemas/review-result.json.md)) from combined reviewer results (all dispatched reviewers for this slice).
   - Update prd.json story: `resultManifestPath`, `reviewManifestPath` (paths relative to Task root), `status: done`.
   - Append sub-agent summary to `progress.txt` (caveman-ultra, status-headed line).
   - **Status authority:** orchestrator reconciles sidecar `status` at fan-in; prd.json is sole source of truth. Never copy sidecar status blindly.

---

## Step 4 — e2e QA pass (task-level, after DAG drained) — GATE 4 RETIRED (ADR 0024, Fork Y)

Run [e2e-loop](../../shared/skills/e2e-engineering/impl/e2e-loop.md): author cross-slice **UI regression test-case DOCS** (Manual disposition → human-QA walk) now the whole feature exists. Full Manual scripts (Preconditions/Steps/Expected) → `tasks/<id>/test-cases/` (caveman-ultra). **NO UI automation** — UI is Manual (Fork Y). A cross-slice API journey MAY be automated as a Playwright `request` test; UI never. (No "E2E green" gate here — gate 4 retired; automated unit+API suite is checked at gate 5, Step 5.0.)

---

## Step 5 — verification (gate 5) + self-review (whole task)

- **5.0 — HARD GATE 5 (verification-before-completion).** Run [verification](../../shared/skills/e2e-engineering/impl/verification.md): (a) full automated suite (unit + API/integration) green from clean state; (b) AC-checklist against code — every `acceptanceCriteria[]` maps to a code path AND a covering automated test (unit/API) OR a Manual test-case (UI). Write `manifests/_task/verification-result.json` ([schema](../../shared/skills/e2e-engineering/schemas/verification-result.json.md)). **NO live-UI exercise** (no app launch — Fork Y). Red suite or unmapped AC → record failures, proceed to Step 5.1 (do NOT mark `blocked` — see ADR 0025).
- Then review assembled Task against acceptanceCriteria + [constitution](../../shared/skills/e2e-engineering/constitution.md).
- **5.1** → on `task/<id>` branch: finalize `progress.txt`. Then `git checkout master`, commit `queue.json` status `in-progress→pending-qa`, `git checkout task/<id>`. Do NOT set `done` — `done` requires human approval at QA gate (ADR 0018). Applies whether gate 5 was fully green or had failures (failures ride to human-QA in qa-signoff.md).
- **5.2 self-review hard fail** (constitution violation, not test failure) → scoped `git restore` UNCOMMITTED leftovers ONLY (never wipe already-merged slices) + mark Task `blocked` in `queue.json`. Committed slices stay.

---

## Step 6 — defer human-QA

Write `tasks/<id>/qa-signoff.md` ([schema](../../shared/skills/e2e-engineering/schemas/qa-signoff.md), caveman-ultra): manual test cases to walk, auto-verified ACs to eyeball, staged pending amendments. If gate 5 had failures, write `## Gate 5 Failures` section (each failing test/AC as a finding → triage entry for human to route into a new repair Task at QA sign-off). Do NOT run [human-qa](../../shared/skills/e2e-engineering/post-impl/human-qa.md) — needs human. `/e2e-engineering` owns human review + replanning.

Also write `tasks/<id>/flow-retro.md` ([schema](../../shared/skills/e2e-engineering/schemas/flow-retro.md), caveman-ultra) from the Step-0 tally (ADR 0027): **§Local retro** (process metrics for the team — bounces by tier, blocked slices + cause, gate-5 failures, stalls, fan-out waves, rejected un-evidenced Criticals) + **§Skill-improvement candidates** (friction that looks like an e2e-engineering TOOL defect, for upstream). SEPARATE from qa-signoff.md — keeps tool-facing signal out of the project QA doc. The human routes §Skill-improvement upstream at QA sign-off (third lane), NOT into the client queue.

---

## Step 7 — exit

Emit exactly one plain status as last line: `<e2e-complete />` (no more pickable Task), `<e2e-task-done id="<id>" />` (Task done/blocked, more remain), `<e2e-stall reason="..." />` (needs human). No respawn.

---

## Token hygiene (every spawn)
- caveman-ultra: all prose artifacts (`progress.txt`, `qa-signoff.md`, test-case `.md`). JSON (`prd.json`/`queue.json`) stays schema-bound.
- **Skill files** (SKILL.md, schemas/*.md, sub-skill .md files): maintained in caveman-ultra. Apply when creating or updating any skill doc.
- offset/limit on all reads — only sections needed; never re-read whole file.
- `progress.txt` = single append-only record; status-headed entries; tail for current state.
- docker config + codebase-map: read ONCE in Step 2, never re-read in Steps 3/4.

## Red flags (stop)
- Slice-impl inline instead of sub-agent dispatch (blowup cause — Step 0 forces fan-out; inline = STOP).
- Fallback to inline when `Agent`/`EnterWorktree` won't load (stall + exit).
- Re-introducing loop / checkpoint / handoff / 65% monitoring (ADR 0022 — gone).
- Running [human-qa](../../shared/skills/e2e-engineering/post-impl/human-qa.md) headless (write qa-signoff.md instead).
- Automating UI with Playwright browser/POM, or opening the app for UI verification (Fork Y/ADR 0024 — UI is Manual → human-QA; automate unit+API only).
- Marking Task `blocked` because gate 5 suite is red (record failures in qa-signoff.md → pending-qa instead — ADR 0025).
- Skipping `## Gate 5 Failures` section when gate 5 had failures (human needs them to route repair Tasks).
- Folding §Skill-improvement into qa-signoff.md, or routing it into the client queue — it's a separate `flow-retro.md` and an upstream lane (ADR 0027).
- `git restore` wiping already-merged slices (uncommitted only).
- Marking Task `done` instead of `pending-qa` after self-review passes (Step 5.1 — ADR 0018).
- Marking Task `blocked` on self-review finding unless it's a constitution violation with no recoverable path.
- Re-reading docker config or codebase-map per-slice (read ONCE in Step 2).
- Staging/committing env/config files in worktree branch (untracked only).
- Touching another Task's `tasks/<id>/` state.
- git stash during flight — no stash ever; master artifacts committed at clean boundaries only.
- Touching master after task branch created, except the two targeted `queue.json` commits (Step 1 lock + Step 5.1 pending-qa).
- Cold-reading source files when `codebase-map.md` missing (stall instead — Step 2).
- Dispatching full re-review wave for mechanical fixes (skip re-review per [[Three-tier bounce]]).
