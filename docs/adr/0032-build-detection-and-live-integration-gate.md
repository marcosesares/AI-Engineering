# Build-system detection + explicit live-integration stack gate

**Status:** accepted — extends ADR 0024 (Fork Y, M1 API/integration on a live stack), ADR 0025 (Gate 5 soft-fail → pending-qa), ADR 0013 (flight reads ARCHITECTURE.md, never writes), ADR 0020 (flight is a top-level skill).

## Problem

`e2e-flight` sub-agents verified changes with an assumed `mvn compile`. On a Gradle project `mvn` silently passes (no `pom.xml`) → false "build passes". Observed: the `extract-upload-validation-helper` worker reported "build passes" via `mvn compile` while the real Gradle build had never run — caught only at human verification.

Second gap: at the test gate the agent should bring the app **up** (docker-compose) and run the client's **independent** Playwright API project, looping fixes on regressions. The stack lifecycle and the API-project discovery/run were never explicit, so M1 (ADR 0024) was under-specified. The main consumer (UniVerse.Academy) exposes BOTH a `chromium` UI project and an `api` project in one `playwright.config.ts`; a bare `playwright test` would launch the browser, breaking "UI stays Manual". Its backend `Dockerfile.jvm` copies `build/quarkus-app/**`, produced by `quarkusBuild` (a package build), NOT by `compileJava` (a compile-only check) — so the compile command and the stack/package build are genuinely different commands.

## Decision

1. **Compile command — §4.1-wins-else-detect (compile ONLY).** Flight resolves `compileCmd` once per spawn (Step 2) for the fast pre-merge compile check:
   - `ARCHITECTURE.md §4.1 Compile command` present → use verbatim.
   - else detect: `pom.xml`→`mvn -q compile`; `build.gradle`(`.kts`)→gradle wrapper + `compileJava`, shell-aware (`./gradlew compileJava` POSIX / `.\gradlew.bat compileJava` PowerShell); `package.json`→`npm run build` (no `build` script → `npx tsc --noEmit`).
   - none → no compile command; skip the compile check + WARN in `progress.txt`. **Never fall back to `mvn`** (the bug).
   `compileCmd` is injected to each impl worker (Step 3.2) and used by the orchestrator compile check (Step 3.4). It is COMPILE-ONLY — it never feeds the stack rebuild.

2. **Package/stack build is separate and §4.1-owned.** The build that produces the docker deploy artifact (e.g. `quarkusBuild`) lives ONLY in `§4.1 Stack-up (M1)`. The generic gate-5 fallback NEVER substitutes `compileCmd` as the package build — for a Dockerfile that copies a pre-built artifact and no seeded Stack-up, flight WARNs and skips the host build rather than generating a broken image.

3. **Live-integration stack gate — Gate 5** (verification.md). After the DAG drains:
   - **Stack rebuild** via `§4.1 Stack-up (M1)`: `down -v → <package build> → up --force-recreate --build -d` (ONCE, not per slice). Fallbacks: compose+safe → generic `down -v → up --force-recreate --build -d`; compose+artifact-copying-Dockerfile+no Stack-up → WARN + bring up as-is; no compose → skip.
   - **Run the API project ONLY:** the client's independent Playwright project, via the `§4.1 API/integration` API-only cmd (`npm run test:api` / `--project <api>`), else discovered (no-browser/`request` project) and run with `--project`. NEVER bare `playwright test`.
   - **Red → durable bounded loop** (max 3 strikes, SEPARATE from per-slice Gate-3). Counter persisted in `verification-result.json` (`gate5Strikes`, `gate5FailureIds[]`) + `progress.txt`; a resumed flight continues, never resets. Still red → status `partial`, `## Gate 5 Failures` in `qa-signoff.md`, `pending-qa` (ADR 0025). Never `blocked`, never unbounded.
   - **Teardown:** `docker compose down -v` after the gate.

4. **Dual-runtime.** Both `.claude/skills/e2e-flight/SKILL.md` and `.agents/skills/e2e-flight/SKILL.md` carry the behavior; `.agents` mirrors semantics in Codex serial/parallel branch mode (`compileCmd` in the spawn manifest). Shared recipe in `skills/e2e-engineering/impl/verification.md`; contract fields in `schemas/architecture.md §4.1` + `schemas/verification-result.json.md`.

5. **Consumer backfill.** Flight reads §4.1 and never writes it (ADR 0013). The main consumer's `ARCHITECTURE.md §4.1` is backfilled (human-phase write) with the concrete `Compile command`, `Stack-up`, and API-only `API/integration` values so flight uses real commands, not weak discovery.

## Considered Options

- **One `buildCmd` for both compile check and stack rebuild** — rejected: the compile command (`compileJava`) does not produce the deploy artifact (`quarkusBuild` does); conflating them builds a broken docker image. Split compile vs package.
- **Always detect, ignore §4.1** — rejected: non-standard builds (multi-module Gradle target, monorepo script) need an explicit override. §4.1 wins; detection is the fallback.
- **Fall back to `mvn` when nothing detected** — rejected: that IS the bug. No detection → skip + WARN.
- **Bare `playwright test` at gate 5** — rejected: launches the browser/UI project. API-only via `--project`.
- **Per-slice stack rebuild** — rejected: O(N) docker rebuilds; per-slice tests hit the shared running stack, full rebuild once at gate 5.
- **Hard-block on a red integration suite / non-durable counter** — rejected: violates ADR 0025; a non-durable counter lets a resumed flight loop forever. Bounded, durable, soft-fail to pending-qa.
- **Automate UI at gate 5** — rejected: Fork Y (ADR 0024). UI stays Manual → human-QA.

## Consequences

- Gradle/npm projects compile with the right tool; the silent-pass false positive is designed out.
- The browser/UI project is never run at gate 5; "UI stays Manual" holds for multi-project configs.
- M1 is executable: explicit §4.1-owned package build + API-only project run; resumed flights keep their strike count.
- `ARCHITECTURE.md §4.1` gains `Compile command`, package-owning `Stack-up (M1)`, and API-only `API/integration`. `verification-result.json` gains `gate5Strikes`/`gate5FailureIds[]`/`partial`.
- Both runtime SKILL.md trees + shared `verification.md` + two schemas touched; `dist/` regenerated; `npm run validate` green. UniVerse `ARCHITECTURE.md §4.1` backfilled (separate repo).
- New build systems beyond mvn/gradle/npm (sbt, make, bazel) out of scope — add when a client needs one.
