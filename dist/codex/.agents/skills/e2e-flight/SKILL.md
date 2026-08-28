---
name: e2e-flight
description: >-
  Headless implementation worker for the e2e-engineering flow. Implements exactly ONE Task from the queue then exits — no external loop, no context monitoring. Within the spawn it IS the orchestrator: fans out each slice to a sub-agent in its own worktree (impl wave), runs an expert-review wave before merge, then self-reviews and parks human-QA. Headless counterpart to the interactive front door /e2e-engineering. Use when the user says "e2e-flight", "/e2e-flight", "flight", "drain the queue", "run the flight loop", or "implement the selected tasks".
---

# e2e-flight — one-Task implementation worker (Codex runtime)

**SPAWNED-SUBAGENT GATE (read first).** If your agent task name is a child of the root task (e.g. `/root/<worker>`), you are a SLICE WORKER, not the orchestrator — do NOT execute Steps 0–2 or the per-slice loop. Your spawn/followup message may arrive EMPTY in some runtimes; that is expected (ADR 0037). Read `skills/e2e-engineering/impl/tdd.md` §0 and self-brief from disk: the Task's `resume.json` `dispatched[]` entry matching your name → its `manifestPath` → your slice's `workerBrief` → the worktree/branch in that entry. The orchestrator journals those BEFORE spawning you (ADR 0034), so disk IS the brief. Implement the slice, return a slice-result manifest.

Sibling to [/e2e-engineering](../e2e-engineering/SKILL.md). Headless implementation. Read CONTEXT.md for any term. Governed by ADR 0022 and the e2e-flight process spec in the source repository.

**One Task per invocation, then exit.** No loop, no respawn, no context monitoring. Re-invoke `/e2e-flight` for next Task. Task finishes in one spawn or stays resumable via `queue.json`/`prd.json` status.

**Token rule.** Blowup cause: fan-out not firing → 126 inline calls → 227-turn O(N²) chain. Fix: fan-out FORCED (Step 0), inline slice-impl = hard STOP (Step 3). Sub-agents hold heavy tool calls, return manifests — keeps orchestrator context small without checkpoint.

---

## Step 0 — bootstrap + forcing mechanism (FIRST, always)

1. **Resolve shared skill root once.** Set `sharedSkillsRoot = skills/e2e-engineering` from repo root. Verify required files exist: `constitution.md`, `impl/tdd.md`, `impl/systematic-debugging.md`, `impl/command-execution.md`, `schemas/slice-result.json.md`, `schemas/review-bundle.json.md`, `schemas/review-result.json.md`, `schemas/qa-signoff.md`, and `agents/`. Missing → `<e2e-stall reason="shared-skills-missing" />` + EXIT. Runtime wrapper dirs (`.agents/skills/...`, `.claude/skills/...`) are entry points only — never probe them for shared sub-skills/schemas/constitution during execution.
2. **Capability probe (fail-closed).** Static requirement: `spawn_agent` / `spawn_agents_on_csv`. **DSH runtime (ADR 0038):** those tools absent BUT `subagent` + `pwsh` + `job_*` + `list_agents` present → DSH mode — NOT `fanout-unavailable`: read `$sharedSkillsRoot/impl/dsh-runtime.md` ONCE, adopt its tool mappings, and run ITS probe set (background-subagent fan-out probe, shared-FS worker-change probe, foreground `timeoutMs` kill test, write-capability probe → denied = `<e2e-stall reason="sandbox-write-denied" />` + EXIT); skip the spawn_agent live probe. Else: live probe — attempt no-op spawn (trivial exit instruction); fails → `<e2e-stall reason="fanout-unavailable" />` + EXIT. Worker-change probe: record orchestrator branch + HEAD; spawn disposable worker; instruct it to create + commit a probe branch; verify branch/commit visible from orchestrator; check whether orchestrator branch + HEAD changed; then delete only the probe branch and restore original branch. Branch/commit invisible → `<e2e-stall reason="worker-changes-unavailable" />` + EXIT. Branch visible + checkout unchanged → **parallel Codex mode**. Branch visible + checkout changed → **Codex serial branch mode** (one impl worker at a time; no parallel ready-set dispatch). NEVER fall back to inline slice work or full text-patch transfer for normal slices.
3. **Bounded-shell probe (fail-closed, ADR 0033).** Adopt `$sharedSkillsRoot/impl/command-execution.md` for EVERY command this spawn runs (compile, package build, stack-up, lint, tests): bounded + non-interactive + self-terminating. Export the non-interactive env once here (`CI=1`, `NO_COLOR=1`, `npm_config_yes=true`, `DEBIAN_FRONTEND=noninteractive`, `GIT_TERMINAL_PROMPT=0`, `GIT_EDITOR=true`). Probe: run a deliberately-blocking command under a 5s bound (POSIX `timeout 5 sleep 30`; PowerShell `Start-Job`+`Wait-Job -Timeout 5`) and confirm control returns. Cannot bound → `<e2e-stall reason="unbounded-shell — runtime cannot time-box commands" />` + EXIT. **Second runaway brake** alongside forced fan-out — a hung command is invisible to the inline-STOP (ADR 0022 Consequences). Codex/OpenCode/Cursor shells do NOT auto-timeout; this probe is what keeps a foreground build from stalling the whole spawn. **Preflight (ADR 0034):** run `$sharedSkillsRoot/scripts/flight-preflight.ps1` (`pwsh -NoProfile -File`; POSIX-without-pwsh → run the same three checks inline per command-execution §1–§2). FAIL → `<e2e-stall reason="preflight-failed" />` + EXIT. `-StopGradleDaemons` is legal ONLY here at Step 0 with zero parallel work.
4. No driver, no lock, no context monitoring. No handoff docs, no checkpoint, no respawn.
5. Orchestrator output = caveman-ultra, essential only (token discipline).
6. **Init flow-retro tally (ADR 0027).** Start counters accumulated across this spawn for the flow-retro (`$sharedSkillsRoot/schemas/flow-retro.md`): bounces (by tier), blocked slices + cause, gate-5 failures, stalls, fan-out waves (impl + review + verify), bounce rounds per slice vs cap 5, verifier spend (confirmed/refuted/inconclusive), findings left `open-at-cap` + followups produced (P1/P3), carried Minors: n, un-cited Minors dropped, watchdog kills/hangs (ADR 0036), chunk-driver degrade waves (ADR 0037), carrier API smokes red/green (ADR 0036). Bump them as they occur in Steps 3/5; emit at Step 6.
7. **Tooling-trap re-read (once).** Read the task's `progress.txt` tail + repo `AGENTS.md` (+ any `RESUME`/handover doc) for repo-specific traps (tool filters like rtk wrapping gradlew, path-length rules, banned flags). Apply them this spawn. The UNIVERSAL traps are in the skill itself (`$sharedSkillsRoot/impl/command-execution.md` + Red flags below) — never re-discover them per slice. Repo tool filters/proxies (rtk etc.) NEVER wrap long-running or compile/test commands — a proxy/filter on gradlew/tsc can mangle output or hang (`rtk proxy gradlew` trap); filters apply to OUTPUT reads only, or the repo AGENTS.md explicitly says otherwise.

---

## Step 1 — pick ONE Task

Read `.e2e-engineering/queue.json` (offset/limit — only what you need).

- User named Task → take it.
- Else pick: `status:ready-for-flight` AND every `dependsOn` in {done, pending-qa}, highest priority first (ADR 0029). `needs-spec` Tasks are NOT pickable — they have no approved PRD.
- No pickable Task → `<e2e-complete />` + EXIT.

**Master-clean check.** `git status` on master — any uncommitted changes → `<e2e-stall reason="master-dirty — commit or clean before flight" />` + EXIT.

**Task lock + branch.** Commit `queue.json` status `ready-for-flight→in-progress` to master. Create/update `task/<id>` from master, then return to master. Orchestrator state artifacts live on master. Task branch receives code merges + verification only. Sub-agents work in isolated branches. Before any checkout: commit orchestrator artifacts; no stash.

Task root: `.e2e-engineering/tasks/<id>/`.

**Task worktree isolation (concurrent-flight guard).** Create `.claude/worktrees/task-<id>` checked out to `task/<id>`. ALL orchestrator code commands this spawn — lint, compile, merges, conflict resolution, gate-5 stack/suite — run with `workdir=<task worktree>` (never in-command `cd`; see command-execution §5). The MAIN tree stays on master the entire flight: no checkout churn, and a second flight cannot thrash your HEAD (surface-api-error-messages-ui incident — ~1h lost to HEAD thrash). Copy the Step-2 cached gitignored env/config files into the task worktree, untracked (env.test.ts `.env` bootstrap gap). Artifact writes (`queue.json`, `prd.json`, `progress.txt`, sidecars) stay in the MAIN tree on master. Main-tree HEAD/branch changes unexpectedly mid-flight → another flight in this repo → `<e2e-stall reason="concurrent-flight — two flights in one repo" />` + EXIT.

---

## Step 2 — reconcile + read state

Read (offset/limit, only needed sections): `tasks/<id>/prd.json` (slice DAG) + `tasks/<id>/progress.txt`.

- **2.1 — structure missing/invalid** (no prd.json, no DAG, no test-cases): do NOT improvise. Tell user to plan via `/e2e-engineering`, EXIT.
- **2.2 — prior in-progress/stall mess** (slices in-flight with no active spawn): propose reconciliation, EXIT — never blindly resume dirty state.
- **Clean reconcile**: slice in-flight with no active spawn → reset to `todo`. Proceed.
- **Committed-but-unrecorded reconcile**: slice branch ahead of Task branch with ≥1 commit AND an in-branch evidence README, but no manifest / no review / no merge (worker committed, session died pre-record — flight-stall postmortem): treat the head commit as the slice result. Orchestrator verifies compile/typecheck (task worktree, bounded), writes `slice-result.json` from the in-branch evidence README, dispatches the review wave, merges, records. Reset to `todo` ONLY when the slice branch has zero commits ahead — re-dispatching committed work duplicates it.
- **Dirty-tree commit rule (ADR 0034).** Main-tree working tree dirty at entry → it is the prior orchestrator's stranded output (postmortem/skill edits uncommitted after session death — 2026-08-20 incident). Commit it as `state: record <unit>` BEFORE anything else. Never stash, never reset, never discard — the work exists; recording it is cheaper than re-deriving it. The tree must stay clean at every step boundary from here on.
- **Resume pointers (ADR 0034).** Read `tasks/<id>/resume.json` if present (`$sharedSkillsRoot/schemas/resume.json.md`) BEFORE prd.json: `headSha`, `phase`, `dispatched[]`, `reviewWave[]`, `worktrees[]`, `stackState`, `teardownOwed`, `gate5`. `teardownOwed:true` → run `down -v` FIRST. `dispatched[]` entries without a manifest on disk → reconcile per the committed-but-unrecorded path above. Stale values are safe by construction (written write-ahead, only cause re-verification). Update it write-ahead at every phase transition and gate step.

**Docker env cache (brownfield/docker projects).** Read `docker-compose.yml` (+ `docker-compose.override.yml` if present) ONCE. Extract required env/config files: `env_file` entries + volume-mounted config paths. Cache this list — included in every sub-agent spawn manifest in Step 3. Do NOT re-read per slice.

**Compile detection (cache `compileCmd` once).** Resolve the COMPILE-ONLY check command, §4.1-wins-else-detect (ADR 0032):
1. `ARCHITECTURE.md §4.1 Compile command` present → use it verbatim.
2. else detect from repo root: `pom.xml` → `mvn -B -ntp -q compile`; `build.gradle`/`build.gradle.kts` → gradle wrapper + `compileJava --console=plain --no-daemon`, shell-aware (`./gradlew` POSIX / `.\gradlew.bat` PowerShell/win32); `package.json` → **read the `build` script BODY first** — absent, or a watch/serve script (`--watch`/`-w`/`dev`/`serve`/`start`/`preview`) → `npx --yes tsc --noEmit`; else `npm run build`. Never run a script to discover what it does — that IS the hang (ADR 0033).
3. none of the above → NO compile command; skip the compile check + WARN in `progress.txt`. Do NOT fall back to `mvn` (the original bug, #35).
`compileCmd` is COMPILE-ONLY — it never feeds the gate-5 stack rebuild (that build comes from §4.1 Stack-up). Cache `compileCmd` once for the spawn (alongside the docker-env cache); pass it in every sub-agent spawn manifest in Step 3. Do NOT re-detect per slice. Whether from §4.1 or detected, it runs under the Step-0 `$sharedSkillsRoot/impl/command-execution.md` contract — bounded (6 min; gradle focused 12 min), non-interactive, self-terminating; a §4.1 command carrying a watch/serve flag is a §4.1 defect → WARN + skip, never run it.

**Contract digests (cache once).** Read the repo's active eslint config ONCE → ≤15-line lint digest for worker briefs (no frontend eslint → skip; backend has no lint tool — ARCHITECTURE naming/ownership + constitution cover it). Extract the `## Digest` section from each applicable `$sharedSkillsRoot/agents/<role>.md` ONCE. Cache both alongside `compileCmd`; pass in every spawn manifest.

**Execution amendments (§4.1b, ADR 0036).** Read `ARCHITECTURE.md §4.1b` (test-execution amendments) ONCE if present — its values (test-fork heap, ports, verdict discipline, runner quirks) WIN over the generic budgets. Cache alongside `compileCmd`; pass the relevant lines in every sub-agent spawn manifest.

**Codebase-map (brownfield only).** Missing `tasks/<id>/codebase-map.md` → `<e2e-stall reason="codebase-map-missing — pre-impl incomplete, run /e2e-engineering" />` + EXIT. Do NOT cold-read source files to compensate. If present: read §1–§3 ONCE (§Index for offset/limit). Hold in context. Do NOT re-read in Steps 3 or 4.

**Gate-1 fail-closed check (HARD).** `gate1Approved: false` in prd.json → `<e2e-stall reason="unapproved-prd" />` + revert queue status `ready-for-flight → needs-spec` + EXIT. Any story `estimatedLoc` missing or beyond its sliceType bound (tracer/schema/api/logic >300, ui >600) → `<e2e-stall reason="oversized-slice <id> — <sliceType> <loc>/<bound>" />` + revert to `ready-for-flight` + `progress.txt` note "flight refused: oversized slice <id> — human split required" + EXIT. Both stalls revert BEFORE exit so the front door replans. `gate1SizingOverride: true` + `sizingOverrideNote` (who/why) in prd.json = deliberate human exception → fly it, but reviewers of that slice get subsystem-scoped evidence (backend half / frontend half / spec half) per reviewer session.

---

## Step 3 — per-slice loop (flight IS the orchestrator)

Sole writer: only orchestrator writes `prd.json` + `progress.txt` + evidence sidecars (`manifests/<story-id>/`). Sub-agents return slice result manifests (`$sharedSkillsRoot/schemas/slice-result.json.md`); never touch shared state.

**Empty-message worker dispatch (ADR 0037).** Some runtimes deliver spawn/followup messages EMPTY (turn triggers, content lost). A worker that receives one self-briefs from disk — `impl/tdd.md` §0 + the SPAWNED-SUBAGENT GATE above. The orchestrator journals the ready-set manifest BEFORE spawning (ADR 0034), so disk IS the brief; never depend on the payload surviving.

Repeat until DAG drained (every slice `done` or `blocked`):

1. **Compute ready set** — slices whose `depends_on` are all `done` AND own `status: todo`.
2. **Impl dispatch wave** — write ready-set manifest JSON (slice ids + injection payload, quoting `git rev-parse task/<id>` RE-READ AT DISPATCH TIME — never from memory) + inline digests (lint + role `## Digest` sections) + canary first-instruction, append a dispatch-intent line to `progress.txt`, then **COMMIT both** (journal-before-dispatch, ADR 0034), THEN dispatch via `spawn_agents_on_csv` (or `spawn_agent`/`wait_agent`). Death mid-dispatch leaves a verbatim-replayable brief on disk (wave-5 quota-abort precedent: briefs re-sent verbatim, zero loss). Re-dispatch = re-send the committed manifest; the only field to refresh is the HEAD sha it quotes. **Quota-containment (ADR 0034):** quota headroom unknown OR a prior wave aborted on quota → dispatch in batches of ≤2, one committed manifest per batch — loss bounded to the in-flight batch. Parallel ready-set dispatch stays the default; batching is the degraded mode, never inline work. Record dispatch table in memory: `agentId -> taskId, sliceId, expectedBranch, attempt`. Codex branch-visible integration is required: each worker creates and commits to `slice/<story-id>` and returns that branch name in its slice result manifest. **Slice branch MUST be created from the current `task/<id>` HEAD — never `origin/master` (stale base wrote stale-API code; flight-log misbehavior #3).** Dependent slices get the upstream slice's key API-change summary in the payload (e.g. "`ApiError.detail` is now the 2nd arg, `e.message` is generic"). Worker NEVER merges into the Task branch. Parallel Codex mode dispatches disjoint ready-set slices concurrently. Codex serial branch mode dispatches exactly one ready slice at a time: orchestrator creates/switches to `slice/<story-id>` from the Task branch before spawning (switch INSIDE the task worktree from Step 1 — never in the main tree), worker commits on the current branch without switching, orchestrator waits/validates, switches back to Task branch (in the task worktree), then merges. Each sub-agent injection: `$sharedSkillsRoot/constitution.md` + `$sharedSkillsRoot/standards/api-testing.md` + `$sharedSkillsRoot/impl/command-execution.md` (worker runs compile + tests under the same bounded/non-interactive contract) + slice (acceptanceCriteria, sliceType, `integration` decision) + testCases + cached `compileCmd` (Step 2 — worker compiles with this, never assumes Maven) + (brownfield) SCOPED slice of `ARCHITECTURE.md` (use §Index for offset/limit on relevant sections). `ui` slices ALSO get `$sharedSkillsRoot/standards/ui-design.md` + the SCOPED slice of `DESIGN.md` (register + relevant tokens/components, §Index offset/limit; READ-only in flight — ADR 0030).

   **Worktree env/config bootstrap** (included in spawn manifest). Pass cached docker env file list (from Step 2) in each sub-agent's spawn payload. Sub-agent copies into its worktree on start. Do NOT stage/commit these files — untracked only. Required file missing from main tree → sub-agent surfaces it as blocker in slice result manifest; does not silently skip.

   Sub-agents run `$sharedSkillsRoot/impl/tdd.md`. Each completes by returning a **slice result manifest** (`$sharedSkillsRoot/schemas/slice-result.json.md`): `{ sliceId, status, summary, testsPassed, branch, evidencePaths[], findings[] }`. Chat carries manifest pointers only; code changes and logs stay in git/test artifacts.

   **Completion contract.** Orchestrator learns a worker finished only from the sub-agent handle (`wait_agent` completion) plus final manifest. Then validate: JSON shape, `sliceId`, `status`, expected `branch`, branch exists, branch is ahead of Task branch, and `evidencePaths[]` exist/are inspectable. Invalid/missing manifest, branch, or evidence paths → bounce/stall; never mark done from branch existence alone. Final worker message must not contain raw logs/diffs or long narrative.

   - **GATE 2 (hard)** — failing test before production code (inside tdd).
   - **GATE 3 (hard)** — 3 failed fixes → re-dispatch ONCE with `$sharedSkillsRoot/impl/systematic-debugging.md`; still red → mark slice `blocked`, keep draining.
   - **DO NOT do slice-impl inline.** Orchestrator writing slice production code = hard red-flag STOP. Sole exception: a single-file pure-styling slice (CSS classes only — zero logic/API/i18n/test changes, ≤300 LoC) MAY run inline (fan-out overhead > benefit; user-mgmt-create-form-style session-log). Everything else fans out.
   - **Chunk-driver degrade (ADR 0037).** An impl wave returns ZERO commits/manifests after its budget (workers alive but stalled — some runtimes' write-capable workers complete ~1 tool call/round; a throughput stall, NOT `worker-changes-unavailable` — the Step-0 probe already proved branch visibility) → degrade: halve the slice into small chunks (≤1 file, one AC); worker writes ONE chunk + self-compiles; orchestrator runs the focused tests per chunk and feeds the verdict back. GATE 2 holds — chunk 1 = the failing test (orchestrator confirms red) before the impl chunk. Review wave unchanged (per slice after the last chunk). Record the degrade in `progress.txt` + the retro counter. Still fan-out — chunk-driver is a smaller unit, never inline slice work.

3. **Expert-review wave (artifact-driven, BEFORE merge).** Slice green → orchestrator writes manifest-first **review bundle** (`$sharedSkillsRoot/schemas/review-bundle.json.md`): branch names, base/head commits, reviewer list, changed files, `git diff --stat`, test command outcomes, and paths to logs/test cases. Do NOT load or paste full raw diffs/logs into orchestrator context; reviewers pull scoped hunks/logs themselves from the bundle. Dispatch reviewer agents via `spawn_agents_on_csv` / `spawn_agent`; parallel is preferred, bounded batches are allowed when runtime agent slots are constrained. In Codex, use standard `worker` agents and inject the matching canonical expert spec from `$sharedSkillsRoot/agents/<role>.md` into each reviewer prompt:
   - schema/db → `dba` + `backend-architect`
   - api/logic → `backend-architect` + `test-reviewer`
   - ui → `frontend-reviewer` (reviews against the approved `DESIGN.md` + `$sharedSkillsRoot/standards/ui-design.md` — deviation = Important, anti-slop defect = normal severity) + `backend-architect` (frontend lens)
   - every slice → `test-reviewer` (AC coverage)

   Reviewer roles above are prompt roles, not Codex `agent_type` names. Always spawn Codex expert reviewers with `agent_type: worker`; never spawn `backend-architect`, `dba`, `frontend-reviewer`, or `test-reviewer` as tool roles, even if the runtime advertises them. Reviewers receive review-bundle path/content + canonical expert spec only — NOT worktree path (Codex worktree isolation is internal; path coupling fails silently). Each returns **reviewer result** (`$sharedSkillsRoot/schemas/review-result.json.md`): `{ reviewerId, sliceId, findings[] }`.

   **Finding hygiene gate (pre-verify, ADR 0035).** EVERY finding, ANY severity, needs a cite (`file:line`, test name, log path, explicit searched-absence scope) AND an implied ACTION.
   - No ACTION → downgrade: Important→Minor, Minor→dropped.
   - Un-cited Critical/Important → **verify wave**, never binned.
   - Un-cited Minor → dropped, logged in `review-result.json` `notes`, NO verifier spend (a Minor worth fixing is worth citing).
   - Coverage doubt without proof → reviewer sets the finding's `signal: "NeedsVerification"` (severity still carries what it WOULD assign) instead of asserting an unproven Critical → verify wave.

   **Verify wave (ADR 0035).** Runs after EVERY review/re-review fan-in, BEFORE bounce classification. Spawn one verifier per unproven finding — `NeedsVerification` findings at Critical/Important + un-cited Critical/Important — via `spawn_agents_on_csv` / `spawn_agent` with `agent_type: worker`, injecting the canonical spec `$sharedSkillsRoot/agents/finding-verifier.md`. `finding-verifier` is a PROMPT role, never a tool `agent_type`. Parallel preferred; bounded batches allowed when slots are constrained. Budget ≤8 calls each. Verifiers receive the finding + the review-bundle path only — never a worktree path. Journal `verifyWave[]` in `resume.json` write-ahead before spawn.
   - `confirmed` + cite → `state: open` at the VERIFIER's severity (it owns severity now) → eligible to bounce; the verifier's cite becomes the finding's `evidence`.
   - `refuted` → `state: dropped-refuted`, logged.
   - `inconclusive` → treated as **refuted** (adversarial default — a starved verifier must not manufacture a bounce).
   - **Verify-once + suppress.** Each finding is verified AT MOST ONCE per slice. `dropped-refuted` keys go to `resume.json` `suppressed[]` (`<severity>|<location>|<sha1-8 of message>`); a later re-review may NOT re-raise them. Without suppression the loop never converges.
   - Verify wave does NOT consume a bounce round — it is not a fix.

   Reviewers read-only, independent. If a reviewer spawn fails due thread/slot limits, close completed/errored agents, retry, then run bounded batches if still constrained. Give each reviewer the same review bundle and no implementation context; never skip `test-reviewer`. Severity enum is exactly **Critical / Important / Minor** — `NeedsVerification` is a pre-verify SIGNAL, not a severity; `Unsubstantiated` is retired (ADR 0035). Orchestrator assigns each finding an `id` + `state` at fan-in.

   **Reviewer prompt budget (hard).** Every reviewer prompt carries a tool-call budget (≤15 calls) and must return bounded JSON only (`verdict` + `findings[]`) — the injected expert spec says so. **Stuck-reviewer protocol:** reviewer hangs or is cancelled with no result → re-dispatch ONCE with halved scope (≤2 checks, ≤8 tool calls). Still nothing → proceed with the remaining reviewers' results, record the gap in `review-result.json` `notes`; never wait unbounded, never block the merge on an unavailable reviewer slot alone — this applies to the INITIAL review wave only. In a re-review round the unreturned reviewer holds an open finding: leave that finding `open` and let the convergence loop continue to the cap, which merges with a followup. Never merge past an `open` finding outside cap exhaustion (ADR 0035) (flight-stall postmortem — one stuck reviewer stalled a whole wave).

   **DSH review/verify waves route through `workflow` (ADR 0039).** Initial review, re-review, and finding-verifier waves = one workflow script each: parallel `agent()` stages with per-agent `model` override (T0 = finding-verifier/mechanical, T1 = judgment reviewers), `opts.schema`-validated results returned pre-merged. Stuck-reviewer protocol in-script: child failure → `null` → filter + record gap in `notes`. Wave size 2–4, budgets in prompts (≤15 initial / ≤8 re-review / ≤8 verifier). Workflow unavailable (Step-0 probe) → background `subagent` waves with prompt-discipline tiers — never a stall.

   **Severity discipline.** Critical/Important imply an ACTION. A finding marked Important with "no change required" → downgrade to Minor (flight-log misuse #4 — orchestrator overrides).

   **Convergence loop v2 (ADR 0035 amendment — replaces the bounce cap).** `open[]` = findings with `state: open`, ANY severity.
   - **Phase A (C/I-driven):** while any Critical/Important is `open` → `bounce.rounds += 1` (per slice, ABSOLUTE, never reset) → worker fixes ALL open findings in ONE pass (Minors piggyback) → re-review → loop.
   - **Phase B (Minor-only):** zero C/I open → one fix pass for all remaining Minors (consumes one round) → ONE review (scope = finding-owner roles + `test-reviewer`) → any Minor still open → `state: carried` → `followups.json` (P3). No further Minor rounds. New C/I surfaced by the Phase-B review → back to Phase A, count continues.
   - **Cap = 5.** `bounce.rounds > 5` → cap exhausted → merge + followup (below). NEVER `blocked`. Minors open at a Phase-A cap hit → carried WITHOUT their fix pass.
   - Re-review tiers unchanged (mechanical/limited → reviewers that raised open findings; logic → full wave). Halved ≤8 budget unchanged. The re-examined→`fixed` flip fires only on re-examination; carried Minors are never re-examined (they ride followups).
   - **Merge gate:** zero open Critical/Important; Minors fixed or `carried`. Sole exception: cap exhaustion.

   **Cap exhaustion → merge + followup (ADR 0035).** On entering round 6:
   - **MERGE the slice.** Tests are green; the residue is a quality/coverage gap, not a red test.
   - `prd.json` story → `status: done`, `notes: "<n> open findings at cap: <severities>"`.
   - `review-result.json` survivors → `state: "open-at-cap"`.
   - Append each to `tasks/<id>/followups.json` (`$sharedSkillsRoot/schemas/followups.json.md`); `suggestedPriority` PER ENTRY from its own severity: Critical → 1, Important/Minor → 3.
   - NEVER write `queue.json` — followups reach the queue via `$sharedSkillsRoot/impl/triage.md` at QA sign-off (ADR 0017 writer table intact).
   - Review-driven slice `blocked` is **RETIRED**. GATE 3 (red tests, 3 failed fixes) still blocks — unchanged.

   Reviewers never fix or merge.

4. **lint + compile** — orchestrator commands (not agents), run from the task worktree (workdir param). Run project lint + the cached `compileCmd` (Step 2 — compile-only check, not a hardcoded build, not the package build), each bounded + non-interactive per `$sharedSkillsRoot/impl/command-execution.md` (lint 3 min, compile 6 min). Long producers redirect to a log file (`> run.log 2>&1`) and read the tail after exit — NEVER pipe-to-filter (`Out-String`, `Select-Object -Last`, `head`, `tail` emit nothing until exit). Timeout = compile failure, logged `TIMEOUT <cmd> @<budget>s` — reconcile like any other failure, never re-run unchanged more than once. Reconcile failures before merge.
5. **Merge** slice branch → Task branch, in the task worktree (workdir param). No stash. No checkout — the task worktree stays on `task/<id>`, the main tree stays on master. Sequence: commit master artifacts (main tree) → task worktree: `git merge slice/<story-id> --no-edit` (never bare — editor prompt blocks headless forever) → resolve conflicts (never discard work) → lint/build if needed. Branch missing or not ahead of Task branch → bounce/stall, do not ask worker to paste full patches.
   **Wave-batched carrier API smoke (ADR 0036 amendment).** After a wave's merges, if any carrier added/changed Playwright API specs: ONE stack-up per §4.1 Stack-up + run EVERY changed spec file in that session (bounded, `--project <api>`), via `carrier-smoke.ps1 -Spec @(...)`. Red spec → REPAIR SLICE on the task branch (fresh worker + Gate 3) targeting the red spec's code, merged before the wave closes. Invariant: no wave closes with a red smoke. §4.1 declares the rebuild too heavy → WARN in `progress.txt` + defer to gate 5.
6. **Record + persist sidecars** (sole writer):
   - Write `tasks/<id>/manifests/<story-id>/slice-result.json` (`$sharedSkillsRoot/schemas/slice-result.json.md`) from sub-agent's returned manifest.
   - Write `tasks/<id>/manifests/<story-id>/review-result.json` (`$sharedSkillsRoot/schemas/review-result.json.md`) from combined reviewer results (parallel or bounded-batch reviewers for this slice).
   - Update prd.json story: `resultManifestPath`, `reviewManifestPath` (paths relative to Task root), `status: done`.
   - Append sub-agent summary to `progress.txt` (caveman-ultra, status-headed line).
   - **Status authority:** orchestrator reconciles sidecar `status` at fan-in; prd.json is sole source of truth. Never copy sidecar status blindly.
   - **Evidence hygiene (ADR 0036):** evidence = counts + ≤20-line excerpts. Full logs stay on disk (gitignored `*.log`), deleted at worktree removal — never commit them (two 179KB copies shipped then removed, bf095e3).

---

## Step 4 — e2e QA pass (task-level, after DAG drained) — GATE 4 RETIRED (ADR 0024, Fork Y)

Run `$sharedSkillsRoot/impl/e2e-loop.md`: author cross-slice **UI regression test-case DOCS** (Manual disposition → human-QA walk) now the whole feature exists. Full Manual scripts (Preconditions/Steps/Expected) → `tasks/<id>/test-cases/` (caveman-ultra). **NO UI automation** — UI is Manual (Fork Y). A cross-slice API journey MAY be automated as a Playwright `request` test; UI never. (No "E2E green" gate here — gate 4 retired; automated unit+API suite is checked at gate 5, Step 5.0.)

---

## Step 5 — verification (gate 5) + self-review (whole task)

- **5.0 — HARD GATE 5 (verification-before-completion).** **Stack ownership.** The flight owns the compose stack during smoke/gate-5: `down -v → package build → up --force-recreate --build -d` runs unconditionally — no probe, no ask. The flight tears down and rebuilds the stack; do not keep dev work in a running compose stack during a flight. Run `$sharedSkillsRoot/impl/verification.md`: bring the live docker-compose stack up ONCE per `ARCHITECTURE.md §4.1 Stack-up` (owns the package build, e.g. `down -v → quarkusBuild → up --force-recreate --build -d`; unseeded + artifact-copying Dockerfile → WARN + skip host build; no compose → skip), run from the task worktree (workdir param). **`up` MUST be detached (`-d`)** and every step bounded per `$sharedSkillsRoot/impl/command-execution.md` (stack-up 10 min, package build 15 min, full suite 30 min, playwright gate 20 min); long producers redirect to a log file, never pipe-to-filter; readiness by bounded poll, never by attaching. **Background jobs (ADR 0036):** any detached suite/stack step ALSO gets the watchdog — bounded poll + hard deadline → `job_kill` + 10-min log-silence heuristic + orphan sweep by targeted PID after a kill (never `--stop`); a killed step routes as its phase timeout. **Fork-heap + verdict discipline (ADR 0036):** JVM suites ~80+ test classes → test-fork heap rule (§4.1/§4.1b value or the `heap.init.gradle` init script); verdicts read test-result XML only after `BUILD SUCCESSFUL` in the log (stale-XML trap) — per `$sharedSkillsRoot/impl/verification.md`. **Gate-5 checkpoints (ADR 0034):** record `gate5.phase` in `resume.json` write-ahead before stack-up / before the full suite / before the Playwright gate; death mid-gate resumes from the checkpoint and re-runs ONLY unfinished phases (`teardownOwed` forces `down -v` first). A stack-up or suite **timeout is a gate-5 failure** (strike), never a stall and never `blocked`. Then (a) full automated suite (unit + the client's independent Playwright **API project ONLY**, via the §4.1 `API/integration` API-only cmd / `--project <name>` — NEVER bare `playwright test`) green. Full API suite runs `retries=0 workers=1` with the documented isolation baseline (retry-inflated counts are noise). (b) AC-checklist against code — every `acceptanceCriteria[]` maps to a code path AND a covering automated test (unit/API) OR a Manual test-case (UI). Red → durable bounded task-level 3-strike loop (`gate5Strikes` in the sidecar; resume-safe; separate from per-slice Gate-3). Tear the stack down (`down -v`) after. Write `manifests/_task/verification-result.json` (`$sharedSkillsRoot/schemas/verification-result.json.md`) incl. `gate5Strikes`/`gate5FailureIds[]`. **NO live-UI exercise** (no app launch, browser project never run — Fork Y). Still red after the loop or unmapped AC → record failures, proceed to Step 5.1 (do NOT mark `blocked` — see ADR 0025).
- Then review assembled Task against acceptanceCriteria + `$sharedSkillsRoot/constitution.md`.
- **5.1** → finalize on master (main tree): write/finalize `progress.txt`, `qa-signoff.md`, verification sidecar, and `queue.json` status `in-progress→pending-qa`; commit. Do NOT set `done` — `done` requires human approval at QA gate (ADR 0018). Applies whether gate 5 was fully green or had failures (failures ride to human-QA in qa-signoff.md).

**Worktree prune (D11).** After 5.1 finalize: from the MAIN tree, `git worktree remove --force .claude/worktrees/task-<id>` — task + slice branches persist, never delete branches. DSH mode: no worktrees — skip.

- **5.2 self-review hard fail** (constitution violation, not test failure) → scoped `git restore` UNCOMMITTED leftovers ONLY (never wipe already-merged slices) + mark Task `blocked` in `queue.json`. Committed slices stay.

---

## Step 6 — defer human-QA

Write `tasks/<id>/qa-signoff.md` (`$sharedSkillsRoot/schemas/qa-signoff.md`, caveman-ultra): manual test cases to walk, auto-verified ACs to eyeball, staged pending amendments. If gate 5 had failures, write `## Gate 5 Failures` section (each failing test/AC as a finding → triage entry for human to route into a new repair Task at QA sign-off). Do NOT run `$sharedSkillsRoot/post-impl/human-qa.md` — needs human. `/e2e-engineering` owns human review + replanning. Always write `## Followups` (empty when every slice converged) from `followups.json` (`$sharedSkillsRoot/schemas/followups.json.md`) — plus `## Release Blockers` IFF an open finding is Critical (ADR 0035). Flight never queues them; triage does at sign-off.

Also write `tasks/<id>/flow-retro.md` (`$sharedSkillsRoot/schemas/flow-retro.md`, caveman-ultra) from the Step-0 tally (ADR 0027): **§Local retro** (process metrics for the team — bounces by tier, bounce rounds per slice vs cap 5, blocked slices + cause, gate-5 failures, stalls, fan-out waves (impl + review + verify), verifier spend (confirmed/refuted/inconclusive), findings left `open-at-cap` + followups produced (P1/P3), carried Minors: n, un-cited Minors dropped, watchdog kills/hangs (ADR 0036), chunk-driver degrade waves (ADR 0037), carrier API smokes red/green (ADR 0036)) + **§Skill-improvement candidates** (friction that looks like an e2e-engineering TOOL defect, for upstream). SEPARATE from qa-signoff.md — keeps tool-facing signal out of the project QA doc. The human routes §Skill-improvement upstream at QA sign-off (third lane), NOT into the client queue.

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
- docker config + codebase-map + `compileCmd` + §4.1b amendments: resolved/read ONCE in Step 2, never re-detect/re-read in Steps 3/4. DSH mode: `impl/dsh-runtime.md` read ONCE at Step 0.

## Red flags (stop)
- Slice-impl inline instead of sub-agent dispatch (blowup cause — Step 0 forces fan-out; inline = STOP). Exception: single-file pure-styling slice (≤300 LoC, zero logic/API/i18n/test changes).
- Running ANY command unbounded, interactive, or foregrounded when it serves/watches/tails (ADR 0033 — a hung shell is a runaway neither fan-out nor inline-STOP catches; Codex/OpenCode shells do not auto-timeout).
- In-command `Set-Location`/`cd` instead of the workdir param (failed chdir silently runs the command in the MAIN tree — wrong tree, wrong verdict). No workdir param → `cd <abs> && pwd`, chained `&&` never `;`.
- Piping long producers through `Out-String` / `Select-Object -Last` / `head` / `tail` (emits nothing until exit — a healthy slow build is indistinguishable from a hang). Redirect to a log file, read tail after.
- Bare `git merge` / bare `git commit` (default editor blocks a non-interactive shell forever) — always `--no-edit` / `-m ...`; `GIT_EDITOR=true` exported at Step 0.
- Bare `vitest` (watch mode never exits) — always `npx vitest run`.
- `npx` without `--yes` or without a binary pre-check (install prompt / silent download blocks headless).
- `./gradlew --stop` during a flight (machine-wide daemon sweep while parallel work exists — banned; supersedes the old gradle-hang postmortem recommendation).
- Wrapping a compile/test command in a repo tool filter/proxy (`rtk proxy gradlew`) — filters apply to output READS only; proxied compiles mangle verdicts or hang.
- Waiting unbounded on a hung reviewer (re-dispatch once with halved scope; then proceed with the rest and record the gap in `notes`).
- Creating a slice branch from `origin/master` instead of current `task/<id>` HEAD (stale base → stale-API code).
- Resetting a committed slice to `todo` when its branch has commits ahead (use the committed-but-unrecorded reconcile path — Step 2.2).
- Crossing a step boundary (dispatch/merge/gate) with a dirty working tree (ADR 0034 — commit `state: record <unit>` first; never stash).
- Dispatching without a committed ready-set manifest + progress intent line (ADR 0034 journal-before-dispatch).
- Skipping or failing the Step-0 preflight (ADR 0034 — fail-closed: `<e2e-stall reason="preflight-failed" />`).
- Re-running already-completed gate-5 phases on resume without reading `resume.json` checkpoints (ADR 0034 — re-verify, don't re-run blind).
- Running two flights concurrently in the same repo working directory (HEAD thrash) — main-tree HEAD moving = stall `concurrent-flight`.
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
- Probing `.agents/skills/...` or `.claude/skills/...` for shared files after Step 0; use `$sharedSkillsRoot` only.
- Continuing when `$sharedSkillsRoot` required files are missing (stall `shared-skills-missing`).
- Fallback to inline when `spawn_agent`/`spawn_agents_on_csv` unavailable (stall + exit).
- Stalling `fanout-unavailable` on DSH when `subagent` is present (ADR 0038: DSH fan-out = background subagent dispatch — read `$sharedSkillsRoot/impl/dsh-runtime.md`).
- Bounding a background job with `timeoutMs` alone (DSH measured: background ignores it — the watchdog is the only brake; ADR 0038).
- Dropping the watchdog loop when a poll returns `running` (persist in-turn: bounded `job_output` wait + output-growth check; the 4.7h wedge died because polling stopped).
- Retrying a sandbox-denied write (policy, not transient — stall `sandbox-write-denied`, never loop; ADR 0038).
- Fallback to text patches when worker branch commits are unavailable (stall `worker-changes-unavailable`).
- Running multiple implementation workers when Step 0 selected Codex serial branch mode.
- Skipping `test-reviewer` because reviewer agent slots are constrained; use bounded batches instead.
- Re-introducing loop / checkpoint / handoff / 65% monitoring (ADR 0022 — gone; `resume.json` is structured on-disk state, not a context checkpoint).
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
- Merging with any finding `state: open` before the cap is exhausted (merge gate = zero open Critical/Important; Minors fixed or `carried` — ADR 0035 amendment).
- Skipping re-review after a mechanical fix (RETIRED — tier picks scope, never whether; no fix merges unread).
- Binning an un-cited Critical/Important instead of spending a `finding-verifier` on it.
- Verifying an un-cited Minor (dropped, no verifier spend — a Minor worth fixing is worth citing).
- Re-raising a `dropped-refuted` finding in a later re-review (suppress by finding key; the loop cannot converge otherwise).
- Resetting `bounce.rounds` on resume, or because a re-review surfaced new findings (absolute per slice, cap 5).
- Marking a slice `blocked` on review findings (RETIRED — merge + followup at cap; `blocked` is GATE 3 / red tests only).
- Writing `queue.json` for a followup (flight never creates queue entries — `followups.json` → triage).
- Omitting `## Release Blockers` from `qa-signoff.md` when a Critical is open at cap.
- Spawning `finding-verifier` as a tool `agent_type` (it is a PROMPT role — use `worker` + injected canonical spec).
- Loading full raw diffs/logs into orchestrator context for review; write `review-bundle.json` and let reviewers pull scoped evidence.
- Accepting worker final messages that paste raw logs/diffs instead of returning `evidencePaths[]`.
- Passing worktree path to reviewer agents — pass review bundle (artifact package) instead.
- Spawning Codex named expert roles directly (`backend-architect`, `dba`, `frontend-reviewer`, `test-reviewer`) instead of `worker` + injected reviewer prompt role.
- Flying a Task with `gate1Approved: false` or an out-of-bounds `estimatedLoc` without `gate1SizingOverride` (Step 2 fail-closed — stall, never WARN-and-fly).
- Running an unbounded workflow review wave (pre-bound: 2–4 agents, budgets in prompts, schema-required returns — ADR 0039).
- Closing a wave with a red carrier smoke (repair slice resolves it first — ADR 0036 amendment).
- Hand-assigning test ports (scripts claim/release from `resume.json` `ports` — never by hand).
- Committing `evidence/` dirs on slice branches (untracked only — ADR 0037 amendment).
- Dispatching without the canary first-instruction in the worker brief.
