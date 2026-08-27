# frozen_string_literal: true

require "spec_helper"

# The whole pipeline, because a cluster is only right if the model, the
# layout and the renderer agree on where it sits. Every expectation was
# read off mmdc 11.12.0.
RSpec.describe Sirena::Engine do
  def render(source)
    described_class.new.render(source)
  end

  def cluster_ids(xml)
    xml.scan(/<g id="cluster-([^"]+)">/).flatten
  end

  def box(xml, id)
    section = xml[/<g id="cluster-#{id}">.*?<\/g>/m]
    return nil unless section

    rect = section[/<rect[^>]*>/]
    %w[x y width height].to_h { |name| [name.to_sym, attr(rect, name)] }
  end

  # `\bwidth=` also matches `stroke-width=`, so the box came back 2 units
  # wide and the containment checks passed on the wrong number.
  def attr(element, name)
    element[/(?<![-\w])#{name}="([^"]*)"/, 1].to_f
  end

  # Which way the second box sits from the first, one sign per axis.
  def centre_gap(from, to)
    [(to[:x] + (to[:width] / 2)) - (from[:x] + (from[:width] / 2)),
     (to[:y] + (to[:height] / 2)) - (from[:y] + (from[:height] / 2))]
      .map { |d| d <=> 0 }
  end

  def inside?(rect, x, y)
    x.between?(rect[:x], rect[:x] + rect[:width]) &&
      y.between?(rect[:y], rect[:y] + rect[:height])
  end

  # On one of the four edges of the rectangle. A unit of slack, because
  # the crossing is rounded to two decimals and the box coordinates come
  # back out of the XML as text.
  def on_border?(rect, x, y)
    right = rect[:x] + rect[:width]
    bottom = rect[:y] + rect[:height]
    return false unless x.between?(rect[:x] - 1, right + 1)
    return false unless y.between?(rect[:y] - 1, bottom + 1)

    [(x - rect[:x]).abs, (x - right).abs,
     (y - rect[:y]).abs, (y - bottom).abs].min <= 1
  end

  # The bounding box the layout gave the node, whichever element the
  # shape is drawn with. `nil` when the node was not drawn at all, so a
  # spec says "no node" rather than crashing on it.
  def node_rect(xml, id)
    shape = node_shape(xml, id)
    shape && bounds_of(shape)
  end

  def bounds_of(shape)
    case shape
    when /\A<circle/
      r = attr(shape, "r")
      { x: attr(shape, "cx") - r, y: attr(shape, "cy") - r,
        width: r * 2, height: r * 2 }
    when /\A<polygon/
      pairs = shape[/points="([^"]*)"/, 1].split(/\s+/)
      pts = pairs.map { |pair| pair.split(",").map(&:to_f) }
      xs = pts.map(&:first)
      ys = pts.map(&:last)
      { x: xs.min, y: ys.min,
        width: xs.max - xs.min, height: ys.max - ys.min }
    else
      %w[x y width height].to_h { |name| [name.to_sym, attr(shape, name)] }
    end
  end

  # Only the edges. Marker paths live in <defs> in their own coordinate
  # system, so sweeping every `d=` in the document compared page width
  # against numbers that mean nothing.
  def edge_paths(xml)
    xml.scan(%r{<g id="edge-[^"]*">\s*<path[^>]*\bd="([^"]*)"}).flatten
  end

  # The right edge of the furthest-right box the diagram drew. Node and
  # cluster rects both count; the arrowhead marker in <defs> is a path,
  # so nothing in there is swept up by this.
  def box_right(xml)
    rects = xml.scan(/<rect[^>]*>/)
    return nil if rects.empty?

    rects.map { |r| attr(r, "x") + attr(r, "width") }.max
  end

  # On the DRAWN outline, not the bounding box around it. A circle and a
  # rhombus only touch their bounding box at one point per side, so a
  # box-based check cannot tell a correct anchor from a detached one.
  def on_shape?(shape, x, y)
    case shape
    when /\A<circle/
      cx = attr(shape, "cx")
      cy = attr(shape, "cy")
      (Math.sqrt(((x - cx)**2) + ((y - cy)**2)) - attr(shape, "r")).abs <= 1
    when /\A<polygon/
      pairs = shape[/points="([^"]*)"/, 1].split(/\s+/)
      pts = pairs.map { |pair| pair.split(",").map(&:to_f) }
      edges = pts.each_cons(2).to_a.push([pts.last, pts.first])
      edges.any? { |a, b| on_segment?(a, b, x, y) }
    else
      on_border?(bounds_of(shape), x, y)
    end
  end

  # Within a unit of the segment, by area of the triangle it makes.
  def on_segment?(from, to, x, y)
    len = Math.sqrt(((to[0] - from[0])**2) + ((to[1] - from[1])**2))
    return false if len.zero?

    cross = ((to[0] - from[0]) * (y - from[1])) -
            ((to[1] - from[1]) * (x - from[0]))
    return false if (cross.abs / len) > 1

    # Divided back to a length, so the slop is a unit here as it is on
    # the perpendicular check above rather than a unit squared.
    along = (((x - from[0]) * (to[0] - from[0])) +
             ((y - from[1]) * (to[1] - from[1]))) / len
    along.between?(-1, len + 1)
  end

  def node_shape(xml, id)
    section = xml[%r{<g id="node-#{Regexp.escape(id)}">.*?</g>}m]
    section && section[/<(?:rect|circle|polygon)[^>]*>/]
  end

  def title_of(xml, id)
    xml[/<g id="cluster-#{id}">.*?<text[^>]*>(.*?)<\/text>/m, 1]
  end

  describe "a subgraph" do
    it "draws a cluster" do
      xml = render("flowchart TD\nsubgraph s [Title]\nA --- B\nend\n")

      expect(cluster_ids(xml)).to eq(%w[s])
    end

    it "writes the title on the box" do
      xml = render("flowchart TD\nsubgraph s [Title]\nA --- B\nend\n")

      expect(title_of(xml, "s")).to eq("Title")
    end

    it "falls back to the id for a title" do
      xml = render("flowchart TD\nsubgraph s\nA --- B\nend\n")

      expect(title_of(xml, "s")).to eq("s")
    end

    # mermaid's paint order is cluster, then edges, then nodes. Drawing
    # the box later would hide everything it contains, and drawing the
    # edges last would leave a line lying across the node it ends on.
    # Reading only the first mark passed while the edges came last.
    it "paints behind the edges and the nodes it holds" do
      xml = render("flowchart TD\nsubgraph s [T]\nA --- B\nend\n")
      order = xml.scan(/<g id="(cluster|edge|node)-/).flatten

      expect(order).to eq(%w[cluster edge node node])
    end

    # The whole node, not its top-left corner. A box that stopped short
    # of the right or bottom edge clips what it holds, and testing the
    # origin alone could not see that.
    it "encloses the nodes it holds" do
      xml = render("flowchart TD\nsubgraph s [T]\nA --- B\nend\n")
      outer = box(xml, "s")
      rects = xml.scan(/<g id="node-[^"]+">\s*(<rect[^>]*>)/).flatten

      expect(rects.length).to eq(2)
      rects.each do |rect|
        expect(attr(rect, "x")).to be >= outer[:x]
        expect(attr(rect, "y")).to be >= outer[:y]
        expect(attr(rect, "x") + attr(rect, "width"))
          .to be <= outer[:x] + outer[:width]
        expect(attr(rect, "y") + attr(rect, "height"))
          .to be <= outer[:y] + outer[:height]
      end
    end

    # A long title used to run out past the edge of a box sized only by
    # the one small node inside it. Compared against a short title on the
    # same contents, because the box has to grow for the title alone.
    it "widens for a longer title" do
      short = box(render("flowchart TD\nsubgraph s [T]\nA\nend\n"), "s")
      long = box(
        render("flowchart TD\nsubgraph s [A Really Quite Long Title]\nA\nend\n"), "s"
      )

      expect(long[:width]).to be > short[:width]
    end

    # Inside the box, not on its top edge. A baseline of zero puts a
    # `dominant-baseline: middle` title half outside the box, and every
    # other assertion here still passed with it there.
    it "writes the title inside the box" do
      xml = render("flowchart TD\nsubgraph s [T]\nA\nend\n")
      title = xml[/<g id="cluster-s">.*?(<text[^>]*>)/m, 1]
      outer = box(xml, "s")

      # The literal drop, not just "below the top". A baseline of 1 still
      # puts half a 14px middle-baselined title outside the box, and
      # "greater than the top edge" was happy with it.
      expect(attr(title, "y") - outer[:y]).to eq(20)
      expect(attr(title, "y")).to be < outer[:y] + outer[:height]
    end

    # The title is written inside the box, so the contents have to start
    # below it or the two are drawn on top of each other.
    it "keeps the nodes clear of the title" do
      xml = render("flowchart TD\nsubgraph s [T]\nA\nend\n")
      title = xml[/<g id="cluster-s">.*?(<text[^>]*>)/m, 1]
      node = xml[/<g id="node-A">\s*<rect[^>]*>/]

      expect(attr(node, "y")).to be > attr(title, "y")
    end

    # A box drawn no bigger than its contents clips them.
    it "is wider than the nodes inside it" do
      xml = render("flowchart TD\nsubgraph s [T]\nA\nend\n")
      outer = box(xml, "s")
      inner = xml[/<g id="node-A">\s*<rect[^>]*>/]

      expect(outer[:width]).to be > attr(inner, "width")
    end

    # mmdc accepts the source and draws nothing for it.
    it "draws no box when it holds nothing" do
      xml = render("flowchart TD\nsubgraph s [T]\nend\nZ\n")

      expect(cluster_ids(xml)).to be_empty
    end

    it "leaves a diagram without one untouched" do
      xml = render("flowchart TD\nA --> B\n")

      expect(cluster_ids(xml)).to be_empty
    end
  end

  describe "nested subgraphs" do
    let(:source) do
      "flowchart TD\nsubgraph outer [O]\nsubgraph inner [I]\nA --- B\nend\nend\n"
    end

    # Outermost first, so the inner box lands on top of the one holding it.
    it "draws the outer box first" do
      expect(cluster_ids(render(source))).to eq(%w[outer inner])
    end

    it "sits the inner box inside the outer one" do
      xml = render(source)
      outer = box(xml, "outer")
      inner = box(xml, "inner")

      expect(inner[:x]).to be >= outer[:x]
      expect(inner[:y]).to be >= outer[:y]
      expect(inner[:x] + inner[:width]).to be <= outer[:x] + outer[:width]
      expect(inner[:y] + inner[:height]).to be <= outer[:y] + outer[:height]
    end
  end

  describe "a subgraph holding only an empty subgraph" do
    # mmdc draws the outer box and drops the inner one. Only the innermost
    # empty box disappears: `a { b { c {} } }` draws a and b.
    it "draws the outer box and not the empty one" do
      xml = render("flowchart TB\nsubgraph a\nsubgraph b\nend\nend\nz\n")

      expect(cluster_ids(xml)).to eq(%w[a])
    end

    it "draws every box above the innermost empty one" do
      source = "flowchart TB\nsubgraph a\nsubgraph b\nsubgraph c\n" \
               "end\nend\nend\nz\n"

      expect(cluster_ids(render(source))).to eq(%w[a b])
    end

    # There is nothing inside to measure, and a box with no size is a box
    # nobody can see.
    it "gives it a size anyway" do
      xml = render("flowchart TB\nsubgraph a\nsubgraph b\nend\nend\nz\n")
      outer = box(xml, "a")

      expect(outer[:width]).to be > 0
      expect(outer[:height]).to be > 0
    end
  end

  describe "sibling subgraphs" do
    let(:source) do
      "flowchart TD\nsubgraph a [A]\nX\nend\nsubgraph b [B]\nY\nend\n"
    end

    it "draws both" do
      expect(cluster_ids(render(source))).to eq(%w[a b])
    end

    it "keeps them apart" do
      xml = render(source)
      first = box(xml, "a")
      second = box(xml, "b")

      expect(second[:x]).to be >= first[:x] + first[:width]
    end
  end

  # Clusters made the grid size-aware, and a cell that shrank to fit would
  # have moved every diagram in the project. The floor is what keeps them
  # still, so these are the coordinates from before that change.
  describe "a diagram with no subgraph" do
    def spots(xml)
      xml.scan(/<g id="node-([^"]+)">\s*<rect[^>]*>/).flatten.map do |id|
        rect = xml[/<g id="node-#{id}">\s*<rect[^>]*>/]
        [id, attr(rect, "x"), attr(rect, "y")]
      end
    end

    it "keeps the grid pitch it has always had" do
      found = spots(render("flowchart TD\nA\nB\nC\nD\n"))

      expect(found).to eq([["A", 50.0, 50.0], ["B", 300.0, 50.0],
                           ["C", 550.0, 50.0], ["D", 50.0, 250.0]])
    end
  end

  # The layout marks a box; the renderer has to read the same mark. When
  # the two disagreed about what a box was, c4, class and er diagrams —
  # which nest children of their own — were resized like clusters.
  describe "a nested child with no cluster mark" do
    let(:renderer) do
      Sirena::Renderer::FlowchartRenderer.new(
        theme: Sirena::Theme::Registry.get(:default)
      )
    end

    let(:graph) do
      { id: "g", edges: [],
        children: [{ id: "outer", x: 10, y: 10, width: 200, height: 100,
                     children: [{ id: "inner", x: 5, y: 5, width: 40,
                                  height: 20, labels: [{ text: "I" }],
                                  metadata: { shape: "rect" } }] }] }
    end

    # Neither a box nor a node: it is a grouping shell, and only what it
    # holds is drawn. Checking the box alone left the node half untested.
    it "draws no box and no node for it" do
      xml = renderer.render(graph).to_xml

      expect(xml).not_to include("cluster-outer")
      expect(xml).not_to include("node-outer")
    end

    it "still draws what it holds, offset by it" do
      xml = renderer.render(graph).to_xml
      rect = xml[/<g id="node-inner">\s*<rect[^>]*>/]

      # The container sits at 10,10 and the node at 5,5 inside it.
      expect([attr(rect, "x"), attr(rect, "y")]).to eq([15.0, 15.0])
    end
  end

  # mmdc 11.12.0 joins the two cluster boxes and draws no node for
  # either id. Both ends used to become invented leaves, and the edge
  # was drawn between them instead of between the boxes.
  describe "an edge that names a subgraph" do
    let(:source) do
      "flowchart TD\nsubgraph one [O]\nA\nend\n" \
        "subgraph two [T]\nB\nend\none --> two\n"
    end

    def node_ids(xml)
      xml.scan(/<g id="node-([^"]+)">/).flatten
    end

    it "draws both boxes and no node for their ids" do
      xml = render(source)

      expect(cluster_ids(xml)).to eq(%w[one two])
      expect(node_ids(xml)).to eq(%w[A B])
    end

    it "still draws the edge" do
      expect(render(source)).to include('id="edge-one_to_two"')
    end

    # ON the borders, not merely somewhere inside. A cluster is painted
    # behind the edges, so a line starting at its centre is drawn right
    # across the box — and "inside the box" is also true of that centre,
    # which is why the weaker test could not see it.
    it "runs from the border of one box to the border of the other" do
      xml = render(source)
      path = xml[/<g id="edge-one_to_two">\s*<path[^>]*\bd="([^"]*)"/, 1]
      sx, sy, tx, ty = path.scan(/-?\d+(?:\.\d+)?/).map(&:to_f)

      expect(on_border?(box(xml, "one"), sx, sy)).to be(true)
      expect(on_border?(box(xml, "two"), tx, ty)).to be(true)
    end

    # The two boxes sit side by side, so the line leaves the right edge
    # of the first and arrives at the left edge of the second.
    it "leaves the near side of each box" do
      xml = render(source)
      path = xml[/<g id="edge-one_to_two">\s*<path[^>]*\bd="([^"]*)"/, 1]
      sx, _sy, tx, _ty = path.scan(/-?\d+(?:\.\d+)?/).map(&:to_f)
      first = box(xml, "one")
      second = box(xml, "two")

      expect(sx).to be_within(0.01).of(first[:x] + first[:width])
      expect(tx).to be_within(0.01).of(second[:x])
    end

    # One box holds the other, so trimming each end independently put
    # both of them past the other and drew the arrow backwards.
    it "still points at the target when one box holds the other" do
      xml = render("flowchart TD\nsubgraph outer\nsubgraph inner\nA\n" \
                   "end\nend\nouter --> inner\n")
      path = xml[/<g id="edge-outer_to_inner">\s*<path[^>]*\bd="([^"]*)"/, 1]
      sx, sy, tx, ty = path.scan(/-?\d+(?:\.\d+)?/).map(&:to_f)

      # The line has to run the same way the boxes do.
      expect([tx - sx, ty - sy].map { |d| d <=> 0 })
        .to eq(centre_gap(box(xml, "outer"), box(xml, "inner")))
    end

    it "routes a contained parent/child edge between both borders" do
      xml = render("flowchart TD\nsubgraph outer\nsubgraph inner\nA\n" \
                   "end\nend\nouter --> inner\n")
      path = xml[/<g id="edge-outer_to_inner">\s*<path[^>]*\bd="([^"]*)"/, 1]
      points = path.scan(/-?\d+(?:\.\d+)?/).map(&:to_f).each_slice(2).to_a

      expect(on_border?(box(xml, "outer"), *points.first)).to be(true)
      expect(on_border?(box(xml, "inner"), *points.last)).to be(true)
    end

    # The label used to be measured from the two centres while the path
    # was drawn from the borders, which left it sitting inside the box
    # the line no longer starts in.
    it "puts a label on the line it drew" do
      xml = render("flowchart TD\nsubgraph one [A Fairly Long Title]\nA\n" \
                   "end\none -->|lbl| Z\n")
      group = xml[%r{<g id="edge-one_to_Z">.*?</g>}m]
      path = group[/<path[^>]*\bd="([^"]*)"/, 1]
      sx, sy, tx, ty = path.scan(/-?\d+(?:\.\d+)?/).map(&:to_f)
      label_x = group[/<text[^>]*\bx="([^"]*)"/, 1].to_f
      label_y = group[/<text[^>]*\by="([^"]*)"/, 1].to_f

      # The midpoint of the run, exactly. "Somewhere along it" was also
      # true of the old label measured from the two centres.
      expect(label_x).to be_within(0.01).of((sx + tx) / 2)
      expect(label_y + 5).to be_within(0.01).of((sy + ty) / 2)
    end

    # Two decimals at most. The trimming arithmetic lands on seventeen
    # digits behind the point, and this output goes into a document.
    it "does not write full float precision into the path" do
      # A crossing that does NOT land on a whole number. Two boxes side
      # by side trim to exact coordinates, so they never showed this.
      xml = render("flowchart TD\nsubgraph one [A Fairly Long Title]\nA\n" \
                   "end\none --> Z\n")
      path = xml[/<g id="edge-one_to_Z">\s*<path[^>]*\bd="([^"]*)"/, 1]

      # The whole path. Counting decimal places only proves the number is
      # no longer than two, which rounding to one or to nothing also
      # satisfies.
      expect(path).to eq("M 300.0 93.98 L 68.5 67.0")
    end

    it "joins a box to a plain node" do
      xml = render("flowchart TD\nsubgraph one [O]\nA\nend\none --> Z\n")

      expect(cluster_ids(xml)).to eq(%w[one])
      expect(node_ids(xml)).to contain_exactly("A", "Z")
      expect(xml).to include('id="edge-one_to_Z"')
    end
  end

  # Every node in the diagram can name a box, leaving the model with
  # clusters and no nodes at all. `valid?` insisted on a node, so this
  # raised "Invalid diagram" instead of drawing anything.
  describe "a diagram that is only boxes" do
    let(:source) do
      "flowchart TD\nsubgraph one\nsubgraph e1\nend\nend\n" \
        "subgraph two\nsubgraph e2\nend\nend\none --> two\n"
    end

    it "renders" do
      expect { render(source) }.not_to raise_error
    end

    it "draws both boxes and the edge between them" do
      xml = render(source)

      expect(cluster_ids(xml)).to eq(%w[one two])
      expect(xml).to include('id="edge-one_to_two"')
    end
  end

  # Trimming touches the renderer every diagram goes through, so these
  # drive it directly with coordinates the fallback grid never makes.
  describe "an edge drawn straight onto the renderer" do
    let(:renderer) do
      Sirena::Renderer::FlowchartRenderer.new(
        theme: Sirena::Theme::Registry.get(:default)
      )
    end

    def leaf(id, spot)
      { id: id, labels: [{ text: id }], metadata: { shape: "rect" } }
        .merge(spot)
    end

    def cluster(id, spot)
      { id: id, children: [], labels: [{ text: id, width: 4, height: 4 }],
        metadata: { cluster: true } }.merge(spot)
    end

    def path_of(graph, edge_id)
      xml = renderer.render(graph).to_xml
      xml[/<g id="edge-#{edge_id}">\s*<path[^>]*\bd="([^"]*)"/, 1]
    end

    # An end nothing trimmed has to come back exactly as it went in.
    # Rounding it moved every ordinary edge in the project.
    it "leaves a node edge on the coordinates it was given" do
      graph = { id: "g",
                children: [leaf("a", x: 10.740735, y: 21.660485,
                                     width: 100.0, height: 50.0),
                           leaf("b", x: 250.7037, y: 89.814705,
                                     width: 100.0, height: 50.0)],
                edges: [{ id: "a_to_b", sources: %w[a], targets: %w[b] }] }

      expect(path_of(graph, "a_to_b"))
        .to eq("M 60.740735 46.660485 L 300.7037 114.814705")
    end

    # Two DIFFERENT boxes can share a centre too. There is no straight
    # direction to trim in that case, so the route must bend visibly.
    it "loops two different boxes that share a centre" do
      graph = { id: "g",
                children: [cluster("s", x: 0.0, y: 0.0,
                                        width: 100.0, height: 100.0),
                           cluster("t", x: 25.0, y: 25.0,
                                        width: 50.0, height: 50.0)],
                edges: [{ id: "s_to_t", sources: %w[s], targets: %w[t] }] }
      points = path_of(graph, "s_to_t").scan(/-?\d+(?:\.\d+)?/)
        .map(&:to_f).each_slice(2).to_a

      expect(points.size).to be > 2
      expect(points.uniq.size).to be > 1
    end

    it "keeps a zero-size coincident edge nonzero" do
      graph = { id: "g",
                children: [cluster("s", x: 10.0, y: 10.0,
                                        width: 0.0, height: 0.0),
                           cluster("t", x: 10.005, y: 10.005,
                                        width: 0.0, height: 0.0)],
                edges: [{ id: "s_to_t", sources: %w[s], targets: %w[t] }] }
      points = path_of(graph, "s_to_t").scan(/-?\d+(?:\.\d+)?/)
        .map(&:to_f).each_slice(2).to_a

      expect(points.size).to be > 2
      expect(points.each_cons(2).none? { |from, to| from == to }).to be(true)
    end

    # Two boxes that meet add up to exactly one run between their
    # centres, and the arithmetic lands a hair under it. Without the
    # slack both ends trim to the same point and the edge vanishes.
    #
    # Fractional sizes on purpose. `Layout::Fallback` rounds a cluster to
    # whole units and every touching integer pair sums to exactly 1.0, so
    # this models what the layout engine will hand the renderer instead.
    it "keeps a length between two boxes that touch" do
      graph = { id: "g",
                children: [cluster("s", x: 0.0, y: 0.0,
                                        width: 10.1, height: 4.0),
                           cluster("t", x: 10.1, y: 0.0,
                                        width: 11.0, height: 4.0)],
                edges: [{ id: "s_to_t", sources: %w[s], targets: %w[t] }] }
      drawn = path_of(graph, "s_to_t").scan(/-?\d+(?:\.\d+)?/).map(&:to_f)
      sx, _sy, tx, _ty = drawn

      expect(tx).to be > sx
    end
  end

  # `s --> s` put both ends on the same point: the path came out
  # `M 88 104 L 88 104`, zero units long, carrying an arrowhead on
  # nothing. mmdc draws a visible loop for a box of either kind.
  describe "an edge from a box to itself" do
    let(:source) { "flowchart TD\nsubgraph s\nA\nend\ns --> s\n" }

    def loop_points(xml)
      d = xml[/<g id="edge-[^"]*">\s*<path[^>]*\bd="([^"]*)"/, 1]
      d.scan(/-?\d+(?:\.\d+)?/).map(&:to_f).each_slice(2).to_a
    end

    # The defect was a path of ZERO length. The loop closes on itself by
    # design, so length is what to assert, not distinct ends.
    it "draws a path with length" do
      points = loop_points(render(source))

      expect(points.uniq.size).to be > 1
    end

    it "bends, rather than running straight between its ends" do
      expect(loop_points(render(source)).size).to be > 2
    end

    it "starts and finishes on the cluster border, and stands clear of it" do
      xml = render(source)
      outer = box(xml, "s")
      points = loop_points(xml)

      expect(on_border?(outer, *points.first)).to be(true)
      expect(on_border?(outer, *points.last)).to be(true)
      expect(points.map(&:first).max).to be > outer[:x] + outer[:width]
    end

    it "uses distinct border endpoints for a nonzero cluster self-edge" do
      xml = render(source)
      outer = box(xml, "s")
      points = loop_points(xml)

      expect(points.uniq.size).to be > 1
      expect(points.first).not_to eq(points.last)
      expect(on_border?(outer, *points.first)).to be(true)
      expect(on_border?(outer, *points.last)).to be(true)
    end

    # The loop reaches past the box it leaves, so the page has to still
    # cover it. It rides the slack the sizing already carries — and the
    # rightmost box is the one that tests it, so a node on the right
    # edge matters as much as a cluster.
    it "stays inside the page" do
      ["flowchart TD\nsubgraph s\nA\nend\ns --> s\n",
       "flowchart LR\nA --> B\nB --> B\n"].each do |src|
        xml = render(src)
        width = xml[/<svg[^>]*\bwidth="([^"]*)"/, 1].to_f
        height = xml[/<svg[^>]*\bheight="([^"]*)"/, 1].to_f
        pts = edge_paths(xml).flat_map do |d|
          d.scan(/-?\d+(?:\.\d+)?/).map(&:to_f).each_slice(2).to_a
        end
        xs = pts.map(&:first)
        ys = pts.map(&:last)

        expect(pts).not_to be_empty, "no edge path drawn for #{src}"

        aggregate_failures(src) do
          # The loop is the thing that reaches furthest right, so a
          # source whose loop vanished would not be testing the page.
          expect(xs.max).to be > box_right(xml)
          expect(xs.max).to be <= width
          expect(xs.min).to be >= 0
          # The loop spreads vertically too, so the page has to hold
          # that as well - the dimension this geometry actually moved.
          expect(ys.max).to be <= height
          expect(ys.min).to be >= 0
        end
      end
    end

    # The same collapse, reached through a node instead. An empty
    # subgraph named by an edge is drawn as a plain node, so `s --> s`
    # arrives here rather than at the cluster branch above.
    # Every shape, because the ends anchor to the middle of the right
    # side — the one point a circle, a rhombus and a hexagon all reach.
    # Anchoring a third of the way down put the loop on the bounding box
    # instead, eight units clear of a rhombus's drawn edge.
    {
      "an empty subgraph drawn as a node" => "subgraph s\nend\ns --> s",
      "a plain rectangle" => "A --> A",
      "a rounded rectangle" => "A(A) --> A",
      "a stadium" => "A([A]) --> A",
      "a circle" => "A((A)) --> A",
      "a rhombus" => "A{A} --> A",
      "a hexagon" => "A{{A}} --> A"
    }.each do |shape, body|
      it "anchors the loop for #{shape} on its drawn outline" do
        xml = render("flowchart TD\n#{body}\n")
        points = loop_points(xml)
        id = body.start_with?("subgraph") ? "s" : "A"
        rect = node_rect(xml, id)
        drawn = node_shape(xml, id)

        expect(rect).not_to be_nil
        expect(drawn).not_to be_nil
        # Out and back: two ends on the outline, two bends clear of it.
        expect(points.size).to eq(4)
        # On the OUTLINE. A circle and a rhombus meet their bounding box
        # at one point per side, so anchoring anywhere else leaves the
        # loop hanging in space beside the shape.
        expect(on_shape?(drawn, *points.first)).to be(true)
        expect(on_shape?(drawn, *points.last)).to be(true)
        # It has to LEAVE the box, or it is a chord across the inside.
        expect(points.map(&:first).max).to be > rect[:x] + rect[:width]
      end
    end

    # Nothing in the diagram may still be drawn as a zero-length path.
    # The edge has to be THERE as well: an omitted path has no zero
    # length either, and would sail through on its own.
    it "leaves no zero-length path anywhere" do
      ["flowchart TD\nA --> A\n",
       "flowchart TD\nsubgraph s\nA\nend\ns --> s\n",
       "flowchart TD\nsubgraph s\nend\ns --> s\n"].each do |src|
        xml = render(src)
        drawn = edge_paths(xml)

        nums = drawn.first.to_s.scan(/-?\d+(?:\.\d+)?/).map(&:to_f)
        points = nums.each_slice(2).to_a

        aggregate_failures(src) do
          expect(drawn.size).to eq(1)
          # No zero-length SEGMENT, not merely no zero-length path: a
          # repeated point anywhere along the run draws the same
          # nothing, and matching one exact serialisation missed it.
          expect(points.each_cons(2).any? { |a, b| a == b }).to be(false)
          expect(points.size).to be > 1
        end
      end
    end

    # A control: two different boxes still get a straight run. It does
    # not pin the choice of IDENTITY over coinciding centres — these two
    # centres differ anyway. The renderer spec below does that.
    it "leaves an edge between two boxes straight" do
      xml = render("flowchart TD\nsubgraph s\nA\nend\n" \
                   "subgraph t\nB\nend\ns --> t\n")

      expect(loop_points(xml).size).to eq(2)
    end
  end

  describe "the page" do
    # The box can reach past every node in it, so measuring the nodes
    # alone cropped the cluster off the right edge.
    it "is wide enough for the box" do
      xml = render("flowchart TD\nsubgraph s [A Fairly Long Title]\nA\nend\n")
      width = xml[/<svg[^>]*\bwidth="([^"]*)"/, 1].to_f
      outer = box(xml, "s")

      expect(width).to be >= outer[:x] + outer[:width]
    end
  end
end
