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

      # Renders a laid-out graph to SVG.
      #
      # @param graph [Hash] laid-out graph with node positions
      # @return [Svg::Document] the rendered SVG document
      def render(graph)
        page = flatten(graph)
        svg = create_document(page)

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

      def calculate_width(graph)
        boxes = drawn(graph)
        return 800 if boxes.empty?

        max_x = boxes.map do |node|
          (node[:x] || 0) + (node[:width] || 100)
        end.max

        max_x + 40 # Add padding
      end

      def calculate_height(graph)
        boxes = drawn(graph)
        return 600 if boxes.empty?

        max_y = boxes.map do |node|
          (node[:y] || 0) + (node[:height] || 50)
        end.max

        max_y + 40 # Add padding
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
          rect.rx = height / 2
          rect.ry = height / 2
          apply_theme_to_node(rect)
        end
      end

      def create_circle_shape(x, y, width, height)
        cx = x + width / 2
        cy = y + height / 2
        r = [width, height].min / 2

        Svg::Circle.new.tap do |circle|
          circle.cx = cx
          circle.cy = cy
          circle.r = r
          apply_theme_to_node(circle)
        end
      end

      def create_rhombus(x, y, width, height)
        cx = x + width / 2
        cy = y + height / 2

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
        cy = y + height / 2
        w4 = width / 4

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

      def render_edge(edge, graph, svg)
        source = find_endpoint(graph, edge[:sources]&.first)
        target = find_endpoint(graph, edge[:targets]&.first)

        return unless source && target

        elk_bends = edge.dig(:sections, 0, :bendPoints)
        # One route, so the path and its label cannot disagree.
        points, label_route = edge_router.route(source, target, elk_bends)
        route = EdgeRouter.ends_of(points)
        # Generated routes carry their own bends; an ordinary route keeps
        # whatever the layout left in the ELK section.
        bends = if points.length > 2
                  points[1...-1]
                else
                  elk_bends
                end
        path_data = calculate_edge_path(route, bends)

        # Create path element
        path = Svg::Path.new.tap do |p|
          p.d = path_data
          p.fill = 'none'
          apply_theme_to_edge(p)
          p.marker_end = 'url(#arrowhead)' if arrow_type?(edge)
        end

        # Create group for edge and label
        group = Svg::Group.new.tap do |g|
          g.id = "edge-#{edge[:id]}"
        end

        group.children << path

        # Render edge label if present
        if edge[:labels] && !edge[:labels].empty?
          label = edge[:labels].first
          text = create_edge_label(label_route, label)
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

      # One router for the whole document. It holds nothing between
      # calls, so the same object answers every edge.
      def edge_router
        @edge_router ||= EdgeRouter.new
      end

      def create_path_with_bends(sx, sy, tx, ty, bend_points)
        path_parts = ["M #{sx} #{sy}"]

        bend_points.each do |point|
          path_parts << "L #{point[:x]} #{point[:y]}"
        end

        path_parts << "L #{tx} #{ty}"
        path_parts.join(' ')
      end

      def arrow_type?(edge)
        arrow_type = edge.dig(:metadata, :arrow_type)
        %w[arrow dotted_arrow thick_arrow].include?(arrow_type)
      end

      # The midpoint of the run that was actually drawn. Measuring from
      # the centres instead left a label on a trimmed edge sitting
      # inside the box the line no longer starts in.
      def create_edge_label(route, label)
        sx, sy, tx, ty = route
        mid_x = (sx + tx) / 2
        mid_y = (sy + ty) / 2

        Svg::Text.new.tap do |text|
          text.x = mid_x
          text.y = mid_y - 5 # Offset slightly above line
          text.content = label[:text]
          apply_theme_to_text(text)
          # Use smaller font for edge labels
          if theme_typography(:font_size_small)
            text.font_size = theme_typography(:font_size_small).to_s
          end
          text.text_anchor = 'middle'
        end
      end
    end
  end
end
