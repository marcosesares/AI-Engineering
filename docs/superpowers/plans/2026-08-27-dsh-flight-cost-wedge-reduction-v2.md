# DSH Flight Cost + Wedge Reduction Implementation Plan (v2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the 12 grilled design decisions (D1–D12) in the e2e-flight skill, DSH-first: workflow-routed review waves + model tiers (T0/T1), convergence loop v2 (Phase A/B, cap 5, `carried`), fail-closed Step 2 (`unapproved-prd`/`oversized-slice` stalls), wave-batched carrier smoke with repair-slice semantics, complete worker briefs with semantic commit points, and the 13-script library under governance.

**Architecture:** One new ADR (0039) + amendments to ADRs 0035/0036/0037 carry the decisions. Skill-doc edits land in `skills/e2e-engineering/` + `.agents/skills/e2e-flight/SKILL.md` as exact old→new string replacements (below). 13 PowerShell scripts join `skills/e2e-engineering/scripts/` behind a shared governance header. `npm run build` regenerates `dist/`; `npm run validate` gates. Self-contained scope: no client-repo installs.

**Tech Stack:** Markdown skill docs (caveman-ultra), PowerShell 7 scripts (bounded + non-interactive, JSON verdicts), DSH `workflow`/`subagent` dispatch, `scripts/validate.js`.

**Spec:**
- `C:\Views\e2e-Engineering\docs\superpowers\plans\2026-08-27-dsh-flight-cost-wedge-reduction.md` (v1 plan — the D1–D12 decisions this plan implements; its Self-Review lists the superseded retro lines)
- Measured 2026-08 DSH flight baseline (anonymized per 2026-08-27 grill — source retro not cited): 8.2M reasoning / 7.4M assistant / 8.5M tool-result, 67 child agents, 4 wedge events

## Global Constraints

- Skill docs maintained in caveman-ultra density — new text matches existing terse style, no fluff.
- `npm run build && npm run validate` must exit 0 before any commit.
- `ARCHITECTURE.md §4.1b` values (fork-heap, ports, playwright fallback, UTC dates) WIN over new generic skill rules — never hardcode client-repo specifics.
- Never edit `.claude/agents/*.md` by hand — regenerate via `skills/e2e-engineering/scripts/generate-agent-wrappers.ps1`.
- DSH-first: do NOT touch `.claude/skills/` or Codex-entry mechanics beyond shared-doc ripples; every DSH mechanic goes in `impl/dsh-runtime.md`.
- All work on branch `skill/retro-video-2026-08`; never main.

## File Structure

| File | Responsibility |
|---|---|
| `docs/adr/0039-dsh-review-routing-and-model-tiers.md` | NEW — workflow review waves, T0/T1 tiers, degrade rule |
| `docs/adr/0035-*.md` | Amendment — convergence v2 (Phase A/B, cap 5, `carried`) |
| `docs/adr/0036-*.md` | Amendment — batched carrier smoke + stack ownership |
| `docs/adr/0037-*.md` | Amendment — worker brief contract, semantic commit points |
| `.agents/skills/e2e-flight/SKILL.md` | Flight entry: fail-closed Step 2, workflow waves, v2 loop, batched smoke |
| `skills/e2e-engineering/impl/tdd.md` | Worker contract: complete brief, commit points, self-check, canary |
| `skills/e2e-engineering/impl/dsh-runtime.md` | DSH mapping: workflow rows, tier table, new probes |
| `skills/e2e-engineering/agents/*.md` (4 reviewer specs) | `## Digest` sections + cap-5 lines |
| `skills/e2e-engineering/schemas/*.md` (5) | `gate1SizingOverride`, ports/concurrency, cap 5, `carried` counter + review-result state enum |
| `skills/e2e-engineering/standards/api-testing.md`, `impl/verification.md` | Fixture helpers, Testcontainers fallback, playwright invocation |
| `skills/e2e-engineering/scripts/*.ps1` (13) | Mechanized slice/quality/review/stack mechanics |
| `CONTEXT.md` | Glossary truth delta |
| `dist/` | Rebuilt artifacts |

## Global Interface Names (exact — used across tasks)

`carried` (finding state) · cap `5` · `## Digest` (role checklist section) · `gate1SizingOverride` / `sizingOverrideNote` (prd.json) · stalls `unapproved-prd` / `oversized-slice` · tiers `T0` / `T1` · `CANARY-OK` · resume.json `ports` / `concurrency` blocks · scripts' params: `-TaskId -SliceId -BaseSha -Worktree -Scope -ChangedFiles -Tests -Port -HeapInit -Spec -KillSwitchMode -Shas -MigrationMap -Branch -Base -Head`.

---

### Task 0: Branch — `skill/retro-video-2026-08`

**Files:**
- Git refs only — no tracked-file edits.

**Interfaces:**
- Produces: branch `skill/retro-video-2026-08` (from clean `main`) — every later task's commit target. The Global Constraint forbids main; the branch does NOT exist yet (verified 2026-08-27: `git branch` shows only `main`, `feat/deslop-and-flow-retro`, `feat/ui-design-capability`, `skill/retro-payments-2026-08`).

- [ ] **Step 1: Verify main is clean** — `git status --porcelain` must print nothing (verified 2026-08-27). Dirty → STOP, hand off to human.
- [ ] **Step 2: Create the branch** — `git switch -c skill/retro-video-2026-08` in the main checkout. (Optional: a separate worktree via superpowers:using-git-worktrees if parallel work is needed — all task paths in this plan are repo-relative and resolve from any checkout of the branch.)
- [ ] **Step 3: Confirm** — `git branch --show-current` prints `skill/retro-video-2026-08`.

---

### Task 1: ADR 0039 — DSH review-wave routing + model tiers

**Files:**
- Create: `docs/adr/0039-dsh-review-routing-and-model-tiers.md`

**Interfaces:**
- Produces: tier names `T0`/`T1`; the workflow-wave contract consumed by Tasks 5/7; the degrade rule (workflow absent → subagent waves).

- [ ] **Step 1: Create the ADR file with this exact content**

```markdown
# DSH review-wave routing and model tiers

**Status:** accepted — refines ADR 0038 (DSH runtime profile: adds the `workflow` tool as the review/verify dispatch surface with per-agent model routing), ADR 0035 (review-wave mechanics: schema-validated pre-merged fan-in + tier routing; the convergence loop itself is amended separately — see its 2026-08-27 amendment). Amends dispatch mechanics only; gates 1/2/3/5 and the finding state machine unchanged.

A measured 2026-08 DSH flight: 67 child agents — 55 of them reviewers — against a token profile where reasoning was 8.2M (52% of model output). Two DSH facts make that spend attackable: `subagent` exposes NO model knob, while the `workflow` tool exposes a per-agent `model` override that is enforced (probe 2026-08-27: a bogus override made the child fail loudly rather than silently no-op). Review waves are bounded (≤15 calls initial / ≤8 re-review / ≤8 verifier) and their results are structured — the two properties `workflow` is built for. Impl workers are long, unbounded-turn jobs and must stay on background `subagent`.

## Context

- **Reasoning tax is per-model.** DeepSeek's reasoning dominates output cost; prompt discipline (terse JSON, reply caps) shrinks assistant/output tokens but not reasoning. Only model routing attacks the reasoning share.
- **Review waves are bounded + structured.** Initial ≤15 tool calls, re-review ≤8, verifier ≤8 (ADR 0035/0037); every wave returns `findings[]` JSON. `workflow` returns schema-validated, pre-merged results — the orchestrator's per-reviewer fan-in cost drops to near zero.
- **`workflow` is foreground + ephemeral.** The tool call blocks the orchestrator until the script finishes, and its agents cannot be continued via `send_message`. T2-style same-agent reuse is therefore incompatible with workflow-dispatched waves.
- **The stuck-reviewer protocol already exists** (ADR 0035: re-dispatch once with halved scope, then proceed with the rest). Inside a workflow script, a failed child resolves `null` — the same protocol becomes script logic.

## Decision

1. **Review/verify waves = `workflow` tool.** Initial review, re-review, and finding-verifier waves dispatch as workflow scripts: parallel `agent()` stages, per-agent `model` override, `opts.schema`-validated results returned pre-merged. Stuck-reviewer protocol lives in-script: a child failure resolves `null` → filter + record the gap in the wave `notes` (the ADR 0035 re-dispatch-once rule applies to the workflow stage before proceeding). Waves are FOREGROUND and blocking: pre-bound in prompts (≤15 initial / ≤8 re-review / ≤8 verifier), wave size 2–4 agents, schema-required returns.
2. **Tier table.** `T0` non-thinking cheap: finding-verifier slots, mechanical review slots, fan-in merge. `T1` thinking medium: judgment reviewers (backend-architect, dba, frontend-reviewer, test-reviewer initial waves). Impl workers: background `subagent`, prompt-discipline only (no model knob exists) — T1 discipline (commit-per-boundary, JSON-only manifests, evidence-pointer returns) rides the brief. **T2 reuse retired**: same-agent follow-up re-review rejected — marginal over ADR 0037's halved re-review, self-confirmation smell, incompatible with ephemeral workflow agents.
3. **Degrade, don't stall.** Step-0 probe adds workflow availability (one trivial script). Absent/failing → review/verify waves fall back to background `subagent` dispatch with prompt-discipline tiers (existing ADR 0038 mapping). Fan-out capability is essential; model routing is an optimization.
4. **Reasoning-cost claim is a hypothesis.** Expected reasoning reduction ~-50% rides on model routing; prompt-discipline-only portions reduce assistant/output tokens. `session-cost.ps1` (diagnostics) is the one-time check after the next flight vs the 8.2M/7.4M/8.5M baseline. No per-flight cost telemetry is added.

## Considered Options

- **Subagent-only review with prompt-discipline tiers** — rejected: no model knob; reasoning untouched.
- **Workflow for impl workers** — rejected: foreground blocks the orchestrator for worker-length durations.
- **T2 reviewer reuse (same agent continued via follow-up)** — rejected per decision 2.
- **Per-agent harness-settings edits** — rejected: routing is a skill policy, never user settings.

## Consequences

- Workflow wedge risk: a foreground call cannot be `job_kill`ed mid-script. Bounded by prompt budgets + 2–4-agent waves + harness workflow caps; the degrade rule (decision 3) is the escape hatch.
- Reviewer fan-in cost ≈ 0 (schema-validated pre-merged results); per-reviewer orchestrator context spend disappears.
- Tiers are unverifiable off-DSH; the Codex/Claude entries keep their existing review dispatch untouched.
- `impl/dsh-runtime.md` gains the workflow mapping + tier table + two probes (Task 7); the flight entry gains the workflow-wave Step-3.3 mechanics (Task 5).
```

- [ ] **Step 2: Self-check against the ADR house format**

Read `docs/adr/0038-dsh-runtime-adaptation.md` and confirm: Status line, Context/Decision/Considered Options/Consequences sections, amendment targets named in the Status line. Fix wording, not decisions.

- [ ] **Step 3: Commit**

```powershell
git add docs/adr/0039-dsh-review-routing-and-model-tiers.md
git commit -m "docs: ADR 0039 — DSH review-wave routing + model tiers"
```

### Task 2: Amend ADR 0035 — convergence loop v2

**Files:**
- Modify: `docs/adr/0035-review-convergence-loop-and-finding-verifier.md`

**Interfaces:**
- Consumes: none new.
- Produces: `carried` state, cap `5`, Phase A/B vocabulary — consumed by Tasks 5/8/9/12.

- [ ] **Step 1: Append this amendment section to the end of the ADR file**

```markdown
## Amendment (2026-08-27 — convergence v2)

Accepted — refines this ADR's convergence loop. Evidence: a measured 2026-08 DSH flight logged 15 bounces and TWO cap exhaustions (5/4, 5/4). Rounds are the scarce resource; spending them on newly-surfaced Minors is opportunity cost against a Critical that may surface next round.

1. **Phase A — Critical/Important-driven.** While any Critical/Important finding is `open`: bounce → the worker fixes ALL open findings in ONE pass (Minors piggyback) → re-review. Each bounce consumes one round; new findings never reset the count.
2. **Phase B — Minor-only.** When zero Critical/Important are `open`: one fix pass for all remaining Minors → ONE review (scope = the finding-owner reviewer roles + `test-reviewer`) → any Minor still open after that review → `state: carried` → `followups.json` (P3). No further Minor rounds.
3. **Cap = 5** (was 4), absolute per slice, never reset. Rationale: the Minor fix pass is now the FINAL round, so cap 5 guarantees it a slot after a full C/I loop.
4. **Edge rules.** (a) Cap exhausted in Phase A with Minors still open → carried WITHOUT their fix pass (cap is absolute). (b) A new Critical/Important surfaced during the Phase-B review → back to Phase A, count continues. (c) Un-cited Minors still drop at the hygiene gate — no carry without cite + implied action. (d) The verify wave and suppression rules are unchanged; carried Minors get no verifier spend.
5. **Merge gate.** Zero open Critical/Important; Minors resolved per rule (fixed in Phase A piggybacks or the Phase-B pass, else `carried`). `carried` joins the finding state enum: `open | fixed | dropped-refuted | open-at-cap | carried`.
6. **Supersessions.** Decision 2's "Minor is an ordinary finding; a Minor-only round is legal and costs one round" is REPLACED. The Considered-Options entry "Minors deferred" is revisited: rejected then as merging-with-known-open-findings; accepted now in the narrow Phase-B form because cap exhaustion already merges with open findings, and `carried` routes them to followups with a state, not a silent merge.
```

- [ ] **Step 2: Commit**

```powershell
git add docs/adr/0035-review-convergence-loop-and-finding-verifier.md
git commit -m "docs: ADR 0035 amendment — convergence v2 (Phase A/B, cap 5, carried)"
```

### Task 3: Amend ADR 0036 — batched carrier smoke + stack ownership

**Files:**
- Modify: `docs/adr/0036-bounded-background-jobs-evidence-hygiene-and-gate5-execution.md`

**Interfaces:**
- Produces: wave-batched smoke invariant ("no wave closes with a red smoke") — consumed by Tasks 5/11.

- [ ] **Step 1: Append this amendment section**

```markdown
## Amendment (2026-08-27 — batched carrier smoke + stack ownership)

Accepted — refines this ADR's carrier smoke. Evidence: a measured 2026-08 DSH flight rebuilt the stack ~8 times where 3 would have covered the work (stack-up 10m + package build 15m, bounded, each).

1. **Carrier smoke runs once per wave.** After the wave's merges: ONE stack-up per §4.1 Stack-up, then run EVERY spec file changed by that wave's carriers in that session (bounded, API project). Red spec → a REPAIR SLICE on the task branch (fresh worker + Gate 3) targeting the red spec's code, merged before the wave closes. Invariant: **no wave closes with a red smoke.** Detection anchor moves merge-time → wave-close; it stays pre-gate-5, which is the ADR's purpose (blind-written specs shipping stale expectations + db-cleanup bugs).
2. **Stack ownership.** The flight owns the compose stack during smoke/gate-5: `down -v → package build → up --force-recreate --build -d` runs UNCONDITIONALLY (bounded + log-to-file per ADR 0033). The flight does not probe for foreign stacks and does not ask — the entry-point doc (Task 5) carries the user-facing line: the flight tears down and rebuilds the stack; don't keep dev work in a running compose stack during a flight.
3. **§4.1 heavy-rebuild defer WARN unchanged** (smoke deferred to gate 5 when §4.1 declares the rebuild too heavy).
```

- [ ] **Step 2: Commit**

```powershell
git add docs/adr/0036-bounded-background-jobs-evidence-hygiene-and-gate5-execution.md
git commit -m "docs: ADR 0036 amendment — batched carrier smoke, stack ownership"
```

### Task 4: Amend ADR 0037 — worker brief contract

**Files:**
- Modify: `docs/adr/0037-degraded-dispatch-and-worker-contract.md`

**Interfaces:**
- Produces: semantic commit-point list, evidence-commit ban, canary step — consumed by Tasks 5/6.

- [ ] **Step 1: Append this amendment section**

```markdown
## Amendment (2026-08-27 — worker brief contract)

Accepted — refines this ADR's worker contract. Evidence: all four wedge events in a measured 2026-08 DSH flight started in worker READ phases (7–9 setup-file reads); every slice broke eslint in its new/modified files and one lint-error set MERGED before the orchestrator gate saw it.

1. **Complete inline brief — zero setup reads.** The workerBrief carries: constitution digest (~15 lines) + command-rules digest (~10 lines) + ACs + integration decision + `compileCmd` + lint digest + applicable role digests. Workers do NO skill-file reads. The empty-message bootstrap (this ADR, decision 3) is unchanged — the journaled manifest IS the brief. A rule the digests don't cover → tdd.md §1 gap-check escalation (one question), never guess.
2. **Semantic commit points replace per-commit checks.** Commit points: (1) red test (Gate 2), (2) green impl per AC, (3) refactor unit, (4) one commit per fix pass, (5) one commit per chunk (chunk-driver), (6) one commit per cherry-pick sequence (restore). `compile-check`/`lint-check` run MANDATORY at commit points, optional elsewhere; scope follows the commit's changed files (frontend-only → tsc+eslint; backend-only → compile). Decision 2 of this ADR ("self-compile before EVERY commit") is superseded by the commit-point rule. Expected ~3–6 commits per in-bounds slice. Wedge visibility = commit boundaries + the zero-commit-wave trigger (chunk-driver), not micro-commits.
3. **Evidence commits banned.** Committing `evidence/` dirs is banned — evidence joins env/config files in the "untracked only" rule. Evidence = manifest pointers + counts + ≤20-line excerpts (ADR 0036). The committed-but-unrecorded reconcile path (flight Step 2.2) now reads the branch commit log + orchestrator re-verification (compile + focused tests) instead of an in-branch evidence README.
4. **Worker canary.** The brief's first instruction: run ONE `pwsh` (`git rev-parse HEAD`) and reply `CANARY-OK`. Dead-on-arrival workers are detected in 1 round instead of 5+ silent rounds.
```

- [ ] **Step 2: Commit**

```powershell
git add docs/adr/0037-degraded-dispatch-and-worker-contract.md
git commit -m "docs: ADR 0037 amendment — worker brief contract, semantic commit points"
```

### Task 5: `.agents/skills/e2e-flight/SKILL.md` — flight entry edits

**Files:**
- Modify: `.agents/skills/e2e-flight/SKILL.md`

**Interfaces:**
- Consumes: `T0`/`T1`, cap `5`, `carried`, stalls `unapproved-prd`/`oversized-slice` (Tasks 1–2); `## Digest` sections (Task 8); scripts' names (Task 11).
- Produces: the flight-side behavior every other doc describes.

- [ ] **Step 1: Replace the Step-2 oversized-slice WARN block with the fail-closed check**

Find this exact text in Step 2:

```markdown
**Oversized-slice WARN (defense-in-depth — Gate 1 should have blocked).** Story `estimatedLoc` beyond its sliceType bound (tracer/schema/api/logic >300, ui >600, ≥10 ACs without a test-coverage slice) → WARN in `progress.txt` (`WARN oversized slice <id> — Gate 1 sizing defect, bounce risk`), still fly it, do not block; route the defect upstream via flow-retro, not the client queue. Missing `estimatedLoc` → no WARN (cannot evaluate; treat as schema drift).
```

Replace with:

```markdown
**Gate-1 fail-closed check (HARD).** `gate1Approved: false` in prd.json → `<e2e-stall reason="unapproved-prd" />` + revert queue status `ready-for-flight → needs-spec` + EXIT. Any story `estimatedLoc` missing or beyond its sliceType bound (tracer/schema/api/logic >300, ui >600) → `<e2e-stall reason="oversized-slice <id> — <sliceType> <loc>/<bound>" />` + revert to `ready-for-flight` + `progress.txt` note "flight refused: oversized slice <id> — human split required" + EXIT. Both stalls revert BEFORE exit so the front door replans. `gate1SizingOverride: true` + `sizingOverrideNote` (who/why) in prd.json = deliberate human exception → fly it, but reviewers of that slice get subsystem-scoped evidence (backend half / frontend half / spec half) per reviewer session.
```

- [ ] **Step 2: Add lint + review contract extraction to Step 2** (after the `**Compile detection (cache `compileCmd` once).**` block — ends with the `Cache `compileCmd` o…` line, immediately before `**Execution amendments (§4.1b, ADR 0036).**`)

```markdown
**Contract digests (cache once).** Read the repo's active eslint config ONCE → ≤15-line lint digest for worker briefs (no frontend eslint → skip; backend has no lint tool — ARCHITECTURE naming/ownership + constitution cover it). Extract the `## Digest` section from each applicable `$sharedSkillsRoot/agents/<role>.md` ONCE. Cache both alongside `compileCmd`; pass in every spawn manifest.
```

- [ ] **Step 3: In Step 3.2 dispatch, replace the HEAD-sha clause**

Find: `write ready-set manifest JSON (slice ids + injection payload, quoting the current `task/<id>` HEAD sha)`

Replace with: `write ready-set manifest JSON (slice ids + injection payload, quoting `git rev-parse task/<id>` RE-READ AT DISPATCH TIME — never from memory) + inline digests (lint + role `## Digest` sections) + canary first-instruction`

- [ ] **Step 4: Replace the convergence-loop block in Step 3.3**

Find, from the line `**Convergence loop (ADR 0035 — replaces the bounce cap).**` through the line `Minor is an ordinary finding. A Minor-only round is legal and costs one round.`, and replace that whole span with:

```markdown
**Convergence loop v2 (ADR 0035 amendment — replaces the bounce cap).** `open[]` = findings with `state: open`, ANY severity.
- **Phase A (C/I-driven):** while any Critical/Important is `open` → `bounce.rounds += 1` (per slice, ABSOLUTE, never reset) → worker fixes ALL open findings in ONE pass (Minors piggyback) → re-review → loop.
- **Phase B (Minor-only):** zero C/I open → one fix pass for all remaining Minors (consumes one round) → ONE review (scope = finding-owner roles + `test-reviewer`) → any Minor still open → `state: carried` → `followups.json` (P3). No further Minor rounds. New C/I surfaced by the Phase-B review → back to Phase A, count continues.
- **Cap = 5.** `bounce.rounds > 5` → cap exhausted → merge + followup (below). NEVER `blocked`. Minors open at a Phase-A cap hit → carried WITHOUT their fix pass.
- Re-review tiers unchanged (mechanical/limited → reviewers that raised open findings; logic → full wave). Halved ≤8 budget unchanged. The re-examined→`fixed` flip fires only on re-examination; carried Minors are never re-examined (they ride followups).
- **Merge gate:** zero open Critical/Important; Minors fixed or `carried`. Sole exception: cap exhaustion.
```

Also within Step 3.3 + the Red flags section — four exact instances, all verified present 2026-08-27:
- `**Cap = 4.**` (convergence block) → `**Cap = 5.**`
- `` `bounce.rounds > 4` → cap exhausted `` → `` `bounce.rounds > 5` → cap exhausted ``
- `On entering round 5:` (the `**Cap exhaustion → merge + followup (ADR 0035).**` paragraph — cap 5 exhausts on the 6th round) → `On entering round 6:`
- Red flags: `(absolute per slice, cap 4)` → `(absolute per slice, cap 5)`

- [ ] **Step 5: Add the workflow-wave dispatch rule to Step 3.3** (after the `**Reviewer prompt budget (hard).**` paragraph)

```markdown
**DSH review/verify waves route through `workflow` (ADR 0039).** Initial review, re-review, and finding-verifier waves = one workflow script each: parallel `agent()` stages with per-agent `model` override (T0 = finding-verifier/mechanical, T1 = judgment reviewers), `opts.schema`-validated results returned pre-merged. Stuck-reviewer protocol in-script: child failure → `null` → filter + record gap in `notes`. Wave size 2–4, budgets in prompts (≤15 initial / ≤8 re-review / ≤8 verifier). Workflow unavailable (Step-0 probe) → background `subagent` waves with prompt-discipline tiers — never a stall.
```

- [ ] **Step 6: Replace the Step-3.5 carrier-smoke paragraph**

Find the paragraph starting `**Carrier-level API smoke (ADR 0036).**` and replace through `…the smoke catches them at merge time.` with:

```markdown
**Wave-batched carrier API smoke (ADR 0036 amendment).** After a wave's merges, if any carrier added/changed Playwright API specs: ONE stack-up per §4.1 Stack-up + run EVERY changed spec file in that session (bounded, `--project <api>`), via `carrier-smoke.ps1 -Spec @(...)`. Red spec → REPAIR SLICE on the task branch (fresh worker + Gate 3) targeting the red spec's code, merged before the wave closes. Invariant: no wave closes with a red smoke. §4.1 declares the rebuild too heavy → WARN in `progress.txt` + defer to gate 5.
```

- [ ] **Step 7: Add the stack-ownership line to Step 5.0** — insert at the start of the `- **5.0 — HARD GATE 5 (verification-before-completion).**` bullet, before the `bring the live docker-compose stack up ONCE` sentence

```markdown
**Stack ownership.** The flight owns the compose stack during smoke/gate-5: `down -v → package build → up --force-recreate --build -d` runs unconditionally — no probe, no ask. The flight tears down and rebuilds the stack; do not keep dev work in a running compose stack during a flight.
```

- [ ] **Step 8: Gate-5 Playwright invocation** — in Step 5.0, immediately after the sentence ending `…via the §4.1 `API/integration` API-only cmd / `--project <name>` — NEVER bare `playwright test`) green`, add:

```markdown
Full API suite runs `retries=0 workers=1` with the documented isolation baseline (retry-inflated counts are noise).
```

- [ ] **Step 8b: Add the worktree-prune line (D11 — artifact hygiene)** — after the `- **5.1** → finalize on master (main tree): …` bullet (ends `…Applies whether gate 5 was fully green or had failures (failures ride to human-QA in qa-signoff.md).`), add:

```markdown
**Worktree prune (D11).** After 5.1 finalize: from the MAIN tree, `git worktree remove --force .claude/worktrees/task-<id>` — task + slice branches persist, never delete branches. DSH mode: no worktrees — skip.
```

- [ ] **Step 9: Step 6 flow-retro tally** — change BOTH instances of `bounce rounds per slice vs cap 4` (the Step 0 tally bullet 6 AND the Step 6 flow-retro writer paragraph) → `bounce rounds per slice vs cap 5`; add `carried Minors: n` to the tally list; do NOT add any cost section.

- [ ] **Step 10: Append these red-flag lines** (end of Red flags section)

```markdown
- Flying a Task with `gate1Approved: false` or an out-of-bounds `estimatedLoc` without `gate1SizingOverride` (Step 2 fail-closed — stall, never WARN-and-fly).
- Running an unbounded workflow review wave (pre-bound: 2–4 agents, budgets in prompts, schema-required returns — ADR 0039).
- Closing a wave with a red carrier smoke (repair slice resolves it first — ADR 0036 amendment).
- Hand-assigning test ports (scripts claim/release from `resume.json` `ports` — never by hand).
- Committing `evidence/` dirs on slice branches (untracked only — ADR 0037 amendment).
- Dispatching without the canary first-instruction in the worker brief.
```

- [ ] **Step 11: Commit**

```powershell
git add .agents/skills/e2e-flight/SKILL.md
git commit -m "feat(e2e-flight): fail-closed Step 2, workflow review waves, convergence v2, batched smoke"
```

### Task 6: `impl/tdd.md` — worker brief contract + commit points

**Files:**
- Modify: `skills/e2e-engineering/impl/tdd.md`

**Interfaces:**
- Consumes: commit-point list, canary, evidence ban (Task 4); `## Digest` sections (Task 8); `compile-check`/`lint-check` (Task 11).
- Produces: the worker-side contract the orchestrator briefs against.

- [ ] **Step 1: Add the recovery line to §0** — find the line ending `…disk IS the brief. Then run the sequence below with the workerBrief as the injected story.` and insert after it:

```markdown
**Post-compaction recovery:** a restarted/compacted worker resumes from its branch diff + slice status JSON + the journaled manifest — NEVER re-reads the full original brief (the brief is the context; recovery must not re-inflate it).
```

- [ ] **Step 2: Add the canary step** — insert after the §0 bootstrap (before "## Sequence"):

```markdown
## 0.5. Canary (FIRST tool call, before any briefing work)

Run ONE pwsh: `git rev-parse HEAD` in your worktree. Reply `CANARY-OK <sha>`. No other work until this reply is sent.
```

- [ ] **Step 3: Add the complete-brief block to §1** — after the gap-check bullets, add:

```markdown
**Complete brief — zero setup reads.** The workerBrief is the whole contract: constitution digest + command-rules digest + ACs + integration + compileCmd + lint digest + role digests. Do NOT open skill files (constitution.md, tdd.md, command-execution.md, api-testing.md, ARCHITECTURE slices). A rule the digests don't cover → the gap-check escalation above (one question). Never guess.
```

- [ ] **Step 4: Replace the self-compile bullet in §2** — find:

```markdown
- **Self-compile before EVERY commit** (ADR 0037) — compile-only `compileCmd`, bounded, ~1 min. Kills compile-fix round-trips (~3× fewer, waves 13b–14); the orchestrator's Step-3.4 lint+compile gate stays authoritative.
```

Replace with:

```markdown
- **Checks at SEMANTIC COMMIT POINTS** (ADR 0037 amendment). Commit ONLY at: (1) red test (Gate 2), (2) green impl per AC, (3) refactor unit, (4) one commit per fix pass, (5) one commit per chunk, (6) one commit per cherry-pick sequence (restore). At each commit point run `compile-check.ps1` + `lint-check.ps1` with scope following the commit's changed files (frontend-only → tsc+eslint; backend-only → compile). Ad-hoc compiles between points are allowed while debugging; the gate fires at points. ~3–6 commits per in-bounds slice. The orchestrator's Step-3.4 gate stays authoritative.
```

- [ ] **Step 5: Add the lint-contract line to §2** — after the RED/GREEN/REFACTOR bullets:

```markdown
- **Lint contract:** write to the injected lint digest from line one — treat it as part of the ACs. Conforming code passes the commit-point check first try.
```

- [ ] **Step 6: Add PRE-RETURN SELF-CHECK** — insert immediately before "## Return manifest (to orchestrator)":

```markdown
## 4c. Pre-return self-check (review contract)

Before returning the manifest: run each applicable role `## Digest` (injected in the brief) against your own diff. Fix violations now, or list unfixed ones as known deviations in `findings[]`. Your "done" should mean the reviewer's "clean" — only genuinely judgment-call findings survive to the review wave.
```

- [ ] **Step 7: Extend the evidence rule in the Return-manifest section** — find `**Evidence = counts + ≤20-line excerpts (ADR 0036)**` and add after that sentence:

```markdown
NEVER commit `evidence/` dirs — evidence files are untracked only, like env/config files. Evidence = manifest pointers + counts + ≤20-line excerpts.
```

- [ ] **Step 7b: Update the worker-facing convergence paragraph** — the paragraph starting `**After returning green, orchestrator runs expert-review wave**` still says `cap 4 rounds` (verified 2026-08-27). Find:

```markdown
Findings at ANY severity — Critical, Important, Minor — bounce back to YOU for fix, ALL open ones in ONE pass; then re-review (convergence loop, cap 4 rounds). At cap the slice MERGES with its residue carried to `followups.json`, never `blocked` — ADR 0035.
```

Replace with:

```markdown
Findings at ANY severity — Critical, Important, Minor — bounce back to YOU for fix, ALL open ones in ONE pass; then re-review (convergence v2, ADR 0035 amendment: Phase A while any Critical/Important is open, cap 5 absolute; Phase B one Minor fix pass + one review → survivors `state: carried` → `followups.json`, never `blocked`).
```

- [ ] **Step 8: Append red-flag lines**

```markdown
- Committing an `evidence/` dir or any log (untracked only — ADR 0037 amendment).
- Skipping the canary (first tool call must be `git rev-parse HEAD` + `CANARY-OK`).
- Committing outside a semantic commit point.
- Running a check with scope wider than the commit's changed files (never whole-repo lint — pre-existing debt is out of slice scope).
- Opening skill files instead of using the complete brief (gap-check escalation is the only exception path).
```

- [ ] **Step 9: Commit**

```powershell
git add skills/e2e-engineering/impl/tdd.md
git commit -m "feat(tdd): complete brief, semantic commit points, self-check, canary, no evidence commits"
```

### Task 7: `impl/dsh-runtime.md` — workflow mapping + probes

**Files:**
- Modify: `skills/e2e-engineering/impl/dsh-runtime.md`

**Interfaces:**
- Consumes: T0/T1 + workflow contract (Task 1).
- Produces: the mapping table rows the flight reads at Step 0.

- [ ] **Step 1: Add the workflow row to the Tool-mapping table** — after the `interrupt stuck reviewer/worker` row, add:

```markdown
| review/verify waves (initial, re-review, finding-verifier) | `workflow` tool: parallel `agent()` stages, per-agent `model` override, `opts.schema`-validated results returned pre-merged; child failure → `null` → filter + record gap in `notes` |
```

- [ ] **Step 2: Add tier table + degrade rule** — after the Budgets table, add:

```markdown
## Review/verify tiers (ADR 0039)

| Tier | Slots | Budget |
|---|---|---|
| T0 non-thinking cheap | finding-verifier, mechanical review slots, fan-in merge | verifier ≤8 calls |
| T1 thinking medium | judgment reviewers (backend-architect, dba, frontend-reviewer, test-reviewer initial waves) | ≤15 initial / ≤8 re-review |

Impl workers stay background `subagent` with prompt-discipline contracts (T1 discipline via the brief) — no model knob exists there. T2 reviewer reuse retired (ADR 0039).

**Degrade, don't stall:** workflow unavailable (Step-0 probe) or failing → review/verify waves = background `subagent` dispatch with prompt-discipline tiers. Fan-out capability is essential; model routing is an optimization.
```

- [ ] **Step 3: Add the two probes to the Step-0 probe list** — after probe 4:

```markdown
5. **Workflow-availability probe** — run a trivial workflow script (one `agent()`, one-word reply, `schema`-validated). Success → workflow review waves active (ADR 0039); failure → subagent review fallback, no stall.
6. **Concurrency budget probe** — read free RAM + CPU count via pwsh; persist `resume.json` `concurrency` cap (concurrent `subagent` dispatches + workflow parallelism). Default when unreadable: 2 workers / 4 reviewers.
```

- [ ] **Step 4: Add the wedge note to Dispatch notes** — after the `workflow` MAY-replace line, replace that line's wording with:

```markdown
- `workflow` IS the review/verify dispatch (ADR 0039): foreground + blocking — pre-bound wave size (2–4 agents) + budgets in prompts + schema-required returns. Never an unbounded workflow script.
```

- [ ] **Step 5: Commit**

```powershell
git add skills/e2e-engineering/impl/dsh-runtime.md
git commit -m "feat(dsh-runtime): workflow review waves, tier table, new probes"
```

### Task 8: Reviewer specs — `## Digest` sections + cap 5 + carried

**Files:**
- Modify: `skills/e2e-engineering/agents/backend-architect.md`, `dba.md`, `frontend-reviewer.md`, `test-reviewer.md`
- Regenerate: `.claude/agents/*.md` via `skills/e2e-engineering/scripts/generate-agent-wrappers.ps1`

**Interfaces:**
- Produces: `## Digest` sections extracted by the flight at Step 2 (Task 5) — canonical single source, never hand-duplicated.

- [ ] **Step 1: Append a `## Digest` section to each spec** — exact content per role:

backend-architect.md:

```markdown
## Digest

Resource → Service → Repository only; no Service call from a Resource-less path. Panache calls inside @WithSession services. Reactive Uni end-to-end, no blocking. Extend the named owner, never parallel classes. Validate every user-controlled path param.
```

dba.md:

```markdown
## Digest

Migrations renumbered per the task's range, never reuse reserved ranges. Never edit an already-applied migration in place (checksum). Index every WHERE/ORDER BY predicate. Entity columns match the DDL exactly.
```

test-reviewer.md:

```markdown
## Digest

Every AC maps to a REAL assertion (no fake-green, no comment-only bodies). Negative cases for every 403/404/409 branch. Real-stack Playwright for endpoints; UI is Manual only. No hardcoded sleeps. skipped=0.
```

frontend-reviewer.md:

```markdown
## Digest

DESIGN.md register + tokens. i18n hook, not hardcoded strings. aria-hidden/roles on decorative + alert content. prefers-reduced-motion. transform/opacity-only motion.
```

- [ ] **Step 2: Replace the merge-gate sentence in each spec** — all four files carry the SAME sentence (verified 2026-08-27: backend-architect L35, dba L32, frontend-reviewer L41, test-reviewer L31):

Find:

```markdown
Every surviving finding, `Minor` included, gates the merge — the slice does not merge until `open[]` is empty (cap 4 rounds, then it merges with a followup). `Minor` is no longer a free note; it costs a fix.
```

Replace the WHOLE sentence (if a file's tail wording differs, still replace the whole sentence through `costs a fix.`) with:

```markdown
Every surviving Critical/Important gates the merge — the slice does not merge until open Critical/Important is empty (cap 5 rounds — ADR 0035 amendment). Minors surviving the Phase-B review (finding-owner roles + test-reviewer) → `state: carried` → followups.json (P3) — they no longer gate the merge.
```

- [ ] **Step 3: Regenerate wrappers + verify**

```powershell
pwsh -NoProfile -File skills/e2e-engineering/scripts/generate-agent-wrappers.ps1
git status --short .claude/agents/
```

Confirm wrapper diffs are generated-only (no hand edits).

- [ ] **Step 4: Commit**

```powershell
git add skills/e2e-engineering/agents/ .claude/agents/
git commit -m "feat(agents): digest sections, cap 5, carried state"
```

### Task 9: Schemas — prd.json, resume.json, flow-retro, followups, review-result

**Files:**
- Modify: `skills/e2e-engineering/schemas/prd.json.md`, `schemas/resume.json.md`, `schemas/flow-retro.md`, `schemas/followups.json.md`, `schemas/review-result.json.md`

**Interfaces:**
- Produces: `gate1SizingOverride` / `sizingOverrideNote`, `ports` / `concurrency` blocks, cap `5`, `carried Minors` counter, `carried` in the review-result finding-state enum.

- [ ] **Step 1: prd.json.md** — find the bullet starting `- `estimatedLoc` required per story` and append after it:

```markdown
- `gate1SizingOverride` optional bool + `sizingOverrideNote` string — deliberate human exception for an out-of-bounds slice (who/why). Flight Step 2 refuses out-of-bounds slices unless this is `true`; override-approved slices get subsystem-scoped reviewer evidence.
```

- [ ] **Step 2: resume.json.md — cap** — find `"rounds": 2, "cap": 4` and replace with `"rounds": 2, "cap": 5`; add a `carried` count to the bounce object:

```json
"bounce": {
    "repair-webhook-source-ip-review-findings": { "rounds": 2, "cap": 5, "carried": 0 }
},
```

- [ ] **Step 3: resume.json.md — ports + concurrency** — after the `"stackState": "up",` line, add:

```json
"ports": { "nextFree": 8431 },
"concurrency": { "workers": 2, "reviewers": 4 },
```

And add two rules bullets after the `suppressed[]` bullet:

```markdown
- `ports.nextFree` — the port allocator ledger (conditional docker/Testcontainers projects). `run-focused-tests.ps1`/`carrier-smoke.ps1` claim a port by incrementing write-ahead and release it on exit; never hand-assign.
- `concurrency` — the Step-0 RAM/CPU probe result; caps concurrent `subagent` dispatch + workflow parallelism for this flight.
```

- [ ] **Step 4: flow-retro.md** — three exact replacements:

`- bounce rounds: <slice-id: n/4> ... (cap exhausted: <n> slices)` → `- bounce rounds: <slice-id: n/5> ... (cap exhausted: <n> slices)`

`- dropped un-cited Minors: <n>` → append after it: `- carried Minors: <n>`

`bounce rounds per slice against the cap of 4` → `bounce rounds per slice against the cap of 5 (carried Minors counted separately)`

- [ ] **Step 5: followups.json.md** — four exact edits (the file still says cap 4 — verified 2026-08-27; NOTE: `open-at-cap` does NOT appear in this file — anchor on the real text):

1. Intro line — find: `still `open` when a slice's bounce cap (4) was exhausted (ADR 0035)` → replace with: `still `open` when a slice's bounce cap (5) was exhausted, plus `carried` Phase-B survivors (ADR 0035 + its 2026-08-27 amendment)`
2. `bounceRounds` line — find: `(5 = the 4 spent rounds plus the increment that tripped the cap)` → replace with: `(6 = the 5 spent rounds plus the increment that tripped the cap)`
3. Invariants — find: `- Written ONLY at bounce-cap exhaustion. A slice whose convergence loop reached zero open findings writes nothing here.` → replace with: `- Written ONLY at bounce-cap exhaustion OR for `carried` Phase-B survivors (ADR 0035 amendment). A slice whose convergence loop reached zero open findings writes nothing here.`
4. Append after the last invariant bullet:

```markdown
- `carried` (ADR 0035 amendment): a Minor surviving the Phase-B review — enters with `suggestedPriority: 3` (Minor → 3 per the existing per-entry rule). Same lane as cap-exhaustion entries; routed by triage intake source #4 at QA sign-off; never a queue write by flight.
```

- [ ] **Step 5b: review-result.json.md** — add `carried` to the finding-state machine (verified 2026-08-27: enum on the `"state"` field line; transitions in the `state transitions (ADR 0035)` bullet):

1. Find: `"state": "open | fixed | dropped-refuted | open-at-cap",` → `"state": "open | fixed | dropped-refuted | open-at-cap | carried",`
2. Find the transitions bullet `- **`state` transitions (ADR 0035):** `open` → `fixed` (…) · `open` → `dropped-refuted` (…) · `open` → `open-at-cap` (still open when bounce round 5 was entered; carried into `followups.json`).` and replace with:

```markdown
- **`state` transitions (ADR 0035 + amendment):** `open` → `fixed` (a bounce round resolved it and the re-review no longer raises it) · `open` → `dropped-refuted` (verifier returned `refuted`, or `inconclusive` which counts as refuted) · `open` → `open-at-cap` (still open when bounce round 6 was entered — cap 5; carried into `followups.json`) · `open` → `carried` (a Minor surviving the Phase-B fix pass + review; routed to `followups.json` P3, no verifier spend, never re-examined).
```

- [ ] **Step 6: Commit**

```powershell
git add skills/e2e-engineering/schemas/
git commit -m "feat(schemas): gate1 override, ports/concurrency, cap 5, carried counter"
```

### Task 10: Standards — api-testing + verification

**Files:**
- Modify: `skills/e2e-engineering/standards/api-testing.md`, `impl/verification.md`

**Interfaces:**
- Produces: fixture-helper mandate + Testcontainers fallback (api-testing); playwright invocation standard (verification).

- [ ] **Step 1: api-testing.md — append two sections**

```markdown
## Per-domain fixture helpers

Every domain (course/lesson/asset/session…) gets seed/cleanup fixture helpers in the API-test project — never per-spec hand-seeding. Cross-spec data contamination is a measured failure class (video flight: 4 full-suite failures from every spec seeding the same rows). Each spec calls its domain's fixture; cleanup runs in `afterAll` so specs stay independent.

## Testcontainers fallback (docker-CLI-container)

Docker Desktop 29's docker-java incompatibility breaks Testcontainers. Canonical workaround: the docker-CLI-container fallback — run the container via the docker CLI and point the test config at it. Document the exact commands in ARCHITECTURE.md §4.1b when a repo hits this; the standard here is the fallback pattern, not Testcontainers-or-nothing.
```

- [ ] **Step 2: verification.md — append to the gate-5 Playwright section**

```markdown
**Playwright invocation standard:** the full API suite runs `retries=0 workers=1` with a documented isolation baseline. Retry-inflated counts are noise — the clean-verdict baseline is the green-merged-tree suite definition; anything else re-runs with the baseline before being reported.
```

- [ ] **Step 2b: verification.md — replace the carrier-smoke paragraph (D6 batched semantics)** — the `**Carrier-level API smoke (ADR 0036 — runs during flight Step 3, not only at gate 5).**` paragraph still prescribes per-merge smoke; the amendment batches it per wave (verified 2026-08-27). Find the whole paragraph:

```markdown
**Carrier-level API smoke (ADR 0036 — runs during flight Step 3, not only at gate 5).** After merging a carrier that added/changed Playwright API specs: rebuild the stack per §4.1 Stack-up and run ONLY that carrier's spec files (bounded, `--project <api>`, single-file runs). Red → fix in-slice before the next wave dispatches (Gate 3 applies). Blind-written specs shipped stale 200-vs-201 expectations + db-cleanup bugs caught only at the final gate — the smoke catches them at merge time. `ARCHITECTURE.md §4.1` declares the stack rebuild too heavy → WARN in `progress.txt` + defer to gate 5. The final gate-5 full suite is unchanged.
```

Replace with:

```markdown
**Wave-batched carrier API smoke (ADR 0036 amendment — runs at flight wave close, not only at gate 5).** After a wave's merges, if any carrier added/changed Playwright API specs: ONE stack-up per §4.1 Stack-up, then run EVERY changed spec file in that session (bounded, `--project <api>`), via `carrier-smoke.ps1 -Spec @(...)`. Red spec → REPAIR SLICE on the task branch (fresh worker + Gate 3) targeting the red spec's code, merged before the wave closes. Invariant: no wave closes with a red smoke. Blind-written specs shipped stale 200-vs-201 expectations + db-cleanup bugs caught only at the final gate — the smoke catches them before gate 5. `ARCHITECTURE.md §4.1` declares the stack rebuild too heavy → WARN in `progress.txt` + defer to gate 5. The final gate-5 full suite is unchanged.
```

- [ ] **Step 3: Commit**

```powershell
git add skills/e2e-engineering/standards/api-testing.md skills/e2e-engineering/impl/verification.md
git commit -m "feat(standards): domain fixtures, Testcontainers fallback, playwright invocation standard"
```

### Task 11: Scripts — the 13-script library

**Files:**
- Create in `skills/e2e-engineering/scripts/`: `slice-setup.ps1`, `slice-rebase-guard.ps1`, `port-commits.ps1`, `compile-check.ps1`, `lint-check.ps1`, `build-package.ps1`, `run-focused-tests.ps1`, `review-bundle.ps1`, `review-fan-in.ps1`, `carrier-smoke.ps1`, `killswitch.ps1`, `slice-merge.ps1`, `session-cost.ps1`

**Interfaces:**
- Consumes: param names from the Global Interface Names list; `resume.json` `ports`/`concurrency` (Task 9).
- Produces: JSON verdicts consumed by the flight (Task 5) + workers (Task 6). Verdict keys: `ok`, `verdict`, `counts`, `errors`, `path`.

- [ ] **Step 1: Paste this governance header at the top of EVERY script**

```powershell
# <NAME>.ps1 — e2e-flight script (D8 governance)
# BOUNDED + NON-INTERACTIVE: each child command carries its budget; no watch/serve/dev.
# LOG-TO-FILE: long producers redirect to a log file, tail read after exit — NEVER Out-String/head/tail pipe filters, NEVER named-pipe capture (DSH forbids).
# VERDICT: exit 0 + ONE JSON object on stdout { "ok": true|false, ... } — keys stable, prose values caveman-ultra, code symbols verbatim.
# NO SIDECAR WRITES: returns JSON only; the orchestrator writes state (sole writer).
$ErrorActionPreference = 'Stop'
$env:CI = '1'; $env:NO_COLOR = '1'; $env:GIT_EDITOR = 'true'; $env:GIT_TERMINAL_PROMPT = '0'
```

- [ ] **Step 2: Write the 13 scripts** — contract per script:

\`slice-setup.ps1 -TaskId -SliceId -BaseSha` — logic: (1) `git worktree add` the slice worktree from `$BaseSha`; (2) create branch `slice/$SliceId`; (3) copy the cached env/config files + `heap.init.gradle` from the task worktree (untracked); (4) echo `{"ok":true,"worktree":"<path>","branch":"slice/$SliceId"}`. Replaces: orchestrator's 5 manual pwsh calls per slice.

\`slice-rebase-guard.ps1 -TaskId -SliceId` — logic: (1) `git merge-base --is-ancestor` check of `task/$TaskId` HEAD vs the slice branch base; (2) stale → `git rebase task/$TaskId` in the slice worktree; (3) emit `{"ok":<bool>,"rebased":<bool>,"changedFiles":[...]}` + exit 1 on conflict. Replaces: orchestrator hand-checking diffs for D-deletions (3 stale-base hits this flight).

\`port-commits.ps1 -Shas @(...) -MigrationMap @{V20='V33'} -Branch` — logic: (1) `GIT_EDITOR=true`; (2) cherry-pick each sha in order; (3) apply migration renames per `$MigrationMap` (`git mv` old→new inside the cherry-picked tree); (4) stop at first conflict, print the conflicting file, exit 1. Conflict RESOLUTION stays agent-side. Replaces: worker's mechanical cherry-pick/rename sequence. Restore-only.

\`compile-check.ps1 -Worktree -Scope backend|frontend|both` — logic: backend → `.\gradlew.bat :backend:compileJava :backend:compileTestJava --no-daemon` (bounded 6m, log to file); frontend → `npx --yes tsc -b` (bounded 6m). Emit `{"ok":true,"verdict":"BUILD SUCCESSFUL"}` or `{"ok":false,"verdict":"BUILD FAILED","errors":[first 5]}`. Replaces: worker ad-hoc self-compile + orchestrator per-slice compile gate — the SAME script both sides.

\`lint-check.ps1 -Worktree -ChangedFiles <list>` — logic: `npx --yes eslint <changed/new files only>` (bounded 3m, log to file); never whole-repo (pre-existing debt out of scope). Emit `{"ok":<bool>,"problems":<n>,"files":[per-file counts]}`. Replaces: the late Step-3.4 eslint bounce; wired into the worker commit loop.

\`build-package.ps1 -Worktree` — logic: `.\gradlew.bat :backend:quarkusBuild --no-daemon` (bounded 15m, log to file). Emit `{"ok":<bool>,"verdict":"BUILD SUCCESSFUL|FAILED"}`. Replaces: repeated manual package builds in carrier-smoke/gate-5. OUT of the per-slice worker loop (stack-owned).

\`run-focused-tests.ps1 -Tests @(...) -Port -HeapInit` — logic: (1) claim a port from `resume.json` `ports.nextFree` (write-ahead increment) when `-Port` empty; (2) run the bounded gradle/vitest focused run (12m, log to file, `-HeapInit` init script when given); (3) release the port; (4) read test-result XML ONLY after `BUILD SUCCESSFUL` in the log; emit `{"ok":<bool>,"verdict":"...","counts":{"tests":n,"failures":n,"errors":n,"skipped":n}}`. Replaces: worker/orchestrator log-reading + verdict reading (stale-XML discipline becomes code).

\`review-bundle.ps1 -SliceId -Base -Head` — logic: `git diff --name-status $Base..$Head` + `git diff --stat` + testEvidence skeleton JSON → `{"ok":true,"bundle":{...}}`. Replaces: orchestrator hand-building mechanical bundle fields.

\`review-fan-in.ps1` — logic: read the slice's reviewer result JSONs, merge `findings[]` into `review-result.json` (mechanical merge, reviewerId-tagged). Emits the merged object. Replaces: orchestrator fan-in context spend.

\`carrier-smoke.ps1 -Spec @(...) -KillSwitchMode on|off` — logic: (1) `docker compose down -v`; (2) `build-package.ps1`; (3) `docker compose up --force-recreate --build -d`; (4) bounded readiness poll; (5) run each `-Spec` file (`--project <api>`, bounded, log to file); (6) teardown. KillSwitchMode off → temp compose override applied in (3). Emit `{"ok":<bool>,"specs":{"<file>":"green|red"}}`. ONE stack-up per wave (D6). Replaces: ~15 hand-run smoke sequences.

\`killswitch.ps1 on|off` — logic: write/remove the temp compose override file + backend restart (bounded). Emit `{"ok":true,"mode":"on|off"}`. Replaces: hand-written override + restart.

\`slice-merge.ps1 -SliceId -TaskId` — logic: (1) `git merge slice/$SliceId --no-edit` in the task worktree; (2) clean-tree verify (`git status --porcelain` empty). Emit `{"ok":<bool>,"conflicts":[files]}`. Replaces: orchestrator manual merge+verify (sidecar writing stays orchestrator).

\`session-cost.ps1` (diagnostics) — logic: zstd frame-split decode of `~/.dsh/sessions`, tally per-agent reasoning/output/tool-result tokens + compaction counts; emit `{"sessions":n,"agents":[{...tallies}]}`. NOT wired into flight steps (D12 removal) — run manually after a flight for the one-time baseline comparison (8.2M/7.4M/8.5M).

- [ ] **Step 3: Smoke-test one script end-to-end** — run `slice-merge.ps1` against a scratch branch in a temp clone; confirm the JSON verdict + exit codes behave. Fix, then re-run.

- [ ] **Step 4: Commit**

```powershell
git add skills/e2e-engineering/scripts/
git commit -m "feat(scripts): 13-script library under governance rule"
```

### Task 12: `CONTEXT.md` — glossary truth delta

**Files:**
- Modify: `CONTEXT.md`

**Interfaces:**
- Consumes: every name produced by Tasks 1–9.
- Produces: the glossary entries future grills check against.

- [ ] **Step 1: Delta block** — after the ADR 0038 bullet (the line ending `…artifact-driven, non-busy waits, goal tools).`), add:

```markdown
> - **ADR 0039 — DSH review routing + tiers.** Review/verify waves route through the `workflow` tool (per-agent model override, schema-validated pre-merged fan-in, stuck-reviewer protocol in-script); T0 = non-thinking cheap slots (finding-verifier, mechanical), T1 = judgment reviewers; impl workers stay background `subagent` (prompt discipline — no model knob); T2 reuse retired; workflow absent → subagent fallback, never a stall.
> - **ADR 0035 amendment — convergence v2.** Phase A: bounce while any Critical/Important open (Minors piggyback, all open findings fixed per pass). Phase B: one Minor fix pass + one review (finding owners + test-reviewer) → survivors `state: carried` → followups P3. Cap 5 (was 4), absolute. Merge gate = zero open Critical/Important.
> - **ADR 0036 amendment — batched carrier smoke + stack ownership.** ONE stack-up per wave, every changed spec in that session; red → repair slice; no wave closes red. The flight owns the compose stack — `down -v → build → up` unconditional, no probe, no ask.
> - **ADR 0037 amendment — worker brief contract.** Complete inline brief (digests + ACs + compileCmd) — zero skill-file reads; checks at SEMANTIC COMMIT POINTS only (scope follows changed files); evidence commits banned; worker canary (`CANARY-OK`).
> - **Flight Step 2 fail-closed.** `gate1Approved:false` → stall `unapproved-prd` + revert `needs-spec`; out-of-bounds `estimatedLoc` → stall `oversized-slice` + revert `ready-for-flight`; `gate1SizingOverride` = deliberate human exception (subsystem-scoped reviewer evidence).
```

- [ ] **Step 2: Glossary entries** — append to the Language section:

```markdown
**Routing tier** _[ADR 0039]_: per-agent model tier for DSH review/verify waves. `T0` = non-thinking cheap (finding-verifier, mechanical slots, fan-in); `T1` = thinking medium (judgment reviewers). Impl workers carry T1 discipline via the brief (no model knob on `subagent`). `T2` (same-agent re-review reuse) is RETIRED.
_Avoid_: editing harness settings to route models — routing is a skill policy.

**carried** _[ADR 0035 amendment]_: finding state for a Minor that survived the Phase-B fix pass + review. Routes to `followups.json` (P3), never re-examined, no verifier spend. Joins `open | fixed | dropped-refuted | open-at-cap`.

**unapproved-prd / oversized-slice stalls** _[2026-08-27]_: flight Step 2 fail-closed stalls. `unapproved-prd`: `gate1Approved:false` → queue reverts `needs-spec`. `oversized-slice`: story `estimatedLoc` missing/out-of-bounds → queue reverts `ready-for-flight` + human split note. `gate1SizingOverride` is the only bypass.

**Stack ownership** _[ADR 0036 amendment]_: the flight owns the compose stack during smoke/gate-5 — `down -v → package build → up --force-recreate --build -d` runs unconditionally. No probe, no ask; the flight tears down and rebuilds. Keep dev work out of the compose stack during a flight.

**Worker brief** _[ADR 0037 amendment]_: the complete inline worker contract — constitution digest + command-rules digest + ACs + integration + compileCmd + lint digest + role digests. Zero skill-file reads; the journaled ready-set manifest IS the brief (empty-message bootstrap unchanged).

**Semantic commit point** _[ADR 0037 amendment]_: the commit boundaries a worker may use — red test, green-AC, refactor, fix pass, chunk, cherry-pick sequence. `compile-check`/`lint-check` run MANDATORY at points (scope follows changed files), optional elsewhere.

**Digest** _[ADR 0037 amendment]_: the canonical ≤15-line checklist section (`## Digest`) inside each `agents/<role>.md` reviewer spec. The flight extracts them at Step 2 for worker briefs + pre-return self-check — single source of truth, never hand-duplicated.
```

- [ ] **Step 3: Update the `Review convergence loop` entry** — find the existing entry and replace its body with:

```markdown
**Review convergence loop**: Per-slice loop replacing the old bounce ceiling (ADR 0035; v2 amendment 2026-08-27). [[Expert-review wave]] → [[finding-verifier]] → Phase A: bounce while any Critical/Important open (worker fixes ALL open findings per pass, Minors piggyback) → Phase B: one Minor fix pass + one review (finding owners + test-reviewer) → survivors `carried` → [[Followup record]]. Cap 5 rounds, absolute per slice, never reset; merge gate = zero open Critical/Important. Verify-once + suppression unchanged.
```

- [ ] **Step 4: Commit**

```powershell
git add CONTEXT.md
git commit -m "docs: CONTEXT delta for ADR 0039 + amendments"
```

### Task 13: Build + validate + finalize

**Files:**
- Regenerate: `dist/` via `npm run build`

- [ ] **Step 1: Build** — `npm run build` (raw, no rtk — compile-class producer)
- [ ] **Step 2: Validate** — `npm run validate`; fix every error (broken links, stale dist, deprecated roles, JSON validity) and re-run until exit 0.
- [ ] **Step 3: Commit**

```powershell
git add dist/
git commit -m "chore: rebuild dist for flight-retro skill updates"
```

### Task 14: Verification report

- [ ] **Step 1: Re-read the plan checklist** — confirm every step verified with fresh output (superpowers:verification-before-completion).
- [ ] **Step 2: Report** — files changed in this repo, validate output, next-flight readiness. Note the one-time `session-cost.ps1` check to run after the next DSH flight (vs 8.2M/7.4M/8.5M baseline).

## Self-Review

- [ ] **Spec coverage:** D1→G1/T5; D2→T1/T5/T7; D3→T2/T5/T6/T8/T9; D4→T5/T9; D5→T4/T6; D6→T3/T5/T10/T11; D7→T3/T5; D8→T11; D9→T4/T5/T6/T8; D10→T4/T6/T11; D11→T4/T5/T6/T11 (prune line = T5 Step 8b; TC-file rename verified already-satisfied 2026-08-27 — `Run UI e2e` has 0 grep hits repo-wide and qa-signoff.md already says Manual walk); D12→T5/T7/T9/T10/T11. Superseded retro lines NOT re-implemented: §1 T2 reuse; §6 carry-at-round≥3; §6 Step-0 stack probe; §7 budget/CHECKPOINT mechanism; §7 to-issues enforcement; §5 "strip at record"; §6 per-flight cost baseline auto-append.
- [ ] **Placeholder scan:** every doc-edit step carries exact old→new or verbatim append content; every script step carries params + logic + verdict schema. No TBD/TODO.
- [ ] **Type consistency:** cap `5` in Tasks 2/5/6/8/9/12 (incl. followups `(4)→(5)` + bounceRounds `(5→6)` + review-result transitions `round 6`); `carried` spelled identically in Tasks 2/5/6/8/9/12 + review-result enum; digest section name `## Digest` in Tasks 5/8; stall names `unapproved-prd`/`oversized-slice` in Tasks 5/9/12; verdict keys `ok/verdict/counts/errors/path` in Task 11; T0/T1 in Tasks 1/5/7/12.
- [ ] **Anchor verification (2026-08-27):** every find-anchor in Tasks 1–14 checked against the live tree — all old→new anchors in Tasks 5/6/8/9/10/12 exist verbatim EXCEPT the ones this v2 fixes (compileCmd-cache wording, reviewer-prompt-budget heading, `open-at-cap` in followups.json.md). New-file tasks verified absent (ADR 0039, the 13 scripts). Task 0 added: branch `skill/retro-video-2026-08` does not exist yet.
- [ ] **Scope (grilled 2026-08-27):** self-contained skill improvement — UniVerse sync task REMOVED (verification report is now Task 14), no client repos/boards/installs; plan + v1 evidence anonymized to `measured 2026-08 DSH flight`; skill docs left as historical record (schema examples untouched).

## Execution Handoff

Start at Task 0 (create `skill/retro-video-2026-08`) — Tasks 1–14 all commit there, never main. Two execution options:

1. **Subagent-Driven (recommended)** — fresh subagent per task + two-stage review between tasks (REQUIRED SUB-SKILL: superpowers:subagent-driven-development).
2. **Inline Execution** — execute tasks in this session via superpowers:executing-plans, batch execution with checkpoints.

Either way: cross-file consistency (cap 5, `carried`, `## Digest`, stall names, verdict keys) is cheapest held by ONE context — the subagent-driven split should hand each worker the Global Interface Names list above, not just their task. Task 11 is the only isolated chunk; delegate per-script but hold the governance header + resume.json wiring in the executing context.
