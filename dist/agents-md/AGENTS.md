# Agents

Codex routing block. Trigger phrases → skill entry points.

| Trigger | Skill |
|---------|-------|
| "e2e-engineering", "e2e-eng", "ship-it", "implement feature", "build this end to end", "run the full flow" | `.agents/skills/e2e-engineering/SKILL.md` |
| "e2e-flight", "flight", "drain the queue", "implement the selected tasks" | `.agents/skills/e2e-flight/SKILL.md` |
| "grill-with-docs", "stress-test my plan", "challenge this plan" | `.agents/skills/grill-with-docs/SKILL.md` |
| "de-slop", "deslop", "architecture scan", "scan for tech debt", "find refactor candidates", "architecture deepening" | `.agents/skills/e2e-deslop/SKILL.md` |

**Note:** e2e-flight requires the shared `skills/` tree, worker fan-out capability, and branch-visible worker changes. If worker checkout isolation is unavailable, Codex uses serial branch mode instead of parallel ready-set dispatch. Emits `<e2e-stall reason="shared-skills-missing" />`, `<e2e-stall reason="fanout-unavailable" />`, or `<e2e-stall reason="worker-changes-unavailable" />` if unavailable; never falls back to inline slice work (ADR 0023).


<!-- headroom:rtk-instructions -->
# RTK (Rust Token Killer) - Token-Optimized Commands

When running shell commands, **always prefix with `rtk`**. This reduces context
usage by 60-90% with zero behavior change. If rtk has no filter for a command,
it passes through unchanged � so it is always safe to use.

## Key Commands
```bash
# Git (59-80% savings)
rtk git status          rtk git diff            rtk git log

# Files & Search (60-75% savings)
rtk ls <path>           rtk read <file>         rtk grep <pattern>
rtk find <pattern>      rtk diff <file>

# Test (90-99% savings) � shows failures only
rtk pytest tests/       rtk cargo test          rtk test <cmd>

# Build & Lint (80-90% savings) � shows errors only
rtk tsc                 rtk lint                rtk cargo build
rtk prettier --check    rtk mypy                rtk ruff check

# Analysis (70-90% savings)
rtk err <cmd>           rtk log <file>          rtk json <file>
rtk summary <cmd>       rtk deps                rtk env

# GitHub (26-87% savings)
rtk gh pr view <n>      rtk gh run list         rtk gh issue list

# Infrastructure (85% savings)
rtk docker ps           rtk kubectl get         rtk docker logs <c>

# Package managers (70-90% savings)
rtk pip list            rtk pnpm install        rtk npm run <script>
```

## Rules
- In command chains, prefix each segment: `rtk git add . && rtk git commit -m "msg"`
- For debugging, use raw command without rtk prefix
- `rtk proxy <cmd>` runs command without filtering but tracks usage
<!-- /headroom:rtk-instructions -->
