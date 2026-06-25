# design — conditional

Fires when the task bears UI (the `design?` trigger in [grill-with-docs](grill-with-docs.md) gates it). Skipped cleanly for pure-API/backend/CLI/non-visual work. Interactive **human phase** — direction, NOT final UI. Seeds/updates the durable [DESIGN.md](../schemas/design.md) at repo root; **flight only READS it**. Reads the [ui-design.md](../standards/ui-design.md) anti-slop standard. Spec/code-only — no image generation here (taste questions may point to a throwaway [prototype](prototype.md) ui-branch).

## First move (ALWAYS) — set the register
Before anything else, decide **Brand vs Product** (DESIGN.md §Overview). This is the pivotal calibration: it gates half of ui-design.md (brand rules apply only when register = Brand). Default = **Product** unless the surface is marketing/landing/editorial/launch.

| Register | When | Posture |
|---|---|---|
| Product (default) | dashboards, admin, data-tables, forms, internal tools | dense, predictable, readable states, quiet motion, a11y-first |
| Brand | marketing, landing, editorial, launch surface | editorial type, image-led heroes, scroll choreography |

## Branch: greenfield (no design language yet)
Scan-then-confirm interview (short — confirm, don't quiz):
- **Register** (set above).
- **Who-for** — the audience.
- **Voice** — three real words ("precise, calm, unfussy"), not adjectives-soup.
- **Named visual references** — real products/sites this should feel like.
- **Anti-references** — what it must NOT look like (the slop it must avoid).
- **A11y needs** — contrast, keyboard, reduced-motion expectations.

Then the agent **drafts DESIGN.md** in the [Stitch format](../schemas/design.md) (6 sections + §Index), with a top-of-file `<!-- SEED -->` marker until real components exist. Human approves at **gate 1**.

## Branch: brownfield (design language already exists)
- Recognize the existing language from the **codebase-map.md UI section** + the actual component/style code.
- DESIGN.md **records REALITY** — what the code actually is, truthful not aspirational.
- ui-design.md violations found in the existing UI → recorded in §6 Do's & Don'ts as **flagged deviations / candidates** for the human to route (like walled refactor candidates). **Never silently "corrected"** — DESIGN.md must stay truthful.

## Hand-off to to-prd
Feed the interview conclusions forward: **audience + anti-references → captured in the PRD** by [to-prd](to-prd.md) (the strategy half lives in `prd.json`, not a second durable file). Register + north star + voice stay in DESIGN.md §Overview.

## Optional
External DESIGN.md-aware skills (impeccable / stitch / taste-skill / Claude design) MAY enrich the draft if installed — never required, graceful absence.

## Red flags (stop)
- **Skipping the register call** — it calibrates everything; never start without it.
- **Producing final UI here** — direction only; pixels are built in flight, judged at human-QA.
- **Writing impl detail into DESIGN.md** — it holds the system (tokens/register/components), not component code.
- **Letting flight write DESIGN.md** — read-only in the implementation loop; amendments are human-phase only (gate 1 seed, post-impl QA amend).
- **Quizzing instead of confirming** (greenfield) — scan, propose, let the human react.
