---
name: e2e-flight
description: >-
  Headless implementation worker for the e2e-engineering flow. Implements exactly ONE Task from the queue then exits — no external loop, no context monitoring. Within the spawn it IS the orchestrator: fans out each slice to a sub-agent in its own worktree (impl wave), runs an expert-review wave before merge, then self-reviews and parks human-QA. Headless counterpart to the interactive front door /e2e-engineering. Use when the user says "e2e-flight", "/e2e-flight", "flight", "drain the queue", "run the flight loop", or "implement the selected tasks".
---

# e2e-flight — one-Task implementation worker (Codex runtime)

Sibling to [/e2e-engineering](../e2e-engineering/SKILL.md). Headless implementation. Read CONTEXT.md for any term. Governed by ADR 0022 and the e2e-flight process spec in the source repository.

**One Task per invocation, then exit.** No loop, no respawn, no context monitoring. Re-invoke `/e2e-flight` for next Task. Task finishes in one spawn or stays resumable via `queue.json`/`prd.json` status.

**Token rule.** Blowup cause: fan-out not firing → 126 inline calls → 227-turn O(N²) chain. Fix: fan-out FORCED (Step 0), inline slice-impl = hard STOP (Step 3). Sub-agents hold heavy tool calls, return manifests — keeps orchestrator context small without checkpoint.

---

## Step 0 — bootstrap + forcing mechanism (FIRST, always)

1. **Resolve shared skill root once.** Set `sharedSkillsRoot = skills/e2e-engineering` from repo root. Verify required files exist: `constitution.md`, `impl/tdd.md`, `impl/systematic-debugging.md`, `schemas/slice-result.json.md`, `schemas/review-bundle.json.md`, `schemas/review-result.json.md`, `schemas/qa-signoff.md`, and `agents/`. Missing → `<e2e-stall reason="shared-skills-missing" />` + EXIT. Runtime wrapper dirs (`.agents/skills/...`, `.claude/skills/...`) are entry points only — never probe them for shared sub-skills/schemas/constitution during execution.
2. **Capability probe (fail-closed).** Static requirement: `spawn_agent` / `spawn_agents_on_csv`. Live probe: attempt no-op spawn (trivial exit instruction); fails → `<e2e-stall reason="fanout-unavailable" />` + EXIT. Worker-change probe: record orchestrator branch + HEAD; spawn disposable worker; instruct it to create + commit a probe branch; verify branch/commit visible from orchestrator; check whether orchestrator branch + HEAD changed; then delete only the probe branch and restore original branch. Branch/commit invisible → `<e2e-stall reason="worker-changes-unavailable" />` + EXIT. Branch visible + checkout unchanged → **parallel Codex mode**. Branch visible + checkout changed → **Codex serial branch mode** (one impl worker at a time; no parallel ready-set dispatch). NEVER fall back to inline slice work or full text-patch transfer for normal slices.
3. No driver, no lock, no context monitoring. No handoff docs, no checkpoint, no respawn.
4. Orchestrator output = caveman-ultra, essential only (token discipline).
5. **Init flow-retro tally (ADR 0027).** Start counters accumulated across this spawn for the flow-retro (`$sharedSkillsRoot/schemas/flow-retro.md`): bounces (by tier), blocked slices + cause, gate-5 failures, stalls, fan-out waves (impl + review), rejected un-evidenced Criticals. Bump them as they occur in Steps 3/5; emit at Step 6.

---

## Step 1 — pick ONE Task

Read `.e2e-engineering/queue.json` (offset/limit — only what you need).

- User named Task → take it.
- Else pick: `status:ready-for-flight` AND every `dependsOn` in {done, pending-qa}, highest priority first (ADR 0029). `needs-spec` Tasks are NOT pickable — they have no approved PRD.
- No pickable Task → `<e2e-complete />` + EXIT.

**Master-clean check.** `git status` on master — any uncommitted changes → `<e2e-stall reason="master-dirty — commit or clean before flight" />` + EXIT.

**Task lock + branch.** Commit `queue.json` status `ready-for-flight→in-progress` to master. Create/update `task/<id>` from master, then return to master. Orchestrator state artifacts live on master. Task branch receives code merges + verification only. Sub-agents work in isolated branches. Before any checkout: commit orchestrator artifacts; no stash.

Task root: `.e2e-engineering/tasks/<id>/`.

---

## Step 2 — reconcile + read state

Read (offset/limit, only needed sections): `tasks/<id>/prd.json` (slice DAG) + `tasks/<id>/progress.txt`.

- **2.1 — structure missing/invalid** (no prd.json, no DAG, no test-cases): do NOT improvise. Tell user to plan via `/e2e-engineering`, EXIT.
- **2.2 — prior in-progress/stall mess** (slices in-flight with no active spawn): propose reconciliation, EXIT — never blindly resume dirty state.
- **Clean reconcile**: slice in-flight with no active spawn → reset to `todo`. Proceed.

**Docker env cache (brownfield/docker projects).** Read `docker-compose.yml` (+ `docker-compose.override.yml` if present) ONCE. Extract required env/config files: `env_file` entries + volume-mounted config paths. Cache this list — included in every sub-agent spawn manifest in Step 3. Do NOT re-read per slice.

**Codebase-map (brownfield only).** Missing `tasks/<id>/codebase-map.md` → `<e2e-stall reason="codebase-map-missing — pre-impl incomplete, run /e2e-engineering" />` + EXIT. Do NOT cold-read source files to compensate. If present: read §1–§3 ONCE (§Index for offset/limit). Hold in context. Do NOT re-read in Steps 3 or 4.

---

## Step 3 — per-slice loop (flight IS the orchestrator)

Sole writer: only orchestrator writes `prd.json` + `progress.txt` + evidence sidecars (`manifests/<story-id>/`). Sub-agents return slice result manifests (`$sharedSkillsRoot/schemas/slice-result.json.md`); never touch shared state.

Repeat until DAG drained (every slice `done` or `blocked`):

1. **Compute ready set** — slices whose `depends_on` are all `done` AND own `status: todo`.
2. **Impl dispatch wave** — write ready-set manifest JSON (slice ids + injection payload), then dispatch via `spawn_agents_on_csv` (or `spawn_agent`/`wait_agent`). Record dispatch table in memory: `agentId -> taskId, sliceId, expectedBranch, attempt`. Codex branch-visible integration is required: each worker creates and commits to `slice/<story-id>` and returns that branch name in its slice result manifest. Worker NEVER merges into the Task branch. Parallel Codex mode dispatches disjoint ready-set slices concurrently. Codex serial branch mode dispatches exactly one ready slice at a time: orchestrator creates/switches to `slice/<story-id>` from the Task branch before spawning, worker commits on the current branch without switching, orchestrator waits/validates, switches back to Task branch, then merges. Each sub-agent injection: `$sharedSkillsRoot/constitution.md` + `$sharedSkillsRoot/standards/api-testing.md` + slice (acceptanceCriteria, sliceType, `integration` decision) + testCases + (brownfield) SCOPED slice of `ARCHITECTURE.md` (use §Index for offset/limit on relevant sections). `ui` slices ALSO get `$sharedSkillsRoot/standards/ui-design.md` + the SCOPED slice of `DESIGN.md` (register + relevant tokens/components, §Index offset/limit; READ-only in flight — ADR 0030).

   **Worktree env/config bootstrap** (included in spawn manifest). Pass cached docker env file list (from Step 2) in each sub-agent's spawn payload. Sub-agent copies into its worktree on start. Do NOT stage/commit these files — untracked only. Required file missing from main tree → sub-agent surfaces it as blocker in slice result manifest; does not silently skip.

   Sub-agents run `$sharedSkillsRoot/impl/tdd.md`. Each completes by returning a **slice result manifest** (`$sharedSkillsRoot/schemas/slice-result.json.md`): `{ sliceId, status, summary, testsPassed, branch, evidencePaths[], findings[] }`. Chat carries manifest pointers only; code changes and logs stay in git/test artifacts.

   **Completion contract.** Orchestrator learns a worker finished only from the sub-agent handle (`wait_agent` completion) plus final manifest. Then validate: JSON shape, `sliceId`, `status`, expected `branch`, branch exists, branch is ahead of Task branch, and `evidencePaths[]` exist/are inspectable. Invalid/missing manifest, branch, or evidence paths → bounce/stall; never mark done from branch existence alone. Final worker message must not contain raw logs/diffs or long narrative.

   - **GATE 2 (hard)** — failing test before production code (inside tdd).
   - **GATE 3 (hard)** — 3 failed fixes → re-dispatch ONCE with `$sharedSkillsRoot/impl/systematic-debugging.md`; still red → mark slice `blocked`, keep draining.
   - **DO NOT do slice-impl inline.** Orchestrator writing slice production code = hard red-flag STOP.

3. **Expert-review wave (artifact-driven, BEFORE merge).** Slice green → orchestrator writes manifest-first **review bundle** (`$sharedSkillsRoot/schemas/review-bundle.json.md`): branch names, base/head commits, reviewer list, changed files, `git diff --stat`, test command outcomes, and paths to logs/test cases. Do NOT load or paste full raw diffs/logs into orchestrator context; reviewers pull scoped hunks/logs themselves from the bundle. Dispatch reviewer agents via `spawn_agents_on_csv` / `spawn_agent`; parallel is preferred, bounded batches are allowed when runtime agent slots are constrained. In Codex, use standard `worker` agents and inject the matching canonical expert spec from `$sharedSkillsRoot/agents/<role>.md` into each reviewer prompt:
   - schema/db → `dba` + `backend-architect`
   - api/logic → `backend-architect` + `test-reviewer`
   - ui → `frontend-reviewer` (reviews against the approved `DESIGN.md` + `$sharedSkillsRoot/standards/ui-design.md` — deviation = Important, anti-slop defect = normal severity) + `backend-architect` (frontend lens)
   - every slice → `test-reviewer` (AC coverage)

   Reviewer roles above are prompt roles, not Codex `agent_type` names. Always spawn Codex expert reviewers with `agent_type: worker`; never spawn `backend-architect`, `dba`, `frontend-reviewer`, or `test-reviewer` as tool roles, even if the runtime advertises them. Reviewers receive review-bundle path/content + canonical expert spec only — NOT worktree path (Codex worktree isolation is internal; path coupling fails silently). Each returns **reviewer result** (`$sharedSkillsRoot/schemas/review-result.json.md`): `{ reviewerId, sliceId, findings[] }`.

   **Finding evidence gate.** Critical/Important findings MUST cite evidence: `file:line`, test name, log path, or explicit searched-absence scope. No cite → orchestrator records `Unsubstantiated`, no bounce. Coverage doubt without proof → `NeedsVerification`, not Critical.

   Reviewers read-only, independent. If a reviewer spawn fails due thread/slot limits, close completed/errored agents, retry, then run bounded batches if still constrained. Give each reviewer the same review bundle and no implementation context; never skip `test-reviewer`. Findings: **Critical / Important / Minor / NeedsVerification / Unsubstantiated**. `NeedsVerification` → targeted read-tool reviewer only for disputed source/test scope; cite-backed Critical/Important from that verifier may bounce.

   **Three-tier bounce.** On Critical/Important finding requiring a fix:
   - **Mechanical** (rename/reformat/comment only — zero logic lines changed, verifiable by diff) → impl worker fixes; orchestrator logs `"skip re-review: mechanical, diff confirms no logic change"`. No re-review dispatched.
   - **Limited** (non-mechanical, no logic change) → re-dispatch triggering reviewer only.
   - **Logic change** → full re-review wave.

   Reviewers never fix or merge. **Bounce cap = 3 round-trips** → still failing → mark slice `blocked`, keep draining. Minor → note, don't block.

4. **lint + compile** — orchestrator commands (not agents). Run project lint + build/typecheck; reconcile failures before merge.
5. **Merge** slice branch → Task branch. No stash. Before any checkout, commit orchestrator-owned artifacts on master; uncommitted state before checkout = hard STOP. Sequence: commit master artifacts → `git checkout task/<id>` → `git merge slice/<story-id>` → resolve conflicts (never discard work) → lint/build if needed → `git checkout master`. Branch missing or not ahead of Task branch → bounce/stall, do not ask worker to paste full patches.
6. **Record + persist sidecars** (sole writer):
   - Write `tasks/<id>/manifests/<story-id>/slice-result.json` (`$sharedSkillsRoot/schemas/slice-result.json.md`) from sub-agent's returned manifest.
   - Write `tasks/<id>/manifests/<story-id>/review-result.json` (`$sharedSkillsRoot/schemas/review-result.json.md`) from combined reviewer results (parallel or bounded-batch reviewers for this slice).
   - Update prd.json story: `resultManifestPath`, `reviewManifestPath` (paths relative to Task root), `status: done`.
   - Append sub-agent summary to `progress.txt` (caveman-ultra, status-headed line).
   - **Status authority:** orchestrator reconciles sidecar `status` at fan-in; prd.json is sole source of truth. Never copy sidecar status blindly.

---

## Step 4 — e2e QA pass (task-level, after DAG drained) — GATE 4 RETIRED (ADR 0024, Fork Y)

Run `$sharedSkillsRoot/impl/e2e-loop.md`: author cross-slice **UI regression test-case DOCS** (Manual disposition → human-QA walk) now the whole feature exists. Full Manual scripts (Preconditions/Steps/Expected) → `tasks/<id>/test-cases/` (caveman-ultra). **NO UI automation** — UI is Manual (Fork Y). A cross-slice API journey MAY be automated as a Playwright `request` test; UI never. (No "E2E green" gate here — gate 4 retired; automated unit+API suite is checked at gate 5, Step 5.0.)

---

## Step 5 — verification (gate 5) + self-review (whole task)

- **5.0 — HARD GATE 5 (verification-before-completion).** Run `$sharedSkillsRoot/impl/verification.md`: (a) full automated suite (unit + API/integration) green from clean state; (b) AC-checklist against code — every `acceptanceCriteria[]` maps to a code path AND a covering automated test (unit/API) OR a Manual test-case (UI). Write `manifests/_task/verification-result.json` (`$sharedSkillsRoot/schemas/verification-result.json.md`). **NO live-UI exercise** (no app launch — Fork Y). Red suite or unmapped AC → record failures, proceed to Step 5.1 (do NOT mark `blocked` — see ADR 0025).
- Then review assembled Task against acceptanceCriteria + `$sharedSkillsRoot/constitution.md`.
- **5.1** → run verification on `task/<id>`, then return `master`; write/finalize `progress.txt`, `qa-signoff.md`, verification sidecar, and `queue.json` status `in-progress→pending-qa`; commit. Do NOT set `done` — `done` requires human approval at QA gate (ADR 0018). Applies whether gate 5 was fully green or had failures (failures ride to human-QA in qa-signoff.md).
- **5.2 self-review hard fail** (constitution violation, not test failure) → scoped `git restore` UNCOMMITTED leftovers ONLY (never wipe already-merged slices) + mark Task `blocked` in `queue.json`. Committed slices stay.

---

## Step 6 — defer human-QA

Write `tasks/<id>/qa-signoff.md` (`$sharedSkillsRoot/schemas/qa-signoff.md`, caveman-ultra): manual test cases to walk, auto-verified ACs to eyeball, staged pending amendments. If gate 5 had failures, write `## Gate 5 Failures` section (each failing test/AC as a finding → triage entry for human to route into a new repair Task at QA sign-off). Do NOT run `$sharedSkillsRoot/post-impl/human-qa.md` — needs human. `/e2e-engineering` owns human review + replanning.

Also write `tasks/<id>/flow-retro.md` (`$sharedSkillsRoot/schemas/flow-retro.md`, caveman-ultra) from the Step-0 tally (ADR 0027): **§Local retro** (process metrics for the team — bounces by tier, blocked slices + cause, gate-5 failures, stalls, fan-out waves, rejected un-evidenced Criticals) + **§Skill-improvement candidates** (friction that looks like an e2e-engineering TOOL defect, for upstream). SEPARATE from qa-signoff.md — keeps tool-facing signal out of the project QA doc. The human routes §Skill-improvement upstream at QA sign-off (third lane), NOT into the client queue.

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
- Probing `.agents/skills/...` or `.claude/skills/...` for shared files after Step 0; use `$sharedSkillsRoot` only.
- Continuing when `$sharedSkillsRoot` required files are missing (stall `shared-skills-missing`).
- Fallback to inline when `spawn_agent`/`spawn_agents_on_csv` unavailable (stall + exit).
- Fallback to text patches when worker branch commits are unavailable (stall `worker-changes-unavailable`).
- Running multiple implementation workers when Step 0 selected Codex serial branch mode.
- Skipping `test-reviewer` because reviewer agent slots are constrained; use bounded batches instead.
- Re-introducing loop / checkpoint / handoff / 65% monitoring (ADR 0022 — gone).
- Running [human-qa](../e2e-engineering/post-impl/human-qa.md) headless (write qa-signoff.md instead).
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
- Leaving master with uncommitted queue/prd/progress/sidecar artifacts before checkout.
- Cold-reading source files when `codebase-map.md` missing (stall instead — Step 2).
- Dispatching full re-review wave for mechanical fixes (skip re-review per [[Three-tier bounce]]).
- Loading full raw diffs/logs into orchestrator context for review; write `review-bundle.json` and let reviewers pull scoped evidence.
- Accepting worker final messages that paste raw logs/diffs instead of returning `evidencePaths[]`.
- Passing worktree path to reviewer agents — pass review bundle (artifact package) instead.
- Spawning Codex named expert roles directly (`backend-architect`, `dba`, `frontend-reviewer`, `test-reviewer`) instead of `worker` + injected reviewer prompt role.
