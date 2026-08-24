# DSH runtime adaptation for e2e-flight

**Status:** accepted — refines ADR 0023 (dual-runtime adaptation: adds a THIRD runtime profile for DeepSeek Harness), ADR 0036 (bounded background jobs: adds the measured fact that DSH background flags void timeout budgets, making the watchdog the only bound), ADR 0022 (fan-out mechanics: ratifies `subagent`-based dispatch as first-class fan-out on DSH). Amends execution mechanics only; gates 1/2/3/5 and the review contract unchanged.

The payments-monetization drain ran on DSH with the Codex/Claude entry points hand-translated in-session: impl/review waves dispatched as background subagents, workers in shared-FS worktrees, `job_kill`/`job_output` as the job registry. It worked — all 35 stories shipped — but three DSH facts cost real money and were only discovered mid-flight: (1) DSH background jobs IGNORE `timeoutMs` entirely (measured: a 60s sleep under a 20s budget ran 60.8s and completed; a 900s sleep under a 720s budget completed after 900s), so the gate-5 half-A suite's 30-min budget was decorative and it wedged 4h47m until a human killed it; (2) the orchestrator's watchdog polling stopped when a read returned "running" — last poll 02:35, human kill 07:12 — because no rule said the loop must persist inside the turn; (3) the skill's Step-0 probe would have stalled `fanout-unavailable` on a runtime that actually has full fan-out capability via a different tool shape. This ADR ratifies the DSH profile instead of leaving it to per-session improvisation.

## Context

- **Tool shapes differ by runtime.** Codex exposes `spawn_agent`/`spawn_agents_on_csv`; Claude exposes `Agent`/`EnterWorktree`; DSH exposes `subagent` (background/continuable), `job_*` (list/output/kill), `list_agents`, `interrupt_agent`, `send_message`, and `pwsh` with a native foreground `timeoutMs`. Capability is equivalent — the names are not. A probe keyed to one runtime's names stalls on another's.
- **Background dispatch voids timeout budgets (measured).** `run_in_background` jobs carry no tool timeout on DSH; the drain's "30-min" background suites were unbounded and the 4.7h wedge burned the session's worst token/credit cost.
- **A watchdog that stops watching is not a watchdog.** The drain's orchestrator polled the wedged suite twice (02:25, 02:35) and then its turn ended; the silence heuristic never fired because no loop survived.
- **Sandbox modes constrain the shell.** DSH read-only mode runs PowerShell in ConstrainedLanguage (no .NET statics, no named-pipe stdout capture, writes denied); workspace-write runs FullLanguage. A denied write is policy, not a transient error — retrying it is a loop, not a fix.
- **DSH workers are full agents.** Subagents share the workspace filesystem, receive prompts always, and can commit to git (probe-verified) — worker throughput is not the 1 tool-call/round problem this skill degraded for (ADR 0037 chunk-driver stays as a fallback trigger only).

## Decision

1. **DSH is a first-class runtime profile.** Detection is tool-shape, not runtime-name: `spawn_agent`/`spawn_agents_on_csv`/`ToolSearch` absent AND `subagent` + `pwsh` + `job_*` present → DSH mode. Flight Step 0 reads `impl/dsh-runtime.md` ONCE and adopts its mappings — impl/review waves = N× background `subagent` dispatches in one program, worker-change = shared-FS git visibility, bounded-shell = foreground `timeoutMs` kill test, PLUS a write-capability probe (create+delete a temp file; denied → `<e2e-stall reason="sandbox-write-denied" />` + EXIT). DSH mode never stalls `fanout-unavailable`.
2. **Background jobs are watchdog-only on DSH.** `timeoutMs` on a background job is decorative (measured) — the ADR 0036 watchdog (bounded poll + hard deadline + 10-min silence heuristic + orphan sweep) is the ONLY bound. The skill never presents a timeout number as a background job's budget.
3. **The watchdog loop persists inside the orchestrator's turn.** Bounded `job_output({ wait: true, timeout_ms: 90s-or-less })` reads in a persistent loop with output-GROWTH comparison between reads; zero growth + `running` > 10 min → `job_kill` + `TIMEOUT … (silent)`. A read that returns `running` and ends the loop is a red flag, not a checkpoint.
4. **DSH budget table.** Foreground `timeoutMs`: inspect 30–60s · lint 3m · compile 6m · focused gradle 12m · stack-up 10m · package build 15m · suite 30m · playwright 20m · teardown 10m. Background: suite watchdog deadline 45m (poll 60–90s, silence 10m), stack-up/package 15m/20m, playwright 30m. Never exceed — the drain's 12–13m/30m values matched these lines and the wedge was unboundedness, not size. Cold cache: ONE 2× retry.
5. **Model-efficiency contract (DeepSeek, reasoning-effort max).** Thinking tokens dominate: compact JSON manifests, evidence pointers not logs (DSH truncates long tool output to tail + spillPath — read tails), non-busy `job_output` waits over poll loops, clean-context `subagent` for workers/reviewers, goal tools for the one-Task objective + resume.

## Considered Options

- **A separate DSH SKILL.md entry point** — rejected: two entries already diverge on vocabulary; a third triples the drift surface. One runtime section + one shared `impl/dsh-runtime.md` keeps the diff local to Step 0 and the mapping table.
- **Huge timeout values as hang insurance (the in-session fix)** — rejected: measured to be decorative on background jobs and clamping-bound on foreground; the watchdog is the brake, the budget is a diagnostic.
- **An orchestrator-side background-job monitor subagent (spawned watcher)** — rejected: the orchestrator's own turn can run the loop with `job_output` waits; a watcher subagent adds a spawn + context handoff and still needs the same silence rule.
- **Detecting DSH by name/env instead of tool shape** — rejected: runtime names are deployment details; the tool shape IS the contract.

## Consequences

- DSH flights stop at Step 0 only for real capability gaps (no `subagent`, no write permission), not vocabulary gaps. The `sandbox-write-denied` stall joins `fanout-unavailable`/`worker-changes-unavailable`/`unbounded-shell`/`preflight-failed` in the stall set.
- Gate-5 wall-clock cost on DSH becomes bounded by construction (silence kill at 10 min vs the 4.7h wedge); every kill lands in the retro watchdog counter.
- `impl/command-execution.md` §9 gains rules 6–7 (background voids budgets; persistent in-turn loop); `impl/verification.md` carries the background-watchdog sentence; the Codex flight entry gains the DSH Step-0 branch + four DSH red flags.
- DeepSeek token spend per slice drops: background-suite credits are the dominant cost line and the watchdog caps them.
