# Standard — API / integration testing (Playwright `request`)

Canonical baseline for automating API/integration tests in this flow (Fork Y, ADR 0024). Injected into every slice sub-agent alongside the [constitution](../constitution.md), and handed to [test-reviewer](../agents/test-reviewer.md). UI is NOT automated — this doc covers API/integration only.

## Override rule (read FIRST)
**Project already has API/integration tests → follow THEIR conventions** (framework, file layout, helpers, fixtures). This doc is the baseline ONLY when the project has none. The project's actual stack + conventions live in **ARCHITECTURE.md §4** and override everything below. Recognize existing patterns (brownfield) before introducing new ones — no parallel test harness.

## Mechanic (M1 — run against the real stack)
API/integration tests hit a **running stack via docker-compose** — real integration, no boundary mocking. `baseURL` + auth + how the stack comes up are defined in **ARCHITECTURE.md §4**. The app + its DB must be up and reachable from the test runner. Slice worktrees inherit the docker env files (flight Step 2/3 bootstrap).

**Data isolation (parallel slices share one stack):** each test seeds AND cleans its own data via API in `beforeAll`/`afterAll`, namespaced to avoid collision. Never depend on shared mutable state. If the project cannot isolate per-test data, API-test slices must serialize (`depends_on` edge) — do not run them concurrently against the same mutable stack.

## Core: `request` fixture
Built-in fixture. Honors `baseURL` / `extraHTTPHeaders` / proxy from config. No browser.

```ts
test('create issue', async ({ request }) => {
  const res = await request.post(`/repos/${USER}/${REPO}/issues`, { data: { title: '[Bug] 1' } });
  expect(res).toBeOK();
  const issues = await (await request.get(`/repos/${USER}/${REPO}/issues`)).json();
  expect(issues).toContainEqual(expect.objectContaining({ title: '[Bug] 1' }));
});
```

- **Methods:** `get/post/put/patch/delete/head/fetch`
- **Options:** `{ data, params, headers, form, multipart }`
- **APIResponse:** `ok()`, `status()`, `json()`, `text()`, `body()`, `headers()`
- **Assert:** `expect(response).toBeOK()` (web-first; waits)

## Context flavors (cookie behavior differs)
| Context | Cookie jar |
|---|---|
| `page.request` / `context.request` | share + update browser context cookies (send Cookie, honor Set-Cookie) |
| `playwright.request.newContext({ baseURL, extraHTTPHeaders })` | isolated, own jar — `dispose()` when done |

## Common patterns
- **Setup/teardown:** manual context in `beforeAll`/`afterAll` — seed server state or clean up via API.
- **Mixed UI+API:** create state via API, verify in browser (or reverse) — faster than clicking through UI. (In this flow the browser/UI half is Manual.)
- **Auth reuse:** `apiRequestContext.storageState({ path })` — log in via API once, save state, reuse.

## Date/time boundaries (frozen clock)

Date filters + summary windows: boundary-test at UTC midnight edges (23:59 / 00:01) via an injected `Clock` / frozen time. A `LocalDate.now()`-style local-date window fails only 00:00–05:00 UTC (two carried fixes in the payments drain) — windows are zone-consistent UTC, and the boundary cases are the test that proves it. Never reintroduce local-date windows.

## TDD (gate 2)
For any endpoint a slice implements: write the **failing** API test FIRST (assert observable response), confirm it fails for the right reason, THEN implement. Red-green-refactor, same as unit.

## Traceability
Annotate each test with its test-case id (Playwright `annotation`), so test → TC id is auditable. Disposition = **Automated**.

## Red flags (stop)
- **Mocked unit tests as Gate 2 substitute** — tests that mock at the repo/service layer (e.g. `@InjectMock`, `Mockito`, test doubles for the DB/session layer) do NOT satisfy Gate 2 for an API endpoint slice. Real-stack `request` test required. Mocking hides session/transaction/reactive context bugs (e.g. Hibernate Reactive concurrent session). Exception: ARCHITECTURE.md §4.1 explicitly documents mocked tests as the project standard.
- Mocking the boundary you're verifying (`page.route` on the API under test) — that's not integration. Mock only third parties.
- Hardcoded sleeps instead of web-first assertions / wait conditions.
- Shared mutable fixtures across parallel slices (data contention) — isolate or serialize.
- Asserting internal state instead of the HTTP response (constitution testing principle 1/6).
- Inventing a new test harness when the project already has API-test conventions (override rule).

Depth reference (not the contract): knowledge-base `wiki/tools/playwright` — [[playwright-network]], [[playwright-auth-state]], [[playwright-assertions]].

## Per-domain fixture helpers

Every domain (course/lesson/asset/session…) gets seed/cleanup fixture helpers in the API-test project — never per-spec hand-seeding. Cross-spec data contamination is a measured failure class (video flight: 4 full-suite failures from every spec seeding the same rows). Each spec calls its domain's fixture; cleanup runs in `afterAll` so specs stay independent.

## Testcontainers fallback (docker-CLI-container)

Docker Desktop 29's docker-java incompatibility breaks Testcontainers. Canonical workaround: the docker-CLI-container fallback — run the container via the docker CLI and point the test config at it. Document the exact commands in ARCHITECTURE.md §4.1b when a repo hits this; the standard here is the fallback pattern, not Testcontainers-or-nothing.
