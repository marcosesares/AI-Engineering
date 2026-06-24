# queue.json — schema (Task queue)

Lives at `.e2e-engineering/queue.json`. Cross-Task ordering layer ABOVE per-Task `prd.json`. See ADR 0017, CONTEXT.md "Task queue".

```
{ tasks: [{
    id,                                # kebab-case; also the tasks/<id>/ dir name
    title,
    priority,                          # integer, lower = sooner (P1 most urgent)
    dependsOn: [ids],                  # CROSS-TASK DAG (camelCase). Distinct from story-level
                                       #   depends_on (snake_case, within one prd.json).
    status: needs-spec|ready-for-flight|in-progress|pending-qa|done|blocked,
    selected: true|false,              # in THIS flight batch (Run selection)
    parentTask: id|null                # set when Task born from QA finding
}] }
```

**Task status ≠ story status.** This is the cross-Task QUEUE status. Per-`prd.json` STORY status is a separate enum (`todo|in-progress|done|blocked`, schema [prd.json](prd.json.md)) — do not conflate. See ADR 0029.

`needs-spec` vs `ready-for-flight`:
- **`needs-spec`** — Task is a queued idea/title with NO approved `tasks/<id>/prd.json` yet. Born here from triage / QA findings (ADR 0018). Front-door routes it into pre-impl spec.
- **`ready-for-flight`** — PRD approved (gate-1 passed), awaiting `/e2e-flight`. Forward-flow Tasks are born here (queued AT gate-1). Only `ready-for-flight` Tasks are launchable.

## Invariants
- **Single in-progress**: at most ONE Task `status:in-progress` at a time. Flight drains Tasks serially; parallelism inside Task only (story fan-out/fan-in).
- **`<e2e-complete>`** fires when no `selected:true` Task is `needs-spec`, `ready-for-flight`, or `in-progress` (all selected are pending-qa / done / blocked).
- **dependsOn closure**: selecting Task auto-includes unmet `dependsOn` Tasks (batch never internally inconsistent).
- **Status mirrors `prd.json` (prd.json is source of truth — ADR 0029).** `ready-for-flight` ⟺ an approved `tasks/<id>/prd.json` exists; `needs-spec` ⟺ none. Front-door + flight RECONCILE at read: `ready-for-flight` with no prd.json → demote to `needs-spec` (warn); status is a label over the artifact, never overrides it.

## Writers (disjoint fields, never concurrent — ADR 0017)
- **/e2e-engineering** (interactive) CREATES entries: forward-flow at gate 1 born `ready-for-flight`; triage / QA-finding Tasks born `needs-spec`. Sets `priority`, `dependsOn`, `selected`, `parentTask`. Flips `needs-spec → ready-for-flight` when a spec lands at gate 1, and `pending-qa → done` at QA sign-off session.
- **/e2e-flight** FLIPS `status` only (ready-for-flight → in-progress → pending-qa / blocked). One Task per spawn, no driver loop (ADR 0022). Never sets `done`.
- Never run at same time: interactive session fully exits before flight runs.

## Status lifecycle
```
needs-spec ──(PRD approved @ gate 1)──> ready-for-flight ──(flight picks)──> in-progress ──(impl+review)──> pending-qa
(triage / QA-finding born here)                                                  │                               │
                                                                                 └──(3-strike fail)──> blocked    └──(QA session approve)──> done
```
`pending-qa`: flight ran all automatable steps; human sign-off deferred (ADR 0018). `done` = human-approved at QA gate.

## Selection ordering
Flight picks next = `selected:true` AND `status:ready-for-flight` AND all `dependsOn` in {done, pending-qa}, lowest `priority` number first.
