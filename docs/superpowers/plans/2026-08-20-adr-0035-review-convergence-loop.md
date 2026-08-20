# ADR 0035 — Review Convergence Loop + finding-verifier Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every expert-review finding in `/e2e-flight` terminate in one of exactly three ways — fixed, refuted with evidence, or carried forward as a followup — and stop a slice ever blocking on review quality.

**Architecture:** This repo ships a dual-runtime skill tree. Runtime-neutral content lives in `skills/e2e-engineering/**` (schemas, canonical agent specs, sub-skills). Two runtime entry points wrap it: `.claude/skills/e2e-flight/SKILL.md` (uses markdown links like `../../../skills/e2e-engineering/...`) and `.agents/skills/e2e-flight/SKILL.md` (uses backtick refs like `` `$sharedSkillsRoot/...` `` — no markdown links). `node scripts/build-dist.js` mirrors all of it into `dist/`; `node scripts/validate.js` gates on dist freshness, markdown-link resolution, and JSON validity. There is no test framework — **the test cycle is a grep assertion plus `npm run build && npm run validate`**. Every task below asserts on text before and after the edit, so a one-runtime-only edit fails loudly.

**Tech Stack:** Markdown (caveman-ultra register for skill docs), JSON schemas documented as Markdown, Node 18+ build/validate scripts, PowerShell wrapper generator (`pwsh`).

**Spec:** `docs/adr/0035-review-convergence-loop-and-finding-verifier.md` (committed as `37829a4`)

## Global Constraints

- **Skill docs are maintained in caveman-ultra.** Drop articles and filler; keep every technical term exact. Match the register of the surrounding text in the file you edit. Applies to `SKILL.md`, `schemas/*.md`, `agents/*.md`, `impl/*.md`.
- **Edit BOTH runtime trees or the change is a bug.** `.claude/skills/e2e-flight/SKILL.md` uses markdown links (`[label](../../../skills/e2e-engineering/x.md)`). `.agents/skills/e2e-flight/SKILL.md` uses backtick refs (`` `$sharedSkillsRoot/x.md` ``) and **no markdown links** — the build rewrites markdown links only, so a markdown link in the `.agents` tree becomes a broken dist link.
- **ADRs are cited as plain text, never markdown links.** Write `ADR 0035`, never `[ADR 0035](docs/adr/...)`. `docs/adr/` is not built and not link-checked.
- **`docs/` and `.agents/` are in `.gitignore`.** Already-tracked files there still show as modified, but a **NEW** file under `docs/` is invisible to `git status` and needs `git add -f`. This plan file itself needs `git add -f`.
- **`npm run build` BEFORE `npm run validate`.** `validate.js` has a dist-freshness gate that compares source against `dist/` byte-for-byte; skipping the build guarantees a failure.
- **Never hand-edit `.claude/agents/*.md`.** They are generated from `skills/e2e-engineering/agents/*.md` + `agents.manifest.json` by `skills/e2e-engineering/scripts/generate-agent-wrappers.ps1`.
- **Severity enum is exactly `Critical | Important | Minor`.** `NeedsVerification` and `Unsubstantiated` are NOT severities. The former becomes a pre-verify signal, the latter retires entirely.
- **Bounce cap = 4.** Absolute per slice. Never reset.
- **`rtk` wraps shell output reads in this repo and truncates long lines.** For text assertions prefer `grep -c` (counts) over `grep -n` (lines) — counts survive truncation. For long-line inspection use `sed -n '<start>,<end>p'`.
- **Out of scope:** version bump and release. `package.json` stays at `1.12.0`; releasing is a separate decision per `RELEASING.md`.

---

## File Structure

**Created:**
- `skills/e2e-engineering/agents/finding-verifier.md` — canonical spec for the new adjudicator agent. Runtime-neutral prose: rubric, evidence bar, budget, JSON return contract.
- `skills/e2e-engineering/schemas/followups.json.md` — schema for the cap-exhaustion carry-forward record.
- `.claude/agents/finding-verifier.md` — **generated**, do not hand-write.

**Modified:**
- `skills/e2e-engineering/agents.manifest.json` — new `finding-verifier` role entry (tools, sandbox, description).
- `skills/e2e-engineering/schemas/review-result.json.md` — finding gains `id`, `evidence`, `state`, `verification`; severity enum narrowed.
- `skills/e2e-engineering/schemas/resume.json.md` — gains `bounce`, `verifyWave[]`, `suppressed[]`.
- `skills/e2e-engineering/schemas/prd.json.md` — `blocked` narrowed to gate-3 only; `notes` gains the cap-exhaustion form.
- `skills/e2e-engineering/schemas/qa-signoff.md` — template gains `## Followups` + `## Release Blockers`; flight-fills list updated.
- `skills/e2e-engineering/schemas/flow-retro.md` — retro counters swapped.
- `skills/e2e-engineering/impl/triage.md` — intake source #4 (flight followups).
- `skills/e2e-engineering/agents/backend-architect.md`, `dba.md`, `frontend-reviewer.md`, `test-reviewer.md` — cite-every-severity + no-action-Minor-dropped.
- `.claude/skills/e2e-flight/SKILL.md` — Step 0 tally, Step 3.3 rewrite, Step 6 followups, red flags.
- `.agents/skills/e2e-flight/SKILL.md` — same, `$sharedSkillsRoot` register, plus severity-enum de-drift.
- `CONTEXT.md` — glossary: rewrite `Expert-review wave`, `Mechanical fix`, `Three-tier bounce`, `Review manifest`, `Reviewer prompt role`, delta bullet; add four new entries.
- `README.md` — agent roster line.

**Untouched on purpose:** `skills/e2e-engineering/schemas/queue.json.md` (ADR 0017 writer table stays intact — flight still never creates entries), `skills/e2e-engineering/agents/product-designer.md` and `architecture-scout.md` (not review-wave reviewers), `.cursor/rules/e2e-flight.mdc` (thin router, carries no review detail).

---

### Task 1: `finding-verifier` agent

**Files:**
- Create: `skills/e2e-engineering/agents/finding-verifier.md`
- Modify: `skills/e2e-engineering/agents.manifest.json`
- Generated: `.claude/agents/finding-verifier.md` (via script, never by hand)

**Interfaces:**
- Consumes: nothing from earlier tasks (this is the first).
- Produces: the agent file `.claude/agents/finding-verifier.md`, which Task 6 markdown-links to as `[finding-verifier](../../agents/finding-verifier.md)` from `.claude/skills/e2e-flight/SKILL.md`. Task 7 refers to it as `` `finding-verifier` `` with the canonical spec at `` `$sharedSkillsRoot/agents/finding-verifier.md` ``. Produces the verifier return contract consumed by Tasks 2 and 4:
  `{ findingId: string, resolution: "confirmed"|"refuted"|"inconclusive", severity: "Critical"|"Important"|"Minor"|null, evidence: string|null, reason: string }`

- [ ] **Step 1: Write the failing assertion**

Run all three; record the output:

```bash
grep -c "finding-verifier" skills/e2e-engineering/agents.manifest.json
ls skills/e2e-engineering/agents/finding-verifier.md
ls .claude/agents/finding-verifier.md
```

Expected: `0` from the grep, and `No such file or directory` from both `ls` calls.

- [ ] **Step 2: Create the canonical spec**

Create `skills/e2e-engineering/agents/finding-verifier.md` with exactly this content:

````markdown
# finding-verifier — unproven-finding adjudicator

You adjudicate ONE expert-review finding that arrived WITHOUT proof. You are not a reviewer: you do not hunt for new problems and you do not judge the slice. You either produce hard evidence for the claim you were handed, or you refute it. Read-only — no edits, no shared-state writes.

## Two input modes, one contract
- **NeedsVerification** — a reviewer had a coverage or behavior doubt and could not prove it. Resolve the doubt inside the disputed source/test scope you were given.
- **Un-cited Critical/Important** — a reviewer asserted a defect with no `file:line`, test name, log path, or searched-absence scope. Find the cite, or refute the assertion.

## What counts as evidence
`confirmed` requires ONE of:
- `file:line` — the exact line exhibiting the defect.
- a test name — the test that fails, is absent, or asserts nothing.
- a log path plus the line in it.
- an explicit searched-absence scope — the glob/grep you ran AND the full set it covered, proving the thing is nowhere in that set.

"I looked and didn't see it" is NOT a scope. Anything weaker than the list above is `refuted`.

## Adversarial default
Kill the finding unless the evidence forces you to keep it. Out of budget with no cite → `inconclusive`, which the orchestrator treats as `refuted`. Never stretch to confirm — a manufactured bounce costs a whole fix round.

## Budget (hard)
≤8 tool calls total. Go straight at the disputed scope; never re-read the whole slice diff. Return bounded JSON only — never prose, never a loop, never a hang.

## Return format
```json
{
  "findingId": "<id from the review-result finding>",
  "resolution": "confirmed | refuted | inconclusive",
  "severity": "Critical | Important | Minor | null",
  "evidence": "file:line | test name | log path:line | searched-absence scope | null",
  "reason": "one line — why this resolution"
}
```
- `confirmed` → `severity` and `evidence` both REQUIRED. You may raise or lower the reviewer's severity; you own it now.
- `refuted` / `inconclusive` → `severity: null`, `evidence: null`, and `reason` states what you checked.

## Red flags (stop)
- Raising a NEW finding — you adjudicate the one you were handed, nothing else.
- Confirming on plausibility, code smell, or "likely" — evidence or nothing.
- Editing any file, or writing `prd.json` / `progress.txt` / any sidecar.
- Burning budget re-reading the whole diff instead of the disputed scope.
- Returning prose instead of the JSON contract.
````

- [ ] **Step 3: Add the manifest role**

In `skills/e2e-engineering/agents.manifest.json`, insert this entry immediately after the `"test-reviewer"` block and before `"architecture-scout"` (mind the trailing comma on the preceding block):

```json
    "finding-verifier": {
      "claude_name": "finding-verifier",
      "description": "Unproven-finding adjudicator. Takes ONE expert-review finding that arrived without proof — a NeedsVerification doubt or an un-cited Critical/Important — and either produces hard evidence (file:line, test name, log path, explicit searched-absence scope) or refutes it. Adversarial default: no cite means refuted; inconclusive is treated as refuted. Read-only, budget 8 tool calls, returns bounded JSON. Dispatched by /e2e-flight's verify wave, once per unproven finding, before bounce classification.",
      "tools": ["Read", "Grep", "Glob", "Bash"],
      "model": null,
      "sandbox_mode": "read-only",
      "mcp_servers": []
    },
```

- [ ] **Step 4: Verify the JSON still parses**

```bash
node -e "const m=require('./skills/e2e-engineering/agents.manifest.json');console.log(Object.keys(m.roles).join(','))"
```

Expected: `backend-architect,dba,frontend-reviewer,product-designer,test-reviewer,finding-verifier,architecture-scout`

- [ ] **Step 5: Generate the Claude wrapper**

```bash
pwsh -NoProfile -File skills/e2e-engineering/scripts/generate-agent-wrappers.ps1
```

Expected: `Written : ...\.claude\agents\finding-verifier.md` among the output lines, and `Done. 7 role(s) processed.`

- [ ] **Step 6: Verify the assertion now passes**

```bash
grep -c "finding-verifier" skills/e2e-engineering/agents.manifest.json
grep -c "unproven-finding adjudicator" .claude/agents/finding-verifier.md
grep -c "^name: finding-verifier" .claude/agents/finding-verifier.md
```

Expected: a non-zero count from each (`1` for the last two).

- [ ] **Step 7: Build and validate**

```bash
npm run build && npm run validate
```

Expected: last line `validate: ok`

- [ ] **Step 8: Commit**

```bash
git add skills/e2e-engineering/agents/finding-verifier.md skills/e2e-engineering/agents.manifest.json .claude/agents/finding-verifier.md dist
git commit -m "feat: add finding-verifier agent (ADR 0035)"
```

---

### Task 2: Finding vocabulary — severity vs state

**Files:**
- Modify: `skills/e2e-engineering/schemas/review-result.json.md`

**Interfaces:**
- Consumes: the verifier return contract from Task 1 (`resolution`, `severity`, `evidence`, `reason`).
- Produces: the finding shape every later task references — field names `id`, `severity`, `location`, `message`, `evidence`, `state`, `verification`. State enum: `open | fixed | dropped-refuted | open-at-cap`. Task 3 copies `severity` / `location` / `message` / `evidence` into `followups.json`; Task 4 keys `suppressed[]` off `severity` + `location` + a message hash; Tasks 6 and 7 branch on `state`.

- [ ] **Step 1: Write the failing assertion**

```bash
grep -c "dropped-refuted" skills/e2e-engineering/schemas/review-result.json.md
grep -c "open-at-cap" skills/e2e-engineering/schemas/review-result.json.md
```

Expected: `0` from both.

- [ ] **Step 2: Replace the finding shape**

In `skills/e2e-engineering/schemas/review-result.json.md`, replace this block:

```json
        {
          "severity": "Critical | Important | Minor",
          "location": "string — file:line or component/area",
          "message": "string"
        }
```

with:

```json
        {
          "id": "string — stable slug, unique within this file; the verify wave and suppressed[] key off it",
          "severity": "Critical | Important | Minor",
          "location": "string — file:line or component/area",
          "message": "string",
          "evidence": "string — file:line | test name | log path | explicit searched-absence scope. null ONLY while pre-verify",
          "state": "open | fixed | dropped-refuted | open-at-cap",
          "verification": {
            "resolution": "confirmed | refuted | inconclusive",
            "verifierEvidence": "string | null",
            "reason": "string — one line"
          }
        }
```

- [ ] **Step 3: Replace the reviewer return-shape note**

Replace this line:

```markdown
Individual reviewer return shape (never written to disk by reviewer — passed back to orchestrator):
```

and the fenced block under it, with:

````markdown
Individual reviewer return shape (never written to disk by reviewer — passed back to orchestrator). Reviewers set `severity`, `location`, `message`, `evidence`; the ORCHESTRATOR assigns `id` and `state` at fan-in and fills `verification` after the verify wave.
```json
{ "reviewerId": "string", "sliceId": "string", "findings": [ { "severity", "location", "message", "evidence" } ] }
```

Verifier return shape (one per unproven finding, `finding-verifier` — never written to disk by the verifier):
```json
{ "findingId": "string", "resolution": "confirmed | refuted | inconclusive", "severity": "Critical | Important | Minor | null", "evidence": "string | null", "reason": "string" }
```
````

- [ ] **Step 4: Replace the invariants block**

Replace the whole `## Invariants` section with:

```markdown
## Invariants
- `reviews[]` contains one entry per reviewer dispatched for this slice.
- `findings[]` empty array if reviewer found nothing. Absence of entry means reviewer was not dispatched (sliceType routing).
- **`severity` is exactly `Critical | Important | Minor`.** `NeedsVerification` and `Unsubstantiated` are NOT severities. `NeedsVerification` is a pre-verify signal a reviewer raises in place of an unproven Critical; `Unsubstantiated` is RETIRED (ADR 0035) — an un-cited claim is now spent on a `finding-verifier` and lands as `dropped-refuted` or `open`.
- **`state` transitions (ADR 0035):** `open` → `fixed` (a bounce round resolved it and the re-review no longer raises it) · `open` → `dropped-refuted` (verifier returned `refuted`, or `inconclusive` which counts as refuted) · `open` → `open-at-cap` (still open when bounce round 5 was entered; carried into `followups.json`).
- **`evidence` is non-null for every terminal finding.** Un-cited `Critical`/`Important` go to the verify wave; un-cited `Minor` is dropped without verifier spend; a finding with no action is downgraded (`Important`→`Minor`) or dropped (`Minor`).
- `verification` is null until the verify wave runs on that finding, and each finding is verified AT MOST ONCE per slice.
- `notes` records orchestrator-side anomalies only (hung reviewer proceeded-past, unavailable slot, downgraded severity misuse, dropped un-cited Minors). Absent when nothing to record.
- Written after all dispatched reviewers return — orchestrator holds findings in memory until fan-in complete.
- Orchestrator updates `prd.json` story's `reviewManifestPath` after writing this file.
- Path in prd.json is relative to Task root: `manifests/<story-id>/review-result.json`.
- Bounce rounds are tracked in `progress.txt` + `resume.json` `bounce.rounds`, not re-written to this sidecar per round; final post-loop state is persisted once.
```

- [ ] **Step 5: Verify the assertion now passes**

```bash
grep -c "dropped-refuted" skills/e2e-engineering/schemas/review-result.json.md
grep -c "open-at-cap" skills/e2e-engineering/schemas/review-result.json.md
grep -c "Unsubstantiated is RETIRED" skills/e2e-engineering/schemas/review-result.json.md
```

Expected: non-zero, non-zero, `1`.

- [ ] **Step 6: Build and validate**

```bash
npm run build && npm run validate
```

Expected: `validate: ok`

- [ ] **Step 7: Commit**

```bash
git add skills/e2e-engineering/schemas/review-result.json.md dist
git commit -m "feat: findings carry state, not pseudo-severities (ADR 0035)"
```

---

### Task 3: Followup carrier — schema, qa-signoff sections, triage lane

**Files:**
- Create: `skills/e2e-engineering/schemas/followups.json.md`
- Modify: `skills/e2e-engineering/schemas/qa-signoff.md`
- Modify: `skills/e2e-engineering/impl/triage.md`

**Interfaces:**
- Consumes: the finding shape from Task 2 (`severity`, `location`, `message`, `evidence`, `state: "open-at-cap"`).
- Produces: `tasks/<id>/followups.json` with entry fields `id`, `sliceId`, `reviewerId`, `severity`, `location`, `message`, `evidence`, `bounceRounds`, `suggestedPriority`. Tasks 6 and 7 write this file at cap exhaustion and mirror it into `qa-signoff.md`. Task 6 markdown-links the schema as `[schema](../../../skills/e2e-engineering/schemas/followups.json.md)`.

- [ ] **Step 1: Write the failing assertion**

```bash
ls skills/e2e-engineering/schemas/followups.json.md
grep -c "Release Blockers" skills/e2e-engineering/schemas/qa-signoff.md
grep -c "flight followups" skills/e2e-engineering/impl/triage.md
```

Expected: `No such file or directory`, then `0`, then `0`.

- [ ] **Step 2: Create the followups schema**

Create `skills/e2e-engineering/schemas/followups.json.md` with exactly this content:

````markdown
# Schema — followups.json

Carry-forward record for expert-review findings still `open` when a slice's bounce cap (4) was exhausted (ADR 0035). Written by orchestrator at cap exhaustion, one entry per open finding. Lives at Task root: `.e2e-engineering/tasks/<id>/followups.json`. Sole writer = orchestrator. Read by the human at QA sign-off and routed through [triage](../impl/triage.md) into new queue Tasks.

```json
{
  "taskId": "payments-monetization",
  "followups": [
    {
      "id": "string — stable slug, unique in this file",
      "sliceId": "string — story id the finding came from",
      "reviewerId": "backend-architect | dba | frontend-reviewer | test-reviewer | finding-verifier",
      "severity": "Critical | Important | Minor",
      "location": "string — file:line or component/area",
      "message": "string — the defect, one line",
      "evidence": "string — file:line | test name | log path | searched-absence scope",
      "bounceRounds": "number — rounds spent before the cap exhausted (4)",
      "suggestedPriority": "number — 1 if ANY entry in this file is Critical, else 3"
    }
  ]
}
```

## Invariants
- Written ONLY at bounce-cap exhaustion. A slice whose convergence loop reached zero open findings writes nothing here.
- **Every entry has non-null `evidence`.** An un-cited finding never reaches this file — the hygiene gate drops it or the verify wave refutes it.
- `suggestedPriority` is UNIFORM across the file: `1` if any entry is `Critical`, else `3`. It is a RECOMMENDATION; triage and the front door set the real queue priority.
- **Flight NEVER writes `queue.json` from this file.** ADR 0017's writer table is intact: `/e2e-engineering` triage (intake source #4) creates the Task at QA sign-off.
- Mirrored into `qa-signoff.md`: `## Followups` always when this file is non-empty; `## Release Blockers` iff any entry is `Critical`.
- Lives on the task branch. Delete or reset at task close alongside `resume.json`.
- Distinct from `## Gate 5 Failures` (ADR 0025 — red suite or unmapped AC, task-level) and from QA findings (human-authored during the sign-off session).
````

- [ ] **Step 3: Add the qa-signoff template sections**

In `skills/e2e-engineering/schemas/qa-signoff.md`, insert these two sections into the fenced template immediately BEFORE the `## Findings (-> triage -> new queue Tasks)` line:

```markdown
## Release Blockers (open Critical at bounce cap -> triage -> P1 repair Task)
- (written by FLIGHT only when a slice merged with an open Critical finding — ADR 0035)
  - <slice-id> <location> — <message>  [evidence: <cite>]  -> P1 repair Task at QA sign-off
- (section ABSENT when no Critical is open)

## Followups (open findings at bounce cap -> triage -> repair Tasks)
- (written by FLIGHT from followups.json when any slice exhausted its 4 bounce rounds — ADR 0035)
  - [<severity>] <slice-id> <location> — <message>  [evidence: <cite>]  -> repair Task (suggested P<1|3>)
- (empty section when every slice converged)
```

- [ ] **Step 4: Update the flight-fills bullet**

In the same file, replace this text inside the `## Sections: flight fills vs human fills` list:

```markdown
pending amendments staged from progress.txt, Gate 5 Failures if any (ADR 0025).
```

with:

```markdown
pending amendments staged from progress.txt, Gate 5 Failures if any (ADR 0025), Followups mirrored from `followups.json` and Release Blockers when a Critical is open at cap (ADR 0035).
```

- [ ] **Step 5: Update the human-fills bullet**

Replace:

```markdown
routes Gate 5 Failures through triage into repair Tasks, logs Findings, records Decision.
```

with:

```markdown
routes Gate 5 Failures and Followups/Release Blockers through triage into repair Tasks, logs Findings, records Decision.
```

- [ ] **Step 6: Add triage intake source #4**

In `skills/e2e-engineering/impl/triage.md`, append this item directly after item `3.` in the `## What feeds triage` list:

```markdown
4. **Flight followups** from `tasks/<id>/followups.json` ([schema](../schemas/followups.json.md)) — expert-review findings still open when a slice exhausted its 4 bounce rounds (ADR 0035). Each becomes a NEW [Task queue](../schemas/queue.json.md) entry (`status:needs-spec`, unselected) with `parentTask=<built task id>` and priority from `suggestedPriority` (1 when a Critical is open, else 3). Surfaced to the human via `qa-signoff.md` `## Followups` / `## Release Blockers`. Flight never creates the entry itself — ADR 0017 writer table.
```

- [ ] **Step 7: Add the triage red flag**

In the same file, append to the `## Red flags (stop)` list:

```markdown
- Closing a QA sign-off while `followups.json` still has un-routed entries (they are the only record — flight cannot queue them itself).
```

- [ ] **Step 8: Verify the assertions now pass**

```bash
grep -c "Release Blockers" skills/e2e-engineering/schemas/qa-signoff.md
grep -c "Flight followups" skills/e2e-engineering/impl/triage.md
grep -c "suggestedPriority" skills/e2e-engineering/schemas/followups.json.md
```

Expected: non-zero from all three.

- [ ] **Step 9: Build and validate**

```bash
npm run build && npm run validate
```

Expected: `validate: ok`. A `broken markdown link` error here means the relative path in the new schema (`../impl/triage.md`) or in `triage.md` (`../schemas/followups.json.md`) is wrong — fix the path, do not delete the link.

- [ ] **Step 10: Commit**

```bash
git add skills/e2e-engineering/schemas/followups.json.md skills/e2e-engineering/schemas/qa-signoff.md skills/e2e-engineering/impl/triage.md dist
git commit -m "feat: followups.json carrier + qa-signoff sections + triage lane (ADR 0035)"
```

---

### Task 4: Durable loop state — resume.json and prd.json

**Files:**
- Modify: `skills/e2e-engineering/schemas/resume.json.md`
- Modify: `skills/e2e-engineering/schemas/prd.json.md`

**Interfaces:**
- Consumes: the finding shape from Task 2 (`id`, `severity`, `location`, `state`) and the followup record from Task 3.
- Produces: `resume.json` fields `bounce: { sliceId, rounds, cap }`, `verifyWave[]` (entries `{ sliceId, findingId, verifierId }`), `suppressed[]` (string keys `"<severity>|<location>|<sha1-8 of message>"`). Tasks 6 and 7 write these write-ahead. Also produces the narrowed `prd.json` `blocked` rule that Tasks 6 and 7 enforce.

- [ ] **Step 1: Write the failing assertion**

```bash
grep -c "bounce" skills/e2e-engineering/schemas/resume.json.md
grep -c "verifyWave" skills/e2e-engineering/schemas/resume.json.md
grep -c "open-at-cap" skills/e2e-engineering/schemas/prd.json.md
```

Expected: `0` from all three.

Note: the file already contains `reviewWave` (the expert-review wave). That string does not match `verifyWave`, so the second grep is genuinely `0`. If it returns non-zero, stop — the file already changed and this task needs re-scoping.

- [ ] **Step 2: Add the loop-state fields**

In `skills/e2e-engineering/schemas/resume.json.md`, inside the fenced JSON example, insert these three fields immediately after the `"reviewWave": [ ... ],` block and before `"worktrees":`:

```json
  "bounce": {                        // review convergence loop state for the slice in flight (ADR 0035)
    "sliceId": "repair-webhook-source-ip-review-findings",
    "rounds": 2,                     // bounce rounds SPENT. Absolute per slice. NEVER reset.
    "cap": 4
  },
  "verifyWave": [                    // in-flight finding-verifiers, written BEFORE spawn
    { "sliceId": "...", "findingId": "ac-3-no-real-stack-test", "verifierId": "finding-verifier" }
  ],
  "suppressed": [                    // dropped-refuted finding keys for the slice in flight
    "Critical|src/Webhook.java:88|9f2c1a7e"
  ],
```

- [ ] **Step 3: Add the loop-state rules**

In the same file, append these bullets to the `## Rules` list:

```markdown
- **`bounce.rounds` is DURABLE and never reset** (ADR 0035). Not on resume, and not when a re-review surfaces brand-new findings — the counter is absolute per slice. Losing it restarts the count and the slice churns unbounded; same failure class as `gate5Strikes`. Write-ahead before every bounce dispatch.
- **`verifyWave[]` written BEFORE verifier dispatch.** On resume, an entry with no `verification` recorded in that slice's `review-result.json` → re-dispatch that verifier ONCE; still nothing → record `inconclusive`, which counts as `refuted`.
- **`suppressed[]` holds `dropped-refuted` finding keys** for the slice in flight, formatted `"<severity>|<location>|<first 8 hex of sha1(message)>"`. A later re-review may NOT re-raise a suppressed finding — without this the convergence loop never terminates. Cleared when the slice merges.
- `bounce`, `verifyWave[]`, and `suppressed[]` are per-slice and scoped to the slice currently in flight. Reset all three when the next slice enters its review wave.
```

- [ ] **Step 4: Narrow the prd.json blocked rule**

In `skills/e2e-engineering/schemas/prd.json.md`, replace this invariant line:

```markdown
- `status` enum: exactly three values. `blocked` only after debug escalation (3 strikes + systematic-debugging failed).
```

with:

```markdown
- `status` enum: exactly three values. `blocked` only after debug escalation (GATE 3 — 3 failed fixes + systematic-debugging failed, red tests). **Expert-review findings NEVER produce `blocked`** (ADR 0035): a slice that exhausts its 4 bounce rounds MERGES as `done`, its open findings recorded in `notes` and carried into `followups.json` ([schema](followups.json.md)).
```

- [ ] **Step 5: Document the cap-exhaustion notes form**

In the same file, inside the fenced JSON example, replace this line:

```json
      "notes": "string — free, e.g. blocked reason, gap-check escalation",
```

with:

```json
      "notes": "string — free, e.g. blocked reason, gap-check escalation. Cap-exhaustion form (ADR 0035): '<n> open findings at cap: <severities>' — e.g. '2 open findings at cap: Critical, Minor'",
```

- [ ] **Step 6: Verify the assertions now pass**

```bash
grep -c "bounce.rounds" skills/e2e-engineering/schemas/resume.json.md
grep -c "verifyWave" skills/e2e-engineering/schemas/resume.json.md
grep -c "suppressed" skills/e2e-engineering/schemas/resume.json.md
grep -c "open findings at cap" skills/e2e-engineering/schemas/prd.json.md
grep -c "NEVER produce" skills/e2e-engineering/schemas/prd.json.md
```

Expected: non-zero from all five.

- [ ] **Step 7: Build and validate**

```bash
npm run build && npm run validate
```

Expected: `validate: ok`

- [ ] **Step 8: Commit**

```bash
git add skills/e2e-engineering/schemas/resume.json.md skills/e2e-engineering/schemas/prd.json.md dist
git commit -m "feat: durable bounce/verify state; review never blocks a slice (ADR 0035)"
```

---

### Task 5: Retro counters

**Files:**
- Modify: `skills/e2e-engineering/schemas/flow-retro.md`

**Interfaces:**
- Consumes: the loop state from Task 4 (`bounce.rounds`), the verifier resolutions from Task 1, the followup priorities from Task 3.
- Produces: the exact counter lines Tasks 6 and 7 tally at Step 0 and emit at Step 6 — `bounce rounds`, `verifier spend`, `open-at-cap`, `dropped un-cited Minors`.

- [ ] **Step 1: Write the failing assertion**

```bash
grep -c "rejected un-evidenced Criticals" skills/e2e-engineering/schemas/flow-retro.md
grep -c "verifier spend" skills/e2e-engineering/schemas/flow-retro.md
```

Expected: `2` (one in the template, one in the §Sections prose), then `0`.

- [ ] **Step 2: Replace the template counter line**

In `skills/e2e-engineering/schemas/flow-retro.md`, replace this line inside the fenced template:

```markdown
- rejected un-evidenced Criticals: <n>
```

with:

```markdown
- bounce rounds: <slice-id: n/4> ... (cap exhausted: <n> slices)
- verifier spend: <n> findings (confirmed <n> / refuted <n> / inconclusive <n>)
- open-at-cap: <n> findings -> <n> followups (P1 <n>, P3 <n>)
- dropped un-cited Minors: <n>
```

- [ ] **Step 3: Replace the §Sections prose**

Replace this sentence fragment in the `## Sections` list item 1:

```markdown
fan-out wave count (impl + review), rejected un-evidenced Criticals.
```

with:

```markdown
fan-out wave count (impl + review + verify), bounce rounds per slice against the cap of 4, verifier spend split by resolution, findings left `open-at-cap` and the followups they produced, and un-cited Minors dropped without verifier spend (ADR 0035).
```

- [ ] **Step 4: Verify the assertions now pass**

```bash
grep -c "rejected un-evidenced Criticals" skills/e2e-engineering/schemas/flow-retro.md
grep -c "verifier spend" skills/e2e-engineering/schemas/flow-retro.md
grep -c "dropped un-cited Minors" skills/e2e-engineering/schemas/flow-retro.md
```

Expected: `0`, then non-zero, then non-zero.

- [ ] **Step 5: Build and validate**

```bash
npm run build && npm run validate
```

Expected: `validate: ok`

- [ ] **Step 6: Commit**

```bash
git add skills/e2e-engineering/schemas/flow-retro.md dist
git commit -m "feat: retro counters for convergence loop + verifier spend (ADR 0035)"
```

---

### Task 6: Claude runtime — `.claude/skills/e2e-flight/SKILL.md`

**Files:**
- Modify: `.claude/skills/e2e-flight/SKILL.md` (Step 0 item 5; all of Step 3 item 3; Step 6; Red flags)

**Interfaces:**
- Consumes: `.claude/agents/finding-verifier.md` (Task 1), the finding shape (Task 2), `followups.json.md` + qa-signoff sections (Task 3), `resume.json` loop fields (Task 4), retro counters (Task 5).
- Produces: the authoritative Claude-runtime procedure. Task 7 mirrors it verbatim in the `$sharedSkillsRoot` register. Task 9 summarizes it into `CONTEXT.md`.

**Register:** caveman-ultra. Markdown links resolve from `.claude/skills/e2e-flight/` — `../../agents/<role>.md` reaches `.claude/agents/`, and `../../../skills/e2e-engineering/<x>` reaches the shared tree. ADRs stay plain text.

- [ ] **Step 1: Write the failing assertion**

```bash
grep -c "Convergence loop" .claude/skills/e2e-flight/SKILL.md
grep -c "Bounce cap = 3" .claude/skills/e2e-flight/SKILL.md
grep -c "skip re-review: mechanical" .claude/skills/e2e-flight/SKILL.md
```

Expected: `0`, then `1`, then `1`.

- [ ] **Step 2: Update the Step 0 retro tally**

Replace this fragment in Step 0 item 5:

```markdown
stalls, fan-out waves (impl + review), rejected un-evidenced Criticals. Bump them as they occur in Steps 3/5; emit at Step 6.
```

with:

```markdown
stalls, fan-out waves (impl + review + verify), bounce rounds per slice vs cap 4, verifier spend (confirmed/refuted/inconclusive), findings left `open-at-cap` + followups produced (P1/P3), un-cited Minors dropped. Bump them as they occur in Steps 3/5; emit at Step 6.
```

- [ ] **Step 3: Replace the reviewer-context-injection tail**

Replace this sentence ending in Step 3 item 3:

```markdown
Reviewers must cite a specific line/test proving a coverage gap before assigning Critical — orchestrator rejects un-evidenced Criticals without bounce.
```

with:

```markdown
Reviewers must cite a specific line/test proving a coverage gap before assigning Critical. Un-cited Critical/Important are NOT binned — they go to the verify wave (ADR 0035).
```

- [ ] **Step 4: Replace the severity sentence**

Replace:

```markdown
Each returns **reviewer result**: `{ reviewerId, sliceId, findings[] }`. Findings: **Critical / Important / Minor**.
```

with:

```markdown
Each returns **reviewer result**: `{ reviewerId, sliceId, findings[] }` ([schema](../../../skills/e2e-engineering/schemas/review-result.json.md)). Severity enum is exactly **Critical / Important / Minor** — `NeedsVerification` is a pre-verify SIGNAL, not a severity; `Unsubstantiated` is retired (ADR 0035). Orchestrator assigns each finding an `id` + `state` at fan-in.
```

- [ ] **Step 5: Replace the finding evidence gate**

Replace this whole paragraph:

```markdown
   **Finding evidence gate.** Critical/Important findings MUST cite evidence: `file:line`, test name, log path, or explicit searched-absence scope. No cite → orchestrator records `Unsubstantiated`, no bounce. Coverage doubt without proof → `NeedsVerification`, not Critical.
```

with:

```markdown
   **Finding hygiene gate (pre-verify, ADR 0035).** EVERY finding, ANY severity, needs a cite (`file:line`, test name, log path, explicit searched-absence scope) AND an implied ACTION.
   - No ACTION → downgrade: Important→Minor, Minor→dropped.
   - Un-cited Critical/Important → **verify wave**, never binned.
   - Un-cited Minor → dropped, logged in `review-result.json` `notes`, NO verifier spend (a Minor worth fixing is worth citing).
   - Coverage doubt without proof → reviewer raises `NeedsVerification` instead of Critical → verify wave.

   **Verify wave (ADR 0035).** Runs after EVERY review/re-review fan-in, BEFORE bounce classification. Dispatch [finding-verifier](../../agents/finding-verifier.md) — one per unproven finding, **in parallel** — for `NeedsVerification` findings + un-cited Critical/Important. Budget ≤8 calls each. Journal `verifyWave[]` in `resume.json` write-ahead before spawn.
   - `confirmed` + cite → `state: open` at the VERIFIER's severity (it owns severity now) → eligible to bounce.
   - `refuted` → `state: dropped-refuted`, logged.
   - `inconclusive` → treated as **refuted** (adversarial default — a starved verifier must not manufacture a bounce).
   - **Verify-once + suppress.** Each finding is verified AT MOST ONCE per slice. `dropped-refuted` keys go to `resume.json` `suppressed[]` (`<severity>|<location>|<sha1-8 of message>`); a later re-review may NOT re-raise them. Without suppression the loop never converges.
   - Verify wave does NOT consume a bounce round — it is not a fix.
```

- [ ] **Step 6: Replace the three-tier bounce and cap**

Replace this whole block:

```markdown
   **Three-tier bounce.** On Critical/Important finding requiring a fix:
   - **Mechanical** (rename/reformat/comment only — zero logic lines changed, verifiable by diff) → impl worker fixes; orchestrator logs `"skip re-review: mechanical, diff confirms no logic change"`. No re-review dispatched.
   - **Limited** (non-mechanical, no logic change) → re-dispatch triggering reviewer only.
   - **Logic change** → full re-review wave.

   Reviewers never fix or merge. **Bounce cap = 3 round-trips** → still failing → mark slice `blocked`, tear down worktree, keep draining. Minor → note, don't block.
```

with:

```markdown
   **Convergence loop (ADR 0035 — replaces the bounce cap).** `open[]` = findings with `state: open`, ANY severity.
   - `open[]` empty → Step 3.4 lint+compile → merge.
   - else `bounce.rounds += 1` — **per slice, ABSOLUTE**. New findings surfaced by a re-review NEVER reset it. Durable in `resume.json` `bounce.rounds`, written write-ahead before each bounce dispatch. **Cap = 4.**
     - `bounce.rounds > 4` → cap exhausted → merge + followup (below). NEVER `blocked`.
     - else bounce → impl worker fixes **ALL** open findings in ONE pass (Minors piggyback) → re-review → loop.
   - **Tier picks re-review SCOPE, never whether** — no fix merges unread:
     - **mechanical** (rename/reformat/comment, zero logic lines, verifiable by diff) / **limited** (non-mechanical, no logic change) → re-dispatch **triggering reviewer only**.
     - **logic change** → **full re-review wave**.
   - Minor is an ordinary finding. A Minor-only round is legal and costs one round.
   - Merge gate = zero open findings at EVERY severity. Sole exception: cap exhaustion.

   **Cap exhaustion → merge + followup (ADR 0035).** On entering round 5:
   - **MERGE the slice.** Tests are green; the residue is a quality/coverage gap, not a red test.
   - `prd.json` story → `status: done`, `notes: "<n> open findings at cap: <severities>"`.
   - `review-result.json` survivors → `state: "open-at-cap"`.
   - Append each to `tasks/<id>/followups.json` ([schema](../../../skills/e2e-engineering/schemas/followups.json.md)); `suggestedPriority` = 1 if ANY open finding is Critical, else 3.
   - NEVER write `queue.json` — followups reach the queue via [triage](../../../skills/e2e-engineering/impl/triage.md) at QA sign-off (ADR 0017 writer table intact).
   - Review-driven slice `blocked` is **RETIRED**. GATE 3 (red tests, 3 failed fixes) still blocks — unchanged.

   Reviewers never fix or merge.
```

- [ ] **Step 7: Add the followups line to Step 6**

In Step 6, append this sentence to the end of the first paragraph (the one that starts `Write \`tasks/<id>/qa-signoff.md\``), immediately after `\`/e2e-engineering\` owns human review + replanning.`:

```markdown
 If any slice exhausted its bounce cap, write `## Followups` from `followups.json` ([schema](../../../skills/e2e-engineering/schemas/followups.json.md)) — plus `## Release Blockers` IFF an open finding is Critical (ADR 0035). Flight never queues them; triage does at sign-off.
```

- [ ] **Step 8: Replace the retired red flag**

Replace this red-flag line:

```markdown
- Dispatching full re-review wave for mechanical fixes (skip re-review per [[Three-tier bounce]]).
```

with these lines:

```markdown
- Merging with any finding `state: open` before the cap is exhausted (merge gate = zero open findings, Minor included — ADR 0035).
- Skipping re-review after a mechanical fix (RETIRED — tier picks scope, never whether; no fix merges unread).
- Binning an un-cited Critical/Important instead of spending a `finding-verifier` on it.
- Verifying an un-cited Minor (dropped, no verifier spend — a Minor worth fixing is worth citing).
- Re-raising a `dropped-refuted` finding in a later re-review (suppress by finding key; the loop cannot converge otherwise).
- Resetting `bounce.rounds` on resume, or because a re-review surfaced new findings (absolute per slice, cap 4).
- Marking a slice `blocked` on review findings (RETIRED — merge + followup at cap; `blocked` is GATE 3 / red tests only).
- Writing `queue.json` for a followup (flight never creates queue entries — `followups.json` → triage).
- Omitting `## Release Blockers` from `qa-signoff.md` when a Critical is open at cap.
```

- [ ] **Step 9: Verify the assertions now pass**

```bash
grep -c "Convergence loop" .claude/skills/e2e-flight/SKILL.md
grep -c "Verify wave" .claude/skills/e2e-flight/SKILL.md
grep -c "Bounce cap = 3" .claude/skills/e2e-flight/SKILL.md
grep -c "skip re-review: mechanical" .claude/skills/e2e-flight/SKILL.md
grep -c "Unsubstantiated" .claude/skills/e2e-flight/SKILL.md
grep -c "followups.json" .claude/skills/e2e-flight/SKILL.md
```

Expected: non-zero, non-zero, `0`, `0`, `1` (only the "is retired" mention), non-zero.

- [ ] **Step 10: Build and validate**

```bash
npm run build && npm run validate
```

Expected: `validate: ok`. A `broken markdown link ... finding-verifier.md` error means Task 1's wrapper generation did not run — re-run `pwsh -NoProfile -File skills/e2e-engineering/scripts/generate-agent-wrappers.ps1`.

- [ ] **Step 11: Commit**

```bash
git add .claude/skills/e2e-flight/SKILL.md dist
git commit -m "feat(claude): review convergence loop + verify wave in flight (ADR 0035)"
```

---

### Task 7: Codex runtime — `.agents/skills/e2e-flight/SKILL.md`

**Files:**
- Modify: `.agents/skills/e2e-flight/SKILL.md` (Step 0 item 6; Step 3 item 3; Step 6; Red flags if present)

**Interfaces:**
- Consumes: everything Task 6 consumes, plus Task 6's own wording as the reference.
- Produces: runtime parity. After this task the two SKILL.md files describe the same procedure.

**Register:** caveman-ultra, **backtick refs only** — `` `$sharedSkillsRoot/schemas/followups.json.md` ``, `` `$sharedSkillsRoot/agents/finding-verifier.md` ``. **No markdown links** in this tree. Reviewer roles here are PROMPT roles: spawn `agent_type: worker` and inject the canonical spec — `finding-verifier` follows the same rule.

- [ ] **Step 1: Write the failing assertion**

```bash
grep -c "Convergence loop" .agents/skills/e2e-flight/SKILL.md
grep -c "Bounce cap = 3" .agents/skills/e2e-flight/SKILL.md
grep -c "Critical / Important / Minor / NeedsVerification / Unsubstantiated" .agents/skills/e2e-flight/SKILL.md
```

Expected: `0`, `1`, `1`.

- [ ] **Step 2: Update the Step 0 retro tally**

Replace this fragment in Step 0 item 6:

```markdown
stalls, fan-out waves (impl + review), rejected un-evidenced Criticals. Bump them as they occur in Steps 3/5; emit at Step 6.
```

with:

```markdown
stalls, fan-out waves (impl + review + verify), bounce rounds per slice vs cap 4, verifier spend (confirmed/refuted/inconclusive), findings left `open-at-cap` + followups produced (P1/P3), un-cited Minors dropped. Bump them as they occur in Steps 3/5; emit at Step 6.
```

- [ ] **Step 3: Fix the severity-enum drift**

Replace this whole sentence pair (this is the drift ADR 0035 decision 7 names):

```markdown
Findings: **Critical / Important / Minor / NeedsVerification / Unsubstantiated**. `NeedsVerification` → targeted read-tool reviewer only for disputed source/test scope; cite-backed Critical/Important from that verifier may bounce.
```

with:

```markdown
Severity enum is exactly **Critical / Important / Minor** — `NeedsVerification` is a pre-verify SIGNAL, not a severity; `Unsubstantiated` is retired (ADR 0035). Orchestrator assigns each finding an `id` + `state` at fan-in.
```

- [ ] **Step 4: Replace the finding evidence gate**

Replace this whole paragraph:

```markdown
   **Finding evidence gate.** Critical/Important findings MUST cite evidence: `file:line`, test name, log path, or explicit searched-absence scope. No cite → orchestrator records `Unsubstantiated`, no bounce. Coverage doubt without proof → `NeedsVerification`, not Critical.
```

with:

```markdown
   **Finding hygiene gate (pre-verify, ADR 0035).** EVERY finding, ANY severity, needs a cite (`file:line`, test name, log path, explicit searched-absence scope) AND an implied ACTION.
   - No ACTION → downgrade: Important→Minor, Minor→dropped.
   - Un-cited Critical/Important → **verify wave**, never binned.
   - Un-cited Minor → dropped, logged in `review-result.json` `notes`, NO verifier spend (a Minor worth fixing is worth citing).
   - Coverage doubt without proof → reviewer raises `NeedsVerification` instead of Critical → verify wave.

   **Verify wave (ADR 0035).** Runs after EVERY review/re-review fan-in, BEFORE bounce classification. Spawn one verifier per unproven finding — `NeedsVerification` + un-cited Critical/Important — via `spawn_agents_on_csv` / `spawn_agent` with `agent_type: worker`, injecting the canonical spec `$sharedSkillsRoot/agents/finding-verifier.md`. `finding-verifier` is a PROMPT role, never a tool `agent_type`. Parallel preferred; bounded batches allowed when slots are constrained. Budget ≤8 calls each. Verifiers receive the finding + the review-bundle path only — never a worktree path. Journal `verifyWave[]` in `resume.json` write-ahead before spawn.
   - `confirmed` + cite → `state: open` at the VERIFIER's severity (it owns severity now) → eligible to bounce.
   - `refuted` → `state: dropped-refuted`, logged.
   - `inconclusive` → treated as **refuted** (adversarial default — a starved verifier must not manufacture a bounce).
   - **Verify-once + suppress.** Each finding is verified AT MOST ONCE per slice. `dropped-refuted` keys go to `resume.json` `suppressed[]` (`<severity>|<location>|<sha1-8 of message>`); a later re-review may NOT re-raise them. Without suppression the loop never converges.
   - Verify wave does NOT consume a bounce round — it is not a fix.
```

- [ ] **Step 5: Replace the three-tier bounce and cap**

Replace this whole block:

```markdown
   **Three-tier bounce.** On Critical/Important finding requiring a fix:
   - **Mechanical** (rename/reformat/comment only — zero logic lines changed, verifiable by diff) → impl worker fixes; orchestrator logs `"skip re-review: mechanical, diff confirms no logic change"`. No re-review dispatched.
   - **Limited** (non-mechanical, no logic change) → re-dispatch triggering reviewer only.
   - **Logic change** → full re-review wave.

   Reviewers never fix or merge. **Bounce cap = 3 round-trips** → still failing → mark slice `blocked`, keep draining. Minor → note, don't block.
```

with:

```markdown
   **Convergence loop (ADR 0035 — replaces the bounce cap).** `open[]` = findings with `state: open`, ANY severity.
   - `open[]` empty → Step 3.4 lint+compile → merge.
   - else `bounce.rounds += 1` — **per slice, ABSOLUTE**. New findings surfaced by a re-review NEVER reset it. Durable in `resume.json` `bounce.rounds`, written write-ahead before each bounce dispatch. **Cap = 4.**
     - `bounce.rounds > 4` → cap exhausted → merge + followup (below). NEVER `blocked`.
     - else bounce → impl worker fixes **ALL** open findings in ONE pass (Minors piggyback) → re-review → loop.
   - **Tier picks re-review SCOPE, never whether** — no fix merges unread:
     - **mechanical** (rename/reformat/comment, zero logic lines, verifiable by diff) / **limited** (non-mechanical, no logic change) → re-dispatch **triggering reviewer only**.
     - **logic change** → **full re-review wave**.
   - Minor is an ordinary finding. A Minor-only round is legal and costs one round.
   - Merge gate = zero open findings at EVERY severity. Sole exception: cap exhaustion.

   **Cap exhaustion → merge + followup (ADR 0035).** On entering round 5:
   - **MERGE the slice.** Tests are green; the residue is a quality/coverage gap, not a red test.
   - `prd.json` story → `status: done`, `notes: "<n> open findings at cap: <severities>"`.
   - `review-result.json` survivors → `state: "open-at-cap"`.
   - Append each to `tasks/<id>/followups.json` (`$sharedSkillsRoot/schemas/followups.json.md`); `suggestedPriority` = 1 if ANY open finding is Critical, else 3.
   - NEVER write `queue.json` — followups reach the queue via `$sharedSkillsRoot/impl/triage.md` at QA sign-off (ADR 0017 writer table intact).
   - Review-driven slice `blocked` is **RETIRED**. GATE 3 (red tests, 3 failed fixes) still blocks — unchanged.

   Reviewers never fix or merge.
```

- [ ] **Step 6: Add the followups line to Step 6**

In the Codex Step 6, append this sentence to the end of the paragraph that starts `Write \`tasks/<id>/qa-signoff.md\``, immediately after `\`/e2e-engineering\` owns human review + replanning.`:

```markdown
 If any slice exhausted its bounce cap, write `## Followups` from `followups.json` (`$sharedSkillsRoot/schemas/followups.json.md`) — plus `## Release Blockers` IFF an open finding is Critical (ADR 0035). Flight never queues them; triage does at sign-off.
```

- [ ] **Step 7: Mirror the red flags**

Locate the `## Red flags (stop)` list in `.agents/skills/e2e-flight/SKILL.md`. If a line matching `mechanical` + `re-review` exists, replace it with the block below; if no such line exists, append the block to the end of the list.

```markdown
- Merging with any finding `state: open` before the cap is exhausted (merge gate = zero open findings, Minor included — ADR 0035).
- Skipping re-review after a mechanical fix (RETIRED — tier picks scope, never whether; no fix merges unread).
- Binning an un-cited Critical/Important instead of spending a `finding-verifier` on it.
- Verifying an un-cited Minor (dropped, no verifier spend — a Minor worth fixing is worth citing).
- Re-raising a `dropped-refuted` finding in a later re-review (suppress by finding key; the loop cannot converge otherwise).
- Resetting `bounce.rounds` on resume, or because a re-review surfaced new findings (absolute per slice, cap 4).
- Marking a slice `blocked` on review findings (RETIRED — merge + followup at cap; `blocked` is GATE 3 / red tests only).
- Writing `queue.json` for a followup (flight never creates queue entries — `followups.json` → triage).
- Omitting `## Release Blockers` from `qa-signoff.md` when a Critical is open at cap.
- Spawning `finding-verifier` as a tool `agent_type` (it is a PROMPT role — use `worker` + injected canonical spec).
```

- [ ] **Step 8: Verify runtime parity**

```bash
grep -c "Convergence loop" .agents/skills/e2e-flight/SKILL.md
grep -c "Verify wave" .agents/skills/e2e-flight/SKILL.md
grep -c "Bounce cap = 3" .agents/skills/e2e-flight/SKILL.md
grep -c "NeedsVerification / Unsubstantiated" .agents/skills/e2e-flight/SKILL.md
grep -c "sharedSkillsRoot/agents/finding-verifier.md" .agents/skills/e2e-flight/SKILL.md
```

Expected: non-zero, non-zero, `0`, `0`, non-zero.

Then confirm no markdown link leaked into the Codex tree — the new text must contain none:

```bash
grep -c "](\.\./\.\./\.\./skills" .agents/skills/e2e-flight/SKILL.md
```

Expected: `0`

- [ ] **Step 9: Build and validate**

```bash
npm run build && npm run validate
```

Expected: `validate: ok`. A `Codex skills dist: stale` error means the build did not re-run; re-run `npm run build`.

- [ ] **Step 10: Commit**

```bash
git add .agents/skills/e2e-flight/SKILL.md dist
git commit -m "feat(codex): review convergence loop + verify wave; de-drift severity enum (ADR 0035)"
```

---

### Task 8: Reviewer specs — cite every severity

**Files:**
- Modify: `skills/e2e-engineering/agents/backend-architect.md`
- Modify: `skills/e2e-engineering/agents/dba.md`
- Modify: `skills/e2e-engineering/agents/frontend-reviewer.md`
- Modify: `skills/e2e-engineering/agents/test-reviewer.md`
- Regenerated: the four matching `.claude/agents/*.md`

**Interfaces:**
- Consumes: the hygiene gate from Tasks 6/7 and the finding shape from Task 2.
- Produces: reviewer output that satisfies the gate — every finding cited and actionable, `NeedsVerification` used instead of an unproven Critical.

**Do not touch** `product-designer.md` (pre-build advisory) or `architecture-scout.md` (deslop, different vocabulary).

- [ ] **Step 1: Write the failing assertion**

```bash
for f in backend-architect dba frontend-reviewer test-reviewer; do
  printf "%s " "$f"
  grep -c "ADR 0035" "skills/e2e-engineering/agents/$f.md"
done
```

Expected: `0` for all four.

- [ ] **Step 2: Append the shared finding contract to each of the four specs**

Append this identical block to the END of each of the four files (`backend-architect.md`, `dba.md`, `frontend-reviewer.md`, `test-reviewer.md`). The text is the same in all four — repeat it verbatim, do not cross-reference.

```markdown
## Finding contract (ADR 0035 — every severity, no exceptions)
Every finding you emit, at ANY severity including `Minor`, MUST carry:
- **a cite** — `file:line`, a test name, a log path, or an explicit searched-absence scope (the glob/grep you ran AND the set it covered). "I looked and didn't see it" is not a scope.
- **an ACTION** — what changes. A finding with "no change required" is not a finding.

Consequences the orchestrator applies, so emit accordingly:
- `Important` with no action → downgraded to `Minor`. `Minor` with no action → **dropped**.
- Un-cited `Critical`/`Important` → sent to a `finding-verifier`, which refutes by default. Cite it yourself or expect it killed.
- **Un-cited `Minor` → dropped outright, no verifier spend.** An uncited nit is discarded; a cited one gets fixed.
- Every surviving finding, `Minor` included, gates the merge — the slice does not merge until `open[]` is empty (cap 4 rounds, then it merges with a followup). `Minor` is no longer a free note; it costs a fix.

Cannot prove a coverage or behavior doubt inside your budget? Emit it as **`NeedsVerification`** rather than an unproven `Critical`. `NeedsVerification` is a signal, not a severity — a `finding-verifier` adjudicates it. Padding the list costs the team a real fix round; under-citing costs you the finding.
```

- [ ] **Step 3: Regenerate the Claude wrappers**

```bash
pwsh -NoProfile -File skills/e2e-engineering/scripts/generate-agent-wrappers.ps1
```

Expected: `Done. 7 role(s) processed.`

- [ ] **Step 4: Verify the assertions now pass**

```bash
for f in backend-architect dba frontend-reviewer test-reviewer; do
  printf "src %s " "$f"; grep -c "ADR 0035" "skills/e2e-engineering/agents/$f.md"
  printf "gen %s " "$f"; grep -c "ADR 0035" ".claude/agents/$f.md"
done
grep -c "ADR 0035" skills/e2e-engineering/agents/product-designer.md
grep -c "ADR 0035" skills/e2e-engineering/agents/architecture-scout.md
```

Expected: non-zero for all eight reviewer lines; `0` for `product-designer` and `architecture-scout`.

- [ ] **Step 5: Build and validate**

```bash
npm run build && npm run validate
```

Expected: `validate: ok`

- [ ] **Step 6: Commit**

```bash
git add skills/e2e-engineering/agents .claude/agents dist
git commit -m "feat: reviewers must cite every severity incl. Minor (ADR 0035)"
```

---

### Task 9: Domain language — CONTEXT.md and README.md

**Files:**
- Modify: `CONTEXT.md` (delta bullet at line ~8; `Review manifest`; `Reviewer prompt role`; `Expert-review wave`; `Mechanical fix`; `Three-tier bounce`; the refined-terms list near line ~320; four new entries)
- Modify: `README.md` (agent roster paragraph)

**Interfaces:**
- Consumes: the final wording from Tasks 6 and 7.
- Produces: nothing downstream — this is the last content task.

**Register:** `CONTEXT.md` entries follow the existing shape — `**Term**: definition` on one line, optionally followed by `_Avoid_: ...` on the next. Use `[[wiki links]]` for cross-references, as the surrounding entries do.

- [ ] **Step 1: Write the failing assertion**

```bash
grep -c "bounce cap 3" CONTEXT.md
grep -c "Review convergence loop" CONTEXT.md
grep -c "finding-verifier" CONTEXT.md
grep -c "finding-verifier" README.md
```

Expected: `1`, `0`, `0`, `0`.

- [ ] **Step 2: Update the ADR 0022 delta bullet**

In `CONTEXT.md`, replace this fragment in the `**Expert agent** (NEW)` bullet:

```markdown
A second fan-out wave reviews each green slice before merge (findings Critical/Important/Minor, bounce cap 3), and advises the PRD in pre-impl planning.
```

with:

```markdown
A second fan-out wave reviews each green slice before merge (findings Critical/Important/Minor), and advises the PRD in pre-impl planning. **ADR 0035:** a third wave (`finding-verifier`) adjudicates unproven findings, and the [[Review convergence loop]] merges only at zero open findings — cap 4 rounds, then merge + [[Followup record]]; review never blocks a slice.
```

- [ ] **Step 3: Update the `Review manifest` entry**

Replace this fragment:

```markdown
Orchestrator deduplicates across reviewers, enforces severity gates, applies bounce ceiling (3 round-trips → `blocked`), writes authoritative status to `prd.json`.
```

with:

```markdown
Orchestrator deduplicates across reviewers, enforces the hygiene gate, assigns each finding an `id` + [[Finding state]], and runs the [[Review convergence loop]] (cap 4 → merge + [[Followup record]], never `blocked`) before writing authoritative status to `prd.json`.
```

- [ ] **Step 4: Update the `Reviewer prompt role` entry**

Replace:

```markdown
**Reviewer prompt role**: Expertise label injected into an [[expert agent]] prompt, one of `backend-architect`, `dba`, `frontend-reviewer`, or `test-reviewer`.
```

with:

```markdown
**Reviewer prompt role**: Expertise label injected into an [[expert agent]] prompt — one of `backend-architect`, `dba`, `frontend-reviewer`, `test-reviewer` (the four REVIEW roles), plus `architecture-scout` (de-slop) and [[finding-verifier]] (adjudication).
```

- [ ] **Step 5: Rewrite the `Expert-review wave` entry**

Replace this fragment:

```markdown
Reviewers must cite a specific line/test proving a coverage gap before assigning Critical; un-evidenced Criticals rejected without bounce. Findings dispatched via [[Three-tier bounce]].
```

with:

```markdown
Reviewers must cite a specific line/test proving a coverage gap before assigning Critical; un-cited Critical/Important go to the [[finding-verifier]] wave, never the bin (ADR 0035). Findings drive the [[Review convergence loop]]; [[Three-tier bounce]] picks re-review scope within it.
```

Then replace its `_Avoid_` line:

```markdown
_Avoid_: inline orchestrator review as a substitute for an expert agent; skipping `test-reviewer`; dispatching full re-review wave for mechanical fixes
```

with:

```markdown
_Avoid_: inline orchestrator review as a substitute for an expert agent; skipping `test-reviewer`; merging with any finding still `open`; binning an un-cited Critical instead of verifying it
```

- [ ] **Step 6: Rewrite the `Mechanical fix` entry**

Replace both its lines:

```markdown
**Mechanical fix**: A bounce-triggered fix classified as rename, reformat, or comment-only — verifiable by diff (zero logic lines changed). Qualifies for skipped re-review under [[Three-tier bounce]]. Orchestrator must log: `"skip re-review: mechanical, diff confirms no logic change"`. Anything beyond pure rename/reformat/comment → limited or logic tier.
_Avoid_: classifying any logic change as mechanical; skipping re-review without logging
```

with:

```markdown
**Mechanical fix**: A bounce-triggered fix classified as rename, reformat, or comment-only — verifiable by diff (zero logic lines changed). Cheapest re-review SCOPE under [[Three-tier bounce]]: triggering reviewer only. **The skip-re-review exemption is RETIRED (ADR 0035)** — no fix merges unread. Anything beyond pure rename/reformat/comment → limited or logic tier.
_Avoid_: classifying any logic change as mechanical; skipping re-review entirely (retired — mechanical still gets one reviewer)
```

- [ ] **Step 7: Rewrite the `Three-tier bounce` entry**

Replace both its lines:

```markdown
**Three-tier bounce**: Bounce protocol deciding post-fix re-review scope after a Critical/Important reviewer finding: (1) **Mechanical** ([[Mechanical fix]] — rename/reformat/comment, zero logic lines) → skip re-review entirely; (2) **Limited** (non-mechanical, no logic change) → re-dispatch triggering reviewer only; (3) **Logic change** → full re-review wave. Bounce cap (3 round-trips) still applies across all tiers.
_Avoid_: always dispatching full wave (wastes reviewer tokens on mechanical renames); no-review on non-mechanical fixes
```

with:

```markdown
**Three-tier bounce**: Tier protocol deciding post-fix re-review SCOPE — never *whether* (ADR 0035). (1) **Mechanical** ([[Mechanical fix]] — rename/reformat/comment, zero logic lines) and (2) **Limited** (non-mechanical, no logic change) → re-dispatch triggering reviewer only; (3) **Logic change** → full re-review wave. Cap of 4 rounds is enforced by the [[Review convergence loop]], not by the tier.
_Avoid_: always dispatching full wave (wastes reviewer tokens on mechanical renames); skipping re-review for any tier
```

- [ ] **Step 8: Add the four new glossary entries**

Insert these immediately AFTER the rewritten `**Three-tier bounce**` entry and its `_Avoid_` line:

```markdown
**Review convergence loop**: Per-slice loop replacing the old bounce ceiling (ADR 0035). [[Expert-review wave]] → [[finding-verifier]] wave → `open[]` → merge if empty, else bounce → re-review → repeat. Merge gate is zero findings in [[Finding state]] `open` at EVERY severity, `Minor` included. `bounce.rounds` is per slice and ABSOLUTE — new findings from a re-review never reset it — and durable in `resume.json` so a mid-loop death cannot restart the count. **Cap = 4**; on entering round 5 the slice MERGES anyway and its residue becomes a [[Followup record]]. Review-driven slice `blocked` is retired; `blocked` now means GATE 3 (red tests) only.
_Avoid_: treating `Minor` as a free note (it gates the merge); resetting the round counter; marking a slice `blocked` for a quality finding; merging with an `open` finding before the cap

**finding-verifier**: [[Expert agent]] (6th [[Reviewer prompt role]]) that adjudicates ONE unproven finding — either a `NeedsVerification` doubt or an un-cited `Critical`/`Important`. Produces a hard cite or refutes the claim; `inconclusive` counts as refuted (adversarial default, so a starved verifier cannot manufacture a bounce). Read-only, ≤8 tool calls, bounded JSON return. Raises NO new findings — it adjudicates the one it was handed. A finding is verified at most ONCE per slice, and `dropped-refuted` keys are suppressed in `resume.json` so a re-review cannot re-raise them. [[Canonical expert spec]] at `skills/e2e-engineering/agents/finding-verifier.md`; Claude wrapper generated via [[agent wrapper generation]], Codex prompt-injected into a `worker`.
_Avoid_: letting it raise new findings (out of scope); confirming on plausibility instead of a cite; spending one on an un-cited `Minor` (dropped instead); treating the label as a [[Spawn agent type]]

**Finding state**: Lifecycle field on a [[review manifest]] finding, orthogonal to severity (ADR 0035). `open` (needs a fix; gates the merge) → `fixed` (a bounce round resolved it and re-review no longer raises it) · → `dropped-refuted` ([[finding-verifier]] refuted it, or returned `inconclusive`) · → `open-at-cap` (still open when round 5 was entered; carried into a [[Followup record]]). Severity stays exactly `Critical | Important | Minor`.
_Avoid_: putting `NeedsVerification` or `Unsubstantiated` in the severity enum (the first is a pre-verify signal, the second is retired); reading state as a severity

**Followup record**: `tasks/<id>/followups.json` — carry-forward for findings still `open` when a slice exhausted its 4 bounce rounds (ADR 0035). One entry per finding with its cite and a `suggestedPriority` (1 if any entry is `Critical`, else 3). Mirrored into `qa-signoff.md` as `## Followups`, plus `## Release Blockers` iff a `Critical` is open. Flight NEVER writes `queue.json` from it — [[triage]] intake source #4 creates the Task at QA sign-off, preserving ADR 0017's writer table. Distinct from `## Gate 5 Failures` (task-level, ADR 0025) and from human-authored QA findings.
_Avoid_: flight creating the queue entry itself; closing a sign-off with un-routed entries; conflating it with Gate 5 Failures
```

- [ ] **Step 9: Add the refined-term line**

Append this bullet to the refined/superseded list near the end of `CONTEXT.md` (the list containing `- "loop" — _SUPERSEDED by ADR 0022._ ...`):

```markdown
- "bounce cap 3 → `blocked`" — _SUPERSEDED by ADR 0035._ Cap is 4 and exhaustion MERGES the green slice with a [[Followup record]]. Review findings never produce `blocked`; `blocked` is GATE 3 (red tests) only. `Minor` is no longer a free note — every severity gates the merge.
```

- [ ] **Step 10: Update the README roster**

In `README.md`, replace this fragment:

```markdown
Four expert reviewer agents (`backend-architect`, `dba`, `frontend-reviewer`, `test-reviewer`) review built slices, with `backend-architect`/`dba` also advising the PRD;
```

with:

```markdown
Four expert reviewer agents (`backend-architect`, `dba`, `frontend-reviewer`, `test-reviewer`) review built slices, with `backend-architect`/`dba` also advising the PRD; a `finding-verifier` adjudicates any finding raised without a cite — proving it or killing it — so no finding is silently dropped and none merges unfixed;
```

- [ ] **Step 11: Verify the assertions now pass**

```bash
grep -c "bounce cap 3" CONTEXT.md
grep -c "Review convergence loop" CONTEXT.md
grep -c "finding-verifier" CONTEXT.md
grep -c "finding-verifier" README.md
grep -c "skip re-review entirely" CONTEXT.md
```

Expected: `0`, non-zero, non-zero, `1`, `0`.

- [ ] **Step 12: Build and validate**

```bash
npm run build && npm run validate
```

Expected: `validate: ok`

- [ ] **Step 13: Commit**

```bash
git add CONTEXT.md README.md dist
git commit -m "docs: domain language for convergence loop + finding-verifier (ADR 0035)"
```

---

### Task 10: Consistency sweep

**Files:**
- Modify: any file the sweep flags (expected: none)

**Interfaces:**
- Consumes: every prior task.
- Produces: proof that no retired term survives anywhere in the active trees.

- [ ] **Step 1: Assert every retired term is gone from the active trees**

```bash
grep -rc "Unsubstantiated" .claude/skills .agents/skills skills CONTEXT.md README.md 2>/dev/null | grep -v ":0$"
```

Expected: exactly three lines — `skills/e2e-engineering/schemas/review-result.json.md:1`, `.claude/skills/e2e-flight/SKILL.md:1`, `.agents/skills/e2e-flight/SKILL.md:1`. Each is the sentence stating the term is RETIRED. Any fourth hit is a miss — fix it.

```bash
grep -rc "bounce cap 3\|Bounce cap = 3\|3 round-trips" .claude/skills .agents/skills skills CONTEXT.md README.md 2>/dev/null | grep -v ":0$"
```

Expected: no output.

```bash
grep -rc "skip re-review" .claude/skills .agents/skills skills 2>/dev/null | grep -v ":0$"
```

Expected: no output.

- [ ] **Step 2: Assert runtime parity on the new vocabulary**

```bash
for term in "Convergence loop" "Verify wave" "open-at-cap" "bounce.rounds" "followups.json"; do
  printf "%-20s claude=" "$term"; grep -c "$term" .claude/skills/e2e-flight/SKILL.md | tr -d '\n'
  printf " codex="; grep -c "$term" .agents/skills/e2e-flight/SKILL.md
done
```

Expected: both columns non-zero for every term. A zero on one side is the exact dual-runtime drift bug this repo keeps hitting.

- [ ] **Step 3: Assert no markdown link leaked into the Codex tree**

```bash
grep -c "](\.\./" .agents/skills/e2e-flight/SKILL.md
```

Expected: `0`

- [ ] **Step 4: Final build and validate**

```bash
npm run build && npm run validate
```

Expected: `validate: ok`

- [ ] **Step 5: Confirm the working tree is clean**

```bash
git status --short
```

Expected: empty. Remember `docs/` is gitignored — if this plan file or the ADR shows as untracked, that is expected and they were force-added already.

- [ ] **Step 6: Commit any sweep fixes**

Only if Steps 1-3 flagged something:

```bash
git add -A
git commit -m "fix: consistency sweep for ADR 0035 vocabulary"
```

---

## Notes for the executor

- **The two SKILL.md files are the whole point.** Everything else is vocabulary that supports them. If you run short on time, Tasks 6 and 7 must both land or neither should — a one-runtime change is worse than no change, because the runtimes silently disagree.
- **`validate.js` link-checks `.claude/skills/**` and `.agents/skills/**` but NOT `skills/**`.** A broken relative link inside a shared schema file will pass validate. Check those by hand: `followups.json.md` links `../impl/triage.md`, and `triage.md` links `../schemas/followups.json.md` and `../schemas/queue.json.md`.
- **`grep -c "verifyWave"` on `resume.json.md` before Task 4 can be confusing** because `reviewWave` already exists and does not match. If you get a non-zero count, read the file before editing.
- **Release is out of scope.** No `package.json` version bump, no `npm publish`, no marketplace publish. `RELEASING.md` owns that and it is a separate decision.
