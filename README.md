# e2e-engineering

Master engineering orchestrator — drives a Task from idea to verified code across three phases: **pre-implementation** (idea → approved PRD), **implementation** (vertical-slice TDD fan-out → unit + API green), **post-implementation** (review + human QA). A `queue.json` of Tasks, a `depends_on` slice DAG, four hard gates, and durable `.e2e-engineering/` state keep the flow honest. The essay below ("AI-Engineering") is the philosophy this skill encodes.

Built for **dual runtimes** — Claude Code and Codex/Cursor/OpenCode — from one canonical source tree.

## Install

```bash
npx e2e-engineering init                     # auto-detect the agent in this project
npx e2e-engineering init --target claude     # shared skills/ + .claude/skills/ + .claude/agents/
npx e2e-engineering init --target cursor     # shared skills/ + .agents/skills/ + AGENTS.md + .cursor/rules/
npx e2e-engineering init --target codex      # shared skills/ + .agents/skills/ + AGENTS.md
npx e2e-engineering init --target opencode   # shared skills/ + .agents/skills/ + AGENTS.md
npx e2e-engineering init --target all        # everything
```

Flags: `--dest <dir>` · `--force` · `--dry-run`. Auto-detect: `.claude/` → claude · `.cursor/` → cursor · else → codex. An existing `AGENTS.md` is never clobbered unless `--force` is used (a `AGENTS.e2e-engineering.md` sidecar is written instead); known deprecated renamed files are only deleted with `--force`.

Maintainers: run `npm run build && npm run validate` before publishing.
Publish/client install runbook: [docs/publish-and-client-install-howto.md](docs/publish-and-client-install-howto.md).

## The skills

Installing drops **four top-level skills** plus a shared sub-skill tree they sequence:

| Skill | Role |
|---|---|
| `/e2e-engineering` | Interactive front door. Human-driven pre-implementation per feature → approved PRD → queues a Task; launches `/e2e-flight`; runs the batched QA sign-off. Also `/e2e-engineering adopt` (one-time onboarding) and `/e2e-engineering qa`. |
| `/e2e-flight` | Headless implementation worker. Implements **one** Task per invocation then exits — fans each ready slice out to a sub-agent in its own worktree, runs an expert-review wave before merge, verifies, parks human-QA. Re-invoke to drain the next Task. |
| `/e2e-deslop` | Recurring, repo-wide architecture-deepening scan. Fans out an `architecture-scout` per eligible module area, surfaces refactor candidates, routes human-picked ones into the queue. Incremental via a durable scan ledger. Never auto-refactors. |
| `/grill-with-docs` | Doc-aware brainstorm that reconciles language against `CONTEXT.md` before building. Used inside pre-implementation; also invokable standalone. |

Everything else — `map-codebase`, `research`, `prototype`, `to-prd`, `to-issues`, `triage`, `tdd`, `systematic-debugging`, `e2e-loop`, `verification`, `review`, `human-qa` — is a **sub-skill** the orchestrator sequences, not a separate command.

Four expert reviewer agents (`backend-architect`, `dba`, `frontend-reviewer`, `test-reviewer`) advise the PRD and review built slices; a fifth, `architecture-scout`, powers `/e2e-deslop`.

In Claude Code, after install: restart/refresh, then type `/e2e-engineering`. Triggers also include "ship-it", "ship it", "implement feature X", "write e2e for X", "build this end to end", "run the full flow".

## How it works

**Three phases, one Task at a time.**

1. **Pre-implementation** (`/e2e-engineering`, human-driven): `[map-codebase (brownfield)] → grill-with-docs → [research?] → [prototype?] → to-prd`. Produces an approved `prd.json`. Expert agents advise the PRD so it is architecture-aware. **Gate 1** (PRD approved) is a hard human chokepoint; the Task is then appended to `queue.json`.
2. **Implementation** (`/e2e-flight`, headless): `to-issues` splits the PRD into a `depends_on` slice DAG; flight computes the ready set and **fans out** one sub-agent per slice into its own git worktree, each running `tdd` (red-green-refactor). An **expert-review wave** reviews each green slice before the orchestrator merges it. One Task per spawn, then exit — re-invoke for the next.
3. **Post-implementation**: a fresh-context `review`, then the batched **QA sign-off session** where the human walks the Manual test scripts and signs off.

**Four hard gates** (ADR 0024 retired gate 4; the label is kept, not renumbered):

| # | Gate | Where |
|---|------|-------|
| 1 | PRD approved → implementation (explicit human consent) | end of pre-impl |
| 2 | TDD red before green — failing test before production code | per slice, in `tdd` |
| 3 | Debug escalation — 3 failed fixes → `systematic-debugging` → `blocked` → stall→human | in the loop |
| ~~4~~ | ~~E2E suite green~~ — **retired** (Fork Y: UI is not automated, verified in human-QA) | — |
| 5 | Verify-before-completion — full **unit + API** suite green + AC-vs-code (no live-UI). Failures → `pending-qa`, **not** `blocked` | self-review |

Coverage / lint / style are **soft** gates — overridable with logged justification, never silently skipped.

**Fork Y (ADR 0024).** Only **unit + API/integration** are automated — unit via Vitest/Jest, every API call via Playwright `request` against the real stack. **UI is Manual**: UI test cases become the human-QA walk script. No browser/POM automation, no agent-driven live-UI checks.

**State lives under `.e2e-engineering/`.** `queue.json` (the Task backlog) at the root; each Task body under `tasks/<id>/` — `prd.json`, `progress.txt`, `codebase-map.md` (brownfield), `research.md`, `test-cases/`, `qa-signoff.md`, `flow-retro.md`, `manifests/<story-id>/` (evidence sidecars). Durable repo-root docs: `CONTEXT.md` (glossary), `ARCHITECTURE.md` (project structure, human-written), the constitution (generic standards). **No handoff docs, no context-monitoring checkpoints** — a fresh session resumes from these state files (ADR 0022).

**Incremental de-slop (ADR 0026).** `/e2e-deslop` scans module areas, skipping any that are clean/accepted and unchanged since their last scan (a durable `scan-ledger.json` keyed to a content hash). Surfaced candidates flow through `triage`; the human picks which become refactor Tasks.

**Per-flow learning report (ADR 0027).** At Step 6 flight writes `flow-retro.md` — §Local retro (process metrics) + §Skill-improvement candidates. At QA sign-off the human routes **three distinct lanes**: Pending Amendments → constitution/ARCHITECTURE.md; QA findings → triage → new client Tasks; Skill-improvement candidates → upstream to this repo.

## Fidelity

| | Claude Code | Codex | Cursor / OpenCode |
|---|---|---|---|
| Phases, 4 gates, DAG, TDD loop, state files, constitution | yes | yes | yes |
| Parallel slice execution | yes | yes if spawn + branch probes pass | serial branch mode |
| Subagent dispatch / lean orchestrator context | yes | yes if spawn probe passes | runtime-dependent |
| `/e2e-deslop` scout fan-out | yes | yes if spawn probe passes | bounded batches |

Codex targets use the `.agents/skills/` entry points routed by `AGENTS.md`; `AGENTS.md` alone is only a router.

## Claude marketplace

Plugin lives in `dist/marketplace/`. Once pushed to a GitHub repo: `/plugin marketplace add <owner>/<repo>` then `/plugin install e2e-engineering@e2e-engineering`.

MIT.

---

# AI-Engineering

## How to Build Software with AI Agents

### Core principle

**AI does not remove the need for software-engineering discipline. It makes discipline more important.**

The workflow is not "ask the AI to build everything and hope." It is:

```text
Human clarifies the idea
Human and AI align on language and architecture
AI helps produce a PRD
PRD becomes small vertical slices
Agents implement with tests
Agents and humans review
Human performs QA
Findings become new Tasks
The loop repeats
```

AI changes the tools, not the fundamentals: clear requirements, modular design, small tasks, feedback loops, testing, QA, and review still matter. This skill encodes that discipline as a runnable flow.

---

## Part 1 — AI agents are tactical, humans are strategic

Agents write code quickly, explore repositories, and review each other's work, but they carry no long-term memory across sessions. So you give them **process, structure, documentation, and feedback loops**.

```text
Human = strategic programmer   (decides what matters, trade-offs, quality boundaries)
AI agent = tactical programmer (executes inside that structure)
```

Architecture improvement is not something you run AFK — it requires judgment from the programmer above the agent. That is why `/e2e-deslop` only *surfaces* refactor candidates; the human chooses which matter.

---

## Part 2 — Make the codebase ready for AI

A messy codebase makes AI worse. With no prior memory, the agent sees only scattered files. So aim for a codebase that is easy to navigate, easy to test, organized around meaningful modules, built around clear interfaces, and protected by feedback loops.

**Deep modules.** A deep module hides a lot of implementation behind a simple interface; a shallow one exposes a wide interface for little gain. Deep modules give **locality** (related change concentrates in one place) and **leverage** (more behavior per unit of interface learned).

**Seams and adapters.** A seam is the boundary where one module talks to another — the best place to test. If a service depends on time, define a clock interface and inject a fake clock in tests. Agents need reliable seams to attach tests to.

**Run architecture improvement regularly.** This is what `/e2e-deslop` is for: a recurring, repo-wide scan that surfaces shallow modules, duplicated rules, missing seams, poor locality, and untestable spots as *candidates with trade-offs*. It is incremental — areas clean and unchanged since their last scan are skipped via the scan ledger — and it never refactors on its own. You pick a candidate; it becomes a refactor Task that runs the full gated flow.

---

## Part 3 — Establish shared language before building

`grill-with-docs` interviews you relentlessly until both sides share an understanding, walking the design tree and resolving dependencies one by one — but it also **writes the language down**. It reads `CONTEXT.md` (the glossary), challenges fuzzy terms, cross-references the code, and updates the glossary inline as terms resolve, so you don't re-explain the domain next session. The four languages it aligns:

```text
Human language · Code language · Agent language · User-facing language
```

**ADRs for hard decisions.** When a choice is hard to reverse, surprising without context, and the result of a real trade-off, record it (`docs/adr/`). This prevents future agents from undoing decisions they don't understand — this repo's own `docs/adr/` is the worked example.

---

## Part 4 — Three phases, not a guess

This skill runs **three phases** — pre-implementation, implementation, post-implementation — for any Task type (greenfield, feature, bugfix, refactor) on new or existing code.

**Pre-implementation** turns an idea into an approved PRD: optionally map the codebase (brownfield), grill for shared language, optionally research external APIs (`research.md`, sprint-lifetime, may rot) or prototype when taste/UX uncertainty needs concrete feedback. The PRD is the **destination document** — problem, goal, non-goals, user stories, implementation decisions, **testing decisions**, risks, acceptance criteria. Gate 1 requires explicit human approval.

**Implementation** turns the PRD into **vertical slices**, never horizontal layers (db → backend → frontend → tests delays all feedback). Each slice cuts through the layers it needs and is independently testable. Slices are ordered as a `depends_on` DAG (`tracer → schema → logic → api → ui`); independent branches run in parallel. Pick risky integrations as early "tracer bullet" slices.

**Post-implementation** reviews and signs off.

---

## Part 5 — Triage before agents touch work

`triage` is the intake state machine (`needs-triage → needs-info → ready-for-agent / ready-for-human / won't-fix`). Forward-flow slices from `to-issues` are born `ready-for-agent` and skip it; triage gates **externally-sourced** work (bug reports, feature ideas, QA findings) and walled refactor candidates. The rule: **never let an AFK agent pick up an un-triaged, under-specified Task.**

---

## Part 6 — Execute with TDD: red, green, refactor

Each slice sub-agent writes **one failing test first**, implements the minimum to pass, then refactors — one behavior at a time. LLMs tend to write many tests then a giant implementation; the per-slice discipline (Gate 2: red before green) prevents that. Under Fork Y the executable layers are **unit + API/integration**; UI behavior is proven by the human walk, not automated locators.

---

## Part 7 — Feedback loops everywhere

Without feedback loops, AI codes blind. Backend feedback is textual and cheap for agents to read: unit tests, API/integration tests, type checks, lint, build, the full-suite run at Gate 5. UI feedback is visual and brittle to automate — so this skill deliberately keeps UI verification **manual** (Fork Y) rather than maintaining AFK browser locators, and captures it as the human-QA walk script. Prototyping still uses browser screenshots when taste matters; that is a throwaway learning tool, not a test suite.

---

## Part 8 — Parallelism with worktrees and sub-agents

Parallel slices run in **git worktrees** — each ready slice gets its own branch, its own sub-agent, its own isolated checkout — so agents never trip over each other. The orchestrator (flight) is the **sole writer** of shared state (`prd.json`, `progress.txt`); sub-agents return compact result manifests and never touch shared state. Fan-out is *forced* at bootstrap: if the dispatch tools won't load, flight stalls rather than silently doing slice work inline (the failure mode that once caused a token blowup).

Protect the main branch: flight works on a `task/<id>` branch, touches master only for two targeted `queue.json` commits, and merges slice branches in itself — never letting a worker push to master.

---

## Part 9 — Review in a fresh context

Review happens at three altitudes, each in a context the implementer doesn't taint:

```text
Per-slice review   (at fan-in)  — spec-compliance then quality, before merge
Expert-review wave (before merge) — independent role agents by slice type
Post-impl review   (fresh)      — full-diff, cross-slice audit
```

Two questions stay separate throughout: **spec compliance** (does it satisfy the issue / acceptance criteria?) and **standards** (does it match conventions and module boundaries?). Code can be well-written but solve the wrong problem, or solve the right problem while violating standards.

---

## Part 10 — Resume from state, not a handoff

Long sessions end; new ones begin. There is **no handoff document and no context-monitoring checkpoint** (ADR 0022). A fresh session resumes deterministically from state files: `queue.json` (which Task) → `tasks/<id>/prd.json` (which slices are done/todo/blocked) → `progress.txt` (tail for current state). The structural token fix is forced fan-out — sub-agents hold the heavy work — not periodic checkpointing.

---

## Part 11 — Human QA closes the loop

Even after headless implementation, tests, and review, the human performs QA. Because flight runs one Task per spawn and defers human-QA, sign-off is **batched**: every `pending-qa` Task is walked in one session. The human walks the Manual test scripts, then routes three distinct lanes:

```text
Pending Amendments       → constitution / ARCHITECTURE.md   (project standards)
QA findings              → triage → new client Tasks         (project work)
Skill-improvement (retro)→ upstream to the e2e-engineering repo (tool feedback)
```

That third lane is the **learning report** (`flow-retro.md`, ADR 0027): process friction the running team sees locally, plus tool-defect signal forwarded to improve the skill itself. QA findings re-enter the queue as new Tasks — the loop is iterative, not one-shot.

---

## The complete workflow

```text
1. Ready the codebase     — deep modules, seams, tests at boundaries; /e2e-deslop surfaces candidates
2. Shared language        — CONTEXT.md + grill-with-docs; ADRs for hard-to-reverse decisions
3. Idea → PRD             — map (brownfield) → grill → research?/prototype? → to-prd → GATE 1
4. PRD → vertical slices  — to-issues emits the depends_on DAG; tracer-bullet the risky parts
5. Implement (flight)     — fan-out to worktree sub-agents; TDD red→green→refactor (GATE 2/3)
6. Review                 — per-slice spec+quality, expert-review wave, fresh post-impl review
7. Verify (GATE 5)        — full unit+API suite green + AC-vs-code; failures ride to pending-qa
8. Human QA               — batched sign-off; route the three lanes; findings become new Tasks
9. Repeat                 — the queue drains one Task per flight; /e2e-deslop feeds it over time
```

## Final takeaway

```text
Do not use AI to avoid engineering.
Use engineering to make AI useful.
```

Good AI-driven development is not the perfect prompt. It is a system where agents can succeed: clear language, clear architecture, clear tasks, clear tests, clear feedback, clear review, clear human ownership. When those are in place, agents are powerful collaborators. When they are missing, AI just accelerates entropy.
