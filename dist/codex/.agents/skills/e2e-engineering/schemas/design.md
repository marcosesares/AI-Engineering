# Schema — DESIGN.md

Durable, project-level reference: THIS project's design system — taste, register, tokens, components. The "what it looks like + why" map every `ui` slice steers by. Lives at repo root (sibling to CONTEXT.md / ARCHITECTURE.md / constitution.md). The visual analogue of ARCHITECTURE.md. See ADR 0030.

## Boundary (no overlap with other doc-types)

| Doc | Holds | Scope |
|-----|-------|-------|
| CONTEXT.md | glossary — terms only | durable |
| constitution.md | **generic** engineering standards | durable, cross-project |
| ARCHITECTURE.md | project structure — WHERE code goes | durable, this-project |
| **DESIGN.md** | **project design system** — WHAT it looks like + register + tokens | durable, this-project |
| [ui-design.md](../standards/ui-design.md) | **generic** anti-slop baseline | durable, cross-project |
| ADRs | point-in-time decision + rationale | append-only log |

**Split rule:** generic taste rule ("ban bounce easing") → [ui-design.md](../standards/ui-design.md). Project-specific token/decision ("our accent is `--signal` OKLCH 0.7 0.15 250") → DESIGN.md. DESIGN.md **overrides** the baseline where they conflict (same as ARCHITECTURE.md §4 over api-testing.md). Audience + anti-references live in the **PRD** (`to-prd` interviews there), NOT here — one durable design file, not two.

## Stitch cross-tool format (6 fixed sections, fixed order + names)
Use these exact section names in this exact order — keeps interop with external DESIGN.md-aware tools (impeccable / stitch / taste-skill / Claude design). Then append our trailing **§Index** (additive — standard parsers ignore it).

```markdown
# Design — <project name>

## 1 Overview
Creative North Star: <a named metaphor — "a quiet control room", "a field notebook">.
Register: <Brand | Product>.   <!-- the pivotal calibration; ui-design.md brand rules apply only when Brand -->
Brand voice: <three real words — "precise, calm, unfussy">.

## 2 Colors
OKLCH, descriptive names (not hex-as-name). One base + ≤1 accent.
<--ink: oklch(...); --surface: oklch(...); --signal: oklch(...)>

## 3 Typography
<display + body pairing; scale steps; line-height; weights>

## 4 Elevation
<shadow/border/surface layering tokens; radius scale 12–16px>

## 5 Components
<owned components + their states (loading/empty/error/:active/disabled); reuse map>

## 6 Do's & Don'ts
<project-specific taste calls + recorded brownfield deviations from ui-design.md>

## §Index
§1: L<start>–L<end>
§2: L<start>–L<end>
§3: L<start>–L<end>
§4: L<start>–L<end>
§5: L<start>–L<end>
§6: L<start>–L<end>
```

**§Index rule:** writer fills/REWRITES the line numbers AFTER every edit (same discipline as ARCHITECTURE.md). Readers use `offset/limit` — orchestrator fetches only the sections a slice needs (e.g. §1 register + §3 typography for a type slice, §5 components for a reuse check). validate.js does NOT check this — discipline is on the writer.

## Lifecycle
- **Lazy create** — born in the [design pre-impl step](../pre-impl/design.md) when a UI-bearing task first needs direction, or recorded from reality by `adopt`/`map-codebase` (brownfield). No empty-doc ceremony.
- **Writes: human-phase ONLY** (mirror ADR 0013 / ARCHITECTURE.md): drafted/seeded in pre-impl (human-reviewed, approved at **gate 1**); amended at the post-impl human-QA gate. **Flight (implementation loop) is READ-ONLY** — drift spotted by a sub-agent is PROPOSED in the summary, staged as a pending amendment, never written mid-flight.
- **Greenfield provisional marker:** until real components exist, the seed may carry a top-of-file `<!-- SEED -->` marker — direction agreed, components not yet built. Drop the marker once §5 records actual components.
- **§Index update:** any writer (design step, adopt, map-codebase, human at QA gate) MUST rewrite §Index line numbers after every edit.

## Read by
- Pre-impl ([design](../pre-impl/design.md), [to-prd](../pre-impl/to-prd.md)) — register + north star calibrate the PRD's UI acceptance criteria.
- [product-designer](../agents/product-designer.md) advisor — reads DESIGN.md + ui-design.md + the PRD draft; advises on coverage/taste BEFORE build.
- Fan-out — orchestrator injects the SCOPED slice (register + relevant tokens/components), not the whole doc (use §Index offset/limit).
- [frontend-reviewer](../agents/frontend-reviewer.md) — reviews the built slice against the approved DESIGN.md (deviation = Important: fix or justify).

## Rules
- Project-specific only. Generic taste → [ui-design.md](../standards/ui-design.md); terms → CONTEXT.md; structure → ARCHITECTURE.md.
- Records REALITY (brownfield) — truthful, not aspirational. Baseline violations = flagged deviations in §6, never silently corrected.
- Brownfield/no-UI project with no design decided yet → file may not exist; valid. UI-bearing task with empty/missing DESIGN.md → run the design step first (to-prd red-flags this).
