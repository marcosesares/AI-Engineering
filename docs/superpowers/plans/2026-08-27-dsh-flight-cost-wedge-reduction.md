# DSH Flight Cost + Wedge Reduction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the grilled skill-improvement plan from the 2026-08 DSH flight retro to the e2e-flight skill — DSH-first. Cut the measured token profile (8.2M reasoning / 7.4M assistant / 8.5M tool-result, 192 sessions, 1118 turns, 67 child agents, 4 wedge events) and eliminate the wedge classes.

**Tech Stack:** Markdown skill docs (caveman-ultra), PowerShell scripts (bounded + non-interactive, JSON verdicts), DSH `workflow`/`subagent` dispatch, `scripts/validate.js` acceptance gate.

**Architecture:** One new ADR (0039) carries DSH review-wave routing + model tiers. ADRs 0035/0036/0037 get targeted amendments (convergence v2, batched carrier smoke + stack ownership, worker brief contract). Doc edits land in the shared `skills/e2e-engineering/` tree + the flight entry. 13 scripts join `skills/e2e-engineering/scripts/` under a governance rule. `npm run build` regenerates `dist/`. Self-contained scope: no client-repo installs.

**Spec:**
- `2026-08 DSH flight retro` (anonymized per 2026-08-27 grill: measured baseline + 7 improvement sections; source path not cited — self-contained scope)
- This plan is the grilled replacement for the retro's §IMPROVEMENT PLAN (see Resolved Design Decisions below for superseded lines)
- Main repo: `docs/adr/*.md` (ADR format), `scripts/validate.js` (acceptance gate)

## Resolved Design Decisions (grill session 2026-08-27)

Each decision is final; task steps below implement it. Superseded retro lines are noted so no executor re-implements them.

- **D1 — DSH-first scope.** Mechanisms verified on DSH; shared spec stays runtime-neutral; Codex/Claude entries change only where shared docs force it; no re-verification on unmeasurable runtimes.
- **D2 — Review/verify waves route through the `workflow` tool.** Impl workers stay background `subagent` (prompt discipline only — no model knob). T0 (cheap/non-thinking: finding-verifier, mechanical slots) / T1 (thinking: judgment reviewers) tier via workflow's enforced per-agent model override (probe-verified 2026-08-27: bogus override → child fails loudly). Schema-validated pre-merged fan-in kills per-reviewer orchestrator fan-in cost. Stuck-reviewer protocol moves inside the workflow script (null-filter; budgets pre-bounded ≤15 initial / ≤8 re-review / ≤8 verifier). **T2 reviewer reuse is DROPPED** (retro §1 line — no `send_message` continuation; marginal value over ADR 0037's halved re-review is small; self-confirmation smell). Workflow unavailable at Step-0 probe → degrade to subagent review waves + prompt-discipline tiers, NOT a stall (fan-out still works).
- **D3 — Convergence loop v2 (amends ADR 0035).** Phase A: while any Critical/Important is `open`, bounce → worker fixes ALL open findings in one pass (Minors piggyback) → re-review. Phase B: when zero C/I open → one fix pass for all remaining Minors → ONE review (scope = finding-owner roles + `test-reviewer`) → any Minor still open → `state: carried` → `followups.json` (P3). Cap = **5** (was 4), absolute per slice, never reset. Edge rules: cap exhausted in Phase A with Minors open → carried WITHOUT fix pass; new C/I surfaced in the Phase-B review → back to Phase A (count continues); un-cited Minors still drop at the hygiene gate (no carry without cite + implied action). **Supersedes retro §6 "carry Minors discovered at round ≥3"** (trigger is now severity-state, not discovery round).
- **D4 — Flight Step 2 fails closed on Gate-1 state.** `gate1Approved: false` → stall `unapproved-prd` + revert queue status `ready-for-flight → needs-spec`. Any story `estimatedLoc` missing/out-of-bounds for its `sliceType` → stall `oversized-slice` + revert to `ready-for-flight` + `progress.txt` note. Deliberate exceptions carry `gate1SizingOverride: true` + who/why in prd.json; override-approved oversized slices get subsystem-scoped reviewer evidence. Replaces the current "WARN, still fly it" line. **Supersedes retro §7 "ENFORCE the split at to-issues"** (to-prd/to-issues already enforce; the defect was a restore-path bypass + fail-open flight).
- **D5 — Context-budget mechanism DROPPED (retro §7).** No turn/char budget, no CHECKPOINT manifest (term removed by ADR 0022). Door-ban (D4) + chunk-driver (ADR 0037) + tdd.md §0 recovery line carry worker-context safety. Orchestrator hygiene kept: `review-fan-in.ps1`, `subagent_fork` for synthesis, deltas-from-disk.
- **D6 — Carrier smoke batched per wave (amends ADR 0036).** After a wave's merges: ONE stack-up + every changed spec file run in that session. Red spec → repair slice on the task branch (worker + Gate 3), merged before the wave closes. No wave closes with a red smoke. Detection anchor moves merge-time → wave-close, stays pre-gate-5.
- **D7 — Stack ownership, no probe (retro §6 stack-probe item DROPPED).** Flight owns the compose stack during smoke/gate-5: canonical `down -v → package build → up --force-recreate --build -d` runs unconditionally (bounded + log-to-file per ADR 0033). Add one user-facing line: the flight tears down and rebuilds the stack — don't keep dev work in a running compose stack during a flight.
- **D8 — Scripts library (retro §3), all 13, under governance.** Scripts: `slice-setup`, `slice-rebase-guard`, `port-commits` (restore-only), `compile-check`, `lint-check`, `build-package`, `run-focused-tests`, `review-bundle`, `review-fan-in`, `carrier-smoke`, `killswitch`, `slice-merge`, `session-cost` (diagnostics-only). Governance: bounded + non-interactive + log-to-file + JSON verdict (ADR 0033 contract encoded); single canonical check (worker + orchestrator call the SAME script); scripts never write sidecars (sole-writer = orchestrator, ADR 0034); DSH-safe (no named-pipe output capture — logs to file, read tail); all human-readable output (log lines, messages, JSON prose values) in **caveman-ultra** (JSON keys/enums stay schema-stable; code symbols/error strings never abbreviated).
- **D9 — Worker brief = complete contract (retro §2 + §4).** Zero skill-file reads for workers: brief carries constitution digest (~15 lines) + command-rules digest (~10 lines) + ACs + integration + compileCmd + lint digest + role digests. Lint contract injection: Step 2 reads the repo's eslint config ONCE → ≤15-line digest into every brief (backend: no lint tool → ARCHITECTURE/constitution only). Review contract injection: ≤15-line checklist digest per role, living as a canonical `## Digest` section inside each `agents/<role>.md` (Step 2 extracts — never hand-maintained twice). tdd.md gains a PRE-RETURN SELF-CHECK (run each applicable digest against own diff; fix or list as `findings[]`). Safety valve: tdd.md §1 gap-check escalation stays.
- **D10 — Semantic commit points replace per-commit checks.** Commit points (tdd.md list): (1) red test (Gate 2), (2) green impl per AC, (3) refactor unit, (4) one commit per fix pass, (5) one commit per chunk, (6) one commit per cherry-pick sequence (restore). Checks (`compile-check`/`lint-check`) are MANDATORY at commit points, optional elsewhere; scope follows changed files (frontend-only → tsc+eslint; backend-only → compile). Expected ~3–6 commits per in-bounds slice. Wedge visibility = boundaries + zero-commit-wave trigger → chunk-driver (ADR 0037), not micro-commits.
- **D11 — Artifact hygiene (retro §5).** Committing `evidence/` dirs is BANNED (joins env/config in the "untracked only" rule). Step 2.2 committed-but-unrecorded reconcile reads the branch commit log + orchestrator re-verification (compile + focused tests) instead of an in-branch evidence README. Worktrees pruned at task close (`git worktree remove --force`; branches persist; prune after Step 5/6). TC files: "Run UI e2e" → "Manual walk". `heap.init.gradle` moves into `slice-setup.ps1`'s copy list.
- **D12 — Small items (retro §6 batch).** (1) dispatch-time HEAD refresh — `git rev-parse` at dispatch, never from memory; (2) port allocator ledger in `resume.json` (`ports` block; conditional docker/Testcontainers projects); (3) concurrency budget probe at Step 0 → cap in `resume.json` (caps concurrent subagent dispatch + workflow parallelism); (4) api-testing standard: per-domain fixture helpers (seed/cleanup) — kills cross-spec data contamination; (5) gate-5 Playwright invocation: `retries=0 workers=1` + documented isolation baseline; (6) api-testing: docker-CLI-container fallback documented as canonical Testcontainers workaround; (7) worker canary step: first brief instruction = one `pwsh` (`git rev-parse HEAD`) + reply `CANARY-OK`. **Cost baseline REMOVED:** no flow-retro cost section, no auto-append; `session-cost.ps1` ships diagnostics-only; one-time verification: run it after the next flight and compare to the 8.2M/7.4M/8.5M baseline.

## Global Constraints

- Skill docs maintained in caveman-ultra density (SKILL.md token-hygiene rule) — new text matches existing terse style, no fluff. The plan file itself is normal English (house format).
- `npm run build && npm run validate` must exit 0 before any commit; `validate.js` checks markdown-link resolution, dist freshness vs sources, no deprecated role names, JSON validity.
- `ARCHITECTURE.md §4.1b` values (fork-heap, ports, playwright fallback, UTC dates) WIN over new generic skill rules — the skill never hardcodes client-repo specifics.
- Never edit `.claude/agents/*.md` by hand — regenerate via `generate-agent-wrappers.ps1` from canonical specs.
- DSH-first: do NOT touch `.claude/skills/` or Codex-entry mechanics beyond what a shared-doc change forces; every DSH mechanic goes in `impl/dsh-runtime.md`.
- All work on branch `skill/retro-video-2026-08`; never main.

---

### Task 1: ADR 0039 — DSH review-wave routing + model tiers

**Files:**
- Create: `docs/adr/0039-dsh-review-routing-and-model-tiers.md`

**Steps:**
- [ ] **Step 1:** Write ADR 0039, Status `accepted`, refines ADR 0038 (adds the `workflow` tool as the review/verify dispatch surface + per-agent model routing), ADR 0035 (review-wave mechanics: schema-validated fan-in, T0/T1 tiers; convergence loop itself is ADR 0035's amendment in Task 2). Decisions:
  1. **Review/verify waves = `workflow` tool.** Initial review, re-review, and finding-verifier waves dispatch as workflow scripts: parallel `agent()` stages, per-agent `model` override (T0 cheap / T1 judgment), `opts.schema`-validated results returned pre-merged. Stuck-reviewer protocol lives in-script: child failure resolves `null` → filter + record gap in `notes` (ADR 0035's re-dispatch-once/halved-scope applies to the workflow stage, then proceed). Workflow waves are FOREGROUND and blocking: budgets pre-bounded in prompts (≤15 initial / ≤8 re-review / ≤8 verifier), wave size 2–4 agents.
  2. **Tier table.** T0 non-thinking cheap: finding-verifier, mechanical review slots, fan-in. T1 thinking medium: judgment reviewers (backend-architect, dba, frontend-reviewer, test-reviewer initial waves). Impl workers: background `subagent`, prompt-discipline only (no model knob exists) — the T1 discipline (commit-per-boundary, JSON-only manifests, evidence-pointer returns) applies via the brief. T2 reuse retired with this ADR (same-agent follow-up re-review rejected: marginal over ADR 0037 halved re-review; self-confirmation smell; incompatible with ephemeral workflow agents).
  3. **Degrade, don't stall.** Step-0 probe adds workflow availability (one trivial script). Absent/failing → review/verify waves fall back to background `subagent` dispatch with prompt-discipline tiers (existing ADR 0038 mapping). Fan-out capability is what's essential; model routing is an optimization.
  4. **Reasoning-cost claim is a hypothesis.** Expected reasoning reduction ~-50% rides on model routing; prompt-discipline-only portions reduce assistant/output tokens. `session-cost.ps1` (diagnostics) is the one-time check after the next flight vs the 8.2M/7.4M/8.5M baseline.
- [ ] **Step 2:** Considered Options: subagent-only review with prompt-discipline tiers (rejected — no model knob; reasoning untouched); workflow for impl workers (rejected — foreground blocks the orchestrator for worker-length durations); T2 reviewer reuse (rejected per decision 2); per-agent harness-settings edits (rejected — routing is a skill policy, never user settings).
- [ ] **Step 3:** Consequences: workflow wedge risk (foreground call cannot be `job_kill`ed mid-script — bounded by prompt budgets + small waves + harness workflow caps); reviewer-fan-in cost near-zero; tiers unverifiable off-DSH.
- [ ] **Step 4:** Commit: `docs: ADR 0039 — DSH review-wave routing + model tiers`

### Task 2: Amend ADR 0035 — convergence loop v2

**Files:**
- Modify: `docs/adr/0035-review-convergence-loop-and-finding-verifier.md`

**Steps:**
- [ ] **Step 1:** Add an `## Amendment (2026-08-27 — convergence v2)` section implementing D3: Phase A (C/I-driven; Minors piggyback; all open findings fixed per pass) → Phase B (one Minor fix pass + one review, scope = finding-owner roles + test-reviewer → survivors `state: carried` → followups P3). Cap 4 → **5**, rationale: the Minor fix pass is now the FINAL round, so cap 5 guarantees it a slot after a full C/I loop. Edge rules verbatim from D3 (cap-hit-in-Phase-A → carried w/o pass; new C/I in Phase B → back to Phase A, no reset; un-cited Minor → dropped, no carry). Merge gate: zero open Critical/Important; Minors resolved per rule. New finding state `carried` joins `open|fixed|dropped-refuted|open-at-cap`.
- [ ] **Step 2:** Record the supersession: the original decision-2 sentence "Minor is an ordinary finding; a Minor-only round is legal and costs one round" is replaced; the Considered-Options entry "Minors deferred" is revisited with this flight's data (15 bounces, 2 cap exhaustions — rounds are the scarce resource).
- [ ] **Step 3:** Consequences: cap-5 ripple list (SKILL.md, CONTEXT.md, flow-retro schema `n/5`, tdd.md, reviewer specs) — all handled in Tasks 5/8/9/12.
- [ ] **Step 4:** Commit: `docs: ADR 0035 amendment — convergence v2 (Phase A/B, cap 5, carried)`

### Task 3: Amend ADR 0036 — batched carrier smoke + stack ownership

**Files:**
- Modify: `docs/adr/0036-bounded-background-jobs-evidence-hygiene-and-gate5-execution.md`

**Steps:**
- [ ] **Step 1:** Add `## Amendment (2026-08-27 — batched carrier smoke)` implementing D6: smoke runs once per wave after the wave's merges (ONE stack-up, all changed spec files in that session); red spec → repair slice on the task branch (worker + Gate 3) merged before the wave closes; "no wave closes with a red smoke" invariant; detection stays pre-gate-5, anchor moves merge-time → wave-close. §4.1 heavy-rebuild defer WARN unchanged.
- [ ] **Step 2:** Add stack-ownership line (D7): the flight owns the compose stack during smoke/gate-5; `down -v → build → up --force-recreate --build -d` unconditional; user-facing warning line lives in the flight entry (Task 5), not in the ADR.
- [ ] **Step 3:** Commit: `docs: ADR 0036 amendment — batched carrier smoke, stack ownership`

### Task 4: Amend ADR 0037 — worker brief contract

**Files:**
- Modify: `docs/adr/0037-degraded-dispatch-and-worker-contract.md`

**Steps:**
- [ ] **Step 1:** Add `## Amendment (2026-08-27 — worker brief contract)` implementing D9 + D10 + D11: worker receives a COMPLETE inline brief (constitution digest + command-rules digest + ACs + integration + compileCmd + lint digest + role digests) — zero skill-file reads; empty-message bootstrap unchanged (journaled manifest IS the brief). Self-compile decision 2 becomes "checks at SEMANTIC COMMIT POINTS" (commit-point list verbatim; checks mandatory at points, optional elsewhere, scope follows changed files). Committing `evidence/` dirs banned (untracked-only rule); committed-but-unrecorded reconcile reads branch commit log + orchestrator re-verification. Worker canary step (D12.7) added to the dispatch contract. tdd.md §1 gap-check escalation stays the safety valve for thin digests.
- [ ] **Step 2:** Commit: `docs: ADR 0037 amendment — worker brief contract, semantic commit points, no evidence commits`

### Task 5: `.agents/skills/e2e-flight/SKILL.md` — flight entry edits

**Files:**
- Modify: `.agents/skills/e2e-flight/SKILL.md`

**Steps:**
- [ ] **Step 1:** Step 0: add workflow-availability probe (DSH mode — one trivial workflow script; absent → subagent review fallback per ADR 0039) + concurrency budget probe (RAM/CPU → cap in resume.json, D12.3).
- [ ] **Step 2:** Step 2: REPLACE the oversized-slice WARN block with the fail-closed check (D4): `gate1Approved:false` → stall `unapproved-prd` + revert queue `needs-spec`; out-of-bounds/missing `estimatedLoc` → stall `oversized-slice` + revert `ready-for-flight` + progress note; `gate1SizingOverride` honored with subsystem-scoped reviewer evidence.
- [ ] **Step 3:** Step 2: lint-contract + review-contract extraction (D9): read repo eslint config ONCE → lint digest; extract `## Digest` sections from the applicable `agents/<role>.md` specs ONCE; both cached alongside compileCmd for every brief.
- [ ] **Step 4:** Step 3.2: dispatch manifest gains: HEAD sha re-read via `git rev-parse` AT dispatch (D12.1), worker canary first-instruction (D12.7), inline digests (D9).
- [ ] **Step 5:** Step 3.3: convergence loop v2 (D3) — Phase A/B, cap 5, `carried`, Phase-B review scope; review/verify waves dispatched via `workflow` per ADR 0039 (subagent fallback noted).
- [ ] **Step 6:** Step 3.5: batched carrier smoke (D6) — wave-level stack-up + all changed specs; red → repair slice; no wave closes red.
- [ ] **Step 7:** Step 5.0/5.1: stack-ownership line (D7) + gate-5 Playwright invocation `retries=0 workers=1` + isolation baseline (D12.5).
- [ ] **Step 8:** Step 6: flow-retro counters — `carried Minors: n`, bounce rounds `n/5`; NO cost section (D12 removal).
- [ ] **Step 9:** Red flags: add fail-closed stalls, workflow-wedge bound (never unbounded workflow wave), no evidence commits, canary requirement, port-ledger claims (D12.2 — scripts claim ports from resume.json, never hand-assign).
- [ ] **Step 10:** Commit: `feat(e2e-flight): fail-closed Step 2, workflow review waves, convergence v2, batched smoke, stack ownership`

### Task 6: `impl/tdd.md` — worker brief contract + commit points

**Files:**
- Modify: `skills/e2e-engineering/impl/tdd.md`

**Steps:**
- [ ] **Step 1:** §0: add recovery line (D5): restarted/compacted worker resumes from branch diff + slice status JSON + journaled manifest — never re-reads the full original brief.
- [ ] **Step 2:** Add "Complete brief" block (D9): the workerBrief is the whole contract; zero skill-file reads; digests are canonical; gap not covered by digests → §1 gap-check escalation (one question), never guess.
- [ ] **Step 3:** Add "Semantic commit points" block (D10): commit-point list verbatim; `compile-check`/`lint-check` mandatory at points (scope follows changed files), optional elsewhere; ~3–6 commits per in-bounds slice.
- [ ] **Step 4:** Add "Lint contract" line: write to the injected lint digest from line one; treat as part of the ACs.
- [ ] **Step 5:** Add PRE-RETURN SELF-CHECK (D9): run each applicable role digest against own diff; fix violations or list as known deviations in `findings[]`.
- [ ] **Step 6:** Canary: first tool call = `git rev-parse HEAD` via pwsh, reply `CANARY-OK` (D12.7).
- [ ] **Step 7:** Evidence rule (D11): NEVER commit `evidence/` dirs — untracked only; evidence = manifest pointers + counts + ≤20-line excerpts.
- [ ] **Step 8:** Red flags: add evidence-commit ban, canary skip, commit outside semantic points.
- [ ] **Step 9:** Commit: `feat(tdd): complete brief, semantic commit points, self-check, canary, no evidence commits`

### Task 7: `impl/dsh-runtime.md` — workflow mapping + probes

**Files:**
- Modify: `skills/e2e-engineering/impl/dsh-runtime.md`

**Steps:**
- [ ] **Step 1:** Tool-mapping table: add `workflow` row — review/verify waves = workflow scripts with per-agent `model` (T0/T1), `schema`-validated results, null-filter for failed children; impl workers stay background `subagent`.
- [ ] **Step 2:** Step-0 probes: add workflow-availability probe + concurrency budget probe (D12.3).
- [ ] **Step 3:** Tier table (T0/T1 slots + budgets) + degrade rule (workflow absent → subagent waves, prompt-discipline tiers).
- [ ] **Step 4:** Wedge note: workflow is foreground — pre-bound wave size + budgets; never an unbounded workflow script.
- [ ] **Step 5:** Commit: `feat(dsh-runtime): workflow review waves, tier table, new probes`

### Task 8: Reviewer specs — `## Digest` sections + cap 5 + carried

**Files:**
- Modify: `skills/e2e-engineering/agents/backend-architect.md`, `dba.md`, `frontend-reviewer.md`, `test-reviewer.md`
- Regenerate: `.claude/agents/*.md` via `skills/e2e-engineering/scripts/generate-agent-wrappers.ps1`

**Steps:**
- [ ] **Step 1:** Each spec gains a canonical `## Digest` section (≤15 lines): the role's checklist distilled for worker pre-return self-check (backend-architect: Resource→Service→Repository only; Panache inside @WithSession; reactive Uni end-to-end; extend named owner; validate every user-controlled path param. dba: migrations renumbered per task range; never edit applied migrations in place; index every WHERE/ORDER BY; entity columns match DDL. test-reviewer: every AC → real assertion, no fake-green; negative cases per 403/404/409; real-stack Playwright for endpoints, UI Manual only; no hardcoded sleeps; skipped=0. frontend-reviewer: DESIGN.md register + tokens; i18n hook; aria roles on decorative/alert content; prefers-reduced-motion; transform/opacity-only motion).
- [ ] **Step 2:** Each spec's merge-gate line: "cap 4 rounds" → "cap 5 rounds"; add Phase-B sentence (Minor survivors after the Phase-B review → `carried` → followups P3) + Phase-B review scope (finding-owner roles + test-reviewer).
- [ ] **Step 3:** Regenerate wrappers; verify no hand edits in `.claude/agents/`.
- [ ] **Step 4:** Commit: `feat(agents): digest sections, cap 5, carried state`

### Task 9: Schemas — prd.json, resume.json, flow-retro, followups

**Files:**
- Modify: `skills/e2e-engineering/schemas/prd.json.md`, `schemas/resume.json.md`, `schemas/flow-retro.md`, `schemas/followups.json.md`

**Steps:**
- [ ] **Step 1:** prd.json: add optional `gate1SizingOverride: true|false` + `sizingOverrideNote` (who/why) — flight Step 2 fail-closed reads these (D4).
- [ ] **Step 2:** resume.json: `bounce` cap `4` → `5`; add `ports` block (next-free-port counter, conditional docker/Testcontainers) + `concurrency` cap (D12.2/D12.3); add per-slice `carried: <n>` count.
- [ ] **Step 3:** flow-retro: template `n/4` → `n/5`; add `carried Minors: <n>` counter; NO cost section (D12 removal — session-cost.ps1 is diagnostics-only, run manually).
- [ ] **Step 4:** followups: carried Minors enter as P3 entries (suggestedPriority from severity, unchanged).
- [ ] **Step 5:** Commit: `feat(schemas): gate1 override, ports/concurrency, cap 5, carried counter`

### Task 10: Standards — api-testing + verification

**Files:**
- Modify: `skills/e2e-engineering/standards/api-testing.md`, `impl/verification.md`

**Steps:**
- [ ] **Step 1:** api-testing: add per-domain fixture helpers mandate (seed/cleanup helpers per domain — course/lesson/asset/session; no per-spec hand-seeding; cross-spec data contamination was the 4-video-suite-failure root cause).
- [ ] **Step 2:** api-testing: document the docker-CLI-container fallback as the canonical Testcontainers workaround (Docker Desktop 29 incompatibility).
- [ ] **Step 3:** verification.md: gate-5 Playwright invocation standard — `retries=0 workers=1` + documented isolation baseline (retry-inflated counts are noise).
- [ ] **Step 4:** Commit: `feat(standards): domain fixtures, Testcontainers fallback, playwright invocation standard`

### Task 11: Scripts — the 13-script library

**Files:**
- Create in `skills/e2e-engineering/scripts/`: `slice-setup.ps1`, `slice-rebase-guard.ps1`, `port-commits.ps1`, `compile-check.ps1`, `lint-check.ps1`, `build-package.ps1`, `run-focused-tests.ps1`, `review-bundle.ps1`, `review-fan-in.ps1`, `carrier-smoke.ps1`, `killswitch.ps1`, `slice-merge.ps1`, `session-cost.ps1`

**Steps:**
- [ ] **Step 1:** Write each script to this exact contract + D8 governance (bounded + non-interactive: CI=1 env block, no watch/serve; long producers log-to-file + read tail — NEVER named-pipe capture, DSH forbids; JSON verdict on exit; human-readable output caveman-ultra — keys/enums schema-stable, code symbols never abbreviated; no sidecar writes):
  - `slice-setup.ps1 -TaskId -SliceId -BaseSha` → slice branch + worktree + copies cached env files + `heap.init.gradle` → replaces orchestrator per-wave manual setup.
  - `slice-rebase-guard.ps1 -TaskId -SliceId` → merge-base ancestry check; auto-rebase onto task HEAD; exit code + changed-files report → replaces hand-checking diffs for D-deletions.
  - `port-commits.ps1 -Shas @(...) -MigrationMap @{V20='V33'} -Branch` → cherry-pick sequence with GIT_EDITOR=true, migration renames, stop-at-first-conflict printing the conflicting file → replaces mechanical cherry-pick/rename (conflict RESOLUTION stays agent-side). Restore-only.
  - `compile-check.ps1 -Worktree -Scope backend|frontend|both` → backend: gradle :backend:compileJava :backend:compileTestJava (bounded, no-daemon, log to file); frontend: npx tsc -b; JSON BUILD verdict + first errors → replaces ad-hoc self-compile + per-slice compile gate (worker + orchestrator call the SAME script).
  - `lint-check.ps1 -Worktree -ChangedFiles <list>` → npx eslint on changed/new files only; problems count + per-file list JSON → replaces late Step-3.4 eslint bounce; wired into worker commit loop.
  - `build-package.ps1 -Worktree` → gradle :backend:quarkusBuild (bounded 15m) → replaces repeated manual package builds (stack-owned; OUT of the per-slice worker loop).
  - `run-focused-tests.ps1 -Tests @(...) -Port -HeapInit` → bounded gradle/vitest run, log to file, JSON verdict + XML counts → replaces log-reading/verdict reading (stale-XML discipline becomes code).
  - `review-bundle.ps1 -SliceId -Base -Head` → git diff --name-status/--stat + testEvidence skeleton JSON → replaces hand-building mechanical bundle fields.
  - `review-fan-in.ps1` → merges reviewer JSON into review-result.json (mechanical) → replaces orchestrator fan-in context spend.
  - `carrier-smoke.ps1 -Spec @(...) -KillSwitchMode on|off` → down/up --build/readiness-poll/spec-runs/teardown with bounded phases + watchdog-friendly log; ONE stack-up per wave (D6) → replaces ~15 hand-run smoke sequences incl. the OFF-state compose override.
  - `killswitch.ps1 on|off` → temp compose override + backend restart → replaces hand-written override + restart.
  - `slice-merge.ps1 -SliceId -TaskId` → merge --no-edit + clean-tree verify → replaces manual merge+verify (sidecar writing stays orchestrator).
  - `session-cost.ps1` (diagnostics) → zstd frame-split decode of ~/.dsh/sessions + per-agent reasoning/output/tool-result tallies → postmortem analyzer; NOT wired into flight steps (D12 removal).
- [ ] **Step 2:** Port ledger + concurrency wiring: `run-focused-tests.ps1` / `carrier-smoke.ps1` claim/release ports from resume.json `ports`; scripts never hand-assign (D12.2).
- [ ] **Step 3:** `carrier-smoke.ps1` implements the D6 batched interface (`-Spec @(...)` list, ONE stack-up per wave); `killswitch.ps1` keeps off-state compose override; `build-package.ps1` bounded 15m quarkusBuild; `compile-check`/`lint-check` take `-Scope`/`-ChangedFiles` (D10).
- [ ] **Step 4:** `port-commits.ps1` marked restore-only; `session-cost.ps1` diagnostics-only (zstd session decode; NOT wired into flight steps — D12 removal).
- [ ] **Step 5:** Commit: `feat(scripts): 13-script library under governance rule`

### Task 12: `CONTEXT.md` — glossary truth delta

**Files:**
- Modify: `CONTEXT.md`

**Steps:**
- [ ] **Step 1:** Top delta block: add ADR 0039 bullet + amendment bullets for 0035/0036/0037 (workflow review waves + tiers; convergence v2 cap 5 + carried; batched carrier smoke + stack ownership; worker brief contract).
- [ ] **Step 2:** Glossary entries: `Routing tier` (T0/T1; T2 retired), `carried` (finding state), `unapproved-prd` + `oversized-slice` (stall set), `Stack ownership`, `Worker brief`, `Semantic commit point`, `Digest` (canonical role checklist section).
- [ ] **Step 3:** Update the `Review convergence loop` entry (cap 4 → 5, Phase A/B, carried).
- [ ] **Step 4:** Commit: `docs: CONTEXT delta for ADR 0039 + amendments`

### Task 13: Build + validate + finalize

**Files:**
- Regenerate: `dist/` via `npm run build`

**Steps:**
- [ ] **Step 1:** Run `npm run build` (raw, no rtk — compile-class producer).
- [ ] **Step 2:** Run `npm run validate`; fix every error (broken links, stale dist, deprecated roles, JSON validity) and re-run until exit 0.
- [ ] **Step 3:** `git status` review; commit dist + stragglers: `chore: rebuild dist for flight-retro skill updates`

### Task 14: ~~Sync UniVerse.Academy~~ — REMOVED (grill 2026-08-27)

Scope decision: this improvement is self-contained to the e2e-engineering repo — no client-repo installs. v2 carries no sync task.

### Task 15: Verification report

**Steps:**
- [ ] **Step 1:** Re-read plan checklist → confirm every step verified with fresh output (superpowers:verification-before-completion).
- [ ] **Step 2:** Report: files changed in this repo, validate output, next-flight readiness. Note the one-time `session-cost.ps1` check to run after the next DSH flight (vs 8.2M/7.4M/8.5M baseline).

## Self-Review

- [ ] Spec coverage: every Resolved Design Decision D1–D12 maps to ≥1 task (D1→G1/T5; D2→T1/T5/T7; D3→T2/T5/T8/T9; D4→T5/T9; D5→T4/T6; D6→T3/T5/T11; D7→T3/T5; D8→T11; D9→T4/T5/T6/T8; D10→T4/T6/T11; D11→T4/T6/T11; D12→T5/T7/T9/T10/T11).
- [ ] Superseded retro lines NOT re-implemented: §1 T2 reuse, §6 carry-at-round≥3, §6 Step-0 stack probe, §7 budget/CHECKPOINT mechanism, §7 to-issues enforcement, §5 "strip at record", §6 per-flight cost baseline auto-append.
- [ ] Placeholder scan: no TBD/TODO in task steps.
- [ ] Type consistency: cap 5 everywhere (SKILL.md, CONTEXT.md, flow-retro `n/5`, reviewer specs, resume.json); budgets ≤15 initial / ≤8 re-review / ≤8 verifier; `carried` state name consistent across ADR 0035 amendment, SKILL.md, schemas, reviewer specs.

## Execution Handoff

Two execution options:

1. **Subagent-Driven (recommended)** — fresh subagent per task + two-stage review between tasks (REQUIRED SUB-SKILL: superpowers:subagent-driven-development).
2. **Inline Execution** — execute tasks in this session via superpowers:executing-plans, batch execution with checkpoints.

Either way: cross-file consistency (cap 5, `carried`, digest sections, budget numbers, counter names, link validity) is cheapest held by ONE context than re-derived per fresh agent — the subagent-driven split should still hand each worker the full D-decision list above, not just their task. Task 11 (13 scripts) is the only isolated implementation chunk — delegate per-script, but hold the governance rule + resume.json wiring in the executing context.
