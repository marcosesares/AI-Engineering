# Flight runs one Task per spawn — no external loop, no context monitoring, fan-out enforced

**Status:** accepted — supersedes the loop/checkpoint parts of ADR 0002, ADR 0014, ADR 0015; refines ADR 0005, ADR 0006, ADR 0016.

`/e2e-flight` does the implementation work for exactly **one Task** then exits; there is no external ralph driver loop and no 65% / gate-boundary context monitoring inside the skill. Within the spawn flight is the orchestrator and **fans out each slice to a sub-agent in its own worktree** (impl wave) plus a second **expert-review wave** before merge. Because the token blowup (one Task = 227 turns / 22.3M cache-read; the session-local incident report was never retained in-repo — the figures here and in §Context are the record) was caused by fan-out silently **not firing** and running 126 calls inline, fan-out is now **forced**: the worker `ToolSearch`-loads `Agent` + `EnterWorktree` at bootstrap, and the orchestrator doing slice-impl inline is a hard red-flag STOP (`<stall>` + exit).

## Context

The previous design (ADR 0015) put an external AFK driver loop around the skill and relied on in-session subagent fan-out (ADR 0006) plus 65%/gate-boundary checkpoints (ADR 0002, 0014) to keep the orchestrator chain lean. In practice the fan-out never fired headless — `Task` calls = 0 — so a single Task ran its whole 126-tool-call implementation inline across 227 turns, growing cache-read ~quadratically (22.3M tokens, ~58% of the flight). The checkpoints did not save it; the loop only made it easy to stack three sessions into the account 5-hour cap.

## Decision

1. **One Task per spawn.** `/e2e-flight` implements one Task and exits. No external ralph loop; re-invoke to take the next Task. Drops the AFK driver, respawn signals (`<e2e-checkpoint>` etc.), `flight.lock`/`flight.log`, and the `E2E_DRIVER` guard.
2. **No in-skill context monitoring.** No 65% net, no unconditional gate reset, no handoff/checkpoint/respawn. A Task completes in one spawn or is left resumable via `prd.json`/`queue.json` status.
3. **Fan-out kept and forced.** Flight IS the orchestrator. It loads the dispatch tools at bootstrap and dispatches every slice to a sub-agent + worktree. Doing slice-impl inline = hard STOP. This is the actual token fix — sub-agents hold the heavy tool calls and return summaries, so the orchestrator chain stays small without any checkpoint.
4. **Expert-review wave.** After a slice goes green, role-prompted reviewer sub-agents (UI designer / backend architect / DBA / senior QA, chosen by `sliceType`) review in the worktree before merge; Critical/Important findings bounce back (cap 3). Replaces the orchestrator's manual quality-check stage with fresh specialist eyes. lint + compile are orchestrator commands, not agents.
5. **Gates 4 & 5 stubbed, not deleted.** E2E journey automation is a placeholder (`TODO`); step 4.1 still authors the e2e TC docs. Interim verification net = gate 2 + gate 3 + expert review + lint/compile + self-review + human-QA checklist. Gates 4/5 slot back in when automation lands.
6. **Token hygiene.** Prose artifacts (`progress.txt`, qa-signoff, TC docs) written caveman:ultra; reads use offset/limit; `progress.txt` is the single append-only record (status-headed entries; tail = current state); `flight-status.md` dropped.

## Considered Options

- **Keep the external loop + make fan-out reliable, keep checkpoints** — rejected: the checkpoints added complexity without preventing the blowup, and the loop's value (Task-to-Task drain) is recoverable by simple re-invocation.
- **Ralph-pure: one SLICE per spawn, no in-session fan-out** (see `prototype/e2e-loop/design.md`) — parked, not chosen now. Structurally caps context but discards the in-worktree parallelism + the orchestrator's cross-slice view the team wants. Revisitable later.

## Consequences

- With loop + checkpoint + driver-brake all gone, the **only** thing preventing another runaway is fan-out firing + the inline-impl STOP. The forcing mechanism is load-bearing; if `Agent`/`EnterWorktree` cannot be loaded, the worker must stall+exit, never grind inline. **(Amended — ADR 0033.)** That brake proved incomplete: it watches turn count, not wall-clock, so a shell command that never returns is a runaway it cannot see (observed on OpenCode/DeepSeek — a foreground compile/stack-up command hung the spawn indefinitely). ADR 0033 adds the second brake: a Step-0 bounded-shell probe (fail-closed `<e2e-stall reason="unbounded-shell" />`) plus a bounded/non-interactive/self-terminating contract on every command flight or a worker runs.
- Verification rigor is temporarily lower (gates 4/5 stubbed) — the human-QA checklist is the real net until E2E automation lands.
- Glossary churn: `Checkpoint`, `Unconditional gate reset`, `Phase transition`, `AFK wrapper`, `Loop driver`, `E2E_DRIVER guard` are removed/deprecated; `Fan-out`, `Sole writer`, `Hard gate` reshaped. CONTEXT.md + AGENTS.md updated alongside.

---

## Amendment — branch model + task lock (2026-06-04)

**Root cause:** `course-validation-error-messages` flight used git stash to swap between master and task branch for artifact commits; stash-pop landed on wrong branch, requiring manual re-apply.

**Decision:** Orchestrator works on `task/<id>` branch throughout flight. Master receives exactly two targeted `queue.json` commits at clean boundaries:

1. `todo→in-progress` before branching (Step 1 — task lock). Pre-condition: master must be clean — uncommitted changes → `<e2e-stall reason="master-dirty">` + EXIT.
2. `in-progress→pending-qa` after Step 5.1 self-review pass (working tree clean at this point; no stash needed).

No stash, no mid-flight master commits, no arbitrary branch switching. Sub-agents work in isolated worktrees off the task branch.

**Considered:** committing all artifacts to task branch only (master never updated until QA merge) — rejected because next flight reads master's `queue.json` and needs to see `in-progress` as the task lock to avoid double-pick.
