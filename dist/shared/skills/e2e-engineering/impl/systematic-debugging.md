# systematic-debugging — 4-phase root-cause (gate 3 re-dispatch)

Invoked by orchestrator ONCE when slice sub-agent reports 3 failed fix attempts (HARD GATE 3). Replaces blind retries with disciplined root-cause analysis.

## 4 phases
1. **Reproduce** — get reliable, minimal repro. Flaky → make deterministic first. No fixing what can't reproduce.
2. **Isolate** — bisect. Narrow to smallest failing unit: which layer, which input, which commit. Form ONE hypothesis at a time, test it.
3. **Root cause** — explain WHY it fails, not just where. State causal chain. Fix without root cause = guess.
4. **Fix + verify** — minimal fix at root (constitution: surgical). Re-run failing test AND surrounding suite — confirm no regression. Diagnosable assertions (testing principle 2).

## Outcome → orchestrator
- **Fixed** → return summary; orchestrator resumes normal fan-in.
- **Still red after single re-dispatch** → orchestrator marks story `blocked` in prd.json, appends `## Blocked` (id | why | 4-phase diagnosis) to progress.txt, keeps draining ready set.
- Escalate to HUMAN only on **stall**: no ready work remains, or every remaining story depends on blocked one.

## Re-dispatch contract (H)
A re-dispatch MUST change at least one variable — repro strategy, environment, or scope — from the failed attempt. Sending the same brief unchanged is a blind retry, and blinds the root cause. The changed variable goes IN the brief so the follow-up worker starts from the delta, not from scratch.

## Red flags (stop)
- More than one re-dispatch per story (ONCE — then `blocked`).
- Fixing without reproduction.
- Changing multiple variables at once (can't attribute fix).
- Silently deferring block to human-QA (E2E gate could deadlock — mark `blocked` now, escalate on stall).
- Re-dispatching with the same brief unchanged (H — change ≥1 variable: repro strategy/env/scope, and write it into the brief).
