# human-qa — Manual test script + amendment approval (single chokepoint)

The single human-approval chokepoint of the whole flow. In ONE touch the human (1) walks the Manual test-case script and signs off QA, AND (2) approves/drops the batched constitution amendments. Provenance: mattpocock + qa dispositions.

## Two modes
- **Single-Task** (no `queue.json`): run the steps below once for the current task.
- **Multi-Task QA sign-off session** (flight drained a [Task queue](../schemas/queue.json.md)): /e2e-flight deferred human-QA per Task, leaving each at `status:pending-qa` with a [qa-signoff.md](../schemas/qa-signoff.md). Walk ALL `pending-qa` Tasks here in ONE pass (priority order). For each Task, open its `tasks/<id>/qa-signoff.md` and run the steps below; then flip queue `status: pending-qa → done`. See ADR 0018.

## Session setup
- Read state in parallel when possible: `queue.json`, every pending Task's `qa-signoff.md`, each Task's `progress.txt`, and each Task's [`flow-retro.md`](../schemas/flow-retro.md) (ADR 0027).
- If `qa-signoff.md` only lists TC ids/titles, open referenced `test-cases/*.md` and inline Preconditions, Steps, Expected. Do not ask human to open files.
- If `qa-signoff.md` and `progress.txt` disagree on Pending Amendments, show union and label source.
- Do not run implementation capability probe, worker spawn, or `/e2e-flight` from QA mode.

## What to do (per Task)
1. **Manual script** — present every Manual test-case body, in order, once. Include title, Preconditions, numbered Steps, and Expected. Preserve concrete endpoints/statuses/badges/messages. Do NOT collapse to titles. Do NOT omit network checks, restore steps, role checks, or status assertions. The human walks them and records pass/fail.
2. **Pending Amendments** — present the `## Pending Amendments` staged in progress.txt (durable learnings extracted across the task, incl. architecture drift subagents proposed mid-loop). For each, the human routes it: **promote → [constitution](../constitution.md)** if generic (bump version + changelog), **promote → ARCHITECTURE.md** if project-specific structure/ownership/naming/convention, or **drop**. (This is the one human-write phase for ARCHITECTURE.md besides pre-impl seeding.)
3. **Gate 5 Failures → repair Tasks** — if `## Gate 5 Failures` section is present and non-empty, route each entry through [triage](../impl/triage.md) into a new repair Task (`parentTask=<this id>`, `status:needs-spec`, unselected). Human decides: real regression → bugfix Task; flaky/pre-existing → can drop. The built Task STILL goes `done` — Gate 5 failures are new scope, not a reason to reopen (ADR 0025).
4. **Findings → issues** — log any QA finding in the Task's qa-signoff.md `## Findings`, then route each through [triage](../impl/triage.md) into a NEW queue Task: a **bug** → linked bugfix Task (`parentTask=<this id>`, `status:needs-spec`, unselected) — the built Task STILL goes `done`, not reopened (it passed automated gates; the bug is new scope); a **new idea** → feature Task (`status:needs-spec`, unselected). Findings re-enter the queue for a future flight (ADR 0018).
5. **Skill-improvement candidates → UPSTREAM (third lane, ADR 0027)** — present the Task's [flow-retro.md](../schemas/flow-retro.md) `## Skill-improvement candidates`. These are e2e-engineering **TOOL-defect** signal, NOT project work. The human copies each upstream to the e2e-engineering maintainer repo (issue/ADR). Do NOT route them into the client queue (that's lane 4) and do NOT promote them to constitution/ARCHITECTURE.md (that's lane 2) — keep the three lanes distinct. No auto-transport (read-only install). §Local retro is informational; surface only blockers worth the human's attention.
6. Record QA sign-off (set qa-signoff.md `Status: APPROVED`, queue `status: done`).

## User prompt shape
Print one compact QA handoff, then wait.

Required shape:
- Header: `QA Sign-off Session — <task-id>` (or task count for multiple).
- One-line state: `Task is pending-qa. <N> manual test cases to walk + <M> pending amendments to route.`
- `Manual Test Cases`: full scripts. Use `TC-<n>: <title>` headings. No duplicate TC ids.
- `Gate 5 Failures` (only if section non-empty): list each failure, ask human to route each to repair Task or drop.
- `Pending Amendment Decisions`: bullet each amendment with proposed target (`constitution`, `ARCHITECTURE.md`, or `drop?`) when inferable.
- `Skill-improvement (upstream)` (only if `flow-retro.md` §Skill-improvement is non-empty): bullet each candidate; ask the human to forward it to the e2e-engineering repo (not a client Task).
- Final ask: `Report pass/fail per TC, Gate 5 failure routing, any findings, promote/drop per amendment, and which skill-improvement candidates to forward upstream.`

Do not approve, reject, edit `queue.json`, edit `qa-signoff.md`, or promote amendments until human gives results.

## Why batched here (not task-by-task)
Pattern promotion is batched at this gate so the human never approves patterns one-task-at-a-time. progress.txt stays per-task scratch and resets on the next task; durable learnings survive only if promoted to the constitution here.

## Task close
- QA signed off + amendments resolved (promoted or dropped) → task DONE.
- progress.txt resets when the NEXT task begins (append-only only WITHIN a task).

## Red flags (stop)
- Auto-promoting amendments without human approval (wrong rule then injected into every future subagent — true for constitution AND ARCHITECTURE.md).
- Approving QA per-slice/per-task instead of at this single chokepoint.
- Carrying Pending Amendments forward unresolved.
- Routing Skill-improvement candidates into the client queue or the constitution — they go UPSTREAM to the e2e-engineering repo (third lane, ADR 0027); keep the three lanes distinct.
