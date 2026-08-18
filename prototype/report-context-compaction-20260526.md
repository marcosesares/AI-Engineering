> **SUPERSEDED — historical incident record, NOT live guidance.** ADR 0022 removed in-skill context monitoring entirely: no 65% threshold, no `context-checkpoint`, no unconditional gate reset, no handoff/respawn. Flight now runs one Task per spawn and exits. Nothing in this report describes current behavior — read it for the incident only, never as a rule to follow. Current runaway brakes: forced fan-out + inline-impl STOP (ADR 0022) and the bounded-shell contract (ADR 0033).

# Report: Context Compaction Failure — 2026-05-26
## Session: e74140fb-8605-45b6-a2b1-c1431ba673c1
## Task: Student Dashboard + Enrollment + Course Browse (5 stories)

---

## 1. What happened

The orchestrator crossed the 65% context threshold during the **HARD GATE 5 / live verification phase** but did not trigger `context-checkpoint`. The session continued until the system forced automatic compaction at **83.5%** during task close (post-human-QA). The compaction produced a usable summary; the session resumed and completed. No implementation work was lost, but the checkpoint rule was violated.

---

## 2. Token progression (context window: 200,000 tokens; 65% = 130,000)

| Time     | Phase                            | Tokens  | %    | Event                                       |
|----------|----------------------------------|---------|------|---------------------------------------------|
| 15:31    | Session start (handoff bootstrap)| 30,305  | 15%  | Read pre-impl handoff, prd.json, progress.txt |
| 15:42    | Loop — S01 fan-in                | 60,305  | 30%  | S01 done, dispatching S02                   |
| 15:56    | Loop — S02 fan-in                | 72,249  | 36%  | S02 merged, creating S03 worktree           |
| 16:04    | Loop — S03 fan-in + S04/S05 fan-out | 83,142 | 42% | S04+S05 dispatched in parallel              |
| 16:09    | Loop — S04+S05 fan-in            | 99,808  | 50%  | All 5 stories merged                        |
| 16:13    | **HARD GATE 4 passed**           | 104,148 | 52%  | 280 tests green, suite run complete         |
| 16:20    | **⚠ 65% threshold crossed**      | 129,944 | **65%** | Playwright: clicking /student/courses link (HARD GATE 5 verification) |
| 16:28    | HARD GATE 5 — live verification  | 158,044 | 79%  | Entering post-impl review (review subagent) |
| 18:15    | Human-QA — user approved         | 163,456 | 82%  | User message received, processing amendments |
| 18:17    | **System compaction triggered**  | 167,095 | **83.5%** | During task close (writing constitution v6, V9 migration) |
| 18:17    | **Resumed from compaction**      | 37,444  | 19%  | Compaction summary injected                 |
| 18:17+   | Task close continued             | —       | —    | Handoff, commit, session ended normally     |

---

## 3. Where the 65% threshold was crossed

**Phase:** HARD GATE 5 — verification  
**Sub-activity:** Playwright live browser verification (student enrollment flow)  
**Specific event:** Clicking the "Explorar Cursos" link from `/student/dashboard` to navigate to `/student/courses` (Line 468, 16:20:47)  
**Why rapid growth:** Playwright `browser_snapshot`, `browser_take_screenshot`, and `browser_evaluate` tool results each add 500–2,000 tokens. The verification loop made ~30 Playwright calls from 52% (GATE 4 passed) to 65%, adding ~25K tokens in under 8 minutes.

---

## 4. Where compaction occurred

**Phase:** Post-human-QA / task close  
**Trigger:** System automatic compaction (not orchestrator-triggered)  
**Context at compaction:** 167,095 tokens (83.5%)  
**Context after compaction:** 37,444 tokens (19%)  
**Timestamp:** 18:17:27 (1 hour 52 minutes after 65% crossed)

The orchestrator received the user's human-QA response at 18:15 (81.7%) and was processing the amendment promotion + V9 migration + Keycloak realm update. Compaction fired mid-response, between tool calls. The compaction summary correctly captured:
- All 5 stories done
- Amendments A/B/C to promote
- V9 migration and Keycloak user to add

---

## 5. Root cause

The `context-checkpoint` rule ("Checkpoint at 65% context — write handoff doc, end session") is defined in the orchestrator instructions but was not enforced during the **Playwright browser verification loop**. Two contributing factors:

**a) No periodic context check during tool-heavy phases.**  
The orchestrator focused on browser interactions and did not pause to assess context size. The checkpoint rule requires the orchestrator to self-monitor but provides no mechanism to interrupt a tool loop mid-step.

**b) Playwright verification is the highest token-growth phase.**  
Each browser interaction (navigate + snapshot + screenshot + evaluate) costs ~2,000–4,000 tokens. GATE 5 verification for a 5-story feature involves 15–30 browser steps. The jump from GATE 4 (52%) to GATE 5 end (79%) consumed ~54K tokens — more than any other phase.

**c) 65% → compaction gap was too large.**  
The orchestrator crossed 65% at 16:20 and compaction triggered at 18:17 — 117 minutes and ~37K tokens later. The checkpoint rule exists precisely to avoid this, but was silently skipped.

---

## 6. Impact

| Item | Outcome |
|------|---------|
| Implementation work | ✅ No loss — all commits already on master |
| prd.json state | ✅ Preserved in compaction summary |
| progress.txt | ✅ Preserved in compaction summary |
| Human-QA gate | ✅ Completed in resumed session |
| Amendment promotion | ✅ Completed in resumed session |
| V9 migration + Keycloak seed | ✅ Completed in resumed session |

Outcome was recoverable because: (1) all code was committed, (2) prd.json + progress.txt were on disk, (3) the compaction summary was accurate.

---

## 7. Recommendations for skill refinement

### R1 — Mandatory checkpoint check before starting GATE 5 / live verification

Insert a context-size check immediately after GATE 4 passes, before entering the Playwright loop. If already ≥ 60%, write handoff + end session instead of starting verification. Verification can be picked up in a fresh session.

**Why 60% not 65%:** Playwright verification consumes ~5K tokens per turn. A full student flow (login → navigate → enroll → check dashboard) takes 10–15 turns = ~50–75K tokens. Starting at 65% would blow past the limit mid-flow with no recovery.

### R2 — Checkpoint after each major GATE, not just at 65%

After GATE 4 (suite green), write `progress.txt` + `prd.json` to disk before proceeding to verification. This is already implied by the loop (update state after each story), but should be explicit: "after every hard gate, flush state to disk."

### R3 — Add a Playwright budget rule to the constitution

> **BR-PLAYWRIGHT-01**: Live verification via Playwright adds ~2–4K tokens per browser interaction. A full regression flow costs ~30–50K tokens. If context is ≥ 55% when verification starts, write a mid-verification handoff and split across sessions. Never start a Playwright session if context ≥ 60%.

### R4 — Warn when threshold was already missed

If at session start the orchestrator detects context ≥ 65% (resumed from compaction mid-flow), it should immediately: (a) write a new handoff doc, (b) confirm state to user, (c) resume from handoff in a fresh session rather than continuing in a degraded context.

---

## 8. What a correct checkpoint run would have looked like

At Line 468 (65%, 16:20 PM), after clicking to /student/courses:

```
## Checkpoint at 65%

Context: 65% (130K / 200K). Hard gate rule: write handoff, end session.

State:
- All 5 stories done, merged, tests green
- HARD GATE 4 passed (280 tests, 16:13)
- HARD GATE 5 in progress: Playwright verification at /student/courses
- Acceptance criteria verified so far: login ✅, Cursos nav ✅, dashboard empty state ✅
- Remaining: enroll flow, toast, Matriculado badge, dashboard reflection

Writing handoff → prd.json → progress.txt → end session.
```

The next session would resume from that handoff, complete the remaining Playwright steps (~3–5 turns), and proceed to post-impl review — starting at ~20% context.
