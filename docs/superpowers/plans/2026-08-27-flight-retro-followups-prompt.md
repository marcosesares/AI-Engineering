# Follow-up dispatch prompt — flight-retro script hardening + cost check

You are an implementation agent in C:\Views\e2e-Engineering (workdir for all commands).
The DSH flight cost-wedge reduction work is merged to main (HEAD 857408c, validate: ok).
Two follow-ups were accepted at the final whole-branch review (not blocking the merge) —
implement them now on a NEW branch off main. Do NOT work on main.

## Setup
1. git switch -c skill/followup-script-hardening-2026-08   (main must be clean first)
2. Read skills/e2e-engineering/scripts/compile-check.ps1 first — it defines Invoke-Bounded,
   the shared helper every other script calls.

## Task A — script hardening (the two real fixes)

### A1. Start-Process argument quoting (latent bug, space-bearing paths break)
Affected: skills/e2e-engineering/scripts/{compile-check,lint-check,build-package,
run-focused-tests,carrier-smoke,killswitch}.ps1 (all users of Invoke-Bounded).
Problem: Invoke-Bounded passes the argument array to Start-Process -ArgumentList,
which space-joins WITHOUT quoting — any arg containing spaces (a -HeapInit path,
a spec path, an npm test pattern) is mis-tokenized.
Fix: change Invoke-Bounded (or its callers) to build ONE pre-quoted command string
(quote args containing spaces with escaped double quotes) and pass that single
string, or invoke with & $Exe @Args while redirecting output to the log file —
the log-to-file + bounded-kill contract must be preserved exactly.
Verification: add a focused functional check — run compile-check.ps1 with a
worktree path containing spaces against a scratch repo, and lint-check.ps1 with
a changed-file path containing spaces; both must invoke the child correctly
(report the actual child command line in your report).

### A2. Port-claim atomicity (parallel slices can collide)
File: skills/e2e-engineering/scripts/run-focused-tests.ps1 (~lines 54-69).
Problem: the resume.json ports.nextFree read-modify-write is non-atomic — two
parallel slices can claim the same port; the release guard only partially heals it.
Fix: serialize the claim with an exclusive lock (e.g., open a lock file
<resume.json dir>/ports.lock with [System.IO.File]::Open(..., FileShare.None)
and a bounded retry), THEN read, increment write-ahead, write resume.json,
release the lock. Same lock on release. Keep the JSON verdict contract unchanged
(ok/counts/errors keys; exit codes as today).
Verification: run a small concurrent test — two pwsh processes claiming
simultaneously from a scratch resume.json must get DISTINCT ports; report the
observed ports.

### Optional cosmetics (fix only if trivial, do not expand scope)
- Precondition failures currently exit 1 (header norm is exit 0 + one JSON object):
  keep as-is unless the caller docs say otherwise — document your decision.
- review-fan-in.ps1: fall back to the file basename when a review JSON lacks reviewerId.
- Add trailing newlines to the 13 scripts (2 pre-existing scripts have them).

## House rules (from the merged plan — binding)
- Scripts stay BOUNDED + NON-INTERACTIVE; long producers log-to-file; verdict =
  exit 0 + ONE JSON object on stdout; NO sidecar writes beyond resume.json port
  ledger writes; prose values caveman-ultra; never hardcode client-repo specifics
  (generic defaults + env overrides only).
- npm run build (RAW, no rtk/filters) then npm run validate must exit 0 before
  committing. Commit dist/ together with the source fixes.

## Task B — one-time cost check (after the NEXT DSH flight; do NOT attempt now)
- After the next e2e-flight on DSH completes: run
  skills/e2e-engineering/scripts/session-cost.ps1 and compare against the
  2026-08 baseline (8.2M reasoning / 7.4M assistant / 8.5M tool-result).
- If the tallies look structurally wrong (field mapping vs the real DSH session
  schema), fix the script's mapping then — evidence-first, one small commit.

## Report contract
Return: status (DONE/DONE_WITH_CONCERNS/BLOCKED), commit shas, one-line summary
per fix, verification output tails (child command lines observed, distinct-ports
result, build/validate exit codes), concerns.
