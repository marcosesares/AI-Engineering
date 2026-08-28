# Degraded dispatch modes and the worker contract

**Status:** accepted — refines ADR 0022 (fan-out mechanics: adds a first-class degraded mode that keeps fan-out fired when full-brief workers stall), ADR 0034 (journal-before-dispatch: makes worker self-briefing from disk possible), ADR 0035 (convergence loop: halves the re-review budget without touching tiers or the cap). Amends dispatch + worker/reviewer mechanics only; gates 1/2/3/5 unchanged.

Full-brief TDD workers stalled at zero commits in the payments drain: write-capable subagents in that runtime complete ~1 tool call per round, so a worker brief asking for a whole slice's red-green cycle never finished a single wave. The drain recovered with two mechanics this ADR ratifies: small chunks with orchestrator-run tests (waves 11–16, every slice completed), and worker self-compile before every commit (~3× fewer compile-fix round-trips). Two more contract gaps surfaced in the same drain: runtimes that deliver spawn/followup messages EMPTY (workers idled asking "what task"), and full re-reads on bounce re-reviews when a scoped re-read of the fix would do.

## Context

- **Worker throughput is runtime-dependent and can be ~1 tool call/round.** A worker that must run tests to complete stalls; a worker that only writes one narrow chunk + compiles completes. The skill had one dispatch mode (full-brief TDD) and one forbidden fallback (inline slice work) — nothing in between.
- **Compile-fix round-trips are expensive.** Waves 13b–14: allowing workers to self-compile (compile-only, ~40–60s) before committing cut compile-fix round-trips ~3×; the orchestrator's compile gate caught what slipped through.
- **Empty payload drops are real.** Some runtimes deliver spawn/followup messages EMPTY (turn triggers, content lost). The drain's workers learned to self-brief from disk instead of idle-asking — the orchestrator journals the ready-set manifest BEFORE spawning (ADR 0034), so disk is the brief.
- **Re-review rounds re-read everything.** The convergence loop (ADR 0035) re-dispatches reviewers after every bounce; the drain found halved-scope re-reviews (budget ≤12 → ≤8) catch the same regressions at a fraction of the spend.

## Decision

1. **Chunk-driver degrade mode (first-class).** Trigger: an impl wave returns zero commits/manifests after its budget — workers alive but stalled. Action: halve the slice into small chunks (≤1 file, one AC each); the worker writes ONE chunk + self-compiles; the orchestrator runs the focused tests per chunk and feeds the verdict back. **Gate 2 holds in degraded mode:** chunk 1 is the failing test (orchestrator confirms RED), the impl chunk follows (orchestrator confirms GREEN) — the test-first order is preserved, the runner moves. The review wave is unchanged (still per slice, after the last chunk, ADR 0035). Degrade is recorded in `progress.txt` + the retro counter. Inline slice work stays forbidden — chunk-driver is fan-out with a smaller unit, not a license to inline.
2. **Worker self-compile default.** Every worker self-compiles (compile-only `compileCmd`, bounded) BEFORE every commit. Cheap (~1 min), kills compile-fix round-trips; the orchestrator's pre-merge lint+compile gate (Step 3.4) remains the authoritative check.
3. **Empty-message bootstrap (worker contract).** A worker whose spawn/followup message arrives EMPTY must NOT idle-ask: read `impl/tdd.md` §0 and self-brief from disk — the Task's `resume.json` `dispatched[]` entry whose slice slug contains the worker's task-name slug (else the sole entry), then that entry's `manifestPath` → `workerBrief` → worktree/branch. No matching entry → return `status: blocked` with a `type:blocker` finding, never guess. Disk is the brief because the orchestrator journals before dispatch (ADR 0034). The Codex flight entry carries a SPAWNED-SUBAGENT GATE pointing workers here before any orchestrator step.
4. **Halved re-review budget.** Initial review rounds keep the ≤15 tool-call budget. Re-review rounds (after a bounce) carry ≤8 tool calls and scope = the open findings + the fix diff — never a full re-read. A finding the re-reviewer could not re-examine within budget stays `open` (ADR 0035's re-examined→`fixed` flip only fires on re-examination), so the loop still converges by the cap.

## Considered Options

- **An upfront worker-throughput probe at Step 0** (spawn a probe worker, measure rounds per tool call) — rejected for now: the stall signal (zero commits after a wave budget) is cheaper to observe and only fires when the mode is actually needed; a probe burns a spawn on every flight.
- **Full-brief dispatch with a smaller tool budget instead of chunking** — rejected: the stall was round-throughput, not tool count; a worker that completes one tool call per round cannot run tests at all, whatever the budget.
- **Letting workers run the full test suite in degraded mode** — rejected: that is the stall the mode exists to avoid; the orchestrator runs focused tests, the worker writes.
- **Keeping re-review at full budget to guarantee every finding gets re-examined** — rejected: the drain's halved re-reviews caught the same regressions; the ≤8 scope is the fix diff plus open findings, which is exactly what a re-review must read.
- **An orchestrator-side empty-payload detector instead of worker self-briefing** — rejected: the orchestrator cannot observe what the worker received; the worker can, and the journaled manifest gives it everything the payload would have carried.

## Consequences

- Degraded-mode slices cost more orchestrator rounds (one test run per chunk) but complete; the alternative measured in the drain was zero commits and a stalled Task. The mode is opt-in by observation, so full-brief TDD stays the default on runtimes with fast workers.
- The empty-message bootstrap makes worker dispatch resilient to payload drops without any orchestrator change — it reuses the ADR 0034 journal, which is already committed before every spawn.
- Reviewer spend per bounce drops (≤8 vs ≤15); the worst case is a finding left `open` to the cap, which already merges with a followup (ADR 0035) — no new exit path.
- `impl/tdd.md` gains §0 (empty-message bootstrap), the self-compile rule, and the chunk-driver worker contract; the four reviewer specs gain the re-review budget line; the Codex flight entry gains the SPAWNED-SUBAGENT GATE; the Claude entry gains the chunk-driver degrade for its serial dispatch.

## Amendment (2026-08-27 — worker brief contract)

Accepted — refines this ADR's worker contract. Evidence: all four wedge events in a measured 2026-08 DSH flight started in worker READ phases (7–9 setup-file reads); every slice broke eslint in its new/modified files and one lint-error set MERGED before the orchestrator gate saw it.

1. **Complete inline brief — zero setup reads.** The workerBrief carries: constitution digest (~15 lines) + command-rules digest (~10 lines) + ACs + integration decision + `compileCmd` + lint digest + applicable role digests. Workers do NO skill-file reads. The empty-message bootstrap (this ADR, decision 3) is unchanged — the journaled manifest IS the brief. A rule the digests don't cover → tdd.md §1 gap-check escalation (one question), never guess.
2. **Semantic commit points replace per-commit checks.** Commit points: (1) red test (Gate 2), (2) green impl per AC, (3) refactor unit, (4) one commit per fix pass, (5) one commit per chunk (chunk-driver), (6) one commit per cherry-pick sequence (restore). `compile-check`/`lint-check` run MANDATORY at commit points, optional elsewhere; scope follows the commit's changed files (frontend-only → tsc+eslint; backend-only → compile). Decision 2 of this ADR ("self-compile before EVERY commit") is superseded by the commit-point rule. Expected ~3–6 commits per in-bounds slice. Wedge visibility = commit boundaries + the zero-commit-wave trigger (chunk-driver), not micro-commits.
3. **Evidence commits banned.** Committing `evidence/` dirs is banned — evidence joins env/config files in the "untracked only" rule. Evidence = manifest pointers + counts + ≤20-line excerpts (ADR 0036). The committed-but-unrecorded reconcile path (flight Step 2.2) now reads the branch commit log + orchestrator re-verification (compile + focused tests) instead of an in-branch evidence README.
4. **Worker canary.** The brief's first instruction: run ONE `pwsh` (`git rev-parse HEAD`) and reply `CANARY-OK`. Dead-on-arrival workers are detected in 1 round instead of 5+ silent rounds.
