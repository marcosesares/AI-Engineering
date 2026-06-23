# Per-flow learning report (flow-retro.md) — dual-section, third QA routing lane

**Status:** accepted.

The skill captures two kinds of end-of-flow learning today: **Pending Amendments** (durable project standards → `constitution`/`ARCHITECTURE.md`) and **QA findings** (project work → `triage` → new queue Tasks). Both improve the **project**. Nothing captures **process friction to improve the skill itself**.

## Problem

Signal about how the flow *ran* — bounce counts, blocked slices, Gate 5 failures, stalls, fan-out events, rejected un-evidenced Criticals — is scattered across `progress.txt` and `qa-signoff.md` and then lost (`progress.txt` resets per Task). There is no aggregation and no channel for tool-level feedback.

Compounding it: the skill installs **read-only into client projects**, separate from the maintainer repo. Friction noticed in a client that looks like a *tool defect* has no path back upstream — and it must not be confused with project-facing amendments or QA findings.

## Decision

1. **New per-Task artifact `tasks/<id>/flow-retro.md`**, written by `/e2e-flight` at Step 6 (sole-writer, beside `qa-signoff.md`), caveman:ultra. Flight already observes all the signal during the spawn; the retro aggregates it.
2. **Dual-section:**
   - **§Local retro** — process metrics for the team running the flow: bounce count (incl. mechanical), blocked slices + cause, Gate 5 failure count, stalls, fan-out fired count, rejected un-evidenced Criticals.
   - **§Skill-improvement candidates** — friction that looks like an e2e-engineering **tool defect**, tagged for upstream.
3. **The QA sign-off session gains a THIRD routing lane.** Per Task the human now routes: (1) Pending Amendments → `constitution`/`ARCHITECTURE.md`; (2) QA findings → `triage` → new client Task; (3) §Skill-improvement candidates → copied **upstream** to the e2e-engineering maintainer repo (issue/ADR). Lane 3 is explicitly **not** a client Task.
4. **No auto-transport.** Read-only install means lane 3 is human-forwarded; the skill makes the signal explicit and well-formatted, nothing more.
5. **Separate artifact, not a section in `qa-signoff.md`** — keeps tool-facing signal out of the project QA document, preserving the project/tool boundary that motivates the feature.

## Considered Options

- **Fold a §Skill-improvement section into `qa-signoff.md`** — rejected: mixes tool feedback into the project QA doc, blurring the boundary.
- **Aggregate-only at sign-off (no per-Task artifact)** — rejected: the friction data (fan-out events, rejected Criticals) is not all in `progress.txt` today, so flight must log it somewhere regardless; this only defers the artifact.
- **Local-retro-only** — rejected: drops the stated "improve the skill" goal.
- **Upstream-feedback-only** — rejected: strands the signal unless forwarded and gives the running team no operational value. The dual-section serves both audiences and matches the read-only-install reality.

## Consequences

- Flight Step 6 writes a second artifact and must instrument friction counters during the spawn (bounces, blocks, Gate 5, stalls, fan-out, rejected Criticals).
- `human-qa.md` and the QA sign-off session gain a third routing lane; `qa-signoff.md` is unchanged (boundary preserved).
- New schema: `flow-retro.md`.
- CONTEXT.md updated: new terms `Flow retrospective`, `Skill-improvement candidate`; `QA sign-off session` updated to name the three lanes.
- Upstream transport stays manual; a future enhancement could template lane-3 items as ready-to-file maintainer issues.
