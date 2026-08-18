# e2e-loop — ralph-pure external drain loop (design)

> **⚠️ PARKED — NOT the current design.** Superseded for now by [ADR 0022](../../docs/adr/0022-flight-one-task-per-spawn-no-loop-no-checkpoint.md) + [e2e-flight-process/design.md](../e2e-flight-process/design.md), which chose **one Task per spawn + forced in-session fan-out** (no external loop) over this slice-per-spawn ralph loop. Kept for a possible future revisit. Do NOT implement from this doc.

**Status:** Parked (future revisit)
**Date:** 2026-05-31
**Supersedes:** the loop logic currently embedded in `e2e-flight/SKILL.md` + the Task-granularity drain in `scripts/afk.ps1`.

Source ideas: local `prototype/ralph_skill` (stateless agent + file persistence), `frankbria/ralph-claude-code` (timeout, circuit breaker, 5-hour cap handling), `michaelshimeles/ralphy` (worktree-per-agent parallelism, AI conflict merge). Motivation: the flight token blowup recorded in ADR 0022 — one Task ran 126 tool calls inline across 227 turns → 22.3M cache-read tokens (O(N²) in turn count, ~58% of the flight). The session-local incident report was not retained in-repo; ADR 0022 carries the figures.

---

## Principle

Three parts, strictly separated:

1. **Dumb external loop** (the driver, `afk.ps1`/`afk.sh`) — owns iteration. Re-spawns a fresh agent until a terminal signal. Never parses the DAG, never does work. Holds no model context.
2. **Stateless fine-grained worker** (one `/e2e-flight` spawn) — does exactly **ONE slice**, commits, emits a signal, exits. Fresh context every spawn.
3. **File state** — the only thing that survives a spawn. The driver and worker communicate through files + one stdout signal line.

This is the ralph recipe. The intelligence is in the slice decomposition (the DAG) and the file state, **not** in any long-lived conversation. Context cannot grow because no process lives longer than one slice.

### Why this kills the token blowup

The old design's loop unit was a whole **Task** (a full feature impl loop) and it relied on **in-session subagent fan-out** to stay lean. That fan-out was soft markdown + deferred tools (`EnterWorktree`/`Agent` need `ToolSearch` to load) → it never fired headless → everything ran inline → 227-turn O(N²) chain.

Ralph-pure removes the dependency entirely: **the fan-out IS the external loop.** One slice per fresh process. No subagent dispatch to forget. Trades O(N²)-in-turns for O(N)-in-slices. The per-spawn re-bootstrap floor (~13K cache-read) is noise next to 22M.

---

## The contract (driver ⇄ worker)

### State files

| File | Owner (writer) | Purpose |
|---|---|---|
| `.e2e-engineering/queue.json` | front-door `/e2e-engineering` creates; worker flips `status` | Task queue: id, priority, dependsOn, status, selected |
| `.e2e-engineering/tasks/<id>/prd.json` | worker (sole writer per Task) | story DAG: per-story `depends_on`, `status`, acceptanceCriteria, testCases |
| `.e2e-engineering/tasks/<id>/progress.txt` | worker (append-only) | learnings + `## Story Log` + `## Pending Amendments` |
| `.e2e-engineering/tasks/<id>/handoff-*.md` | worker | checkpoint resume payload (caveman:ultra) |
| `.e2e-engineering/flight.lock` | driver | PID; single-driver guard |
| `.e2e-engineering/flight.log` | driver | console mirror |
| `.e2e-engineering/flight-status.md` | worker | at-a-glance current Task→slice→gate for the human |

### Signals (worker stdout → driver acts) — last line of the spawn

| Signal | When | Driver action |
|---|---|---|
| `<e2e-slice-done id="<task>" story="<sid>" next="<sid\|none>" />` | one slice merged, more slices remain in this Task | respawn (same Task) |
| `<e2e-task-done id="<task>" next="<task\|none>" />` | Task → pending-qa (all its slices done + gates 4/5 + review) | respawn (next Task) |
| `<e2e-checkpoint handoff="..." reason="timeout\|threshold\|gate-N" />` | spawn hit a brake mid-slice, slice unfinished | respawn (resume same slice/Task) |
| `<e2e-complete stories="N" />` | no selected Task todo/in-progress left | stop, success |
| `<e2e-stall reason="..." />` | no ready work / all blocked / needs human | stop, alert human |

Exactly ONE terminal signal per spawn, as the last output line. **New vs today:** `<e2e-slice-done>` is added — the unit shrinks from Task to slice.

---

## Worker arc (one spawn = one slice)

No loop inside the worker. It runs once and exits.

```
1. Bootstrap: read queue.json → pick Task (in-progress, else next selectable).
2. Read tasks/<id>/{prd.json, progress.txt, handoff-*.md if resuming}.
3. Reconcile: any story marked in-flight with no commit → reset to todo.
4. Compute ready set (depends_on all done AND status todo). Pick ONE slice.
   - none ready, none in-flight, all done → run gate-4/5/review path OR emit <e2e-task-done>/<e2e-complete>.
5. Run the slice: gap-check → red → green → refactor → slice feature-e2e.
6. Self-review the slice (acceptanceCriteria EXACT + constitution + ARCHITECTURE slice).
7. Green + self-review clean?
   - YES → commit, set story status:done in prd.json, append ## Story Log + stage ## Pending Amendments.
   - NO (after gate-3 escalation) → git restore (discard uncommitted), mark story blocked, log it.
8. Emit signal (<e2e-slice-done> / <e2e-task-done> / <e2e-complete> / <e2e-stall>) and EXIT.
```

**Sequential mode (default): no git worktree.** One slice at a time on the Task branch; commit straight to it. `git restore` on failure keeps the branch clean for the next spawn. This also removes the worktree-leak bug and the deferred-tool trap (no `EnterWorktree`/`Agent` to load).

**Gates 4/5 + post-impl review** are their own spawns (fresh context), as today — triggered when no story remains ready/todo.

---

## Driver responsibilities + brakes

The driver stays dumb but gains real token brakes (from frankbria):

1. **Single-driver lock** — `flight.lock` (PID). Refuse a second. *(have it)*
2. **Console mirror + status file** — `flight.log`, `flight-status.md`. *(have it)*
3. **Max-sessions ceiling** — hard cap on total spawns. *(have it: `MaxSessions`)*
4. **Per-spawn wall-clock timeout** — kill a spawn exceeding N minutes (frankbria default 15), treat as `<e2e-checkpoint reason="timeout">`, respawn-resume. **NEW** — the direct brake on a 23-min/227-turn runaway.
5. **Circuit breaker — no-commit-in-N** — if N consecutive spawns produce no new commit / no prd.json status change → stop + alert. **NEW** — generalizes today's `MaxStuckCheckpoints` (which only counts checkpoints, not stalled-but-emitting spawns). Detect: no-progress, repeated identical error.
6. **5-hour usage-window detect + auto-wait** — recognize the account rolling-cap message, auto-wait to reset instead of burning spawns into the cap. **NEW** — the report's three stacked sessions tripped the cap blindly.

Driver never reads the DAG, never decides the next slice — the worker does, from files. Keeps the loop dumb (ralph principle: dumb loop, smart files).

---

## Improvements over baseline

| vs current `afk.ps1` + e2e-flight | vs vanilla ralph |
|---|---|
| Unit Task → **slice** (the O(N²) fix) | adds a real **DAG** (`depends_on`) + gates, not a flat story list |
| Removes in-session fan-out reliance | keeps stateless-agent + append-log + commit-if-green |
| Adds per-spawn **timeout** | adds **DAG-ordered** ready-set selection |
| `MaxStuckCheckpoints` → **no-commit circuit breaker** | adds gate-4/5 + fresh-context review as separate spawns |
| Adds **5-hr cap** detect/wait | sequential-first; parallel later (ralphy worktree+branch+AI-merge) |
| `<e2e-slice-done>` signal added | |

---

## Phasing

- **Now — sequential, no worktree.** One slice/spawn on the Task branch. Simplest; already removes O(N²) and the worktree leak.
- **Later — parallel (ralphy).** Driver spawns N ready slices into isolated worktree+branch each, auto-merges back with AI conflict resolution. Faster wall-clock; re-introduces worktree management + merge-conflict token cost. Opt-in flag.

---

## Open questions (resolve before build)

1. Exact per-spawn timeout value (frankbria 15 min — tune to slice size).
2. Circuit-breaker N (frankbria 3 no-progress / 5 same-error).
3. Where gate-4/5/review trigger lives in the worker bootstrap decision tree (step 4 branch).
4. 5-hr cap detection: structural JSON vs text-match on the CLI output (frankbria uses three-layer).
