# Plan — skill/pipeline fixes from `fix-ac8-concurrent-create-idempotency` (I1–I14)

Source: `.e2e-engineering/tasks/fix-ac8-concurrent-create-idempotency/reports/session-painpoints-postmortem-20260901.md`
(+ `flow-retro.md` §Skill-improvement candidates).

Scope: skill-file guardrails only. The AC8 code fix (`342007c` row-lock serialization +
`4c157f4` entitlement-lock 403 reconcile) is merged to master and QA-approved — no production
code changes here.

## Verified grounding

- Harness split: `.agents/skills/**` = DSH/Reasonix entry (`reasonix.toml`
  `default_model="deepseek"`, `[permissions] mode="allow"`, `allow_dynamic_bash=true`);
  `skills/e2e-engineering/**` = shared canonical root read by both the claude.ai wrapper and the
  DSH entry (e2e-flight Step 0 probes `sharedSkillsRoot = skills/e2e-engineering`). DSH-specific
  mechanics live in `impl/dsh-runtime.md`.
- Both trees are per-harness forks → edit both with ADAPTED phrasing (not verbatim mirrors).

## Decisions (locked via grill-with-docs)

- **K term anchor:** idempotency umbrella, two sub-cases — (a) retry-in-flight of the same logical
  request, (b) concurrent duplicate of a distinct business event. Create/duplicate-guard tasks must
  pick one and state the discriminator (idempotency key / request id / business key) in the PRD, or
  flag it as an explicit decision BEFORE implementation.
- **Gate-5 strike policy:** a strike counts against the clean-env re-run only. Infra signatures
  (mass skip, `password authentication failed`, `QuarkusBindException`) trigger the env preflight
  first; diagnosis is a prerequisite, never a strike waiver.
- **Status markers:** running turns end with `@at <phase> | done: | next:`; any human-chokepoint STOP
  overrides it and ends with `WAITING:` alone. `WAITING:` wins; no turn ends with both.
- **Subagent silence (F):** worker writes a mandatory untracked `<slice>.heartbeat` at each semantic
  commit point; orchestrator liveness snapshot reads heartbeat + `git status --porcelain` + untracked
  mtimes. 15-min stalled_warning = advisory snapshot-check (no kill); 30-min no-disk-change = hard
  kill + stranded-file record.
- **Hard-kill scope:** recycle the worker first (matches the existing WATCHDOG/WORKER RECYCLE
  pattern); a repeated hard-kill on the same slice pauses the flight for a human.
- **Serial mode (A):** Tier-2 probe is the oracle — spawn one disposable write worker with the same
  `write_paths`; if it lacks `bash`/writer, record `resume.json mode: serial`. Never preset.
- **DSH full-access (Q8b):** `mode="allow"` + `allow_dynamic_bash=true` + workspace-root confinement
  already provide the YOLO/Auto writer posture; the probe still verifies `bash` actually reaches the
  worker (permissions config cannot override runtime worker-stripping).

## Edits

### `skills/e2e-engineering/` (canonical root)

1. `impl/dsh-runtime.md`
   - Replace Step-0 probe 4 with the two-tier write probe (permission-mode read before write; Tier-2
     disposable write worker; `bash`-loss → serial mode; hard `sandbox-write-denied` stall only on
     repeated policy denial after mode confirmed allow).
   - §Dispatch: invocation cheat-sheet (`subagent` takes `prompt`+`write_paths`, no `name`;
     reviewers read-only, no `write_paths`).
   - Watchdog: D7/F2 subagent silence thresholds + heartbeat snapshot.
   - Turn-end `@at` + heartbeat rule for DSH long producers.
2. `impl/command-execution.md`
   - `@at`/`WAITING:` precedence; any wait >60s = background + watchdog (never a foreground sleep
     loop).
   - J: assert `git branch --show-current = master` before `.e2e-engineering/**` commits; never
     `cmd > state-file` for a fallible command (temp file + verify non-empty).
3. `impl/tdd.md`
   - F2 heartbeat write at semantic commit points; G red-proof validity (assertion ≠ crash); H
     changed-approach on second failure; I incremental commits + stranded-file kill protocol.
4. `impl/systematic-debugging.md`
   - H: re-dispatch must change at least one variable (repro strategy/env/scope); never the same
     brief unchanged.
5. `impl/verification.md`
   - C gate-5 env preflight (`docker compose ls` worktree-scoped projects + orphan DevServices/
     testcontainers sweep); D4 clean-env strike semantics; L QA branch-ownership +
     `npm run test:api`-only.
6. `pre-impl/grill-with-docs.md`
   - K idempotency-umbrella checklist item (create/duplicate-guard tasks).

### `.agents/skills/` (DSH entry, adapted phrasing)

7. `e2e-flight/SKILL.md`
   - Step 0: two-tier probe routing for DSH + serial-mode record.
   - Step 3 + Step 5: dispatch shapes, gate-5 env preflight, clean-env strike, QA branch-ownership.
   - Red-flags: red-proof validity, changed-approach, incremental commits, stranded-file protocol,
     heartbeat liveness.
8. `e2e-engineering/SKILL.md`
   - `@at`/`WAITING:` turn-end invariant.
9. `grill-with-docs/SKILL.md`
   - K one-line pointer (idempotency umbrella).

## Verification

1. Structural grep: every decision-row maps to a concrete edit; no rule left as "proposed" only.
2. Re-read changed regions for probe numbering, ADR cross-refs, red-flag symmetry.
3. `git diff` — skill markdown only; no production code, no state artifacts.
4. No compile/test applies (markdown rules); note unverified: runtime-level behavior needs a live
   flight to observe.
