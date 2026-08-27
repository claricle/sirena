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
   `Parser::Pie`, `Diagram::Pie`, `Layout::Pie`, `Renderer::Pie`. All
   four are mandatory — item 04 gave every type a layout — so a
   constant that does not resolve is an error, never an absence. Item
   03 made the names uniform so this works.

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
   fails when a type is wrong. Its criteria are in `## Done when` below,
   not here — the plan scorer reads that list and stops, so a check
   parked in a step does not gate anything.

   One trap worth naming. Item 01's spec catches a deleted registry row
   because it compares two lists. After this item there is only `TYPES`,
   and a spec that iterates `TYPES` **cannot** notice a missing row — the
   row's example simply stops existing and the suite goes green with one
   fewer test. Restore the second inventory from something outside the
   table: the canonical fixture basenames under
   `spec/fixtures/contract/`. One fixture per type, and `TYPES` must
   match that set exactly.

   This does not contradict the parity assertion disappearing. Detection
   itself does not go away — it moves into `Notation::Mermaid` and reads
   `TYPES`. What goes away is the detector's *separate inventory*, and
   with it registry-versus-detector parity. What replaces it is
   table-versus-fixtures parity.
4. Delete the stray `self.render` at `lib/sirena.rb:38`.
5. `Engine` holds no type constants. Its render method's **core
   pipeline** is the four lines from `00-overview.md`, the first being
   `type = Notation::Mermaid.detect(source)` — detection moved, it did
   not vanish. Theme resolution, `today`, `verbose` and the
   `Svg::Document` -> String conversion all stay exactly where they are;
   step 6 requires it.
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
- [ ] `contract_spec.rb` iterates `TYPES` and covers every entry
- [ ] it still resolves each model by convention, and still runs each
      canonical fixture
- [ ] and still asserts the **parsed fixture's class is** the
      convention-resolved model. Resolution and fixture-runs as two
      separate checks is what let `:block` pass while pointing at a
      component. Item 03 closed that; do not reopen it here
- [ ] it asserts `TYPES` keys match the basenames under
      `spec/fixtures/contract/` exactly, in both directions
- [ ] deleting one `TYPES` row turns it red — check it, do not assume
      it. Without the fixture parity above, deletion is silent
- [ ] it passes with `model:` removed from every registration
- [ ] the three `.for` lookups return a **fresh instance**, not a class
      and not a cached one. The pipeline calls `.parse`, `.call` and
      `.render` on the result directly, and `Layout::Base#call` stores
      the theme and the date on the instance — a memoised lookup would
      share that state across concurrent renders
- [ ] `Renderer.for(type, theme:)` takes the theme, because
      `renderer/base.rb:42` already keeps it on the instance. `render`
      stays one-argument. Item 06 changes how a renderer is found, not
      how it is called
- [ ] a spec asserts two calls to the same `.for` return different
      object ids
- [ ] all three answer **three** cases, and every layer raises **its
      own** error class. A bare "it raises" passes while a `KeyError`,
      `NameError` or `LoadError` leaks out, and a blanket
      `DiagramTypeError` contradicts the taxonomy in `LAYERS.md`:

      | case | `Parser.for` | `Layout.for` | `Renderer.for` |
      |---|---|---|---|
      | type not in `TYPES` | `DiagramTypeError` | `DiagramTypeError` | `DiagramTypeError` |
      | known type, constant resolves | an instance | an instance | an instance |
      | known type, constant does not resolve | `ParseError` | `LayoutError` | `RenderError` |

      Unknown type is a *notation* failure, so it is `DiagramTypeError`
      for all three. A broken convention lookup is a failure **of that
      layer**, so it takes that layer's error.

      There is no "no layout" row. Every type has a layout (item 04),
      so `Layout.for` never returns `nil`
- [ ] every cell has a spec. The raising cells assert the exact class;
      the resolving cell asserts the instance's class is the
      convention-resolved one
- [ ] a spec proves a misnamed layout constant raises rather than
      rendering an unlaid-out diagram with no error, which is worse
      than a crash
- [ ] every piece of item 04's temporary transition machinery is gone,
      not just the fallback branch:
      - `Layout::Base`'s `to_graph` branch, and
        `grep -rn "to_graph" lib/sirena/` returns nothing
      - the `Layout::Legacy` wrapper class
      - `Engine`'s Grid gate, and the Grid stage itself if nothing
        legacy can reach it
      - `spec/support/legacy_layout.rb` and the transition spec
      A temporary thing with no deletion criterion is a permanent thing

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
`lib/sirena/diagram_registry.rb`, `lib/sirena/engine.rb`,
`lib/sirena/layout/base.rb` (the `to_graph` fallback comes out),
`spec/contract_spec.rb` (migrated from `DiagramRegistry.types` to
`TYPES`), `spec/sirena/lookup_spec.rb` (new, the three-case matrix above).

`Parser.for`, `Layout.for` and `Renderer.for` live on their own
namespace modules — `lib/sirena/parser.rb`, `lib/sirena/layout.rb`,
`lib/sirena/renderer.rb`. Name them somewhere; three lookups with no
declared home is how they end up on `Engine` again.
