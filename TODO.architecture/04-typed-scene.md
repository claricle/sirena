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
    class Pie < Layout::Base           # gives #call, and theme/today readers
      class Scene < Layout::Scene        # width, height inherited
        attribute :sectors, Sector, collection: true
        attribute :title, :string
      end

      def scene(diagram) = Scene.new(...)   # theme, today are readers
    end
  end
end
```

`Layout::Scene` is the shared base and carries only `width` and
`height` — enough for `Renderer::Base` to own document creation, which
item 05 uses to delete nine copies of it.

**Every type gets a Layout and a Scene. There is no pass-through.**

An earlier draft said types with no geometry get no Layout class, and
the renderer takes the `Diagram` model directly. That does not survive
contact with the rest of the plan:

- `renderer/info.rb:71` reads `graph[:show_info]`, and the error
  renderer reads `message`. A Scene carrying only `width` and `height`
  loses both.
- Both renderers compute their own box, icon and text coordinates,
  which item 04's own rule forbids.
- Item 05 collapses nine document builders into **one** method that
  reads `width` and `height` off the Scene. Hand it a bare `Diagram`
  and it has nothing to read.

So `info` and `error` get a real Scene — their content *and* their
dimensions — and a layout of about twenty lines each to compute it.
That is cheaper than two exceptions threaded through the builder, the
lookup, the pipeline and the contract spec.

The pipeline loses its conditional with them:

```ruby
scene = Layout.for(type).call(model, theme: theme, today: today)
```

No `&.`, no `|| model`, no optional layout. `Layout.for` always returns
a layout, and a missing one is an error like any other.

**`Transform::InfoTransform` and `Transform::ErrorTransform` are still
the two smallest**, 38 lines each — measured 2026-08-25 by scanning all
24 for coordinate keys and arithmetic. They become the two smallest
layouts, not deletions. `timeline` reads like a pass-through and is
not.

**Rule for the future: every type gets a layout. A layout that would
only copy fields still gets written — it is the thing that owns the
canvas size and the coordinates the renderer must not compute.**

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
its endpoints. ELK allows more than one edge-coordinate mode, `ROOT`
among them, so a top-level edge may already be in canvas coordinates
while a nested one is not. That is what makes it worth measuring rather
than assuming in either direction. Measure all three — node, label,
edge section — and flatten whichever are not already canvas. A probe
that only checks node positions will look clean whether or not the
nested edges needed translating, which is the point: it cannot tell you
either way.

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
   prove the design while you still have room to change it; the small
   ones last, because they are the least informative:

   `flowchart`, `class_diagram`, `sequence`, `state_diagram`,
   `er_diagram`, `mindmap`, `xy_chart`, `git_graph`, `gantt`,
   `timeline`, `kanban`, `quadrant`, `radar`, `sankey`, `block`,
   `architecture`, `c4`, `requirement`, `packet`, `treemap`,
   `user_journey`, `pie`, `info`, `error`

   **All 24, not 21.** An earlier draft ended the list at
   `user_journey` because `pie`, `info` and `error` were going to lose
   their layouts. They are not — see above — and leaving them out here
   would strand three `to_graph` implementations at the point item 06
   deletes the fallback.

3. **`Layout::Base` owns the signature; subclasses do not repeat it.**
   `Base#call(diagram, theme:, today:)` stores both and calls the
   subclass's `#scene(diagram)`; `theme` and `today` are private
   readers. Layouts need the theme, and `gantt` needs the reference
   date the engine already carries (`engine.rb:93`).

   Do **not** give every subclass `call(diagram, theme:, today:)` and
   let it ignore what it does not use. `Lint/UnusedMethodArgument` is
   enabled with `AllowUnusedKeywordArguments` at its default, so a pie
   layout that never reads `today` is an offence. The template method
   gives one signature *and* a lint-clean subclass.

   `Layout::Base#today` must be **`@today ||= Date.today`**, character
   for character. Not `@today || Date.today`. Two reasons, and both
   bite:

   - Without `||=` it does not memoize, so a long gantt render can read
     the clock twice and cross midnight between reads.
   - `spec/sirena/determinism_spec.rb:209` allowlists the ambient clock
     read by matching that **exact line**, deliberately, so a second
     ambient read cannot hide in the same file. Any other spelling
     fails it.

   A `nil` reaching the layout means "use the real date" — it does not
   mean nil. That is the semantics `engine.rb:185` has today
   (`transform.today = today if today && transform.respond_to?(:today=)`)
   and step 6 keeps it. Every layout today hardcodes
   `DEFAULT_FONT_SIZE = 14` while renderers draw at
   `theme.typography.font_size_normal`. The built-in `high_contrast`
   theme sets 16.0, so today its text overflows every box it is sized
   into. Sizing is a layout concern and it depends on font metrics; see
   `LAYERS.md`.
4. **Before converting the first type, give `Layout::Base` a transition
   path.** This item converts one type per PR and requires
   `rake corpus[<type>]` unchanged after each. That is impossible as
   stated: an unconverted layout exposes `to_graph`, a converted one
   exposes `scene`, and the engine does not switch to
   `Layout.for(type).call(...)` until item 06. Switch early and every
   unconverted type breaks; switch late and every converted type does.

   The fix is one temporary **branch**, deleted by item 06 —
   `Layout::Base#call` itself stays: it returns `scene(diagram)` when
   the subclass defines `scene`, and falls back to `to_graph(diagram)`
   when it does not. The engine calls `call` from the first conversion PR onward.
   Every PR in between has one path that works for both kinds, and
   `corpus[<type>]` stays green throughout.

   The registry-era engine instantiates the registered class
   (`engine.rb:180`), so a `nil` layout would be `nil.new`. That cannot
   happen here, because every type keeps a layout through the whole
   rollout — the pass-through path was withdrawn above for exactly this
   family of reasons.

   **Grid must run on the legacy branch only, and `Base#call` has to
   say which branch it took.** `Engine#apply_fallback_layout` picks its
   generic path with `elsif graph.respond_to?(:nodes)`
   (`engine.rb:223`). A converted Sankey Scene responds to `nodes`, so
   Grid would catch it and overwrite the coordinates the layout just
   computed. Non-mutation does not save you — it hands back a correctly
   typed Scene in the wrong positions, and the corpus pass count cannot
   see wrong coordinates.

   Returning the output alone is not enough for the engine to decide.
   Give `Base#call` an explicit contract — the simplest is a second
   return value, or a `Layout::Legacy` wrapper around the `to_graph`
   result — and have the engine run Grid on that signal, never on
   `respond_to?`.

   **Keep a test-only legacy layout.** By the end of this item every
   production layout defines `scene`, so the legacy branch becomes
   untestable with real classes and its gate rots. Define a fixture
   layout in `spec/support/` that implements `to_graph` and nothing
   else, and keep it until item 06 deletes the branch.

   Item 06 deletes the fallback once no `to_graph` remains. Add it to
   that item's `Done when`, or it survives forever.

5. For each type, one PR:
   - define the Scene from what the renderer actually reads — that *is*
     the contract, already written down, just in the wrong place
   - move every coordinate and angle calculation out of the renderer and
     into the layout
   - replace the hardcoded font size with the theme's
   - rewrite the renderer to read named attributes
   - the layout returns a new Scene and never mutates the diagram
   - `rake corpus[<type>]` must show the same pass count
6. Extend `spec/contract_spec.rb`: every registered type has a layout,
   and that layout returns a `Layout::Scene` with non-nil `width` and
   `height`. There is no "no layout" case to special-case.

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
      Each type exposes its own thing, and **text counts** — a label
      the renderer still positions itself is exactly the leak these
      assertions exist to catch:
      `git_graph` commits, connections, **commit/tag/branch labels**;
      `kanban` columns, cards, **headers, badges, card metadata, and
      the card's own text** (`renderer/kanban.rb:218` computes its `y`);
      `mindmap` nodes, links, **node text**;
      `packet` fields, grid lines, bit markers, **title/field/range
      labels**.
      The rule underneath the list: if the renderer computes a position
      for it, it belongs in the Scene and it gets an assertion
- [ ] `packet`'s case has a title, or `@title_offset` is zero and the
      spec proves nothing
- [ ] each of those four also asserts the document's own width and
      height include the framing
- [ ] and asserts its `viewBox`. `Svg::Document` computes `view_box`
      only in `initialize` (`svg/document.rb:66`), so assigning width
      and height afterwards leaves it stale or nil. All four renderers
      set it by hand today — width and height alone do not prove the
      viewport is right
- [ ] `Layout::Base` defines `#call` and **no subclass overrides it**;
      `grep -rn "def call" lib/sirena/layout/` returns exactly one hit
- [ ] every layout subclass defines `#scene(diagram)` and declares no
      keyword arguments of its own
- [ ] `theme` and `today` are private readers on `Layout::Base`; a
      subclass reading them works, an outside caller gets
      `NoMethodError`
- [ ] `Layout::Base#today` is literally `@today ||= Date.today`, and
      `determinism_spec.rb` still passes
- [ ] calling with `today: nil` gives the same output as calling with
      `today: Date.today` — a spec, not an assumption
- [ ] a transition spec drives **one converted and one unconverted**
      layout through `Base#call` in the same example, using the
      `spec/support/` legacy fixture so it still works after the last
      real conversion. Write it at the first conversion
- [ ] the same spec goes through **`Engine`, not just `Base#call`**, and
      asserts Grid ran on the legacy result and did **not** run on the
      converted one. Use Sankey for the converted case — its Scene
      responds to `nodes`, which is exactly what trips `engine.rb:223`
- [ ] that spec asserts **coordinates**, not a pass count. A corpus run
      cannot tell you Grid overwrote a position
- [ ] no layout hardcodes a font size; `grep -rn "FONT_SIZE = " lib/sirena/layout/`
      returns nothing
- [ ] rendering one diagram under `default` and `high_contrast` gives
      boxes sized to their own theme's text
- [ ] every registered type has a layout, and no `Layout.for` call site
      guards against `nil`; `grep -rn "Layout.for" lib/sirena/` shows no
      `&.` and no `|| model`
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

`lib/sirena/layout/scene.rb` (new), `lib/sirena/layout/base.rb` (the
`#call` template and its temporary `to_graph` branch),
`lib/sirena/layout/*.rb`, `lib/sirena/layout/info.rb` and `error.rb` (**not** new — item 03
renamed the existing transform files into those paths; item 04
rewrites them, ~20 lines each), `lib/sirena/renderer/*.rb`,
`lib/sirena/engine.rb` (calls `Layout::Base#call` from the first
conversion PR, and gates the Grid stage on the legacy branch),
`spec/contract_spec.rb`, the transition spec, and
`spec/support/legacy_layout.rb` (new, the `to_graph`-only fixture).
