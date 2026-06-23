---
name: e2e-deslop
description: Recurring, repo-wide architecture-deepening scan for the e2e-engineering flow. Fans out one architecture-scout per eligible module area, surfaces refactor candidates (shallow modules, duplicated rules, missing seams, poor locality, untestable spots), and routes human-picked ones into the Task queue as refactor Tasks. Incremental — skips areas already covered + unchanged via the scan ledger. Code is NEVER auto-refactored. Use when the user says "de-slop", "deslop", "/e2e-deslop", "architecture scan", "scan for tech debt", "find refactor candidates", or "architecture deepening".
---

# e2e-deslop — repo-wide architecture-deepening scan (Codex runtime)

Sibling to [/e2e-engineering](../e2e-engineering/SKILL.md) + [/e2e-flight](../e2e-flight/SKILL.md). Read CONTEXT.md for any term. Governed by ADR 0026.

Recurring, repo-wide scan that surfaces architecture-deepening opportunities as refactor candidates (`$sharedSkillsRoot/schemas/refactor-candidate.json.md`) → triage (`$sharedSkillsRoot/impl/triage.md`) → human-picked refactor Tasks in `queue.json`. **Incremental** via the scan ledger (`$sharedSkillsRoot/schemas/scan-ledger.json.md`): scan only areas not already covered + unchanged. **Code is NEVER auto-refactored** — surface candidates only (same wall as map-codebase §5). Deeper than map-codebase §5's change-scoped byproduct: a dedicated `architecture-scout` per area.

**Token rule.** Inline deep-analysis over a whole repo = blowup. Fix: fan-out FORCED (Step 0) — one scout per eligible area; orchestrator doing the analysis itself = hard STOP. Scouts hold the heavy reads, return compact manifests.

---

## Step 0 — bootstrap + forcing mechanism (FIRST, always)
1. **Resolve shared skill root once.** Set `sharedSkillsRoot = skills/e2e-engineering` from repo root. Verify `constitution.md`, `impl/triage.md`, `schemas/scan-ledger.json.md`, `schemas/refactor-candidate.json.md`, `schemas/queue.json.md`, and `agents/architecture-scout.md` exist. Missing → `<e2e-stall reason="shared-skills-missing" />` + EXIT. Never probe `.agents/skills/...` or `.claude/skills/...` for shared files during execution.
2. **Capability probe (fail-closed).** Static requirement: `spawn_agent` / `spawn_agents_on_csv`. Live no-op probe fails → `<e2e-stall reason="fanout-unavailable" />` + EXIT. NEVER fall back to inline area analysis.
3. Scouts are READ-ONLY — no worktree, no branch, no code changes. De-slop writes only `.e2e-engineering/` state (ledger, candidate manifests) + queue/triage entries.
4. Orchestrator output = caveman-ultra, essential only.

## Step 1 — resolve scan areas
- ARCHITECTURE.md exists → areas = §1 module boundaries (use §Index for offset/limit).
- No ARCHITECTURE.md → areas = top-level source subdirectories (fallback). Note the weaker grain in the Step 6 summary.
- User named an area/path → scope to it (still ledger-checked).

## Step 2 — compute eligible set (scanned-since-change)
Read `.e2e-engineering/scan-ledger.json` (`$sharedSkillsRoot/schemas/scan-ledger.json.md`). Per area, hash its file subtree and decide:
- absent OR subtree hash ≠ `scannedAtCommit` OR `verdict:candidate` not yet actioned → **eligible**.
- `verdict:accepted` (human won't-fix) → **muted**, skip until manually reopened.
- `verdict:clean` + unchanged → skip.

**No silent caps.** Log the eligible set AND the skipped set (with reason). Nothing eligible → report "all areas covered + unchanged" + EXIT.

## Step 3 — fan-out scouts (FORCED)
Dispatch ONE scout per eligible area via `spawn_agents_on_csv` / `spawn_agent`, parallel where slots allow (bounded batches otherwise). In Codex, use standard `worker` agents and inject the canonical spec from `$sharedSkillsRoot/agents/architecture-scout.md` into each prompt — `architecture-scout` is a prompt role, NOT a `spawn_agent.agent_type`. Inject also: `$sharedSkillsRoot/constitution.md` + (when present) ARCHITECTURE.md §1–§5 (§Index for offset/limit) + the area's file list. Each returns a refactor-candidate manifest (`$sharedSkillsRoot/schemas/refactor-candidate.json.md`): `{ area, verdict, candidates[] }`.
- **DO NOT analyze an area inline.** Orchestrator doing scout work = hard red-flag STOP (blowup cause).

## Step 4 — fan-in + persist (sole writer)
Per returned manifest:
- ≥1 candidate → write `.e2e-engineering/deslop/<area-slug>/refactor-candidates.json`; set ledger entry `verdict:candidate`, `candidateManifestPath`, `scannedAtCommit` = current subtree hash.
- empty → set ledger entry `verdict:clean`, `candidateManifestPath:null`, `scannedAtCommit` = current subtree hash.
- Reject un-anchored candidates (no `file:line`) without persisting.

## Step 5 — triage + human pick
Route all surfaced candidates through `$sharedSkillsRoot/impl/triage.md` (externally-sourced intake — NOT born ready-for-agent). Present the candidate set (priority + blastRadius + behaviorPreserved). Human picks which become refactor Tasks:
- Picked → append refactor Task to `queue.json` (`status:todo`, `selected:false`, refactor-shaped — runs FULL flow, ADR 0012). `behaviorPreserved` seeds the safety-net acceptance criterion.
- Human marks an area won't-fix → set ledger `verdict:accepted` (mutes until reopened).
- **HARD interactive STOP** — do NOT auto-create refactor Tasks.

## Step 6 — exit
One compact summary: areas scanned / skipped (with reasons) / candidates found / refactor Tasks created. Emit `<e2e-deslop-done scanned="N" candidates="M" tasks="K" />`. No respawn, no loop.

---

## Red flags (stop)
- Inline area analysis instead of scout fan-out (blowup cause — Step 0 forces fan-out; inline = STOP).
- Probing `.agents/skills/...` or `.claude/skills/...` for shared files after Step 0; use `$sharedSkillsRoot` only.
- Auto-refactoring code (forbidden — surface candidates only; the map-codebase §5 wall applies).
- Auto-creating refactor Tasks without the human pick (Step 5 is a HARD interactive stop).
- Re-scanning an area that is `clean`/`accepted` AND unchanged (the scan ledger exists to skip it).
- Permanent "scanned" latch with no change-detection (goes blind to re-rot — eligibility is hash-based).
- Spawning Codex `architecture-scout` as an `agent_type` instead of `worker` + injected spec.
- Emitting review severities (Critical/Important/Minor) for candidates (rank by priority + blastRadius).
