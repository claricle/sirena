# 04 — A typed Scene between layout and renderer

**Goal:** no bare Hash crosses a layer boundary. Every renderer's input
is a class you can open and read.
**Size:** ~21 PRs, one per diagram type, plus one small PR for the base
class. Each type PR is small — Scene definition, layout rewrite,
renderer rewrite.
**Prerequisite:** item 03.

This is the item that makes every later fix cheaper. It is also the
longest. Do it one type at a time and it is mechanical.

Read `WORKED-EXAMPLE.md` before starting. It shows pie converted in
full; every type follows that shape.

## Why

After item 03, `Layout::X` still emits a plain Hash and `Renderer::X`
digs through it: `node.dig(:metadata, :shape) || 'rect'`
(`renderer/flowchart.rb:62`). There are **24 private hash shapes and no
documentation of any of them**. To change what a layout emits, you have
to read the renderer to find out what it expects.

## The design

The result class lives **in the same file** as the layout that produces
it, so one file answers both "how is this type laid out" and "what does
that layout look like":

```ruby
# lib/sirena/layout/pie.rb
module Sirena
  module Layout
    class Pie
      class Scene < Layout::Scene        # width, height inherited
        attribute :sectors, Sector, collection: true
        attribute :title, :string
      end

      def call(diagram, theme:) = Scene.new(...)
    end
  end
end
```

`Layout::Scene` is the shared base and carries only `width` and
`height` — enough for `Renderer::Base` to own document creation, which
item 05 uses to delete nine copies of it.

**Types with no geometry get no Layout class at all.** Two of today's
`Transform` classes only copy fields into a hash —
`Transform::InfoTransform` and `Transform::ErrorTransform`, 38 lines
each. `Transform::PieTransform` (61 lines) is arguably a third: it
copies, but it also pulls each slice's angle and percentage off the
model. Delete those files; the renderer takes the `Diagram` model
directly. The engine handles both in one line:

```ruby
scene = Layout.for(type)&.call(model, theme: theme) || model
```

**Expect two or three deletions, not ten.** Every other `Transform`
computes geometry — measured 2026-08-25 by scanning all 24 for
coordinate keys and arithmetic. Check each one before you delete it;
`timeline` reads like a pass-through and is not.

**Rule for the future: if a layout would only copy fields, do not write
one.**

## Two kinds of Scene

**Graph types must use an ELK-shaped Scene.** Geometry parity is the
agreed bar (`00-overview.md`), which means elkrb computes positions for
graph types in item 08. If their Scenes mirror what ELK already emits,
that integration is a swap; if you invent a different shape now, it is a
redesign of every one of them later.

**The swap is not free: establish elkrb's coordinate frame first.** ELK
nests children in their parent's frame by default, and our Scene holds
final canvas coordinates. Those are not the same numbers. Before wiring
elkrb in, run one nested graph through it and record which frame the
child `x`/`y` come back in — measured, not assumed. If they are
parent-relative, the adapter flattens them to canvas coordinates on the
way into the Scene, and that flattening is part of item 08, not
something a renderer does later.

**Node `x`/`y` is not the whole surface.** The Scene below also imports
label positions and edge `sections` — `start_point`, `end_point` and
`bend_points`. Each of those carries coordinates and each may sit in a
different frame from the node it belongs to; ELK routes an edge in the
frame of the container that owns it, which is not always the frame of
its endpoints. Measure all three — node, label, edge section — and
flatten all three. A probe that only checks node positions will look
clean and leave every edge in the wrong place.

Measured 2026-08-27 against elkrb at `v2`: a two-level graph came back
with sibling boxes that overlap, so the frame could not be settled from
one probe. Treat it as unknown until item 08 pins it.

For `flowchart`, `class_diagram`, `state_diagram`, `er_diagram`, `c4`,
`requirement`, `architecture`, `block` and `mindmap`, shape the Scene
like ELK's own output:

```ruby
class Node < Lutaml::Model::Serializable
  attribute :id, :string
  attribute :x, :float
  attribute :y, :float
  attribute :width, :float
  attribute :height, :float
  attribute :labels, Label, collection: true
  attribute :shape, :string            # type-specific extras are fine
  attribute :children, Node, collection: true   # nesting, where the type has it
end

class Edge < Lutaml::Model::Serializable
  attribute :id, :string
  attribute :source, :string
  attribute :target, :string
  attribute :sections, Section, collection: true   # start/end/bend points
  attribute :labels, Label, collection: true
end
```

`Section` holds `start_point`, `end_point` and `bend_points` — that is
ELK's edge routing structure, and it is also what a renderer needs to
draw a polyline. Add type-specific attributes freely (`shape`,
`arrow_type`, `cardinality`); do not rename or restructure the geometry
fields.

**Everything else gets a Scene shaped by its own diagram.** A pie has
sectors, a gantt has bars on a date axis, an xy chart has axes and
series. Do not force those into nodes and edges — see the Do-not list.

## Scene coordinates are final

Scene holds the coordinates the renderer writes out. Not a size and an
origin the renderer then applies. One coordinate space, and the layout
owns it.

Three renderers frame their own canvas by hand today. `git_graph.rb:48`,
`mindmap.rb:48` and `kanban.rb:45` each set `padding = 40`, add
`padding * 2` to both document dimensions, then carry `@offset_x` and
`@offset_y` into every draw call below. None of them uses an SVG
`translate`.

That framing belongs in the layout. `Scene#width` and `#height` already
include the padding, every point is already shifted, and the renderer
adds nothing.

`packet` does the same thing outside its document builder.
`packet.rb:33` computes `@title_offset` during `render`, and
`packet.rb:187` adds it to every field's `y`. Grepping the builders
alone will not find it. Move it upstream with the rest.

The alternative — Scene carries an origin, the renderer applies it —
fails in two directions. Miss one draw site and connected geometry pulls
apart. Apply it twice and content slides into its own padding.
`git_graph` applies `@offset_x`/`@offset_y` at 16 separate sites, so
both are reachable.

Measured 2026-08-27: `grep -rn "@[a-z_]*offset\|padding = "
lib/sirena/renderer/` returns 44 lines across those four files.

## Scene classes are lutaml, with one restriction

Scenes use `Lutaml::Model::Serializable` and `attribute` declarations,
matching the Diagram layer.

**Never add an `xml do` block to a Scene class.** Scenes are internal
geometry; they are never read from or written to XML. That block is
exactly what went wrong in the Svg layer — three declarations of every
attribute, two of them dead (item 02).

## Steps

1. Add `lib/sirena/layout/scene.rb`: `Layout::Scene` with `width` and
   `height`. One small PR on its own.
2. Convert types in this order — geometry-heavy first, because they
   prove the design while you still have room to change it; trivial ones
   last, because most of them get deleted rather than converted:

   `flowchart`, `class_diagram`, `sequence`, `state_diagram`,
   `er_diagram`, `mindmap`, `xy_chart`, `git_graph`, `gantt`,
   `timeline`, `kanban`, `quadrant`, `radar`, `sankey`, `block`,
   `architecture`, `c4`, `requirement`, `packet`, `treemap`,
   `user_journey`

3. The layout signature is `call(diagram, theme:)` throughout this plan
   — **layouts need the theme.** Every layout today hardcodes
   `DEFAULT_FONT_SIZE = 14` while renderers draw at
   `theme.typography.font_size_normal`. The built-in `high_contrast`
   theme sets 16.0, so today its text overflows every box it is sized
   into. Sizing is a layout concern and it depends on font metrics; see
   `LAYERS.md`.
4. For each type, one PR:
   - define the Scene from what the renderer actually reads — that *is*
     the contract, already written down, just in the wrong place
   - move every coordinate and angle calculation out of the renderer and
     into the layout
   - replace the hardcoded font size with the theme's
   - rewrite the renderer to read named attributes
   - the layout returns a new Scene and never mutates the diagram
   - `rake corpus[<type>]` must show the same pass count
5. For each pass-through type, delete the layout class and register the
   type without one.
6. Extend `spec/contract_spec.rb`: where a layout exists it returns a
   `Layout::Scene`; where it does not, the renderer accepts the
   `Diagram` model.

## Done when

- [ ] no renderer indexes a Hash (`[:symbol]`, `.dig`) on its input
- [ ] no renderer performs arithmetic on coordinates or angles
- [ ] no renderer holds positional state between calls;
      `grep -rn "@[a-z_]*offset\|padding = " lib/sirena/renderer/`
      returns nothing. `@[a-z_]*offset` is the half that catches
      `packet`'s `@title_offset`; a plain `@offset_` grep misses it
- [ ] no Scene class declares an `origin`, and no renderer emits an SVG
      `translate`. The grep above passes if you merely delete the
      offsets or move them to a `translate`, and neither puts the
      displacement in the Scene
- [ ] `git_graph`, `mindmap`, `kanban` and `packet` each have a spec
      asserting **canvas** coordinates, framing already included, on
      *every* coordinate-bearing element that type emits — not one. One
      assertion passes while edges, labels or bounds stay unshifted.
      Each type exposes its own thing, so name it per type: `git_graph`
      commits **and** connections, `kanban` columns **and** cards,
      `mindmap` nodes **and** the links between them, `packet` fields
      **and** grid lines **and** bit markers
- [ ] `packet`'s case has a title, or `@title_offset` is zero and the
      spec proves nothing
- [ ] each of those four also asserts the document's own width and
      height include the framing
- [ ] no layout hardcodes a font size; `grep -rn "FONT_SIZE = " lib/sirena/layout/`
      returns nothing
- [ ] rendering one diagram under `default` and `high_contrast` gives
      boxes sized to their own theme's text
- [ ] every pass-through layout class is deleted (expect two or three:
      `info`, `error`, and possibly `pie`)
- [ ] `rake corpus:check` shows no regression across the whole item

## Do not

- **Do not design one scene format for all 24 types.** Graph types share
  the ELK shape above because elkrb will populate it. Non-graph types get
  a Scene shaped by their own diagram. Forcing a pie into nodes and edges
  recreates the untyped Hash with extra steps.
- **Do not build the cross-notation IR here.** These Scenes are
  geometry and they are Mermaid-shaped on purpose. The IR is a different
  boundary and a different item: `TODO.foundation/18`, which the owner
  ruled on 2026-08-13 **is** built in this foundation. It is not
  deferred and item 04 does not replace it — it starts after item 10,
  after item 14's `docs/emit-accept-survey.md`, and after item 16's
  PlantUML class spike. See `00-overview.md`, "The IR, and what the
  owner ruled".
- Do not convert two types in one PR.
- Do not fix rendering bugs you notice. Write them down — they are item
  08's work, and they belong in a PR whose corpus delta is expected.

## Files

`lib/sirena/layout/scene.rb` (new), `lib/sirena/layout/*.rb`,
`lib/sirena/renderer/*.rb`, `spec/contract_spec.rb`.
