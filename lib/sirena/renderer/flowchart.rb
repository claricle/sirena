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
        source = find_node(graph, edge[:sources]&.first)
        target = find_node(graph, edge[:targets]&.first)

        return unless source && target

        # Calculate edge path
        path_data = calculate_edge_path(source, target, edge)

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
          text = create_edge_label(source, target, label)
          group.children << text if text
        end

        svg << group
      end

      def find_node(graph, node_id)
        return nil unless graph[:children] && node_id

        graph[:children].find { |n| n[:id] == node_id }
      end

      def calculate_edge_path(source, target, edge)
        # Simple straight line path
        sx = (source[:x] || 0) + (source[:width] || 100) / 2
        sy = (source[:y] || 0) + (source[:height] || 50) / 2
        tx = (target[:x] || 0) + (target[:width] || 100) / 2
        ty = (target[:y] || 0) + (target[:height] || 50) / 2

        # Use sections if available (from elkrb layout)
        if edge[:sections] && !edge[:sections].empty?
          section = edge[:sections].first
          if section[:bendPoints] && !section[:bendPoints].empty?
            return create_path_with_bends(sx, sy, tx, ty,
                                          section[:bendPoints])
          end
        end

        "M #{sx} #{sy} L #{tx} #{ty}"
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

      def create_edge_label(source, target, label)
        # Position label at midpoint of edge
        sx = (source[:x] || 0) + (source[:width] || 100) / 2
        sy = (source[:y] || 0) + (source[:height] || 50) / 2
        tx = (target[:x] || 0) + (target[:width] || 100) / 2
        ty = (target[:y] || 0) + (target[:height] || 50) / 2

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
