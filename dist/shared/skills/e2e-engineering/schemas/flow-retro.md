# Schema — flow-retro.md

Per-Task PROCESS-friction record (ADR 0027). Written by `/e2e-flight` at Step 6 (sole-writer, beside `qa-signoff.md`), at `tasks/<id>/flow-retro.md`. **caveman:ultra.** The SKILL-facing feedback channel — distinct from `progress.txt` (project learnings) and `qa-signoff.md` (human QA checklist). Two sections, two audiences.

## Template
```markdown
# Flow Retro — <task-id>

## Local retro (this team)
- bounces: <n> (mechanical: <n>, limited: <n>, logic: <n>)
- blocked slices: <n> — <slice-id: cause> ...
- gate-5 failures: <n>
- stalls: <n> — <reason> ...
- fan-out fired: <n> waves (impl: <n>, review: <n>)
- rejected un-evidenced Criticals: <n>
- notes: <one-line friction the team should know>

## Skill-improvement candidates (UPSTREAM → e2e-engineering repo)
- <smell>: <what the TOOL did wrong + where the flow felt it> — <suggested fix/ADR>
- ...
```

## Sections
1. **§Local retro** — metrics for the team running the flow. Counters flight accumulates during the spawn: bounce count (by tier), blocked slices + cause (gate-3 exhaustion), [[Gate 5 failure]] count, stalls + reason, fan-out wave count (impl + review), rejected un-evidenced Criticals. Operational, stays in the client project.
2. **§Skill-improvement candidates** — friction that looks like an e2e-engineering **tool defect** (not project work). Each is a [[Skill-improvement candidate]] tagged for upstream. Empty section is fine (write `- none`).

## Invariants
- **Sole writer = `/e2e-flight`** (Step 6). Flight observes all the signal during the spawn; the retro aggregates it. Never written by sub-agents.
- **Separate from `qa-signoff.md`** — keeps tool-facing signal out of the project QA doc (ADR 0027). Do NOT fold §Skill-improvement into qa-signoff.md.
- **Three distinct lanes at QA sign-off** — §Skill-improvement candidates → upstream (NOT a client Task); distinct from Pending Amendments (→ constitution/ARCHITECTURE.md) and [[QA finding]]s (→ triage → new client Task).
- **No auto-transport.** Skill installs read-only; lane-3 items are human-forwarded to the maintainer repo. The artifact only makes the signal explicit + well-formed.
