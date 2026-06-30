# Emit a `WAITING:` signal at every human chokepoint

**Status:** accepted. Touches ADR 0019 (grill-with-docs), ADR 0028 (front-door menu), ADR 0029 (queue states).

## Problem

Every time `/e2e-engineering` STOPs for human input — Gate 1 PRD approval, the route fork, bucket selection, batch/launch, the run-selection checkbox, and each grilling question — the agent fell silent. From the human's side a STOP and a long-running computation look identical: no output either way. There was no way to tell "agent is working" from "agent is waiting for me."

This is the #1 cause of wall-time waste. Observed in one session (`extract-upload-validation-helper`): a Gate-1 question was asked at 9:21 AM and the next activity was at 12:39 PM — ~3h of dead time at a single chokepoint. The human confirmed: *"I didn't notice you were waiting, indeed I asked if you were stuck."* All measured gaps correlated with human-question chokepoints.

## Decision

1. **Every STOP/WAIT chokepoint MUST emit a visible signal as its final line.** Format:

   ```
   WAITING: <action needed> — <task/context>
   ```

   Plain text, one marker per STOP, always the last line so it is unmistakable in a terminal.

2. **Convention is defined once, applied at each site.** A *Waiting signal* block near the top of both `e2e-engineering/SKILL.md` entry points (`.claude` + `.agents`) states the rule and rationale; each STOP carries the concrete wording inline so the agent does not have to compose it.

3. **Covered chokepoints** (every interactive STOP in the human-driven flow):
   - Gate 1 — PRD approval → `WAITING: approve or reject PRD for <id>`
   - Route fork (Step 0) → `WAITING: pick (1) new task or (2) existing queue`
   - Bucket selection (Step 0) → `WAITING: select Task(s) to work — <bucket>`
   - Batch-or-launch (On-consent step 3) → `WAITING: spec another feature, or launch flight?`
   - Run-selection checkbox (On-consent step 3) → `WAITING: check which ready Task(s) to drain this flight`
   - grill-with-docs per question → `WAITING: answer to continue grilling (Q<n>)`

4. **Scope = human-driven flow only.** `/e2e-flight` is headless (no human chokepoints), so it is untouched. `<e2e-stall .../>` markers already signal the one place flight surfaces to a human and stay as-is.

## Considered Options

- **Signal only the three sites named in the bug report** (Gate 1, batch/launch + checkbox, grill) — rejected: the route fork and bucket selection are the same silent-STOP bug and would still strand the human at the queue menu. Cover all chokepoints.
- **A harness hook / Stop-notification instead of in-prompt text** — out of scope here: portable across the dual runtime (Claude + Codex) and any harness, the in-flow marker needs no settings. A desktop/push hook can layer on top later but does not replace the visible line.
- **Free-form "let me know" phrasing** — rejected: not greppable, easy to drop. A fixed `WAITING:` prefix is scannable by the human and by any future tooling.

## Consequences

- **Both runtimes touched:** `.claude` + `.agents` `e2e-engineering/SKILL.md` (convention block + six STOP sites); shared `skills/e2e-engineering/pre-impl/grill-with-docs.md` (per-question marker). `dist/` regenerated.
- The human can now distinguish working from waiting at a glance; silent multi-hour stalls at chokepoints are designed out.
- New interactive STOPs added in future MUST carry a `WAITING:` marker — the convention block is the standing rule.
