# 07 — Adding or changing a type in an hour

**Goal:** the thing this whole plan is for. Every future Mermaid change
lands fast, including the 524 oracle-valid corpus cases still failing.
**Size:** 2 PRs — tooling, then documentation.
**Prerequisite:** item 06.

## The measure

Two numbers, asserted by a spec rather than claimed:

- **Adding a new diagram type touches exactly 5 files** — 4 new, plus
  one row in `TYPES`.
- **Extending the syntax of an existing type touches 2 files** — grammar
  and builder — when the diagram model already covers the concept.

## The five files

```
  lib/sirena/parser/grammars/<type>.rb    what the text LOOKS LIKE
  lib/sirena/parser/builders/<type>.rb    parse tree -> model
  lib/sirena/diagram/<type>.rb            what the diagram MEANS
  lib/sirena/renderer/<type>.rb           scene -> SVG
  lib/sirena/notation/mermaid.rb          one row in TYPES
```

Plus `lib/sirena/layout/<type>.rb` only if the type has geometry.

## Steps — PR 1, tooling

1. **Generator.** `rake type:new[kanban]` scaffolds the four files and
   their specs from templates, and prints the `TYPES` row to paste. The
   templates encode the conventions, so they cannot be got wrong.
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
   - the five files and what each owns, in one sentence each
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
- [ ] a spec asserts the file count: adding `demo` touched 5 files
- [ ] `docs/adding-a-diagram-type.md` exists, and someone who has not
      read this plan can follow it end to end
- [ ] `rake corpus[<type>] --failing` output is good enough to work from

## Do not

- Do not make the generator configurable. One template set, no options.
- Do not generate a layout file by default — most types do not need one
  (item 04). Add a `--layout` flag if you want it.

## Files

`lib/tasks/type.rake` (new), `spec/support/shared_examples.rb` (new),
`lib/tasks/corpus.rake`, `docs/adding-a-diagram-type.md` (new),
`lib/generators/templates/` (new).
