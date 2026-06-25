# grill-with-docs — pre-impl doc-aware brainstorm (the only grill)

Karpathy-style brainstorm, doc-aware. Single grilling skill (absorbs old grill-me). Runs in pre-implementation AFTER map-codebase (brownfield), so every question informed by what already exists. Stateless, one question at a time, no cap. Loops until user approves direction. See ADR 0019.

## Read first (so questions are informed)
Before first question, read what exists:
- `CONTEXT.md` — project's canonical terms.
- `ARCHITECTURE.md` (if present) — durable structure/ownership/naming (use §Index for offset/limit).
- **Brownfield:** `.e2e-engineering/.../codebase-map.md` §1–§4 — blast radius, seams, existing language (use §Index for offset/limit). map-codebase ran first precisely so grilling walks in familiar.
- **Greenfield / fresh repo:** may be empty/minimal. Grill anyway; seed CONTEXT.md as terms crystallise.

Never ask what code/docs already answer — read instead.

## What to do
Interview user relentlessly until shared, concrete understanding. Walk each branch of design tree, resolve dependencies one at a time. Give recommended answer per question.

- Ask ONE question at a time. Wait for answer before next.
- If question answerable by reading code/docs → read instead of asking.
- Reconcile language AS YOU GO: user's term conflicts with glossary or code's term → surface immediately, pin ONE canonical term. Update CONTEXT.md inline as terms resolve (glossary only — no implementation detail).
- Stress-test with concrete scenarios. Probe edge cases. Force precision on boundaries.
- Push back: simpler approach exists → say so (constitution: think-before-coding).
- Offer ADR only when decision is hard-to-reverse AND surprising AND real trade-off.

## Gate conditional pre-impl steps
Before exiting, decide and record which conditional steps fire:
- **research?** — YES if task leans on external APIs / unfamiliar libs / unknown protocols.
- **prototype?** — YES if taste/UX or state-machine uncertainty needs concrete feedback. Pick branch: **ui** (visual variants) or **logic** (state machine / terminal).
- **design?** — fires the [design](design.md) step (sets register, seeds/records DESIGN.md). Explicit YES/NO:
  - **YES** if the task adds/changes a user-visible screen/page/route · creates/edits a component with visual presentation · the PRD says button/form/modal/layout/styling/UX/visual · any greenfield with a UI · a brand/marketing surface.
  - **NO** if pure API/backend/data/schema · CLI/script with no rendered output · refactor with zero visual change · non-visual bugfix.

(map-codebase NOT gated here — already ran before this skill, driven by taskType.)

## Exit
User approves direction → hand caveman:ultra brainstorm notes + conflict-free language + conditional-step decisions to orchestrator, which sequences research / prototype / design / to-prd. Language reconciled here → Implementation skips straight to to-issues (no second grill).

## Red flags (stop)
- Building anything here — brainstorm only.
- Asking question codebase or glossary already answers.
- Skipping read-first step (questions would be uninformed).
- Letting term conflict survive into to-prd (every slice inherits ambiguity).
- Writing implementation detail into CONTEXT.md.
- Moving on while user still uncertain about core direction.
