# 13 — Skills + agents: work flows through gates automatically

Can start: now. THIS WEEK — the parallel-agent strategy depends on it;
every dispatched agent must inherit the rules without being told.

**Owner decision 2026-08-10, extended 2026-08-12: this tooling is
MAINTAINER-LOCAL, not committed.** `AGENTS.md`,
`.claude/skills/sirena-*`, `.claude/agents/*` and **`CLAUDE.md`** live
untracked on the maintainer's machine (built, reviewed, and live-tested
— they exist and work). Rationale: they are the maintainer's workbench,
not repo policy — other developers must not have their tooling choices
forced. Consequences: the discoverability acceptance below applies to
sessions ON THIS MACHINE; the committed repo carries the bars via this
plan (`00-overview.md`) and neutral dev tools
(`scripts/corpus_sweep.rb`) only.

`CLAUDE.md` joining the local set has a knock-on effect the plan must
respect: it is no longer a tracked surface, so items 01, 11 and 14 do
not inventory or update it. Keeping it accurate is maintainer upkeep,
not a plan deliverable.

## Do

1. `AGENTS.md` (maintainer-local, untracked, agent-neutral, first —
   per the owner decision above): the bars table, the scoreboard
   workflow, "no High/Medium reaches a PR", "doc numbers are
   generated" — and a **definition of the Pre-Push Review Chain
   itself** (the ordered gates a change passes before push), so the
   term every item uses is defined in ONE file, not in anyone's memory.
   Codex and any non-Claude session on this machine discovers the
   rules here; the committed repo carries the bars via
   `TODO.foundation/00-overview.md`.
2. `.claude/skills/sirena-gates/`: how to run every gate locally
   (corpus, coverage, conformance, lint, parity), read/update the
   scoreboard, and what a PR must show before push.
3. `.claude/skills/sirena-corpus/`: the burndown method — bucket a
   type's failures, fix largest-first, one bucket per PR, update the
   scoreboard.
4. Agent definitions for the parallel tracks (durable, in `.claude/agents/`
   or dispatched ad-hoc): corpus-triage/burndown agent (per-type),
   docs-truth agent, lint-burndown agent — each briefed with its item
   file AND the gates skill. Audited 2026-08-11: four briefs were
   missing one of those reads (`corpus-triage`, `corpus-burndown`,
   `docs-truth-auditor`, `lint-burndown`) and have been corrected. Add a
   check that re-audits this rather than trusting the audit to stay
   true — a brief is easy to edit and easy to forget.
5. `CLAUDE.md` (local): point at AGENTS.md + skills; keep only
   Claude-specifics.
6. **Worktree bootstrap — this is what makes the rest of the item
   real.** `.git/info/exclude` keeps `AGENTS.md`, `.claude/`,
   `CLAUDE.md` and `docs/plans/` untracked, and the canonical pipeline
   dispatches every
   builder into a FRESH `git worktree`. A fresh worktree checks out
   tracked files only, so a dispatched agent inherits none of this
   tooling — the exact opposite of the item's goal. Ship a bootstrap
   step (script or documented command) that copies or symlinks
   `AGENTS.md`, `.claude/` and `CLAUDE.md` into every new worktree
   before dispatch,
   and make it a required step in the dispatch flow rather than
   something to remember. (Item 11's decision manifest is NOT bootstrap
   payload — it is committed at `docs/claims-manifest.yml`, so every
   worktree already has it.)

## Done when

A fresh session (Claude or not), started **inside a newly created
pipeline worktree that has been bootstrapped**, scores 8/8 on the FIXED
question set at `.claude/skills/sirena-gates/QUIZ.md` (maintainer-local,
like the rest of the tooling) — e.g.: what are the corpus and coverage
bars? what must a PR show before push? how do you update the
scoreboard? which numbers may be hand-written in docs? — answers graded
against the AGENTS.md bars table, not vibes.

And the negative control: a SECOND, context-isolated fresh session given
the identical prompt in an **un-bootstrapped** worktree scores **≤ 3/8**.
It must be a separate session — reusing the first one proves nothing,
since it has already read `AGENTS.md`. Grade both against the same key.
If the un-bootstrapped run also passes, the bootstrap isn't load-bearing
and the quiz is measuring the model's priors, not the tooling.

Skills reviewed through the same chain as code.

[Partially met 2026-08-10: quiz scored 8/8 from AGENTS.md alone in the
MAIN checkout. That result does not transfer — it was never run from a
worktree, where the tooling is absent. Re-run after the bootstrap
lands.]

## Files

`AGENTS.md`, `CLAUDE.md`,
`.claude/skills/sirena-{gates,corpus,oracle}/SKILL.md`,
`.claude/agents/*.md` — all maintainer-local, untracked, and all listed
in `.git/info/exclude` so no `git add` can sweep them in. Nothing in
this item is committed; `TODO.foundation/00-overview.md` is what the
repo carries.
