# Standard — UI / UX design (anti-slop taste baseline)

Canonical baseline for UI/UX taste + anti-slop in this flow (Fork Y — UI is manual, no in-flight browser). Injected into every `ui` slice sub-agent alongside the [constitution](../constitution.md), read by [product-designer](../agents/product-designer.md) (advises the PRD) and [frontend-reviewer](../agents/frontend-reviewer.md) (reviews the built slice). Spec/code-only — this doc judges what is source-readable; rendered-layout judgments ride to human-QA.

## Override rule (read FIRST)
**Project has a `DESIGN.md` → it wins where they conflict.** This doc is the GENERIC baseline; the project's [DESIGN.md](../schemas/design.md) is the specific design system. Same rule as [api-testing.md](api-testing.md) vs ARCHITECTURE.md §4. Recognize the existing design language (brownfield) before applying any rule below — DESIGN.md records reality; baseline violations there are flagged deviations, not silent corrections.

## Register FIRST (the calibration that gates half this doc)
Read **DESIGN.md §Overview register** before applying anything. Two registers:

| Register | Default for | Posture |
|---|---|---|
| **Product** (DEFAULT) | dashboards, admin, data-tables, forms, internal tools, CRUD | dense, predictable, readable states, quiet motion, a11y/audit-first |
| **Brand** (gated) | marketing, landing, editorial, launch surface | editorial type, image-led heroes, scroll choreography |

Rules tagged **[brand-gated]** apply ONLY when register = Brand. Everything else applies to both. When DESIGN.md absent or register unset → assume **Product**.

## Enforcement layer (every rule is one of two)
- **[slice-reviewer]** — source-readable. frontend-reviewer catches it from the diff (overused font as identity, gradient text, nested cards, bounce easing, missing `prefers-reduced-motion`, em-dash in UI copy, skipped heading level).
- **[human-QA]** — needs a rendered layout (line length, overflow, cramped padding, actual contrast ratio). Fork Y has no in-flight browser → these ride to the human-QA gate, not the slice review.

## The 7 areas

### 1. Typography
- Intentional typeface. **Ban overused defaults AS THE WHOLE IDENTITY** (Inter / Geist / Space Grotesk / Instrument Serif used unchanged everywhere). [slice-reviewer]
- Pair display + body (two roles, not one font doing all). [slice-reviewer]
- Hierarchy steps ≥1.25×. [slice-reviewer]
- Body line-height 1.5–1.7; no crushed/wide body letter-spacing. [human-QA]
- Body ≥14px (ideally 16px). [slice-reviewer]
- **[brand-gated]** oversized editorial heroes.

### 2. Color
- **OKLCH**, descriptive names (`--ink`, `--surface-raised`), NOT hex-as-name. [slice-reviewer]
- One base + ≤1 accent (saturation <80%). [slice-reviewer]
- Always tint black/grays — no pure `#000`/`#fff`. [slice-reviewer]
- No gray text on colored background. [human-QA]
- **Ban the AI palette**: purple/violet gradient, cyan-on-dark, dark+glow. [slice-reviewer]
- Ban gradient text; ban reflex cream/beige as the default surface. [slice-reviewer]

### 3. Layout
- No nested cards / giant boxed wrappers. [slice-reviewer]
- Card radius 12–16px (no 24px+ blobs). [slice-reviewer]
- Rhythmic (not monotonous) spacing. [human-QA]
- Bento: exact cell count, no empty tiles. [slice-reviewer]
- Body text max-width 65–75ch. [human-QA]
- Container padding ≥16px. [human-QA]

### 4. Components
- **Reuse the owned component over duplicating** (ties to ARCHITECTURE.md ownership). [slice-reviewer]
- Every interactive component covers **loading (skeleton not spinner) / empty / error / `:active` / disabled**. [slice-reviewer]
- Button + form contrast WCAG AA. [human-QA]
- No placeholder-as-label; one label per CTA intent. [slice-reviewer]

### 5. Motion
- Animate **only `transform` / `opacity`** (no layout-property animation). [slice-reviewer]
- **Ban bounce/elastic easing.** [slice-reviewer]
- **`prefers-reduced-motion` mandatory.** [slice-reviewer]
- **[brand-gated]** scroll choreography / pinning.

### 6. Accessibility
- Contrast AA (4.5:1 body, 3:1 large). [human-QA]
- Focus order, labels/roles, keyboard reachability. [slice-reviewer]
- No skipped heading levels. [slice-reviewer]

### 7. Anti-slop tells (concrete catalog — the recognizable ones)
- Side-tab / border-accent on a rounded element ("the most recognizable tell"). [slice-reviewer]
- Icon-tile-above-heading feature template. [slice-reviewer]
- Identical 3-card grids. [slice-reviewer]
- Numbered section eyebrows (`01 / 02 / 03`). [slice-reviewer]
- Hero version labels (`V0.6` / `BETA`). [slice-reviewer]
- Div-based fake screenshots; decoration text strips; custom cursors. [slice-reviewer]
- Filler copy: "Jane Doe" / Acme, verb-slop (Elevate / Seamless / Unleash), perfect numbers (`99.99%`). [slice-reviewer]
- **Em-dash ban — GENERATED UI COPY ONLY.** No em-dashes in user-facing strings/labels/headings the build produces. [slice-reviewer]
  - **Explicit exception:** this ban does NOT apply to the caveman skill docs (which use em-dashes freely), NOR to this standard or any other internal markdown. Scope = rendered product copy, nothing else.

## Optional deterministic pre-pass
If `npx impeccable detect` is installed, the ui-slice review MAY run it as a deterministic exit-code gate before the human read. **Optional only** — never required, absent = skip silently. Native posture: no runtime dependency.

## Red flags (stop)
- Applying **[brand-gated]** rules to a Product surface (over-designing a dashboard) — register said Product, hold the line.
- "Correcting" a brownfield DESIGN.md deviation silently — record it as a flagged candidate for the human, keep DESIGN.md truthful.
- Treating a **[human-QA]** rule as a slice-review blocker — it needs a rendered layout; route it to human-QA.
- Writing impl detail into DESIGN.md, or treating this baseline as overriding a project's explicit DESIGN.md (it does not — DESIGN.md wins).
- Stripping em-dashes from skill docs / ADRs / this file "to comply" — the ban is product UI copy ONLY.

Depth reference (not the contract): the [design schema](../schemas/design.md) governs the DESIGN.md this standard defers to; the [design pre-impl step](../pre-impl/design.md) seeds it.
