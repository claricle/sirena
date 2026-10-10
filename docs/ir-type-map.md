# Typed IR shape and ownership map

This is the design record for Foundation 18 steps 1–3. It compares the
Mermaid emit/accept survey with the shipped PlantUML class slice, fixes the
three shared IR shapes, and gives every registered Mermaid type one mapping.

## Evidence from both notations

The Mermaid survey in `docs/emit-accept-survey.md` found two implementation
forms: seven layouts emitted ELK-like `children` and `edges`, while seventeen
emitted type-specific hashes. That representation difference is incidental.
Across both groups the stable concepts are identities, labels, ordered items,
containment, endpoint identity, scalar values, and source-domain placement
constraints. The survey also proves that Mermaid's `metadata`, option names,
and final coordinates are not a safe shared contract: elkrb drops unknown
metadata, translates only some options, and produces geometry of its own.

The PlantUML class slice supplies the second-notation check. Its private parse
model (`lib/sirena/notation/plantuml/diagram.rb`) has classes and relations;
its layout (`lib/sirena/notation/plantuml/layout.rb`) measures boxes, places
them, and routes relations; and its final Scene contains drawable geometry
(`lib/sirena/notation/plantuml/scene.rb`). PlantUML therefore needs the same
graph concepts as Mermaid class diagrams without sharing PlantUML keywords,
member syntax, relation spellings, or its Scene classes. This rules out both a
Mermaid-hash IR and a final-canvas Scene as the notation-neutral boundary.

## Boundary and ownership

The pipeline boundary is:

```text
notation source -> private parse model -> notation adapter -> shared IR
                                                       |
                                                       v
                                    layout -> positioned Scene -> renderer
```

Notation adapters run **before** layout. They remove source-language spelling
and map private models to the shared concepts below. Mermaid keywords,
PlantUML relation tokens, parser nodes, source aliases, comments, directives,
and notation-specific error context stay on the private side. A shared field
may carry a normalized semantic or drawing role, but neither its name nor its
value may name a notation construct.

Layout owns **all geometry**: measured width and height, x/y coordinates,
canvas bounds, routes and bend points, SVG paths and polygon points, computed
label anchors, and final angles or percentages used for drawing. None belongs
in adapter output. Source-domain constraints such as a grid cell, bit range,
date, or chart coordinate are input data, not final canvas geometry.

The shared fields common to all shapes are `id`, ordered `items`, normalized
`label`/`role`, optional `parent_id`, and notation-neutral `properties`.
Properties are a closed, typed vocabulary owned by the IR; they are not an
escape hatch for a notation's metadata hash.

## The three shapes

The tests are applied in this order; the first match wins.

1. **pre-positioned** carries items plus source-domain placement constraints
   that completely determine relative placement for every valid document.
   Its distinguishing field is a typed `placement` value (dimension, ordinal,
   value, and optional span), not an x/y canvas coordinate. Connectivity may
   also exist, as Block demonstrates, but does not change the first match.
2. **graph-shaped** carries `nodes` and `edges`; every edge has `source_id`
   and `target_id` that resolve to node identity. Nodes may carry `parent_id`
   for containment. Edge kind, markers, labels, and weights use normalized IR
   roles. Layout chooses node geometry and routes.
3. **data-shaped** carries ordered dimensions, series, and data values (or
   ordered content with containment) without identity-based connectivity.
   Layout chooses the visual form and all geometry. This is the exhaustive
   residual category, not an exception path.

## Mermaid type decisions

Each implementation path exists on this revision. Evidence cites the current
layout behavior; the older survey's `transform/*` wording refers to these
`lib/sirena/layout/*` implementations.

| Type | Shape | Implementation | Evidence |
|---|---|---|---|
| `flowchart` | `graph-shaped` | `lib/sirena/layout/flowchart.rb` | `build_graph` emits identified children and source/target edges (164–169); layout later supplies positions and routes. |
| `sequence` | `graph-shaped` | `lib/sirena/layout/sequence.rb` | Participants are nodes and messages identify their endpoints (91–96, 154–165); message order remains an edge property. |
| `class_diagram` | `graph-shaped` | `lib/sirena/layout/class_diagram.rb` | Classes become children and relationships carry resolvable source/target ids (120–125, 169–174). |
| `state_diagram` | `graph-shaped` | `lib/sirena/layout/state_diagram.rb` | States become children and transitions become endpoint-identified edges (196–201, 250–259). |
| `er_diagram` | `graph-shaped` | `lib/sirena/layout/er_diagram.rb` | Entities become children and relationships resolve source and target entities (223–229, 314–322). |
| `user_journey` | `graph-shaped` | `lib/sirena/layout/user_journey.rb` | Tasks are identified children and consecutive task flow emits source/target ids (41–46, 89–100). |
| `gantt` | `pre-positioned` | `lib/sirena/layout/gantt.rb` | Dates, durations, declaration order, and dependencies determine task intervals before drawing (21–31, 60–101). |
| `pie` | `data-shaped` | `lib/sirena/notation/mermaid/ir_adapters/pie.rb` | Ordered slice values and visibility become shared data; layout alone computes percentages, angles, paths, and labels. |
| `timeline` | `pre-positioned` | `lib/sirena/layout/timeline.rb` | Event time values determine their position on the source-domain timeline (21–34, 45–74, 98–112). |
| `quadrant` | `pre-positioned` | `lib/sirena/layout/quadrant.rb` | Each point's source x/y values determine its place in the fixed 2x2 chart (28–48, 138–158). |
| `git_graph` | `graph-shaped` | `lib/sirena/layout/git_graph.rb` | Commits identify parents and emitted connections identify from/to commits (45–82, 226–257); branch order only influences layout. |
| `mindmap` | `graph-shaped` | `lib/sirena/notation/mermaid/ir_adapters/mindmap.rb` | Tree nodes map to shared identities, containment, and resolved parent/child edges; layout owns their geometry. |
| `kanban` | `data-shaped` | `lib/sirena/layout/kanban.rb` | Columns contain ordered cards but no identity-based edges; layout chooses stacking and dimensions (42–59, 79–130). |
| `radar` | `data-shaped` | `lib/sirena/layout/radar.rb` | Axes and curve values are data series without endpoint connectivity; layout derives polar geometry (36–64, 108–139). |
| `block` | `pre-positioned` | `lib/sirena/layout/block.rb` | The grammar's column count, spaces, order, and spans fix the grid (28–38, 43–109); its from/to connections do not override the first test (182–198). |
| `requirement` | `graph-shaped` | `lib/sirena/layout/requirement.rb` | Requirements/elements are identified nodes and relationships name source and target (31–41, 113–133, 199–224). |
| `xychart` | `pre-positioned` | `lib/sirena/layout/xy_chart.rb` | Axis domains and data values determine plot positions in source-domain coordinates (33–58, 190–224). |
| `architecture` | `graph-shaped` | `lib/sirena/layout/architecture.rb` | Services/junctions have ids and each embedded edge model retains `from_id`/`to_id` even though the output also has routed coordinates (24–41, 296–317). |
| `sankey` | `graph-shaped` | `lib/sirena/notation/mermaid/ir_adapters/sankey.rb` | Flows map to shared nodes and resolved weighted edges; layout owns layering, positions, and paths. |
| `packet` | `pre-positioned` | `lib/sirena/layout/packet.rb` | Field bit ranges determine row, column, and span in the fixed-width bit grid (40–59, 115–180). |
| `treemap` | `data-shaped` | `lib/sirena/layout/treemap.rb` | Nested values have containment but no endpoint connectivity; layout allocates space from values (19–44, 47–85). |
| `c4` | `graph-shaped` | `lib/sirena/layout/c4.rb` | Elements/boundaries become identified children and relationships carry source/target ids (40–50, 178–206). |
| `info` | `data-shaped` | `lib/sirena/notation/mermaid/ir_adapters/info.rb` | The title and show-information flag map to shared data without nodes or connectivity; layout owns panel geometry. |
| `error` | `data-shaped` | `lib/sirena/notation/mermaid/ir_adapters/error.rb` | The title and message map to shared ordered content without connectivity; layout owns panel geometry. |

Summary: **6 pre-positioned, 12 graph-shaped, 6 data-shaped; 24 total.**

Migration status: **5 of 24 Mermaid types use the shared IR boundary** — 2
graph-shaped (`mindmap`, `sankey`) and 3 data-shaped (`pie`, `info`, `error`);
19 types remain on their private layout inputs.

`rake type:new[<type>]` adds a data-shaped row immediately above this
summary and recalculates all four counts from the table. The generated adapter
maps the private ordered-item model to `IR::Data`; changing the generated type
to another shape means changing that adapter and this row together.

## Consequence for implementation

Foundation 18 migration adds one notation adapter per private parse model (or
per type where a notation already splits them), then passes only these shared
shapes into layout. Existing Mermaid `build_graph` methods currently combine
adaptation with geometry and must be split during steps 4–5. The PlantUML
class adapter maps its private classes and relations to the same graph shape;
its current layout remains responsible for measuring, placing, and routing.
