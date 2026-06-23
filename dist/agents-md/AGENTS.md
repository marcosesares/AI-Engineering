# Agents

Codex routing block. Trigger phrases → skill entry points.

| Trigger | Skill |
|---------|-------|
| "e2e-engineering", "e2e-eng", "ship-it", "implement feature", "build this end to end", "run the full flow" | `.agents/skills/e2e-engineering/SKILL.md` |
| "e2e-flight", "flight", "drain the queue", "implement the selected tasks" | `.agents/skills/e2e-flight/SKILL.md` |
| "grill-with-docs", "stress-test my plan", "challenge this plan" | `.agents/skills/grill-with-docs/SKILL.md` |
| "de-slop", "deslop", "architecture scan", "scan for tech debt", "find refactor candidates", "architecture deepening" | `.agents/skills/e2e-deslop/SKILL.md` |

**Note:** e2e-flight requires the shared `skills/` tree, worker fan-out capability, and branch-visible worker changes. If worker checkout isolation is unavailable, Codex uses serial branch mode instead of parallel ready-set dispatch. Emits `<e2e-stall reason="shared-skills-missing" />`, `<e2e-stall reason="fanout-unavailable" />`, or `<e2e-stall reason="worker-changes-unavailable" />` if unavailable; never falls back to inline slice work (ADR 0023).
