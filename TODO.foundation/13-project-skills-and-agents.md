# 13 — Skills + agents: work flows through gates automatically

Can start: now. THIS WEEK — the parallel-agent strategy depends on it;
every dispatched agent must inherit the rules without being told.

**Owner decision 2026-08-10: this tooling is MAINTAINER-LOCAL, not
committed.** `AGENTS.md`, `.claude/skills/sirena-*`, and
`.claude/agents/*` live untracked on the maintainer's machine (built,
reviewed, and live-tested — they exist and work). Rationale: they are
the maintainer's workbench, not repo policy — other developers must
not have their tooling choices forced. Consequences: the
discoverability acceptance below applies to sessions ON THIS MACHINE;
the committed repo carries the bars via this plan
(`00-overview.md`) and neutral dev tools (`scripts/corpus_sweep.rb`)
only.

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
   file + the gates skill.
5. CLAUDE.md: point at AGENTS.md + skills; keep only Claude-specifics.

## Done when

A fresh session (Claude or not) ON THIS MACHINE, given only this
machine's checkout (tracked files + the untracked tooling that lives
here), scores 8/8 on the FIXED
question set at `.claude/skills/sirena-gates/QUIZ.md` (maintainer-local,
like the rest of the tooling) — e.g.: what are the corpus and coverage
bars? what must a PR show before push? how do you update the
scoreboard? which numbers may be hand-written in docs? — answers graded
against the AGENTS.md bars table, not vibes. Skills reviewed through
the same chain as code. [Met 2026-08-10: quiz scored 8/8 from
AGENTS.md alone; machinery FINALIZED after live rehearsal.]

## Files

`AGENTS.md`, `.claude/skills/sirena-{gates,corpus,oracle}/SKILL.md`,
`.claude/agents/*.md` (all maintainer-local, untracked); `CLAUDE.md`
(committed) points at them as optional maintainer tooling.
