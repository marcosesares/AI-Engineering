# Schema — ARCHITECTURE.md

Durable, project-level reference: THIS project's structure + project-specific conventions. "Right route" map every slice sub-agent steers by. Lives at repo root (sibling to CONTEXT.md), NOT under `.e2e-engineering/`. See ADR 0013.

## Boundary (no overlap with other doc-types)

| Doc | Holds | Scope |
|-----|-------|-------|
| CONTEXT.md | glossary — terms only | durable |
| constitution.md | **generic** engineering standards — HOW to write any code | durable, cross-project |
| **ARCHITECTURE.md** | **project-specific** structure + conventions — WHERE code goes, WHAT owns what | durable, this-project |
| ADRs | point-in-time decision + rationale | append-only log |
| codebase-map.md | this-change blast-radius snapshot | per-task, rots |

**Split rule:** generic best practice ("write test first") → constitution. Project-specific rule ("completion endpoints extend domain resource, never new class") → ARCHITECTURE.md. ARCHITECTURE.md = synthesized current state; ADRs = changelog behind it.

## Template (index + five sections)

```markdown
# Architecture — <project name>

## §Index
§1: L<start>–L<end>
§2: L<start>–L<end>
§3: L<start>–L<end>
§4: L<start>–L<end>
§5: L<start>–L<end>

## §1 Layering / module boundaries
<layers and what each owns. e.g. resource → service → repository; pages → components → api-client.>

## §2 Ownership rules
<which class/module/layer owns which concern or URL path family.>
<e.g. "EnrollmentResource owns /enrollment/** — completion endpoints live here, not new class.">

## §3 Naming conventions
<per layer: files, classes, components, endpoints.>
<e.g. "pages: {Domain}Page.tsx; resources: {Domain}Resource.java.">

## §4 Integration patterns
<API-client method shape; i18n key scheme/prefixes; how new endpoint/component plugs in.>

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

## §5 Anti-patterns / wrong routes
<explicit "don't X, do Y" list. Traps fresh sub-agent would fall into.>
<e.g. "DON'T create parallel resource class at existing URL path — extend owner.">
```

**§Index rule**: writer fills line numbers AFTER writing all sections. Readers use `offset/limit` — orchestrator fetches only sections relevant to slice's layer/ownership (e.g. §1+§2 for to-issues integration pin, §2+§3+§5 for quality-check on a ui slice).

## Lifecycle
- **Lazy create** — born when first structural decision crystallizes (greenfield), or seeded by `adopt`/`map-codebase` (brownfield). No empty-doc ceremony. Absent at impl entry → readers skip (nothing to violate yet).
- **Writes: human-phase only** (ADR 0013): seeded/drafted in pre-impl (human-reviewed); amended at post-impl human-QA gate. Implementation loop READ-ONLY — drift spotted by sub-agent = PROPOSED in summary, staged as pending amendment, never written mid-loop.
- **§Index update**: any writer (adopt, map-codebase, human at QA gate) MUST update §Index line numbers after every edit.

## Read by
- Pre-impl (to-prd, map-codebase) — proposed feature doesn't take wrong route.
- to-issues — pins each story's `integration` decision from §1–§2 (use §Index offset/limit).
- Fan-out — orchestrator injects SCOPED slice (layer naming + ownership + anti-patterns), not whole doc (use §Index offset/limit for relevant sections).
- Quality-check (per-slice review) — full doc, orchestrator-side, catches ownership/naming/duplicate violations before merge.

## Rules
- Project-specific only. Generic standards → constitution.md; terms → CONTEXT.md.
- Synthesized current state — single readable map, not pile of decisions (those are ADRs).
- Greenfield with no architecture decided yet → file may not exist; valid.
