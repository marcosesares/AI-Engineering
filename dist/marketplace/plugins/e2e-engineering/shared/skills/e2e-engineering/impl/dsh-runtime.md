# dsh-runtime — DeepSeek Harness runtime profile (ADR 0038)

Read ONCE at flight Step 0 when the runtime is DSH (DeepSeek Harness): the Step-0 tool sniff finds NO `spawn_agent`/`spawn_agents_on_csv`/`ToolSearch` but `subagent` + `pwsh` + `job_*` + `list_agents` ARE present. That is NOT `fanout-unavailable` — adopt the mappings below and keep flying. The payments drain (waves 11–16) ran on DSH exactly this way.

## Tool mapping (DSH)

| Skill concept | DSH equivalent |
|---|---|
| `spawn_agents_on_csv` parallel impl/review wave | N× `tools.subagent({ run_in_background: true })` dispatched in ONE `run_code` program — all start concurrently; completion notices arrive as inbox messages ("Background subagent <id> finished") |
| `spawn_agent` + `wait_agent` | `subagent` background + notice; `job_output({ wait: true, timeout_ms })` for bounded waits; `list_agents` status (`running`/`idle`/`ready`) |
| `Agent` + `EnterWorktree` | DSH subagents share the workspace filesystem — serial mode needs no worktree; parallel isolation via `git worktree add` (pwsh). Worker git commits are branch-visible (probe-verified) |
| `job_kill` / orphan sweep | `job_kill` + targeted-PID pwsh sweep (never `gradlew --stop`) |
| OS timeout wrapper | foreground `pwsh timeoutMs` — NATIVE, enforced (kills at deadline, `timedOut: true`). Background: NO timeout applies — watchdog only |
| interrupt stuck reviewer/worker | `interrupt_agent` / `job_kill`; then `send_message` for a follow-up turn |
| review/verify waves (initial, re-review, finding-verifier) | `workflow` tool: parallel `agent()` stages, per-agent `model` override, `opts.schema`-validated results returned pre-merged; child failure → `null` → filter + record gap in `notes` |

## The two background-job rules (measured, not theoretical)

1. **Background flags VOID timeout budgets.** DSH measured: a 60s sleep under a 20s `timeoutMs` budget ran 60.8s and completed; a 900s sleep under a 720s budget completed after 900s. `timeoutMs` on a background job is DECORATIVE. Never bound a background job with a timeout number — the watchdog is its only bound. (The payments gate-5 half-A suite had a 30-min budget and wedged 4h47m.)
2. **The watchdog loop persists INSIDE the turn.** Bounded `job_output({ wait: true, timeout_ms: ≤90s })` reads in a persistent loop; compare output GROWTH between reads; status `running` + zero growth > 10 min → `job_kill` + record `TIMEOUT <cmd> @<budget>s (silent)`. Hard deadline → `job_kill`. A poll that returns "running" and then stops watching is NOT a watchdog — the wedge's last poll was 02:35; nothing read again until a human killed it at 07:12.

## Budgets (foreground `timeoutMs`; background = watchdog deadline)

| Class | Foreground | Background watchdog |
|---|---|---|
| inspect/read/tail | 30–60s | — |
| lint | 3m | — |
| compile / self-compile | 6m (observed ≤1.5m) | — |
| focused gradle test | 12m (observed 2–4m) | poll 60–90s / silence 10m |
| stack-up / package build | 10m / 15m | deadline 15m / 20m |
| full backend suite | 30m | REQUIRED bg: poll 60–90s, silence 10m, deadline 45m |
| playwright API gate | 20m (single file 5m) | deadline 30m |
| teardown | 10m | — |

Never exceed the table — bigger ≠ safer (the drain's 12–13m/30m values matched these lines; the wedge was unboundedness, not size). Cold cache: ONE 2× retry, logged.

## Review/verify tiers (ADR 0039)

| Tier | Slots | Budget |
|---|---|---|
| T0 non-thinking cheap | finding-verifier, mechanical review slots, fan-in merge | verifier ≤8 calls |
| T1 thinking medium | judgment reviewers (backend-architect, dba, frontend-reviewer, test-reviewer initial waves) | ≤15 initial / ≤8 re-review |

Impl workers stay background `subagent` with prompt-discipline contracts (T1 discipline via the brief) — no model knob exists there. T2 reviewer reuse retired (ADR 0039).

**Degrade, don't stall:** workflow unavailable (Step-0 probe) or failing → review/verify waves = background `subagent` dispatch with prompt-discipline tiers. Fan-out capability is essential; model routing is an optimization.

## Step-0 probes (DSH replaces the Codex/Claude probe set)

1. **Fan-out probe** — spawn a trivial background subagent ("return OK"), confirm the notice arrives → fan-out available.
2. **Worker-change probe** — probe worker runs `git rev-parse` + `git status` in the repo via pwsh → shared FS, commits visible (probe-verified).
3. **Bounded-shell probe** — foreground pwsh `Start-Sleep 45` under `timeoutMs: 20000` → expect kill ~20s, `timedOut: true`. Not killed → treat as unbounded-shell stall.
4. **Write-capability probe (DSH-only)** — create + delete a temp file at the task root. Denied → `<e2e-stall reason="sandbox-write-denied" />` + EXIT — a sandbox policy denial is FINAL, never retry/loop.
5. **Workflow-availability probe** — run a trivial workflow script (one `agent()`, one-word reply, `schema`-validated). Success → workflow review waves active (ADR 0039); failure → subagent review fallback, no stall.
6. **Concurrency budget probe** — read free RAM + CPU count via pwsh; persist `resume.json` `concurrency` cap (concurrent `subagent` dispatches + workflow parallelism). Default when unreadable: 2 workers / 4 reviewers.

## Sandbox modes

- read-only → PowerShell ConstrainedLanguage: .NET statics, `Add-Type`, COM, named-pipe stdout capture FAIL; cmdlets + core types work. Writes are denied — denial is policy, not transient.
- workspace-write → FullLanguage; flight work (git commit, build outputs) needs this at minimum.
- Approval prompts disabled → escalation requests are auto-rejected: do NOT request `sandbox_permissions`; stall instead.

## Dispatch notes

- Subagents receive the prompt ALWAYS (empty-message bootstrap stays fallback-only — tdd.md §0).
- Workers = clean-context `subagent` (self-contained manifest prompt); reviewers = clean-context `subagent` (review-bundle path, never paste diffs/logs — DSH truncates long tool output to a tail + spillPath; read tails).
- `list_agents` `running`/`idle`/`ready` is the worker-stall signal — a zero-commit wave with workers alive = throughput stall → chunk-driver degrade, never `worker-changes-unavailable`.
- `workflow` IS the review/verify dispatch (ADR 0039): foreground + blocking — pre-bound wave size (2–4 agents) + budgets in prompts + schema-required returns. Never an unbounded workflow script.

## Model efficiency (DeepSeek v4, reasoning-effort max)

- Thinking tokens dominate cost — the skill's laws stay law: caveman-ultra artifacts, compact JSON manifests only, evidence pointers not logs, offset/limit reads.
- Prefer non-busy `job_output({ wait: true })` over rapid poll loops (fewer tool calls = fewer reasoning cycles).
- Use goal tools (`create_goal`/`update_goal`) for the one-Task-per-spawn objective + resume (the drain's resume used goal rounds).
- Orchestrator continuity: `subagent_fork` for context-inheriting follow-ups; never re-derive state.
