# Standard — Slice test quality

Canonical baseline for the [test-reviewer](../agents/test-reviewer.md)'s quality checks. Injected into EVERY slice sub-agent (all slice types get the test-reviewer) alongside the [constitution](../constitution.md). The [api-testing standard](api-testing.md) governs API mechanics (`request` fixture, M1 stack, data isolation, traceability); this doc governs coverage + quality for all slice types. PROJECT's own API-test conventions (ARCHITECTURE.md §4) override the api-testing baseline; the rules below apply to every slice regardless.

## AC coverage (FIRST)
- Map every `acceptanceCriteria[]` to a covering test BEFORE declaring done — any AC without a test is a defect, not a note.
- Each AC maps to a REAL assertion — no fake-green, no comment-only bodies, no test that cannot fail.

## Edge + negative cases
- Cover boundaries, empty/invalid input, and the error paths the AC implies even when the happy path doesn't name them.
- Negative-case test for every 403 / 404 / 409 branch the slice introduces.

## Red→green honesty
- The test genuinely fails without the production code (gate 2 not faked).

## Runner hygiene
- Real-interface interaction (real HTTP, not internal-state poking).
- Diagnosable failures — no silent `catch` swallowing the signal.
- No hardcoded sleeps — wait on conditions.
- Assert behavior, not implementation.
- `skipped=0` — no silently-skipped tests in the slice's suite.
