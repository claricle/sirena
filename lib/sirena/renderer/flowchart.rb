# frozen_string_literal: true

require_relative 'base'
require_relative 'edge_router'

module Sirena
  module Renderer
    # Flowchart renderer for converting graphs to SVG.
    #
    # Converts a laid-out graph structure (with computed positions) into
    # SVG using the Svg builder classes. Handles different node shapes,
    # edge routing, and label positioning.
    #
    # @example Render a flowchart
    #   renderer = FlowchartRenderer.new
    #   svg = renderer.render(laid_out_graph)
    class FlowchartRenderer < Base
      # Rounded like mermaid draws a cluster, and far enough down that the
      # title clears the top edge.
      # The radius lives with the routing, because an endpoint on a
      # corner has to land on the outline drawn here.
      CLUSTER_CORNER = EdgeRouter::CLUSTER_CORNER
      CLUSTER_TITLE_BASELINE = 20

      # Which outline each shape name is drawn with. One table, because
      # the drawing and the boundary have to agree: a head landing on a
      # circle's outline while the node is drawn as a rect points at
      # nothing. Every other name `SHAPE_MAP` produces — `rect`,
      # `subroutine`, `cylindrical`, `asymmetric`, the parallelograms and
      # the trapezoids — is drawn as a plain box and answers as one.
      #
      # `rounded` and `stadium` share an outline: both are drawn with
      # their ends rounded the whole way, so a head aiming at one pulls
      # in from the corners as far as a circle's does.
      NODE_OUTLINES = {
        'rounded' => :rounded, 'stadium' => :rounded,
        'circle' => :circle, 'double_circle' => :circle,
        'rhombus' => :rhombus, 'hexagon' => :hexagon
      }.freeze
      private_constant :NODE_OUTLINES

      # mmdc's own numbers, reached when the theme names no thick width
      # and no dash pattern. The multiple lands on whatever plain width
      # the theme does name, and on mmdc's 1 only when it names none —
      # see `thick_width`. mmdc's thick line is 3.5 times its normal one,
      # and its dotted one is dashed 2 on, 2 off.
      LINK_THICK_MULTIPLE = 3.5
      LINK_DOTTED_DASHES = '2'
      private_constant :LINK_THICK_MULTIPLE, :LINK_DOTTED_DASHES

      # Which marker each HEAD name draws, read off mmdc's own
      # `marker-start` and `marker-end`. Keyed on the head alone, not on
      # the whole link type: `render_edge_heads` strips the weight prefix
      # and the `_both` suffix first, so `thick_arrow_both` looks up
      # `arrow` here rather than needing a key of its own.
      EDGE_HEADS = { 'arrow' => :arrow, 'cross' => :cross,
                     'circle' => :circle }.freeze
      private_constant :EDGE_HEADS

      # Each head is mmdc's own marker, scaled the way mmdc scales it.
      # `pointEnd` is a 0..10 viewBox drawn at markerWidth 8, so its
      # `M 0 0 L 10 5 L 0 10 z` lands 8 long and 4 either side of the axis.
      ARROW_LENGTH = 8.0
      ARROW_HALF_WIDTH = 4.0
      private_constant :ARROW_LENGTH, :ARROW_HALF_WIDTH

      # The two scale differently, so each is derived from its own marker
      # rather than from a shared factor.
      #
      # `circleEnd` is a radius-5 circle in a `0 0 10 10` viewBox at
      # markerWidth 11, so it scales by 11/10 and its drawn radius is 5.5.
      # `crossEnd` draws `M 1,1 l 9,9 M 10,1 l -9,9` in a `0 0 11 11`
      # viewBox at markerWidth 11, so it scales by 11/11 = 1 and nothing
      # here is multiplied. Its arms run 1..10 about a centre of 5.5,
      # making each axis's half-run 4.5 and each drawn half-arm
      # 4.5 * sqrt(2) long.
      CIRCLE_HEAD_RADIUS = 5.5
      CROSS_HEAD_HALF = 4.5
      private_constant :CIRCLE_HEAD_RADIUS, :CROSS_HEAD_HALF

      # mmdc fixes its circle stroke at 1 and its cross stroke at 2. `%g`
      # writes those widths without a decimal. A line's stroke width comes
      # from the theme and keeps its own formatting.
      CIRCLE_HEAD_STROKE = 1.0
      CROSS_HEAD_STROKE = 2.0
      private_constant :CIRCLE_HEAD_STROKE, :CROSS_HEAD_STROKE

      # mmdc puts each marker's reference point on the node boundary, so
      # each back-off along the line is the refX-to-centre distance in
      # that marker's own viewBox units, taken at that marker's own scale.
      #
      # `circleEnd` has refX 11 against a centre of 5, so (11 - 5) * 1.1
      # = 6.6 and its outline stops 1.1 short of the node. The stroke is
      # centred on that outline and so paints 0.5 past it, leaving 0.6.
      # `crossEnd` has refX 12 against a centre of 5.5 and scales by 1, so
      # 12 - 5.5 = 6.5 and its nearest arm point stops 2.0 short.
      CIRCLE_HEAD_REACH = 6.6
      CROSS_HEAD_REACH = 6.5
      private_constant :CIRCLE_HEAD_REACH, :CROSS_HEAD_REACH

      # How far an edge label sits off the line it belongs to.
      EDGE_LABEL_LIFT = 5.0
      private_constant :EDGE_LABEL_LIFT

      # A `<text>` with no font-size anywhere is drawn at the user agent's
      # `medium`, which is 16px.
      SVG_DEFAULT_FONT_SIZE = 16.0
      private_constant :SVG_DEFAULT_FONT_SIZE

      # `TextMeasurement`'s average ratio is deliberately an average — the
      # right choice for sizing a box AROUND text, the wrong one for
      # reducing how often a self loop's label runs past the room this
      # sizes for it.
      #
      # This is NOT a bound, and a first version of this constant that
      # tried to be one (`1.0`, set from ASCII alone) was refuted by
      # measuring real scripts rather than raising the number until
      # nothing failed. `overflow: 'hidden'` on the document is SVG's
      # SPECIFIED way to clip a viewport's content to its own bounds —
      # see `#render` for what that specification is measured to buy
      # here, which is less than it sounds. This constant only decides
      # how RARELY an underestimate reaches that edge at all.
      #
      # Measured with Chrome against Sirena's own rendered `<text>`
      # (Arial, Helvetica, sans-serif at font-size 12 — the theme's
      # `font_size_small`), em-per-character:
      #
      #   ASCII widest (ten repeats each, ' @' the max)         0.889
      #   CJK Han / Hiragana / Fullwidth Latin                  1.00–1.02
      #   Emoji, incl. a 7-codepoint ZWJ family (one glyph)     1.25–1.42
      #   Devanagari (plain and a 3-codepoint conjunct)         0.75–0.81
      #   Arabic (a plain letter)                               0.71
      #   A combining sequence (e + acute, 2 codepoints)        0.56
      #   Arabic ligature U+FDFD (Bismillah, ONE codepoint)     6.49
      #
      # The last row is why this can never be a bound. East Asian Width
      # classifies U+FDFD as `N` (Neutral) — NOT the same class as `A`
      # or `@`, which are both `Na` (Narrow): a table keyed on that
      # property could in principle score them apart. What it proves is
      # narrower and still fatal to any character-count approach: one
      # 6.49em character disproves every SMALLER constant, and Unicode
      # properties alone do not supply reliable advances for an
      # unspecified font — EAW describes how much horizontal space a
      # character is conventionally given in East Asian typesetting, not
      # what any particular font's ligature or shaping table does with
      # it. This does not prove no scalar exists for a FIXED font
      # configuration (Arial, Helvetica, sans-serif, as the theme names
      # it); it proves that deriving one from codepoint properties
      # rather than measuring the font is not reliable. Short of a real
      # font metrics table (the dependency `TextMeasurement`'s own docs
      # say this gem avoids), no per-codepoint number bounds what a
      # font's ligature substitution can do with a single input
      # character.
      #
      # 1.5 clears every row above except the ligature — CJK and emoji
      # included, both of which `1.0` (this constant's first value)
      # UNDERSHOT despite being set with headroom over ASCII, which is
      # the tell that ASCII-only measurement was never going to
      # generalise.
      WIDE_CHAR_WIDTH_RATIO = 1.5
      private_constant :WIDE_CHAR_WIDTH_RATIO

      # A self loop is a two-corner polyline. It goes out past the node
      # edge by SELF_LOOP_DEPTH of the node's shorter side, capped at
      # SELF_LOOP_MAX_DEPTH, and spreads SELF_LOOP_HALF_SPAN either side
      # of centre. The spread runs ACROSS the throw, so it is measured
      # across it too: a vertical loop spreads along x and takes its span
      # from the width, a horizontal one spreads along y and takes it
      # from the height.
      #
      # Only the depth has the oracle behind it, and it is measured across
      # sizes rather than read off one node. mmdc loops 24.3 past a 69.4x54
      # node and 45.0 past a 100x102 one — 0.45 of the shorter side both
      # times — and 48.0 past a 108.4x366 one, where the ratio wants 48.8.
      # So the ratio and the 48 cap are both mmdc's.
      #
      # The half span and its limits do NOT. mermaid draws a self loop as
      # a bezier and this draws a polyline, so their widths are not the
      # same measurement and no mmdc run settles one from the other. They
      # are pinned by the specs below this file, not by the oracle.
      # Anyone changing them should know which half is which.
      SELF_LOOP_DEPTH = 0.45
      SELF_LOOP_HALF_SPAN = 0.175
      SELF_LOOP_HALF_SPAN_LIMITS = (18.0..50.0)
      SELF_LOOP_MAX_DEPTH = 48.0
      private_constant :SELF_LOOP_DEPTH, :SELF_LOOP_HALF_SPAN,
                       :SELF_LOOP_HALF_SPAN_LIMITS, :SELF_LOOP_MAX_DEPTH

      # Which way a self loop is thrown: the way the diagram flows. mmdc
      # loops below for TD, right for LR, left for RL and above for BT.
      SELF_LOOP_SIDES = { 'DOWN' => [0, 1].freeze, 'UP' => [0, -1].freeze,
                          'RIGHT' => [1, 0].freeze,
                          'LEFT' => [-1, 0].freeze }.freeze
      private_constant :SELF_LOOP_SIDES

      # Renders a laid-out graph to SVG.
      #
      # `overflow: 'hidden'` is SVG's SPECIFIED way to clip a viewport's
      # rendering to its own bounds — see `WIDE_CHAR_WIDTH_RATIO` for why
      # no character-count estimate can size that viewport correctly on
      # its own. What the specified behaviour actually BUYS here was
      # measured, not assumed, and the measurement is smaller than the
      # attribute sounds: screenshotting the same pathological label
      # with and without it, root document and nested alike, came back
      # byte-identical (`compare -metric AE` reports 0 differing
      # pixels). Chrome already contains SVG content to its own box by
      # default, contrary to the SVG2 spec's stated `visible` default
      # for a root `<svg>` — so in every context this could be measured
      # against, the attribute changed nothing. It is kept anyway, at
      # zero cost, because it states the specified policy explicitly
      # rather than leaving it to an unwritten default; whether that
      # matters for any renderer other than Chrome was not measured and
      # is not claimed here.
      #
      # `clear_self_loop_overflow` and `self_loop_reach` still do real
      # work sizing the page from the loop's BENDS, which are exact
      # numbers, not text estimates; only a label's own contribution to
      # that sizing is a best-effort hint rather than a guarantee. When
      # the hint is wrong, the label's own excess is invisible past the
      # page edge — CHROME MEASURED, not merely intended — while
      # everything else in the diagram (nodes, other edges, the loop's
      # own bends) stays exactly where the exact numbers put it. mmdc
      # does not carry this limit — measured directly, it sizes the
      # SAME pathological label correctly (viewBox grows to 737px,
      # `mmdc -i` on a `flowchart RL` self loop reading `|﷽﷽﷽﷽|`) —
      # because it drives an actual Chrome layout of the label as HTML
      # and reads the box back. That is the gap: mmdc MEASURES, sirena
      # ESTIMATES, and adding a headless browser to a pure-Ruby renderer
      # to close it is a different, much bigger change than this one.
      #
      # @param graph [Hash] laid-out graph with node positions
      # @return [Svg::Document] the rendered SVG document
      def render(graph)
        page = clear_self_loop_overflow(flatten(graph))
        svg = create_document(page, overflow: 'hidden')

        # mermaid's paint order: clusters sit behind everything, then
        # edges, then the nodes that cover where the edges end.
        render_clusters(page, svg)
        render_edges(page, svg) if page[:edges]
        render_nodes(page, svg) if page[:children]

        svg
      end

      protected

      # The layout nests a cluster's contents inside it, ELK style, so a
      # child's coordinates are relative to the box holding it. Everything
      # below this point works in page coordinates on a flat list, so the
      # tree is walked once here and the offsets added up.
      def flatten(graph)
        clusters = []
        nodes = []
        collect(graph[:children] || [], 0, 0, clusters, nodes)

        graph.merge(children: nodes, clusters: clusters)
      end

      # Outermost first, which is the order mermaid paints nested boxes,
      # so an inner cluster lands on top of the one holding it.
      def collect(children, dx, dy, clusters, nodes)
        children.each do |child|
          placed = child.merge(x: (child[:x] || 0) + dx,
                               y: (child[:y] || 0) + dy)

          unless child[:children]
            nodes << placed
            next
          end

          # The same test Layout::Fallback#cluster? makes. Nothing
          # coupled keeps them together: change one and change the other,
          # or the layout and the renderer stop agreeing about what a box
          # is. Transform::FlowchartTransform sets the marker.
          clusters << placed.except(:children) if cluster?(child)
          collect(child[:children], placed[:x], placed[:y], clusters, nodes)
        end
      end

      def cluster?(child)
        EdgeRouter.cluster?(child)
      end

      # A self loop can reach past its own node on any side, and a BT or
      # RL diagram throws it up or left — past the zero the page is
      # pinned to. `create_document` only ever grows the right and
      # bottom, so a loop escaping the other way is not a bigger page,
      # it is a clipped one. mmdc never draws that: its own viewBox stays
      # non-negative because mermaid's layout reserves the room for a
      # loop before placing anything. Sirena's fallback layout does not
      # know loops exist, so the whole page is nudged down and right
      # here instead, by however far the worst loop — and the label past
      # it — reaches beyond zero.
      def clear_self_loop_overflow(graph)
        dx, dy = self_loop_overflow(graph)
        return graph if dx.zero? && dy.zero?

        graph.merge(children: shift_boxes(graph[:children], dx, dy),
                    clusters: shift_boxes(graph[:clusters], dx, dy),
                    edges: shift_edges(graph[:edges], dx, dy))
      end

      def shift_boxes(boxes, dx, dy)
        (boxes || []).map { |box| box.merge(x: (box[:x] || 0) + dx, y: (box[:y] || 0) + dy) }
      end

      # A self loop's own bends are recomputed from the (now shifted)
      # node at render time, but an edge that arrives with its route
      # already drawn — real ELK output, or a graph built by hand — is
      # drawn exactly where its bend points say, and never touches the
      # node again. Shifting the boxes and leaving those points behind
      # walks the node one way and the line it is supposedly attached to
      # nowhere, so the route has to move with the page too.
      def shift_edges(edges, dx, dy)
        (edges || []).map { |edge| shift_edge(edge, dx, dy) }
      end

      def shift_edge(edge, dx, dy)
        sections = edge[:sections]
        return edge unless sections&.any?

        edge.merge(sections: sections.map { |section| shift_section(section, dx, dy) })
      end

      def shift_section(section, dx, dy)
        bend_points = section[:bendPoints]
        return section unless bend_points&.any?

        section.merge(bendPoints: bend_points.map { |point| shift_point(point, dx, dy) })
      end

      def shift_point(point, dx, dy)
        point.merge(x: (point[:x] || 0) + dx, y: (point[:y] || 0) + dy)
      end

      # The full reach of every self loop in the graph, as one bounding
      # box — nil when there are none. Reuses the exact bends and label
      # anchor `render_edge` draws later, so this can never disagree with
      # what actually gets drawn on the BEND side of the box — except
      # that a bend or an anchor is a POINT and the label drawn there is
      # not: `create_edge_label` centres it on `x` and leaves it sitting
      # on its default SVG baseline at `y`, so the text itself reaches
      # half its width either side of `x` and the whole of its height
      # above `y`, never below. `loop_label_extent` supplies that
      # half-width and height as a wide HINT, not a bound — no
      # per-character number is one, see the constant it reads — so this
      # box can still be smaller than what Chrome renders for an extreme
      # script. Chrome contains that gap on its own, measured — see
      # `#render` — so a wrong answer here costs legibility of one
      # label, never the rest of the page.
      #
      # Both `self_loop_overflow` (page shifted for a loop hanging off
      # the top or left) and `calculate_width`/`calculate_height` (page
      # grown for one hanging off the right or bottom) read this same
      # box, so the two can never disagree about where a loop reaches.
      def self_loop_bounds(graph)
        side = self_loop_side(graph)
        (graph[:edges] || []).reduce(nil) do |bounds, edge|
          node = self_loop_node(graph, edge)
          next bounds unless node

          bends = edge_bends(edge, node, node, side)
          next bounds if bends.empty?

          label_x, label_y = loop_label_anchor(node, bends)
          half_width, height = loop_label_extent(edge)
          xs = bends.map { |point| point[:x] } + [label_x - half_width, label_x + half_width]
          ys = bends.map { |point| point[:y] } + [label_y - height, label_y]

          merge_bounds(bounds, xs.min, xs.max, ys.min, ys.max)
        end
      end

      def merge_bounds(bounds, min_x, max_x, min_y, max_y)
        return { min_x: min_x, max_x: max_x, min_y: min_y, max_y: max_y } unless bounds

        { min_x: [bounds[:min_x], min_x].min, max_x: [bounds[:max_x], max_x].max,
          min_y: [bounds[:min_y], min_y].min, max_y: [bounds[:max_y], max_y].max }
      end

      # How far below zero the worst self loop reaches, on each axis.
      def self_loop_overflow(graph)
        bounds = self_loop_bounds(graph)
        return [0.0, 0.0] unless bounds

        [bounds[:min_x].negative? ? -bounds[:min_x] : 0.0,
         bounds[:min_y].negative? ? -bounds[:min_y] : 0.0]
      end

      # How far past the box-based page edge the worst self loop reaches,
      # on each axis. `calculate_width`/`calculate_height` fold this in
      # alongside the node- and cluster-based extent, since a loop's
      # bends and label are drawn past its own node and neither one is a
      # box `drawn(graph)` already counts.
      def self_loop_reach(graph)
        bounds = self_loop_bounds(graph)
        return [0.0, 0.0] unless bounds

        [bounds[:max_x], bounds[:max_y]]
      end

      # Half the loop label's own width, and the whole of its height —
      # the reach its text adds on top of the anchor point
      # `loop_label_anchor` returns. `text_anchor` centres a label
      # horizontally, so it is `x` minus half the width at its narrowest;
      # nothing here sets `dominant-baseline`, so the glyphs sit entirely
      # above `y`, SVG's default text baseline. [0.0, 0.0] when there is
      # no label to draw, since nothing then reaches past the anchor.
      #
      # The width is a wider HINT (`WIDE_CHAR_WIDTH_RATIO`), not
      # `TextMeasurement`'s average and not a bound either — see the
      # constant for why no per-character number can be one. Chrome
      # measured a wrong answer here as staying CONTAINED regardless —
      # see `#render` — so the failure mode of this hint being wrong is
      # an invisible label tail, not a distorted or escaping page. The
      # height is still `TextMeasurement`'s, since neither finding
      # touched it and mmdc's
      # own measurement never showed it short.
      def loop_label_extent(edge)
        label = edge[:labels]&.first
        return [0.0, 0.0] unless label

        font_size = edge_label_font_size
        text = label[:text].to_s
        width = text.length * font_size * WIDE_CHAR_WIDTH_RATIO
        height = font_size * TextMeasurement::HEIGHT_RATIO
        [width / 2.0, height]
      end

      # The size `create_edge_label` actually draws at: the theme's small
      # size, else the normal size `apply_theme_to_text` sets, else the SVG
      # default. Keep the two in step, or loop room is sized for text the
      # page does not draw.
      def edge_label_font_size
        theme_typography(:font_size_small) ||
          theme_typography(:font_size_normal) || SVG_DEFAULT_FONT_SIZE
      end

      def self_loop_node(graph, edge)
        source_id = edge[:sources]&.first
        return nil unless source_id && source_id == edge[:targets]&.first

        find_endpoint(graph, source_id)
      end

      def render_clusters(graph, svg)
        (graph[:clusters] || []).each { |cluster| render_cluster(cluster, svg) }
      end

      def render_cluster(cluster, svg)
        group = Svg::Group.new.tap { |g| g.id = "cluster-#{cluster[:id]}" }
        group.children << cluster_box(cluster)

        label = (cluster[:labels] || []).first
        group.children << cluster_title(cluster, label) if label

        svg << group
      end

      def cluster_box(cluster)
        Svg::Rect.new.tap do |rect|
          rect.x = cluster[:x].to_i
          rect.y = cluster[:y].to_i
          rect.width = cluster[:width].to_i
          rect.height = cluster[:height].to_i
          rect.rx = CLUSTER_CORNER
          rect.ry = CLUSTER_CORNER
          apply_theme_to_cluster(rect)
        end
      end

      # mermaid writes the title inside the box, centred along the top.
      def cluster_title(cluster, label)
        Svg::Text.new.tap do |text|
          text.x = cluster[:x] + (cluster[:width].to_i / 2)
          text.y = cluster[:y] + CLUSTER_TITLE_BASELINE
          text.content = label[:text]
          apply_theme_to_text(text)
          text.text_anchor = 'middle'
          text.dominant_baseline = 'middle'
        end
      end

      # A cluster is a surface behind the nodes, not another node, so it
      # borrows the palette's variant surface rather than the node fill.
      def apply_theme_to_cluster(element)
        element.fill = theme_color(:surface_variant) if theme_color(:surface_variant)
        element.stroke = theme_color(:node_stroke) if theme_color(:node_stroke)
        return unless theme_shape(:stroke_width)

        element.stroke_width = theme_shape(:stroke_width).to_s
      end

      # A self loop can reach past its own node on the right, and neither
      # its bends nor its label is a box this counts on its own — see
      # `self_loop_reach`. Without folding that in, a loop thrown right
      # or the label past it clips against a viewBox sized for the boxes
      # alone.
      def calculate_width(graph)
        boxes = drawn(graph)
        return 800 if boxes.empty?

        max_x = boxes.map do |node|
          (node[:x] || 0) + (node[:width] || 100)
        end.max

        [max_x, self_loop_reach(graph)[0]].max + 40 # Add padding
      end

      def calculate_height(graph)
        boxes = drawn(graph)
        return 600 if boxes.empty?

        max_y = boxes.map do |node|
          (node[:y] || 0) + (node[:height] || 50)
        end.max

        [max_y, self_loop_reach(graph)[1]].max + 40 # Add padding
      end

      # A cluster can reach past the nodes inside it, so the page is
      # measured against the boxes as well.
      def drawn(graph)
        (graph[:children] || []) + (graph[:clusters] || [])
      end

      def render_nodes(graph, svg)
        graph[:children].each do |node|
          render_node(node, svg)
        end
      end

      def render_node(node, svg)
        shape = node.dig(:metadata, :shape) || 'rect'

        # Create group for node and its label
        group = Svg::Group.new.tap do |g|
          g.id = "node-#{node[:id]}"
        end

        # Render node shape
        shape_element = create_node_shape(node, shape)
        group.children << shape_element if shape_element

        # Render node label
        if node[:labels] && !node[:labels].empty?
          label = node[:labels].first
          text_element = create_node_label(node, label)
          group.children << text_element if text_element
        end

        svg << group
      end

      def create_node_shape(node, shape)
        x = node[:x] || 0
        y = node[:y] || 0
        width = node[:width] || 100
        height = node[:height] || 50

        case NODE_OUTLINES[shape]
        when :rounded then create_rounded_rectangle(x, y, width, height)
        when :circle then create_circle_shape(x, y, width, height)
        when :rhombus then create_rhombus(x, y, width, height)
        when :hexagon then create_hexagon(x, y, width, height)
        else create_rectangle(x, y, width, height)
        end
      end

      def create_rectangle(x, y, width, height)
        Svg::Rect.new.tap do |rect|
          rect.x = x
          rect.y = y
          rect.width = width
          rect.height = height
          apply_theme_to_node(rect)
        end
      end

      def create_rounded_rectangle(x, y, width, height)
        Svg::Rect.new.tap do |rect|
          rect.x = x
          rect.y = y
          rect.width = width
          rect.height = height
          rect.rx = height / 2.0
          rect.ry = height / 2.0
          apply_theme_to_node(rect)
        end
      end

      def create_circle_shape(x, y, width, height)
        cx = x + (width / 2.0)
        cy = y + (height / 2.0)
        r = [width, height].min / 2.0

        Svg::Circle.new.tap do |circle|
          circle.cx = cx
          circle.cy = cy
          circle.r = r
          apply_theme_to_node(circle)
        end
      end

      def create_rhombus(x, y, width, height)
        cx = x + (width / 2.0)
        cy = y + (height / 2.0)

        points = [
          "#{cx},#{y}",
          "#{x + width},#{cy}",
          "#{cx},#{y + height}",
          "#{x},#{cy}"
        ].join(' ')

        Svg::Polygon.new.tap do |polygon|
          polygon.points = points
          apply_theme_to_node(polygon)
        end
      end

      def create_hexagon(x, y, width, height)
        cy = y + (height / 2.0)
        w4 = width / 4.0

        points = [
          "#{x + w4},#{y}",
          "#{x + width - w4},#{y}",
          "#{x + width},#{cy}",
          "#{x + width - w4},#{y + height}",
          "#{x + w4},#{y + height}",
          "#{x},#{cy}"
        ].join(' ')

        Svg::Polygon.new.tap do |polygon|
          polygon.points = points
          apply_theme_to_node(polygon)
        end
      end

      def create_node_label(node, label)
        x = node[:x] || 0
        y = node[:y] || 0
        width = node[:width] || 100
        height = node[:height] || 50

        # Center text in node. Halved as a float like the shape and the
        # path are, so a hand-built node with odd integer sides puts its
        # label on the same centre they use.
        text_x = x + (width / 2.0)
        text_y = y + (height / 2.0)

        Svg::Text.new.tap do |text|
          text.x = text_x
          text.y = text_y
          text.content = label[:text]
          apply_theme_to_text(text)
          text.text_anchor = 'middle'
          text.dominant_baseline = 'middle'
        end
      end

      def render_edges(graph, svg)
        graph[:edges].each do |edge|
          render_edge(edge, graph, svg)
        end
      end

      def render_edge(edge, graph, svg)
        source = find_endpoint(graph, edge[:sources]&.first)
        target = find_endpoint(graph, edge[:targets]&.first)

        return unless source && target

        route, bends, label_route = edge_route(edge, graph, source, target)
        path_data = calculate_edge_path(route, bends)
        type = edge.dig(:metadata, :arrow_type).to_s

        # Create path element
        path = Svg::Path.new.tap do |p|
          p.d = path_data
          p.fill = 'none'
          apply_theme_to_edge(p)
          apply_link_weight(p, type)
          # The parsed link still emits a path, but no stroke keeps it
          # hidden. Today's edge-blind layout reserves no space for it.
          p.stroke = 'none' if type == 'invisible'
        end

        # Create group for edge and label
        group = Svg::Group.new.tap do |g|
          g.id = "edge-#{edge[:id]}"
        end

        group.children << path
        render_edge_heads(group, route, source, target, type, bends)

        # Render edge label if present
        if edge[:labels] && !edge[:labels].empty?
          label = edge[:labels].first
          text = create_edge_label(source, target, label, bends, label_route)
          group.children << text if text
        end

        svg << group
      end

      # An edge may end on a cluster: mermaid joins the boxes when an
      # edge names a subgraph. A cluster carries the same x, y, width and
      # height a node does, so the routing needs no special case — which
      # is why this looks past the nodes, and why it is not called
      # `find_node` any more.
      def find_endpoint(graph, node_id)
        return nil unless node_id

        (graph[:children] || []).find { |n| n[:id] == node_id } ||
          (graph[:clusters] || []).find { |c| c[:id] == node_id }
      end

      def calculate_edge_path(route, bends)
        sx, sy, tx, ty = route
        return create_path_with_bends(sx, sy, tx, ty, bends) if bends&.any?

        "M #{sx} #{sy} L #{tx} #{ty}"
      end

      # Where one edge runs, as [ends, bends, label run].
      #
      # A node linked to ITSELF is mermaid's own loop, and mmdc throws it
      # off the face the flow leaves by: measured on mmdc 11.12.0,
      # `flowchart TD\nA --> A` starts at y 62 — the node's BOTTOM — and
      # never reaches past its right edge, while the LR spelling starts at
      # x 77.4, the right edge. The router knows nothing of the flow
      # direction and always throws the loop rightwards, so a true self
      # link is built here and only the rest of the graph goes through it.
      #
      # Everything else takes the router's run, which is what pulls an end
      # back to a CLUSTER border and rounds it into the corner it was
      # drawn with, and what carries a run around boxes that overlap. Its
      # ends are kept exactly as routed whenever it CHOSE them — a cluster
      # at either end, or a run it generated bends for. A plain
      # node-to-node run it leaves at the two centres, and those are
      # pulled out to the drawn outline here, so the line stops where its
      # head sits.
      def edge_route(edge, graph, source, target)
        if source[:id] == target[:id]
          bends = edge_bends(edge, source, target, self_loop_side(graph))
          ends = clipped_ends(bends, source, target)
          return [ends, bends, ends]
        end

        elk_bends = edge.dig(:sections, 0, :bendPoints)
        points, label_route = edge_router.route(source, target, elk_bends)
        # Generated routes carry their own bends; an ordinary route keeps
        # whatever the layout left in the ELK section.
        bends = points.length > 2 ? points[1...-1] : (elk_bends || [])
        if points.length > 2 || EdgeRouter.cluster?(source) ||
           EdgeRouter.cluster?(target)
          return [EdgeRouter.ends_of(points), bends, label_route]
        end

        route = clipped_ends(bends, source, target)
        # A plain run's label sits on the stretch just re-clipped, so it
        # follows the line rather than the centres it no longer joins.
        [route, bends, route]
      end

      # Both ends on the outline of the box each one touches.
      def clipped_ends(bends, source, target)
        [*edge_end(bends, source, target, :source),
         *edge_end(bends, source, target, :target)]
      end

      # One router for the whole document. It holds nothing between
      # calls, so the same object answers every edge.
      def edge_router
        @edge_router ||= EdgeRouter.new
      end

      # Clipped to the node's outline the way mermaid clips it, aiming
      # along the segment that actually leaves or arrives — so the line
      # stops exactly where its head sits. There is no route yet to read
      # this off — building one is what this is for — so it is worked
      # out from the node centres, the same way `head_tip_geometry` falls
      # back to when a route has no cluster end to trust instead. Running
      # to the centres unclipped showed the line through a node the theme
      # painted `none`.
      #
      # Rounded like the heads are: an outline crossing at an angle lands
      # on a long decimal, and 87 of 232 sampled path coordinates carried
      # one before this.
      def edge_end(bends, source, target, which)
        boundary_geometry(bends, source, target, which)
          .values_at(:tip_x, :tip_y).map { |n| n.round(1) }
      end

      # The node-centre geometry `edge_end` builds a route from, before
      # any route exists to hand a head instead.
      def boundary_geometry(bends, source, target, which)
        node, other = which == :target ? [target, source] : [source, target]
        approach = which == :target ? bends.last : bends.first
        from_x, from_y = approach ? [approach[:x], approach[:y]] : node_centre(other)
        tip_x, tip_y = node_boundary(node, from_x, from_y)

        { tip_x: tip_x, tip_y: tip_y, from_x: from_x, from_y: from_y }
      end

      # The graph names the direction it flows in; a graph built by hand
      # need not, and then the loop hangs below as it does for TD.
      def self_loop_side(graph)
        SELF_LOOP_SIDES[graph.dig(:layoutOptions, 'elk.direction')] ||
          SELF_LOOP_SIDES['DOWN']
      end

      # A laid-out graph already knows where its edge turns. Only a self
      # link without that route needs corners to keep it from disappearing.
      def edge_bends(edge, source, target, side)
        bend_points = edge.dig(:sections, 0, :bendPoints) || []
        return bend_points unless source[:id] == target[:id] && bend_points.empty?

        self_loop_bends(source, side)
      end

      # Where the loop sits. It goes out past the node edge by 0.45 of
      # the node's SHORTER side, and runs 0.175 of the dimension it
      # spreads ACROSS either side of centre — the width for an up or
      # down loop, the height for a left or right one.
      #
      # That span is then held between 18 and 50, and the answer held
      # again to half the spreading dimension. The two limits are applied
      # in that order, not together, and the second one wins where they
      # disagree: a 34-high node's sideways loop reaches 17, not 18. The
      # note inside the method says why it has to be last.
      #
      # The depth is mmdc's; the half span is ours — see the note on the
      # constants. The depth is capped at 48. No node the layout builds
      # reaches it, but a graph handed straight to the renderer can, so
      # the cap is written rather than assumed.
      def self_loop_bends(node, side)
        cx, cy = node_centre(node)
        width = node[:width] || 100
        height = node[:height] || 50
        out_x, out_y = side
        # The span runs across the throw, so it is measured across it too:
        # a downward loop spreads along x and takes its span from the width,
        # a rightward one spreads along y and takes it from the height.
        #
        # Then it is held inside that same dimension. The lower limit is 18
        # and a node is 34 high, so a horizontal loop's clamped span could
        # exceed the half height — and once a corner sits outside the face,
        # the line into the centre leaves through the next face round and
        # the loop attaches to the top and bottom instead of the side.
        span_side = out_y.zero? ? height : width
        half_span =
          (span_side * SELF_LOOP_HALF_SPAN).clamp(SELF_LOOP_HALF_SPAN_LIMITS)
        half_span = [half_span, span_side / 2.0].min
        depth = [[width, height].min * SELF_LOOP_DEPTH, SELF_LOOP_MAX_DEPTH].min

        edge_x, edge_y = node_boundary(node, cx + out_x, cy + out_y)
        far_x = edge_x + (out_x * depth)
        far_y = edge_y + (out_y * depth)
        [{ x: far_x - (out_y.abs * half_span),
           y: far_y - (out_x.abs * half_span) },
         { x: far_x + (out_y.abs * half_span),
           y: far_y + (out_x.abs * half_span) }]
      end

      def create_path_with_bends(sx, sy, tx, ty, bend_points)
        path_parts = ["M #{sx} #{sy}"]

        bend_points.each do |point|
          path_parts << "L #{point[:x].round(1)} #{point[:y].round(1)}"
        end

        path_parts << "L #{tx} #{ty}"
        path_parts.join(' ')
      end

      # A thick link is drawn heavier and a dotted one dashed. Every type
      # that parsed used to reach the same solid stroke, so `-.-` and
      # `---` came out as the same picture. `===` drew nothing at all —
      # it was rejected before it reached the renderer.
      #
      # A theme already has a word for both of these — every built-in one
      # names `stroke_width_thick` and `dash_pattern_dotted` — so they are
      # what a thick or dotted link is drawn with. Multiplying the plain
      # width by mmdc's 3.5 instead ignored the theme and drew
      # high_contrast's thick line at 10.5 where it asks for 4.
      #
      # A dotted link is dashed and nothing else — only `thick_` touches
      # the width. That follows mermaid: mmdc marks `-.-` as
      # `edge-thickness-normal edge-pattern-dotted`, so dotting a line
      # does not thin it, and the theme's plain width still applies.
      def apply_link_weight(path, type)
        path.stroke_width = thick_width.to_s if type.start_with?('thick_')
        path.stroke_dasharray = dotted_dashes if type.start_with?('dotted_')
      end

      # Three answers, in order. A theme naming a thick width gets it. One
      # naming only a plain width gets mmdc's multiple on top of ITS
      # width, not on top of mmdc's — a 2.0 line thickens to 7.0. A theme
      # naming neither falls back to mmdc outright, whose thick line is
      # 3.5 times its normal one and whose normal one is 1.
      def thick_width
        theme_shape(:stroke_width_thick) ||
          ((theme_shape(:stroke_width) || 1.0) * LINK_THICK_MULTIPLE)
      end

      def dotted_dashes
        theme_shape(:dash_pattern_dotted) || LINK_DOTTED_DASHES
      end

      # The head is drawn, not referenced: `url(#arrowhead)` pointed at a
      # marker this document never defined, so an arrow and an open link
      # rasterised identically. A `_both` type carries one at each end.
      # An invisible link needs no guard of its own: it has no entry in
      # EDGE_HEADS, so it falls out here with everything else that draws
      # no head.
      def render_edge_heads(group, route, source, target, type, bends)
        shape =
          EDGE_HEADS[type.sub(/\A(?:thick|dotted)_/, '').delete_suffix('_both')]
        return unless shape

        edge_head_ends(type).each do |which|
          draw_edge_head(
            group, head_tip_geometry(route, bends, source, target, which), shape
          )
        end
      end

      # The head's tip and approach, read off the route the path itself
      # draws rather than recomputed from the node centres. A cluster's
      # end was already pulled onto its outline by `EdgeRouter` — corner
      # rounding, containment and all — so that end is trusted outright:
      # recomputing it from "the other node's centre" disagreed whenever
      # a node sat inside the cluster it pointed at, landing the head on
      # the wrong face or, reversed, on top of its own tip.
      #
      # A plain node's end stays at its centre in the route (the node is
      # painted over the line, so it never needed trimming) and is
      # projected onto its outline here, same as before — only the point
      # it approaches FROM changes, from the other node's raw centre to
      # the route's own near end, which is the same point on an ordinary
      # straight run and the correct one when a cluster sits between them.
      def head_tip_geometry(route, bends, source, target, which)
        node = which == :target ? target : source
        other = which == :target ? :source : :target
        approach = which == :target ? bends.last : bends.first
        from_x, from_y = approach ? [approach[:x], approach[:y]] : route_end(route, other)
        tip_x, tip_y =
          EdgeRouter.cluster?(node) ? route_end(route, which) : node_boundary(node, from_x, from_y)

        { tip_x: tip_x, tip_y: tip_y, from_x: from_x, from_y: from_y }
      end

      # The [x, y] a route ends with — the source end or the target end.
      def route_end(route, which)
        which == :target ? route.last(2) : route.first(2)
      end

      def edge_head_ends(type)
        type.end_with?('_both') ? [:source, :target] : [:target]
      end

      def node_centre(node)
        EdgeRouter.centre(node).values_at(:x, :y)
      end

      # A head drawn at the node's centre is under the node, and the nodes
      # are painted afterwards — so every head was invisible and `---` and
      # `-->` rasterised the same. `--x` and `--o` were rejected outright
      # and drew nothing. The tip belongs on the node's edge, where the
      # line meets it.
      def node_boundary(node, from_x, from_y)
        cx, cy = node_centre(node)
        dx = from_x - cx
        dy = from_y - cy
        return [cx, cy] if dx.zero? && dy.zero?

        scale = boundary_scale(node, dx, dy)
        [cx + (dx * scale), cy + (dy * scale)]
      end

      # How far along the ray out of the centre the node's edge lies, as
      # a multiple of (dx, dy). The box answer is only right for a box: a
      # diamond, a circle and a hexagon all pull in from the corners a box
      # keeps, so a head coming in diagonally landed outside the shape it
      # was pointing at.
      #
      # Dispatched off NODE_OUTLINES, the same table `create_node_shape`
      # draws from, so the outline a head lands on is the outline that
      # was drawn.
      def boundary_scale(node, dx, dy)
        half_w = (node[:width] || 100) / 2.0
        half_h = (node[:height] || 50) / 2.0

        case NODE_OUTLINES[node.dig(:metadata, :shape)]
        when :rhombus then rhombus_scale(half_w, half_h, dx, dy)
        when :circle then circle_scale(half_w, half_h, dx, dy)
        when :hexagon then hexagon_scale(half_w, half_h, dx, dy)
        when :rounded then stadium_scale(half_w, half_h, dx, dy)
        else box_scale(half_w, half_h, dx, dy)
        end
      end

      def box_scale(half_w, half_h, dx, dy)
        [dx.zero? ? Float::INFINITY : half_w / dx.abs,
         dy.zero? ? Float::INFINITY : half_h / dy.abs].min
      end

      # A diamond's straight sides make the two axis ratios additive.
      def rhombus_scale(half_w, half_h, dx, dy)
        1 / (axis_ratio(dx, half_w) + axis_ratio(dy, half_h))
      end

      # The node is drawn as a circle on the shorter side, not an ellipse.
      def circle_scale(half_w, half_h, dx, dy)
        span = Math.hypot(dx, dy)

        [half_w, half_h].min / span
      end

      # A hexagon is the box with a quarter of its width sliced off each
      # end, top and bottom. So it is the box's flat top and bottom, and
      # the four sloped faces, whichever the ray meets first.
      def hexagon_scale(half_w, half_h, dx, dy)
        slope = 1 / (axis_ratio(dx, half_w) + axis_ratio(dy, 2 * half_h))
        [slope, dy.zero? ? Float::INFINITY : half_h / dy.abs].min
      end

      # A capsule: a flat top and bottom between two semicircular ends of
      # the node's half height. The flat answers whenever the ray leaves
      # through it; past that the ray meets the near cap.
      #
      # The ends are round while the node is wider than it is tall, which
      # any visible label makes it: the height is a fixed 34 and the
      # padding alone is 30. A label that measures nothing — `A( )` — is
      # the one that does not, and SVG narrows `rx` to half the width
      # there, so the node is drawn as an ellipse and the caps answer for
      # the whole outline.
      def stadium_scale(half_w, half_h, dx, dy)
        return ellipse_scale(half_w, half_h, dx, dy) if half_w <= half_h

        flat = dy.zero? ? Float::INFINITY : half_h / dy.abs
        straight = half_w - half_h
        return flat if (flat * dx).abs <= straight

        cap_intersection(straight * (dx.negative? ? -1 : 1), half_h, dx, dy)
      end

      # SVG clamps `rx` to half the width, so a stadium no wider than it
      # is tall is drawn as a plain ellipse rather than a capsule.
      def ellipse_scale(half_w, half_h, dx, dy)
        x_ratio = axis_ratio(dx, half_w)
        y_ratio = axis_ratio(dy, half_h)

        1 / Math.sqrt((x_ratio**2) + (y_ratio**2))
      end

      # A collapsed axis only blocks rays that try to cross it.
      def axis_ratio(delta, half_extent)
        return 0.0 if delta.zero?

        delta.abs / half_extent
      end

      # Where the ray out of the centre meets a cap of radius `radius`
      # centred at (centre_x, 0) — the far root, so the tip lands on the
      # outside of the cap rather than the inside.
      def cap_intersection(centre_x, radius, dx, dy)
        a = (dx * dx) + (dy * dy)
        b = dx * centre_x
        c = (centre_x * centre_x) - (radius * radius)

        (b + Math.sqrt([(b * b) - (a * c), 0].max)) / a
      end

      def draw_edge_head(group, geometry, shape)
        case shape
        when :cross
          draw_edge_cross(group, *backed_off(geometry, CROSS_HEAD_REACH),
                          *geometry.values_at(:from_x, :from_y))
        when :circle
          draw_edge_circle(group, *backed_off(geometry, CIRCLE_HEAD_REACH))
        else
          draw_edge_arrow(group, *geometry.values_at(:tip_x, :tip_y,
                                                     :from_x, :from_y))
        end
      end

      # mmdc puts the marker's reference point on the node boundary, so a
      # circle's and a cross's CENTRE sit behind it by that marker's
      # reference distance. Only those two come through here.
      #
      # An arrow does not. `pointEnd`'s refX is the middle of the
      # triangle, and mmdc ends the line 4 short so the tip still lands on
      # the boundary — which is where this draws it, with no back-off.
      def backed_off(geometry, reach)
        tip_x, tip_y, from_x, from_y =
          geometry.values_at(:tip_x, :tip_y, :from_x, :from_y)
        along_x, along_y = unit_towards(tip_x, tip_y, from_x, from_y)

        [tip_x + (along_x * reach), tip_y + (along_y * reach)]
      end

      # The heads follow the theme, like the line they belong to. Hardcoded
      # black left a white path with black heads on a dark theme.
      #
      # nil when the theme names no edge colour. A theme is whatever the
      # caller passes and nothing fills its gaps in, so that happens.
      def edge_ink
        theme_color(:edge_stroke)
      end

      # mmdc's triangle, not an angle either side of the axis: the corners
      # sit ARROW_LENGTH back along the line and ARROW_HALF_WIDTH across
      # it. Reading them off a fixed angle drew a head 3.1 wide where
      # mermaid draws 4.
      def draw_edge_arrow(group, tip_x, tip_y, from_x, from_y)
        along_x, along_y = unit_towards(tip_x, tip_y, from_x, from_y)
        back_x = tip_x + (along_x * ARROW_LENGTH)
        back_y = tip_y + (along_y * ARROW_LENGTH)

        group.children << Svg::Polygon.new.tap do |poly|
          poly.points = [
            [tip_x, tip_y],
            [back_x - (along_y * ARROW_HALF_WIDTH),
             back_y + (along_x * ARROW_HALF_WIDTH)],
            [back_x + (along_y * ARROW_HALF_WIDTH),
             back_y - (along_x * ARROW_HALF_WIDTH)]
          ].map { |x, y| "#{x.round(1)},#{y.round(1)}" }.join(' ')
          # An unpainted polygon is not an invisible one: SVG fills it
          # black. A theme with no edge colour drew black heads floating
          # over nothing, because the line it belonged to had no stroke
          # and a path with no stroke really is invisible. So say `none`
          # out loud for the fill; leaving the stroke off is enough.
          poly.fill = edge_ink || 'none'
          poly.stroke = edge_ink
        end
      end

      # The unit vector from the tip back along the line it arrived on.
      # Zero when the two points coincide, which is a direction no head
      # can be turned by — but never a NaN one. Only the arrow collapses
      # to nothing there; a circle keeps its radius, and the cross takes
      # the horizontal fallback in `draw_edge_cross` and stays full size.
      def unit_towards(tip_x, tip_y, from_x, from_y)
        span = Math.hypot(from_x - tip_x, from_y - tip_y)
        return [0.0, 0.0] if span.zero?

        [(from_x - tip_x) / span, (from_y - tip_y) / span]
      end

      # mmdc's cross marker is `orient="auto"`, so it turns with the line
      # it ends. Drawing it square to the screen put its arms at the wrong
      # angle on every edge that is not axis-aligned.
      def draw_edge_cross(group, tip_x, tip_y, from_x, from_y)
        along_x, along_y = unit_towards(tip_x, tip_y, from_x, from_y)
        # Two nodes at one point leave no direction to turn with; draw
        # it as if the line ran horizontally into the tip.
        along_x = 1.0 if along_x.zero? && along_y.zero?
        arm_x = (along_x - along_y) * CROSS_HEAD_HALF
        arm_y = (along_y + along_x) * CROSS_HEAD_HALF

        [[arm_x, arm_y], [arm_y, -arm_x]].each do |dx, dy|
          group.children << Svg::Line.new.tap do |line|
            line.x1 = (tip_x - dx).round(1)
            line.y1 = (tip_y - dy).round(1)
            line.x2 = (tip_x + dx).round(1)
            line.y2 = (tip_y + dy).round(1)
            line.stroke = edge_ink
            line.stroke_width = format('%g', CROSS_HEAD_STROKE)
          end
        end
      end

      # A filled dot, not a ring. mmdc's circleEnd marker sets no fill of
      # its own and inherits the `.marker` one, so it comes out solid in
      # the edge's own colour; drawing it hollow made `--o` a different
      # picture from the one mermaid draws. Painted the way the arrow
      # head is, so a theme naming no edge colour leaves it invisible
      # rather than black.
      def draw_edge_circle(group, tip_x, tip_y)
        group.children << Svg::Circle.new.tap do |circle|
          circle.cx = tip_x.round(1)
          circle.cy = tip_y.round(1)
          circle.r = CIRCLE_HEAD_RADIUS
          circle.fill = edge_ink || 'none'
          circle.stroke = edge_ink
          circle.stroke_width = format('%g', CIRCLE_HEAD_STROKE)
        end
      end

      def create_edge_label(source, target, label, bends, route)
        mid_x, mid_y = edge_label_anchor(source, target, bends, route)

        Svg::Text.new.tap do |text|
          text.x = mid_x
          text.y = mid_y
          text.content = label[:text]
          apply_theme_to_text(text)
          # Use smaller font for edge labels
          if theme_typography(:font_size_small)
            text.font_size = theme_typography(:font_size_small).to_s
          end
          text.text_anchor = 'middle'
        end
      end

      # Midway along the run that was ACTUALLY DRAWN, lifted five straight
      # up. Straight up clears a horizontal line and only slides along a
      # vertical one. Measuring from the two centres instead left a label
      # on a trimmed edge sitting inside the box the line no longer
      # starts in, which is why the drawn run is passed in rather than
      # recomputed from the boxes.
      #
      # A self link's two ends are the same centre, so that midpoint was
      # the node's own centre and the label sat buried under a node
      # painted after it. Its loop corners are out past the node, so the
      # middle of those carries the label clear.
      def edge_label_anchor(source, target, bends, route)
        return loop_label_anchor(source, bends) if source[:id] == target[:id]

        sx, sy, tx, ty = route
        [(sx + tx) / 2.0, ((sy + ty) / 2.0) - EDGE_LABEL_LIFT]
      end

      # mmdc hangs a loop's label past the loop. Lifting it the way an
      # ordinary label is lifted pulled it back towards the node instead
      # — the loop is thrown downwards as often as not — so it goes
      # outward here, along the line from the node to the loop.
      def loop_label_anchor(node, bends)
        mid_x = (bends.first[:x] + bends.last[:x]) / 2.0
        mid_y = (bends.first[:y] + bends.last[:y]) / 2.0
        cx, cy = node_centre(node)
        span = Math.hypot(mid_x - cx, mid_y - cy)
        return [mid_x, mid_y] if span.zero?

        [mid_x + ((mid_x - cx) / span * EDGE_LABEL_LIFT),
         mid_y + ((mid_y - cy) / span * EDGE_LABEL_LIFT)]
      end
    end
  end
end
