# frozen_string_literal: true

require "spec_helper"

# Pure geometry/XML helpers plus two that need example state (`render`
# reads `described_class`, `expect_exterior_route` uses `expect`/
# `aggregate_failures`): all single-user (this file only), so they live in
# one module at the file top and are `include`d into the describe rather
# than split module_function/included -- nothing here is called at
# describe-body level to generate examples, only from inside `it` blocks.
module FlowchartClusterSpecHelpers
  def render(source)
    described_class.new.render(source)
  end

  def render_graph(graph)
    scene = Sirena::Layout::Flowchart.from_graph(graph, theme: renderer.theme)
    renderer.render(scene)
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
    [axis_gap(from, to, :x, :width), axis_gap(from, to, :y, :height)]
      .map { |delta| delta <=> 0 }
  end

  def axis_gap(from, to, origin, size)
    (to[origin] + (to[size] / 2)) - (from[origin] + (from[size] / 2))
  end

  def inside?(rect, x_pos, y_pos)
    x_pos.between?(rect[:x], rect[:x] + rect[:width]) &&
      y_pos.between?(rect[:y], rect[:y] + rect[:height])
  end

  # On one of the four edges of the rectangle. A unit of slack, because
  # the crossing is rounded to two decimals and the box coordinates come
  # back out of the XML as text.
  def on_border?(rect, x_pos, y_pos)
    edges = edges_of(rect)
    left, right, top, bottom = edges
    return false unless x_pos.between?(left - 1, right + 1)
    return false unless y_pos.between?(top - 1, bottom + 1)

    border_gap(x_pos, y_pos, edges) <= 1
  end

  def border_gap(x_pos, y_pos, edges)
    left, right, top, bottom = edges
    [(x_pos - left).abs, (x_pos - right).abs,
     (y_pos - top).abs, (y_pos - bottom).abs].min
  end

  # left, right, top, bottom
  def edges_of(rect)
    [rect[:x], rect[:x] + rect[:width],
     rect[:y], rect[:y] + rect[:height]]
  end

  def exactly_on_border?(rect, x_pos, y_pos)
    left = rect[:x].to_i.to_f
    top = rect[:y].to_i.to_f
    bounds = [left, left + rect[:width].to_i, top, top + rect[:height].to_i]
    # Square corners: the rounded-side test with a zero radius.
    on_rounded_side?(bounds, x_pos, y_pos, [0, 0])
  end

  def on_rounded_border?(rect, x_pos, y_pos, radius)
    bounds = edges_of(rect)
    # SVG clamps rx by half the width and ry by half the height,
    # independently, so a short wide box gets an elliptical corner.
    radii = [rect[:width], rect[:height]]
      .map { |size| [radius, size / 2.0].min }

    on_rounded_side?(bounds, x_pos, y_pos, radii) ||
      on_rounded_arc?(bounds, x_pos, y_pos, radii)
  end

  def on_rounded_side?(bounds, x_pos, y_pos, radii)
    left, right, top, bottom = bounds
    rx, ry = radii
    horizontal = [top, bottom].include?(y_pos) &&
      x_pos.between?(left + rx, right - rx)
    vertical = [left, right].include?(x_pos) &&
      y_pos.between?(top + ry, bottom - ry)
    horizontal || vertical
  end

  def on_rounded_arc?(bounds, x_pos, y_pos, radii)
    left, right, top, bottom = bounds
    centre_x = corner_centre(x_pos, left, right, radii[0])
    centre_y = corner_centre(y_pos, top, bottom, radii[1])
    return false unless centre_x && centre_y && radii.all?(&:positive?)

    ellipse = ellipse_value(x_pos - centre_x, y_pos - centre_y, radii)
    ellipse.between?(1.0, 1.01)
  end

  def ellipse_value(delta_x, delta_y, radii)
    ((delta_x / radii[0])**2) + ((delta_y / radii[1])**2)
  end

  # nil for a coordinate in neither corner band, so a mid-box point is
  # never measured against a corner it is nowhere near.
  def corner_centre(coordinate, near, far, radius)
    return near + radius if coordinate.between?(near, near + radius)

    far - radius if coordinate.between?(far - radius, far)
  end

  # Whether an orthogonal segment enters the open interior. Contact with
  # the border is allowed; a diagonal is rejected because exterior routes
  # are deliberately orthogonal.
  def crosses_face?(rect, from, to)
    left, right, top, bottom = edges_of(rect)

    if from[0] == to[0]
      crosses_span?(from[0], [from[1], to[1]], [left, right], [top, bottom])
    elsif from[1] == to[1]
      crosses_span?(from[1], [from[0], to[0]], [top, bottom], [left, right])
    else
      true
    end
  end

  # `fixed` is the segment's constant coordinate and must sit strictly
  # inside `across`; the segment's `ends` must overlap the open `through`.
  def crosses_span?(fixed, ends, across, through)
    low, high = ends.minmax
    fixed.between?(*across) && !across.include?(fixed) &&
      low < through[1] && high > through[0]
  end

  def path_points(path)
    path.scan(/-?\d+(?:\.\d+)?/).map(&:to_f).each_slice(2).to_a
  end

  def expect_exterior_route(document, source, target, name)
    route = exterior_route(document)

    aggregate_failures(name) do
      expect_route_ends(route[:points], source, target, name)
      expect_route_clear_of(route[:points], [source, target], name)
      expect_route_inside_canvas(route, document.view_box, name)
      expect(route[:label]).to eq(route[:expected_label]), name
    end
  end

  def exterior_route(document)
    xml = document.to_xml
    path = xml[/<g id="edge-s_to_t">\s*<path[^>]*\bd="([^"]*)"/, 1]
    points = path_points(path)
    { points: points,
      label: label_position(xml[%r{<g id="edge-s_to_t">.*?</g>}m]),
      expected_label: midpoint(points[1], points[2]) }
  end

  def label_position(group)
    [group[/<text[^>]*\bx="([^"]*)"/, 1].to_f,
     group[/<text[^>]*\by="([^"]*)"/, 1].to_f + 5]
  end

  def midpoint(from, to)
    [(from[0] + to[0]) / 2, (from[1] + to[1]) / 2]
  end

  def expect_route_ends(points, source, target, name)
    expect(points.size).to eq(4), name
    expect(exactly_on_border?(source, *points.first)).to be(true), name
    expect(exactly_on_border?(target, *points.last)).to be(true), name
  end

  def expect_route_clear_of(points, faces, name)
    clear = points.each_cons(2).none? do |from, to|
      faces.any? { |face| crosses_face?(face, from, to) }
    end
    expect(clear).to be(true), name
  end

  def expect_route_inside_canvas(route, view_box, name)
    min_x, min_y, width, height = view_box.split.map(&:to_f)
    inside = route[:points].all? do |x_pos, y_pos|
      x_pos.between?(min_x, min_x + width) &&
        y_pos.between?(min_y, min_y + height)
    end
    expect(inside).to be(true), name
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
    when /\A<circle/ then circle_bounds(shape)
    when /\A<polygon/ then polygon_bounds(shape)
    else
      %w[x y width height].to_h { |name| [name.to_sym, attr(shape, name)] }
    end
  end

  def circle_bounds(shape)
    radius = attr(shape, "r")
    { x: attr(shape, "cx") - radius, y: attr(shape, "cy") - radius,
      width: radius * 2, height: radius * 2 }
  end

  def polygon_points(shape)
    pairs = shape[/points="([^"]*)"/, 1].split(/\s+/)
    pairs.map { |pair| pair.split(",").map(&:to_f) }
  end

  def polygon_bounds(shape)
    xs, ys = polygon_points(shape).transpose
    { x: xs.min, y: ys.min,
      width: xs.max - xs.min, height: ys.max - ys.min }
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

  # Same, for the bottom edge — the axis a TD self-loop reaches past
  # instead of the right edge an LR one does.
  def box_bottom(xml)
    rects = xml.scan(/<rect[^>]*>/)
    return nil if rects.empty?

    rects.map { |r| attr(r, "y") + attr(r, "height") }.max
  end

  # On the DRAWN outline, not the bounding box around it. A circle and a
  # rhombus only touch their bounding box at one point per side, and a
  # rounded rectangle only along the flat middle of each face, so a
  # box-based check cannot tell a correct anchor from a detached one.
  def on_shape?(shape, x_pos, y_pos)
    case shape
    when /\A<circle/ then on_circle?(shape, x_pos, y_pos)
    when /\A<polygon/ then on_polygon?(shape, x_pos, y_pos)
    when /(?<![-\w])rx="/
      radius = attr(shape, "rx")
      rounded_outline_gap(bounds_of(shape), radius, x_pos, y_pos) <= 1

    else
      on_border?(bounds_of(shape), x_pos, y_pos)
    end
  end

  def on_circle?(shape, x_pos, y_pos)
    centre_x = attr(shape, "cx")
    centre_y = attr(shape, "cy")
    distance = Math.sqrt(((x_pos - centre_x)**2) + ((y_pos - centre_y)**2))
    (distance - attr(shape, "r")).abs <= 1
  end

  def on_polygon?(shape, x_pos, y_pos)
    pts = polygon_points(shape)
    edges = pts.each_cons(2).to_a.push([pts.last, pts.first])
    edges.any? { |a, b| on_segment?(a, b, x_pos, y_pos) }
  end

  # How far a point sits from a rounded rectangle's outline, in units, so
  # the one-unit tolerance the circle and polygon branches use carries
  # over. `on_border?` measures the four straight sides only, so it reads
  # a corner-arc anchor as detached: a rounded 37x34 node here carries a
  # 17-unit radius, which leaves three units of flat bottom, and every
  # self-loop end lands on the arc rather than in that gap.
  #
  # Signed distance to a rounded box: fold the point into one quadrant,
  # take the radius out of the half extents, measure to the inset box,
  # then put the radius back.
  def rounded_outline_gap(rect, radius, x_pos, y_pos)
    inset_x = axis_inset(x_pos, rect[:x], rect[:width], radius)
    inset_y = axis_inset(y_pos, rect[:y], rect[:height], radius)
    outside = outside_length(inset_x, inset_y)
    (outside + [inset_x, inset_y].max.clamp(..0) - radius).abs
  end

  def axis_inset(point, origin, size, radius)
    half = size / 2.0
    (point - (origin + half)).abs - (half - radius)
  end

  def outside_length(first, second)
    Math.sqrt(([first, 0].max**2) + ([second, 0].max**2))
  end

  # Within a unit of the segment, by area of the triangle it makes.
  def on_segment?(from, to, x_pos, y_pos)
    segment = vector(from, to)
    len = vector_length(segment)
    return false if len.zero?

    offset = vector(from, [x_pos, y_pos])
    return false if (cross_product(segment, offset).abs / len) > 1

    # Divided back to a length, so the slop is a unit here as it is on
    # the perpendicular check above rather than a unit squared.
    along = dot_product(offset, segment) / len
    along.between?(-1, len + 1)
  end

  def vector(from, to)
    [to[0] - from[0], to[1] - from[1]]
  end

  def vector_length(vec)
    Math.sqrt((vec[0]**2) + (vec[1]**2))
  end

  def cross_product(left, right)
    (left[0] * right[1]) - (left[1] * right[0])
  end

  def dot_product(left, right)
    (left[0] * right[0]) + (left[1] * right[1])
  end

  def node_shape(xml, id)
    section = xml[%r{<g id="node-#{Regexp.escape(id)}">.*?</g>}m]
    section && section[/<(?:rect|circle|polygon)[^>]*>/]
  end

  def title_of(xml, id)
    xml[/<g id="cluster-#{id}">.*?<text[^>]*>(.*?)<\/text>/m, 1]
  end

  # Clusters made the grid size-aware, and a cell that shrank to fit would
  # have moved every diagram in the project. Used by "a diagram with no
  # subgraph" only.
  def spots(xml)
    xml.scan(/<g id="node-([^"]+)">\s*<rect[^>]*>/).flatten.map do |id|
      rect = xml[/<g id="node-#{id}">\s*<rect[^>]*>/]
      [id, attr(rect, "x"), attr(rect, "y")]
    end
  end

  # Used by "an edge that names a subgraph" only.
  def node_ids(xml)
    xml.scan(/<g id="node-([^"]+)">/).flatten
  end

  # The following are used by "an edge drawn straight onto the renderer"
  # only.
  def leaf(id, spot)
    { id: id, labels: [{ text: id }], metadata: { shape: "rect" } }
      .merge(spot)
  end

  def cluster(id, spot)
    { id: id, children: [], labels: [{ text: id, width: 4, height: 4 }],
      metadata: { cluster: true } }.merge(spot)
  end

  def path_of(graph, edge_id)
    xml = render_graph(graph).to_xml
    xml[/<g id="edge-#{edge_id}">\s*<path[^>]*\bd="([^"]*)"/, 1]
  end

  def graph_linking(first, second)
    edge_id = "#{first[:id]}_to_#{second[:id]}"
    { id: "g", children: [first, second],
      edges: [{ id: edge_id, sources: [first[:id]],
                targets: [second[:id]] }] }
  end

  def contained_arrow_graph(from_id, to_id)
    leaf_node, cluster_node = contained_node_and_cluster
    { id: "g", children: [leaf_node, cluster_node],
      edges: [{ id: "#{from_id}_to_#{to_id}", sources: [from_id],
                targets: [to_id], metadata: { arrow_type: "arrow" } }] }
  end

  def outside_edge
    { labels: [{ text: "outside", width: 40.0, height: 10.0 }],
      sections: [{ bendPoints: [{ x: 60.0, y: 60.0 },
                                { x: 90.0, y: 60.0 }] }] }
  end

  def graph_between(source, target, edge = {})
    { id: "g", children: [source, target],
      edges: [{ id: "s_to_t", sources: %w[s], targets: %w[t] }.merge(edge)] }
  end

  def cluster_pair(source_at, target_at)
    [cluster("s", x: source_at[0], y: source_at[1],
                  width: 100.0, height: 100.0),
     cluster("t", x: target_at[0], y: target_at[1],
                  width: 100.0, height: 100.0)]
  end

  def cross_cluster_pair(reverse: false, offset: 0.0)
    horizontal = { x: 0.0, y: 25.0, width: 100.0, height: 50.0 }
    vertical = { x: 25.0 + offset, y: 0.0, width: 50.0, height: 100.0 }
    source, target = reverse ? [vertical, horizontal] : [horizontal, vertical]

    [cluster("s", source), cluster("t", target)]
  end

  def asymmetric_cluster_pair(rotated: false, reverse: false)
    boxes = if rotated
              [{ x: 0.0, y: 40.0, width: 40.0, height: 40.0 },
               { x: 20.0, y: 0.0, width: 40.0, height: 160.0 }]
            else
              [{ x: 80.0, y: 0.0, width: 40.0, height: 40.0 },
               { x: 0.0, y: 20.0, width: 160.0, height: 40.0 }]
            end
    source, target = reverse ? boxes.reverse : boxes
    [cluster("s", source), cluster("t", target)]
  end

  # A node can sit inside the cluster its own edge names — mermaid
  # draws that from a bare node under a subgraph header. The head used
  # to read its approach off the OTHER end's raw centre, which ignores
  # that A sits inside s: the path left through the cluster's TOP face
  # (the only way out `EdgeRouter` found), while the head — aimed at
  # A's centre, which sits BELOW the cluster's own centre — landed on
  # the BOTTOM face instead. The two must agree on which face, because
  # they are the same drawn line.
  def contained_node_and_cluster
    [leaf("a", x: 70.0, y: 104.0, width: 37.0, height: 34.0),
     cluster("s", x: 50.0, y: 50.0, width: 77.0, height: 108.0)]
  end

  def edge_geometry(xml, edge_id)
    group = xml[%r{<g id="edge-#{edge_id}">.*?</g>}m]
    path_end = path_points(group[/<path[^>]*\bd="([^"]*)"/, 1]).last
    head_tip = group[/<polygon[^>]*\bpoints="([^"]*)"/, 1]
      .split.first.split(",").map(&:to_f)
    [path_end, head_tip]
  end

  # The shoelace formula. Three DISTINCT points can still be
  # collinear — a head with two coincident vertices and one apart from
  # them has two unique points, which `.uniq.size > 1` cannot tell
  # from a real triangle. Area is what actually says the head has a
  # visible shape.
  def triangle_area(apex, left, right)
    cross_product(vector(apex, left), vector(apex, right)).abs / 2.0
  end

  def edge_d(xml, edge_id)
    xml[/<g id="edge-#{edge_id}">\s*<path[^>]*\bd="([^"]*)"/, 1]
  end

  def edge_numbers(xml, edge_id)
    edge_d(xml, edge_id).scan(/-?\d+(?:\.\d+)?/).map(&:to_f)
  end

  def svg_dimension(xml, name)
    xml[/<svg[^>]*\b#{name}="([^"]*)"/, 1].to_f
  end

  def label_xy(group)
    [group[/<text[^>]*\bx="(-?[\d.]+)"/, 1].to_f,
     group[/<text[^>]*\by="(-?[\d.]+)"/, 1].to_f]
  end

  def edge_group(xml, edge_id)
    xml[%r{<g id="edge-#{edge_id}">.*?</g>}m]
  end

  # Used by "an edge from a box to itself" only.
  def loop_node_id(body)
    body.start_with?("subgraph") ? "s" : "A"
  end

  def loop_points(xml)
    d = xml[/<g id="edge-[^"]*">\s*<path[^>]*\bd="([^"]*)"/, 1]
    d.scan(/-?\d+(?:\.\d+)?/).map(&:to_f).each_slice(2).to_a
  end
end

# The whole pipeline, because a cluster is only right if the model, the
# layout and the renderer agree on where it sits. Every expectation was
# read off mmdc 11.12.0.
RSpec.describe Sirena::Engine do
  include FlowchartClusterSpecHelpers

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
    context "when it holds two nodes" do
      let(:xml) { render("flowchart TD\nsubgraph s [T]\nA --- B\nend\n") }
      let(:outer) { box(xml, "s") }
      let(:rects) { xml.scan(/<g id="node-[^"]+">\s*(<rect[^>]*>)/).flatten }

      it "draws both node rectangles" do
        expect(rects.length).to eq(2)
      end

      it "encloses their left edges" do
        expect(rects.map { |rect| attr(rect, "x") }).to all(be >= outer[:x])
      end

      it "encloses their top edges" do
        expect(rects.map { |rect| attr(rect, "y") }).to all(be >= outer[:y])
      end

      it "encloses their right edges" do
        rights = rects.map { |rect| attr(rect, "x") + attr(rect, "width") }

        expect(rights).to all(be <= outer[:x] + outer[:width])
      end

      it "encloses their bottom edges" do
        bottoms = rects.map { |rect| attr(rect, "y") + attr(rect, "height") }

        expect(bottoms).to all(be <= outer[:y] + outer[:height])
      end
    end

    # A long title used to run out past the edge of a box sized only by
    # the one small node inside it. Compared against a short title on the
    # same contents, because the box has to grow for the title alone.
    it "widens for a longer title" do
      short = box(render("flowchart TD\nsubgraph s [T]\nA\nend\n"), "s")
      long_source = "flowchart TD\nsubgraph s [A Really Quite Long Title]\n" \
                    "A\nend\n"
      long = box(render(long_source), "s")

      expect(long[:width]).to be > short[:width]
    end

    # Inside the box, not on its top edge. A baseline of zero puts a
    # `dominant-baseline: middle` title half outside the box, and every
    # other assertion here still passed with it there.
    context "with a short title" do
      let(:xml) { render("flowchart TD\nsubgraph s [T]\nA\nend\n") }
      let(:title) { xml[/<g id="cluster-s">.*?(<text[^>]*>)/m, 1] }
      let(:outer) { box(xml, "s") }

      # The literal drop, not just "below the top". A baseline of 1 still
      # puts half a 16px middle-baselined title outside the box, and
      # "greater than the top edge" was happy with it.
      #
      # 20, plus the 0.35em `middle` baseline shift Svg::Text folds into `y`
      # itself (Sirena::Svg::Text::BASELINE_SHIFTS) now that Tiny 1.2 forbids
      # the `dominant-baseline` attribute: 20 + 0.35 * 16px font-size = 25.6.
      # mmdc leaves the CSS property in place and never needs this shift; a
      # Tiny 1.2 renderer has no `dominant-baseline` to honour, so the shift
      # is what keeps the glyph centred where mmdc's title actually sits.
      it "writes the title inside the box" do
        expect(attr(title, "y") - outer[:y]).to be_within(0.001).of(25.6)
      end

      it "keeps the title above the bottom edge" do
        expect(attr(title, "y")).to be < outer[:y] + outer[:height]
      end
    end

    # The title is written inside the box, so the contents have to start
    # below it or the two are drawn on top of each other.
    it "keeps the nodes clear of the title" do
      xml = render("flowchart TD\nsubgraph s [T]\nA\nend\n")
      title = xml[/<g id="cluster-s">.*?(<text[^>]*>)/m, 1]
      node = xml[/<g id="node-A">\s*<rect[^>]*>/]

      title_centre = attr(title, "y") - (0.35 * 16)
      expect(attr(node, "y")).to be > title_centre
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
      "flowchart TD\nsubgraph outer [O]\nsubgraph inner [I]\n" \
        "A --- B\nend\nend\n"
    end

    # Outermost first, so the inner box lands on top of the one holding it.
    it "draws the outer box first" do
      expect(cluster_ids(render(source))).to eq(%w[outer inner])
    end

    context "when measuring the boxes" do
      let(:outer) { box(render(source), "outer") }
      let(:inner) { box(render(source), "inner") }

      it "sits the inner box right of the outer left edge" do
        expect(inner[:x]).to be >= outer[:x]
      end

      it "sits the inner box below the outer top edge" do
        expect(inner[:y]).to be >= outer[:y]
      end

      it "sits the inner box inside the outer right edge" do
        expect(inner[:x] + inner[:width]).to be <= outer[:x] + outer[:width]
      end

      it "sits the inner box inside the outer bottom edge" do
        expect(inner[:y] + inner[:height])
          .to be <= outer[:y] + outer[:height]
      end
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
    # nobody can see. Literal numbers, because `> 0` is satisfied by a
    # one-by-one box, which is invisible too.
    it "gives it a size anyway" do
      xml = render("flowchart TB\nsubgraph a\nsubgraph b\nend\nend\nz\n")
      outer = box(xml, "a")

      expect([outer[:width], outer[:height]]).to eq([48.0, 50.0])
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

  # Unconnected nodes share one rank, left to right in source order, with
  # elkrb's 50 point node spacing between them.
  describe "a diagram with no subgraph" do
    let(:found) { spots(render("flowchart TD\nA\nB\nC\nD\n")) }

    it "keeps unconnected nodes in source order" do
      expect(found.map(&:first)).to eq(%w[A B C D])
    end

    it "lays them in one row" do
      expect(found.map(&:last).uniq.size).to eq(1)
    end

    it "leaves more than the 50 point node spacing between them" do
      gaps = found.each_cons(2).map { |left, right| right[1] - left[1] }

      expect(gaps).to all(be > 50.0)
    end
  end

  # The layout marks a box; the renderer has to read the same mark. When
  # the two disagreed about what a box was, c4, class and er diagrams —
  # which nest children of their own — were resized like clusters.
  describe "a nested child with no cluster mark" do
    let(:renderer) do
      Sirena::Renderer::Flowchart.new(
        theme: Sirena::Theme::Registry.get(:default),
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
    it "draws no box for it" do
      expect(render_graph(graph).to_xml).not_to include("cluster-outer")
    end

    it "draws no node for it" do
      expect(render_graph(graph).to_xml).not_to include("node-outer")
    end

    it "still draws what it holds, offset by it" do
      xml = render_graph(graph).to_xml
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

    it "draws both boxes" do
      expect(cluster_ids(render(source))).to eq(%w[one two])
    end

    it "draws no node for their ids" do
      expect(node_ids(render(source))).to eq(%w[A B])
    end

    it "still draws the edge" do
      expect(render(source)).to include('id="edge-one_to_two"')
    end

    # ON the borders, not merely somewhere inside. A cluster is painted
    # behind the edges, so a line starting at its centre is drawn right
    # across the box — and "inside the box" is also true of that centre,
    # which is why the weaker test could not see it.
    context "when drawn" do
      let(:xml) { render(source) }
      let(:ends) { edge_numbers(xml, "one_to_two") }

      # ON the borders, not merely somewhere inside. A cluster is painted
      # behind the edges, so a line starting at its centre is drawn right
      # across the box — and "inside the box" is also true of that centre,
      # which is why the weaker test could not see it.
      it "starts on the border of the first box" do
        expect(on_border?(box(xml, "one"), ends[0], ends[1])).to be(true)
      end

      it "ends on the border of the second box" do
        expect(on_border?(box(xml, "two"), ends[2], ends[3])).to be(true)
      end

      # The second box ranks below the first, so the line leaves the bottom
      # edge of the first and arrives at the top edge of the second.
      it "leaves the bottom side of the first box" do
        first = box(xml, "one")

        expect(ends[1]).to be_within(0.01).of(first[:y] + first[:height])
      end

      it "arrives at the top side of the second box" do
        expect(ends[3]).to be_within(0.01).of(box(xml, "two")[:y])
      end
    end

    # One box holds the other, so trimming each end independently put
    # both of them past the other and drew the arrow backwards.
    it "still points at the target when one box holds the other" do
      # B keeps the two centres apart; boxes with one centre have no way
      # to run.
      xml = render("flowchart TD\nsubgraph outer\nsubgraph inner\nA\n" \
                   "end\nB\nend\nouter --> inner\n")
      sx, sy, tx, ty = edge_numbers(xml, "outer_to_inner")

      # The line has to run the same way the boxes do.
      expect([tx - sx, ty - sy].map { |d| d <=> 0 })
        .to eq(centre_gap(box(xml, "outer"), box(xml, "inner")))
    end

    context "when a box holds the other and nothing else" do
      let(:xml) do
        render("flowchart TD\nsubgraph outer\nsubgraph inner\nA\n" \
               "end\nend\nouter --> inner\n")
      end
      let(:points) { path_points(edge_d(xml, "outer_to_inner")) }

      it "starts the contained parent/child edge on the outer border" do
        expect(on_border?(box(xml, "outer"), *points.first)).to be(true)
      end

      it "ends the contained parent/child edge on the inner border" do
        expect(on_border?(box(xml, "inner"), *points.last)).to be(true)
      end
    end

    # The label used to be measured from the two centres while the path
    # was drawn from the borders, which left it sitting inside the box
    # the line no longer starts in.
    context "when the edge from a box carries a label" do
      let(:xml) do
        render("flowchart TD\nsubgraph one [A Fairly Long Title]\nA\n" \
               "end\none -->|lbl| Z\n")
      end
      let(:group) { edge_group(xml, "one_to_Z") }
      let(:ends) do
        path = group[/<path[^>]*\bd="([^"]*)"/, 1]
        path.scan(/-?\d+(?:\.\d+)?/).map(&:to_f)
      end

      # The midpoint of the run, exactly. "Somewhere along it" was also
      # true of the old label measured from the two centres.
      it "puts the label at the horizontal midpoint of the line" do
        expect(label_xy(group)[0])
          .to be_within(0.01).of((ends[0] + ends[2]) / 2)
      end

      it "puts the label at the vertical midpoint of the line" do
        expect(label_xy(group)[1] + 5)
          .to be_within(0.01).of((ends[1] + ends[3]) / 2)
      end
    end

    # Three decimals at most. The trimming arithmetic lands on seventeen
    # digits behind the point, and this output goes into a document.
    it "does not write full float precision into the path" do
      # A crossing that does NOT land on a whole number. Boxes in line
      # trim to exact coordinates, so a second target keeps this one slanted.
      xml = render("flowchart TD\n" \
                   "subgraph one [A Fairly Long Title Indeed Here]\nA\n" \
                   "end\none --> Z\none --> Y\n")
      path = xml[/<g id="edge-one_to_Z">\s*<path[^>]*\bd="([^"]*)"/, 1]

      # The whole path. Counting decimal places only proves the number is
      # no longer than three, which rounding to two or fewer also
      # satisfies. The start is where the ray between the two boxes' exact
      # centres leaves `one`.
      expect(path).to eq("M 112.39 137.0 L 80.02 214.0")
    end

    context "when a box joins a plain node" do
      let(:xml) do
        render("flowchart TD\nsubgraph one [O]\nA\nend\none --> Z\n")
      end

      it "draws the box" do
        expect(cluster_ids(xml)).to eq(%w[one])
      end

      it "draws the plain nodes" do
        expect(node_ids(xml)).to contain_exactly("A", "Z")
      end

      it "draws the edge" do
        expect(xml).to include('id="edge-one_to_Z"')
      end
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

    it "draws both boxes" do
      expect(cluster_ids(render(source))).to eq(%w[one two])
    end

    it "draws the edge between them" do
      expect(render(source)).to include('id="edge-one_to_two"')
    end
  end

  # These hand-positioned graphs exercise coordinates the fallback grid never
  # makes. They cross the same typed Layout-to-Renderer boundary as production.
  describe "a hand-positioned edge converted to a Scene" do
    let(:renderer) do
      Sirena::Renderer::Flowchart.new(
        theme: Sirena::Theme::Registry.get(:default),
      )
    end

    # A plain node-to-node run is clipped to the outline each end draws,
    # not left at the raw centres — mirroring the arrowhead, which reads
    # the same geometry so the line stops exactly where its head sits.
    it "leaves a node edge on the coordinates its outline draws" do
      first = leaf("a", x: 10.740735, y: 21.660485, width: 100.0, height: 50.0)
      second = leaf("b", x: 250.7037, y: 89.814705, width: 100.0, height: 50.0)

      expect(path_of(graph_linking(first, second), "a_to_b"))
        .to eq("M 110.7 60.9 L 250.7 100.6")
    end

    # A node can sit inside the cluster its own edge names — mermaid
    # draws that from a bare node under a subgraph header. The head used
    # to read its approach off the OTHER end's raw centre, which ignores
    # that A sits inside s: the path left through the cluster's TOP face
    # (the only way out `EdgeRouter` found), while the head — aimed at
    # A's centre, which sits BELOW the cluster's own centre — landed on
    # the BOTTOM face instead. The two must agree on which face, because
    # they are the same drawn line.

    it "keeps the arrowhead on the same face the path leaves through" do
      xml = render_graph(contained_arrow_graph("a", "s")).to_xml
      path_end, head_tip = edge_geometry(xml, "a_to_s")

      expect(head_tip).to eq(path_end)
    end

    # Reversed, the same mismatch degenerated further: the head's
    # approach (A's raw centre) landed EXACTLY on A's own boundary,
    # giving a zero-area, invisible arrowhead — three identical points.
    # Reaching A back from s, the path itself still ends at A's own
    # CENTRE — a plain node's end is never trimmed, since the node is
    # painted over the line — so this does not repeat the equality
    # above. What matters here is the head: it lands on A's real top
    # edge either way, but the point it approached FROM used to be
    # exactly that same edge point too, giving a triangle with no area.
    context "when the cluster is the source instead" do
      let(:xml) { render_graph(contained_arrow_graph("s", "a")).to_xml }
      let(:head_points) do
        xml[%r{<g id="edge-s_to_a">.*?<polygon[^>]*\bpoints="([^"]*)"}m, 1]
          .split.map { |pair| pair.split(",").map(&:to_f) }
      end

      it "lands the head on the node's real top edge" do
        expect(edge_geometry(xml, "s_to_a").last).to eq([88.5, 104.0])
      end

      it "draws a real, nonzero head" do
        expect(triangle_area(*head_points)).to be > 0
      end
    end

    # Two DIFFERENT boxes can share a centre too. There is no straight
    # direction to trim in that case, so the route must bend visibly.
    context "when two different boxes share a centre" do
      let(:points) do
        outer = cluster("s", x: 0.0, y: 0.0, width: 100.0, height: 100.0)
        inner = cluster("t", x: 25.0, y: 25.0, width: 50.0, height: 50.0)
        path_points(path_of(graph_between(outer, inner), "s_to_t"))
      end

      it "loops them with a bend" do
        expect(points.size).to be > 2
      end

      it "loops them between distinct points" do
        expect(points.uniq.size).to be > 1
      end
    end

    context "when a coincident loop meets a cluster" do
      let(:points) do
        source = cluster("s", x: 0.9, y: 0.9, width: 100.9, height: 100.9)
        target = leaf("t", x: 46.35, y: 46.35, width: 10.0, height: 10.0)
        path_points(path_of(graph_between(source, target), "s_to_t"))
      end

      it "bends the coincident loop" do
        expect(points.size).to be > 2
      end

      it "starts the loop on the painted top edge" do
        expect(points.first[1]).to eq(0.0)
      end

      it "clamps the loop to the painted cluster outline" do
        painted = { x: 0.0, y: 0.0, width: 100.0, height: 100.0 }

        expect(on_rounded_border?(painted, *points.first, 5)).to be(true)
      end
    end

    context "when the boxes are zero-size and coincident" do
      let(:points) do
        first = cluster("s", x: 10.0, y: 10.0, width: 0.0, height: 0.0)
        second = cluster("t", x: 10.005, y: 10.005, width: 0.0, height: 0.0)
        path_points(path_of(graph_between(first, second), "s_to_t"))
      end

      it "keeps the edge bent" do
        expect(points.size).to be > 2
      end

      it "keeps no segment at zero length" do
        expect(points.each_cons(2).none? { |from, to| from == to }).to be(true)
      end
    end

    # Two boxes that meet add up to exactly one run between their
    # centres, and the arithmetic lands a hair under it. Without the
    # slack both ends trim to the same point and the edge vanishes.
    #
    # Fractional sizes on purpose. `Layout::Grid` rounds a cluster to
    # whole units and every touching integer pair sums to exactly 1.0, so
    # this models what the layout engine will hand the renderer instead.
    it "keeps a length between two boxes that touch" do
      source = cluster("s", x: 0.0, y: 0.0, width: 10.1, height: 4.0)
      target = cluster("t", x: 10.1, y: 0.0, width: 11.0, height: 4.0)
      points = path_points(path_of(graph_between(source, target), "s_to_t"))

      expect(points.last[0]).to be > points.first[0]
    end

    context "when clusters meet diagonally" do
      let(:source) do
        cluster("s", x: 50.0, y: 50.0, width: 100.0, height: 100.0)
      end
      let(:target) do
        cluster("t", x: 250.0, y: 250.0, width: 100.0, height: 100.0)
      end
      let(:points) do
        path_points(path_of(graph_between(source, target), "s_to_t"))
      end

      it "anchors the source end on its rounded outline" do
        expect(on_rounded_border?(source, *points.first, 5)).to be(true)
      end

      it "anchors the target end on its rounded outline" do
        expect(on_rounded_border?(target, *points.last, 5)).to be(true)
      end

      it "keeps the source end off the square corner" do
        expect(exactly_on_border?(source, *points.first)).to be(false)
      end

      it "keeps the target end off the square corner" do
        expect(exactly_on_border?(target, *points.last)).to be(false)
      end

      it "keeps the unrounded corner point off the outline" do
        expect(on_rounded_border?(source, 148.18, 148.18, 5)).to be(false)
      end
    end

    context "when the corner coordinates carry two decimals" do
      let(:points) do
        source = cluster("s", x: 50.901, y: 50.901,
                              width: 100.903, height: 100.903)
        target = cluster("t", x: 250.901, y: 250.901,
                              width: 100.903, height: 100.903)
        path_points(path_of(graph_between(source, target), "s_to_t"))
      end
      let(:painted_source) { { x: 50.0, y: 50.0, width: 100.0, height: 100.0 } }
      let(:painted_target) do
        { x: 250.0, y: 250.0, width: 100.0, height: 100.0 }
      end

      it "uses the painted source bounds" do
        expect(on_rounded_border?(painted_source, *points.first, 5))
          .to be(true)
      end

      it "uses the painted target bounds" do
        expect(on_rounded_border?(painted_target, *points.last, 5))
          .to be(true)
      end

      it "keeps the source end off the painted square corner" do
        expect(exactly_on_border?(painted_source, *points.first)).to be(false)
      end

      it "keeps the target end off the painted square corner" do
        expect(exactly_on_border?(painted_target, *points.last)).to be(false)
      end
    end

    context "when the ELK section carries a bend point" do
      let(:source) do
        cluster("s", x: 0.0, y: 0.0, width: 100.0, height: 4.0)
      end
      let(:points) do
        target = leaf("t", x: 149.0, y: 5.0, width: 2.0, height: 2.0)
        edge = { sections: [{ bendPoints: [{ x: 110.0, y: 4.0 }] }] }
        graph = graph_between(source, target, edge)
        path_points(path_of(graph, "s_to_t"))
      end

      it "starts at the radius-clamped outline point" do
        expect(points.first).to eq([95.0, 4.0])
      end

      it "keeps the adjacent ELK bend" do
        expect(points[1]).to eq([110.0, 4.0])
      end

      it "starts on the rounded outline with independent radii" do
        expect(on_rounded_border?(source, *points.first, 5)).to be(true)
      end
    end

    context "when rounded cluster borders would coincide" do
      let(:source) do
        cluster("s", x: 0.0, y: 0.0, width: 100.0, height: 100.0)
      end
      let(:target) do
        cluster("t", x: 100.001, y: 0.0, width: 100.0, height: 100.0)
      end
      let(:points) do
        path_points(path_of(graph_between(source, target), "s_to_t"))
      end

      it "detours with a bend" do
        expect(points.size).to be > 2
      end

      it "keeps no segment at zero length" do
        expect(points.each_cons(2).none? { |from, to| from == to }).to be(true)
      end

      it "starts exactly on the source border" do
        expect(exactly_on_border?(source, *points.first)).to be(true)
      end

      it "ends exactly on the target border" do
        expect(exactly_on_border?(target, *points.last)).to be(true)
      end
    end

    {
      "horizontal shallow" => -> { cluster_pair([0.0, 0.0], [75.0, 0.0]) },
      "vertical shallow" => -> { cluster_pair([0.0, 0.0], [0.0, 75.0]) },
      "horizontal centre inside" =>
        -> { cluster_pair([0.0, 0.0], [40.0, 0.0]) },
      "horizontal centre inside reversed" =>
        -> { cluster_pair([40.0, 0.0], [0.0, 0.0]) },
      "vertical centre inside" =>
        -> { cluster_pair([0.0, 0.0], [0.0, 40.0]) },
      "vertical centre inside reversed" =>
        -> { cluster_pair([0.0, 40.0], [0.0, 0.0]) },
      "diagonal centre inside" =>
        -> { cluster_pair([0.0, 0.0], [40.0, 40.0]) },
      "diagonal centre inside reversed" =>
        -> { cluster_pair([40.0, 40.0], [0.0, 0.0]) },
      "equal-centre cross" => -> { cross_cluster_pair },
      "equal-centre cross reversed" =>
        -> { cross_cluster_pair(reverse: true) },
      "near-centre cross" => -> { cross_cluster_pair(offset: 0.004) },
      "near-centre cross reversed" =>
        -> { cross_cluster_pair(reverse: true, offset: 0.004) },
      "asymmetric" => -> { asymmetric_cluster_pair },
      "asymmetric reversed" => -> { asymmetric_cluster_pair(reverse: true) },
      "asymmetric rotated" => -> { asymmetric_cluster_pair(rotated: true) },
      "asymmetric rotated reversed" =>
        -> { asymmetric_cluster_pair(rotated: true, reverse: true) },
    }.each do |name, build|
      it "routes overlapping clusters outside both faces: #{name}" do
        source, target = instance_exec(&build)
        document = render_graph(graph_between(source, target, outside_edge))

        expect_exterior_route(document, source, target, name)
      end
    end

    [0.01, 0.008].each do |offset|
      it "uses Euclidean distance for diagonal zero-size boxes (#{offset})" do
        source = cluster("s", x: 0.0, y: 0.0, width: 0.0, height: 0.0)
        target = cluster("t", x: offset, y: offset, width: 0.0, height: 0.0)
        expected = [[0.0, 0.0], [offset.round(2), offset.round(2)]]

        expect(path_points(path_of(graph_between(source, target), "s_to_t")))
          .to eq(expected)
      end
    end

    it "keeps centres exactly one output unit apart distinct" do
      source = cluster("s", x: 0.0, y: 0.0, width: 0.0, height: 0.0)
      target = cluster("t", x: 0.01, y: 0.0, width: 0.0, height: 0.0)

      expect(path_points(path_of(graph_between(source, target), "s_to_t")))
        .to eq([[0.0, 0.0], [0.01, 0.0]])
    end

    it "keeps ordinary ELK bend points, clipped to each end's outline" do
      source = leaf("s", x: 0.0, y: 0.0, width: 100.0, height: 50.0)
      target = leaf("t", x: 200.0, y: 0.0, width: 100.0, height: 50.0)
      edge = { sections: [{ bendPoints: [{ x: 120.0, y: 80.0 }] }] }

      expect(path_of(graph_between(source, target, edge), "s_to_t"))
        .to eq("M 81.8 50.0 L 120.0 80.0 L 200.0 46.2")
    end

    context "when a single cluster is the whole diagram" do
      let(:view_box) do
        source = cluster("s", x: 0.0, y: 0.0, width: 100.0, height: 100.0)
        render_graph({ id: "g", children: [source], edges: [] })
          .view_box.split.map(&:to_f)
      end

      it "starts the view box at the origin" do
        expect(view_box.first(2)).to eq([0.0, 0.0])
      end

      it "keeps mmdc's 8px beyond the right maximum" do
        expect((view_box[0] + view_box[2]) - 100.0).to eq(8.0)
      end

      it "keeps mmdc's 8px beyond the bottom maximum" do
        expect((view_box[1] + view_box[3]) - 100.0).to eq(8.0)
      end
    end
  end

  # `s --> s` put both ends on the same point: the path came out
  # `M 88 104 L 88 104`, zero units long, carrying an arrowhead on
  # nothing. mmdc draws a visible loop for a box of either kind.
  describe "an edge from a box to itself" do
    let(:source) { "flowchart TD\nsubgraph s\nA\nend\ns --> s\n" }

    # The defect was a path of ZERO length. The loop closes on itself by
    # design, so length is what to assert, not distinct ends.
    it "draws a path with length" do
      points = loop_points(render(source))

      expect(points.uniq.size).to be > 1
    end

    it "bends, rather than running straight between its ends" do
      expect(loop_points(render(source)).size).to be > 2
    end

    context "with the cluster border to measure against" do
      let(:xml) { render(source) }
      let(:outer) { box(xml, "s") }
      let(:points) { loop_points(xml) }

      it "starts on the cluster border" do
        expect(on_border?(outer, *points.first)).to be(true)
      end

      it "finishes on the cluster border" do
        expect(on_border?(outer, *points.last)).to be(true)
      end

      # TD throws the loop downward, not sideways — see self_loop_side.
      it "stands clear of the border" do
        expect(points.map(&:last).max).to be > outer[:y] + outer[:height]
      end

      it "uses distinct border endpoints for a nonzero cluster self-edge" do
        expect(points.uniq.size).to be > 1
      end

      it "does not close the loop on one point" do
        expect(points.first).not_to eq(points.last)
      end
    end

    # The loop reaches past the box it leaves, so the page has to still
    # cover it. It rides the slack the sizing already carries — and the
    # rightmost/bottommost box is the one that tests it, so a node on
    # that edge matters as much as a cluster.
    #
    # TD throws its loop downward and LR throws its rightward (see
    # self_loop_side), so the axis that has to clear the box differs per
    # source — a TD loop never needs to reach past the box on the right.
    { "flowchart TD\nsubgraph s\nA\nend\ns --> s\n" => :y,
      "flowchart LR\nA --> B\nB --> B\n" => :x }.each do |src, thrown_axis|
      context "with the loop thrown along #{thrown_axis}" do
        let(:xml) { render(src) }
        let(:pts) { edge_paths(xml).flat_map { |d| path_points(d) } }

        it "draws an edge path" do
          expect(pts).not_to be_empty
        end

        # The loop is the thing that reaches furthest along the axis
        # it is thrown on, so a source whose loop vanished would not
        # be testing the page.
        it "reaches past the box on the axis it is thrown on" do
          reach = pts.map(&(thrown_axis == :x ? :first : :last)).max
          limit = thrown_axis == :x ? box_right(xml) : box_bottom(xml)

          expect(reach).to be > limit
        end

        it "stays within the page width" do
          expect(pts.map(&:first).max).to be <= svg_dimension(xml, "width")
        end

        it "stays right of zero" do
          expect(pts.map(&:first).min).to be >= 0
        end

        it "stays within the page height" do
          expect(pts.map(&:last).max).to be <= svg_dimension(xml, "height")
        end

        it "stays below zero" do
          expect(pts.map(&:last).min).to be >= 0
        end
      end
    end

    # BT and RL throw the loop up and left instead — the two directions
    # `create_document` never grows into, since its own comment says it
    # only grows the right and bottom. A loop's label reaches
    # EDGE_LABEL_LIFT further than its own corners, so the label is what
    # first crosses zero even when the corners themselves still clear it.
    %w[BT RL].each do |direction|
      context "when the loop is thrown #{direction}" do
        let(:points) do
          xml = render("flowchart #{direction}\nsubgraph s\nA[abcdefghij]\n" \
                       "end\ns -->|again| s\n")
          group = xml[%r{<g id="edge-s_to_s".*?</g>}m]
          loop_points(xml) << label_xy(group)
        end

        it "keeps every x, label included, inside the page" do
          expect(points.map(&:first).min).to be >= 0
        end

        it "keeps every y, label included, inside the page" do
          expect(points.map(&:last).min).to be >= 0
        end
      end
    end

    # The same collapse, reached through a node instead. An empty
    # subgraph named by an edge is drawn as a plain node, so `s --> s`
    # arrives here rather than at the cluster branch above.
    # Every shape, because the ends anchor either side of the same point
    # on the boundary where the loop's two corners meet it, and TD
    # throws the loop straight down, not sideways. A rectangle and a
    # hexagon meet it on their flat bottom face; a circle and a rhombus
    # have no flat face there, so theirs lands a touch above the true
    # bottom instead — the lower arc, the two lower sloped edges — the
    # one pair of points all four shapes reach.
    # Anchoring a third of the way down put the loop on the bounding box
    # instead, eight units clear of a rhombus's drawn edge.
    {
      "an empty subgraph drawn as a node" => "subgraph s\nend\ns --> s",
      "a plain rectangle" => "A --> A",
      "a rounded rectangle" => "A(A) --> A",
      "a stadium" => "A([A]) --> A",
      "a circle" => "A((A)) --> A",
      "a rhombus" => "A{A} --> A",
      "a hexagon" => "A{{A}} --> A",
    }.each do |shape, body|
      context "with #{shape}" do
        let(:xml) { render("flowchart TD\n#{body}\n") }
        let(:points) { loop_points(xml) }
        let(:rect) { node_rect(xml, loop_node_id(body)) }
        let(:drawn) { node_shape(xml, loop_node_id(body)) }

        it "finds the node's box" do
          expect(rect).not_to be_nil
        end

        it "finds the drawn outline" do
          expect(drawn).not_to be_nil
        end

        # Out and back: two ends on the outline, two bends clear of it.
        it "goes out and back through four points" do
          expect(points.size).to eq(4)
        end

        # On the OUTLINE. A circle and a rhombus meet their bounding box
        # at one point per side, so anchoring anywhere else leaves the
        # loop hanging in space beside the shape.
        it "anchors the first end on the drawn outline" do
          expect(on_shape?(drawn, *points.first)).to be(true)
        end

        it "anchors the last end on the drawn outline" do
          expect(on_shape?(drawn, *points.last)).to be(true)
        end

        # It has to LEAVE the box, or it is a chord across the inside —
        # downward for TD, the axis the loop is actually thrown on.
        it "leaves the box downward" do
          expect(points.map(&:last).max).to be > rect[:y] + rect[:height]
        end
      end
    end

    # Nothing in the diagram may still be drawn as a zero-length path.
    # The edge has to be THERE as well: an omitted path has no zero
    # length either, and would sail through on its own.
    ["flowchart TD\nA --> A\n",
     "flowchart TD\nsubgraph s\nA\nend\ns --> s\n",
     "flowchart TD\nsubgraph s\nend\ns --> s\n"].each do |src|
      context "with #{src.inspect}" do
        let(:drawn) { edge_paths(render(src)) }
        let(:points) { path_points(drawn.first.to_s) }

        it "draws exactly one path" do
          expect(drawn.size).to eq(1)
        end

        # No zero-length SEGMENT, not merely no zero-length path: a
        # repeated point anywhere along the run draws the same
        # nothing, and matching one exact serialisation missed it.
        it "has no zero-length segment" do
          expect(points.each_cons(2).any? { |a, b| a == b }).to be(false)
        end

        it "has more than one point" do
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
