# Crash-safe flight state — write-ahead journal, dirty-tree commit rule, gate-5 checkpoints

**Status:** accepted — refines ADR 0022 ("resume via state files") and ADR 0033 (bounded-shell contract); supersedes nothing.

The flight orchestration dies at arbitrary instants: account quota aborts (3+ recorded on payments-monetization), hung shells, stuck reviewers. Every death left the repo in a state that cost a reconcile pass to reconstruct — worker commits without manifests, orchestrator edits stranded uncommitted (2026-08-20 incident: the orchestrator's final postmortem/skill edits sat uncommitted after session death), gate 5 abandoned mid-stack. ADR 0022 removed context checkpoints; the sanctioned resume mechanism is on-disk state files (`queue.json`/`prd.json`/`progress.txt`). Those files are written AFTER the fact — nothing is written BEFORE a risky action, so death mid-action forces reconstruction from memory. This ADR closes that gap.

## Context

- **2026-08-19 wave-5 quota aborts (×2):** dispatch briefs were written to `briefs/wave-5/` before dispatch. Both aborts cost nothing — the briefs re-sent verbatim. The third dispatch died mid-wave after workers committed; reconcile (postmortem path B) recovered it. Lesson: brief-first dispatch works; commit-before-dispatch makes it durable.
- **2026-08-20 stranded-orchestrator-output:** the session died after applying its final edits; the whole work product (postmortem + skill contract) sat uncommitted until a recovery session committed it. No skill rule covered "task branch dirty at entry".
- **Gate-5 span:** stack-up 10 min + suite 30 min + Playwright 20 min = the single longest wall-clock window in the flight, with the least state durability — a mid-suite death re-runs everything and can leave the stack up.
- **Reviewer hang (2026-08-19):** one stuck reviewer stalled a whole wave; fixed per-skill (budget + halved-scope re-dispatch), but a quota abort DURING the review wave still strands its state.

## Decision

1. **`resume.json` — machine-readable resume pointers at the task root.** Schema in `skills/e2e-engineering/schemas/resume.json.md`. Fields: `headSha`, `phase` (dispatch|review|merge|gate5), `readySet[]`, `worktrees[]`, `stackState`, `teardownOwed`, `gate5Strikes`. Sole writer = orchestrator. Written **write-ahead** — BEFORE each phase transition and before every long-running gate step — and updated after completion. `progress.txt` stays the append-only narrative; `resume.json` is the fast resume path, read at Step 2 before anything else. NOT a handoff doc and NOT a context checkpoint (ADR 0022 bans those): no narrative, no context transfer — structured pointers only, same class as `queue.json`/`prd.json`.
2. **Dirty-tree commit rule.** The working tree must be clean at every step boundary — never cross a dispatch, merge, or gate with uncommitted changes. Task branch dirty at entry (Step 2.2) → it is the prior orchestrator's stranded output: commit it as `state: record <unit>` before doing anything else. Never stash, never `git reset`, never discard — the work exists; recording it is cheaper than re-deriving it (2026-08-20 incident).
3. **Journal-before-dispatch.** The ready-set manifest (slice ids + injection payload) is written AND committed with a `progress.txt` dispatch-intent line BEFORE any agent spawn. Death mid-dispatch leaves a verbatim-replayable brief on disk (wave-5 precedent). Re-dispatch = re-send the committed manifest; the only field to refresh is the task-branch HEAD sha it quotes.
4. **Quota-containment batching.** When account/session quota headroom is unknown or a prior wave aborted on quota, dispatch impl waves in batches of ≤2 with one committed manifest per batch — loss is bounded to the in-flight batch. Parallel ready-set dispatch remains the default; batching is the degraded mode, not a fallback to inline work.
5. **Gate-5 checkpoints.** Before stack-up, before the full suite, and before the Playwright gate, the orchestrator records the phase in `resume.json` (write-ahead). Long steps run detached to a log file with bounded polling. Resume after death reads the checkpoint and re-runs only unfinished phases; `teardownOwed` forces teardown first, so the stack never stays orphaned.
6. **Step-0 preflight script.** `skills/e2e-engineering/scripts/flight-preflight.ps1` automates the ADR 0033 probe + non-interactive env block + stale-daemon guard (`./gradlew --stop` allowed ONLY at Step 0 with zero parallel java processes). FAIL → `<e2e-stall reason="preflight-failed" />`; never a blind dispatch. POSIX-without-pwsh runs the same checks inline (ADR 0033 already specifies the probe).
7. **Filter exception encoded in the shipped AGENTS.md rtk block.** "Always prefix with rtk" gains an explicit carve-out: filters/proxies apply to OUTPUT READS only; never wrap long-running/compile/test commands (gradlew/tsc/vitest/playwright/compose). Removes the contradiction that produced the `rtk proxy gradlew` trap.

## Considered Options

- **Auto-commit hook / git pre-commit guard** — rejected: cannot distinguish flight artifacts from user work, and hooks can't bound shell commands.
- **External watchdog process polling `progress.txt` mtime** — parked: violates the no-driver spirit of ADR 0022/0023; revisit only if write-ahead journaling proves insufficient.
- **One slice per spawn (ADR 0022 parked option)** — still parked: caps context structurally but discards in-worktree parallelism; journaling addresses the same risk cheaper.

## Consequences

- Every phase transition costs one extra artifact write + commit. Token cost is negligible (JSON pointers); the commit is the resume point.
- `resume.json` stale on resume is SAFE by construction: it is only ever written write-ahead, so a stale value can only cause an already-completed step to be re-verified — never skipped unsafely.
- CONTEXT.md gains `resume.json` and `preflight` glossary entries; AGENTS.md rtk block gains the filter exception.
