# 08 — Then the corpus burndown

**Goal:** move the pass rate. This is the only number a user of the gem
can feel.
**Size:** the largest block of work in the project by an order of
magnitude. Ongoing.
**Prerequisite:** item 07.

This item does not restate the burndown work — `TODO.foundation/05`,
`06`, `07` and `14` describe it well and their per-type case counts and
bars still stand. This item says what order to do it in and what the
tooling from items 01-07 gives you.

## Your loop

```
  rake corpus[flowchart] --failing
    -> pick a case, read its stage
    -> stage tells you which file to open (docs/adding-a-diagram-type.md)
    -> fix
    -> rake corpus[flowchart]
    -> rake corpus && commit scoreboard/corpus.json with the fix
```

The `scoreboard/corpus.json` update is part of the fix, not a follow-up.
`corpus:check` fails on unrecorded improvements precisely so this cannot
be forgotten.

## What is actually left

Measured 2026-08-25, over the 1,032 oracle-valid cases only
(`scripts/corpus_sweep.rb` joined to `spec/mermaid/corpus-verdicts.yml`).
**508 pass, 524 fail.** Two types hold 337 of those 524 — nearly two
thirds of everything left:

| Type | Pass / valid | Rate | Remaining |
|---|---|---|---|
| `flowchart` | 24/218 | 11.0% | **194** |
| `class_diagram` + `class` | 161/304 | 53.0% | **143** |
| `state_diagram` + `state` | 8/52 | 15.4% | 44 |
| `sequence` | 66/107 | 61.7% | 41 |
| `kanban` | 10/39 | 25.6% | 29 |
| `unknown` | 4/32 | 12.5% | 28 |
| `user_journey` | 11/27 | 40.7% | 16 |
| `gantt` | 9/21 | 42.9% | 12 |
| everything else | — | — | 17 |

Ten types are already at 100% of their valid cases: `c4`, `git`,
`gitgraph`, `info`, `packet`, `quadrant`, `radar`, `timeline`,
`treemap` and `xychart`. Three more are within two cases of it: `pie`
39/40, `requirement` 23/24, `mindmap` 43/45.

Re-measure before you plan a week's work. Never copy a number out of
this file: `AGENTS.md` bans hand-written figures, and this one is a
snapshot.

## Order

1. **Type detection first** — `TODO.foundation/05`.
   104 corpus failures never reach a parser: 71 of the 85 cases in
   `unknown/`, plus 33 scattered across typed directories. Causes are
   YAML frontmatter before the keyword, `%%` comments, `%%{init}%%`
   directives, and keyword variants. These are the cheapest cases per
   hour in the whole corpus, and item 01's `stage` field hands you the
   list directly: every row with `stage: detect`.
   After item 06 these are edits to one table plus a preprocessing step.

2. **Then the big types** — `TODO.foundation/06` and `07`, worst first,
   by remaining valid cases: flowchart (194 left, at 11%), class and
   class_diagram together (143 left, at 53%), state and state_diagram
   (44 left, at 15%), sequence (41 left, at 62%).

   **`git` is not on this list any more.** Its per-type figures in
   `TODO.foundation/06` and `07` are raw counts over every file in
   `spec/mermaid/git*/`, and 27 of those are extraction artifacts while
   127 more carry no oracle evidence either way. Over the 12 cases
   mermaid actually accepts,
   `git` and `gitgraph` are both at 100%. Read those items for their
   method, not their denominators.

   **One rule from those items still matters and is easy to trip over:**
   `Flowchart`, `StateDiagram` and `ErDiagram` all subclass
   `Grammars::Common`. A change to a shared rule there changes three
   types at once. Type-local edits are safe to do in any order; any edit
   to `grammars/common.rb` needs a **full** `rake corpus:check`, not
   just the type you are working on.

3. **Then layout parity** — `TODO.foundation/14`, elkrb. **This is the
   agreed bar (8% node-centre, 15% dimension-aspect), not an optional
   extra**, so budget for it as the largest single track after the
   corpus itself.

   Do it in this order, and not in any other — each step is useless
   without the one before it:

   a. **Pin the mermaid toolchain** — `TODO.foundation/02a`. Node,
      mermaid-cli, mermaid, Puppeteer, Chromium and fonts, as a lockfile
      or a container digest. Deferred until now on purpose; it becomes
      necessary here because a geometry comparator built on
      irreproducible references measures noise.
   b. **Regenerate reference SVGs** under that pin —
      `TODO.foundation/02b` step 7 — with provenance per reference.
   c. **Write the comparator** to `TODO.foundation/14`'s metric
      contract, in full: node identity, normalisation, the equations,
      overlap semantics (ancestor containment is legitimate, peer
      collision is not), and a metric for every non-box type.
   d. **Then integrate elkrb.** It does not replace `Layout::Grid` —
      item 06 deletes that class once no legacy layout is left to call
      it. What elkrb replaces is the positioning each graph-type layout
      does for itself after item 04. Their Scenes are already
      ELK-shaped, so this is a swap per layout rather than a redesign.

      **Not every type.** `block` is pre-positioned by author-specified
      columns (`TODO.foundation/18:47-51`) and `TODO.foundation/14:115`
      names it an explicit elkrb exception. Take the classification
      from item 18's survey, not from a roster written here.

   Keep that metric contract as written. Geometry comparison genuinely
   is subtle, and it is the one place in the original plan where the
   rigour is proportionate to the problem.

4. **Then lint** — `TODO.foundation/08` and `09`.
   Item 08 (109 live offences, 104 autocorrectable) is small and can run
   any time. The 7,614-entry `.rubocop_todo.yml` burndown belongs
   **here**, after the structural work — items 04-06 delete a large
   fraction of the files that debt is parked in, and styling code you
   are about to delete costs twice.

## Do not

- Do not start the burndown before item 07. The tooling from 01-07 is
  what makes this affordable; without it every case costs roughly twice
  as much, and there are 524 of them.
- Do not fix a case by special-casing it in a renderer. If a fix does
  not generalise to the other cases in its group, it is probably in the
  wrong layer.

This item owns the **order and the handoff**, not the pass rate itself.
The pass-rate criteria live in `TODO.foundation/05`, `06`, `07` and
`14`, and they are deliberately not repeated below — repeating them
would count the same burndown twice in any plan total.

## Done when

- [ ] `TODO.foundation/05`'s detect-stage list is worked from `scoreboard/corpus.json`'s `stage: detect` rows, and the type table is the only file edited for it
- [ ] the burndown ran in remaining-valid order — flowchart, then class, then state, then sequence — and each type's remaining count was re-measured before it started, never copied from this file
- [ ] every edit to `grammars/common.rb` was followed by a full `rake corpus:check`, not a single-type run
- [ ] `TODO.foundation/02a`'s toolchain pin landed before the comparator, and `02b`'s reference regeneration before elkrb replaced `Layout::Grid`
- [ ] `TODO.foundation/14`'s metric contract is implemented as written, including a metric for every non-box type
- [ ] `bundle exec rubocop` exits 0 and `.rubocop_todo.yml` is gone
