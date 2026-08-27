# Worked example: the pie type, before and after

Copy this shape. When a file in this plan says "convert type X", it
means "make X look like the AFTER column here".

Pie is a good example because it has real geometry (slice angles). Every
type keeps a Layout — item 04 made it mandatory, including for `info`
and `error`, whose layouts are about twenty lines each. The smallest
case is at the bottom.

## Files

```
  BEFORE                                  AFTER
  parser/pie.rb              48 ln        parser/pie.rb              ~8 ln
  parser/grammars/pie.rb    127 ln        parser/grammars/pie.rb    127 ln  unchanged
  parser/transforms/pie.rb  142 ln        parser/builders/pie.rb    142 ln  renamed only
  diagram/pie.rb            114 ln        diagram/pie.rb            114 ln  unchanged
  transform/pie.rb           61 ln        layout/pie.rb             ~70 ln
  renderer/pie.rb           234 ln        renderer/pie.rb          ~150 ln
```

The grammar, the builder and the diagram model do not change. Only the
back half of the pipeline does.

## 1. Parser — becomes a declaration

**Before** (`lib/sirena/parser/pie.rb`, 48 lines) — this exact body is
copy-pasted into 13 of the 24 parsers:

```ruby
class PieParser < Base
  def parse(source)
    grammar = Grammars::Pie.new
    begin
      parse_tree = grammar.parse(source)
    rescue Parslet::ParseFailed => e
      raise ParseError, "Syntax error at #{e.parse_failure_cause.pos}: " \
                        "#{e.parse_failure_cause}"
    end
    transform = Transforms::Pie.new
    diagram = transform.apply(parse_tree)
    diagram
  end
end
```

**After** — the body moves to `Parser::Base` once (item 05):

```ruby
module Sirena
  module Parser
    class Pie < Base
      grammar Grammars::Pie
      builder Builders::Pie
    end
  end
end
```

## 2. Layout — emits a class, not a Hash

**Before** (`lib/sirena/transform/pie.rb`) — returns a Hash whose shape
is written down nowhere:

```ruby
def to_graph(diagram)
  raise TransformError, 'Invalid diagram' unless diagram.valid?

  {
    id: diagram.id || 'pie',
    title: diagram.title,
    show_data: diagram.show_data || false,
    slices: transform_slices(diagram),
    metadata: { total_value: ..., slice_count: ... }
  }
end
```

**After** (`lib/sirena/layout/pie.rb`) — the result class lives in the
same file, so one file answers both "how is pie laid out" and "what does
that layout look like":

```ruby
module Sirena
  module Layout
    class Pie < Layout::Base   # gives #call, and the theme/today readers
      RADIUS = 150
      CENTRE = [250, 200].freeze

      class Sector < Lutaml::Model::Serializable
        attribute :label, :string
        attribute :percentage, :float
        attribute :start_angle, :float
        attribute :end_angle, :float
        attribute :label_x, :float
        attribute :label_y, :float
        attribute :colour_index, :integer
      end

      class Scene < Layout::Scene          # width, height inherited
        attribute :title, :string
        attribute :show_data, :boolean
        attribute :sectors, Sector, collection: true
      end

      def scene(diagram)   # theme and today are readers on Layout::Base
        angle = -90.0
        sectors = diagram.slices.each_with_index.map do |slice, i|
          sweep = diagram.slice_angle(slice)
          sector = build_sector(slice, angle, sweep, i, diagram)
          angle += sweep
          sector
        end

        Scene.new(
          width: 500,
          height: diagram.title ? 460 : 400,
          title: diagram.title,
          show_data: diagram.show_data,
          sectors: sectors
        )
      end
    end
  end
end
```

Note what moved: **`start_angle`, `end_angle` and the label position are
computed here.** Today the renderer computes them itself, walking the
slices twice (`renderer/pie.rb` `render_slices` and `render_labels` each
re-accumulate `start_angle` from -90.0).

**The rule that follows from this: if a renderer computes a coordinate,
that computation belongs in Layout.** The renderer places shapes; it
does not decide where they go.

## 3. Renderer — becomes dumb

**Before** — digs through a Hash and does geometry:

```ruby
def render_slices(graph, svg)
  slices = graph[:slices] || []
  start_angle = -90.0
  slices.each_with_index do |slice, index|
    end_angle = start_angle + slice[:angle]
    render_slice(start_angle, end_angle, get_slice_color(index), svg, index)
    start_angle = end_angle
  end
end
```

**After** — reads typed fields and places shapes:

```ruby
def render_sectors(scene, svg)
  scene.sectors.each_with_index do |sector, i|
    svg << Svg::Path.new(
      d: arc_path(sector.start_angle, sector.end_angle),
      fill: theme.palette(sector.colour_index),
      stroke: theme_color(:node_stroke),
      stroke_width: '2',
      id: "slice-#{i}"
    )
  end
end
```

`get_slice_color` and the private `DEFAULT_COLORS` constant are gone —
`theme.palette(i)` replaces them (item 05C).

## 4. Registration — one row

**Before** — 13 lines in `lib/sirena.rb`, plus a separate entry in
`Engine::DIAGRAM_TYPE_PATTERNS`:

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

**After** — one row in `lib/sirena/notation/mermaid.rb`, classes found by
convention (item 06):

```ruby
TYPES = {
  pie: /\A\s*pie\s/i,
  ...
}
```

## The smallest case

Two types have a `Transform` that only copies fields —
`Transform::InfoTransform` and `Transform::ErrorTransform`, 38 lines
each to move three or four values into a Hash. `Transform::PieTransform` is not one of them — it reads each slice's
angle and percentage off the model, which is geometry, and that is why
pie is the example here. Every other `Transform` computes geometry.

**They still get a Layout and a Scene.** An earlier draft deleted them
and handed the renderer the `Diagram` model. That fails three ways:
`renderer/info.rb:71` reads `graph[:show_info]`, both renderers compute
their own text and box coordinates, and item 05's single document
builder reads `width`/`height` off the Scene and would find neither.

So `Layout::Info` is about twenty lines: copy the two fields the
renderer needs, measure the text, set `width` and `height`, **and move
the box, icon and text positions out of the renderer into the Scene**.
That last part is the point — those coordinates are constants today, so
they slip past a gate that only looks for arithmetic. A constant
position in a renderer is still the renderer owning geometry. The
engine's one line has no special case:

```ruby
scene = Layout.for(type).call(model, theme: theme, today: today)
```

**Rule: a layout that only copies fields is still a layout. What it
must never do is nothing — if it has no `width` and `height` to give,
the type is not converted yet.**

**One more thing this example still gets wrong.** The layout above calls
`diagram.slice_angle`, and the Files section promises `diagram/pie.rb`
is unchanged. Angle arithmetic belongs to Layout, not Diagram
(`LAYERS.md`), so converting pie properly moves that method across and
`diagram/pie.rb` does change. Listed here rather than quietly fixed,
because the same trap is waiting in every type whose model computes
something.

## What this example does not finish

The after-renderer above still calls `arc_path(start_angle, end_angle)`,
and `renderer/pie.rb:133` does the angle conversion, the trigonometry,
the endpoint calculation and the large-arc choice. That is renderer
geometry, which item 04 forbids.

Finish it. `renderer/pie.rb:149-151` builds the path from the centre and
the radius as well as the endpoints, so endpoints and a flag are not
enough. The Scene needs all of it:

- each sector's start and end **points**
- its large-arc flag **and its sweep flag** — `renderer/pie.rb:151`
  hardcodes the sweep to `1`, which is still the renderer choosing an
  arc direction
- the **centre** and **radius** it arcs around
- the title's coordinates, which are absent above and computed in the
  renderer today

Then the renderer only strings values into `"M … L … A … Z"` and does
no arithmetic at all.

**So this file is not yet the full conversion its opening claims.** It
is the shape to copy — the Scene, the layout, the renderer reading named
attributes — with one honest gap named here. Converting a type is not
done when the renderer stops indexing a Hash; it is done when the
renderer stops doing arithmetic.

## Checklist for each converted type

- [ ] The renderer contains no arithmetic on coordinates or angles.
- [ ] The renderer reads named attributes, never `[:symbol]` or `.dig`.
- [ ] The Scene class names every value the renderer uses — if you had to
      look at the renderer to know what to put in the Scene, that is
      fine; that is where the contract lived. Now it is written down.
- [ ] `rake corpus[pie]` shows the same pass count as before.
