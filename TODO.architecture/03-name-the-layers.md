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

(Nine is right for that pair. **Ten** renderers take a `layout`
parameter — `treemap.rb` is the tenth and does not define
`create_document_from_layout`. Elsewhere the figure is ten because the
claim there is only about the parameter name.)

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
   explicitly. It stays a stub, and it is **explicitly temporary**: put
   a comment at the top saying item 06 deletes it, and when — once
   `Engine` no longer receives a legacy result to hand it. It has no
   successor; nothing takes its place.

   Its life is short. It exists to hold the engine's positioning code
   while legacy layouts still return graphs; item 06 deletes it once
   item 04 has converted the last one. It is not the thing elkrb
   replaces — see `06-registry-as-data.md` and `08-burndown.md`.
4. **Uniform class names.** `Sirena::<Layer>::<Type>` everywhere:
   `Parser::Pie`, `Diagram::Pie`, `Layout::Pie`, `Renderer::Pie`. The
   suffix repeats the namespace; drop it.

   **The Diagram layer is included, and 10 of 24 need work.** Measured
   2026-08-27, and measured the right way: *"does the constant resolve"*
   is not the question, because for two types it resolves to the wrong
   class. The question is whether the conventional constant **is the
   type's top-level model**.

   Seven are plain renames — nothing else owns the target name:

   | today | after |
   |---|---|
   | `Diagram::GanttChart` | `Diagram::Gantt` |
   | `Diagram::QuadrantChart` | `Diagram::Quadrant` |
   | `Diagram::RadarChart` | `Diagram::Radar` |
   | `Diagram::ArchitectureDiagram` | `Diagram::Architecture` |
   | `Diagram::SankeyDiagram` | `Diagram::Sankey` |
   | `Diagram::PacketDiagram` | `Diagram::Packet` |
   | `Diagram::TreemapDiagram` | `Diagram::Treemap` |

   **`xychart` is not a two-part rename. It is ten places — eight in the
   table below, plus the grammar and builder named under it.** It is the only
   key that does not match its own file name, and item 06 makes the key
   the single source every class is derived from, so every place the
   old spelling appears has to move together:

   | what | today | after |
   |---|---|---|
   | registry key | `:xychart` | `:xy_chart` |
   | detector key | `Engine::DIAGRAM_TYPE_PATTERNS[:xychart]` | `[:xy_chart]` |
   | model | `Diagram::XYChart` (`diagram/xy_chart.rb:6`) | `Diagram::XyChart` |
   | model's `diagram_type` | `:xychart` | `:xy_chart` |
   | parser | `Parser::XYChartParser` (`parser/xy_chart.rb:31`) | `Parser::XyChart` |
   | layout | `Transform::XYChart` (`transform/xy_chart.rb:16`) | `Layout::XyChart` |
   | renderer | `Renderer::XYChart` (`renderer/xy_chart.rb:26`) | `Renderer::XyChart` |
   | contract fixture | `spec/fixtures/contract/xychart.mmd` | `xy_chart.mmd` |

   Rows nine and ten are the inner grammar and builder classes,
   `Parser::Grammars::XYChart` (`parser/grammars/xy_chart.rb:10`) and
   `Parser::Transforms::XYChart` (`parser/transforms/xy_chart.rb:9`).
   No key addresses them, but leaving one spelling behind in a file
   where everything else moved is how the next person gets it wrong.

   What each miss costs you:

   | miss | what fails, and when |
   |---|---|
   | registry key | `DiagramRegistry.get(:xy_chart)` returns nil; the engine cannot dispatch. Immediate |
   | detector key | item 01's set-parity assertion goes red. Immediate |
   | model constant | **item 03's own criterion** below goes red — `Diagram::XyChart` must resolve and equal what the parser returns. Immediate. Item 06 is the second net, not the first |
   | `diagram_type` | item 01's contract spec goes red. Immediate |
   | parser or renderer class | item 06's lookup finds nothing for a **mandatory** layer. It must raise, not return nil — see below |
   | layout class | item 06's lookup cannot resolve it and raises `LayoutError`. Loud, but only because item 04 gave every type a layout — there is no optional-layout branch left for a misspelled constant to slip down |
   | contract fixture filename | item 01's spec cannot find `xy_chart.mmd`, so it goes red **immediately** — not at item 06. Item 06's fixture parity is the second net, not the first |
   | grammar or builder class | nothing fails; the inconsistency just survives |

   The parser, layout and renderer rows above are why item 06's lookups
   raise rather than answer `nil`. All three layers are mandatory — item 04 gives every type a
   layout — so a constant that does not resolve is always a broken
   rename, never a legitimate absence. Each layer raises its own error:
   `ParseError`, `LayoutError`, `RenderError`. An unknown type is a
   different failure and raises `DiagramTypeError`.

   **Two are collisions, and they are the reason a bare resolution
   check is not enough.** `Diagram::Block` and `Diagram::Requirement`
   both already exist — as *components*, one block and one requirement
   (`diagram/block.rb:8`, `diagram/requirement.rb:8`). The actual models
   are `BlockDiagram` (`:62`) and `RequirementDiagram` (`:100`). A check
   that only asks "does `Diagram::Block` exist" passes today and passes
   for the wrong reason.

   | today | after |
   |---|---|
   | `Diagram::Block` (a component) | `Diagram::BlockNode` |
   | `Diagram::BlockDiagram` (the model) | `Diagram::Block` |
   | `Diagram::Requirement` (a component) | `Diagram::RequirementNode` |
   | `Diagram::RequirementDiagram` (the model) | `Diagram::Requirement` |

   Both swaps land **inside step 4's single commit**, and each swap is
   atomic — move the component out and rename the model in together.
   This item ships one commit per numbered rename, so the collisions do
   not get their own commits; splitting a swap would leave a state where
   the identity criterion above is deliberately false and
   `corpus:check` has nothing to compare against.

   Other inner classes — `Diagram::GanttTask`, `Diagram::BlockStyle` —
   keep their names. They are not addressed by a registry key.

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
- [ ] for every registry key, `Sirena::Diagram::<CamelKey>` resolves
      **and is the same class the parser returns** for that type's
      canonical fixture. Existence alone is not the check — it passes
      for `:block` today while resolving to a component
- [ ] do not also ask that no name ends in `Chart` or `Diagram`.
      `:xy_chart` correctly gives `XyChart` and `:class_diagram`
      correctly gives `ClassDiagram`. A suffix is only wrong when the
      key does not contain it, and the identity check above catches
      exactly that
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

**Items 02, 03 and 06 DO change observable behaviour** and are blocked by
it too. An earlier draft exempted them; that was wrong on all three,
measured 2026-09-02:

- **Item 02** removes the currently callable `Svg::Text.from_xml` path.
- **Item 03** changes the registry/detector/model value `:xychart` to
  `:xy_chart`, which is observable in `sirena types` output.
- **Item 06** is the engine/registry/CLI work that `TODO.foundation/03:16-20`
  names explicitly.

None of the eight items is exempt from the retained `03a` gate.

**Items 01, 04, 05 and 08 are blocked.** An earlier draft exempted all
of 01-06 and that was wrong twice over:

- **Item 01** changes behaviour in both parts. Part A closes a latent
  runtime crash; Part B deliberately changes a failing parse from
  `PipelineError` to `ParseError`. `TODO.foundation/03`'s only exemption
  is the lutaml migration, and item 01 is not it.
- **Item 04** sizes boxes from theme metrics; **item 05 part C** swaps
  hardcoded hex for theme colours. Both change what a user sees.

**This has to be in their headers, not only here.** Item 01, item 04 and
item 05 each carry 03a as a prerequisite alongside whatever else they
list; a dependency that lives in one narrative paragraph is a dependency
nobody checks.

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
