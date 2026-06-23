# De-slop scan — standalone /e2e-deslop skill with architecture-scout agent and incremental scan ledger

**Status:** accepted.

The README "AI-Engineering" essay (Part 2.4) advocates running architecture improvement *regularly* — surfacing shallow modules, duplicated rules, missing seams, poor locality, untestable spots as candidates a human chooses from. The skill only produces such candidates **incidentally** (`map-codebase` §5, a change-scoped byproduct walled `NOT THIS TASK`) or **once** (`adopt` Half 2, repo-wide but locked to one-time onboarding and also drafts docs). There is no recurring, repo-wide, deep architecture scan.

## Problem

Two non-options framed the gap:

- **Re-running `adopt`** is wrong — it is one-time onboarding, drafts CONTEXT/constitution/ADRs, and is not meant to repeat.
- **Leaning on `map-codebase` §5** is wrong — it is change-scoped, surface-only, and tuned as a byproduct, not a deep repo-wide analysis.

A recurring scan over a whole repo is token-expensive if it re-reads everything every run. It needs memory of what was already covered — but a naive "scanned" latch goes permanently blind to slop that returns to an area after later edits.

## Decision

1. **New standalone top-level skill `/e2e-deslop`** (the 4th skill alongside `/e2e-engineering` + `/e2e-flight`), with its own dual-runtime entry points (`.claude/skills/e2e-deslop/`, `.agents/skills/e2e-deslop/`), AGENTS.md router entry, and install wiring; runtime-neutral body under `skills/`. Chosen over a `/e2e-engineering deslop` mode for discoverability of a recurring maintenance operation, accepting the larger dual-runtime surface.
2. **New 5th expert agent `architecture-scout`** — a proactive *hunter*, not a reviewer. Input is a scan area (no diff); it hunts deep-vs-shallow modules, locality, leverage, missing seams, duplicated rules, untestable spots. Canonical spec at `skills/e2e-engineering/agents/architecture-scout.md`; Claude wrapper generated, Codex prompt-injected — same dual-runtime contract as the four review agents.
3. **New output type — refactor-candidate manifest.** Per area, candidates `{ area, smell (shallow-module|dup-rule|missing-seam|poor-locality|untestable), location, rationale, proposedBoundary, blastRadius (S|M|L), priority (high|med|low), behaviorPreserved }`. Ranked by priority + blastRadius — **not** Critical/Important/Minor (review-defect vocabulary, wrong for opportunities).
4. **Fan-out one `architecture-scout` per eligible scan area** (parallel, read-only), and **force fan-out** via the existing Step-0 forcing mechanism — inline deep analysis over a whole repo is the token-blowup path.
5. **Incremental scan ledger** `.e2e-engineering/scan-ledger.json` — durable and repo-scoped (sibling to `queue.json`; does **not** rot or reset per task, unlike `codebase-map.md`/`research.md`). Entry `{ area, scannedAtCommit, verdict: candidate|clean|accepted }`. Eligibility (**scanned-since-change**): area absent, OR its files changed since `scannedAtCommit`, OR `verdict:candidate` not yet actioned. `verdict:accepted` (human "won't-fix") mutes an area until manually reopened.
6. **Scan area grain = module boundary** — an ARCHITECTURE.md §1 module when that doc exists, else a top-level source subdirectory; `scannedAtCommit` = hash over the area's file subtree. Module-grain (not per-file) because architecture smells are inherently cross-file.
7. **Candidates flow through the existing pipe:** refactor-candidate manifest → `triage` → human-picked refactor Tasks in the queue (full flow, ADR 0012). Same wall as `map-codebase` §5 — code is **never** auto-refactored.

## Considered Options

- **Option 1 — recurring `adopt` Half-2** (reuse map-codebase repo-wide, no new agent) — rejected as the analysis engine: §5 is a shallow change-scoped byproduct; repo-wide it reads noisy. Cheapest, but under-powered for deliberate deepening.
- **Option 3 — recurring Half-2 + advisory lens of the existing review agents** — rejected on token cost: an advisory fan-out (N reviewers re-reading candidate areas) over a whole repo is the most expensive path, every run.
- **Reuse the review-manifest shape for scout output** — rejected: Critical/Important/Minor is bug-review semantics; a shallow module is not a Critical defect.
- **`/e2e-engineering deslop` mode instead of a standalone skill** — rejected for discoverability; standalone wins despite the extra dual-runtime entry points.
- **Scanned-once set / refactor-completion-driven coverage** — rejected: the first goes blind to re-rot; the second pays full-repo scan tokens every run (defeats the incremental goal).

## Consequences

- Install surface grows by one skill across both runtimes (Claude entry point, Codex entry point, AGENTS.md router, install wiring, optional Cursor rule) — README **Install** + **Fidelity** sections need updating.
- A 5th expert agent to maintain (canonical spec + generated Claude wrapper + Codex injection + `agents.manifest.json` entry + validation).
- A new **durable** artifact (`scan-ledger.json`) joins `queue.json` as repo-scoped state that does not reset per task — distinct from the sprint-lifetime Task artifacts.
- CONTEXT.md updated: new terms `De-slop scan`, `Scan ledger`, `Scan area`, `architecture-scout`, `Refactor-candidate manifest`; refined `Refactor candidates`.
- The README essay's "run architecture improvement regularly" guidance now maps to a real command rather than an aspiration.
