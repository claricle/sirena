# frozen_string_literal: true

require "spec_helper"

# The geometry half of the link work. The parser's half — which tokens
# are a link at all — is `spec/sirena/parser/flowchart_link_spec.rb`.
# These examples read the drawn SVG back, and several hand a graph
# straight to the renderer, so they belong to the renderer, not to the
# parser that happens to feed it.
RSpec.describe Sirena::Renderer::FlowchartRenderer do
  # One node's rect, read off the node it belongs to rather than off
  # whichever rect happens to come first in the document. A coordinate may
  # be negative — a loop thrown up or left from a node near the origin
  # puts it there — so every capture takes a sign.
  def node_rect(xml, id = "A")
    group = xml[%r{<g id="node-#{id}".*?</g>}m]
    %w[x y width height].map do |attr|
      group[/<rect[^>]*\s#{attr}="(-?[\d.]+)"/, 1].to_f
    end
  end

  # The left and right edge of one node.
  def node_span(xml, id)
    x, _y, width, = node_rect(xml, id)

    [x, x + width]
  end

  def node_centre(xml, id = "A")
    x, y, width, height = node_rect(xml, id)

    [x + (width / 2), y + (height / 2)]
  end

  # The corners of the shape a node is actually drawn as.
  def outline(xml, id)
    xml[%r{<g id="node-#{id}".*?</g>}m][/<polygon[^>]*points="([^"]*)"/, 1]
      .split.map { |corner| corner.split(",").map(&:to_f) }
  end

  # The parser knowing a link's type is worth nothing if the renderer
  # draws them all the same. It did: every type reached one solid stroke
  # and a `url(#arrowhead)` that this document never defines, so `---`,
  # `--x`, `--o`, `o--o`, `===` and `-.-` rasterised identically.
  describe "what the renderer draws" do
    # Every "does not include" below would pass on an empty string, so
    # the group and its path are asserted present here rather than in one
    # example that only covers `---`.
    def edge_group(link, **options)
      xml = Sirena.render("flowchart TD\n  A #{link} B\n", **options)
      group = xml[%r{<g id="edge-[^"]*".*?</g>}m]
      expect(group).to start_with("<g id=\"edge-")
      group
    end

    def edge_path(link)
      path = edge_group(link)[/<path\b[^>]*>/]
      expect(path).to start_with("<path")
      path
    end

    it "draws nothing for an invisible link" do
      expect(edge_path("~~~")).to include('stroke="none"')
      expect(edge_group("~~~"))
        .not_to match(/<(?:polygon|line|circle)\b/)
    end

    # The transparent fill is what made the defect visible — a line run to
    # the centres showed straight through a node the theme paints `none` —
    # but it is not a condition of what is asserted here. The same `d` is
    # drawn whatever the fill is, so the name promises only the clipping.
    it "clips a visible path to the node outline at each end" do
      xml = Sirena.render(
        "flowchart LR\n  A --x B\n",
        theme: { colors: { node_fill: "none", edge_stroke: "#000000" } }
      )
      group = xml[%r{<g id="edge-[^"]*".*?</g>}m]
      points = group[/<path[^>]*d="([^"]*)"/, 1]
        .scan(/(-?[\d.]+) (-?[\d.]+)/)
        .map { |x, y| [x.to_f, y.to_f] }

      expect(points.first.first).to be_within(0.05).of(node_span(xml, "A").last)
      expect(points.last.first).to be_within(0.05).of(node_span(xml, "B").first)
    end

    # A loop's corners are the coordinates that land on a long decimal:
    # a depth of 0.45 of the shorter side, off an edge that already carries
    # one. This node drew `L 84.775 99.3` before the corners were rounded
    # with everything else on the path.
    #
    # It has to be a TD loop. Holding the span inside the node's height put
    # an LR loop's corners on whole tenths already, so the LR form passed
    # this whether or not anything rounded. TD is the only one of the two
    # that still bends off a tenth.
    it "writes every path coordinate to one decimal" do
      xml = Sirena.render("flowchart TD\n  A[abcdefghijk] --> A\n")
      numbers = xml.scan(/ d="([^"]*)"/).flatten
        .flat_map { |d| d.scan(/-?[\d.]+/) }
      decimals = numbers.filter_map { |n| n.split(".")[1]&.length }

      expect(numbers.size).to be >= 4
      expect(decimals.max).to eq(1)
    end

    # The line half: weight and pattern. Every type used to reach the
    # same solid stroke. The theme already names both — the default one
    # asks for a 2.0 line, a 3.0 thick one and a "2,2" dot — and a
    # dotted link keeps the plain width.
    {
      "---" => ["2.0", nil],
      "===" => ["3.0", nil],
      "-.-" => ["2.0", "2,2"]
    }.each do |link, (weight, dashes)|
      it "draws #{link} with the right weight and pattern" do
        path = edge_path(link)

        expect(path[/stroke-width="([^"]*)"/, 1]).to eq(weight)
        expect(path[/stroke-dasharray="([^"]*)"/, 1]).to eq(dashes)
      end
    end

    # A theme that asks for something else gets it. high_contrast names a
    # 4.0 thick line and a "4,4" dot; multiplying its 3.0 line by mmdc's
    # 3.5 drew 10.5 and dotted it 2 whatever the theme said.
    it "draws a thick link at the width its own theme asks for" do
      thick = edge_group("===", theme: "high_contrast")
      dotted = edge_group("-.-", theme: "high_contrast")

      expect(thick[/<path[^>]*stroke-width="([^"]*)"/, 1]).to eq("4.0")
      expect(dotted[/<path[^>]*stroke-dasharray="([^"]*)"/, 1]).to eq("4,4")
    end

    # Nothing fills a theme's gaps in. Then mmdc's own numbers stand: its
    # thick line is 3.5 times its normal one, and its normal one is 1.
    it "falls back to mmdc's own line when the theme names none" do
      theme = { colors: { node_fill: "#eeeeee" } }
      thick = edge_group("===", theme: theme)
      dotted = edge_group("-.-", theme: theme)

      expect(thick[/<path[^>]*stroke-width="([^"]*)"/, 1]).to eq("3.5")
      expect(dotted[/<path[^>]*stroke-dasharray="([^"]*)"/, 1]).to eq("2")
    end

    # A theme can name its plain line and say nothing about a thick one.
    # Then the multiple goes on top of the width it did name, not on top
    # of mmdc's — a 2.0 line thickens to 7.0, not to 3.5.
    it "multiplies the width the theme did name" do
      group = edge_group("===", theme: { shapes: { stroke_width: 2.0 } })

      expect(group[/<path[^>]*stroke-width="([^"]*)"/, 1]).to eq("7.0")
    end

    # The head half. Each of these was identical before.
    {
      "---" => [0, 0, 0],
      "-->" => [1, 0, 0],
      "--x" => [0, 2, 0],
      "--o" => [0, 0, 1],
      "o--o" => [0, 0, 2],
      "x--x" => [0, 4, 0],
      "<-->" => [2, 0, 0],
      "-.-o" => [0, 0, 1],
      "==x" => [0, 2, 0]
    }.each do |link, (polygons, lines, circles)|
      it "draws #{link} with its own head" do
        group = edge_group(link)

        expect([group.scan("<polygon").size,
                group.scan("<line").size,
                group.scan("<circle").size])
          .to eq([polygons, lines, circles])
      end
    end

    # A head at the node's centre is under the node, and the nodes are
    # painted afterwards — so every head was invisible and four link types
    # rasterised identically. The tip belongs on the node's edge.
    it "puts the tip on the target's boundary, not inside it" do
      xml = Sirena.render("flowchart TD\n  A --> B\n")
      left, = node_span(xml, "B")
      group = xml[%r{<g id="edge-[^"]*".*?</g>}m].to_s
      tip = group[/<polygon[^>]*points="(-?[\d.]+),/, 1].to_f

      expect(tip).to be_within(0.5).of(left)
    end

    # mmdc centres the circle behind the reference point it puts on the
    # boundary. This keeps the head visible without making it touch.
    it "leaves mmdc's gap between a circle head and the node" do
      xml = Sirena.render("flowchart TD\n  A --o B\n")
      group = xml[%r{<g id="edge-[^"]*".*?</g>}m].to_s
      cx = group[/<circle[^>]*cx="(-?[\d.]+)"/, 1].to_f
      radius = group[/<circle[^>]*r="([\d.]+)"/, 1].to_f
      stroke = group[/<circle[^>]*stroke-width="([\d.]+)"/, 1].to_f
      edge = node_span(xml, "B").first

      # Pin the marker size so a resized head cannot hide a wrong reach.
      expect(radius).to be_within(0.05).of(5.5)
      expect(stroke).to eq(1.0)
      expect(edge - (cx + radius)).to be_within(0.05).of(1.1)
    end

    # mmdc's circleEnd marker names no fill of its own and inherits the
    # `.marker` one, so the dot it draws is solid. A ring is a different
    # picture.
    it "fills the circle head the way mermaid does" do
      expect(edge_group("--o")).to include('<circle fill="#000000"')
    end

    it "keeps a cross head clear of the node" do
      xml = Sirena.render("flowchart TD\n  A --x B\n")
      group = xml[%r{<g id="edge-[^"]*".*?</g>}m].to_s
      arms = group.scan(/<line[^>]*x1="([-\d.]+)"[^>]*x2="([-\d.]+)"/)
        .flatten.map(&:to_f)
      edge = node_span(xml, "B").first

      # mmdc's reference point leaves the nearest arm point 2.0 short.
      expect(edge - arms.max).to be_within(0.05).of(2.0)
    end

    # Pin the width because placement alone cannot catch a thinner cross.
    it "strokes the cross head the width mermaid does" do
      group = edge_group("--x")

      widths = group.scan(/<line[^>]*stroke-width="([^"]*)"/).flatten

      # Counted as well as matched: `all` is happy with an empty list, so
      # a cross that drew no arms at all would have passed this.
      expect(widths).to eq(%w[2 2])
    end

    # mmdc's pointEnd is `M 0 0 L 10 5 L 0 10 z` in a 0..10 viewBox drawn
    # at markerWidth 8, so the triangle is 8 long and 4 either side of the
    # line. Reading the corners off a fixed angle instead drew it 3.1
    # wide, and nothing here would have noticed.
    it "draws the arrow head mermaid's size" do
      tip, left, right =
        edge_group("-->")[/<polygon[^>]*points="([^"]*)"/, 1]
          .split.map { |pair| pair.split(",").map(&:to_f) }

      expect(Math.hypot(*tip.zip(left).map { |a, b| a - b }))
        .to be_within(0.05).of(Math.hypot(8.0, 4.0))
      expect(Math.hypot(*left.zip(right).map { |a, b| a - b }))
        .to be_within(0.05).of(8.0)
    end

    # mmdc's crossEnd is `orient="auto"`, so the cross turns with the line
    # it ends. Drawn square to the screen it sat at the wrong angle on
    # every edge that is not axis-aligned.
    it "turns the cross head with the line it ends" do
      graph = {
        children: [{ id: "A", x: 0, y: 0, width: 40, height: 20 },
                   { id: "B", x: 300, y: 300, width: 40, height: 20 }],
        edges: [{ id: "A_to_B", sources: ["A"], targets: ["B"],
                  metadata: { arrow_type: "cross" } }]
      }
      xml = described_class.new.render(graph).to_xml
      arms = xml.scan(
        /<line[^>]*x1="(-?[\d.]+)"[^>]*y1="(-?[\d.]+)"[^>]*
         x2="(-?[\d.]+)"[^>]*y2="(-?[\d.]+)"/x
      ).map { |a| a.map(&:to_f) }

      # A diagonal edge turns both arms square to the screen; a cross drawn
      # square to the screen leaves both diagonal.
      expect(arms.size).to eq(2)
      expect(arms.map { |x1, y1, x2, y2| (x2 - x1).abs < 0.05 || (y2 - y1).abs < 0.05 })
        .to all(be(true))
      # Every endpoint is written to one decimal, so the measured arm
      # carries up to 0.1 of quantisation on its own — it lands on 12.8
      # against a true 12.728. The window has to clear that before it can
      # mean anything, or rounding alone spends most of it.
      expect(arms.map { |x1, y1, x2, y2| Math.hypot(x2 - x1, y2 - y1) })
        .to all(be_within(0.2).of(2 * 4.5 * Math.sqrt(2)))
    end

    # A node of no size has no outline for the head to land on. Dividing
    # by its half width put NaN in the SVG rather than a coordinate.
    #
    # The approach has to be square on. A ray with both components
    # non-zero divides by nothing twice, and the two infinities collapse
    # back to a finite 0 — so an off-axis node would pass this with the
    # guards taken out again.
    #
    # Three of the four discriminate. `circle` is the control: its scale
    # is [half_w, half_h].min / span, which is a finite 0.0 at zero size
    # and never calls `axis_ratio`, so it stays green with the guard
    # removed. It is here to say a zero-size circle still draws a head,
    # not to hold the guard up.
    %w[rhombus hexagon circle stadium].each do |shape|
      it "draws no NaN aiming square at a #{shape} of no size" do
        graph = {
          children: [{ id: "A", x: 0, y: 0, width: 40, height: 20 },
                     { id: "B", x: 20, y: 200, width: 0, height: 0,
                       metadata: { shape: shape } }],
          edges: [{ id: "A_to_B", sources: ["A"], targets: ["B"],
                    metadata: { arrow_type: "arrow" } }]
        }
        xml = described_class.new.render(graph).to_xml

        # The edge group, not the document: a rhombus and a hexagon NODE
        # are drawn as polygons too, so asserting against the whole thing
        # passed whether or not a head was drawn at all.
        expect(xml[%r{<g id="edge-A_to_B".*?</g>}m]).to include("<polygon")
        expect(xml).not_to include("NaN")
      end
    end

    # A collapsed width still leaves a vertical outline for a square-on head.
    %w[rhombus hexagon stadium].each do |shape|
      it "lands on the end of a #{shape} with no width" do
        graph = {
          children: [{ id: "A", x: -20, y: 100, width: 40, height: 20 },
                     { id: "B", x: 0, y: 0, width: 0, height: 20,
                       metadata: { shape: shape } }],
          edges: [{ id: "A_to_B", sources: ["A"], targets: ["B"],
                    metadata: { arrow_type: "arrow" } }]
        }
        xml = described_class.new.render(graph).to_xml
        group = xml[%r{<g id="edge-A_to_B".*?</g>}m]
        tip = group[/<polygon[^>]*points="([^"]*)"/, 1]
          .split.first.split(",").map(&:to_f)

        expect(tip).to eq([0.0, 20.0])
      end
    end

    # An arrow is the head that reads the direction. A circle and a cross
    # reach the same zero-span guard through `backed_off`, so this pins
    # the arrow because it is the one drawn without a back-off first.
    #
    # It does NOT draw a head. Two nodes on the same centre give the head
    # no direction, and the polygon comes out as three copies of one point
    # — `20.0,10.0` three times, zero area. What this holds is that the
    # guard turns that into a degenerate polygon rather than NaN.
    it "writes no NaN for nodes sitting on top of each other" do
      graph = {
        children: [{ id: "A", x: 0, y: 0, width: 40, height: 20 },
                   { id: "B", x: 0, y: 0, width: 40, height: 20 }],
        edges: [{ id: "A_to_B", sources: ["A"], targets: ["B"],
                  metadata: { arrow_type: "arrow" } }]
      }
      xml = described_class.new.render(graph).to_xml

      expect(xml[%r{<g id="edge-A_to_B".*?</g>}m]).to include("<polygon")
      expect(xml).not_to include("NaN")
    end

    # SVG clamps `rx` to half the width, so a stadium no wider than it is
    # tall is drawn as an ellipse, not a capsule.
    #
    # The approach has to be diagonal. Dead level with the centre the two
    # answers coincide — the capsule's cap crosses that line at exactly
    # the ellipse's own side — so a square-on head would pass this with
    # the ellipse branch taken out again.
    it "lands on the outline of a stadium narrower than it is tall" do
      graph = {
        children: [{ id: "A", x: 95, y: -100, width: 40, height: 20 },
                   { id: "B", x: 200, y: -40, width: 30, height: 100,
                     metadata: { shape: "stadium" } }],
        edges: [{ id: "A_to_B", sources: ["A"], targets: ["B"],
                  metadata: { arrow_type: "arrow" } }]
      }
      xml = described_class.new.render(graph).to_xml
      tip_x, tip_y = xml[/<polygon[^>]*points="(-?[\d.]+),(-?[\d.]+)/]
        .match(/(-?[\d.]+),(-?[\d.]+)/).captures.map(&:to_f)

      # On the ellipse itself: half the width is 15, half the height 50.
      expect((((tip_x - 215) / 15.0)**2) + (((tip_y - 10) / 50.0)**2))
        .to be_within(0.01).of(1.0)
    end

    # mmdc caps a loop's depth at 48. The layout never builds a node big
    # enough, but a graph handed straight to the renderer can.
    it "caps a big node's loop depth the way mmdc does" do
      graph = {
        children: [{ id: "A", x: 0, y: 0, width: 200, height: 200 }],
        edges: [{ id: "A_to_A", sources: ["A"], targets: ["A"],
                  metadata: { arrow_type: "arrow" } }],
        layoutOptions: { "elk.direction" => "DOWN" }
      }
      xml = described_class.new.render(graph).to_xml
      corners = xml[/<path[^>]*d="([^"]*)"/, 1]
        .scan(/(-?[\d.]+) (-?[\d.]+)/).map { |_x, y| y.to_f }

      # 0.45 of 200 is 90; the cap stops it at 48 below the node's foot.
      expect(corners.max - 200).to be_within(0.05).of(48.0)
    end

    # Two nodes at one position leave the head no direction to point in.
    # Backing it off its own reach must not divide by that nothing.
    it "draws a circle head for nodes sitting on top of each other" do
      graph = {
        children: [{ id: "A", x: 0, y: 0, width: 40, height: 20 },
                   { id: "B", x: 0, y: 0, width: 40, height: 20 }],
        edges: [{ id: "A_to_B", sources: ["A"], targets: ["B"],
                  metadata: { arrow_type: "circle" } }]
      }
      xml = described_class.new.render(graph).to_xml

      expect(xml[%r{<g id="edge-A_to_B".*?</g>}m]).to include("<circle")
      expect(xml).not_to include("NaN")
    end

    # The cross is the third head, and the only one that turns its arms to
    # the line. With no direction to turn to it falls back to horizontal —
    # take that fallback out and the arms collapse to nothing, which is why
    # this measures their length rather than their presence.
    it "draws a cross head for nodes sitting on top of each other" do
      graph = {
        children: [{ id: "A", x: 0, y: 0, width: 40, height: 20 },
                   { id: "B", x: 0, y: 0, width: 40, height: 20 }],
        edges: [{ id: "A_to_B", sources: ["A"], targets: ["B"],
                  metadata: { arrow_type: "cross" } }]
      }
      xml = described_class.new.render(graph).to_xml
      arms = xml[%r{<g id="edge-A_to_B".*?</g>}m]
        .scan(/<line[^>]*x1="([-\d.]+)" y1="([-\d.]+)" x2="([-\d.]+)" y2="([-\d.]+)"/)
        .map { |c| c.map(&:to_f) }

      expect(arms.size).to eq(2)
      expect(arms.map { |x1, y1, x2, y2| Math.hypot(x2 - x1, y2 - y1) })
        .to all(be_within(0.2).of(2 * 4.5 * Math.sqrt(2)))
      expect(xml).not_to include("NaN")
    end

    # A node of no size loops back onto its own centre, so the label has
    # no direction to be pushed out along. It stays ON that centre, and
    # the coordinates are what says so: asserting only that a `<text>` was
    # drawn leaves the guard free to put it anywhere at all — a thousand
    # units off-canvas passed.
    #
    # The node sits away from the origin deliberately. At (0, 0) its
    # centre and a dropped or zeroed coordinate are the same point, so the
    # assertion could not tell them apart.
    it "places a self link's label on a node of no size" do
      graph = {
        children: [{ id: "A", x: 30, y: 70, width: 0, height: 0 }],
        edges: [{ id: "A_to_A", sources: ["A"], targets: ["A"],
                  labels: [{ text: "x" }],
                  metadata: { arrow_type: "arrow" } }]
      }
      xml = described_class.new.render(graph).to_xml
      text = xml[%r{<g id="edge-A_to_A".*?</g>}m][/<text\b[^>]*>/].to_s

      expect(text).to start_with("<text")
      expect(text[/\sx="(-?[\d.]+)"/, 1].to_f).to eq(30.0)
      expect(text[/\sy="(-?[\d.]+)"/, 1].to_f).to eq(70.0)
      expect(xml).not_to include("NaN")
    end

    # A hardcoded head left a white line with black heads on a dark theme.
    # Asserted as "the head is the same colour as its line", and that it
    # is a colour — matching on absence alone passed while a leaked empty
    # theme registry left the whole diagram unpainted.
    %w[default dark light high_contrast].each do |name|
      it "draws the head in the #{name} theme's edge colour" do
        xml = Sirena.render("flowchart TD\n  A --> B\n", theme: name)
        group = xml[%r{<g id="edge-[^"]*".*?</g>}m].to_s
        ink = group[/<path[^>]*stroke="([^"]*)"/, 1]

        expect(ink).to match(/\A#[0-9a-f]{6}\z/)
        expect(group[/<polygon[^>]*fill="([^"]*)"/, 1]).to eq(ink)
      end
    end

    # The sweep above cannot say WHICH colour the head was drawn in. All
    # four built-in themes paint their nodes and their edges the same ink
    # — `node_stroke` and `edge_stroke` are one value in every one of them
    # — so reading the node's colour by mistake agrees with reading the
    # edge's on all four. A theme that separates them is what tells the
    # two apart, and it draws the picture the sweep exists to refuse: a
    # red head on a blue line.
    it "draws the head in the edge colour, not the node's" do
      xml = Sirena.render(
        "flowchart TD\n  A --> B\n",
        theme: { colors: { node_stroke: "#ff0000", edge_stroke: "#0000ff" } }
      )
      group = xml[%r{<g id="edge-[^"]*".*?</g>}m].to_s

      expect(group[/<path[^>]*stroke="([^"]*)"/, 1]).to eq("#0000ff")
      expect(group[/<polygon[^>]*fill="([^"]*)"/, 1]).to eq("#0000ff")
    end

    # Nothing fills a theme's gaps in, so a theme can name no edge colour
    # at all. Then the line has no stroke and is invisible, but the head
    # was a polygon with no fill, and SVG fills that black. The picture
    # was black arrowheads floating over nothing.
    it "leaves the head unpainted when the theme paints no line" do
      xml = Sirena.render("flowchart TD\n  A --> B\n",
                          theme: { colors: { node_fill: "#eeeeee" } })
      group = xml[%r{<g id="edge-[^"]*".*?</g>}m].to_s

      expect(group).not_to match(/<path[^>]*stroke=/)
      expect(group[/<polygon[^>]*fill="([^"]*)"/, 1]).to eq("none")
    end

    # A cross is stroked and not filled, so leaving its stroke off really
    # is invisible. A circle is BOTH — mermaid's circleEnd is a solid dot
    # — so it needs its own `none` for the fill, or SVG paints it black.
    # Asserting only the stroke let that `none` be deleted unnoticed.
    %w[--x --o].each do |link|
      it "leaves #{link}'s head unstroked when the theme paints no line" do
        xml = Sirena.render("flowchart TD\n  A #{link} B\n",
                            theme: { colors: { node_fill: "#eeeeee" } })
        group = xml[%r{<g id="edge-[^"]*".*?</g>}m].to_s

        expect(group).to match(/<(line|circle)\b/)
        expect(group).not_to match(/<(line|circle)[^>]*\bstroke=/)
      end
    end

    # Every halving in the renderer is a float one, so a hand-built node
    # with odd integer sides puts its label on the same centre its shape
    # and its edge use. Integer division put the text half a pixel off.
    it "centres a label on an odd-sided node the way the shape is centred" do
      graph = {
        children: [{ id: "A", x: 0, y: 0, width: 41, height: 21,
                     labels: [{ text: "A" }] }],
        edges: []
      }
      xml = described_class.new.render(graph).to_xml
      group = xml[%r{<g id="node-A".*?</g>}m]

      expect(group[/<text[^>]*x="(-?[\d.]+)"/, 1].to_f).to eq(20.5)
      expect(group[/<text[^>]*y="(-?[\d.]+)"/, 1].to_f).to eq(10.5)
    end

    # The circle's own half of that: it is filled, so an absent fill is
    # not an unpainted dot but a black one. Only this assertion stops the
    # `none` being dropped.
    it "leaves a circle head unfilled when the theme paints no line" do
      xml = Sirena.render("flowchart TD\n  A --o B\n",
                          theme: { colors: { node_fill: "#eeeeee" } })
      group = xml[%r{<g id="edge-[^"]*".*?</g>}m].to_s

      expect(group[/<circle[^>]*fill="([^"]*)"/, 1]).to eq("none")
    end

    # A path that bends arrives along its last segment, not along the span
    # between the two node centres. Orienting on the span drew a diagonal
    # arrow on a path that comes in vertically.
    #
    # Read off the drawn SVG rather than through the geometry helper. The
    # fallback layout emits no bend points, so nothing else in this file
    # renders a non-self edge that carries one — the branch that follows a
    # bend was reached by no example that draws, and a `send` past it
    # leaves that arm empty rather than filling it.
    it "points the head along the arriving segment, not the span" do
      graph = {
        children: [{ id: "A", x: 0, y: 0, width: 40, height: 20 },
                   { id: "B", x: 200, y: 200, width: 40, height: 20 }],
        edges: [{ id: "A_to_B", sources: ["A"], targets: ["B"],
                  sections: [{ bendPoints: [{ x: 220, y: 0 }] }],
                  metadata: { arrow_type: "arrow" } }]
      }
      xml = described_class.new.render(graph).to_xml
      group = xml[%r{<g id="edge-A_to_B".*?</g>}m].to_s
      tip, *back = group[/<polygon[^>]*points="([^"]*)"/, 1]
        .split.map { |pair| pair.split(",").map(&:to_f) }

      # The path leaves the bend at x 220 and drops straight onto B's top
      # edge. `tip.first` is the assertion that discriminates: aiming
      # along the span puts the tip at 210, and its y is 200 either way.
      expect(tip).to eq([220.0, 200.0])
      # Square across the line it ends, so both back corners share a y
      # above the tip. Aimed along the span they sit at different ones.
      expect(back.map(&:last).uniq).to eq([192.0])
    end

    # With no bend the head has only the OTHER node's centre to aim from.
    it "falls back to the other node when there is no bend" do
      graph = {
        children: [{ id: "A", x: 0, y: 0, width: 40, height: 20 },
                   { id: "B", x: 200, y: 0, width: 40, height: 20 }],
        edges: [{ id: "A_to_B", sources: ["A"], targets: ["B"],
                  metadata: { arrow_type: "arrow" } }]
      }
      xml = described_class.new.render(graph).to_xml
      group = xml[%r{<g id="edge-A_to_B".*?</g>}m].to_s
      tip, *back = group[/<polygon[^>]*points="([^"]*)"/, 1]
        .split.map { |pair| pair.split(",").map(&:to_f) }

      # A's centre is (20, 10), dead level with B's, so the tip lands on
      # the middle of B's left edge. Aiming from the origin instead pulls
      # it to y 9.1; aiming from B's own centre leaves no ray at all and
      # the polygon degenerates onto that centre.
      expect(tip).to eq([200.0, 10.0])
      expect(back.map(&:first).uniq).to eq([192.0])
    end

    it "puts a head at each end of a two-ended link" do
      xml = Sirena.render("flowchart TD\n  A <--> B\n")
      group = xml[%r{<g id="edge-[^"]*".*?</g>}m].to_s
      tips = group.scan(/<polygon[^>]*points="(-?[\d.]+),/)
        .flatten.map(&:to_f)

      expect(tips).to contain_exactly(
        be_within(0.5).of(node_span(xml, "A").last),
        be_within(0.5).of(node_span(xml, "B").first)
      )
    end

    # An ordinary label sits at the midpoint of the two node centres,
    # lifted off the line it names. The loop specs below measure their
    # lift against this one, and nothing was holding it — the lift could
    # go and they would all still agree.
    #
    # The x is asserted as well as the y, and it is the half that
    # discriminates. The fallback layout puts A and B on one row, so the
    # path's start, the source's centre and the midpoint all share a y of
    # 67 — every candidate anchor gives the same lifted y. Anchoring on
    # the source centre instead drops the label on top of A and leaves
    # that y untouched.
    it "lifts an ordinary label clear of its own line" do
      xml = Sirena.render("flowchart TD\n  A -->|hi| B\n")
      group = xml[%r{<g id="edge-[^"]*".*?</g>}m].to_s
      line = group[/<path[^>]*d="M [-\d.]+ ([-\d.]+)/, 1].to_f
      midpoint = (node_centre(xml, "A").first + node_centre(xml, "B").first) / 2

      expect(group[/<text[^>]*y="([-\d.]+)"/, 1].to_f).to eq(line - 5)
      expect(group[/<text[^>]*x="([-\d.]+)"/, 1].to_f).to eq(midpoint)
    end
  end

  # Both ends of a self link are the same centre, so the path came out as
  # `M x y L x y` and the head sat at that centre, under a node painted
  # after it. Nothing of the link was on screen. mmdc 11.12.0 loops it off
  # the node instead. Measured off mmdc: the loop reaches past the node
  # edge by 0.45 of the node's shorter side. How far it spreads sideways is
  # sirena's own answer, and the ORDER its two limits are applied in is what
  # decides the corners the examples below assert — `self_loop_bends` in
  # `lib/sirena/renderer/flowchart.rb` states that rule, and it is
  # deliberately not restated here so the two cannot drift apart. The head
  # sits where the loop meets the node again.
  describe "a link from a node to itself" do
    def node_top(xml, id = "A")
      node_rect(xml, id)[1]
    end

    def node_bottom(xml, id = "A")
      _x, y, _width, height = node_rect(xml, id)
      y + height
    end

    # A coordinate can be negative, and a regex that cannot match one
    # drops the point silently rather than failing.
    def path_points(xml)
      group = xml[%r{<g id="edge-[^"]*".*?</g>}m]
      group[/<path[^>]*d="([^"]*)"/, 1].scan(/(-?[\d.]+) (-?[\d.]+)/)
        .map { |x, y| [x.to_f, y.to_f] }
    end

    def head_points(xml)
      group = xml[%r{<g id="edge-[^"]*".*?</g>}m]
      group[/<polygon[^>]*points="([^"]*)"/, 1]
        .split.map { |pair| pair.split(",").map(&:to_f) }
    end

    it "loops past the node instead of drawing a line of no length" do
      xml = Sirena.render("flowchart TD\n  A --> A\n")

      expect(path_points(xml).map(&:last).max).to be > node_bottom(xml)
    end

    it "gives the loop two corners, not one line out and back" do
      xml = Sirena.render("flowchart TD\n  A --> A\n")
      corners = path_points(xml).select { |_x, y| y > node_bottom(xml) }

      expect(corners.size).to eq(2)
      expect(corners.map(&:first).uniq.size).to eq(2)
    end

    it "starts and ends the loop on the node outline" do
      xml = Sirena.render("flowchart TD\n  A --> A\n")
      start_point, end_point = path_points(xml).values_at(0, -1)

      expect([start_point.last, end_point.last])
        .to all(be_within(0.05).of(node_bottom(xml)))
    end

    # A loop thrown sideways spreads along y, so the spread has to be
    # measured from the height, and then held inside it. Measuring it from
    # the width put the corners outside a wide node's height band, and the
    # loop left through the top face and came back through the bottom one.
    #
    # The all-directions example below does not catch that: it asks only
    # that the corners sit past the node edge along the flow, which stays
    # true while the face moves. This asks where the loop actually meets
    # the node.
    #
    # The width is swept rather than picked: a single 16-character label
    # passed here while an 80-character one still left through the top.
    #
    # Not because the inequality turns over — every node in this sweep is
    # 34 high, so the lower limit of 18 exceeds the 17 half height at all
    # of them. What the width changes is which boundary the ray out of the
    # corner meets first. That is why one label proves nothing here and a
    # range does.
    #
    # The window is 0.1 rather than 0.05 because a coordinate written to
    # one decimal already carries 0.05 of rounding, so 0.05 would sit
    # exactly on the quantisation floor with no headroom.
    [4, 16, 40, 80, 160].each do |label_width|
      it "keeps a sideways loop on the flow-side face at #{label_width} characters" do
        xml = Sirena.render("flowchart LR\n  A[#{'a' * label_width}] --> A\n")
        x, _y, width, = node_rect(xml)
        start_point, end_point = path_points(xml).values_at(0, -1)

        expect([start_point.first, end_point.first])
          .to all(be_within(0.1).of(x + width))
      end
    end

    # `sections` with `bendPoints` is the shape a laid-out graph would
    # arrive in. Nothing produces it today — the fallback grid writes no
    # `sections` at all, and elkrb is declared but not wired — so this
    # fixture stands in for that layout rather than reproducing one.
    it "keeps supplied bends for a self link" do
      graph = {
        children: [{ id: "A", x: 0, y: 0, width: 40, height: 20 }],
        edges: [{ id: "A_to_A", sources: ["A"], targets: ["A"],
                  sections: [{ bendPoints: [{ x: 80, y: 30 },
                                            { x: 80, y: -10 }] }],
                  metadata: { arrow_type: "arrow" } }]
      }
      xml = described_class.new.render(graph).to_xml

      expect(path_points(xml)[1..2]).to eq([[80.0, 30.0], [80.0, -10.0]])
    end

    # A long label widens the layout box without widening the drawn circle.
    it "starts a wide circle loop's depth at its drawn edge" do
      xml = Sirena.render(
        "flowchart LR\n  A((a fairly long circle label)) --> A\n"
      )
      circle = xml[%r{<g id="node-A".*?</g>}m][/<circle\b[^>]*>/]
      cx = circle[/\scx="(-?[\d.]+)"/, 1].to_f
      radius = circle[/\sr="([\d.]+)"/, 1].to_f
      far_x = path_points(xml).map(&:first).max

      expect(far_x - (cx + radius)).to be_within(0.05).of(2 * radius * 0.45)
    end

    it "puts the head where the loop meets the node, not inside it" do
      xml = Sirena.render("flowchart TD\n  A --> A\n")
      tip, *back = head_points(xml)

      expect(tip.last).to be_within(0.5).of(node_bottom(xml))
      expect(back.map(&:last).min).to be > node_bottom(xml)
    end

    it "leaves a link between two nodes straight" do
      xml = Sirena.render("flowchart TD\n  A --> B\n")

      expect(path_points(xml).size).to eq(2)
    end

    # A bare node is 37 wide, so the ratio alone would reach 6.5 on each
    # side and span about 13. Sirena pins the reach at 18 to avoid a spike.
    it "keeps a narrow node's loop 18 either side of centre" do
      xml = Sirena.render("flowchart TD\n  A --> A\n")
      centre_x, = node_centre(xml)
      corners = path_points(xml).select { |_cx, y| y > node_bottom(xml) }

      expect(corners.size).to eq(2)
      expect(corners.map { |cx, _y| (cx - centre_x).abs })
        .to all(be_within(0.05).of(18.0))
    end

    # Both neighbours above sit on a clamp, so the ratio itself never shows
    # through them: doubling 0.175 leaves both of their answers unchanged.
    # This node is wide enough to clear 18 and narrow enough to stay under
    # 50, which is the only place the ratio is the answer.
    it "spans 0.175 of the width where neither limit binds" do
      xml = Sirena.render(
        "flowchart TD\n  A --> A[a label of some length here]\n"
      )
      centre_x, = node_centre(xml)
      width = node_rect(xml, "A")[2]
      corners = path_points(xml).select { |_cx, y| y > node_bottom(xml) }

      expect(width * 0.175).to be_between(18.0, 50.0)
      expect(corners.size).to eq(2)
      expect(corners.map { |cx, _y| (cx - centre_x).abs })
        .to all(be_within(0.05).of(width * 0.175))
    end

    # 296 wide here, so the ratio alone would reach 51.8 either side.
    # Sirena pins it at 50.
    it "keeps a wide node's loop 50 either side of centre" do
      xml = Sirena.render(
        "flowchart TD\n  A --> A[a very long label indeed goes here now]\n"
      )
      centre_x, = node_centre(xml)
      corners = path_points(xml).select { |_cx, y| y > node_bottom(xml) }

      expect(corners.size).to eq(2)
      expect(corners.map { |cx, _y| (cx - centre_x).abs })
        .to all(be_within(0.05).of(50.0))
    end

    # mmdc throws the loop the way the diagram flows: below for TD, right
    # for LR, left for RL and above for BT. Every one of them used to hang
    # below, so three directions in four drew the loop on the wrong side.
    { "TD" => [0, 1], "BT" => [0, -1], "LR" => [1, 0], "RL" => [-1, 0] }
      .each do |direction, (out_x, out_y)|
      it "throws a #{direction} loop the way the diagram flows" do
        xml = Sirena.render("flowchart #{direction}\n  A --> A\n")
        _x, _y, width, height = node_rect(xml)
        cx, cy = node_centre(xml)
        corners = path_points(xml)[1..2]

        # Every corner lies past the node edge, measured along the flow.
        reach = corners.map do |px, py|
          ((px - cx) * out_x) + ((py - cy) * out_y)
        end

        expect(reach.min)
          .to be > ((width / 2) * out_x.abs) + ((height / 2) * out_y.abs)
      end
    end

    # A graph handed straight to the renderer need not say which way it
    # flows. Then the loop hangs below, as it does for TD.
    it "hangs the loop below a graph that names no direction" do
      graph = {
        children: [{ id: "A", x: 0, y: 0, width: 40, height: 20 }],
        edges: [{ id: "A_to_A", sources: ["A"], targets: ["A"],
                  metadata: { arrow_type: "arrow" } }]
      }
      xml = described_class.new.render(graph).to_xml

      expect(path_points(xml).map(&:last).max).to be > 20
    end

    # The label sat at the midpoint between the two ends, and a self
    # link's two ends are the same centre — so it was buried under the
    # node along with everything else.
    it "carries a self link's label clear of the node" do
      xml = Sirena.render("flowchart TD\n  A -->|again| A\n")
      group = xml[%r{<g id="edge-[^"]*".*?</g>}m].to_s

      expect(group[/<text[^>]*y="(-?[\d.]+)"/, 1].to_f).to be > node_bottom(xml)
    end

    # An ordinary label is lifted UP off its line. Doing that to a loop
    # thrown downwards pulls it back towards the node, and a loop thrown
    # upwards is lifted into the loop. It belongs past the loop, whichever
    # way the loop went.
    { "TD" => 1, "BT" => -1 }.each do |direction, outward|
      it "hangs a #{direction} loop's label past the loop, not back inside" do
        xml = Sirena.render("flowchart #{direction}\n  A -->|again| A\n")
        group = xml[%r{<g id="edge-[^"]*".*?</g>}m].to_s
        label = group[/<text[^>]*y="([-\d.]+)"/, 1].to_f
        corner = path_points(xml).map(&:last).minmax[outward.positive? ? 1 : 0]

        expect((label - corner) * outward).to be_within(0.05).of(5.0)
      end
    end

    # The shorter side, whichever side that is. A diamond is 47 wide and
    # 54 tall, so it pins the width half; a plain box is 37 wide and 34
    # tall, so it pins the height half. Asserting only the diamond would
    # hold just as well if the depth were read off the width outright,
    # because there the width IS the shorter side.
    it "measures a loop's depth from a tall node's width" do
      xml = Sirena.render("flowchart TD\n  A{x} --> A\n")
      diamond = outline(xml, "A")
      width = diamond.map(&:first).max - diamond.map(&:first).min
      height = diamond.map(&:last).max - diamond.map(&:last).min
      depth = path_points(xml).map(&:last).max - diamond.map(&:last).max

      # Every corner is written to one decimal, so the measured depth
      # carries up to 0.05 of quantisation on its own — it lands on 21.2
      # against a true 21.15. The window has to clear that and still
      # discriminate: reading the depth off the HEIGHT instead lands 3.15
      # away, thirty times the window.
      expect(width).to be < height
      expect(depth).to be_within(0.1).of(0.45 * width)
    end

    it "measures a loop's depth from a wide node's height" do
      xml = Sirena.render("flowchart TD\n  A --> A\n")
      left, right = node_span(xml, "A")
      bottom = node_bottom(xml)
      height = bottom - node_top(xml)
      depth = path_points(xml).map(&:last).max - bottom

      expect(height).to be < (right - left)
      expect(depth).to be_within(0.05).of(0.45 * height)
      expect(depth).not_to be_within(0.05).of(0.45 * (right - left))
    end
  end

  # The head was placed by intersecting the node's bounding box whatever
  # the node was drawn as. A diamond, a circle and a hexagon all pull in
  # from the corners a box keeps, so a head arriving diagonally stopped
  # outside the shape it was pointing at. mmdc lands it on the outline.
  describe "the head on a node that is not a box" do
    def tip_of(xml, edge)
      xml[%r{<g id="edge-#{edge}".*?</g>}m][/<polygon[^>]*points="([^"]*)"/, 1]
        .split.first.split(",").map(&:to_f)
    end

    # How far the tip is from the nearest edge of the drawn outline.
    def gap_to(point, corners)
      edges = corners.each_cons(2).to_a << [corners.last, corners.first]
      edges.map { |a, b| distance_to_segment(point, a, b) }.min
    end

    def distance_to_segment(point, corner_a, corner_b)
      px, py = point
      ax, ay = corner_a
      dx = corner_b[0] - ax
      dy = corner_b[1] - ay
      along = ((((px - ax) * dx) + ((py - ay) * dy)) /
               ((dx * dx) + (dy * dy))).clamp(0.0, 1.0)

      Math.hypot(px - (ax + (along * dx)), py - (ay + (along * dy)))
    end

    # The box answer puts this tip 7.6 out past the diamond's sloped edge.
    it "lands on a diamond's sloped edge" do
      xml = Sirena.render("flowchart TD\n  A{x} --> A\n")

      expect(gap_to(tip_of(xml, "A_to_A"), outline(xml, "A"))).to be_within(0.05).of(0)
    end

    # D sits on the row below, so the link arrives at a slant. The box
    # answer puts this tip 4.0 out past the hexagon's sloped face.
    it "lands on a hexagon's sloped face" do
      xml = Sirena.render(
        "flowchart TD\n  A --> B\n  B --> C\n  C --> D{{x}}\n"
      )

      expect(gap_to(tip_of(xml, "C_to_D"), outline(xml, "D"))).to be_within(0.05).of(0)
    end

    # A hexagon keeps a flat top and bottom, and a loop comes back up
    # into one of them. Reading only its sloped faces overshoots and puts
    # the tip 2.1 below the node.
    it "lands on a hexagon's flat bottom" do
      xml = Sirena.render("flowchart TD\n  A{{x}} --> A\n")

      expect(gap_to(tip_of(xml, "A_to_A"), outline(xml, "A")))
        .to be_within(0.05).of(0)
    end

    # A stadium and a rounded box are both drawn with `rx` at half the
    # height, so their ends are semicircles and the box answer overshoots
    # them by as much as it overshoots a diamond. A narrow one is almost
    # all end; a wide one has a flat run between its two ends, and the
    # ray leaves through whichever it reaches.
    { "x" => "narrow", "a very long stadium label here" => "wide" }
      .each do |label, shape|
      it "lands on a #{shape} stadium's outline" do
        xml = Sirena.render(
          "flowchart TD\n  A --> B\n  B --> C\n  C --> D([#{label}])\n"
        )
        rect = xml[%r{<g id="node-D".*?</g>}m].match(
          /<rect[^>]*x="([-\d.]+)" y="([-\d.]+)" width="([\d.]+)" height="([\d.]+)"/
        )
        x, y, width, height = rect.captures.map(&:to_f)
        half_w = width / 2
        half_h = height / 2
        tip_x, tip_y = tip_of(xml, "C_to_D")
        across = (tip_x - (x + half_w)).abs
        down = tip_y - (y + half_h)
        straight = [half_w - half_h, 0].max
        gap = if across <= straight
                down.abs - half_h
              else
                Math.hypot(across - straight, down) - half_h
              end

        expect(gap).to be_within(0.05).of(0)
      end
    end

    # `double_circle` and `rounded` each ride another shape's branch —
    # one shares the circle's outline in NODE_OUTLINES, one shares the
    # stadium's. Dropping either name sends it to the box answer, and
    # every example above would stay green, so each is pinned on the
    # outline it is actually drawn as.
    it "lands on a double circle at its radius" do
      xml = Sirena.render("flowchart TD\n  A(((x))) --> A\n")
      group = xml[%r{<g id="node-A".*?</g>}m]
      cx, cy, r = group.match(
        /<circle[^>]*cx="([-\d.]+)"[^>]*cy="([-\d.]+)"[^>]*r="([\d.]+)"/
      ).captures.map(&:to_f)
      tip_x, tip_y = tip_of(xml, "A_to_A")

      expect(Math.hypot(tip_x - cx, tip_y - cy)).to be_within(0.05).of(r)
    end

    it "lands on a rounded box's curved end" do
      xml = Sirena.render("flowchart TD\n  A --> B\n  B --> C\n  C --> D(x)\n")
      rect = xml[%r{<g id="node-D".*?</g>}m].match(
        /<rect[^>]*x="([-\d.]+)" y="([-\d.]+)" width="([\d.]+)" height="([\d.]+)"/
      )
      x, y, width, height = rect.captures.map(&:to_f)
      half_w = width / 2
      half_h = height / 2
      tip_x, tip_y = tip_of(xml, "C_to_D")
      across = (tip_x - (x + half_w)).abs
      down = tip_y - (y + half_h)
      straight = [half_w - half_h, 0].max
      gap = if across <= straight
              down.abs - half_h
            else
              Math.hypot(across - straight, down) - half_h
            end

      expect(gap).to be_within(0.05).of(0)
    end

    it "lands on a circle at its radius" do
      xml = Sirena.render("flowchart TD\n  A((x)) --> A\n")
      group = xml[%r{<g id="node-A".*?</g>}m]
      cx, cy, r = group.match(
        /<circle[^>]*cx="([-\d.]+)"[^>]*cy="([-\d.]+)"[^>]*r="([\d.]+)"/
      ).captures.map(&:to_f)
      tip = tip_of(xml, "A_to_A")

      expect(Math.hypot(tip[0] - cx, tip[1] - cy)).to be_within(0.05).of(r)
    end
  end
end
