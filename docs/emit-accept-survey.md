# Emit/accept survey: what each layout emits, what elkrb accepts

Persisted result of `TODO.foundation/14-elkrb-layout-integration.md` step 2.
Item 18 (typed IR) starts from this file.

Measured 2026-10-07 on `main` at `7d41197a`, Ruby 3.4.8, elkrb 1.0.2,
lutaml-model 0.8.95 (no lockfile is committed, so a later 0.8.x may
resolve), against the real gem. Nothing here is from memory. Counts and the rows
that name a probe are printed by a command in [Reproduce](#reproduce); the
other "elkrb does X" rows (container size, per-node and per-edge `metadata`,
an edge declared inside a container, the algorithm list) were checked by running
the call and reading the cited gem file, and are not in the pasted probes.

Population: every `spec/mermaid/*/*.mmd` case (1,997) that Sirena parses and
lays out. That is 1,255 cases, and it includes cases the oracle rejects, so
these are shape and acceptance counts, not a parity cohort.

## What "emit" and "accept" mean here

- **Emit.** What `Layout::<Type>#build_graph` returns today. All 24 registered
  layouts still define `build_graph` and none defines `#scene`
  (`lib/sirena/layout/base.rb`, `converted?`), so every layout returns a
  `Layout::Legacy` Hash.
- **Accept.** What `Elkrb.layout(hash)` does with that Hash as emitted, with no
  adapter in between. "Accepted" means it returned positions without raising.
  It does not mean the result is right; the Gaps column says where it is not.
- **Positions today** come from `Layout::Grid` (`engine.rb:164`, a three-column
  grid) for Hashes with a `children` key, and from the layout itself for the
  rest. elkrb is not called anywhere (`engine.rb:160-168`).

## What elkrb 1.0.2 does with a Hash

Each row is one probe in `probes.rb`.

| Fact | Evidence |
|---|---|
| Hash input works with symbol keys, which is what Sirena emits. Result is the mutated `Elkrb::Graph::Graph`. | `survey.rb`: 817 of 819 ELK-shaped cases returned (the other 2 are the sequence self-message cases below) |
| A Hash with no `children` key raises `NoMethodError` at `graph.rb:86`. | probe `no children key`; 436 of 436 cases of the 17 other layouts |
| Every node, containers included, needs a numeric `width` and `height`. 0 is fine; nil or absent raises `TypeError` at `base_algorithm.rb:121`. | probe `node without width` |
| Keys elkrb does not model are dropped, so Sirena's `metadata` does not come back. elkrb does keep a `properties` Hash on nodes and edges (`graph/node.rb:20`, `graph/edge.rb:72`), so metadata either moves there or the renderer keeps its own id-to-metadata index. | probes `unknown key survives into the result`, `properties key on a node and an edge survives` |
| A self-loop edge (`sources == targets`) raises `SystemStackError`, which is not a `StandardError`. | probe `self-loop edge` and `Sirena flowchart A --> A`; 2 sequence corpus cases (self-messages) |
| An edge to an id that is not a node is silently left unrouted. No error. | probe `edge to an unknown id` |
| The algorithm is chosen only by the call option `algorithm:`. `layoutOptions["elk.algorithm"]` is ignored, and so is a per-node request (c4 boundaries ask for `box`, `c4.rb:112`). | probes `layoutOptions elk.algorithm=box`, `boundary inside a container` |
| Layered reads only these spacing and padding call options: `layer_spacing`, `spacing_node_node` and `padding` (`layout/algorithms/layered/node_placer.rb:16-17`, `layout/algorithms/base_algorithm.rb:101`). Sirena's `elk.spacing.*` and `elk.layered.spacing.*` keys in `layoutOptions` change nothing. | probes `layoutOptions elk.spacing.nodeNode=200` vs `call option spacing_node_node: 200` |
| Layered has no direction support: `RIGHT` and `elk.direction` give the same top-to-bottom stack. er_diagram and user_journey always ask for `RIGHT`; 17 flowcharts, 1 state diagram and 5 class diagrams ask for `RIGHT` or `LEFT`. | probes `layoutOptions elk.direction=RIGHT`, `call option direction: RIGHT`; the requested values are counted in `survey.rb` output below |
| Child coordinates are relative to their container, the same convention as `Layout::Grid` (`grid.rb:13`). | probe `child coordinates`: `S` at (132, 12) and its child `C` at (24, 24) |
| Every edge with an endpoint inside a container gets no route (`sections` empty), whether the edge is declared at the root or inside the container. Edges with both ends at the top level are all routed. | probe `edges with an end in a container`; flowchart 74 of 74, c4 4 of 4 |
| A nested container is placed with the size it was emitted with (0x0 from Sirena), so its peers overlap it. Pre-sizing the containers to their first result removes the overlap. | probes `nested subgraphs ...`: 2 overlaps then 0; 13 of 48 nested flowchart cases overlap. The mechanism is shown on one case; the other 12 are counted, not individually isolated |
| `Elkrb.known_layout_algorithms` raises `NoMethodError` (`elkrb.rb:379` calls `AlgorithmRegistry.all`, which does not exist). Registered algorithms are read with `AlgorithmRegistry.available_algorithms`: box, disco, fixed, force, layered, libavoid, mrtree, radial, random, rectpacking, spore_compaction, spore_overlap, stress, topdownpacking, vertiflex. | probe `known_layout_algorithms` |

## Per-layout survey

Shape columns are facts for item 18's classification, not a classification:
**connectivity** is edges whose endpoints name nodes, **containment** is
children nested inside a parent, **positioned** is x/y present in the emitted
Hash. `Accepted` counts are corpus cases (Sirena lays out / elkrb returns).

### Emitted as an ELK graph (`children` + `edges` + `layoutOptions`)

All seven request `layered` with `INCLUDE_CHILDREN` hierarchy handling where
the layout sets it. None is positioned: `Layout::Grid` places them.

| Layout | Emits | Connectivity / containment | Accepted | Gap |
|---|---|---|---|---|
| flowchart (`flowchart.rb:35`) | nodes with `labels`, `metadata.shape`, `metadata.classes`; subgraphs are nodes with `children` and `metadata.cluster`, sized 0x0; edges with `sources`, `targets`, `labels`, `metadata.arrow_type` | yes / yes, nested to any depth | 241 / 241 | self-loop raises; 74 of 337 edges (every one with an end in a subgraph) unrouted; 13 of 48 nested cases overlap peers and 13 have a subgraph that does not enclose a child; `RIGHT` (17 cases) not honored; node and edge `metadata` dropped |
| class_diagram (`class_diagram.rb:45`) | class boxes with `metadata.attributes`, `.methods`, `.stereotype`; edges with `metadata.relationship_type`, markers, cardinalities, label `position` | yes / none in the corpus | 348 / 348, 206 of 206 edges routed | direction `LEFT` (4) and `RIGHT` (1) not honored; nested namespaces not exercised by any corpus case, so the container gaps above are unmeasured for this type |
| er_diagram (`er_diagram.rb:42`) | entity boxes with `metadata.attributes`; edges with cardinalities; a `class_defs` Hash that elkrb drops | yes / none in the corpus | 11 / 11, 17 of 17 routed | every case asks for `RIGHT` and gets a top-to-bottom stack |
| state_diagram (`state_diagram.rb:25`) | state boxes with `metadata.state_type`, `.shape_type`; edges with trigger and guard | yes / none in the corpus | 54 / 54, 59 of 59 routed | composite states are not emitted nested in any corpus case, so container gaps are unmeasured; 1 case asks for `RIGHT` |
| sequence (`sequence.rb:37`) | participants as `children`, messages as `edges` with `metadata.message_index` | yes / no | 107 / 109 | the 2 failures are self-messages (`SystemStackError`). The renderer ignores node coordinates and positions participants by index (`renderer/sequence.rb:95-107`), so elkrb output would not be read. elkrb has no message-order or lifeline notion |
| user_journey (`user_journey.rb:41`) | tasks as `children` with `metadata.score`, `.section_name`, `.actors`; edges `metadata.type` | yes (linear) / no | 28 / 28, 51 of 51 routed | every case asks for `RIGHT` and layered stacks vertically, but the renderer reads node x/y (`renderer/user_journey.rb:165-166`), so a journey would change shape |
| c4 (`c4.rb:40`) | elements and boundaries as nested `children`; edges with `metadata.rel_type` | yes / yes | 28 / 28 | 4 of 4 edges unrouted (an end inside a boundary); 1 case where a boundary does not enclose its child; boundary `box` packing request ignored (algorithm is per call) |

### Emitted in another shape

For these, elkrb as emitted raises `NoMethodError` at `graph.rb:86` on every
case, because there is no `children` key. That is the whole "accepts" result;
what an adapter would have to supply is in the Gap column. Only layout-side
facts are stated; whether elkrb's algorithm would match Mermaid's for the type
is not measured here.

| Layout | Emits | Connectivity / containment / positioned | Raises | Gap |
|---|---|---|---|---|
| architecture (`architecture.rb:24`) | `services`, `junctions`, `groups` as Hashes keyed by id with the model, x, y, width, height; services and junctions also carry `group_id`, and group nesting is the group model's `parent_id` (`architecture.rb:54-66`); `edges[]` with `from_x/from_y/to_x/to_y`, `from_side/to_side` and an `edge` model carrying `from_id`, `to_id` | yes (ids inside `edge`) / yes (`group_id`) / yes | 23 / 23 | nodes, containers and edges would all need mapping to `children`/`edges`; side hints have no measured elkrb equivalent (elkrb has ports; not probed) |
| block (`block.rb:28`) | `blocks` Hash keyed by id with `col`, `row`, `col_span`, `parent_id`, x, y, width, height; `connections[]` with `from`, `to` | yes / yes (`parent_id`) / yes | 6 / 6 | the grammar's `columns` fixes the grid, so nothing is left for a layout engine to decide; `connections` need mapping if edges are to be routed |
| error (`error.rb:24`) | `id`, `title`, `message`, `metadata.diagram_type` | no / no / no geometry | 4 / 4 | no nodes to hand over |
| gantt (`gantt.rb:21`) | `sections[].tasks[]` with `start_x`, `width`, dates; `timeline`, `excludes`, `today_marker` | no / sections hold tasks / x and width only | 26 / 26 | placement is date arithmetic, not graph layout |
| git_graph (`git_graph.rb:45`) | `commits[]` with `lane`, x, y, `parent_ids`; `branches[]`; `connections[]` with `from`, `to` | yes / no / yes | 141 / 141 | own lane and time-axis placement (`git_graph.rb:9`); connections could map to edges, lanes have no elkrb counterpart |
| info (`info.rb:24`) | `id`, `title`, `show_info`, `metadata.diagram_type` | no / no / no geometry | 15 / 15 | no nodes to hand over |
| kanban (`kanban.rb:42`) | `columns[]` and `cards[]` with `column_id`, x, y, width, height | no / yes (`column_id`) / yes | 38 / 38 | columns are fixed by the board; nothing to route |
| mindmap (`mindmap.rb:36`) | `nodes[]` with `parent_id`, `level`, x, y; `root`; `connections[]` with `from`, `to` | yes (tree) / yes (`parent_id`) / yes | 53 / 53 | tree placement is own code (`position_tree`, `position_children`: nodes in rows by depth); elkrb registers `mrtree` and `radial`, not probed here |
| packet (`packet.rb:40`) | `fields[]` with `bit_start`, `bit_end`, `row`, x, y | no / no / yes | 4 / 4 | bit-row grid, no graph |
| pie (`pie.rb:26`) | `slices[]` with `value`, `percentage`, `angle`; no x, y or size | no / no / no (angle only) | 50 / 50 | no boxes exist, so elkrb has nothing to place |
| quadrant (`quadrant.rb:28`) | `quadrants` bounds, `axes`, `points[]` with x, y, `svg_x`, `svg_y`, `radius` | no / yes (points sit in quadrants) / yes | 10 / 10 | fixed chart rectangle |
| radar (`radar.rb:36`) | `axes[]` with end points, `curves[].points[]` with x, y, `grid_circles[]` | no / no / yes (polar) | 14 / 14 | polar geometry, no graph |
| requirement (`requirement.rb:31`) | `requirements` and `elements` Hashes with x, y, width, height; `relationships[]` with `source`, `target` | yes / no / yes | 24 / 24 | boxes and relationships map directly to children and edges; own placement today |
| sankey (`sankey.rb:28`) | `nodes[]` with `layer`, x, y; `flows[]` with `source`, `target`, `value`, `width` | yes / no / yes | 1 / 1 | own layering and flow-width computation; elkrb has no sankey algorithm |
| timeline (`timeline.rb:21`) | `sections[].events[]`, `events[]` with `x_position`, `timeline` span | no / sections hold events / x only | 16 / 16 | date-to-x placement, no graph |
| treemap (`treemap.rb:19`) | `cells[]` nested through `children` with x, y, width, height, `depth` | no / yes (`treemap.rb:72-85`) / yes | 9 / 9 | space-filling by value; elkrb registers `rectpacking` and `topdownpacking`, not probed here |
| xychart (`xy_chart.rb:33`) | plot rectangle, `x_axis`, `y_axis`, `datasets[].points[]` with x, y | no / no / yes | 2 / 2 | plot geometry, no graph |

## What this means for card 14 step 1 (flowchart first)

These are the elkrb-side gaps the first integration PR meets, in the order it
meets them. Each is a decision for the owner or the elkrb maintainer, not
something this survey rules on.

1. **Edges to nodes inside subgraphs get no route.** Flowchart subgraphs are
   common in the corpus (48 of 241 laid-out cases nest), and every edge
   touching one is unrouted. The card's "invariants: edges connecting the right
   nodes" cannot pass on those cases without an elkrb fix or an edge router in
   Sirena.
2. **Container size is not known when peers are placed.** 13 of 48 nested cases
   overlap peers. Sirena could pre-size containers, but that needs a size
   before layout, which is what layout produces.
3. **Self-loops crash.** `A --> A` is valid Mermaid. The Engine already turns
   `SystemStackError` into a `PipelineError` (`engine.rb:113`, rescue of
   `EXHAUSTION_ERRORS`), so it fails loudly rather than silently, but the
   render fails where the fallback grid renders it today.
4. **`layoutOptions` is not the configuration channel.** The algorithm,
   spacing and direction Sirena emits are ignored; the same settings must be
   passed as call options under different names (`spacing_node_node`,
   `layer_spacing`, `algorithm`), and direction has no equivalent at all.
   Left-to-right flowcharts (17 laid-out cases) cannot match Mermaid without
   it.
5. **`metadata` is dropped.** Shape, class, arrow type and cluster flags must be
   moved into `properties` or re-attached by id after layout.

For types outside the ELK-shaped seven, the card's "Done when" already allows a
recorded exception for types elkrb cannot meaningfully own. This survey shows
which shapes would need an adapter and which have no boxes to place; it does
not decide the exceptions.

## Reproduce

The two scripts exist only as the code blocks below. From the repository root,
this writes each block to a temporary directory and runs it. `survey.rb` takes
about ten seconds of CPU; `probes.rb` under one.

```sh
dir=$(mktemp -d)
for name in survey probes; do
  awk -v head="### $name.rb" '
    $0 == head { found = 1; next }
    found && /^```ruby$/ { inside = 1; next }
    inside && /^```$/ { exit }
    inside' docs/emit-accept-survey.md > "$dir/$name.rb"
done
bundle exec ruby -Ilib "$dir/survey.rb"
bundle exec ruby -Ilib "$dir/probes.rb"
```

The scripts read `spec/mermaid/` by relative path, so run them from the
repository root.

### survey.rb

```ruby
require "sirena"
require "elkrb"
require "timeout"

rows = Hash.new { |h, k| h[k] = Hash.new(0) }

Dir.glob("spec/mermaid/*/*.mmd").sort.each do |path|
  body = Sirena::Source.split(File.read(path))[:body]
  type = Sirena::Notation::Mermaid.detect_type(body)
  handlers = Sirena::DiagramRegistry.get(type)
  payload = Timeout.timeout(10) do
    handlers[:transform].new.call(handlers[:parser].new.parse(body)).payload
  end
rescue StandardError, Timeout::Error
  next # the case never reaches layout in Sirena; nothing to feed elkrb
else
  row = rows[type]
  row[:layouts] += 1
  options = payload[:layoutOptions] || {}
  row[:"requests #{options['elk.direction']}"] += 1 if options.key?("elk.direction")
  depth = {}
  nest = ->(node, d) { (node[:children] || []).each { |c| depth[c[:id]] = d; nest.(c, d + 1) } }
  nest.(payload, 0)
  row[:"cases that nest"] += 1 if depth.values.any?(&:positive?)
  begin
    graph = Elkrb.layout(Marshal.load(Marshal.dump(payload)))
  rescue SystemStackError
    row[:"raises SystemStackError"] += 1
    next
  rescue StandardError => e
    where = e.backtrace_locations.first
    row[:"raises #{e.class} at #{File.basename(where.path)}:#{where.lineno}"] += 1
    next
  end
  row[:accepted] += 1
  graph.edges.each do |edge|
    inside = (edge.sources + edge.targets).any? { |id| depth.fetch(id, 0).positive? }
    routed = edge.sections.to_a.any?
    row[:"edges routed, both ends top-level"] += 1 if routed && !inside
    row[:"edges unrouted, an end inside a container"] += 1 if !routed && inside
    row[:"edges unrouted, both ends top-level"] += 1 if !routed && !inside
  end
  every = ->(node, acc = []) { node.children.to_a.each { |c| acc << c; every.(c, acc) }; acc }
  levels = [graph.children.to_a] + every.(graph).map { |n| n.children.to_a }
  overlap = levels.any? do |peers|
    peers.combination(2).any? do |a, b|
      ([a.x + a.width, b.x + b.width].min - [a.x, b.x].max) > 0.5 &&
        ([a.y + a.height, b.y + b.height].min - [a.y, b.y].max) > 0.5
    end
  end
  row[:"cases with peer overlap"] += 1 if overlap
  leaks = every.(graph).any? do |box|
    box.children.to_a.any? do |c|
      c.x < 0 || c.y < 0 || c.x + c.width > box.width + 0.5 || c.y + c.height > box.height + 0.5
    end
  end
  row[:"cases where a container does not enclose a child"] += 1 if leaks
end

rows.sort.each { |type, row| puts "#{type}: #{row.sort_by { |k, _| k.to_s }.to_h}" }
```

Output on the commit above:

```
architecture: {layouts: 23, "raises NoMethodError at graph.rb:86": 23}
block: {layouts: 6, "raises NoMethodError at graph.rb:86": 6}
c4: {accepted: 28, "cases that nest": 5, "cases where a container does not enclose a child": 1, "edges unrouted, an end inside a container": 4, layouts: 28, "requests DOWN": 28}
class_diagram: {accepted: 348, "edges routed, both ends top-level": 206, layouts: 348, "requests DOWN": 343, "requests LEFT": 4, "requests RIGHT": 1}
er_diagram: {accepted: 11, "edges routed, both ends top-level": 17, layouts: 11, "requests RIGHT": 11}
error: {layouts: 4, "raises NoMethodError at graph.rb:86": 4}
flowchart: {accepted: 241, "cases that nest": 48, "cases where a container does not enclose a child": 13, "cases with peer overlap": 13, "edges routed, both ends top-level": 263, "edges unrouted, an end inside a container": 74, layouts: 241, "requests DOWN": 224, "requests RIGHT": 17}
gantt: {layouts: 26, "raises NoMethodError at graph.rb:86": 26}
git_graph: {layouts: 141, "raises NoMethodError at graph.rb:86": 141}
info: {layouts: 15, "raises NoMethodError at graph.rb:86": 15}
kanban: {layouts: 38, "raises NoMethodError at graph.rb:86": 38}
mindmap: {layouts: 53, "raises NoMethodError at graph.rb:86": 53}
packet: {layouts: 4, "raises NoMethodError at graph.rb:86": 4}
pie: {layouts: 50, "raises NoMethodError at graph.rb:86": 50}
quadrant: {layouts: 10, "raises NoMethodError at graph.rb:86": 10}
radar: {layouts: 14, "raises NoMethodError at graph.rb:86": 14}
requirement: {layouts: 24, "raises NoMethodError at graph.rb:86": 24}
sankey: {layouts: 1, "raises NoMethodError at graph.rb:86": 1}
sequence: {accepted: 107, "edges routed, both ends top-level": 202, layouts: 109, "raises SystemStackError": 2, "requests DOWN": 109}
state_diagram: {accepted: 54, "edges routed, both ends top-level": 59, layouts: 54, "requests DOWN": 53, "requests RIGHT": 1}
timeline: {layouts: 16, "raises NoMethodError at graph.rb:86": 16}
treemap: {layouts: 9, "raises NoMethodError at graph.rb:86": 9}
user_journey: {accepted: 28, "edges routed, both ends top-level": 51, layouts: 28, "requests RIGHT": 28}
xychart: {layouts: 2, "raises NoMethodError at graph.rb:86": 2}
```

### probes.rb

```ruby
require "sirena"
require "elkrb"

def node(id) = { id: id, width: 40, height: 30 }

def try(label)
  puts "#{label}: #{yield}"
rescue SystemStackError
  puts "#{label}: SystemStackError"
rescue StandardError => e
  where = e.backtrace_locations.first
  puts "#{label}: #{e.class} at #{File.basename(where.path)}:#{where.lineno}"
end

def laid(graph, options = {}) = Elkrb.layout(Marshal.load(Marshal.dump(graph)), options)
def xy(graph) = graph.children.map { |c| [c.id, c.x.to_i, c.y.to_i] }

nodes = %w[A B C].map { |id| node(id) }
edge = ->(id, from, to) { { id: id, sources: [from], targets: [to] } }
chain = { id: "r", children: nodes, edges: [edge.("e1", "A", "B"), edge.("e2", "B", "C")] }

try("no children key") { laid({ id: "r", slices: [] }).class }
try("node without width") { laid({ id: "r", children: [{ id: "A" }] }).class }
try("self-loop edge") { laid({ id: "r", children: [node("A")], edges: [edge.("s", "A", "A")] }).class }
try("unknown key survives into the result") { laid(chain.merge(metadata: { a: 1 })).to_hash.key?("metadata") }
try("properties key on a node and an edge survives") do
  g = laid({ id: "r", children: [{ id: "A", width: 40, height: 30, properties: { shape: "box" } }, node("B")],
             edges: [{ id: "e", sources: ["A"], targets: ["B"], properties: { arrow: "open" } }] })
  [g.children[0].to_hash["properties"], g.edges[0].to_hash["properties"]]
end
try("edge to an unknown id: sections") { laid({ id: "r", children: nodes, edges: [edge.("d", "A", "ZZ")] }).edges[0].sections.to_a.size }

fan = { id: "r", children: nodes, edges: [edge.("e", "A", "B"), edge.("f", "A", "C")] }
try("default placement") { xy(laid(fan)) }
try("layoutOptions elk.spacing.nodeNode=200") { xy(laid(fan.merge(layoutOptions: { "elk.spacing.nodeNode" => 200 }))) }
try("call option spacing_node_node: 200") { xy(laid(fan, { spacing_node_node: 200 })) }
try("call option layer_spacing: 200") { xy(laid(fan, { layer_spacing: 200 })) }
try("layoutOptions elk.direction=RIGHT") { xy(laid(fan.merge(layoutOptions: { "elk.direction" => "RIGHT" }))) }
try("call option direction: RIGHT") { xy(laid(fan, { direction: "RIGHT" })) }
try("layoutOptions elk.algorithm=box") { xy(laid(fan.merge(layoutOptions: { "elk.algorithm" => "box" }))) }
try("call option algorithm: box") { xy(laid(fan, { algorithm: "box" })) }

boundary = lambda do |options|
  { id: "r", edges: [],
    children: [{ id: "S", width: 0, height: 0, layoutOptions: options,
                 children: %w[A B C D E].map { |id| node(id) }, edges: [edge.("e", "A", "B")] }] }
end
try("boundary inside a container, requests box") { laid(boundary.({ "elk.algorithm" => "box" })).children[0].children.map { |c| [c.id, c.x.to_i, c.y.to_i] } }
try("boundary inside a container, requests nothing") { laid(boundary.({})).children[0].children.map { |c| [c.id, c.x.to_i, c.y.to_i] } }

nested = { id: "r", children: [node("A"), { id: "S", width: 0, height: 0, children: [node("C"), node("D")] }],
           edges: [edge.("x", "A", "C"), edge.("in", "C", "D")] }
try("child coordinates: container S and its children C, D") do
  box = laid({ id: "r", edges: [], children: [node("A"), node("B"), { id: "S", width: 0, height: 0, children: [node("C"), node("D")] }] })
  s = box.children.last
  "S at (#{s.x.to_i}, #{s.y.to_i}), C at (#{s.children[0].x.to_i}, #{s.children[0].y.to_i}), D at (#{s.children[1].x.to_i}, #{s.children[1].y.to_i})"
end
try("edges with an end in a container: sections") { laid(nested).edges.map { |e| [e.id, e.sections.to_a.size] } }
flowchart = Sirena::DiagramRegistry.get(:flowchart)
graph_for = lambda do |source|
  flowchart[:transform].new.call(flowchart[:parser].new.parse(source)).payload
end
try("Sirena flowchart `A --> A`") { laid(graph_for.("flowchart TD\n A --> A\n")).class }

overlaps = lambda do |graph|
  levels = [graph.children]
  walk = ->(n) { n.children.to_a.each { |c| levels << c.children.to_a; walk.(c) } }
  walk.(graph)
  levels.sum do |peers|
    peers.combination(2).count do |a, b|
      [a.x + a.width, b.x + b.width].min - [a.x, b.x].max > 0.5 &&
        [a.y + a.height, b.y + b.height].min - [a.y, b.y].max > 0.5
    end
  end
end
subgraphs = graph_for.(File.read("spec/mermaid/flowchart/023_parser_should_handle_nested_subgraphs_22.mmd"))
first = laid(subgraphs)
try("nested subgraphs, containers emitted 0x0: peer overlaps") { overlaps.(first) }
sizes = {}
collect = ->(n) { n.children.to_a.each { |c| sizes[c.id] = [c.width, c.height]; collect.(c) } }
collect.(first)
presize = lambda do |n|
  (n[:children] || []).each do |c|
    c[:width], c[:height] = sizes[c[:id]] if c[:children]
    presize.(c)
  end
end
presize.(subgraphs)
try("same graph, containers pre-sized to the first result: peer overlaps") { overlaps.(laid(subgraphs)) }

try("known_layout_algorithms") { Elkrb.known_layout_algorithms.size }
```

Output:

```
no children key: NoMethodError at graph.rb:86
node without width: TypeError at base_algorithm.rb:121
self-loop edge: SystemStackError
unknown key survives into the result: false
properties key on a node and an edge survives: [{shape: "box"}, {arrow: "open"}]
edge to an unknown id: sections: 0
default placement: [["A", 12, 12], ["B", 12, 102], ["C", 72, 102]]
layoutOptions elk.spacing.nodeNode=200: [["A", 12, 12], ["B", 12, 102], ["C", 72, 102]]
call option spacing_node_node: 200: [["A", 12, 12], ["B", 12, 102], ["C", 252, 102]]
call option layer_spacing: 200: [["A", 12, 12], ["B", 12, 242], ["C", 72, 242]]
layoutOptions elk.direction=RIGHT: [["A", 12, 12], ["B", 12, 102], ["C", 72, 102]]
call option direction: RIGHT: [["A", 12, 12], ["B", 12, 102], ["C", 72, 102]]
layoutOptions elk.algorithm=box: [["A", 12, 12], ["B", 12, 102], ["C", 72, 102]]
call option algorithm: box: [["A", 12, 12], ["B", 72, 12], ["C", 132, 12]]
boundary inside a container, requests box: [["A", 24, 24], ["B", 24, 114], ["C", 84, 24], ["D", 144, 24], ["E", 204, 24]]
boundary inside a container, requests nothing: [["A", 24, 24], ["B", 24, 114], ["C", 84, 24], ["D", 144, 24], ["E", 204, 24]]
child coordinates: container S and its children C, D: S at (132, 12), C at (24, 24), D at (84, 24)
edges with an end in a container: sections: [["x", 0], ["in", 0]]
Sirena flowchart `A --> A`: SystemStackError
nested subgraphs, containers emitted 0x0: peer overlaps: 2
same graph, containers pre-sized to the first result: peer overlaps: 0
known_layout_algorithms: NoMethodError at elkrb.rb:379
```
