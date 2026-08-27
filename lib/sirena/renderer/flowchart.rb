# frozen_string_literal: true

require_relative 'base'

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
      # Renders a laid-out graph to SVG.
      #
      # @param graph [Hash] laid-out graph with node positions
      # @return [Svg::Document] the rendered SVG document
      def render(graph)
        svg = create_document(graph)

        # Render edges first (so they appear under nodes)
        render_edges(graph, svg) if graph[:edges]

        # Render nodes
        render_nodes(graph, svg) if graph[:children]

        svg
      end

      protected

      def calculate_width(graph)
        return 800 unless graph[:children]

        max_x = graph[:children].map do |node|
          (node[:x] || 0) + (node[:width] || 100)
        end.max || 800

        max_x + 40 # Add padding
      end

      def calculate_height(graph)
        return 600 unless graph[:children]

        max_y = graph[:children].map do |node|
          (node[:y] || 0) + (node[:height] || 50)
        end.max || 600

        max_y + 40 # Add padding
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

        case shape
        when 'rect', 'subroutine'
          create_rectangle(x, y, width, height)
        when 'rounded', 'stadium'
          create_rounded_rectangle(x, y, width, height)
        when 'circle', 'double_circle'
          create_circle_shape(x, y, width, height)
        when 'rhombus'
          create_rhombus(x, y, width, height)
        when 'hexagon'
          create_hexagon(x, y, width, height)
        else
          create_rectangle(x, y, width, height)
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

        # Center text in node
        text_x = x + width / 2
        text_y = y + height / 2

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

      # What each link type draws, read off mmdc's own SVG. The line half
      # is its `edge-thickness-*` and `edge-pattern-*` classes; the head
      # half is its `marker-start` and `marker-end`.
      LINK_THICK_MULTIPLE = 3.5
      LINK_DOTTED_DASHES = '2'
      EDGE_HEADS = { 'arrow' => :arrow, 'cross' => :cross,
                     'circle' => :circle,
                     'bidirectional' => :arrow }.freeze
      # Each head is mmdc's own marker, scaled the way mmdc scales it.
      # `pointEnd` is a 0..10 viewBox drawn at markerWidth 8, so its
      # `M 0 0 L 10 5 L 0 10 z` lands 8 long and 4 either side of the axis.
      ARROW_LENGTH = 8.0
      ARROW_HALF_WIDTH = 4.0
      # `circleEnd` is a radius-5 circle in a 0..10 viewBox at markerWidth
      # 11, so its drawn radius is 5.5. `crossEnd` uses the diagonals of a
      # 9x9 box. The 4.5 is each axis's half-run, making each drawn half-arm
      # 4.5 * sqrt(2) long.
      CIRCLE_HEAD_RADIUS = 5.5
      CROSS_HEAD_HALF = 4.5
      # mmdc fixes its circle stroke at 1 and its cross stroke at 2. They
      # stay numeric because the reach below uses them. `%g` writes these
      # marker strokes the way mmdc does. A line's stroke-width comes from
      # the theme and keeps its own formatting.
      CIRCLE_HEAD_STROKE = 1.0
      CROSS_HEAD_STROKE = 2.0
      # How far each reaches along the line it arrives on: its geometry
      # plus the half stroke painted outside it. Backing off the geometry
      # alone left half the stroke lying over the node.
      CIRCLE_HEAD_REACH = CIRCLE_HEAD_RADIUS + (CIRCLE_HEAD_STROKE / 2)
      CROSS_HEAD_REACH = CROSS_HEAD_HALF + (CROSS_HEAD_STROKE / 2)

      # Drawn with their ends rounded the whole way, so a head aiming at
      # one pulls in from the corners as far as a circle's does.
      STADIUM_SHAPES = %w[rounded stadium].freeze

      # How far an edge label sits off the line it belongs to.
      EDGE_LABEL_LIFT = 5.0

      # Only the depth has the oracle behind it, and it is measured across
      # sizes rather than read off one node. mmdc loops 24.3 past a 69.4x54
      # node and 45.0 past a 100x102 one — 0.45 of the shorter side both
      # times — and 48.0 past a 108.4x366 one, where the ratio wants 48.8.
      # So the ratio and the 48 cap are both mmdc's.
      #
      # The reach and its limits do NOT. mermaid draws a self loop as a
      # bezier and this draws a two-corner polyline, so their widths are
      # not the same measurement and no mmdc run settles one from the
      # other. They are pinned by the specs below this file, not by the
      # oracle. Anyone changing them should know which half is which.
      SELF_LOOP_DEPTH = 0.45
      SELF_LOOP_REACH = 0.175
      SELF_LOOP_REACH_LIMITS = (18.0..50.0)
      SELF_LOOP_MAX_DEPTH = 48.0
      # Which way a self loop is thrown: the way the diagram flows. mmdc
      # loops below for TD, right for LR, left for RL and above for BT.
      SELF_LOOP_SIDES = { 'DOWN' => [0, 1], 'UP' => [0, -1],
                          'RIGHT' => [1, 0], 'LEFT' => [-1, 0] }.freeze

      def render_edge(edge, graph, svg)
        source = find_node(graph, edge[:sources]&.first)
        target = find_node(graph, edge[:targets]&.first)

        return unless source && target

        bends = edge_bends(edge, source, target, self_loop_side(graph))
        path_data = calculate_edge_path(source, target, bends)
        type = edge.dig(:metadata, :arrow_type).to_s

        # Create path element
        path = Svg::Path.new.tap do |p|
          p.d = path_data
          p.fill = 'none'
          apply_theme_to_edge(p)
          apply_link_weight(p, type)
          # An invisible link occupies layout space and draws nothing.
          p.stroke = 'none' if type == 'invisible'
        end

        # Create group for edge and label
        group = Svg::Group.new.tap do |g|
          g.id = "edge-#{edge[:id]}"
        end

        group.children << path
        render_edge_heads(group, source, target, type, bends)

        # Render edge label if present
        if edge[:labels] && !edge[:labels].empty?
          text = create_edge_label(source, target, edge[:labels].first, bends)
          group.children << text if text
        end

        svg << group
      end

      def find_node(graph, node_id)
        return nil unless graph[:children] && node_id

        graph[:children].find { |n| n[:id] == node_id }
      end

      def calculate_edge_path(source, target, bends)
        # `node_centre` keeps the path on the same centre as its heads and
        # label. The old inline calculation used integer division, so odd
        # widths left the line half a pixel from where its head pointed.
        sx, sy = node_centre(source)
        tx, ty = node_centre(target)

        return create_path_with_bends(sx, sy, tx, ty, bends) if bends.any?

        "M #{sx} #{sy} L #{tx} #{ty}"
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

      # Where the loop sits. It reaches past the node edge by 0.45 of the
      # node's SHORTER side, and spans 0.175 of its WIDTH either side of
      # centre whichever way it is thrown, never narrower than 18 or wider
      # than 50. The depth is mmdc's; the width is ours — see the note on
      # the constants.
      #
      # The depth is capped at 48. No node the layout builds reaches it,
      # but a graph handed straight to the renderer can, so the cap is
      # written rather than assumed.
      def self_loop_bends(node, side)
        cx, cy = node_centre(node)
        width = node[:width] || 100
        height = node[:height] || 50
        reach = (width * SELF_LOOP_REACH).clamp(SELF_LOOP_REACH_LIMITS)
        depth = [[width, height].min * SELF_LOOP_DEPTH, SELF_LOOP_MAX_DEPTH].min
        out_x, out_y = side

        edge_x, edge_y = node_boundary(node, cx + out_x, cy + out_y)
        far_x = edge_x + (out_x * depth)
        far_y = edge_y + (out_y * depth)
        [{ x: far_x - (out_y.abs * reach), y: far_y - (out_x.abs * reach) },
         { x: far_x + (out_y.abs * reach), y: far_y + (out_x.abs * reach) }]
      end

      def create_path_with_bends(sx, sy, tx, ty, bend_points)
        path_parts = ["M #{sx} #{sy}"]

        bend_points.each do |point|
          path_parts << "L #{point[:x]} #{point[:y]}"
        end

        path_parts << "L #{tx} #{ty}"
        path_parts.join(' ')
      end

      # A thick link is drawn heavier and a dotted one dashed. Every type
      # used to reach the same solid stroke, so `===`, `-.-` and `---`
      # came out as the same picture.
      #
      # A theme already has a word for both of these — every built-in one
      # names `stroke_width_thick` and `dash_pattern_dotted` — so they are
      # what a thick or dotted link is drawn with. Multiplying the plain
      # width by mmdc's 3.5 instead ignored the theme and drew
      # high_contrast's thick line at 10.5 where it asks for 4.
      #
      # A dotted link keeps the plain width. It used to be forced to 2
      # here and came out thinner than its own theme's line.
      def apply_link_weight(path, type)
        path.stroke_width = thick_width.to_s if type.start_with?('thick_')
        path.stroke_dasharray = dotted_dashes if type.start_with?('dotted_')
      end

      # What mmdc falls back to when the theme names neither: its own
      # thick line is 3.5 times its normal one, and its normal one is 1.
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
      def render_edge_heads(group, source, target, type, bends)
        shape =
          EDGE_HEADS[type.sub(/\A(?:thick|dotted)_/, '').delete_suffix('_both')]
        return unless shape

        edge_head_ends(type).each do |which|
          draw_edge_head(group, head_geometry(bends, source, target, which),
                         shape)
        end
      end

      # The head points along the segment it sits on, not along the span:
      # a path that bends and arrives vertically was drawing a diagonal
      # arrow. The target head follows the last bend point in, the source
      # head follows the first one out.
      def head_geometry(bends, source, target, which)
        node, other = which == :target ? [target, source] : [source, target]
        approach = which == :target ? bends.last : bends.first
        from_x, from_y = if approach
                           [approach[:x], approach[:y]]
                         else
                           node_centre(other)
                         end
        tip_x, tip_y = node_boundary(node, from_x, from_y)

        { tip_x: tip_x, tip_y: tip_y, from_x: from_x, from_y: from_y }
      end

      def edge_head_ends(type)
        type.end_with?('_both', 'bidirectional') ? [:source, :target] : [:target]
      end

      def node_centre(node)
        [(node[:x] || 0) + ((node[:width] || 100) / 2.0),
         (node[:y] || 0) + ((node[:height] || 50) / 2.0)]
      end

      # A head drawn at the node's centre is under the node, and the nodes
      # are painted afterwards — so every head was invisible and `---`,
      # `-->`, `--x` and `--o` rasterised the same. The tip belongs on the
      # node's edge, where the line meets it.
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
      # was pointing at. A rounded box and a stadium are drawn with their
      # corners rounded the whole way — `rx` is half the height — so they
      # pull in as far as any of them.
      def boundary_scale(node, dx, dy)
        half_w = (node[:width] || 100) / 2.0
        half_h = (node[:height] || 50) / 2.0

        case node.dig(:metadata, :shape)
        when 'rhombus' then rhombus_scale(half_w, half_h, dx, dy)
        when 'circle', 'double_circle' then circle_scale(half_w, half_h, dx, dy)
        when 'hexagon' then hexagon_scale(half_w, half_h, dx, dy)
        when *STADIUM_SHAPES then stadium_scale(half_w, half_h, dx, dy)
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

        cap_scale(straight * (dx.negative? ? -1 : 1), half_h, dx, dy)
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
      def cap_scale(centre_x, radius, dx, dy)
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

      # An arrow has its point at the tip and its body behind it, so the
      # node never covers it. A circle and a cross are drawn AROUND their
      # point, so sitting that point on the node's edge buried half of
      # each one. mmdc keeps them clear of the node — circleEnd's
      # reference point is at 11 on a circle that ends at 10.
      #
      # The circle is backed off its full reach. The cross is backed off
      # its per-axis half-run, so its corner stops 1.0 short when it
      # arrives square on. mmdc leaves a gap there too: crossEnd's
      # reference point is at 12 on arms that end at 10.
      def backed_off(geometry, reach)
        tip_x, tip_y, from_x, from_y =
          geometry.values_at(:tip_x, :tip_y, :from_x, :from_y)
        span = Math.hypot(from_x - tip_x, from_y - tip_y)
        return [tip_x, tip_y] if span.zero?

        [tip_x + ((from_x - tip_x) / span * reach),
         tip_y + ((from_y - tip_y) / span * reach)]
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
      # Zero when the two points coincide, which leaves a head of no size
      # rather than a NaN one.
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
        # Two nodes at one point leave no direction; draw it square then.
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

      def create_edge_label(source, target, label, bends)
        mid_x, mid_y = edge_label_anchor(source, target, bends)

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

      # Midway between the two node centres, lifted five straight up.
      # Straight up clears a horizontal line and only slides along a
      # vertical one, and the centres are not the drawn path, so a bent
      # edge would not move the label either. Both are how an ordinary
      # label has always been placed, and neither shows yet — the
      # fallback layout hands out no bend points. The self link below is
      # what had to change.
      #
      # A self link's two ends are the same centre, so that midpoint was
      # the node's own centre and the label sat buried under a node
      # painted after it. Its loop corners are out past the node, so the
      # middle of those carries the label clear.
      def edge_label_anchor(source, target, bends)
        return loop_label_anchor(source, bends) if source[:id] == target[:id]

        sx, sy = node_centre(source)
        tx, ty = node_centre(target)
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
