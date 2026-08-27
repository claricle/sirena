# 06 — Registry as data

**Goal:** a diagram type is declared in exactly one place.
**Size:** 1 PR. `lib/sirena.rb` goes from 328 lines to under 40.
**Prerequisite:** item 03 (needs uniform class names).

## Why

`lib/sirena.rb` is 328 lines: the same block copy-pasted 24 times.

```ruby
require_relative 'sirena/parser/pie'
require_relative 'sirena/transform/pie'
require_relative 'sirena/renderer/pie'

Sirena::DiagramRegistry.register(
  :pie,
  parser: Sirena::Parser::PieParser,
  transform: Sirena::Transform::PieTransform,
  renderer: Sirena::Renderer::PieRenderer
)
```

Detection is a **second, separate list**: a 24-entry regex table
hardcoded in `Engine::DIAGRAM_TYPE_PATTERNS` (`engine.rb:32`). Adding a
type means editing two files in two different shapes and hoping the
symbols match.

There is also dead code to delete by name: `lib/sirena.rb:38` defines a
stray top-level `def self.render` on `main`, referencing a bare `Engine`
constant. It would raise `NameError` if anything ever called it.

## Before you start

PlantUML is committed for the next few months (`00-overview.md`). Read
`TODO.foundation/12` and `16` first — not to build anything from them,
but so this table does not paint PlantUML into a corner.

The one thing that matters for that: **detection lives inside
`Notation::Mermaid`, never in `Engine`.** A second notation then adds a
second module and a line in the engine, instead of a second regex table
in a file that already knows about Mermaid.

**The boundary this sets is interim, and it has a named successor.**
`TODO.foundation/10:25-36` carries the owner's 2026-08-13 ruling and is
explicit about it: today each notation's transform shapes stay private
to that notation; after `TODO.foundation/18` the typed IR is
deliberately **shared**, and what stays private is each notation's parse
output before it becomes IR. Write any boundary assertion so item 18
updates it rather than deletes it, and **do not describe today's shapes
as permanent** — that is the item's own wording.

## Steps

1. One table, one row per type, in `lib/sirena/notation/mermaid.rb` —
   the only place a type is declared:

```ruby
TYPES = {
  pie:       /\A\s*pie\s/i,
  flowchart: /\A\s*(graph|flowchart)\s+/i,
  # ...
}
```

2. Resolve classes by convention from the type name: `:pie` ->
   `Parser::Pie`, `Diagram::Pie`, `Layout::Pie` (only if that file
   exists), `Renderer::Pie`. Item 03 made the names uniform so this
   works.

   That includes the `model:` row item 01 added to `DiagramRegistry`.
   It stops being a row and becomes the convention; `contract_spec.rb`
   iterates `TYPES` instead. Its set-parity assertion collapses to
   nothing, because there is now one table to be out of step with.

   **This only works if item 03 step 4 renamed the Diagram models.**
   Eight of them carry a `Chart` or `Diagram` suffix today and do not
   resolve. Check that first — `Diagram::Gantt` must answer before you
   delete the `model:` row, or a third of the types lose their contract.
3. Detection reads the same table. One list, not two.

   `contract_spec.rb` moves with it, and it must still be the thing that
   fails when a type is wrong. Done-when for this migration:
   - it iterates `TYPES`, and covers every entry
   - it still resolves each model and still runs each canonical fixture
   - deleting one `TYPES` row turns it red
   - it passes with `model:` removed from every registration
4. Delete the stray `self.render` at `lib/sirena.rb:38`.
5. `Engine` holds no type constants. Its render method is the three
   lines from `00-overview.md`.
6. Keep the public API byte-identical: `Sirena.render(source, options)`
   and `Engine#render` behave exactly as before, including error
   classes and messages.

## Done when

- [ ] `lib/sirena.rb` is under 40 lines
- [ ] a diagram type is declared in exactly one place
- [ ] `Engine` contains no diagram-type constants
- [ ] `grep -n "def self.render" lib/sirena.rb` shows one, inside `module Sirena`
- [ ] the CLI and `Sirena.render` behave identically; `corpus:check`
      unchanged

## Do not

**Do not build a notation plugin system** — even though PlantUML is
coming. No plugin objects, no two-level registry, no RubyGems discovery
hook, no loading notations from a directory. One notation exists today,
so any API you design now is a guess; the PlantUML PR will show you what
the second one actually needs. A `Notation::Mermaid` module with its own
`TYPES` table is the whole seam required, and it costs nothing to
extend.

`DO-NOT-BUILD.md` records the trigger for when this becomes real work.

## Files

`lib/sirena.rb`, `lib/sirena/notation/mermaid.rb` (new),
`lib/sirena/diagram_registry.rb`, `lib/sirena/engine.rb`.
