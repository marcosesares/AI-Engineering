# Resume-queue entry — /e2e-engineering launches existing PRD-approved Tasks without a fresh spec

**Status:** accepted.

`/e2e-engineering` is the interactive front door. Its Step 0 router had three terminal branches — `adopt`, `qa`/pending-qa, and "Otherwise → per-feature flow (spec a new feature)". The launch machinery (Run-selection checkbox → invoke `/e2e-flight`) lived ONLY at the tail of the per-feature flow, behind a fresh spec + Gate 1 approval.

## Problem

A user re-runs `/e2e-engineering` against a populated queue: N `status:todo` Tasks, several with an approved `tasks/<id>/prd.json` (gate-1 already passed), **none `in-progress`, none `pending-qa`, none `selected`**. This is the normal "come back and launch what I already specced" case.

The router has no branch for it:

- Step 0 — not `adopt`, not `qa`, no `pending-qa` → falls to *"Otherwise → per-feature flow (spec a new feature)"*.
- Step 1.1 — "`prd.json` for an **in-progress** Task?" → none in-progress → **No → start Pre-implementation from top**.

So the script instructs a brand-new feature spec, ignoring the approved Tasks waiting to launch. The model correctly refuses to blind-start a new spec, improvises a state listing ("13 queued, 5 ready for /e2e-flight, reply with task IDs"), then has **no scripted step for "launch the named existing Tasks"** and detaches. The launch tail is unreachable without first speccing a new feature.

## Decision

1. **Bare `/e2e-engineering` against a populated queue presents a front-door menu** — not an auto-route, not a fresh spec. Trigger: `queue.json` has ≥1 Task in `todo` OR `pending-qa` and Step 1 found no single `in-progress` Task to resume. Two-way fork, STOP for answer: **(1) specify a new task/idea**, or **(2) work on the existing queue**.
2. **"Work on existing queue" shows up to three labeled buckets** (only non-empty shown), each a selectable checklist; STOP and wait for the human's selection. Buckets and their routing:
   - **Ready for implementation** — `status:todo` with approved `tasks/<id>/prd.json` → **Launch sequence** (`→ On consent` step 3, resume mode) → `/e2e-flight`.
   - **Pending spec** — `status:todo` with no `prd.json` → per-feature flow for that Task id (spec → gate 1 → relands as ready-for-impl).
   - **Pending QA sign-off** — `status:pending-qa` → QA sign-off session (`human-qa` multi-Task) over the selected Tasks.
3. **Resume-mode entry into the existing Launch sequence.** Selecting ready Task ID(s) jumps to the launch tail (`→ On consent` step 3) skipping new-spec steps 1–2 (already queued + PRD-approved): the named IDs ARE the chosen set, verify each `todo`+approved, auto-add only unmet `dependsOn` (warn), set `selected:true`, invoke `/e2e-flight`. No checklist re-presentation.
4. **Direct selection (not a second hard stop).** If the reply already names Task ID(s), treat them as chosen per their bucket; mixed-bucket selections act per bucket. The checklist STOP is the fallback only when the reply is ambiguous.
5. **`pending-qa` folds into the menu instead of auto-routing.** Previously Step 0 auto-ran the QA session whenever any Task was `pending-qa` ("offer first"). Now bare invocation surfaces it as the **Pending QA sign-off** bucket — still prominent, but the human picks it rather than being forced into it. Explicit `/e2e-engineering qa` still hard-routes to the QA session over **all** pending-qa Tasks (no selection step), preserving the ADR 0018 batch-clear gesture.

## Considered Options

- **Flat single-list listing** (the original detach behavior: "5 ready, 8 need spec, reply with IDs") — rejected: no explicit new-vs-existing fork, mixes pending-spec and ready-for-impl in one undifferentiated list, and had no scripted follow-through (the detach). The two-level menu makes the user's intent explicit before acting.
- **Keep pending-qa auto-routing, add only a todo-launch branch** — rejected: leaves two competing entry behaviors (auto QA vs menu) for the same bare invocation. One unified menu that includes the QA bucket is more predictable.
- **Make Step 1.1 detect any `todo` Task (not just in-progress)** — rejected: Step 1 is phase detection for a *single* Task root; cross-Task queue routing belongs in Step 0.
- **A separate `/e2e-engineering launch` sub-mode** — rejected: re-running the bare front door against a populated queue is the natural gesture; gating it behind a sub-mode hurts discoverability.
- **Always force the checkbox stop even when IDs are named** — rejected per decision 4: redundant interactive stop after the human already chose; fallback-only keeps the safety net without friction.

## Consequences

- Both runtime entry points (`.claude/skills/e2e-engineering/SKILL.md`, `.agents/skills/e2e-engineering/SKILL.md`) gain the Step 0 menu + the resume-mode arm of the launch tail; `dist/` regenerated via `build-dist.js`.
- The launch tail (`→ On consent` step 3) is now reachable from two entries — new-spec consent and menu resume-mode — and documents both.
- Behavior change vs ADR 0018: bare invocation no longer auto-enters the QA session; it offers QA as a menu bucket. Explicit `qa` arg behavior is unchanged. ADR 0018's batch-clear semantics are preserved either way.
- Closes the detach: a populated, none-in-progress queue now has a scripted path to `/e2e-flight`, to spec, or to QA — instead of running out of instructions.
- No schema change — `selected`/`status`/`prd.json` presence already carry all state the menu reads.
