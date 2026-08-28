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
2. **Bounded-shell probe (fail-closed, ADR 0033).** Adopt [command-execution](../../../skills/e2e-engineering/impl/command-execution.md) for EVERY command this spawn runs (compile, package build, stack-up, lint, tests): bounded + non-interactive + self-terminating. Export the non-interactive env once here. Probe: run a deliberately-blocking command under a 5s bound (POSIX `timeout 5 sleep 30`; PowerShell `Start-Job`+`Wait-Job -Timeout 5`) and confirm control returns. Cannot bound → `<e2e-stall reason="unbounded-shell — runtime cannot time-box commands" />` + EXIT. **Second runaway brake** alongside forced fan-out — a hung command is invisible to the inline-STOP (ADR 0022 Consequences). **Preflight (ADR 0034):** run [flight-preflight](../../../skills/e2e-engineering/scripts/flight-preflight.ps1) (`pwsh -NoProfile -File`; POSIX-without-pwsh → run the same three checks inline per command-execution §1–§2). FAIL → `<e2e-stall reason="preflight-failed" />` + EXIT. `-StopGradleDaemons` is legal ONLY here at Step 0 with zero parallel work.
3. No driver, no lock, no context monitoring. No handoff docs, no checkpoint, no respawn.
4. Orchestrator output = caveman-ultra, essential only (token discipline).
5. **Init flow-retro tally (ADR 0027).** Start counters accumulated across this spawn for the [flow-retro](../../../skills/e2e-engineering/schemas/flow-retro.md): bounces (by tier), blocked slices + cause, gate-5 failures, stalls, fan-out waves (impl + review + verify), bounce rounds per slice vs cap 4, verifier spend (confirmed/refuted/inconclusive), findings left `open-at-cap` + followups produced (P1/P3), un-cited Minors dropped, watchdog kills/hangs (ADR 0036), chunk-driver degrade waves (ADR 0037), carrier API smokes red/green (ADR 0036). Bump them as they occur in Steps 3/5; emit at Step 6.
6. **Tooling-trap re-read (once).** Read the task's `progress.txt` tail + repo `AGENTS.md` (+ any `RESUME`/handover doc) for repo-specific traps (tool filters like rtk wrapping gradlew, path-length rules, banned flags). Apply them this spawn. The UNIVERSAL traps are in the skill itself ([command-execution](../../../skills/e2e-engineering/impl/command-execution.md) + Red flags below) — never re-discover them per slice. Repo tool filters/proxies (rtk etc.) NEVER wrap long-running or compile/test commands — a proxy/filter on gradlew/tsc can mangle output or hang (`rtk proxy gradlew` trap); filters apply to OUTPUT reads only.

---

## Step 1 — pick ONE Task

Read `.e2e-engineering/queue.json` (offset/limit — only what you need).

- User named Task → take it.
- Else pick: `status:ready-for-flight` AND every `dependsOn` in {done, pending-qa}, highest priority first (ADR 0029). `needs-spec` Tasks are NOT pickable — they have no approved PRD.
- No pickable Task → `<e2e-complete />` + EXIT.

**Master-clean check.** `git status` on master — any uncommitted changes → `<e2e-stall reason="master-dirty — commit or clean before flight" />` + EXIT.

**Task lock + branch.** Commit `queue.json` status `ready-for-flight→in-progress` to master. Then `git checkout -b task/<id>` from master. Orchestrator works on `task/<id>` throughout. Sub-agents work in isolated worktrees. Master not touched again until Step 5.1.

Task root: `.e2e-engineering/tasks/<id>/`.

---

## Step 2 — reconcile + read state

Read (offset/limit, only needed sections): `tasks/<id>/prd.json` (slice DAG) + `tasks/<id>/progress.txt`.

- **2.1 — structure missing/invalid** (no prd.json, no DAG, no test-cases): do NOT improvise. Tell user to plan via `/e2e-engineering`, EXIT.
- **2.2 — prior in-progress/stall mess** (worktrees on disk, slices in-flight with no commit): propose reconciliation, EXIT — never blindly resume dirty state.
- **Clean reconcile**: slice in-flight with no commit → reset to `todo`. Proceed.
- **Committed-but-unrecorded reconcile**: slice branch ahead of Task branch with ≥1 commit AND an in-branch evidence README, but no manifest / no review / no merge (worker committed, session died pre-record — flight-stall postmortem): treat the head commit as the slice result. Orchestrator verifies compile/typecheck per slice (workdir, bounded), writes `slice-result.json` from the in-branch evidence README, dispatches the review wave, merges, records. Reset to `todo` ONLY when the slice branch has zero commits ahead — re-dispatching committed work duplicates it.
- **Dirty task-branch reconcile (ADR 0034).** Working tree dirty at entry → it is the prior orchestrator's stranded output (postmortem/skill edits uncommitted after session death — 2026-08-20 incident). Commit it as `state: record <unit>` BEFORE anything else. Never stash, never reset, never discard — the work exists; recording it is cheaper than re-deriving it. The tree must stay clean at every step boundary from here on.
- **Resume pointers (ADR 0034).** Read `tasks/<id>/resume.json` if present ([schema](../../../skills/e2e-engineering/schemas/resume.json.md)) BEFORE prd.json: `headSha`, `phase`, `dispatched[]`, `reviewWave[]`, `worktrees[]`, `stackState`, `teardownOwed`, `gate5`. `teardownOwed:true` → run `down -v` FIRST. `dispatched[]` entries without a manifest on disk → reconcile per the committed-but-unrecorded path above. Stale values are safe by construction (written write-ahead, only cause re-verification). Update it write-ahead at every phase transition and gate step.

**Docker env cache (brownfield/docker projects).** Read `docker-compose.yml` (+ `docker-compose.override.yml` if present) ONCE. Extract required env/config files: `env_file` entries + volume-mounted config paths. Cache this list — used by every `EnterWorktree` call in Step 3. Do NOT re-read per slice.

**Compile detection (cache `compileCmd` once).** Resolve the COMPILE-ONLY check command, §4.1-wins-else-detect (ADR 0032):
1. `ARCHITECTURE.md §4.1 Compile command` present → use it verbatim.
2. else detect from repo root: `pom.xml` → `mvn -B -ntp -q compile`; `build.gradle`/`build.gradle.kts` → gradle wrapper + `compileJava --console=plain --no-daemon`, shell-aware (`./gradlew` POSIX / `.\gradlew.bat` PowerShell/win32); `package.json` → **read the `build` script BODY first** — absent, or a watch/serve script (`--watch`/`-w`/`dev`/`serve`/`start`/`preview`) → `npx --yes tsc --noEmit`; else `npm run build`. Never run a script to discover what it does — that IS the hang (ADR 0033).
3. none of the above → NO compile command; skip the compile check + WARN in `progress.txt`. Do NOT fall back to `mvn` (the original bug, #35).
`compileCmd` is COMPILE-ONLY — it never feeds the gate-5 stack rebuild (that build comes from §4.1 Stack-up). Cache `compileCmd` once for the spawn (alongside the docker-env cache); do NOT re-detect per slice. Whether from §4.1 or detected, it runs under the Step-0 [command-execution](../../../skills/e2e-engineering/impl/command-execution.md) contract — bounded (6 min; gradle focused 12 min), non-interactive, self-terminating; a §4.1 command carrying a watch/serve flag is a §4.1 defect → WARN + skip, never run it.

**Execution amendments (§4.1b, ADR 0036).** Read `ARCHITECTURE.md §4.1b` (test-execution amendments) ONCE if present — its values (test-fork heap, ports, verdict discipline, runner quirks) WIN over the generic budgets. Cache alongside `compileCmd`; pass the relevant lines in every sub-agent spawn.

**Codebase-map (brownfield only).** Missing `tasks/<id>/codebase-map.md` → `<e2e-stall reason="codebase-map-missing — pre-impl incomplete, run /e2e-engineering" />` + EXIT. Do NOT cold-read source files to compensate. If present: read §1–§3 ONCE (§Index for offset/limit). Hold in context. Do NOT re-read in Steps 3 or 4.

---

## Step 3 — per-slice loop (flight IS the orchestrator)

Sole writer: only orchestrator writes `prd.json` + `progress.txt` + evidence sidecars (`manifests/<story-id>/`). Sub-agents return slice result manifests ([schema](../../../skills/e2e-engineering/schemas/slice-result.json.md)); never touch shared state.

Repeat until DAG drained (every slice `done` or `blocked`):

1. **Compute ready set** — slices whose `depends_on` are all `done` AND own `status: todo`.
2. **Fan-out impl wave** — dispatch each ready slice to its OWN git worktree + sub-agent (`EnterWorktree` + `Agent`). Run [tdd](../../../skills/e2e-engineering/impl/tdd.md). **Journal before dispatch (ADR 0034):** write the ready-set manifest JSON (`tasks/<id>/briefs/<wave>/ready-set-NN.json` — slice ids + injection payload, quoting the current task-branch HEAD sha) AND append a dispatch-intent line to `progress.txt`, then COMMIT, then dispatch. Death mid-dispatch leaves a verbatim-replayable brief on disk (wave-5 quota-abort precedent: briefs re-sent verbatim, zero loss). Re-dispatch = re-send the committed manifest; the only field to refresh is the HEAD sha it quotes. **Quota-containment (ADR 0034):** quota headroom unknown OR a prior wave aborted on quota → dispatch in batches of ≤2, one committed manifest per batch — loss bounded to the in-flight batch. Parallel ready-set dispatch stays the default; batching is the degraded mode, never inline work. Parallel ONLY across disjoint file sets (same-file slices serialized by `depends_on` in to-issues). Inject: [constitution](../../../skills/e2e-engineering/constitution.md) + [testing standard](../../../skills/e2e-engineering/standards/testing.md) + [command-execution](../../../skills/e2e-engineering/impl/command-execution.md) (worker runs compile + tests under the same bounded/non-interactive contract) + slice (acceptanceCriteria, sliceType, `integration` decision) + testCases + cached `compileCmd` (Step 2 — worker compiles with this, never assumes Maven) + (brownfield) SCOPED slice of `ARCHITECTURE.md` (use §Index for offset/limit on the relevant sections). **Per sliceType:** `schema/db` → also the [db standard](../../../skills/e2e-engineering/standards/db.md); `api/logic` → also the [api-testing standard](../../../skills/e2e-engineering/standards/api-testing.md) + [backend standard](../../../skills/e2e-engineering/standards/backend.md); `ui` → also the [ui-design standard](../../../skills/e2e-engineering/standards/ui-design.md) + the SCOPED slice of `DESIGN.md` (register + relevant tokens/components, §Index offset/limit; READ-only in flight — ADR 0030). The reviewer `## Digest` sections are retired as injection content — the standards files they summarized ARE the contract; inject the files, not the summaries.

   **Worktree env/config bootstrap** (immediately after `EnterWorktree`, before sub-agent dispatch). Copy cached docker env file list (from Step 2) into the worktree. Use `cp`/`Copy-Item`. Do NOT stage/commit these files — untracked, cleaned by `ExitWorktree`. Required file missing from main tree → sub-agent surfaces it as a blocker in slice result manifest, does not silently skip.

   Sub-agents complete by returning evidence-pointer-first **slice result manifest** ([schema](../../../skills/e2e-engineering/schemas/slice-result.json.md)): `{ sliceId, status, summary, testsPassed, branch, evidencePaths[], findings[] }`. Worker NEVER merges into the Task branch. Final worker message must not contain raw logs/diffs or long narrative.

   - **GATE 2 (hard)** — failing test before production code (inside tdd).
   - **GATE 3 (hard)** — 3 failed fixes → re-dispatch ONCE with [systematic-debugging](../../../skills/e2e-engineering/impl/systematic-debugging.md); still red → mark slice `blocked`, keep draining.
   - **DO NOT do slice-impl inline.** Orchestrator writing slice production code = hard red-flag STOP.
   - **Chunk-driver degrade (ADR 0037).** An impl wave returns ZERO commits/manifests after its budget (workers alive but stalled — some runtimes' write-capable workers complete ~1 tool call/round; a throughput stall, NOT `worker-changes-unavailable` — the Step-0 probe already proved branch visibility) → degrade: halve the slice into small chunks (≤1 file, one AC); worker writes ONE chunk + self-compiles; orchestrator runs the focused tests per chunk and feeds the verdict back. GATE 2 holds — chunk 1 = the failing test (orchestrator confirms red) before the impl chunk. Review wave unchanged (per slice after the last chunk). Record the degrade in `progress.txt` + the retro counter. Still fan-out — chunk-driver is a smaller unit, never inline slice work.

3. **Expert-review wave (in worktree, BEFORE merge).** Slice green → dispatch role reviewer agents **in parallel** by `sliceType` (all agents for a given slice fire simultaneously in one message):
   - schema/db → [dba](../../agents/dba.md) + [backend-architect](../../agents/backend-architect.md)
   - api/logic → [backend-architect](../../agents/backend-architect.md) + [test-reviewer](../../agents/test-reviewer.md)
   - ui → [frontend-reviewer](../../agents/frontend-reviewer.md) (reviews against the approved `DESIGN.md` + [ui-design standard](../../../skills/e2e-engineering/standards/ui-design.md) — deviation = Important, anti-slop defect = normal severity) + frontend lens of [backend-architect](../../agents/backend-architect.md)
   - every slice → [test-reviewer](../../agents/test-reviewer.md) (AC coverage)

   **Reviewer context injection.** Before dispatching, read method signatures (not bodies) of existing test files touched by this slice. Inject as `existingTests[]` in each reviewer prompt. Reviewers must cite a specific line/test proving a coverage gap before assigning Critical. Un-cited Critical/Important are NOT binned — they go to the verify wave (ADR 0035).

   Reviewers are read-only and independent — always parallel, never serial. Each reviews slice vs PRD + [constitution](../../../skills/e2e-engineering/constitution.md) + (brownfield) ARCHITECTURE slice + `existingTests[]`. Each returns **reviewer result**: `{ reviewerId, sliceId, findings[] }` ([schema](../../../skills/e2e-engineering/schemas/review-result.json.md)). Severity enum is exactly **Critical / Important / Minor** — `NeedsVerification` is a pre-verify SIGNAL, not a severity; `Unsubstantiated` is retired (ADR 0035). Orchestrator assigns each finding an `id` + `state` at fan-in.

   **Finding hygiene gate (pre-verify, ADR 0035).** EVERY finding, ANY severity, needs a cite (`file:line`, test name, log path, explicit searched-absence scope) AND an implied ACTION.
   - No ACTION → downgrade: Important→Minor, Minor→dropped.
   - Un-cited Critical/Important → **verify wave**, never binned.
   - Un-cited Minor → dropped, logged in `review-result.json` `notes`, NO verifier spend (a Minor worth fixing is worth citing).
   - Coverage doubt without proof → reviewer sets the finding's `signal: "NeedsVerification"` (severity still carries what it WOULD assign) instead of asserting an unproven Critical → verify wave.

   **Verify wave (ADR 0035).** Runs after EVERY review/re-review fan-in, BEFORE bounce classification. Dispatch [finding-verifier](../../agents/finding-verifier.md) — one per unproven finding, **in parallel** — for `NeedsVerification` findings at Critical/Important + un-cited Critical/Important. Budget ≤8 calls each. Journal `verifyWave[]` in `resume.json` write-ahead before spawn.
   - `confirmed` + cite → `state: open` at the VERIFIER's severity (it owns severity now) → eligible to bounce; the verifier's cite becomes the finding's `evidence`.
   - `refuted` → `state: dropped-refuted`, logged.
   - `inconclusive` → treated as **refuted** (adversarial default — a starved verifier must not manufacture a bounce).
   - **Verify-once + suppress.** Each finding is verified AT MOST ONCE per slice. `dropped-refuted` keys go to `resume.json` `suppressed[]` (`<severity>|<location>|<sha1-8 of message>`); a later re-review may NOT re-raise them. Without suppression the loop never converges.
   - Verify wave does NOT consume a bounce round — it is not a fix.

   **Reviewer prompt budget (hard).** Every reviewer prompt carries a tool-call budget (≤15 calls) and must return bounded JSON only. **Stuck-reviewer protocol:** reviewer hangs or is cancelled with no result → re-dispatch ONCE with halved scope (≤2 checks, ≤8 tool calls). Still nothing → proceed with the remaining reviewers' results, record the gap in `review-result.json` `notes`; never wait unbounded, never block the merge on an unavailable reviewer slot alone — this applies to the INITIAL review wave only. In a re-review round the unreturned reviewer holds an open finding: leave that finding `open` and let the convergence loop continue to the cap, which merges with a followup. Never merge past an `open` finding outside cap exhaustion (ADR 0035) (flight-stall postmortem — one stuck reviewer stalled a whole wave).

   **Severity discipline.** Critical/Important imply an ACTION. A finding marked Important with "no change required" → downgrade to Minor (orchestrator overrides).

   **Convergence loop (ADR 0035 — replaces the bounce cap).** `open[]` = findings with `state: open`, ANY severity.
   - `open[]` empty → Step 3.4 lint+compile → merge.
   - else `bounce.rounds += 1` — **per slice, ABSOLUTE**. New findings surfaced by a re-review NEVER reset it. Durable in `resume.json` `bounce.rounds`, written write-ahead before each bounce dispatch. **Cap = 4.**
     - `bounce.rounds > 4` → cap exhausted → merge + followup (below). NEVER `blocked`.
     - else bounce → impl worker fixes **ALL** open findings in ONE pass (Minors piggyback) → re-review → loop. **Findings a re-reviewer that RE-EXAMINED them no longer raises → `state: fixed`** — nothing else clears them, so without this flip `open[]` never empties and every slice runs to the cap.
   - **Tier picks re-review SCOPE, never whether** — no fix merges unread:
     - **mechanical** (rename/reformat/comment, zero logic lines, verifiable by diff) / **limited** (non-mechanical, no logic change) → re-dispatch **EVERY reviewer that raised an open finding this round** — no more, no fewer.
     - **logic change** → **full re-review wave**.
   - **Re-review budget halves (ADR 0037):** re-review rounds carry ≤8 tool calls, scope = the open findings + the fix diff — never a full re-read. Initial stays ≤15. A finding the re-reviewer could not re-examine stays `open` — the re-examined→`fixed` flip fires only on re-examination, so the loop still converges by the cap.
   - Minor is an ordinary finding. A Minor-only round is legal and costs one round.
   - Merge gate = zero open findings at EVERY severity. Sole exception: cap exhaustion.

   **Cap exhaustion → merge + followup (ADR 0035).** On entering round 5:
   - **MERGE the slice.** Tests are green; the residue is a quality/coverage gap, not a red test.
   - `prd.json` story → `status: done`, `notes: "<n> open findings at cap: <severities>"`.
   - `review-result.json` survivors → `state: "open-at-cap"`.
   - Append each to `tasks/<id>/followups.json` ([schema](../../../skills/e2e-engineering/schemas/followups.json.md)); `suggestedPriority` PER ENTRY from its own severity: Critical → 1, Important/Minor → 3.
   - NEVER write `queue.json` — followups reach the queue via [triage](../../../skills/e2e-engineering/impl/triage.md) at QA sign-off (ADR 0017 writer table intact).
   - Review-driven slice `blocked` is **RETIRED**. GATE 3 (red tests, 3 failed fixes) still blocks — unchanged.

   Reviewers never fix or merge.

4. **lint + compile** — orchestrator commands (not agents). Run project lint + the cached `compileCmd` (Step 2 — compile-only check, not a hardcoded build, not the package build), each bounded + non-interactive per [command-execution](../../../skills/e2e-engineering/impl/command-execution.md) (lint 3 min, compile 6 min). Long producers redirect to a log file (`> run.log 2>&1`) and read the tail after exit — NEVER pipe-to-filter (`Out-String`, `Select-Object -Last`, `head`, `tail` emit nothing until exit; a healthy slow build looks like a hang). Timeout = compile failure, logged `TIMEOUT <cmd> @<budget>s` — reconcile like any other failure, never re-run unchanged more than once. Reconcile failures before merge.
5. **Merge** slice branch → Task branch. Orchestrator owns this merge (resolve conflicts, never discard work). `git merge slice/<story-id> --no-edit` — NEVER bare `merge` (default editor blocks a headless shell forever); `GIT_EDITOR=true` exported at Step 0. Remove worktree immediately (`ExitWorktree`) — life ends at merge.
   **Carrier-level API smoke (ADR 0036).** The merged carrier added/changed Playwright API specs → rebuild the stack per §4.1 Stack-up and run ONLY that carrier's spec files (bounded, `--project <api>`, single-file runs). Red → fix in-slice before the next wave (Gate 3 applies). `ARCHITECTURE.md §4.1` declares the stack rebuild too heavy → WARN in `progress.txt` + defer to gate 5. Blind-written specs shipped stale 200-vs-201 expectations + db-cleanup bugs found only at the final gate — the smoke catches them at merge time.
6. **Record + persist sidecars** (sole writer):
   - Write `tasks/<id>/manifests/<story-id>/slice-result.json` ([schema](../../../skills/e2e-engineering/schemas/slice-result.json.md)) from sub-agent's returned manifest.
   - Write `tasks/<id>/manifests/<story-id>/review-result.json` ([schema](../../../skills/e2e-engineering/schemas/review-result.json.md)) from combined reviewer results (all dispatched reviewers for this slice).
   - Update prd.json story: `resultManifestPath`, `reviewManifestPath` (paths relative to Task root), `status: done`.
   - Append sub-agent summary to `progress.txt` (caveman-ultra, status-headed line).
   - **Status authority:** orchestrator reconciles sidecar `status` at fan-in; prd.json is sole source of truth. Never copy sidecar status blindly.
   - **Evidence hygiene (ADR 0036):** evidence = counts + ≤20-line excerpts. Full logs stay on disk (gitignored `*.log`), deleted at worktree removal — never commit them (two 179KB copies shipped then removed, bf095e3).

---

## Step 4 — e2e QA pass (task-level, after DAG drained) — GATE 4 RETIRED (ADR 0024, Fork Y)

Run [e2e-loop](../../../skills/e2e-engineering/impl/e2e-loop.md): author cross-slice **UI regression test-case DOCS** (Manual disposition → human-QA walk) now the whole feature exists. Full Manual scripts (Preconditions/Steps/Expected) → `tasks/<id>/test-cases/` (caveman-ultra). **NO UI automation** — UI is Manual (Fork Y). A cross-slice API journey MAY be automated as a Playwright `request` test; UI never. (No "E2E green" gate here — gate 4 retired; automated unit+API suite is checked at gate 5, Step 5.0.)

---

## Step 5 — verification (gate 5) + self-review (whole task)

- **5.0 — HARD GATE 5 (verification-before-completion).** Run [verification](../../../skills/e2e-engineering/impl/verification.md): bring the live docker-compose stack up ONCE per `ARCHITECTURE.md §4.1 Stack-up` (owns the package build, e.g. `down -v → quarkusBuild → up --force-recreate --build -d`; unseeded + artifact-copying Dockerfile → WARN + skip host build; no compose → skip). **`up` MUST be detached (`-d`)** and every step bounded per [command-execution](../../../skills/e2e-engineering/impl/command-execution.md) (stack-up 10 min, package build 15 min, full suite 30 min, playwright gate 20 min); long producers redirect to a log file, never pipe-to-filter; readiness by bounded poll, never by attaching. **Background jobs (ADR 0036):** any detached suite/stack step ALSO gets the watchdog — bounded poll + hard deadline → `job_kill` + 10-min log-silence heuristic + orphan sweep by targeted PID after a kill (never `--stop`); a killed step routes as its phase timeout. **Fork-heap + verdict discipline (ADR 0036):** JVM suites ~80+ test classes → test-fork heap rule (§4.1/§4.1b value or the `heap.init.gradle` init script); verdicts read test-result XML only after `BUILD SUCCESSFUL` in the log (stale-XML trap) — per [verification](../../../skills/e2e-engineering/impl/verification.md). **Gate-5 checkpoints (ADR 0034):** record `gate5.phase` in `resume.json` write-ahead before stack-up / before the full suite / before the Playwright gate; death mid-gate resumes from the checkpoint and re-runs ONLY unfinished phases (`teardownOwed` forces `down -v` first). A stack-up or suite **timeout is a gate-5 failure** (strike), never a stall and never `blocked`. Then (a) full automated suite (unit + the client's independent Playwright **API project ONLY**, via the §4.1 `API/integration` API-only cmd / `--project <name>` — NEVER bare `playwright test`) green; (b) AC-checklist against code — every `acceptanceCriteria[]` maps to a code path AND a covering automated test (unit/API) OR a Manual test-case (UI). Red → durable bounded task-level 3-strike loop (`gate5Strikes` in the sidecar; resume-safe; separate from per-slice Gate-3). Tear the stack down (`down -v`) after. Write `manifests/_task/verification-result.json` ([schema](../../../skills/e2e-engineering/schemas/verification-result.json.md)) incl. `gate5Strikes`/`gate5FailureIds[]`. **NO live-UI exercise** (no app launch, browser project never run — Fork Y). Still red after the loop or unmapped AC → record failures, proceed to Step 5.1 (do NOT mark `blocked` — see ADR 0025).
- Then review assembled Task against acceptanceCriteria + [constitution](../../../skills/e2e-engineering/constitution.md).
- **5.1** → on `task/<id>` branch: finalize `progress.txt`. Then `git checkout master`, commit `queue.json` status `in-progress→pending-qa`, `git checkout task/<id>`. Do NOT set `done` — `done` requires human approval at QA gate (ADR 0018). Applies whether gate 5 was fully green or had failures (failures ride to human-QA in qa-signoff.md).
- **5.2 self-review hard fail** (constitution violation, not test failure) → scoped `git restore` UNCOMMITTED leftovers ONLY (never wipe already-merged slices) + mark Task `blocked` in `queue.json`. Committed slices stay.

---

## Step 6 — defer human-QA

Write `tasks/<id>/qa-signoff.md` ([schema](../../../skills/e2e-engineering/schemas/qa-signoff.md), caveman-ultra): manual test cases to walk, auto-verified ACs to eyeball, staged pending amendments. If gate 5 had failures, write `## Gate 5 Failures` section (each failing test/AC as a finding → triage entry for human to route into a new repair Task at QA sign-off). Do NOT run [human-qa](../../../skills/e2e-engineering/post-impl/human-qa.md) — needs human. `/e2e-engineering` owns human review + replanning. Always write `## Followups` (empty when every slice converged) from `followups.json` ([schema](../../../skills/e2e-engineering/schemas/followups.json.md)) — plus `## Release Blockers` IFF an open finding is Critical (ADR 0035). Flight never queues them; triage does at sign-off.

Also write `tasks/<id>/flow-retro.md` ([schema](../../../skills/e2e-engineering/schemas/flow-retro.md), caveman-ultra) from the Step-0 tally (ADR 0027): **§Local retro** (process metrics for the team — bounces by tier, bounce rounds per slice vs cap 4, blocked slices + cause, gate-5 failures, stalls, fan-out waves (impl + review + verify), verifier spend (confirmed/refuted/inconclusive), findings left `open-at-cap` + followups produced (P1/P3), un-cited Minors dropped, watchdog kills/hangs (ADR 0036), chunk-driver degrade waves (ADR 0037), carrier API smokes red/green (ADR 0036)) + **§Skill-improvement candidates** (friction that looks like an e2e-engineering TOOL defect, for upstream). SEPARATE from qa-signoff.md — keeps tool-facing signal out of the project QA doc. The human routes §Skill-improvement upstream at QA sign-off (third lane), NOT into the client queue.

---

## Step 7 — exit

Emit exactly one plain status as last line: `<e2e-complete />` (no more pickable Task), `<e2e-task-done id="<id>" />` (Task done/blocked, more remain), `<e2e-stall reason="..." />` (needs human). No respawn.

---

## Token hygiene (every spawn)
- caveman-ultra: all prose artifacts (`progress.txt`, `qa-signoff.md`, test-case `.md`). JSON (`prd.json`/`queue.json`) stays schema-bound.
- **Skill files** (SKILL.md, schemas/*.md, sub-skill .md files): maintained in caveman-ultra. Apply when creating or updating any skill doc.
- offset/limit on all reads — only sections needed; never re-read whole file.
- `progress.txt` = single append-only record; status-headed entries; tail for current state.
- **State files stay LEAN (ADR 0027):** `progress.txt`/`resume.json`/sidecars carry pointers + counts only; narrative goes to `qa-signoff.md` / `flow-retro.md` once, at the end.
- docker config + codebase-map + `compileCmd` + §4.1b amendments: resolved/read ONCE in Step 2, never re-detect/re-read in Steps 3/4.

## Red flags (stop)
- Slice-impl inline instead of sub-agent dispatch (blowup cause — Step 0 forces fan-out; inline = STOP).
- Running ANY command unbounded, interactive, or foregrounded when it serves/watches/tails (ADR 0033 — a hung shell is a runaway neither fan-out nor inline-STOP catches; that is the hang, not a slow build).
- Skipping or failing the Step-0 preflight (ADR 0034 — fail-closed: `<e2e-stall reason="preflight-failed" />`).
- In-command `Set-Location`/`cd` instead of the workdir param (failed chdir silently runs the command in the wrong tree). No workdir param → `cd <abs> && pwd`, chained `&&` never `;`.
- Piping long producers through `Out-String` / `Select-Object -Last` / `head` / `tail` (emits nothing until exit — a healthy slow build is indistinguishable from a hang). Redirect to a log file, read tail after.
- Bare `git merge` / bare `git commit` (default editor blocks a non-interactive shell forever) — always `--no-edit` / `-m ...`; `GIT_EDITOR=true` exported at Step 0.
- Bare `vitest` (watch mode never exits) — always `npx vitest run`.
- `npx` without `--yes` or without a binary pre-check (install prompt / silent download blocks headless).
- `./gradlew --stop` during a flight (machine-wide daemon sweep while parallel work exists — banned; safe ONLY at Step 0 preflight with zero parallel work).
- Wrapping a compile/test command in a repo tool filter/proxy (`rtk proxy gradlew`) — filters apply to output READS only; proxied compiles mangle verdicts or hang.
- Waiting unbounded on a hung reviewer (re-dispatch once with halved scope; then proceed with the rest and record the gap in `notes`).
- Resetting a committed slice to `todo` when its branch has commits ahead (use the committed-but-unrecorded reconcile path — Step 2.2).
- Crossing a step boundary (dispatch/merge/gate) with a dirty working tree (ADR 0034 — commit `state: record <unit>` first; never stash).
- Dispatching without a committed ready-set manifest + progress intent line (ADR 0034 journal-before-dispatch).
- Selecting `npm run build` without reading the script body, or `npx` without `--yes` (watch script / install prompt = infinite block).
- `docker compose up` without `-d` at gate 5, or polling readiness by attaching to logs.
- Treating a gate-5 stack-up/suite timeout as `blocked` or a stall (it is a gate-5 failure → `pending-qa`, ADR 0025).
- Assuming `mvn` / a hardcoded build instead of the §4.1-or-detected `compileCmd` (bug #35 cause — Step 2 detects, §4.1 wins; none → skip + WARN, never `mvn`).
- Feeding `compileCmd` into the gate-5 stack rebuild — the package build comes ONLY from §4.1 Stack-up.
- Running bare `playwright test` at gate 5 (runs the browser/UI project) — API project ONLY.
- Leaving the gate-5 docker stack up (orphan), or resetting `gate5Strikes` on resume.
- Waiting unbounded on a background job (watchdog: bounded poll + hard deadline + `job_kill` + 10-min silence heuristic + orphan sweep — ADR 0036).
- Committing a full log as evidence (counts + ≤20-line excerpts only — ADR 0036).
- Reading test-result XML before confirming `BUILD SUCCESSFUL` in the log (stale-XML trap — ADR 0036).
- Running a large JVM suite without a test-fork heap rule (§4.1/§4.1b value or the init script — ADR 0036).
- Merging a carrier that added/changed Playwright API specs without the carrier smoke or a §4.1 defer WARN (ADR 0036).
- Skipping the chunk-driver degrade after a zero-commit impl wave (re-dispatch halved chunks + orchestrator-runs-tests; never inline — ADR 0037).
- Misreading a zero-commit wave (workers alive) as `worker-changes-unavailable` — it is a throughput stall → chunk-driver degrade; branch visibility was already proven by the Step-0 probe (ADR 0037).
- Reading §4.1 at Step 2 but not §4.1b (execution amendments win over generic budgets — ADR 0036).
- Re-running already-completed gate-5 phases on resume without reading `resume.json` checkpoints (ADR 0034 — re-verify, don't re-run blind).
- Fallback to inline when `Agent`/`EnterWorktree` won't load (stall + exit).
- Re-introducing loop / checkpoint / handoff / 65% monitoring (ADR 0022 — gone; `resume.json` is structured on-disk state, not a context checkpoint).
- Running [human-qa](../../../skills/e2e-engineering/post-impl/human-qa.md) headless (write qa-signoff.md instead).
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
- Merging with any finding `state: open` before the cap is exhausted (merge gate = zero open findings, Minor included — ADR 0035).
- Skipping re-review after a mechanical fix (RETIRED — tier picks scope, never whether; no fix merges unread).
- Binning an un-cited Critical/Important instead of spending a `finding-verifier` on it.
- Verifying an un-cited Minor (dropped, no verifier spend — a Minor worth fixing is worth citing).
- Re-raising a `dropped-refuted` finding in a later re-review (suppress by finding key; the loop cannot converge otherwise).
- Resetting `bounce.rounds` on resume, or because a re-review surfaced new findings (absolute per slice, cap 4).
- Marking a slice `blocked` on review findings (RETIRED — merge + followup at cap; `blocked` is GATE 3 / red tests only).
- Writing `queue.json` for a followup (flight never creates queue entries — `followups.json` → triage).
- Omitting `## Release Blockers` from `qa-signoff.md` when a Critical is open at cap.
