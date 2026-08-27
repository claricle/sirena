# 07 — Adding or changing a type in an hour

**Goal:** the thing this whole plan is for. Every future Mermaid change
lands fast, including the 458 evidence-valid corpus cases still failing.
**Size:** 2 PRs — tooling, then documentation.
**Prerequisite:** item 06.

## The measure

One number asserted by a spec, and one measurement that refuses to be a
number:

- **Adding a new diagram type touches exactly 8 files that define the
  type** — 6 new under `lib/`, one new fixture, and one edited row in
  `TYPES`. Counted from the list below, not estimated. Two earlier
  drafts said 5 and then 6; both forgot files that the list itself
  names.

  Specs are on top of that and the generator writes them too. The 8 is
  the contract surface — what someone has to understand — not the
  number of files the generator creates.

  **This is the count before `TODO.foundation/18`.** That item's typed
  IR adds more than a row: it requires a notation-to-IR mapping per
  type (`18-typed-ir-boundary.md:103-115,142-144`, `TODO.foundation/12:106-109`)
  as well as an entry in `docs/ir-type-map.md`. Item 03 turned the
  existing transforms into layouts, so that mapping is a new
  **responsibility** whose home item 18 has not settled.

  The post-18 count is **9 or 10, and item 18 settles which**: a
  separate mapper file makes 10; folding the mapping into one of the
  eight above keeps it at 9. Any other existing file still makes it 10,
  because it is a file this list does not already count.

  **Item 18 owns that handoff, and it is gated.** Saying so was not
  enough — `TODO.foundation/18` had no Do, Done or Files entry covering
  the generator or the counts, so it could have closed with the pre-IR
  generator intact. That criterion is now in item 18's `Done when`
  (`18-typed-ir-boundary.md:125`), written in the same plain list style
  as the criteria around it. One line, and item 18 cannot close without
  it.
- **Extending the syntax of an existing type has no fixed cost, and
  this page has stopped guessing at one.** Measured on `origin/main`:

  | commit | what it added | production files |
  |---|---|---|
  | `22996b9` | semicolon statement separators | 1 — the grammar |
  | `c09c975` | strip comments before metadata | 2 — grammar, flowchart transform |
  | node-metadata series | `@{ shape: ... }` syntax | 4 — plus a YAML composer and a shape table |
  | `4f77b61` | the full sequence arrow set | 5, across four layers |

  Three drafts of this page promised a bound and three were wrong: two
  files, then two-with-conditions, then one-to-four-in-one-or-two-layers.
  `22996b9` needs one; `4f77b61` needs five across four layers.

  **What holds is the direction, not a number.** Extending a type is
  bounded by the change itself. Adding one is a fixed eight files across
  every layer, every time. The structural work is what makes the first
  cheap; it cannot make it constant.

## The eight files

```
  lib/sirena/parser/<type>.rb             the parser itself
  lib/sirena/parser/grammars/<type>.rb    what the text LOOKS LIKE
  lib/sirena/parser/builders/<type>.rb    parse tree -> model
  lib/sirena/diagram/<type>.rb            what the diagram MEANS
  lib/sirena/layout/<type>.rb             geometry, AND its Scene class
  lib/sirena/renderer/<type>.rb           scene -> SVG
  spec/fixtures/contract/<type>.mmd       the contract fixture
  lib/sirena/notation/mermaid.rb          one row in TYPES
```

**The layout is mandatory** — item 04 gives every type one, so there is
no "only if it has geometry" case. **The Scene lives inside the layout
file**, not beside it; that is item 04's rule, and it is why this list
has no separate scene file.

Six new files, one new fixture, one edited row. Specs are on top of
that.

## Steps — PR 1, tooling

1. **Generator.** `rake type:new[kanban]` scaffolds the seven files the
   list above names — parser, grammar, builder, diagram, layout (with
   its Scene inside), renderer, contract fixture — plus their specs,
   from templates. The templates encode the conventions, so they cannot
   be got wrong.

   **It edits `TYPES` itself; it does not print a row to paste.** Item
   06 asserts `TYPES` and the contract fixtures match exactly, so a
   generator that writes the fixture and leaves the row to a human
   leaves the suite red — and that contradicts this item's own "no
   hand-editing" criterion.
2. **Shared examples.** Package item 01's contract spec as
   `it_behaves_like 'a diagram type'`, so a new type inherits for free:
   parses, produces a valid model, renders parseable escaped XML,
   respects themes, handles empty input without raising.
3. **Per-type corpus output.** `rake corpus[kanban] --failing` prints,
   for each failing case: the path, the stage, and the first line of the
   error. This is the command someone lives in for a whole day of item
   08, so spend the time to make its output good.

## Steps — PR 2, documentation

4. Write `docs/adding-a-diagram-type.md`:
   - the pipeline diagram from `00-overview.md`
   - the eight files and what each owns, in one sentence each
   - the generator command
   - a worked example adding a trivial type end to end
5. In the same page, **"how do I fix a failing case"** — the single most
   useful thing to write down for whoever comes next:

```
  stage        what it means                     file to open
  ---------------------------------------------------------------------
  detect       no type matched the source        notation/mermaid.rb TYPES row
  parse        the grammar rejected the text     parser/grammars/<type>.rb
  parse        grammar OK, model build failed    parser/builders/<type>.rb
  layout       geometry raised                   layout/<type>.rb
  render       SVG generation raised             renderer/<type>.rb
```

## Done when

- [ ] `rake type:new[demo]` produces a type that passes the shared
      examples with no hand-editing
- [ ] a spec asserts the file count: adding `demo` touched 8 defining
      files, ignoring specs
- [ ] `rake type:new[demo]` leaves the suite **green**, including item
      06's `TYPES`-to-fixture parity — no hand-edited row
- [ ] `docs/adding-a-diagram-type.md` exists, and someone who has not
      read this plan can follow it end to end
- [ ] `rake corpus[<type>] --failing` output is good enough to work from

## Do not

- Do not make the generator configurable. One template set, no options.
- Always generate the layout. There is no `--layout` flag, because
  there is no type without a layout (item 04). A generated type that
  skips it cannot pass `contract_spec.rb`.

## Files

`lib/tasks/type.rake` (new), `spec/support/shared_examples.rb` (new),
`lib/tasks/corpus.rake`, `docs/adding-a-diagram-type.md` (new),
`lib/generators/templates/` (new).
