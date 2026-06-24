# qa-signoff.md — schema (per-Task human-QA checklist)

Lives at `.e2e-engineering/tasks/<id>/qa-signoff.md`. Written by [/e2e-flight](../../e2e-flight/SKILL.md) when deferring human-QA (ADR 0018). Audit record; `queue.json` holds actionable state. Cleared in [QA sign-off session](../post-impl/human-qa.md) (multi-Task pass).

```markdown
# QA Sign-off: <task-id>
Status: PENDING            # PENDING | APPROVED | REJECTED

## Manual test cases (walk these)
### TC-03: <journey name>
Preconditions: <env/data/login state>
1. <action> → expect <observable result>
2. <action> → expect <observable result>
3. <restore/reset step when needed> → expect <baseline restored>

### TC-07: <journey name>
Preconditions: <env/data/login state>
1. <action> → expect <observable result>

## PRD acceptance criteria (auto-verified — confirm visually)
- [x] AC-1 <criterion>     # gate-5 self-review: covered by automated unit/API test
- [ ] AC-4 <criterion>     # UI — needs human eyes (Manual walk; not automated, Fork Y)

## Pending amendments (promote / drop)
- constitution: <generic learning from progress.txt>
- ARCHITECTURE.md: <project-specific structure/ownership/naming change>

## Gate 5 Failures (-> triage -> repair Tasks)
- (written by FLIGHT when gate 5 suite was red or an AC was unmapped — ADR 0025)
  - test: <test name/file> — <failure reason>  -> human routes to new repair Task at QA sign-off
  - ac:   <AC-id> <criterion>                  -> human routes to new repair Task at QA sign-off
- (empty section when gate 5 was fully green)

## Findings (-> triage -> new queue Tasks)
- (filled DURING QA session by human)
  - bug:  <desc>   -> new bugfix Task (parentTask=<this id>); this Task still goes done
  - idea: <desc>   -> new feature Task (status:needs-spec, unselected)

## Decision
- [ ] Approve -> queue status: done
- [ ] Reject  -> reason: ___
```

## Sections: flight fills vs human fills
- **Flight fills** (headless): full Manual test-case scripts (from prd.json testCases disposition Manual — **all UI cases are Manual, Fork Y/ADR 0024**, incl. Preconditions, Steps, Expected), AC list with gate-5-auto-verified (unit/API-covered) ticked, pending amendments staged from progress.txt, Gate 5 Failures if any (ADR 0025).
- **Human fills** (QA session): walks Manual cases, eyeballs visual ACs, decides each amendment, routes Gate 5 Failures through triage into repair Tasks, logs Findings, records Decision.

## Manual case rules
- Write full script bodies, not ids/titles only.
- Preserve concrete endpoints, status codes, UI labels, role names, blocked/allowed assertions, and cleanup/restore steps.
- One TC id once. No duplicate cases.

## Why deferred + batched
Human-QA cannot run headless. Flight runs all automatable steps (gate 5: full unit+API suite green + AC-vs-code, review), parks human judgment here — **UI walk is the human's job (no UI automation, Fork Y/ADR 0024)** — sets Task `pending-qa`, continues to next Task. All checklists cleared in one batched session — mirrors pattern-promotion batching (ADR 0014 lineage). See ADR 0018, ADR 0024.
