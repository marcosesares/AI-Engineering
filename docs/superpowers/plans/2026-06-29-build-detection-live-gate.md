# Build-Detection + Live-Integration Stack Gate — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop e2e-flight from assuming `mvn compile` (false "build passes" on Gradle/npm) and make the gate-5 live-integration stack lifecycle + independent **API-only** Playwright run explicit, durable, and safe for the main consumer (UniVerse.Academy — Quarkus/Gradle + docker-compose).

**Architecture:** Skill-content change across the dual-runtime e2e-engineering tree, plus a cross-repo backfill of the main consumer's `ARCHITECTURE.md §4.1`. Two distinct build concepts are separated: a **compile command** (fast pre-merge compile check, auto-detected or §4.1-override) and the **package/stack build** (produces the docker deploy artifact, owned ONLY by §4.1 Stack-up). At gate 5 flight brings the docker-compose stack up via the §4.1 Stack-up recipe, runs the client's independent Playwright **API project only** (never the browser project) against the live `baseURL`, runs a bounded 3-strike loop with a durable counter, then tears the stack down. Soft-fails to `pending-qa` (never `blocked`). UI stays Manual (Fork Y).

**Tech Stack:** Markdown skill docs (`.claude`, `.agents`, shared `skills/e2e-engineering`), JSON-schema markdown, ADR markdown, Node build/validate scripts. No application code. Main consumer = `C:\Views\UniVerse.Academy` (Quarkus/Gradle backend :8081, Vite frontend :3000, Keycloak :8080, Postgres 16, MinIO; `docker-compose`).

## Global Constraints

- **Two build concepts, never conflated:**
  - `compileCmd` — fast compile-only check (Step 3.4 pre-merge). Auto-detected from repo files, or `ARCHITECTURE.md §4.1 Compile command` override. NEVER defaults to `mvn` (bug #35). No detection → skip compile check + WARN in `progress.txt`.
  - **package/stack build** — produces the docker deploy artifact (e.g. `./gradlew :backend:quarkusBuild` → `build/quarkus-app/**`). Owned ONLY by `§4.1 Stack-up (M1)`. The generic gate-5 fallback MUST NOT substitute `compileCmd` here (would build a broken image missing the packaged artifact).
- **Gate-5 runs the API project ONLY.** Bare `npx playwright test` is FORBIDDEN — multi-project configs (e.g. UniVerse `chromium`+`api`) would launch the browser/UI project, violating "UI stays Manual". Use the §4.1 API-only run cmd (`npm run test:api` / `playwright test --project <api>`). Discovery MUST pick the no-browser/`request` project and pass `--project`.
- **Shell-aware Gradle wrapper:** POSIX `./gradlew`; Windows/PowerShell `.\gradlew.bat` (current dir not on PATH in PowerShell). Detection emits the platform-correct form.
- **§4.1 wins over auto-detection.** Detection is the fallback default. Flight READS `ARCHITECTURE.md §4.1`, never writes it (ADR 0013) — §4.1 is human-seeded (pre-impl / QA-gate). The UniVerse backfill (Task 8) is a human-phase write, allowed.
- **Durable bounded loop → soft-fail.** Gate-5 red → bounded task-level 3-strike loop with a counter persisted in `verification-result.json` (`gate5Strikes` + `gate5FailureIds[]`) + a `progress.txt` status line, so a resumed flight does not reset it. Still red after 3 → `verification-result.json` status `partial`, `## Gate 5 Failures` in `qa-signoff.md`, proceed to `pending-qa`. NEVER `blocked`, NEVER unbounded (ADR 0025). Counter is SEPARATE from the per-slice Gate-3 counter.
- **UI stays Manual** (Fork Y / ADR 0024). No browser, no app launch for UI. Gate 5 exercises API against the live stack only.
- **Build before validate (rtk-prefixed per repo CLAUDE.md).** Any source edit under `skills/e2e-engineering/**`, `.claude/skills/**`, or `.agents/skills/**` is mirrored to `dist/`. After every such edit run `rtk npm run build` THEN `rtk npm run validate`; both MUST pass. Commit the regenerated `dist/` with the source edit. (`docs/adr/**` and root `CONTEXT.md` are NOT built/link-checked.)
- **Markdown links resolve relative to file dir** (validate enforces). ADRs are referenced as PLAIN TEXT ("ADR 0032"), never markdown links.
- **caveman-ultra** prose for all skill docs.
- **rtk on every shell segment**, including each segment of a chain (repo rule).

---

### Task 1: Schema §4.1 — `Compile command` + package-owning `Stack-up` + API-only `API/integration`

**Files:**
- Modify: `skills/e2e-engineering/schemas/architecture.md:43-51` (the `### §4.1 Test architecture` block inside the template fence)

**Interfaces:**
- Consumes: nothing (foundational — defines contract field labels).
- Produces: §4.1 labels downstream reads — `Compile command:` (compile-only override), `Stack-up (M1):` (owns the package build + compose sequence), `API/integration:` (independent project + **API-only run cmd**). Tasks 3, 5, 6, 8 rely on these exact labels.

> §4.1 lives INSIDE the ```` ```markdown ```` template fence; the schema's own §Index is a placeholder, so no §Index renumber is required.

- [ ] **Step 1: Failing test (new labels absent)**

Run: `rtk grep -n "Compile command:" skills/e2e-engineering/schemas/architecture.md`
Expected: NO match (exit 1).

- [ ] **Step 2: Apply the §4.1 edit**

Replace this exact block (lines 43-51):

```markdown
### §4.1 Test architecture (Fork Y, ADR 0024 — REQUIRED before any API-bearing task launches)
Seeded in pre-impl (human phase); flight READS, never writes. Baseline standard = [standards/api-testing.md](standards/api-testing.md); fill THIS project's actuals (they override the baseline):
- **Unit runner:** <Vitest|Jest|...> + test dir/glob.
- **API/integration:** Playwright `request` — config path (`playwright.config.*`), test dir, `baseURL`.
- **Stack-up (M1):** how the running stack comes up for tests (docker-compose service(s), required env files, ports).
- **Auth:** how an API test authenticates (token/storageState/setup project).
- **Data isolation:** per-test seed/clean strategy; if none possible → API-test slices serialize.
- **Existing conventions:** if the project already has API tests, point to them — follow, don't replace.
- **UI:** Manual (no automation).
```

with:

```markdown
### §4.1 Test architecture (Fork Y, ADR 0024 — REQUIRED before any API-bearing task launches)
Seeded in pre-impl (human phase); flight READS, never writes. Baseline standard = [standards/api-testing.md](standards/api-testing.md); fill THIS project's actuals (they override the baseline):
- **Compile command:** <fast compile-only check, e.g. `./gradlew :backend:compileJava` | `mvn -q compile` | `npx tsc --noEmit`>. OPTIONAL — overrides flight's compile auto-detection. Compile ONLY; does NOT package. Empty → flight auto-detects from repo files (ADR 0032).
- **Unit runner:** <Vitest|Jest|JUnit|...> + test dir/glob + run cmd.
- **API/integration (independent project):** the client's standalone Playwright `request` project (own `playwright.config.*` + `package.json`, may be a sibling dir). Give config path, project name, testDir, `baseURL`, and the **API-only run cmd** (e.g. `cd playwright && npm run test:api`, or `npx playwright test --project api`). Flight runs THIS cmd; NEVER bare `playwright test` (would also run any browser/UI project — UI is Manual). Absent → flight discovers the no-browser/`request` project and runs it with `--project <name>`.
- **Stack-up (M1):** the explicit sequence gate 5 runs to bring the stack up clean — and it OWNS the **package/deploy build** (the build that produces the docker artifact, e.g. `quarkusBuild` → `build/quarkus-app/**`, NOT the compile-only command). e.g. `docker compose down -v` → `<package build>` → `docker compose up --force-recreate --build -d`. List service(s), required env files, ports. Empty + a Dockerfile that copies a pre-built artifact → flight CANNOT safely rebuild (it will WARN and skip the host build); seed this line for such projects (ADR 0032).
- **Auth:** how an API test authenticates (token/storageState/setup project).
- **Data isolation:** per-test seed/clean strategy; if none possible → API-test slices serialize.
- **Existing conventions:** if the project already has API tests, point to them — follow, don't replace.
- **UI:** Manual (no automation).
```

- [ ] **Step 3: Passing test**

Run: `rtk grep -n "Compile command:\|API-only run cmd\|package/deploy build" skills/e2e-engineering/schemas/architecture.md`
Expected: ≥3 matches.

- [ ] **Step 4: Build + validate**

Run: `rtk npm run build && rtk npm run validate`
Expected: `validate: ok`.

- [ ] **Step 5: Commit**

```bash
git add skills/e2e-engineering/schemas/architecture.md dist/
git commit -m "feat(schema): §4.1 split Compile command vs package-owning Stack-up + API-only run (bug #35)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Schema `verification-result.json` — durable gate-5 strike state + `partial` status

**Files:**
- Modify: `skills/e2e-engineering/schemas/verification-result.json.md:3-26` (JSON shape, banner, invariants)

**Interfaces:**
- Consumes: nothing.
- Produces: the `status: partial` value + `gate5Strikes` (int) + `gate5FailureIds` (string[]) fields that verification.md (Task 3) and both SKILLs (Tasks 5/6) write/read to make the bounded loop durable across resumed flights.

- [ ] **Step 1: Failing test (field absent)**

Run: `rtk grep -n "gate5Strikes" skills/e2e-engineering/schemas/verification-result.json.md`
Expected: NO match (exit 1).

- [ ] **Step 2: Edit the JSON shape**

Replace this block (lines 6-18):

```json
{
  "scope": "story-id | _task — story-scoped or task-level verification",
  "status": "passed | failed",
  "suiteGreen": "boolean — full unit+API suite green from clean state",
  "checklist": [
    {
      "criterion": "string — acceptance criteria text",
      "verified": "boolean",
      "method": "automated | manual | self-review"
    }
  ],
  "notes": "string — caveman-ultra; gaps or deferred items"
}
```

with:

```json
{
  "scope": "story-id | _task — story-scoped or task-level verification",
  "status": "passed | partial | failed",
  "suiteGreen": "boolean — full unit+API suite green from clean state",
  "gate5Strikes": "int — task-level fix-loop attempts spent (0..3); durable, NOT reset on resume",
  "gate5FailureIds": ["string — stable id of each still-failing test/AC (e.g. spec::test name, or AC index)"],
  "checklist": [
    {
      "criterion": "string — acceptance criteria text",
      "verified": "boolean",
      "method": "automated | manual | self-review"
    }
  ],
  "notes": "string — caveman-ultra; gaps or deferred items"
}
```

- [ ] **Step 3: Update the banner status set + add invariants**

Replace (line 3, ends `...task-level verification).`):

```markdown
Evidence sidecar for GATE 5 (verification-before-completion). **ACTIVE — ADR 0024 (Fork Y):** = full automated suite (unit+API) green + AC-checklist-vs-code, no live-UI exercise. Written at gate 5 inside self-review. Lives at `tasks/<task-id>/manifests/<story-id>/verification-result.json` (or `manifests/_task/verification-result.json` for task-level verification).
```

with:

```markdown
Evidence sidecar for GATE 5 (verification-before-completion). **ACTIVE — ADR 0024 (Fork Y) + ADR 0032:** = full automated suite (unit + independent API project) green against the live stack + AC-checklist-vs-code, no live-UI exercise. Written at gate 5 inside self-review. Lives at `tasks/<task-id>/manifests/<story-id>/verification-result.json` (or `manifests/_task/verification-result.json` for task-level verification).
```

Then in `## Invariants`, after the line beginning `- **Active (Fork Y, ADR 0024).**`, add:

```markdown
- **`status: partial`** = suite still red (or an AC unmapped) AFTER the bounded gate-5 loop — route to `pending-qa` + `## Gate 5 Failures` (ADR 0025/0032); NOT `blocked`.
- **`gate5Strikes` is durable.** A resumed flight reads the existing sidecar and continues from the recorded strike count; it does NOT reset to 0. `gate5FailureIds[]` lists the still-red tests/ACs so re-dispatch targets exactly them.
```

- [ ] **Step 4: Passing test**

Run: `rtk grep -n "gate5Strikes\|gate5FailureIds\|status: partial" skills/e2e-engineering/schemas/verification-result.json.md`
Expected: ≥3 matches.

- [ ] **Step 5: Build + validate**

Run: `rtk npm run build && rtk npm run validate`
Expected: `validate: ok`.

- [ ] **Step 6: Commit**

```bash
git add skills/e2e-engineering/schemas/verification-result.json.md dist/
git commit -m "feat(schema): verification-result gains durable gate5Strikes + partial status (bug #35)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: verification.md gate-5 live-integration rewrite

**Files:**
- Modify: `skills/e2e-engineering/impl/verification.md:1-23` (banner, `## What to do`, soft-fail paragraph, red flags)

**Interfaces:**
- Consumes (Tasks 1-2): §4.1 `Compile command`/`Stack-up`/`API/integration`; `verification-result.json` `gate5Strikes`/`gate5FailureIds`/`partial`.
- Produces: the gate-5 procedure both SKILLs (Tasks 5/6) point at — §4.1 stack-up (package build), API-only run, no-compile-inject fallback, durable 3-strike loop, teardown.

- [ ] **Step 1: Failing test**

Run: `rtk grep -n "API project ONLY\|gate5Strikes\|package build" skills/e2e-engineering/impl/verification.md`
Expected: NO match (exit 1).

- [ ] **Step 2: Edit the RESCOPED banner**

Replace (line 3):

```markdown
> **RESCOPED — ADR 0024 (Fork Y).** = full automated suite (unit + API) green **+** AC-checklist against CODE. **No live-UI exercise** — `/run` + `/verify` removed (agent live-UI verification too costly; UI is verified by the human-QA Manual walk post-impl). Executed inside self-review. Hard, agent-enforced, non-overridable.
```

with:

```markdown
> **RESCOPED — ADR 0024 (Fork Y) + ADR 0032.** = full automated suite (unit + the client's independent **API project ONLY**) green against a live docker-compose stack **+** AC-checklist against CODE. **No live-UI exercise** — `/run` + `/verify` removed; the browser/UI Playwright project is NEVER run here (UI is verified by the human-QA Manual walk post-impl). Executed inside self-review. Hard, agent-enforced, non-overridable.
```

- [ ] **Step 3: Replace the `## What to do` block**

Replace this exact block (lines 7-10):

```markdown
## What to do
1. **Full suite re-run** — ALL automated tests (unit Vitest + API/integration Playwright `request`), not just changed slices. Confirm green from clean state. Red → re-open loop (trace failure to story → re-dispatch slice; cross-slice gap → new slice / systematic-debugging).
2. **AC-checklist against code** — walk every story's `acceptanceCriteria[]`; for each confirm an implementing code path AND a covering automated test (unit/API) OR a Manual test-case (UI) exists. No mapping = not done.
3. Record into `verification-result.json` ([schema](../schemas/verification-result.json.md)); `method` = `automated` (suite) | `manual` (UI → human-QA) | `self-review` (code read).
```

with:

```markdown
## What to do
1. **Stack rebuild (docker-compose projects).** Run the `ARCHITECTURE.md §4.1 Stack-up (M1)` recipe verbatim — it OWNS the package/deploy build (e.g. `docker compose down -v` → `./gradlew :backend:quarkusBuild` → `docker compose up --force-recreate --build -d`). Runs ONCE here, not per slice. Fallbacks when §4.1 Stack-up is empty: (a) compose file present AND no Dockerfile copies a pre-built artifact → generic `down -v → up --force-recreate --build -d` (let compose build the image; do NOT inject the compile command as a package build); (b) compose file present BUT a Dockerfile copies a pre-built artifact (e.g. `COPY build/quarkus-app/`) → CANNOT safely rebuild → WARN in `progress.txt` ("§4.1 Stack-up unseeded; skipping host build") and bring the existing stack up as-is; (c) no compose file → skip stack lifecycle entirely.
2. **Full suite re-run against the live stack** — unit tests + the client's independent Playwright **API project ONLY**, not just changed slices. Run the `§4.1 API/integration` API-only cmd (e.g. `cd playwright && npm run test:api`). Absent → discover the project whose `use` has NO browser device / uses the `request` fixture / targets the API `baseURL`, and run it with `npx playwright test --project <name>`. NEVER bare `playwright test` (runs browser/UI projects too). Confirm green.
3. **Red → durable bounded fix loop** (task-level, max 3 strikes — SEPARATE from the per-slice Gate-3). Read `gate5Strikes` from any existing `verification-result.json` (resume-safe; do NOT reset). For each still-red test/AC: record its id in `gate5FailureIds[]`, trace to its story, re-dispatch the slice (or systematic-debugging; cross-slice gap → new slice), re-run the affected suite, increment `gate5Strikes`. Persist `gate5Strikes` + a status line to `progress.txt` after each strike.
4. **AC-checklist against code** — walk every story's `acceptanceCriteria[]`; for each confirm an implementing code path AND a covering automated test (unit/API) OR a Manual test-case (UI) exists. No mapping = not done.
5. **Teardown** — `docker compose down -v` after the gate completes (leave no orphan stack).
6. Record into `verification-result.json` ([schema](../schemas/verification-result.json.md)): `status`, `suiteGreen`, `gate5Strikes`, `gate5FailureIds[]`, `checklist[]`; `method` = `automated` (suite) | `manual` (UI → human-QA) | `self-review` (code read).
```

- [ ] **Step 4: Update the soft-fail paragraph**

Replace (line 15):

```markdown
**Suite red or AC unmapped → do NOT block.** Record each failure in `verification-result.json` (status `partial`) AND write a `## Gate 5 Failures` section in `qa-signoff.md`. Proceed to `pending-qa`. Human routes each failure through triage into a new repair Task at QA sign-off (ADR 0025). `blocked` is reserved for Gate 3 exhausted stories — NOT for test failures.
```

with:

```markdown
**Suite still red after the bounded loop (`gate5Strikes` hits 3) or AC unmapped → do NOT block.** Record each failure in `verification-result.json` (status `partial`, `gate5FailureIds[]` populated) AND write a `## Gate 5 Failures` section in `qa-signoff.md`. Proceed to `pending-qa`. Human routes each failure through triage into a new repair Task at QA sign-off (ADR 0025). `blocked` is reserved for Gate 3 exhausted stories — NOT for test failures.
```

- [ ] **Step 5: Add red flags**

In `## Red flags (stop)`, after the line beginning `- Re-running only changed slices`, add:

```markdown
- Running bare `playwright test` (launches the browser/UI project) — run the API project ONLY via the §4.1 cmd or `--project <name>`.
- Injecting the compile command as the stack/package build in the generic fallback — the package build comes ONLY from §4.1 Stack-up; missing it for an artifact-copying Dockerfile → WARN + skip, never guess.
- Leaving the gate-5 docker stack up (orphan) — tear down `docker compose down -v` after the gate.
- Resetting `gate5Strikes` to 0 on a resumed flight — read the existing sidecar and continue the count.
```

- [ ] **Step 6: Passing test**

Run: `rtk grep -n "API project ONLY\|gate5Strikes\|package build\|Teardown" skills/e2e-engineering/impl/verification.md`
Expected: ≥4 matches.

- [ ] **Step 7: Build + validate**

Run: `rtk npm run build && rtk npm run validate`
Expected: `validate: ok`.

- [ ] **Step 8: Commit**

```bash
git add skills/e2e-engineering/impl/verification.md dist/
git commit -m "feat(verification): gate-5 API-only run + §4.1 package build + durable 3-strike loop (bug #35)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: ADR 0032 — record the decision

**Files:**
- Create: `docs/adr/0032-build-detection-and-live-integration-gate.md`

**Interfaces:**
- Consumes: nothing. Cross-refs ADR 0024, 0025, 0013, 0020 as plain text.
- Produces: the "ADR 0032" citation Tasks 1-3, 5, 6 reference. No dist/link impact.

- [ ] **Step 1: Write the file** — create `docs/adr/0032-build-detection-and-live-integration-gate.md` with EXACTLY:

```markdown
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
```

- [ ] **Step 2: Verify + validate**

Run: `rtk grep -n "^# Build-system detection" docs/adr/0032-build-detection-and-live-integration-gate.md`
Expected: 1 match.
Run: `rtk npm run validate`
Expected: `validate: ok`.

- [ ] **Step 3: Commit**

```bash
git add docs/adr/0032-build-detection-and-live-integration-gate.md
git commit -m "docs(adr): 0032 build detection + live-integration stack gate (bug #35)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: `.claude` flight SKILL.md — Step 2 detection, Step 3 inject/use, Step 5 stack gate

**Files:**
- Modify: `.claude/skills/e2e-flight/SKILL.md` — Step 2 (after line 50), Step 3.2 (line 63), Step 3.4 (line 90), Step 5.0 (line 109), token-hygiene (line 135), red flags (after line 138).

**Interfaces:**
- Consumes (Tasks 1-4): §4.1 labels; verification.md gate-5 recipe; verification-result fields; "ADR 0032".
- Produces: the `compileCmd` contract — resolved Step 2, injected Step 3.2, used Step 3.4. Task 6 (`.agents`) mirrors these behaviors.

- [ ] **Step 1: Failing test**

Run: `rtk grep -n "Compile detection\|compileCmd" .claude/skills/e2e-flight/SKILL.md`
Expected: NO match (exit 1).

- [ ] **Step 2: Insert the Compile-detection sub-step in Step 2**

After the "Docker env cache" paragraph (ends `Do NOT re-read per slice.`, line 50) and BEFORE `**Codebase-map (brownfield only).**`, insert:

```markdown
**Compile detection (cache `compileCmd` once).** Resolve the COMPILE-ONLY check command, §4.1-wins-else-detect (ADR 0032):
1. `ARCHITECTURE.md §4.1 Compile command` present → use it verbatim.
2. else detect from repo root: `pom.xml` → `mvn -q compile`; `build.gradle`/`build.gradle.kts` → gradle wrapper + `compileJava`, shell-aware (`./gradlew compileJava` POSIX / `.\gradlew.bat compileJava` PowerShell/win32); `package.json` → `npm run build` (no `build` script → `npx tsc --noEmit`).
3. none of the above → NO compile command; skip the compile check + WARN in `progress.txt`. Do NOT fall back to `mvn` (the original bug, #35).
`compileCmd` is COMPILE-ONLY — it never feeds the gate-5 stack rebuild (that build comes from §4.1 Stack-up). Cache `compileCmd` once for the spawn (alongside the docker-env cache); do NOT re-detect per slice.
```

- [ ] **Step 3: Inject `compileCmd` at Step 3.2**

In line 63, find `+ testCases + (brownfield) SCOPED slice of \`ARCHITECTURE.md\`` and replace with:

```markdown
+ testCases + cached `compileCmd` (Step 2 — worker compiles with this, never assumes Maven) + (brownfield) SCOPED slice of `ARCHITECTURE.md`
```

- [ ] **Step 4: Use `compileCmd` at Step 3.4**

In line 90, find:

```markdown
4. **lint + compile** — orchestrator commands (not agents). Run project lint + build/typecheck; reconcile failures before merge.
```

replace with:

```markdown
4. **lint + compile** — orchestrator commands (not agents). Run project lint + the cached `compileCmd` (Step 2 — compile-only check, not a hardcoded build, not the package build); reconcile failures before merge.
```

- [ ] **Step 5: Rewrite Step 5.0 (stack gate, API-only)**

In line 109, find:

```markdown
- **5.0 — HARD GATE 5 (verification-before-completion).** Run [verification](../../../skills/e2e-engineering/impl/verification.md): (a) full automated suite (unit + API/integration) green from clean state; (b) AC-checklist against code — every `acceptanceCriteria[]` maps to a code path AND a covering automated test (unit/API) OR a Manual test-case (UI). Write `manifests/_task/verification-result.json` ([schema](../../../skills/e2e-engineering/schemas/verification-result.json.md)). **NO live-UI exercise** (no app launch — Fork Y). Red suite or unmapped AC → record failures, proceed to Step 5.1 (do NOT mark `blocked` — see ADR 0025).
```

replace with:

```markdown
- **5.0 — HARD GATE 5 (verification-before-completion).** Run [verification](../../../skills/e2e-engineering/impl/verification.md): bring the live docker-compose stack up ONCE per `ARCHITECTURE.md §4.1 Stack-up` (owns the package build, e.g. `down -v → quarkusBuild → up --force-recreate --build -d`; unseeded + artifact-copying Dockerfile → WARN + skip host build; no compose → skip), then (a) full automated suite (unit + the client's independent Playwright **API project ONLY**, via the §4.1 `API/integration` API-only cmd / `--project <name>` — NEVER bare `playwright test`) green; (b) AC-checklist against code — every `acceptanceCriteria[]` maps to a code path AND a covering automated test (unit/API) OR a Manual test-case (UI). Red → durable bounded task-level 3-strike loop (`gate5Strikes` in the sidecar; resume-safe; separate from per-slice Gate-3). Tear the stack down (`down -v`) after. Write `manifests/_task/verification-result.json` ([schema](../../../skills/e2e-engineering/schemas/verification-result.json.md)) incl. `gate5Strikes`/`gate5FailureIds[]`. **NO live-UI exercise** (no app launch, browser project never run — Fork Y). Still red after the loop or unmapped AC → record failures, proceed to Step 5.1 (do NOT mark `blocked` — see ADR 0025).
```

- [ ] **Step 6: Token-hygiene cache line**

In line 135, find:

```markdown
- docker config + codebase-map: read ONCE in Step 2, never re-read in Steps 3/4.
```

replace with:

```markdown
- docker config + codebase-map + `compileCmd`: resolved/read ONCE in Step 2, never re-detect/re-read in Steps 3/4.
```

- [ ] **Step 7: Add red flags**

In `## Red flags (stop)`, after the first bullet (`- Slice-impl inline instead of sub-agent dispatch ...`), add:

```markdown
- Assuming `mvn` / a hardcoded build instead of the §4.1-or-detected `compileCmd` (bug #35 cause — Step 2 detects, §4.1 wins; none → skip + WARN, never `mvn`).
- Feeding `compileCmd` into the gate-5 stack rebuild — the package build comes ONLY from §4.1 Stack-up.
- Running bare `playwright test` at gate 5 (runs the browser/UI project) — API project ONLY.
- Leaving the gate-5 docker stack up (orphan), or resetting `gate5Strikes` on resume.
```

- [ ] **Step 8: Passing test**

Run: `rtk grep -n "Compile detection\|compileCmd\|API project ONLY" .claude/skills/e2e-flight/SKILL.md`
Expected: ≥6 matches.

- [ ] **Step 9: Build + validate**

Run: `rtk npm run build && rtk npm run validate`
Expected: `validate: ok`.

- [ ] **Step 10: Commit**

```bash
git add .claude/skills/e2e-flight/SKILL.md dist/
git commit -m "feat(flight-claude): compile detection + gate-5 API-only live-integration stack (bug #35)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: `.agents` flight SKILL.md — mirror semantics (Codex runtime)

**Files:**
- Modify: `.agents/skills/e2e-flight/SKILL.md` — Step 2 (after line 51), Step 3.2 (line 64), Step 3.4 (line 95), Step 5.0 (line 114), token-hygiene (line 140), red flags (after line 143).

**Interfaces:**
- Consumes: same as Task 5.
- Produces: dual-runtime parity. Codex difference: `compileCmd` rides in the **spawn manifest**; no worktrees.

- [ ] **Step 1: Failing test**

Run: `rtk grep -n "Compile detection\|compileCmd" .agents/skills/e2e-flight/SKILL.md`
Expected: NO match (exit 1).

- [ ] **Step 2: Insert the Compile-detection sub-step in Step 2**

After the "Docker env cache" paragraph (ends `Do NOT re-read per slice.`, line 51) and BEFORE `**Codebase-map (brownfield only).**`, insert:

```markdown
**Compile detection (cache `compileCmd` once).** Resolve the COMPILE-ONLY check command, §4.1-wins-else-detect (ADR 0032):
1. `ARCHITECTURE.md §4.1 Compile command` present → use it verbatim.
2. else detect from repo root: `pom.xml` → `mvn -q compile`; `build.gradle`/`build.gradle.kts` → gradle wrapper + `compileJava`, shell-aware (`./gradlew compileJava` POSIX / `.\gradlew.bat compileJava` PowerShell/win32); `package.json` → `npm run build` (no `build` script → `npx tsc --noEmit`).
3. none of the above → NO compile command; skip the compile check + WARN in `progress.txt`. Do NOT fall back to `mvn` (the original bug, #35).
`compileCmd` is COMPILE-ONLY — it never feeds the gate-5 stack rebuild (that build comes from §4.1 Stack-up). Cache `compileCmd` once for the spawn (alongside the docker-env cache); pass it in every sub-agent spawn manifest in Step 3. Do NOT re-detect per slice.
```

- [ ] **Step 3: Inject `compileCmd` into the spawn manifest at Step 3.2**

In line 64, find `+ testCases + (brownfield) SCOPED slice of \`ARCHITECTURE.md\`` and replace with:

```markdown
+ testCases + cached `compileCmd` (Step 2 — worker compiles with this, never assumes Maven) + (brownfield) SCOPED slice of `ARCHITECTURE.md`
```

- [ ] **Step 4: Use `compileCmd` at Step 3.4**

In line 95, find:

```markdown
4. **lint + compile** — orchestrator commands (not agents). Run project lint + build/typecheck; reconcile failures before merge.
```

replace with:

```markdown
4. **lint + compile** — orchestrator commands (not agents). Run project lint + the cached `compileCmd` (Step 2 — compile-only check, not a hardcoded build, not the package build); reconcile failures before merge.
```

- [ ] **Step 5: Rewrite Step 5.0**

In line 114, find:

```markdown
- **5.0 — HARD GATE 5 (verification-before-completion).** Run `$sharedSkillsRoot/impl/verification.md`: (a) full automated suite (unit + API/integration) green from clean state; (b) AC-checklist against code — every `acceptanceCriteria[]` maps to a code path AND a covering automated test (unit/API) OR a Manual test-case (UI). Write `manifests/_task/verification-result.json` (`$sharedSkillsRoot/schemas/verification-result.json.md`). **NO live-UI exercise** (no app launch — Fork Y). Red suite or unmapped AC → record failures, proceed to Step 5.1 (do NOT mark `blocked` — see ADR 0025).
```

replace with:

```markdown
- **5.0 — HARD GATE 5 (verification-before-completion).** Run `$sharedSkillsRoot/impl/verification.md`: bring the live docker-compose stack up ONCE per `ARCHITECTURE.md §4.1 Stack-up` (owns the package build, e.g. `down -v → quarkusBuild → up --force-recreate --build -d`; unseeded + artifact-copying Dockerfile → WARN + skip host build; no compose → skip), then (a) full automated suite (unit + the client's independent Playwright **API project ONLY**, via the §4.1 `API/integration` API-only cmd / `--project <name>` — NEVER bare `playwright test`) green; (b) AC-checklist against code — every `acceptanceCriteria[]` maps to a code path AND a covering automated test (unit/API) OR a Manual test-case (UI). Red → durable bounded task-level 3-strike loop (`gate5Strikes` in the sidecar; resume-safe; separate from per-slice Gate-3). Tear the stack down (`down -v`) after. Write `manifests/_task/verification-result.json` (`$sharedSkillsRoot/schemas/verification-result.json.md`) incl. `gate5Strikes`/`gate5FailureIds[]`. **NO live-UI exercise** (no app launch, browser project never run — Fork Y). Still red after the loop or unmapped AC → record failures, proceed to Step 5.1 (do NOT mark `blocked` — see ADR 0025).
```

- [ ] **Step 6: Token-hygiene cache line**

In line 140, find:

```markdown
- docker config + codebase-map: read ONCE in Step 2, never re-read in Steps 3/4.
```

replace with:

```markdown
- docker config + codebase-map + `compileCmd`: resolved/read ONCE in Step 2, never re-detect/re-read in Steps 3/4.
```

- [ ] **Step 7: Add red flags**

In `## Red flags (stop)`, after the first bullet (`- Slice-impl inline instead of sub-agent dispatch ...`), add:

```markdown
- Assuming `mvn` / a hardcoded build instead of the §4.1-or-detected `compileCmd` (bug #35 cause — Step 2 detects, §4.1 wins; none → skip + WARN, never `mvn`).
- Feeding `compileCmd` into the gate-5 stack rebuild — the package build comes ONLY from §4.1 Stack-up.
- Running bare `playwright test` at gate 5 (runs the browser/UI project) — API project ONLY.
- Leaving the gate-5 docker stack up (orphan), or resetting `gate5Strikes` on resume.
```

- [ ] **Step 8: Passing test**

Run: `rtk grep -n "Compile detection\|compileCmd\|API project ONLY" .agents/skills/e2e-flight/SKILL.md`
Expected: ≥6 matches.

- [ ] **Step 9: Build + validate**

Run: `rtk npm run build && rtk npm run validate`
Expected: `validate: ok`.

- [ ] **Step 10: Commit**

```bash
git add .agents/skills/e2e-flight/SKILL.md dist/
git commit -m "feat(flight-codex): compile detection + gate-5 API-only live-integration stack (bug #35)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: CONTEXT.md glossary + dual-runtime parity verification

**Files:**
- Modify: `CONTEXT.md` (glossary)

**Interfaces:**
- Consumes: terminology from Tasks 1-6.
- Produces: nothing downstream. Final in-repo task; verifies parity.

> CONTEXT.md is NOT under a built skill dir → no `dist` impact.

- [ ] **Step 1: Confirm terms absent**

Run: `rtk grep -n "compileCmd\|Stack-up (M1)\|API-test project" CONTEXT.md`
Expected: NO match (exit 1).

- [ ] **Step 2: Add glossary entries** (match existing `**Term**: definition` format, alphabetical placement):

```markdown
**compileCmd** _[ADR 0032]_: the COMPILE-ONLY check command flight resolves once per spawn — `ARCHITECTURE.md §4.1 Compile command` if set, else auto-detected (`pom.xml`→mvn, `build.gradle`→`./gradlew`/`.\gradlew.bat compileJava`, `package.json`→npm/tsc). Never defaults to `mvn` (bug #35 false-pass). Injected to impl workers; used by the orchestrator compile check. Distinct from the package/stack build.

**Stack-up (M1)** _[ADR 0024, 0032]_: the explicit `down -v → <package build> → up --force-recreate --build -d` sequence gate 5 runs once to bring the docker-compose stack up clean. OWNS the package/deploy build (e.g. `quarkusBuild`), which the compile check does not produce. Seeded in `ARCHITECTURE.md §4.1`; unseeded + artifact-copying Dockerfile → WARN + skip host build.

**API-test project** _[ADR 0032]_: the client's independent Playwright `request` project (own config/package, possibly a sibling dir) gate 5 runs **API-only** (`--project <api>` / `npm run test:api`) against the live `baseURL`. NEVER run via bare `playwright test` (would also launch the browser/UI project — UI is Manual, Fork Y).
```

- [ ] **Step 3: Verify + final build/validate**

Run: `rtk grep -n "compileCmd\|Stack-up\|API-test project" CONTEXT.md`
Expected: ≥3 matches.
Run: `rtk npm run build && rtk npm run validate`
Expected: `validate: ok`.

- [ ] **Step 4: Dual-runtime parity check**

Run: `rtk grep -c "compileCmd" .claude/skills/e2e-flight/SKILL.md .agents/skills/e2e-flight/SKILL.md`
Expected: both ≥6. Eyeball that Step 2 detection, 3.2 inject, 3.4 use, 5.0 API-only stack gate, and the four red flags appear in BOTH trees.

- [ ] **Step 5: Commit**

```bash
git add CONTEXT.md dist/
git commit -m "docs(context): glossary compileCmd / Stack-up / API-test project (bug #35)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: Backfill UniVerse.Academy `ARCHITECTURE.md §4.1` (CROSS-REPO)

> **Different repo:** `C:\Views\UniVerse.Academy` — its own git. Branch + commit THERE, not in e2e-Engineering. No `dist`/validate (consumer repo). This is a human-phase ARCHITECTURE write (allowed; flight only READS — ADR 0013).

**Files:**
- Modify: `C:\Views\UniVerse.Academy\ARCHITECTURE.md` — §4.1 block (current intro at line 43-45; insert new labeled bullets after the intro paragraph, before the existing `- **baseURL:**` bullet at line 47).

**Interfaces:**
- Consumes: the §4.1 labels defined in Task 1 (`Compile command`, `Unit runner`, `Stack-up (M1)`, API-only `API/integration`).
- Produces: real commands flight reads for UniVerse, replacing weak discovery/fallback.

- [ ] **Step 1: Confirm labels absent**

Run: `rtk grep -n "Compile command:\|Stack-up (M1):" "C:/Views/UniVerse.Academy/ARCHITECTURE.md"`
Expected: NO match (exit 1).

- [ ] **Step 2: Insert the labeled bullets**

In `C:\Views\UniVerse.Academy\ARCHITECTURE.md`, immediately AFTER the §4.1 intro paragraph (the line ending `...real DB, real Keycloak, real everything.`, line 45) and BEFORE the `- **baseURL:**` bullet, insert:

```markdown
- **Compile command:** `./gradlew :backend:compileJava` (compile-only check; does NOT package).
- **Unit runner:** backend JUnit5 `./gradlew :backend:test`; frontend Vitest `./gradlew frontend:test`.
- **Stack-up (M1):** `docker-compose down -v` → `./gradlew :backend:quarkusBuild` → `docker-compose up --force-recreate --build -d`. Brings up Postgres 16, Keycloak 24 (:8080), MinIO, backend (:8081), frontend (:3000). `quarkusBuild` produces `backend/build/quarkus-app/**` that `Dockerfile.jvm` copies — REQUIRED before the compose build, since the compile-only command does not produce it.
- **API/integration (independent project, API-only):** run `cd playwright && npm run test:api` (= `playwright test --project api`, no browser). Config `playwright/playwright.config.ts`, project `api`, testDir `playwright/tests/api/`, baseURL `http://localhost:8081`. Do NOT run bare `playwright test` — that also runs the `chromium` UI project (UI is Manual, Fork Y).
```

- [ ] **Step 3: Verify**

Run: `rtk grep -n "Compile command:\|Stack-up (M1):\|test:api" "C:/Views/UniVerse.Academy/ARCHITECTURE.md"`
Expected: ≥3 matches.

- [ ] **Step 4: Commit IN THE UniVerse REPO**

```bash
git -C "C:/Views/UniVerse.Academy" checkout -b chore/architecture-41-flight-backfill
git -C "C:/Views/UniVerse.Academy" add ARCHITECTURE.md
git -C "C:/Views/UniVerse.Academy" commit -m "docs(architecture): §4.1 add Compile command / Stack-up / API-only run for e2e-flight (bug #35)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

> If the UniVerse repo's branch/PR conventions differ, follow them — the content of the §4.1 edit is the deliverable.

---

## Self-Review

**1. Findings coverage:**

| Finding | Fix |
|---------|-----|
| 1 High — gate-5 runs UI Playwright | Task 1 §4.1 API-only run cmd; Task 3 verification "API project ONLY" + discovery `--project`; Tasks 5/6 Step 5.0 + red flag; Task 8 UniVerse `npm run test:api` |
| 2 High — generic Gradle fallback breaks Quarkus image | Split `compileCmd` (compile-only) vs §4.1-owned package build; generic fallback never injects compileCmd, WARNs for artifact-copying Dockerfile (Tasks 1, 3, 5, 6, ADR 4) |
| 3 High — UniVerse §4.1 won't satisfy new labels | Task 8 cross-repo backfill with concrete values |
| 4 Med — PowerShell `gradlew.bat` | `.\gradlew.bat` (win32) / `./gradlew` (POSIX) in detection (Tasks 5/6 Step 2, ADR, CONTEXT) |
| 5 Med — no durable strike counter | Task 2 schema `gate5Strikes`/`gate5FailureIds[]`/`partial`; Task 3 reads/persists; Tasks 5/6 Step 5.0 + red flag |
| 6 Low — rtk prefix | all build/validate/grep commands rtk-prefixed, each chain segment |

**2. Placeholder scan:** every edit step has the literal old_string anchor + full new_string; ADR + glossary + UniVerse §4.1 content verbatim. No TBD/"handle edge cases"/"similar to".

**3. Name consistency:** `compileCmd` (not `buildCmd`) across Tasks 1,5,6,7. §4.1 labels `Compile command`/`Stack-up (M1)`/`API/integration` identical in Tasks 1,3,5,6,8. `gate5Strikes`/`gate5FailureIds` identical in Tasks 2,3,5,6. Bounded loop consistently "task-level, durable, 3-strike, separate from per-slice Gate-3".

**Ordering:** 1-2 schemas (contracts) → 3 recipe → 4 ADR → 5/6 SKILLs → 7 glossary+parity → 8 cross-repo backfill. Each in-repo task independently committable, leaves `npm run validate` green.
```