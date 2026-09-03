# Prompt: Audit & Fix Standards Alignment Between Implementation and Reviewer Agents

Use this prompt with a coding agent (e.g. inside Fork Y itself) that has access to the full agent/skill definitions.

---

## Prompt

You are auditing the Fork Y agent system for a specific failure mode: **implementation agents and reviewer agents are enforcing different standards for the same domain**, causing review-phase rejections and rework that could have been caught during implementation.

Audit these reviewer agents: `test-reviewer`, `frontend-reviewer`, `dba`, `backend-architect` (review phase), and their corresponding implementation-phase agents/prompts.

### Step 1 — Extract the rule sets

For each domain (test, frontend, db, backend):
- List every concrete rule, checklist item, or standard the **reviewer** agent checks for. Cite the exact file/section it comes from.
- List every rule, convention, or standard given to the **implementation** agent for that same domain. Cite the exact file/section.

### Step 2 — Diff them

For each domain, classify every reviewer-side rule into one of three buckets:
1. **Present in both** — rule text matches or is clearly equivalent in the implementer's instructions.
2. **Missing from implementer** — reviewer checks it, but the implementer was never told. (This is the bug causing rework.)
3. **Legitimately reviewer-only** — requires whole-codebase/cross-file context an implementer working a single slice wouldn't have (e.g. consistency across modules, architectural fit). Flag these explicitly as intentional, not drift.

Do the reverse check too: any implementer-side constraints the reviewer doesn't actually verify (dead weight, or a gap in review coverage).

### Step 3 — Propose the fix

For every "missing from implementer" item, propose one of:
- Move the rule into a **single canonical `standards/<domain>.md`** file that both the implementer's pre-flight/self-check step and the reviewer's checklist load by reference (not by restating). Prefer this by default.
- If the rule genuinely only applies at review time (bucket 3), leave it reviewer-only but document *why* in that standards file, so future edits don't "fix" it into the implementer prompt by mistake.

Do not paraphrase reviewer rules into implementer prompts — reference the same source file/section so they can't drift again.

### Step 4 — Output

Produce:
1. A table per domain: rule | in reviewer | in implementer | classification | proposed fix.
2. A concrete diff/patch proposal for each `standards/<domain>.md` (create if it doesn't exist) and the corresponding edits to both the implementer and reviewer agent prompts to reference it.
3. A short list of any rules you could not classify confidently, with the specific question needed to resolve each.

Do not implement the changes yet — output the audit and proposed diffs first so I can review before anything is applied.
