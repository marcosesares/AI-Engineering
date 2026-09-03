# Design spec — bug #35: build-system detection + explicit live-integration stack gate

**Date:** 2026-06-29
**Source issue:** GitHub #35 — "e2e: sub-agents need build system detection (Gradle vs Maven)"
**Status:** design APPROVED (Q1–Q3 + two refinements answered); spec written for fresh-session pickup. Next step = `superpowers:writing-plans`.
**Author flow:** superpowers brainstorming → (this spec) → writing-plans → implement.

---

## 1. Problem

`e2e-flight` sub-agents verify changes with a hardcoded/assumed `mvn compile`. On a Gradle project, `mvn` silently passes (no `pom.xml`) → false "build passes". Real compile needs `./gradlew compileJava`. Observed: the `extract-upload-validation-helper` sub-agent reported "build passes" via `mvn compile`; the actual Gradle build had never run — caught only at human verification.

Second, related gap surfaced by the issue author: at the **test gate** the agent should bring the app **up** (docker-compose) and run **all** tests — including the client's **independent Playwright API test project** — and loop fixing regressions. Today the stack lifecycle and the API-test-project discovery/run are not made explicit in the skill.

## 2. Decisions (from brainstorming Q&A)

| # | Question | Decision |
|---|----------|----------|
| Q1 | Source of `buildCmd` + stack-up sequence | **Hybrid.** Auto-detect the COMPILE cmd from repo files; read the STACK-UP rebuild + API-test-project location from `ARCHITECTURE.md §4.1`. §4.1 **wins** when present; detection is the fallback default. |
| Q2 | Red integration suite behavior | **Bounded loop → soft-fail.** Re-open the fix loop capped at gate-3's 3 strikes; still red after cap → record `## Gate 5 Failures` in `qa-signoff.md` → `pending-qa`. Never `blocked`, never unbounded. |
| Q3 | When the full stack rebuild runs | **Task-level gate only.** `down -v → quarkusBuild/<buildCmd> → up --force-recreate --build` runs ONCE at gate 5 after the slice DAG drains. Per-slice API tests (Step 3) hit the already-running shared stack per §4.1; no per-slice rebuild. |
| R1 | Runtime coverage | Two entry trees: `.claude/skills/e2e-flight/SKILL.md` (Claude) + `.agents/skills/e2e-flight/SKILL.md` (Codex / OpenCode / Cursor, via `AGENTS.md`). Cursor `.mdc` is a router only — no edit. **No deepseek target exists** in this repo (out of scope). |
| R2 | What "integration tests" means | The client's **independent Playwright API test project** (separate `playwright.config.*` / `package.json`, possibly sibling dir). Gate must FIND it (via §4.1 config path, else discover) and RUN it against the live `baseURL`. Not the app's UI. |

## 3. Scope — files to change

- `.claude/skills/e2e-flight/SKILL.md` — Step 2 detection, Step 3.2 inject, Step 3.4 use, gate-5 stack lifecycle.
- `.agents/skills/e2e-flight/SKILL.md` — same (Codex runtime; serial branch mode, no worktrees — mirror semantics, not exact wording).
- `skills/e2e-engineering/impl/verification.md` — gate 5: stack rebuild + API-test-project run + bounded loop.
- `skills/e2e-engineering/schemas/architecture.md` — §4.1: add `Build command` (optional override) + make `Stack-up (M1)` hold the explicit rebuild sequence + the independent API-test-project path/run-cmd.
- `docs/adr/0032-build-detection-and-live-integration-gate.md` — NEW. Records the decision; cross-refs ADR 0024 (Fork Y), 0025 (gate-5 soft fail), 0013 (flight reads ARCHITECTURE, never writes), 0020 (flight top-level).
- `dist/**` — regenerate via `npm run build`; `npm run validate` must pass.
- (Optional) `CONTEXT.md` glossary — `buildCmd`, `stack-up`, `API-test project`.

> Note: bug #35 cites `impl/e2e-flight/SKILL.md` — **stale path**. Flight is a top-level skill since ADR 0020.

## 4. Detailed design

### 4.1 Build-system detection — flight Step 2 (new sub-step "Build detection")

Resolve `buildCmd`, §4.1-wins-else-detect:
1. `ARCHITECTURE.md §4.1 Build command` present → use it verbatim.
2. else detect from repo root:
   - `pom.xml` → `mvn -q compile`
   - `build.gradle` or `build.gradle.kts` → gradle wrapper + `compileJava` — platform-aware wrapper: `./gradlew` (POSIX) / `gradlew.bat` (win32).
   - `package.json` → `npm run build`; if no `build` script → `npx tsc --noEmit`.
   - none of the above → **no compile command**; skip the compile check and WARN in `progress.txt`. (Do NOT fall back to `mvn` — that is the original bug.)
3. Cache `buildCmd` once for the spawn, alongside the existing Step-2 docker-env cache. Do not re-detect per slice.

### 4.2 Inject + use — Step 3.2 and Step 3.4

- **Step 3.2 (fan-out impl wave):** add `buildCmd` to the sub-agent injection manifest, so each worker compiles with the correct tool instead of assuming Maven.
- **Step 3.4 (lint + compile):** orchestrator runs the cached `buildCmd` (not a hardcoded build) before merge.

### 4.3 Live-integration stack gate — gate 5 (`verification.md` + flight Step 5)

After the DAG drains, before the full automated suite:
1. **Stack rebuild (docker-compose projects).** Run the `§4.1 Stack-up` recipe:
   `docker compose down -v` → `<§4.1 build, e.g. ./gradlew :backend:quarkusBuild>` → `docker compose up --force-recreate --build -d`.
   - §4.1 stack-up absent but a compose file exists → generic fallback: `down -v → <buildCmd> → up --force-recreate --build -d`.
   - No compose file → skip stack lifecycle (preserve current behavior); run suite as-is.
2. **Run the full automated suite** against the live stack: unit + the client's **independent Playwright API test project**.
   - Locate the API-test project via `§4.1 API/integration` config path; if absent, discover (`playwright.config.*` whose tests use the `request` fixture / target `baseURL`).
   - Run it in its own project dir (`npx playwright test`) against the live `baseURL`.
3. **Red → bounded fix loop** (gate-3, max 3 strikes): trace each failure to its story → re-dispatch the slice (or `systematic-debugging`). Re-run the affected suite.
4. **Still red after cap** → record each failure in `qa-signoff.md ## Gate 5 Failures`; set `verification-result.json` status `partial`; proceed to `pending-qa` (ADR 0025). Never `blocked`, never unbounded.
5. **Teardown:** `docker compose down -v` after the gate completes (leave no orphan stack).

### 4.4 Schema §4.1 extension (`schemas/architecture.md`)

Add to §4.1:
- `Build command:` — optional. The project's compile/build cmd; overrides flight auto-detection. Empty → flight auto-detects.
- Extend `Stack-up (M1):` to hold the **explicit rebuild sequence** gate 5 executes (the `down -v → build → up --force-recreate` line), not just prose about "how it comes up".
- Make the `API/integration` line explicit that it points to the **independent** API-test project (own config/package), with the run command.

Pre-impl (human phase) seeds these; flight READS, never writes (ADR 0013). Empty fields → flight uses detection fallbacks (no new stall beyond the existing API-bearing-task §4.1 gate-1 check).

## 5. Reconciliation with existing ADRs

- **ADR 0024 (Fork Y) — preserved.** UI stays Manual; no browser, no `/run`/`/verify`. ADR 0024 *already* mandates M1 ("API/integration tests hit a running docker-compose stack"). This work makes M1's stack lifecycle + API-test-project discovery **explicit** — it is not a new live-UI exercise.
- **ADR 0025 (gate-5 soft fail) — preserved.** Bounded loop then `pending-qa`; failures never flip a Task to `blocked`.
- **ADR 0013 — preserved.** Flight reads `ARCHITECTURE.md §4.1`, never writes it.
- **ADR 0020 — flight is top-level** (corrects the issue's stale path).

## 6. Out of scope (YAGNI)

- UI E2E automation (browser/POM) — stays Manual (Fork Y).
- Per-slice stack rebuilds.
- Build matrices beyond mvn / gradle / npm (sbt, make, bazel, …) — add later if a client needs them.
- A deepseek runtime target — separate task.

## 7. Open items for writing-plans / implementation

- Exact wording diffs for `.claude` vs `.agents` (Codex serial branch mode differs — mirror behavior, not text).
- Whether the bounded-loop counter is shared with the per-slice gate-3 counter or a separate task-level counter (lean: separate task-level 3-strike for the integration gate).
- CONTEXT.md glossary additions (optional).
- New ADR 0032 prose.

## 8. Fresh-session resume instructions

1. Read this spec end-to-end.
2. Re-read current code: `.claude/skills/e2e-flight/SKILL.md` (Steps 2, 3, 5), `.agents/skills/e2e-flight/SKILL.md`, `skills/e2e-engineering/impl/verification.md`, `skills/e2e-engineering/schemas/architecture.md` §4 (verify §4.1 line numbers — may have drifted).
3. Invoke `superpowers:writing-plans` to turn §3–§4 into a step-by-step implementation plan.
4. Implement; then `npm run build` + `npm run validate` (validate enforces dist freshness + markdown-link integrity — keep new links resolvable from each SKILL.md dir).
5. Dual-runtime parity: every behavior change lands in BOTH `.claude` and `.agents` flight SKILL.md.
6. Precedent for a near-identical change: the WAITING-signal fix (ADR 0031, same session) edited both SKILL.md trees + a shared file + added an ADR + rebuilt dist.
