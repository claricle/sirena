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
    -> rake corpus && commit corpus.json with the fix
```

The `corpus.json` update is part of the fix, not a follow-up.
`corpus:check` fails on unrecorded improvements precisely so this cannot
be forgotten.

## Order

1. **Type detection first** — `TODO.foundation/05`.
   104 corpus failures never reach a parser: 71 of the 85 cases in
   `unknown/`, plus 33 scattered across typed directories. Causes are
   YAML frontmatter before the keyword, `%%` comments, `%%{init}%%`
   directives, and keyword variants. These are the cheapest cases per
   hour in the whole corpus, and item 01's `stage` field hands you the
   list directly: every row with `stage: detect`.
   After item 06 these are edits to one table plus a preprocessing step.

2. **Then the big types** — `TODO.foundation/06` and `07`, worst first:
   flowchart (331 cases, ~6%), class (465, ~27%), git (168, 66%),
   sequence (126, 48%).

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
   d. **Then integrate elkrb**, replacing `Layout::Grid`. After item 03
      that is one file with one caller; after item 04 the graph Scenes
      are already ELK-shaped, so this is a swap rather than a redesign.

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
  as much, and there are over a thousand of them.
- Do not fix a case by special-casing it in a renderer. If a fix does
  not generalise to the other cases in its group, it is probably in the
  wrong layer.
