# UI design system (DESIGN.md) + design advisor + anti-slop standard

**Status:** accepted — amends ADR 0013 (durable-doc human-phase writes), ADR 0007 (gate taxonomy unchanged), ADR 0024 (Fork Y spec/code-only stance).

The orchestrator and README advertised that the PRD is planned "with expert agents (UI designer / backend architect / DBA)", but that design advisor **never existed** — the only UI agent was `frontend-reviewer`, a post-build slice reviewer, not a pre-build advisor. There was also no durable design-system doc, no pre-impl design step, and no design standard for the reviewer to check against. This ADR fills those holes natively.

## Context

The flow has durable docs for glossary (CONTEXT.md), structure (ARCHITECTURE.md), and generic engineering (constitution.md) — nothing owned visual design / taste / tokens. `frontend-reviewer` was told to check "design-system consistency" with no design system to check against, and `prototype.md`'s ui-branch is throwaway taste experiments, not a durable design establishment. Ideas were borrowed (no runtime dependency) from impeccable (DESIGN.md + brand/product split + anti-slop detector), the taste-skill family (register boundary, density discipline), and Claude design (design-system-as-living-doc).

## Decision

1. **New durable `DESIGN.md` at repo root**, governed by a new `schemas/design.md`, beside CONTEXT.md / ARCHITECTURE.md / constitution.md. It is the visual analogue of ARCHITECTURE.md.
2. **Stitch cross-tool format** — six fixed sections in fixed order/names: Overview (Creative North Star metaphor + register + voice) · Colors (OKLCH, descriptive names) · Typography · Elevation · Components · Do's & Don'ts; plus a trailing `§Index` (line numbers) for our offset/limit reads. The §Index is additive — external DESIGN.md-aware tools still parse it.
3. **One durable file, not two (no PRODUCT.md).** Register + north star + brand voice live in DESIGN.md §Overview; audience + anti-references are captured in the PRD (`prd.json`), where `to-prd` already interviews. Avoids a fifth root doc the orchestrator/flight must govern.
4. **Register (Brand vs Product) is the primary calibration.** The `ui-design.md` standard **defaults to Product** (dense, predictable, readable states, quiet motion, a11y/audit-first); brand/awwwards rules are **register-gated** — they apply only when DESIGN.md §Overview register = Brand. Matches the taste-skill's own out-of-scope boundary (not for dashboards/admin/data-tables, which is most real product UI).
5. **New generic `standards/ui-design.md`** — anti-slop taste baseline mirroring `standards/api-testing.md`, injected into `ui` slices, read by the advisor and the reviewer. Anti-slop encoded as a concrete catalog subset, each rule tagged by enforcement layer: **slice-reviewer** (source-readable) vs **human-QA/LLM** (needs a rendered layout — line length, overflow, contrast, padding ride to human-QA, since Fork Y has no in-flight browser). Em-dash ban is scoped to **generated UI copy only** (explicitly NOT the caveman skill docs or any internal markdown).
6. **New conditional `design` pre-impl step** (`pre-impl/design.md`), fired by a `design?` trigger in grill-with-docs, alongside `research?`/`prototype?`. First move is always to set the register. Greenfield drafts DESIGN.md from a scan-then-confirm interview (provisional `<!-- SEED -->` marker until components exist); brownfield records reality and flags baseline deviations for the human. **Not a new hard gate** — gate taxonomy (ADR 0007) unchanged.
7. **New design advisor agent (`product-designer`)** — read-only, mirrors `backend-architect.md`. Acts on the **spec, pre-build**: bakes design requirements into the PRD acceptance criteria and surfaces what DESIGN.md must seed. Advisory contract (`verdict: clean | findings` then `- [Important|Minor] …`) with **no Critical** — an advisor sharpens the spec, it does not gate.
8. **Division of labour vs `frontend-reviewer` (no duplication).** The advisor acts on the spec pre-build; the reviewer acts on the built slice post-green (verifies code meets the approved DESIGN.md + ui-design.md, deviation = Important). Hand-off = DESIGN.md + the acceptance criteria. The reviewer's manifest description is refined to "UI/UX slice reviewer" to disambiguate.
9. **DESIGN.md is human-phase-written, flight read-only** (exact analogy to ARCHITECTURE.md per ADR 0013): seeded/drafted in pre-impl, approved at gate 1, amended at the post-impl human-QA gate; the implementation loop only reads it, proposing drift as a pending amendment.
10. **Spec/code-only (Fork Y).** No image generation in the flow; image-gen is referenced only as an optional throwaway aid inside `prototype`. An optional `npx impeccable detect` deterministic pre-pass MAY gate a ui-slice review if installed — never required, graceful absence.

## Why `product-designer`, not the advertised name

`scripts/validate.js` lists the old advisor token as a **deprecated role** (with `senior-qa`) — it must not appear in any active source/dist file, and its agent wrapper must not exist. The new advisor is therefore named **`product-designer`**. The standard file `standards/ui-design.md` is fine (the `ui-design` substring is not the deprecated token). The deprecation is kept intact (history preserved); the gap the README/SKILL advertised is closed by the new advisor under the new name.

## Considered Options

- **A second durable `PRODUCT.md`** for audience/strategy — rejected: a fifth root doc to govern; audience/anti-refs fit the PRD interview `to-prd` already runs.
- **Brand/awwwards taste as the primary register** — rejected: most product UI is dashboards/admin/data-tables; Product is the correct default, Brand is register-gated.
- **A new hard gate for design** — rejected: the conditional step + advisor + reviewer cover it without churning the gate taxonomy (ADR 0007).
- **Image-generation design path** (image-to-code / brandkit / imagegen) — deferred per Fork Y; the flow stays spec/code-only.
- **Un-deprecating the old advisor token** — rejected: keeps the validate guard and history intact.

## Consequences

- New files: `standards/ui-design.md`, `schemas/design.md`, `pre-impl/design.md`, `agents/product-designer.md`, this ADR. New per-project instance: `DESIGN.md` (seeded later by the design step, not created in this repo — this repo has no UI surface).
- `agents.manifest.json` gains the `product-designer` role; `frontend-reviewer` description refined. The generated `.claude/agents/product-designer.md` wrapper is emitted by `generate-agent-wrappers.ps1`.
- Wiring: grill-with-docs (`design?` trigger), to-prd (advisor swap + DESIGN.md read + audience/anti-ref capture + empty-DESIGN.md red flag), prototype, tdd, both SKILL entry points (eng + flight, lockstep ×2 runtimes), frontend-reviewer body.
- CONTEXT.md gains glossary terms: register, Creative North Star, design system, design token, anti-slop, design advisor. README clears the queued reconcile (advertised advisor now real).
- Gate taxonomy (ADR 0007) unchanged; Fork Y (ADR 0024) spec/code-only posture preserved.
