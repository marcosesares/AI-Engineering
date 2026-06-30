# verification — verify-before-completion (HARD GATE 5)

> **RESCOPED — ADR 0024 (Fork Y) + ADR 0032.** = full automated suite (unit + the client's independent **API project ONLY**) green against a live docker-compose stack **+** AC-checklist against CODE. **No live-UI exercise** — `/run` + `/verify` removed; the browser/UI Playwright project is NEVER run here (UI is verified by the human-QA Manual walk post-impl). Executed inside self-review. Hard, agent-enforced, non-overridable.

Final Implementation-phase check, after the DAG drains. Blocks `done` (→ `pending-qa`) on a red suite or an unmet AC.

## What to do
1. **Stack rebuild (docker-compose projects).** Run the `ARCHITECTURE.md §4.1 Stack-up (M1)` recipe verbatim — it OWNS the package/deploy build (e.g. `docker compose down -v` → `./gradlew :backend:quarkusBuild` → `docker compose up --force-recreate --build -d`). Runs ONCE here, not per slice. Fallbacks when §4.1 Stack-up is empty: (a) compose file present AND no Dockerfile copies a pre-built artifact → generic `down -v → up --force-recreate --build -d` (let compose build the image; do NOT inject the compile command as a package build); (b) compose file present BUT a Dockerfile copies a pre-built artifact (e.g. `COPY build/quarkus-app/`) → CANNOT safely rebuild → WARN in `progress.txt` ("§4.1 Stack-up unseeded; skipping host build") and bring the existing stack up as-is; (c) no compose file → skip stack lifecycle entirely.
2. **Full suite re-run against the live stack** — unit tests + the client's independent Playwright **API project ONLY**, not just changed slices. Run the `§4.1 API/integration` API-only cmd (e.g. `cd playwright && npm run test:api`). Absent → discover the project whose `use` has NO browser device / uses the `request` fixture / targets the API `baseURL`, and run it with `npx playwright test --project <name>`. NEVER bare `playwright test` (runs browser/UI projects too). Confirm green.
3. **Red → durable bounded fix loop** (task-level, max 3 strikes — SEPARATE from the per-slice Gate-3). Read `gate5Strikes` from any existing `verification-result.json` (resume-safe; do NOT reset). For each still-red test/AC: record its id in `gate5FailureIds[]`, trace to its story, re-dispatch the slice (or systematic-debugging; cross-slice gap → new slice), re-run the affected suite, increment `gate5Strikes`. Persist `gate5Strikes` + a status line to `progress.txt` after each strike.
4. **AC-checklist against code** — walk every story's `acceptanceCriteria[]`; for each confirm an implementing code path AND a covering automated test (unit/API) OR a Manual test-case (UI) exists. No mapping = not done.
5. **Teardown** — `docker compose down -v` after the gate completes (leave no orphan stack).
6. Record into `verification-result.json` ([schema](../schemas/verification-result.json.md)): `status`, `suiteGreen`, `gate5Strikes`, `gate5FailureIds[]`, `checklist[]`; `method` = `automated` (suite) | `manual` (UI → human-QA) | `self-review` (code read).

## HARD GATE 5
Suite green AND every AC mapped = implementation done → `pending-qa`. UI ACs mapped to Manual test-cases (proven at human-QA), NOT exercised here.

**Suite still red after the bounded loop (`gate5Strikes` hits 3) or AC unmapped → do NOT block.** Record each failure in `verification-result.json` (status `partial`, `gate5FailureIds[]` populated) AND write a `## Gate 5 Failures` section in `qa-signoff.md`. Proceed to `pending-qa`. Human routes each failure through triage into a new repair Task at QA sign-off (ADR 0025). `blocked` is reserved for Gate 3 exhausted stories — NOT for test failures.

## Red flags (stop)
- Opening the app / `/run` / `/verify` for UI checks (removed — Fork Y; UI is human-QA's job).
- Marking Task `blocked` because Gate 5 suite is red (route to `pending-qa` + qa-signoff failures instead — ADR 0025).
- AC with no implementing code path and no covering test (automated or Manual) — record as Gate 5 failure, do not block.
- Re-running only changed slices instead of the full suite.
- Running bare `playwright test` (launches the browser/UI project) — run the API project ONLY via the §4.1 cmd or `--project <name>`.
- Injecting the compile command as the stack/package build in the generic fallback — the package build comes ONLY from §4.1 Stack-up; missing it for an artifact-copying Dockerfile → WARN + skip, never guess.
- Leaving the gate-5 docker stack up (orphan) — tear down `docker compose down -v` after the gate.
- Resetting `gate5Strikes` to 0 on a resumed flight — read the existing sidecar and continue the count.
- Claiming a UI AC "verified" by reading code beyond "a handler/route exists" (behavioral UI proof = human walk).
