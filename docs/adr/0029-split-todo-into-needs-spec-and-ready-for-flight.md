# Split queue `todo` into `needs-spec` + `ready-for-flight`

**Status:** accepted. Builds on ADR 0028 (front-door menu), ADR 0017 (Task queue), ADR 0018 (QA deferral).

## Problem

The `queue.json` Task status enum was `todo|in-progress|pending-qa|done|blocked`. `todo` silently meant **two different things** depending on provenance:

- **Gate-1-born** Tasks — queued in the forward flow AFTER PRD approval. Genuinely ready to implement.
- **Triage / QA-finding-born** Tasks — queued as a bare idea/title with no `prd.json` yet (ADR 0018). Cannot fly; need a spec first.

The ADR 0028 front-door menu had to disambiguate these by **statting `tasks/<id>/prd.json`** for every `todo` Task. The queue alone was not self-describing: a human (or `/e2e-flight`'s selection filter) could not tell a launchable Task from an unspecced idea without a filesystem probe. Flight's `selected:true AND status:todo` selection could in principle pick an unspecced Task.

## Decision

1. **Replace `todo` with two explicit states.** New enum: `needs-spec | ready-for-flight | in-progress | pending-qa | done | blocked`.
   - **`needs-spec`** — queued idea/title, no approved PRD. Triage and QA findings are born here.
   - **`ready-for-flight`** — PRD approved at gate-1, awaiting `/e2e-flight`. Forward-flow Tasks are born here. **Only `ready-for-flight` is launchable.**
2. **Lifecycle:** `needs-spec ──(PRD approved @ gate-1)──> ready-for-flight ──(flight picks)──> in-progress ──> pending-qa ──> done`; `in-progress ──(3-strike)──> blocked`.
3. **`prd.json` remains the source of truth; status is a reconciled label, not an independent truth.** Invariant: `ready-for-flight` ⟺ an approved `prd.json` exists; `needs-spec` ⟺ none. Front-door and flight RECONCILE at read — a `ready-for-flight` Task whose `prd.json` is missing is demoted to `needs-spec` (warn). This keeps the new field from drifting against the artifact and preserves the existing "prd.json is sole source of truth" principle.
4. **Writers updated.** `/e2e-engineering`: creates `needs-spec` (triage/QA) or `ready-for-flight` (gate-1); **flips `needs-spec → ready-for-flight`** when a menu-selected idea clears gate-1 (no duplicate append). `/e2e-flight`: flips `ready-for-flight → in-progress → pending-qa/blocked`; selection is `selected:true AND status:ready-for-flight`.
5. **Menu buckets map 1:1 to states** (ADR 0028) — *Ready for implementation* = `ready-for-flight`, *Pending spec* = `needs-spec`, *Pending QA sign-off* = `pending-qa`. The `prd.json` stat in the bucket logic is dropped (status now carries it).
6. **`<e2e-complete>`** fires when no `selected:true` Task is `needs-spec`, `ready-for-flight`, or `in-progress`.

## Considered Options

- **Keep `todo`, derive the split by statting `prd.json`** — rejected: queue not self-describing, repeated filesystem probes, and flight selection could pick an unspecced Task. The distinction is real state and deserves a real field.
- **Names `backlog`/`ready`, `draft`/`specced`** — viable; rejected in favor of `needs-spec`/`ready-for-flight` which read verbatim as the menu bucket intent and are unambiguous about what each gates.
- **Make status the sole truth (no reconcile against prd.json)** — rejected: introduces drift (status says ready, PRD deleted). Mirroring the artifact, with read-time reconcile, is safer and consistent with prior ADRs.

## Consequences

- **Schema + both runtimes touched:** `schemas/queue.json.md` (enum, invariants, writers, lifecycle, selection); `.claude` + `.agents` `e2e-engineering/SKILL.md` (Step 0 buckets, launch-tail land-vs-flip, resume verify); `.claude` + `.agents` `e2e-flight/SKILL.md` (selection + lock transition); `triage.md`, `post-impl/human-qa.md`, `schemas/qa-signoff.md` (born `needs-spec`); `CONTEXT.md` glossary (new **Task status** + **Front-door menu** terms). `dist/` regenerated.
- **Story status untouched.** `prd.json` story status stays `todo|in-progress|done|blocked` — same words, different scope. Schema note added to prevent conflation.
- **Existing live queues need a one-time migration:** `todo` + approved `prd.json` → `ready-for-flight`; `todo` + none → `needs-spec`.
- Queue is now self-describing; flight can never pick an unspecced Task; the front-door menu reads status directly.
