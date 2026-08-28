# Bounded background jobs, evidence hygiene, and gate-5 execution discipline

**Status:** accepted — refines ADR 0033 (bounded command execution: extends the contract to background/detached jobs), ADR 0034 (gate-5 checkpoints: adds the watchdog that makes detached steps survivable), ADR 0027 (retro counters: adds watchdog/degrade/smoke tallies). Amends gate-5 practice only; slice review semantics (ADR 0035) untouched.

The payments-monetization drain paid for four gate-5 classes of friction: a background suite wedged for 4.7 hours with no watchdog to kill it (the single worst token/credit cost of the session), ~1.5MB of full logs committed as evidence, three monolithic-suite OOMs caused by Gradle 9's 512MB default test-fork heap, and several fix rounds burned on stale JUnit XML left behind by failed compiles. A fifth gap was timing: carrier-written Playwright specs ran blind until the final gate, where stale 200-vs-201 expectations and db-cleanup bugs surfaced all at once. This ADR closes all five with generic rules; the repo-specific values that resolved them stay in `ARCHITECTURE.md §4.1b`.

## Context

- **Background flags bypass tool timeouts.** `run_in_background` / `Start-Job` start a job that no tool-level timeout governs. The gate-5 half-A run wedged: log silent, 0 XML, a zombie 1.6GB JVM holding the port — and only a human message triggered the kill. The bounded-shell contract (ADR 0033) covers foreground commands; it had nothing to say about background ones.
- **A killed run is not a dead run.** After the kill, the orphaned test-JVM processes survived and kept the port; cleanup had to be targeted by PID, not `gradlew --stop` (banned mid-flight, command-execution §8).
- **Committed logs are dead weight.** `*.log` is gitignored, so logs cost nothing in git — but full logs WERE committed as `evidence/*.log.txt` across waves (two 179KB copies; removed in bf095e3). The durable record is XML counts + `progress.txt` + evidence READMEs.
- **Gradle 9's default test-fork heap is 512MB** and OOMs a Quarkus suite at ~87 classes; `GRADLE_OPTS` raises the daemon heap only, not the fork. The fix was an init script raising `Test.maxHeapSize` to 3g.
- **A failed compile leaves the previous JUnit XML behind.** Verdicts read from XML without checking `BUILD SUCCESSFUL` in the log reported phantom results for several fix rounds.
- **Carrier-written Playwright specs were blind.** Workers wrote API specs without running them in-slice (the stack serves merged code only), so expectation bugs accumulated until the single gate-5 Playwright step.
- **Repo-specific traps already live in the repo.** The drain committed its machine-specific rules to `ARCHITECTURE.md §4.1b` (fork heap, stale-XML discipline, per-run ports, playwright node_modules fallback, UTC-only date windows, orphaned-JVM cleanup). The skill's Step-2 compileCmd resolution reads §4.1 but had no hook for §4.1b.

## Decision

1. **Background-job watchdog.** Every detached/background job gets an orchestrator watchdog, runtime-agnostic: (a) poll completion in a BOUNDED loop (capped attempts × interval = the phase budget) — never an unbounded wait; (b) a hard deadline → `job_kill`; (c) a **silence heuristic** — log last-write > 10 min while status = running → treat as hung, kill, record `TIMEOUT <cmd> @<budget>s (silent)`; (d) after every kill, sweep the run's orphan processes by targeted PID (test JVMs etc., per §4.1/§4.1b) — never `gradlew --stop`. A killed job routes exactly like a phase timeout in the command-execution §4 outcome table (gate-5 phase → strike; worker test → gate-3 strike; teardown → WARN). The kill is logged in `progress.txt` and bumps the retro counter.
2. **Evidence hygiene.** Committed evidence = counts + ≤20-line excerpts. Full logs stay on disk, gitignored (`*.log`), and are deleted at worktree removal. `evidencePaths[]` point to counts/excerpt files; a `slice-result`/`review-result`/`verification-result` that ships a full log is a red flag.
3. **Test-fork heap rule (gate-5 JVM suites).** Suite near/over ~80 test classes → check the test-fork heap. §4.1/§4.1b sets one → use it verbatim. Else prescribe an init script (`--init-script heap.init.gradle`: `allprojects { tasks.withType(Test).configureEach { maxHeapSize = "3g" } }`). `GRADLE_OPTS` does NOT affect the test fork. Memory-constrained machine → split into class-list halves (distinct ports; sum the XML; each half skipped = 0).
4. **Stale-XML verdict discipline.** Check `BUILD SUCCESSFUL` in the log BEFORE reading `build/test-results` XML — a failed compile leaves the previous XML behind. Report tests/failures/errors/skipped; skipped must be 0.
5. **Carrier-level API smoke.** After merging a carrier that added/changed Playwright API specs: rebuild the stack per §4.1 Stack-up and run ONLY that carrier's spec files (bounded, API project, single-file runs). Red → fix in-slice before the next wave dispatches (Gate 3 applies). `ARCHITECTURE.md §4.1` declaring the stack rebuild too heavy → WARN in `progress.txt` + defer to gate 5. The final gate-5 full suite is unchanged — the smoke is early signal, not a replacement gate.
6. **§4.1b is the first-class hook for repo-specific execution rules.** Flight Step 2 reads `ARCHITECTURE.md §4.1b` (test-execution amendments) ONCE alongside §4.1; its values (fork heap, ports, verdict discipline, runner quirks) win over the generic budgets in this ADR and in command-execution. The skill stays generic; the repo carries the specifics.

## Considered Options

- **OS-level timeout wrapping for background jobs** (`timeout <secs>` around the background command) — rejected: an OS timeout kills the shell process but cannot see a wedged JVM that holds the port while its executor hangs; the watchdog (poll + deadline + silence + orphan sweep) is the only brake that observes the actual symptom.
- **Per-slice stack rebuilds to run specs in-slice** — rejected: rebuild cost multiplies by slice count and the stack still cannot serve unmerged worker code; the carrier-level smoke is the earliest point the merged code is actually running.
- **Reading XML counts only, dropping the log check** — rejected: that is exactly the stale-XML trap; the log check is one bounded tail read and prevents phantom green verdicts.
- **Hardcoding the 3g fork-heap value in the skill** — rejected: machine-specific; §4.1b owns the value, the skill owns the detection rule.
- **A preflight check for `*.log` gitignore** — rejected as a fail-closed gate: log hygiene is a discipline rule, not a runtime-capability probe; enforcing it as a red flag keeps preflight at three checks.

## Consequences

- Gate-5 wall-clock cost becomes bounded by construction: a hung background phase is killed at the silence threshold (10 min) instead of burning hours; every kill lands in the retro as a counter, so the failure mode stays visible.
- The carrier smoke adds one stack rebuild per API-touching carrier. Amortized against a gate-5 3-strike loop over a full suite, this is a net win; projects that cannot afford it opt out via §4.1 and carry the blind-spec risk to the gate.
- `flow-retro.md` gains three counters: watchdog kills/hangs, chunk-driver degrade waves (ADR 0037), and carrier API smokes (red/green).
- Evidence artifacts shrink to counts + excerpts; anything larger is a red flag at fan-in and gate 5.
- `impl/command-execution.md` gains §9 (background jobs stay bounded); `impl/verification.md` gains the fork-heap, stale-XML, carrier-smoke, and watchdog rules; both flight entry points carry the new red flags.

## Amendment (2026-08-27 — batched carrier smoke + stack ownership)

Accepted — refines this ADR's carrier smoke. Evidence: a measured 2026-08 DSH flight rebuilt the stack ~8 times where 3 would have covered the work (stack-up 10m + package build 15m, bounded, each).

1. **Carrier smoke runs once per wave.** After the wave's merges: ONE stack-up per §4.1 Stack-up, then run EVERY spec file changed by that wave's carriers in that session (bounded, API project). Red spec → a REPAIR SLICE on the task branch (fresh worker + Gate 3) targeting the red spec's code, merged before the wave closes. Invariant: **no wave closes with a red smoke.** Detection anchor moves merge-time → wave-close; it stays pre-gate-5, which is the ADR's purpose (blind-written specs shipping stale expectations + db-cleanup bugs).
2. **Stack ownership.** The flight owns the compose stack during smoke/gate-5: `down -v → package build → up --force-recreate --build -d` runs UNCONDITIONALLY (bounded + log-to-file per ADR 0033). The flight does not probe for foreign stacks and does not ask — the entry-point doc (Task 5) carries the user-facing line: the flight tears down and rebuilds the stack; don't keep dev work in a running compose stack during a flight.
3. **§4.1 heavy-rebuild defer WARN unchanged** (smoke deferred to gate 5 when §4.1 declares the rebuild too heavy).

