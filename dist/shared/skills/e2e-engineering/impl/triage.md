# triage — 5-state intake (external work + walled candidates only)

5-state intake machine. Forward flow to-issues output born `ready-for-agent`, SKIPS triage. Gates only EXTERNALLY-sourced work (bug reports, feature requests from outside) and WALLED refactor candidates from map-codebase §5. Preserves "never AFK un-triaged issue" where it matters.

## States
```
needs-triage → needs-info → ready-for-agent
                          → ready-for-human
                          → won't-fix
```
- **needs-triage** — just arrived, unassessed.
- **needs-info** — under-specified; ask for missing detail, re-triage.
- **ready-for-agent** — clear enough to become Task / slice. (to-issues output starts here directly.)
- **ready-for-human** — needs human decision/action agent can't make.
- **won't-fix** — out of scope / rejected, with reason.

## What feeds triage
1. External bug reports / feature requests.
2. Refactor candidates from [map-codebase](../pre-impl/map-codebase.md) §5 — each becomes NEW issue, human-gated into own refactor Task. NEVER auto-actioned.
3. **QA findings** from multi-Task [human-qa](../post-impl/human-qa.md) sign-off session — each becomes NEW [Task queue](../schemas/queue.json.md) entry (`status:needs-spec`, unselected — no PRD yet, ADR 0029): bug → bugfix Task with `parentTask=<built task id>` (built Task stays `done`, not reopened); new idea → feature Task. Closes QA→queue loop (ADR 0018).
4. **Flight followups** from `tasks/<id>/followups.json` ([schema](../schemas/followups.json.md)) — expert-review findings still open when a slice exhausted its 5 bounce rounds (ADR 0035). Each becomes a NEW [Task queue](../schemas/queue.json.md) entry (`status:needs-spec`, unselected) with `parentTask=<built task id>` and priority from each entry's own `suggestedPriority` (`Critical` → 1, `Important`/`Minor` → 3; a file may hold a mix). Surfaced to the human via `qa-signoff.md` `## Followups` / `## Release Blockers`. Flight never creates the entry itself — ADR 0017 writer table.

## Red flags (stop)
- Sending forward-flow to-issues slices through triage (they skip it).
- Auto-promoting refactor candidate to work without human gating.
- Leaving external issue in needs-triage indefinitely (rule: never AFK un-triaged issue).
- Closing a QA sign-off while `followups.json` still has un-routed entries (they are the only record — flight cannot queue them itself).
