# Bounded, non-interactive command execution contract

**Status:** accepted — closes the wall-clock gap in ADR 0022 (forced fan-out is the only runaway brake); extends ADR 0032 (compile detection) and ADR 0024/0025 (gate 5 + soft-fail).

## Problem

`e2e-flight` tells the agent **which** command to run and never **how**. Grepping the whole skill tree for `timeout | non-interactive | background | --no-daemon | batch-mode | CI=1` returned zero hits: every emitted command was a naked foreground string.

Claude Code hid the defect — its shell tool auto-timeouts and can background. Codex / OpenCode / Cursor run the literal string unbounded, and a weaker driver model (DeepSeek) does not spontaneously add `-d`, `-B`, `--no-daemon`, or `--yes`. Observed: flights on OpenCode/DeepSeek hung indefinitely on the compile / package-build / stack-up step.

Every command class could block forever as specified:

- `npm run build` when the `build` script is a watcher or dev server (`vite build --watch`, `tsc -w`).
- `npx tsc --noEmit` / `npx playwright test` — the `Need to install… Ok to proceed? (y)` prompt reads stdin that never arrives headless.
- `mvn -q compile` with no `-B`; `./gradlew compileJava` with no `--console=plain --no-daemon`.
- `docker compose up` without `-d`. `ARCHITECTURE.md §4.1 Stack-up` is verbatim human text and nothing required detachment.
- An API-project script carrying `--ui` / `--headed` / `--watch`.

The deeper failure is a missing brake. ADR 0022 Consequences: *"the **only** thing preventing another runaway is fan-out firing + the inline-impl STOP."* Both brakes count turns. A hung shell burns wall-clock at zero turns, so neither sees it — the spawn stalls forever with no stall signal.

## Decision

1. **Contract, not runtime luck.** New shared sub-skill `skills/e2e-engineering/impl/command-execution.md`. Every command flight or a sub-agent runs is **bounded** (OS-level timeout wrapper — POSIX `timeout N`, PowerShell `Start-Job`+`Wait-Job -Timeout`; a native runtime timeout may substitute), **non-interactive** (`CI=1`, `NO_COLOR=1`, `npm_config_yes=true`, `DEBIAN_FRONTEND=noninteractive`, `GIT_TERMINAL_PROMPT=0` + per-tool flags), and **self-terminating** (nothing that serves, watches, tails, or attaches).

2. **Second runaway brake — Step 0 bounded-shell probe (fail-closed).** Flight probes that the runtime can time-box a command (blocking command under a 5s bound, control must return). Cannot bound → `<e2e-stall reason="unbounded-shell — runtime cannot time-box commands" />` + EXIT. Mirrors the existing `fanout-unavailable` / `worker-changes-unavailable` probes.

3. **Probe the script, never run it to find out.** Before selecting `npm run <script>`, read the script BODY in `package.json`; a watch/serve pattern disqualifies it → fall through to `npx --yes tsc --noEmit`. Detection flags hardened: `mvn -B -ntp -q compile`, `gradlew compileJava --console=plain --no-daemon`, `npx --yes`.

4. **Timeout routes by position, and never grinds.** Step-0 probe → stall. Worker compile/test → gate-3 strike + `findings[] type:blocker`. Orchestrator lint/compile (Step 3.4) → compile failure → normal reconcile. Gate-5 stack-up/suite → gate-5 failure (`gate5Strikes` + `gate5FailureIds[]`) → `partial` → `pending-qa`, honoring ADR 0025 — never `blocked`, never a stall. Teardown → WARN only. One cold-cache retry at 2× budget, never a third.

5. **Default budgets** (an explicit `§4.1` value wins): lint 3 min · compile 5 · stack-up/teardown 10 · package build 15 · suite 20.

6. **§4.1 is held to the contract.** `schemas/architecture.md §4.1` now requires every seeded command be non-interactive and self-terminating (`up -d`, no `--ui/--headed/--watch`, no `dev/serve/start`). A §4.1 command that violates it is a §4.1 defect: flight WARNs and skips rather than hanging on it. Flight still never writes §4.1 (ADR 0013).

7. **Dual-runtime.** Both `.claude/skills/e2e-flight/SKILL.md` and `.agents/skills/e2e-flight/SKILL.md` carry the probe + contract references; shared behavior in `impl/command-execution.md`, `impl/verification.md`, `impl/tdd.md`, `schemas/architecture.md`.

## Considered Options

- **Rely on the runtime's shell timeout** — rejected: that is exactly the bug. Only Claude Code has one; the skill ships to four runtimes.
- **Run the candidate script and kill it if it doesn't return** — rejected: a `--watch` build produces plausible output before blocking, so the kill is indistinguishable from a slow success. Read the script body instead; it is free and deterministic.
- **Background every long command and poll** — rejected as the default: it hides failures and complicates evidence capture. Detached is required only for the gate-5 stack, which must be `-d` and readiness-polled with a capped loop.
- **Treat a gate-5 timeout as `blocked`** — rejected: violates ADR 0025. A timeout is a gate-5 failure that rides to human-QA as a triage entry.
- **Global "just add a timeout" red flag with no budgets** — rejected: without numbers each spawn invents its own, and a cold Maven/Gradle cache trips a guessed-low bound on the first honest run.

## Consequences

- The OpenCode/DeepSeek hang is designed out, and the same hardening removes the latent hang on Claude (a 2-min tool timeout mid-`quarkusBuild` was already a false failure).
- ADR 0022's load-bearing single brake gains a wall-clock companion; its Consequences section is amended to point here.
- `§4.1` gains a contract clause; existing consumer `ARCHITECTURE.md` files with a foreground `up` or a `--headed` API cmd now get WARN + skip instead of an infinite block, and need a human-phase backfill.
- Budgets are defaults, not law — a genuinely long build states its own budget in `§4.1`.
- Non-mvn/gradle/npm build systems still out of scope (ADR 0032 carries that).
