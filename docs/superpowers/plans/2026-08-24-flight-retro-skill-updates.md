# Flight Retro Skill Updates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply every skill-improvement candidate from the payments-monetization flow-retro to the e2e-flight skill, then re-sync UniVerse.Academy (the only client) onto the updated install.

**Architecture:** Two new ADRs carry the design decisions (0036 = gate-5/runtime safety: background-job watchdog, evidence hygiene, fork-heap, stale-XML verdicts, carrier-level API smoke, §4.1b hook; 0037 = dispatch/worker mechanics: chunk-driver degrade mode, worker self-compile default, empty-message bootstrap, halved re-review budget). Doc edits land in the shared `skills/e2e-engineering/` tree + both runtime entry points. `npm run build` regenerates `dist/`; the installer then re-syncs UniVerse.Academy from `dist/`.

**Tech Stack:** Markdown skill docs, PowerShell build/validate scripts, Node installer.

**Spec:**
- `C:\Views\UniVerse.Academy\.e2e-engineering\tasks\payments-monetization\flow-retro.md` (retro, 2026-08-23)
- `C:\Views\UniVerse.Academy\ARCHITECTURE.md §4.1b` (repo-specific rules — stay authoritative)
- Main repo: `docs/adr/0035-*.md` (ADR format), `scripts/validate.js` (acceptance gate)

## Global Constraints

- Skill docs are maintained in caveman-ultra density (SKILL.md token-hygiene rule) — new text matches existing terse style, no fluff.
- `npm run build && npm run validate` must exit 0 before any commit; `validate.js` checks markdown-link resolution, dist freshness vs sources, no deprecated role names, JSON validity.
- `ARCHITECTURE.md §4.1b` values (fork-heap 3g, ports, playwright fallback, UTC dates) WIN over the new generic skill rules — the skill never hardcodes UniVerse specifics.
- Never edit `.claude/agents/*.md` by hand — regenerate via `generate-agent-wrappers.ps1` from canonical specs.
- All work on branch `skill/retro-payments-2026-08`; never main.
- UniVerse.Academy sync = `node bin/install.js --dest C:\Views\UniVerse.Academy --target <t> --force` AFTER build (installer reads `dist/`); preserve any UniVerse-specific AGENTS.md content.

---

### Task 1: ADR 0036 — gate-5 runtime safety

**Files:**
- Create: `docs/adr/0036-bounded-background-jobs-evidence-hygiene-and-gate5-execution.md`

**Steps:**
- [ ] **Step 1:** Write ADR 0036 with Status `accepted` + this decisions list (each with rationale grounded in the retro):
  1. **Background-job watchdog.** Every detached/background job gets a bounded poll (capped attempts × interval = phase budget), a hard deadline → `job_kill`, a silence heuristic (log last-write > 10 min while running = hung → kill + record `TIMEOUT <cmd> @<budget>s (silent)`), and an orphan-process sweep after kill (targeted PIDs per §4.1/§4.1b; never `gradlew --stop`). Killed jobs route per command-execution §4 outcome table (gate-5 phase → strike; worker test → gate-3 strike; teardown → WARN). Counters to flow-retro.
  2. **Evidence hygiene.** Committed evidence = counts + ≤20-line excerpts. Full logs stay on disk, gitignored (`*.log`), deleted at worktree removal. `evidencePaths[]` point to counts/excerpt files. (Retro: ~1.5MB of full logs committed as `evidence/*.log.txt`; two 179KB copies removed in bf095e3.)
  3. **Test-fork heap rule.** Gate-5 JVM suites near/over ~80 test classes → check the test-fork heap. Gradle 9's default 512MB fork OOMs mid-suite and the executor can hang instead of dying (payments drain: 3 OOMs + 4.7h wedge). §4.1/§4.1b sets one → use it verbatim; else prescribe an init script (`allprojects { tasks.withType(Test).configureEach { maxHeapSize = "3g" } }` via `--init-script`). `GRADLE_OPTS` does NOT affect the test fork. Memory-constrained → split into class-list halves (distinct ports, sum XML, each half skipped=0).
  4. **Stale-XML verdict discipline.** Check `BUILD SUCCESSFUL` in the log BEFORE reading test-result XML — a failed compile leaves prior XML behind. Report tests/failures/errors/skipped; skipped must be 0.
  5. **Carrier-level API smoke.** After a carrier's merge that added/changed Playwright API specs: rebuild the stack per §4.1 Stack-up and run ONLY that carrier's spec files (bounded, API project). Red → fix in-slice (Gate 3 applies) before the next wave. §4.1 declares rebuild too heavy → WARN + defer to gate 5. Final gate-5 full suite unchanged. (Retro: blind carrier specs shipped stale 200-vs-201 expectations + db-cleanup bugs caught only at the gate.)
  6. **§4.1b hook.** `ARCHITECTURE.md §4.1b` (test-execution amendments) is the first-class hook for repo-specific execution rules; read ONCE at Step 2 alongside §4.1, its values win over generic budgets.
- [ ] **Step 2:** Add Considered Options (e.g., rejected: OS-level timeout wrap for background jobs — the runtime flag bypasses tool timeouts but an OS timeout cannot see a wedged JVM holding the port; rejected: per-slice stack rebuilds — cost multiplies by slices) + Consequences (budget impact of carrier smoke, retro counter changes).
- [ ] **Step 3:** Commit: `docs: ADR 0036 — background-job watchdog, evidence hygiene, gate-5 execution rules`

### Task 2: ADR 0037 — dispatch + worker contract

**Files:**
- Create: `docs/adr/0037-degraded-dispatch-and-worker-contract.md`

**Steps:**
- [ ] **Step 1:** Write ADR 0037 with Status `accepted` + decisions:
  1. **Chunk-driver degrade mode (first-class).** Trigger: an impl wave returns zero commits/manifests after its budget (workers alive but stalled — write-capable workers ~1 tool-call/round). Action: halve the slice into small chunks (≤1 file, one AC each); worker writes ONE chunk + self-compiles; orchestrator runs the focused tests per chunk. Gate 2 preserved: chunk 1 = failing test (orchestrator confirms red) before the impl chunk. Review wave unchanged (still per slice after last chunk). Never inline slice work. Degrade is recorded in `progress.txt` + flow-retro.
  2. **Worker self-compile default.** Compile-only `compileCmd` before EVERY commit (~1 min) — reduced compile-fix round-trips ~3× (waves 13b–14).
  3. **Empty-message bootstrap (upstream of the UniVerse local patch).** Some runtimes deliver worker spawn/followup messages EMPTY. A worker must self-brief from disk: `impl/tdd.md` §0 (resume.json `dispatched[]` → `manifestPath` → `workerBrief`); disk is the brief because the orchestrator journals before dispatch (ADR 0034). Codex entry gains the SPAWNED-SUBAGENT GATE.
  4. **Halved re-review budget.** Re-review rounds (after a bounce): ≤8 tool calls, scope = open findings + fix diff, never a full re-read. Initial review stays ≤15. (Retro: halved-scope re-reviews after bounces instead of full re-reads.)
- [ ] **Step 2:** Considered Options + Consequences (chunk-driver keeps Gate 2 via the test-first chunk; empty-message bootstrap depends on journal-before-dispatch; re-review budget interacts with the ADR 0035 "re-examined → fixed" flip — a reviewer that can't reach a finding leaves it open, loop continues to cap).
- [ ] **Step 3:** Commit: `docs: ADR 0037 — chunk-driver degrade, self-compile default, empty-message bootstrap, halved re-review budget`

### Task 3: `impl/command-execution.md` — watchdog §9

**Files:**
- Modify: `skills/e2e-engineering/impl/command-execution.md`

**Steps:**
- [ ] **Step 1:** Append §9 "Background jobs stay bounded — orchestrator watchdog" (5 rules: bounded poll / hard deadline + `job_kill` / 10-min silence heuristic / orphan sweep by targeted PID / log kill + retro counter), grounded in the 4.7h wedge.
- [ ] **Step 2:** Add row to §4 outcome table: background job killed by watchdog → same routing as its phase timeout (gate-5 strike / gate-3 strike / teardown WARN).
- [ ] **Step 3:** Add 2 red-flag lines (unbounded wait on a background job; orphan processes after a kill).
- [ ] **Step 4:** Commit: `feat(command-execution): §9 background-job watchdog + evidence hygiene routing`

### Task 4: `impl/verification.md` — gate-5 execution rules

**Files:**
- Modify: `skills/e2e-engineering/impl/verification.md`

**Steps:**
- [ ] **Step 1:** Checkpoints section: extend the "Long steps detached + polled" bullet with the ADR 0036 watchdog (bounded poll, deadline, job_kill, silence heuristic, orphan sweep; killed step routes as phase timeout).
- [ ] **Step 2:** Step 2 (full suite): add "Test-fork heap (JVM suites)" + "Verdict discipline (stale-XML trap)" blocks (Task 1 decision 3/4 wording).
- [ ] **Step 3:** Add "Carrier-level API smoke (ADR 0036)" block (runs during Step 3; §4.1 heavy-rebuild override; gate-5 full suite unchanged).
- [ ] **Step 4:** Step 6: add evidence-hygiene sentence (counts + ≤20-line excerpts; full logs gitignored + deleted at worktree removal).
- [ ] **Step 5:** Red flags: add stale-XML (XML read without BUILD SUCCESSFUL), committing full logs, unbounded background wait.
- [ ] **Step 6:** Commit: `feat(verification): fork-heap, stale-XML verdict, carrier API smoke, watchdog, evidence hygiene`

### Task 5: `impl/tdd.md` — worker contract

**Files:**
- Modify: `skills/e2e-engineering/impl/tdd.md`

**Steps:**
- [ ] **Step 1:** Add §0 "Empty-message bootstrap (runtime payload-drop fallback)" — upstream the UniVerse local patch verbatim (self-brief from resume.json `dispatched[]` → `manifestPath` → `workerBrief`; worktree/branch from entry; no entry → `blocked` + blocker finding).
- [ ] **Step 2:** Add "Worker self-compile" rule: compile-only `compileCmd` before every commit.
- [ ] **Step 3:** Add "Chunk-driver mode (ADR 0037)" worker contract block: one narrow chunk + self-compile; orchestrator runs focused tests; chunk 1 = failing test (Gate 2 holds); manifest after last chunk.
- [ ] **Step 4:** Return-manifest section: evidence = counts + ≤20-line excerpts; full logs never committed.
- [ ] **Step 5:** Commit: `feat(tdd): empty-message bootstrap, self-compile default, chunk-driver contract, evidence hygiene`

### Task 6: `standards/api-testing.md` — frozen-clock pattern

**Files:**
- Modify: `skills/e2e-engineering/standards/api-testing.md`

**Steps:**
- [ ] **Step 1:** Add "Date/time boundaries (frozen clock)" section: boundary-test UTC midnight edges (23:59/00:01) via injected `Clock`/frozen time; `LocalDate.now()` windows fail only 00:00–05:00 UTC; windows zone-consistent UTC.
- [ ] **Step 2:** Commit: `feat(api-testing): frozen-clock UTC boundary test pattern`

### Task 7: `schemas/flow-retro.md` — new counters

**Files:**
- Modify: `skills/e2e-engineering/schemas/flow-retro.md`

**Steps:**
- [ ] **Step 1:** Template + §1: add `watchdog kills/hangs: <n>`, `chunk-driver degrade: <n> waves`, `carrier API smokes: <n> (red: <n>)`.
- [ ] **Step 2:** Commit: `feat(flow-retro): watchdog, chunk-driver, carrier-smoke counters`

### Task 8: Reviewer specs — re-review budget

**Files:**
- Modify: `skills/e2e-engineering/agents/backend-architect.md`, `dba.md`, `frontend-reviewer.md`, `test-reviewer.md` (Budget sections)
- Regenerate: `.claude/agents/*.md` via `skills/e2e-engineering/scripts/generate-agent-wrappers.ps1`

**Steps:**
- [ ] **Step 1:** In each canonical spec Budget section: "≤15 tool calls total (INITIAL review). Re-review round (after a bounce): ≤8 tool calls — re-examine ONLY the open findings + the fix diff; never a full re-read."
- [ ] **Step 2:** Run `pwsh -NoProfile -File skills/e2e-engineering/scripts/generate-agent-wrappers.ps1` to regenerate `.claude/agents/`.
- [ ] **Step 3:** Commit: `feat(agents): halved re-review budget (≤8) in reviewer specs + wrappers`

### Task 9: `.agents/skills/e2e-flight/SKILL.md` (Codex entry)

**Files:**
- Modify: `.agents/skills/e2e-flight/SKILL.md`

**Steps:**
- [ ] **Step 1:** After the H1, add SPAWNED-SUBAGENT GATE block (upstream from UniVerse: child task name = slice worker; empty message expected; self-brief via tdd.md §0; orchestrator journals before spawn so disk IS the brief).
- [ ] **Step 2:** Step 0 #6 retro tally: add watchdog kills/hangs, chunk-driver degrade waves, carrier API smokes.
- [ ] **Step 3:** Step 2 compile detection: add "§4.1b read ONCE" — execution amendments win over generic budgets; pass relevant lines in spawn manifests.
- [ ] **Step 4:** Step 3 intro: add empty-message worker dispatch note (disk is the brief).
- [ ] **Step 5:** Step 3.2: add chunk-driver degrade rule (zero-commit stalled wave → halved chunks + orchestrator-runs-tests; Gate 2 = test-first chunk; record degrade; never inline).
- [ ] **Step 6:** Step 3.3 convergence loop: add halved re-review budget (≤8, open findings + fix diff).
- [ ] **Step 7:** Step 3.5 merge: add carrier-level API smoke sub-step (rebuild stack per §4.1, run carrier's spec files only, red → in-slice fix; §4.1 heavy-rebuild override → WARN + defer).
- [ ] **Step 8:** Step 3.6 record: evidence-hygiene bullet (counts + ≤20-line excerpts; full logs gitignored/deleted).
- [ ] **Step 9:** Step 5.0: reference watchdog (background steps), fork-heap, stale-XML verdicts.
- [ ] **Step 10:** Token hygiene: lean state files line (pointers + counts only; narrative → qa-signoff/flow-retro at the end).
- [ ] **Step 11:** Red flags: add ~5 lines (unbounded background wait; committing full logs; XML before BUILD SUCCESSFUL; blind carrier specs without smoke/defer; orphan processes after kill).
- [ ] **Step 12:** Commit: `feat(e2e-flight codex): watchdog, chunk-driver, carrier smoke, evidence hygiene, §4.1b hook, empty-message gate`

### Task 10: `.claude/skills/e2e-flight/SKILL.md` (Claude entry)

**Files:**
- Modify: `.claude/skills/e2e-flight/SKILL.md`

**Steps:**
- [ ] **Step 1:** Apply the same changes as Task 9 in Claude vocabulary (ToolSearch/EnterWorktree, `../../../skills/e2e-engineering/` links) EXCEPT the SPAWNED-SUBAGENT GATE (Claude subagents receive prompts; keep tdd.md §0 as shared worker fallback only). Chunk-driver degrade applies to Claude's serial EnterWorktree dispatch too.
- [ ] **Step 2:** Commit: `feat(e2e-flight claude): watchdog, chunk-driver, carrier smoke, evidence hygiene, §4.1b hook`

### Task 11: `CONTEXT.md` truth delta

**Files:**
- Modify: `CONTEXT.md`

**Steps:**
- [ ] **Step 1:** Top delta block: add ADR 0036 + 0037 bullets (watchdog, evidence hygiene, fork-heap, stale-XML, carrier smoke, §4.1b hook; chunk-driver, self-compile, empty-message, halved re-review).
- [ ] **Step 2:** Add glossary entries: `Watchdog`, `Chunk-driver mode`, `Carrier API smoke`, `Evidence excerpts`.
- [ ] **Step 3:** Commit: `docs: CONTEXT delta for ADR 0036 + 0037`

### Task 12: Build + validate + finalize

**Files:**
- Regenerate: `dist/` via `npm run build`

**Steps:**
- [ ] **Step 1:** Run `npm run build` (raw, no rtk — this is a compile/test-class producer).
- [ ] **Step 2:** Run `npm run validate`; fix every reported error (broken links, stale dist, deprecated roles) and re-run until exit 0.
- [ ] **Step 3:** `git status` review; commit dist + any stragglers: `chore: rebuild dist for retro updates`

### Task 13: Sync UniVerse.Academy

**Files:**
- Modify (in `C:\Views\UniVerse.Academy`): `.agents/skills/`, `.claude/skills/`, `.claude/agents/`, `skills/`, `AGENTS.md`

**Steps:**
- [ ] **Step 1:** Dry-run installer: `node bin/install.js --dest C:\Views\UniVerse.Academy --target codex --dry-run` + `--target claude --dry-run`; inspect the file list.
- [ ] **Step 2:** Diff UniVerse `AGENTS.md` vs `dist/agents-md/AGENTS.md` — UniVerse is missing the rtk-trap bullet; confirm overwrite is desirable (it is), back up current UniVerse AGENTS.md.
- [ ] **Step 3:** Run installer with `--force` for `codex` and `claude` targets.
- [ ] **Step 4:** Verify tree parity: re-run the path+hash comparison of `skills/e2e-engineering` between repos — expect zero diffs except expected generated differences.
- [ ] **Step 5:** Verify §4.1b interplay: UniVerse ARCHITECTURE §4.1b fork-heap/stale-XML/UTC lines remain the winner; new generic rules don't conflict.
- [ ] **Step 6:** Verify the two previously-flagged files (`finding-verifier.md`, `followups.json.md`) now come from the installer and are tracked.
- [ ] **Step 7:** `git status` + commit in UniVerse: `chore: refresh e2e-engineering install (v1.13.0 + retro updates)`.

### Task 14: Verification report

**Steps:**
- [ ] **Step 1:** Re-read plan checklist → confirm every step verified with fresh output (superpowers:verification-before-completion).
- [ ] **Step 2:** Report: files changed in main repo + UniVerse, validate output, tree-parity output, next-flight readiness (video-content-protection).

## Self-Review

- [ ] Spec coverage: every retro line 12–21 mapped to a task (1→T4, 2/19→T1+T3+T4, 3→T2+T5, 4→T1+T4, 5→T1+T4+T9/T10, 6→T1, 7→T6, 8→T13, 9→T2, 10→T1, 11→T5/T9, 13→T2/T9, 14→T2/T5, 16→T1, 17→T6, 18→T13, 20→T1, 21→T2/T5/T9/T11).
- [ ] Placeholder scan: no TBD/TODO in task steps.
- [ ] Type consistency: budget numbers (≤15 initial / ≤8 re-review / ≤8 verifier), phase budgets (stack-up 10 / build 15 / suite 30 / playwright 20), counter names match flow-retro schema.

## Execution Handoff

Execution approach: **Inline execution** (superpowers:executing-plans) — the 14 tasks are tightly-coupled edits to one doc system; cross-file consistency (budget numbers, counter names, link validity) is cheaper to hold inline than to re-derive per fresh subagent.
