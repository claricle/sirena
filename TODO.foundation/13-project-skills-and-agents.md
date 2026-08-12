# 13 — Skills + agents: work flows through gates automatically

Can start: now. THIS WEEK — the parallel-agent strategy depends on it;
every dispatched agent must inherit the rules without being told.

**Gates dispatch plan-wide, not just item 06.** No track dispatches a
builder agent until this item's bootstrap and start guard have landed.
The topology draws the edge to item 06 because that is the first track
to need it, but the rule is global: an unguarded worktree produces an
agent that has read none of the bars. Hand-written work and
investigation are unaffected.

**Owner decision 2026-08-10, extended 2026-08-12: this tooling is
MAINTAINER-LOCAL, not committed.** `AGENTS.md`,
`.claude/skills/sirena-*`, `.claude/agents/*` and **`CLAUDE.md`** live
untracked on the maintainer's machine (built, reviewed, and live-tested
— they exist and work). Rationale: they are the maintainer's workbench,
not repo policy — other developers must not have their tooling choices
forced. Consequences: the discoverability acceptance below applies to
sessions ON THIS MACHINE; the committed repo carries the bars via this
plan (`00-overview.md`) and neutral dev tools only.

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

   Two pieces, because "a script or a documented command" cannot make a
   bypass fail:
   - an **executable** bootstrap the dispatch frontends call, and
   - a **guard** that runs at agent start, checks the tooling is
     present, and aborts if it is not.

   The canonical pipeline goes straight from `git worktree add` to
   building, and item 13 does not own that file — so this item's Files
   list must name both dispatch frontends it has to change, and getting
   that change accepted is part of the work, not an assumption.

## Done when

**The bootstrap is automatic, proven by dispatch and not by hand.**
Run the canonical dispatch flow with NO manual pre-step and confirm
`AGENTS.md`, `.claude/` and `CLAUDE.md` are present in the new worktree
before the agent starts. Then bypass the hook deliberately and confirm
dispatch FAILS rather than quietly running an unequipped agent. A Done
criterion that begins "in a worktree that has been bootstrapped" tests
nothing — copying files by hand passes it while the pipeline still does
only `git worktree add`.

**The quiz measures the tooling, not the repo.** The old question set
asked what the bars are — and `00-overview.md` is tracked, so it answers
most of them; an un-bootstrapped session scores well without any
tooling, which makes the negative control unsatisfiable. Replace those
questions with facts that exist ONLY in the local tooling:

- the exact ordered gates of the Pre-Push Review Chain;
- the command each gate runs, and the lutaml-model pin workaround;
- how to update the scoreboard, by command;
- which agent brief owns a given track, and what it must read first.

Bootstrapped session scores 8/8. A SECOND session scores **≤ 3/8** on
that same set — and it must be **filesystem-isolated, not just
context-isolated**. A linked worktree can find the main checkout through
`git worktree list` and read the tooling from there, and `~/.claude`
global files are visible from anywhere. So run the negative control in a
disposable clone or container where neither source exists. A separate
session in a linked worktree proves nothing.

**The skills are checked structurally too:** every command named in a
skill runs, and every agent brief reads its owning item file and the
gates skill. Audits go stale — this is a check, not a one-time sweep.

Skills reviewed through the same chain as code.

[The 2026-08-10 "8/8 from AGENTS.md alone in the main checkout" result
does NOT carry over. It used the old content quiz, which the tracked
overview largely answers, and it never ran from a worktree. Re-run both
halves after the bootstrap and the new question set land.]

## Files

`AGENTS.md`, `CLAUDE.md`,
`.claude/skills/sirena-{gates,corpus,oracle}/SKILL.md`,
`.claude/agents/*.md` — all maintainer-local, untracked, and all listed
in `.git/info/exclude` so no `git add` can sweep them in.

Plus the two dispatch frontends the bootstrap hook has to change:
`~/.claude/pipeline/PIPELINE.md` and the `dispatch` skill. This item
does not own either, so landing that change is part of the work.

Nothing here is committed to the repo; `TODO.foundation/00-overview.md`
is what it carries.
