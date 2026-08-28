# Standard — Backend / API work

Canonical baseline for `api`/`logic` slices. Injected into every api/logic slice sub-agent alongside the [constitution](../constitution.md) and the [api-testing standard](api-testing.md), and handed to the [backend-architect](../agents/backend-architect.md) reviewer. Project-specific layering (e.g. Resource→Service→Repository, ORM-in-transaction services, reactive end-to-end) stays in ARCHITECTURE.md §1/§5 and overrides this floor.

## Override rule (read FIRST)
**ARCHITECTURE.md §1–§5 wins for layering/naming/anti-patterns where they conflict.** This doc is the generic floor; the project's actual structure lives in ARCHITECTURE.md.

## Ownership / seams
- Extend the named owner from the slice's `integration` decision — never invent a parallel class/file/endpoint an existing one already owns.
- One client/config per dependency; reuse existing logic, don't duplicate it.

## Layering
- Logic sits in the layer ARCHITECTURE.md §1 defines; no leakage across the seams it names.
- The API layer does API work; DB work belongs below the seam — no API doing DB work or vice-versa.

## API shape
- Contracts match existing endpoints: same error envelope, status codes, and idempotency where relevant.
- Validate every user-controlled path/query/body parameter before use.

## Constitution
- simplicity-first (new code), surgical-changes (edits), scope discipline (no "while I'm here").
