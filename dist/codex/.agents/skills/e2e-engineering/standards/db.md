# Standard — Database / schema work

Canonical baseline for schema/data slices. Injected into every `schema/db` slice sub-agent alongside the [constitution](../constitution.md), and handed to the [dba](../agents/dba.md) reviewer. Project-specific ownership/naming (which table/column owns which concern) stays in ARCHITECTURE.md §1–§2 and overrides this floor.

## Override rule (read FIRST)
**ARCHITECTURE.md §1–§2 wins for ownership/naming where they conflict.** This doc is the generic floor; the project's actual data model lives in ARCHITECTURE.md. Extend the named table/column the `integration` decision or ARCHITECTURE.md names — never invent a parallel table or column for an existing concept.

## Schema design
- Types / nullability / constraints correct for the domain — no "nullable whatever fits".
- Normalize what must be normalized; no redundant columns.
- Constraints live IN the database, not only in app code.

## Migrations
- Reversible / forward-safe.
- No destructive change without an explicit migration path.
- Ordering safe against existing data.
- Renumber migrations into the task's reserved range; NEVER reuse a reserved range.
- NEVER edit an already-applied migration in place (checksum drift) — add a new migration instead.

## Integrity
- Foreign keys, unique constraints, and cascade behavior match the PRD domain rules exactly.

## Indexing + query cost
- Index every WHERE / ORDER BY / JOIN predicate the slice introduces.
- No obvious full-scan or N+1; index choice matches the read pattern (not the write pattern).
- Entity/column definitions match the DDL exactly — no drift between the ORM entity and the schema.

## Constitution
- simplicity-first (new code), surgical-changes (edits), scope discipline (no "while I'm here").
