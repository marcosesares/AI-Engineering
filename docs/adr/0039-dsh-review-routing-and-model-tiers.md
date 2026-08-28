# DSH review-wave routing and model tiers

**Status:** accepted — refines ADR 0038 (DSH runtime profile: adds the `workflow` tool as the review/verify dispatch surface with per-agent model routing), ADR 0035 (review-wave mechanics: schema-validated pre-merged fan-in + tier routing; the convergence loop itself is amended separately — see its 2026-08-27 amendment). Amends dispatch mechanics only; gates 1/2/3/5 and the finding state machine unchanged.

A measured 2026-08 DSH flight: 67 child agents — 55 of them reviewers — against a token profile where reasoning was 8.2M (52% of model output). Two DSH facts make that spend attackable: `subagent` exposes NO model knob, while the `workflow` tool exposes a per-agent `model` override that is enforced (probe 2026-08-27: a bogus override made the child fail loudly rather than silently no-op). Review waves are bounded (≤15 calls initial / ≤8 re-review / ≤8 verifier) and their results are structured — the two properties `workflow` is built for. Impl workers are long, unbounded-turn jobs and must stay on background `subagent`.

## Context

- **Reasoning tax is per-model.** DeepSeek's reasoning dominates output cost; prompt discipline (terse JSON, reply caps) shrinks assistant/output tokens but not reasoning. Only model routing attacks the reasoning share.
- **Review waves are bounded + structured.** Initial ≤15 tool calls, re-review ≤8, verifier ≤8 (ADR 0035/0037); every wave returns `findings[]` JSON. `workflow` returns schema-validated, pre-merged results — the orchestrator's per-reviewer fan-in cost drops to near zero.
- **`workflow` is foreground + ephemeral.** The tool call blocks the orchestrator until the script finishes, and its agents cannot be continued via `send_message`. T2-style same-agent reuse is therefore incompatible with workflow-dispatched waves.
- **The stuck-reviewer protocol already exists** (ADR 0035: re-dispatch once with halved scope, then proceed with the rest). Inside a workflow script, a failed child resolves `null` — the same protocol becomes script logic.

## Decision

1. **Review/verify waves = `workflow` tool.** Initial review, re-review, and finding-verifier waves dispatch as workflow scripts: parallel `agent()` stages, per-agent `model` override, `opts.schema`-validated results returned pre-merged. Stuck-reviewer protocol lives in-script: a child failure resolves `null` → filter + record the gap in the wave `notes` (the ADR 0035 re-dispatch-once rule applies to the workflow stage before proceeding). Waves are FOREGROUND and blocking: pre-bound in prompts (≤15 initial / ≤8 re-review / ≤8 verifier), wave size 2–4 agents, schema-required returns.
2. **Tier table.** `T0` non-thinking cheap: finding-verifier slots, mechanical review slots, fan-in merge. `T1` thinking medium: judgment reviewers (backend-architect, dba, frontend-reviewer, test-reviewer initial waves). Impl workers: background `subagent`, prompt-discipline only (no model knob exists) — T1 discipline (commit-per-boundary, JSON-only manifests, evidence-pointer returns) rides the brief. **T2 reuse retired**: same-agent follow-up re-review rejected — marginal over ADR 0037's halved re-review, self-confirmation smell, incompatible with ephemeral workflow agents.
3. **Degrade, don't stall.** Step-0 probe adds workflow availability (one trivial script). Absent/failing → review/verify waves fall back to background `subagent` dispatch with prompt-discipline tiers (existing ADR 0038 mapping). Fan-out capability is essential; model routing is an optimization.
4. **Reasoning-cost claim is a hypothesis.** Expected reasoning reduction ~-50% rides on model routing; prompt-discipline-only portions reduce assistant/output tokens. `session-cost.ps1` (diagnostics) is the one-time check after the next flight vs the 8.2M/7.4M/8.5M baseline. No per-flight cost telemetry is added.

## Considered Options

- **Subagent-only review with prompt-discipline tiers** — rejected: no model knob; reasoning untouched.
- **Workflow for impl workers** — rejected: foreground blocks the orchestrator for worker-length durations.
- **T2 reviewer reuse (same agent continued via follow-up)** — rejected per decision 2.
- **Per-agent harness-settings edits** — rejected: routing is a skill policy, never user settings.

## Consequences

- Workflow wedge risk: a foreground call cannot be `job_kill`ed mid-script. Bounded by prompt budgets + 2–4-agent waves + harness workflow caps; the degrade rule (decision 3) is the escape hatch.
- Reviewer fan-in cost ≈ 0 (schema-validated pre-merged results); per-reviewer orchestrator context spend disappears.
- Tiers are unverifiable off-DSH; the Codex/Claude entries keep their existing review dispatch untouched.
- `impl/dsh-runtime.md` gains the workflow mapping + tier table + two probes (Task 7); the flight entry gains the workflow-wave Step-3.3 mechanics (Task 5).
