# 03 — Name the layers honestly

**Goal:** no two layers share a name, and every class name says what it
does.
**Size:** 4 PRs, one per rename. Large diffs, zero logic change.
**Prerequisite:** item 01.

This is a pure rename. Nothing in it changes behaviour, and
`rake corpus:check` must show **zero** change after every one of the
four PRs. If it moves, you have a typo — find it before continuing.

## Why

**(a) Two different layers are both called "Transform".**

```
  Sirena::Parser::Transforms::Pie    parse tree  -> Diagram model
  Sirena::Transform::PieTransform    Diagram model -> Hash
```

**(b) The layer called `Transform` is doing layout.**

```
  Transform::Mindmap        position_tree, position_children, calculate_bounds
  Transform::XYChart        axis scales, point coordinates
  Transform::InfoTransform  copies 3 fields into a hash (38 lines)
```

Meanwhile `Engine#layout_graph` (`engine.rb:199`) — the method named
layout — applies a 3-column grid and only fires on graphs that have
`:children` and no `x`/`y`. Nine renderers already take a parameter
named `layout` and define `create_document_from_layout`. The renderers
have the right name; the classes have the wrong one.

**(c) Registered class names follow three conventions.** 17 types use
`XParser` / `XTransform` / `XRenderer`. Seven use the bare type name for
transform and renderer (`GitGraph`, `Mindmap`, `Kanban`, `Radar`,
`XYChart`, `Packet`, `Treemap`). One parser is bare
(`Parser::Architecture`). Item 06 cannot look classes up by convention
until this is uniform.

## Steps

One commit — and one PR — per rename.

1. **`Parser::Transforms::X` -> `Parser::Builders::X`**
   Directory `parser/transforms/` -> `parser/builders/`. It builds a
   model from a parse tree; that is what a builder does.
2. **`Transform::X` -> `Layout::X`**
   Directory `transform/` -> `layout/`. `Transform::Base` ->
   `Layout::Base`, `TransformError` -> `LayoutError`.
3. **`Engine#layout_graph` / `apply_fallback_layout` -> `Layout::Grid`**

   A named class in `lib/sirena/layout/grid.rb` that the engine calls
   explicitly. It stays a stub, and it is **explicitly temporary**: put a
   comment at the top naming its successor. Geometry parity is the agreed
   bar, so elkrb replaces it in item 08 step 3. The point of giving it a
   name and one caller now is that the replacement touches this file and
   nothing else.
4. **Uniform class names.** `Sirena::<Layer>::<Type>` everywhere:
   `Parser::Pie`, `Diagram::Pie`, `Layout::Pie`, `Renderer::Pie`. The
   suffix repeats the namespace; drop it.

   **The Diagram layer is included, and 8 of 24 need it.** Measured
   2026-08-27 by resolving every registry key to its conventional
   constant:

   | today | after |
   |---|---|
   | `Diagram::GanttChart` | `Diagram::Gantt` |
   | `Diagram::QuadrantChart` | `Diagram::Quadrant` |
   | `Diagram::RadarChart` | `Diagram::Radar` |
   | `Diagram::XYChart` | `Diagram::XyChart` |
   | `Diagram::ArchitectureDiagram` | `Diagram::Architecture` |
   | `Diagram::SankeyDiagram` | `Diagram::Sankey` |
   | `Diagram::PacketDiagram` | `Diagram::Packet` |
   | `Diagram::TreemapDiagram` | `Diagram::Treemap` |

   Rename the registry key `:xychart` to `:xy_chart` in the same PR. It
   is the only key that does not match its own file name, and item 06
   makes the key the single source the class is derived from.

   Only the top-level model per type is in scope. Inner classes like
   `Diagram::GanttTask` keep their names — they are not addressed by a
   registry key.

   The other 16 already resolve. If this step is skipped, item 06's
   convention lookup misses a third of the types and item 01's contract
   spec goes red.

**No deprecated aliases.** The gem is pre-1.0 with nothing released, and
breaking changes are explicitly allowed (`00-overview.md`). Update every
caller in `spec/`, `scripts/` and `lib/tasks/` and delete the old names.

## Done when

- [ ] `grep -rn "Sirena::Transform\|Transform::Base\|TransformError" lib/`
      returns nothing.

      Not a bare `grep -rn "Transform" lib/` — that can never return
      nothing. Ten builder files inherit `Parslet::Transform`
      (`parser/transforms/block.rb`, `flowchart`, `git_graph`, `kanban`,
      `mindmap`, `packet`, `radar`, `requirement`, `treemap`,
      `xy_chart`), and that is the gem's class name, not ours.
- [ ] class names are uniform, no `Parser`/`Transform`/`Renderer` suffixes
- [ ] every registry key resolves to `Sirena::Diagram::<CamelKey>`;
      no `Chart`/`Diagram` suffix survives on a top-level model
- [ ] `Layout::Grid` exists; `Engine` contains no positioning code
- [ ] `rake corpus:check` shows **zero** change after each of the 4 PRs

## The coverage gate this item does not repeal

`TODO.foundation/03-coverage-gate.md:16` says **"No behavior PR may
close before 03a lands"**, and `TODO.foundation/05` names 03a as a
completion prerequisite. This plan simplifies item 03's *staged
timeline* (see `DO-NOT-BUILD.md`) — it does not lift that gate, and it
never mentioned 03a at all, which read as if the gate had gone.

It has not. 03a is the coverage instrumentation plus one line floor and
one branch floor. Land it before the first behaviour PR, exactly as
`TODO.foundation/03` says. What this plan drops is only the
70 -> 80 -> 90 -> 97 timeline tied to other tracks' completion events.

Items 01-06 are refactors and change no behaviour, so they are not
blocked by it. Item 08 is, and so is anything in item 05 that changes a
parse-error message.

## Do not

- Do not fix anything you notice while renaming. Write it down instead.
  A rename PR that also changes behaviour cannot be reviewed, and it
  breaks the "zero change" check that makes this item safe.
- Do not change the public API: `Sirena.render` and `Engine#render` keep
  their names and signatures.

## Files

`lib/sirena/parser/builders/*` (moved), `lib/sirena/layout/*` (moved),
`lib/sirena/layout/grid.rb` (new), `lib/sirena/engine.rb`,
`lib/sirena.rb`, `lib/sirena/renderer/*.rb`, all affected specs.
