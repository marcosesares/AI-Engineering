# command-execution — bounded, non-interactive shell contract

> **ADR 0033.** Every shell command flight or a sub-agent runs MUST be **bounded** (kills itself), **non-interactive** (never reads stdin), and **self-terminating** (returns control). A command that blocks forever is a runaway — the forced-fan-out / inline-STOP brakes (ADR 0022) do not see it. Applies to compile, package build, stack-up, lint, and test runs, in EVERY runtime.

## Why it lives here
Claude Code's shell tool auto-timeouts and can background; Codex / OpenCode / Cursor run the literal string unbounded. A skill that emits a naked foreground command is portable by accident only. The contract is the skill's job, not the runtime's.

## 1. Bound every command
Wrap with an OS-level timeout — not a tool-level hope.
- POSIX: `timeout <secs> <cmd>` (exit 124 = timed out).
- PowerShell / win32: `$j = Start-Job { <cmd> }; Wait-Job $j -Timeout <secs>; if ($j.State -ne 'Completed') { Stop-Job $j }`.
- Runtime offers a native per-command timeout → use it INSTEAD. Double-wrapped is fine; unbounded is not.
- **Runtime cap below the budget** (e.g. Claude Code's shell maxes at 10 min, under the 15-min package build) → do NOT shorten the budget and do NOT drop the bound. Start the command detached (runtime background mechanism, or `nohup … &` / `Start-Job`) writing to a log file, then poll completion in a BOUNDED loop (capped attempts × interval = the budget) and read the log. Same outcome routing on expiry.

**Budgets** (defaults; `ARCHITECTURE.md §4.1` may state a larger explicit value — that wins):

| Command class | Budget |
|---|---|
| lint | 3 min |
| compile check (`compileCmd`) | 5 min |
| stack-up / teardown (`up -d`, `down -v`) | 10 min |
| package/deploy build (§4.1 Stack-up) | 15 min |
| test suite (unit / API project) | 20 min |

Cold dependency cache legitimately blows the FIRST budget → retry ONCE at 2× budget, log in `progress.txt`, never a third time.

## 2. Non-interactive always
Set once per spawn, inherited by every child command:
`CI=1` · `NO_COLOR=1` · `npm_config_yes=true` · `DEBIAN_FRONTEND=noninteractive` · `GIT_TERMINAL_PROMPT=0`

Per-tool flags — ADD them; never rewrite the command's semantics:

| Tool | Flags |
|---|---|
| maven | `-B -ntp` |
| gradle | `--console=plain --no-daemon` |
| npm / npx | `npx --yes`; `npm ci --no-audit --no-fund` |
| docker compose | `--ansi never`; `up` ALWAYS `-d` |
| playwright | `--reporter=line`; NEVER `--ui` / `--headed` / `--watch` / `--debug` |

## 3. Never foreground a long-lived command
Anything that serves, watches, tails, or waits is NOT a build/test command. Reject these patterns — in the command AND in the npm-script body it resolves to:

`up` without `-d` · `--watch` / `-w` / `--ui` / `--headed` / `--debug` · `dev` / `serve` / `start` / `preview` · `logs -f` / `tail -f` / `attach` / `exec -it` / `run -it`

**Probe the script, don't run it.** Before selecting `npm run <script>`, READ that script's body in `package.json`. Matches a reject pattern → not a compile command → fall through to the next detection rule. Never "run it and see" — that IS the hang.

Need a background service (the gate-5 stack) → start it detached (`-d`), then poll readiness with a BOUNDED loop (health endpoint / `compose ps` status, capped attempts). Never by attaching.

## 4. Timeout → outcome (never silently retry, never hang)

| Where | A timeout means |
|---|---|
| Step 0 probe — runtime cannot bound a command at all | `<e2e-stall reason="unbounded-shell — runtime cannot time-box commands" />` + EXIT |
| Worker compile / test (tdd) | failed fix → GATE 3 strike; `findings[]` `type:blocker` carrying cmd + budget |
| Orchestrator lint/compile (flight Step 3.4) | compile failure → normal pre-merge reconcile; cap reached → slice `blocked` |
| Gate-5 stack-up or suite | gate-5 failure → `gate5Strikes` + `gate5FailureIds[]` → `partial` → `pending-qa` (ADR 0025). NOT a stall, NOT `blocked` |
| Teardown (`down -v`) | WARN in `progress.txt`; never block the gate on teardown |

Record every timeout in `progress.txt`: `TIMEOUT <cmd> @<budget>s`.

## Red flags (stop)
- Emitting a shell command with no timeout wrapper and no runtime timeout (ADR 0033 — a hung shell is a runaway neither fan-out nor inline-STOP catches).
- `docker compose up` without `-d`, or attaching to logs to "watch it come up".
- Selecting `npm run build` without reading the script body (a watch/dev script blocks forever).
- `npx` without `--yes` / `npm_config_yes` — the "Ok to proceed?" stdin prompt hangs headless.
- Retrying a timed-out command unchanged more than once.
- Treating a gate-5 timeout as `blocked` (it is a gate-5 failure → `pending-qa`, ADR 0025).
- Leaving a detached stack up after the gate — teardown is still owed.
