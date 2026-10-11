# Transform emit/accept survey

This is the executable evidence for Foundation 14, step 2, and the input to
Foundation 18. It records the current boundary, not the pre-Scene architecture
assumed by the original plan text.

## Method and contract

The survey was measured on exact `main` at
`ae7b1d8fee2967e882668af37cfcd2512cdc254f` with installed elkrb 1.0.2.
Run it again with:

```sh
ruby scripts/emit_accept_survey.rb
```

The script enumerates `DiagramRegistry.types`; for every registered type it:

1. parses the first non-beta `.mmd` file in that type's `examples/` directory;
2. applies the Mermaid adapter to obtain the shared `IR::Graph`,
   `IR::Prepositioned`, or `IR::Data` value;
3. calls the registered transform (`Layout::<Type>#call`) and passes the
   emitted typed Scene to the real installed `Elkrb.layout`;
4. where the layout has a pre-Scene `build_graph` handoff, passes that exact
   Hash to `Elkrb.layout` too; and
5. verifies the registry roster, IR category, direct failure family, and
   pre-Scene acceptance result. Any drift exits non-zero.

Calling private `build_graph` is deliberate audit instrumentation, not a new
API. It locates the only useful ELK boundary: before final Scene geometry is
created. A registered transform now emits a final typed Scene, so passing that
result back through a layout engine would be architecturally backward even if
the gem happened to accept it.

The installed gem accepts an `Elkrb::Graph::Graph` or a Hash carrying
ELK-shaped `children` and `edges`. A typed Scene is neither. Scenes with a
`children` collection advance farther but fail when elkrb asks their typed
nodes for `ports`; other Scenes fail immediately because they have no
`children`. These are real gem results, not inferred schema comparisons.

The previous version of this document measured commit `7d41197a`, where all
24 layouts still returned `Layout::Legacy` Hashes and the engine applied a
fallback grid afterward. That boundary no longer exists: the registry now
names `Layout::*` classes and all 24 return typed, fully positioned Scenes.
The old per-corpus acceptance counts were therefore removed rather than
presented as current facts.

## Retained elkrb 1.0.2 constraints

The prior survey also isolated gem behavior that remains relevant to the new
handoff rows. These constraints are properties of the same pinned elkrb 1.0.2
contract and still shape each rollout:

- Hash input uses symbol keys and must contain `children`; every node needs
  numeric `width` and `height` values.
- Unknown keys such as Sirena's `metadata` are not retained. elkrb does retain
  its modeled `properties` Hash, so rollout must either use `properties` or
  reattach semantic metadata by stable id.
- A self-loop recurses until `SystemStackError`; an edge to an unknown id is
  instead returned without a route. Neither condition is a usable success.
- Algorithm, spacing, and padding are call options. `layoutOptions` does not
  select the algorithm, and layered does not implement direction itself.
  `Layout::ElkPlacement` is the integration boundary that translates the
  supported options and excludes self-loops.
- Child coordinates are relative to their container. Edges touching nested
  nodes are not routed by layered, and zero-sized containers can overlap their
  peers unless Sirena supplies truthful container dimensions first.
- `Elkrb.known_layout_algorithms` is broken in 1.0.2 because it calls a
  nonexistent registry method. `AlgorithmRegistry.available_algorithms` is
  the working introspection surface.

## Results

No registered transform's final Scene is accepted directly. Seven existing
pre-Scene Hashes are accepted and return positioned nodes and routed edges;
fifteen Hashes are rejected because they do not carry ELK `children`; Timeline
and Sankey expose no `build_graph` handoff.

“Retain” below is the technical disposition supported by this evidence. Where
Foundation 14 requires a user-approved exception, that approval is still a
separate recorded decision; this survey does not manufacture it.

| Type | Registered transform and emitted Scene | Real elkrb result | Gap | Rollout disposition and evidence |
|---|---|---|---|---|
| `flowchart` | `Layout::Flowchart`; `children=11`, `edges=12` | Scene rejected: node has no `ports`. Pre-Scene `Hash{id,children,edges,layoutOptions}` accepted as 11 nodes / 12 edges. | Final Scene is too late; existing graph handoff is valid. | Keep the existing explicit ELK path. Probe: `examples/flowchart/00-original.mmd`. |
| `sequence` | `Layout::Sequence`; 5 participants, 5 lifelines, 14 messages, 1 note | Scene rejected: no `children`. Pre-Scene ELK Hash accepted as 5 nodes / 14 edges. | Syntactic acceptance loses the sequence contract: participant columns, lifelines, and vertical message time are Scene geometry, not generic graph topology. | Retain the sequence layout; propose a semantic exception despite Hash acceptance. Probe: `examples/sequence/01-basic-sequence.mmd`. |
| `class_diagram` | `Layout::ClassDiagram`; `children=8`, `edges=7`, no notes/namespaces | Scene rejected: node has no `ports`. Pre-Scene `Hash{id,children,edges,layoutOptions}` accepted as 8 / 7. | Valid graph handoff exists; namespace/note constraints need loud refusal or adapters. | Wire the accepted flat graph through ELK and ratchet parity; keep unsupported nested cases explicit. Probe: `examples/class_diagram/01-basic-classes.mmd`. |
| `state_diagram` | `Layout::StateDiagram`; `children=13`, `edges=18` | Scene rejected: node has no `ports`. Pre-Scene ELK Hash accepted as 13 / 18. | Final Scene is too late; existing graph handoff is valid. | Keep the existing explicit ELK path and its compound-state controls. Probe: `examples/state_diagram/01-simple-states.mmd`. |
| `er_diagram` | `Layout::ErDiagram`; `children=6`, `edges=8` | Scene rejected: node has no `ports`. Pre-Scene ELK Hash accepted as 6 / 8. | Valid graph handoff exists; relationship endpoints already identify entities. | Wire the accepted graph through ELK and ratchet ER parity. Probe: `examples/er_diagram/01-basic-entities.mmd`. |
| `user_journey` | `Layout::UserJourney`; 3 legend entries, 5 sections, 16 tasks, 1 arrow | Scene rejected: no `children`. Pre-Scene ELK Hash accepted as 16 / 15. | Valid task-flow graph exists; section and legend geometry remain post-layout concerns. | Wire the accepted graph through ELK and ratchet journey parity. Probe: `examples/user_journey/01-simple-journey.mmd`. |
| `gantt` | `Layout::Gantt`; 1 positioned section | Scene rejected: no `children`. Timeline Hash rejected: no ELK `children`. | Time-axis coordinates, exclusions, ticks, and task bars are the layout contract. | Retain the specialized time-axis layout; propose a pre-positioned exception. Probe: `examples/gantt/01-simple-timeline.mmd`. |
| `pie` | `Layout::Pie`; 4 slices and 4 legend entries | Scene rejected: no `children`. Slice Hash rejected: no ELK `children`. | Polar sectors have no node boxes or graph edges. | Retain polar layout; propose a data-shaped exception. Probe: `examples/pie/01-simple-chart.mmd`. |
| `timeline` | `Layout::Timeline`; 15 positioned cards | Scene rejected: no `children`. No `build_graph` handoff (`NotImplementedError`). | Chronological card placement is already the transform's meaning. | Retain the specialized timeline layout; propose a pre-positioned exception. Probe: `examples/timeline/01-simple-timeline.mmd`. |
| `quadrant` | `Layout::Quadrant`; 4 quadrants, 6 axes, 5 points | Scene rejected: no `children`. Chart-space Hash rejected: no ELK `children`. | Point coordinates and quadrant axes are explicit chart-space values. | Retain chart layout; propose a pre-positioned exception. Probe: `examples/quadrant/01-basic-quadrant.mmd`. |
| `git_graph` | `Layout::GitGraph`; 6 commits, 3 branches, 4 connections | Scene rejected: no `children`. `{commits,branches,connections,...}` Hash rejected: no ELK `children`. | Shared `IR::Graph` has identity, but the handoff uses branch-lane collections instead of ELK nodes/edges. | Add an IR-to-ELK adapter, then ratchet commit/branch semantics before rollout. Probe: `examples/git_graph/01-linear-history.mmd`. |
| `mindmap` | `Layout::Mindmap`; `children=18`, `edges=17` | Scene rejected: node has no `ports`. `{nodes,connections,...}` Hash rejected: no ELK `children`. | Graph identity exists but the pre-Scene spelling is non-ELK. | Add an IR-to-ELK hierarchy adapter and ratchet parent/child containment. Probe: `examples/mindmap/01-simple-tree.mmd`. |
| `kanban` | `Layout::Kanban`; 3 columns and 4 cards | Scene rejected: no `children`. Board Hash rejected: no ELK `children`. | Columns and card membership define board lanes; no graph connectivity exists. | Retain board layout; propose a data-shaped exception. Probe: `examples/kanban/01-simple-board.mmd`. |
| `radar` | `Layout::Radar`; 5 grid circles, 3 axes, 1 curve, 1 legend entry | Scene rejected: no `children`. Polar-data Hash rejected: no ELK `children`. | Axis angles, radii, and curve points are polar data, not graph nodes. | Retain radial layout; propose a data-shaped exception. Probe: `examples/radar/01-simple-radar.mmd`. |
| `block` | `Layout::Block`; `children=5`, `edges=4` | Scene rejected: node has no `ports`. `{blocks,connections,columns,...}` Hash rejected: no ELK `children`. | Source `columns` fixes the grid even though connections are recoverable. | Retain source-directed placement; propose the plan's named pre-positioned exception. Probe: `examples/block/01-basic-blocks.mmd`. |
| `requirement` | `Layout::Requirement`; `children=3`, `edges=2` | Scene rejected: node has no `ports`. `{requirements,elements,relationships,...}` Hash rejected: no ELK `children`. | Shared graph identity exists, but three domain collections have not been normalized to ELK nodes/edges. | Add an IR-to-ELK adapter, then ratchet requirement parity. Probe: `examples/requirement/01-basic-requirements.mmd`. |
| `xychart` | `Layout::XyChart`; 13 lines, 12 labels, 1 series, 1 legend entry | Scene rejected: no `children`. Axis/dataset Hash rejected: no ELK `children`. | Numeric scales determine marks in plot coordinates. | Retain chart layout; propose a pre-positioned exception. Probe: `examples/xychart/01-line-chart.mmd`. |
| `architecture` | `Layout::Architecture`; `children=4`, `edges=3` | Scene rejected: node has no `ports`. `{services,junctions,groups,edges,...}` Hash rejected: no ELK `children`. | Endpoints are recoverable in `IR::Graph`, but the handoff is not ELK-shaped and group containment must survive. | Add an IR-to-ELK adapter and ratchet groups, junctions, and edge ownership. Probe: `examples/architecture/01-basic-services.mmd`. |
| `sankey` | `Layout::Sankey`; 7 nodes and 6 weighted flows | Scene rejected: no `children`. No `build_graph` handoff (`NotImplementedError`). | It is graph-shaped, but weighted flow widths and layer conservation are its layout algorithm. | Retain Sankey's own layering; propose the documented graph-shaped exception. Probe: `examples/sankey/01-simple-flow.mmd`. |
| `packet` | `Layout::Packet`; 2 positioned fields | Scene rejected: no `children`. Field/bit-range Hash rejected: no ELK `children`. | Bit offsets and widths fully determine placement. | Retain packet layout; propose a pre-positioned exception. Probe: `examples/packet/01-basic-packet.mmd`. |
| `treemap` | `Layout::Treemap`; 1 nested cell | Scene rejected: no `children`. Cell Hash rejected: no ELK `children`. | Area partition and ancestor containment are the chart algorithm. | Retain squarified layout; propose a data-shaped exception. Probe: `examples/treemap/01-basic-treemap.mmd`. |
| `c4` | `Layout::C4`; `children=4`, `edges=3` | Scene rejected: node has no `ports`. Pre-Scene `Hash{id,children,edges,layoutOptions,metadata}` accepted as 4 / 3. | Final Scene is too late; the existing graph handoff is valid for supported levels. | Keep the existing explicit ELK path and loud unsupported-case behavior. Probe: `examples/c4/01-context-diagram.mmd`. |
| `info` | `Layout::Info`; scalar Scene | Scene rejected: no `children`. Message Hash rejected: no ELK `children`. | It renders informational text, not layout topology. | Retain direct rendering; propose a data-shaped exception. Probe: `examples/info/02-showinfo.mmd`. |
| `error` | `Layout::Error`; scalar Scene | Scene rejected: no `children`. Error-message Hash rejected: no ELK `children`. | It renders an error panel, not layout topology. | Retain direct rendering; propose a data-shaped exception. Probe: `examples/error/01-basic-error.mmd`. |

## Rollout queue

The measured queue is therefore:

1. Keep the three already-wired graph handoffs: Flowchart, State Diagram, and
   C4.
2. Wire the three accepted graph handoffs that elkrb can meaningfully own:
   Class Diagram, ER Diagram, and User Journey.
3. Normalize four `IR::Graph` handoffs before attempting layout: Git Graph,
   Mindmap, Requirement, and Architecture.
4. Retain specialized layout for Sequence and Sankey because generic graph
   placement cannot preserve their temporal and weighted-flow invariants.
5. Retain specialized layout for all six `IR::Prepositioned` and all six
   `IR::Data` transforms.

That accounts for all 24 registered transforms. There is no unclassified or
silently-falling-back type, and the adapter work is located before Scene
creation, where elkrb can own geometry without consuming renderer-ready data.
