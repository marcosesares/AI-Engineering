# prototype — conditional

Fires when taste/UX or state-machine uncertainty needs concrete feedback. grill-with-docs gates it AND picks branch. THROWAWAY experiment — NOT final implementation.

## Branch: ui
For visual / UX / interaction uncertainty.
- Build quick visual variants. Cheap, disposable.
- Reference the [ui-design standard](../standards/ui-design.md) (register + anti-slop) while exploring — so variants avoid known tells.
- Feedback loop: browser-driven — render and look (Playwright MCP / screenshots). Show user variants, let them react. **Image generation is an allowed throwaway aid HERE ONLY** (never in the flow proper — Fork Y is spec/code-only).
- Goal: resolve taste/layout/flow questions before committing to PRD.
- Feed conclusions into [DESIGN.md](../schemas/design.md) (via the [design](design.md) step) and to-prd — the prototype is thrown away, the taste call is kept.

## Branch: logic
For state-machine / algorithm / terminal-app uncertainty.
- Build minimal spike of core logic or state machine.
- Feedback loop: textual — run it, print states/transitions, inspect output.
- Goal: prove model behaves before committing to PRD.

## Rules
- Throwaway. Do NOT carry prototype code into implementation. Output = understanding, not artifacts.
- Feed conclusions back into grill-with-docs notes / to-prd.

## Red flags (stop)
- Polishing prototype as if production.
- Prototype code leaking into real implementation (skipped TDD + constitution).
- Prototyping when uncertainty is not taste/UX/state-machine (use research instead).
