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
| compile check (`compileCmd`, tsc) | 6 min |
| gradle compile (focused, `--no-daemon`) | 12 min |
| stack-up / teardown (`up -d`, `down -v`) | 10 min |
| package/deploy build (§4.1 Stack-up) | 15 min |
| test suite (unit / API project) | 20 min |
| full backend suite | 30 min |
| playwright gate (API project only) | 20 min |

Cold dependency cache legitimately blows the FIRST budget → retry ONCE at 2× budget, log in `progress.txt`, never a third time.

## 2. Non-interactive always
Set once per spawn, inherited by every child command:
`CI=1` · `NO_COLOR=1` · `npm_config_yes=true` · `DEBIAN_FRONTEND=noninteractive` · `GIT_TERMINAL_PROMPT=0` · `GIT_EDITOR=true`

Per-tool flags — ADD them; never rewrite the command's semantics:

| Tool | Flags |
|---|---|
| maven | `-B -ntp` |
| gradle | `--console=plain --no-daemon` |
| npm / npx | `npx --yes`; `npm ci --no-audit --no-fund` |
| git | `commit -m "..."`; `merge <branch> --no-edit` — NEVER bare `merge`/`commit` (default editor blocks a headless shell forever) |
| vitest | ALWAYS `npx vitest run` — bare `vitest` opens watch mode and never exits |
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
| Background job killed by watchdog | same routing as its phase timeout (gate-5 strike / worker gate-3 strike / teardown WARN) — never "it just stopped" |
| Teardown (`down -v`) | WARN in `progress.txt`; never block the gate on teardown |

Record every timeout in `progress.txt`: `TIMEOUT <cmd> @<budget>s`.

## 5. workdir — never chdir inside a command
- Every command targeting a worktree/task dir runs with the runtime's **`workdir` parameter**. NEVER `Set-Location`/`cd` inside the command string (flight-stall postmortem 2026-08-19: in-command chdir with a relative path silently falls back to the MAIN tree on failure — wrong tree, wrong verdict, longer run).
- Runtime has no workdir param → `cd <abs> && pwd` chained with `&&` (never `;`) so a failed cd ABORTS the chain.

## 6. Long-running producers → log file, never a pipe-filter
- Redirect to a file, then read its tail after exit: `> run.log 2>&1` (POSIX) / `*> run.log` (PowerShell) / `cmd /c "<cmd> 2>&1"` (win32).
- NEVER pipe a long producer through `Out-String`, `Select-Object -Last`, `Tee-Object`, `head`, or `tail` — a pipe-filter emits NOTHING until the producer exits, so a slow-but-healthy build (tsc 1–3 min, gradle) is indistinguishable from a hang.
- PowerShell: `"cmd 2>&1"` as a QUOTED STRING is a literal, not a redirect (gradle-hang postmortem cause 1 — evidence logs were 30 bytes of command text). Use `*>&1` or the `cmd /c` wrapper.

## 7. npx hygiene
- Pre-check the binary exists (`Test-Path node_modules/.bin/<bin>`) or run install in that tree first; always `npx --yes`. A missing binary makes `npx` prompt "Need to install…?" (blocks stdin headless forever) or download silently for minutes.

## 8. Gradle daemon contention — NEVER `--stop` mid-flight
- Workers run `--no-daemon` (§2). NEVER `./gradlew --stop` during a flight — it sweeps machine-wide forked single-use daemons while OTHER parallel work is using them. Contention control is per-worktree isolation, not daemon killing. (An older postmortem recommended `--stop` as worker bootstrap — superseded, banned: this contract wins.)

## 9. Background jobs stay bounded — orchestrator watchdog (ADR 0036)

A runtime background flag (`run_in_background`, `Start-Job`, detached spawn) bypasses tool-level timeouts — the job is UNBOUNDED unless the orchestrator bounds it. The payments drain proved the cost: a wedged background suite ran silent 4.7h (log quiet, 0 XML, zombie 1.6GB JVM) until a human killed it. Every background/detached job therefore gets a watchdog:

1. **Bounded poll** — poll completion in a capped loop (attempts × interval = the phase budget). NEVER wait unbounded on a job handle.
2. **Hard deadline** — deadline reached → `job_kill`. A killed job is a TIMEOUT, not "finished": route per §4.
3. **Silence heuristic** — log last-write > 10 min while status = running → hung. Kill NOW, record `TIMEOUT <cmd> @<budget>s (silent)`, don't wait for the deadline.
4. **Orphan sweep after every kill** — the run's processes may survive the kill. Stop them by targeted PID (test JVMs etc., per §4.1/§4.1b) — NEVER `gradlew --stop` mid-flight (§8).
5. **Record** — log the kill in `progress.txt`; bump the flow-retro watchdog counter.
6. **Runtime background flags VOID timeout budgets (DSH, ADR 0038).** `run_in_background` ignores `timeoutMs` entirely — measured: a 60s sleep under a 20s budget ran 60.8s; a 900s sleep under a 720s budget completed. A background job's ONLY bound is this watchdog. Never "budget" a background job with a timeout number.
7. **The watchdog loop persists INSIDE the turn.** Bounded `job_output({ wait: true })` reads in a loop; track output GROWTH between reads; status `running` + zero growth > 10 min → kill + `TIMEOUT <cmd> @<budget>s (silent)`. A poll that returns `running` and then stops watching is NOT a watchdog — the payments wedge's last poll was 02:35; nothing read again until a human killed it at 07:12 (4h47m).

## 10. Turn-end markers + wait discipline
- Running turns (watchdog loops, poll sequences, long producers) end with `@at <phase> | done: | next:` — a status marker so the human can tell "working" from "dead".
- Any human-chokepoint STOP overrides it: the turn ends with `WAITING:` ALONE. `WAITING:` wins — never end a turn with both.
- Any wait > 60s → background the command + watchdog (§9). NEVER a foreground sleep loop (`sleep 60 && retry` × n) — a foreground sleep is invisible to the brakes and unbounded by the watchdog.

## 11. State-file write discipline (J)
- Before committing `.e2e-engineering/**` state artifacts, assert `git branch --show-current` = master — state lives on master; a state commit from a task/slice branch strands it.
- NEVER `cmd > state-file` redirect for a fallible command — a failed cmd still truncates the file and the flight later reads an empty "state". Write to a temp file (`cmd > .tmp 2>&1`), verify non-empty + exit code, THEN move into place.

## Red flags (stop)
- Emitting a shell command with no timeout wrapper and no runtime timeout (ADR 0033 — a hung shell is a runaway neither fan-out nor inline-STOP catches).
- `docker compose up` without `-d`, or attaching to logs to "watch it come up".
- Selecting `npm run build` without reading the script body (a watch/dev script blocks forever).
- `npx` without `--yes` / `npm_config_yes` — the "Ok to proceed?" stdin prompt hangs headless.
- In-command `Set-Location`/`cd` instead of the workdir param (failed chdir runs in the wrong tree).
- Piping a long producer through `Out-String` / `Select-Object -Last` / `head` / `tail` (no output until exit — hang invisible).
- Bare `git merge` / `git commit` (editor prompt blocks forever) — always `--no-edit` / `-m`, `GIT_EDITOR=true`.
- Bare `vitest` (watch mode never exits) — always `npx vitest run`.
- `./gradlew --stop` during a flight (machine-wide daemon sweep while parallel work exists).
- Wrapping a long-running/compile/test command in a repo tool filter or proxy (`rtk proxy gradlew`, output mangles on `git show branch:path`) — filters apply to OUTPUT READS only; a proxied compile can mangle verdicts or hang.
- Retrying a timed-out command unchanged more than once.
- Treating a gate-5 timeout as `blocked` (it is a gate-5 failure → `pending-qa`, ADR 0025).
- Leaving a detached stack up after the gate — teardown is still owed.
- Unbounded wait on a background job (no poll cap, no deadline, no `job_kill`) — a wedged job is invisible and billable forever (§9).
- Treating a background job's `timeoutMs` as a bound (DSH ignores it — the watchdog is the only brake; ADR 0038).
- Ending the watchdog poll loop when a read returns `running` (the loop persists in-turn — bounded wait + output-growth check; §9 rule 7).
- Leaving a killed run's orphan processes up — targeted-PID sweep after every kill (§9).
- Committing a full log as evidence — evidence = counts + ≤20-line excerpts; full logs stay gitignored on disk (ADR 0036).
- Ending a turn with both `@at …` and `WAITING:` (STOP ends `WAITING:`-alone; running ends `@at`-alone — §10).
- Foregrounding a wait > 60s instead of background + watchdog (§10).
- Committing `.e2e-engineering/**` state from a non-master branch (assert `git branch --show-current` = master first — §11).
- Redirecting a fallible command straight into a state file — temp file + verify non-empty, then move (§11).
