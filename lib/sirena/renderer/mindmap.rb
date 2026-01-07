# frozen_string_literal: true

require_relative "../svg/document"
require_relative "../svg/circle"
require_relative "../svg/rect"
require_relative "../svg/path"
require_relative "../svg/line"
require_relative "../svg/text"
require_relative "../svg/group"
require_relative "../svg/polygon"

module Sirena
  module Renderer
    # Renders a Mindmap layout to SVG.
    #
    # The renderer converts the positioned layout structure from
    # Transform::Mindmap into an SVG visualization showing:
    # - Nodes with different shapes (circle, cloud, hexagon, etc.)
    # - Connections between parent and child nodes
    # - Icons and custom classes
    # - Level-based or branch-based coloring
    #
    # @example Render a mindmap
    #   renderer = Renderer::Mindmap.new(theme: my_theme)
    #   svg = renderer.render(layout)
    class Mindmap < Base
      # Renders the layout structure to SVG.
      #
      # @param layout [Hash] layout data from Transform::Mindmap
      # @return [Svg::Document] rendered SVG document
      def render(layout)
        svg = create_document_from_layout(layout)

        # Render in order: connections, then nodes, then labels
        render_connections(layout, svg)
        render_nodes(layout, svg)

        svg
      end

      protected

      # Creates an SVG document with dimensions from layout.
      #
      # @param layout [Hash] layout data
      # @return [Svg::Document] new SVG document
      def create_document_from_layout(layout)
        padding = 40

        Svg::Document.new.tap do |doc|
          doc.width = layout[:width] + (padding * 2)
          doc.height = layout[:height] + (padding * 2)
          doc.view_box = "0 0 #{doc.width} #{doc.height}"

          # Add a group with padding offset
          @offset_x = padding
          @offset_y = padding
        end
      end

      # Renders all connections between nodes.
      #
      # @param layout [Hash] layout data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_connections(layout, svg)
        layout[:connections].each do |connection|
          render_connection(connection, layout, svg)
        end
      end

      # Renders a single connection line.
      #
      # @param connection [Hash] connection data
      # @param layout [Hash] layout data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_connection(connection, layout, svg)
        from_node = layout[:nodes].find { |n| n[:id] == connection[:from] }
        to_node = layout[:nodes].find { |n| n[:id] == connection[:to] }

        return unless from_node && to_node

        from_x = from_node[:x] + @offset_x
        from_y = from_node[:y] + @offset_y + (from_node[:height] / 2)
        to_x = to_node[:x] + @offset_x
        to_y = to_node[:y] + @offset_y

        # Use bezier curve for connections
        control_y = from_y + (to_y - from_y) / 2

        path_data = "M #{from_x} #{from_y} " \
                    "C #{from_x} #{control_y}, " \
                    "#{to_x} #{control_y}, " \
                    "#{to_x} #{to_y}"

        color = get_node_color(from_node)

        path = Svg::Path.new.tap do |p|
          p.d = path_data
          p.stroke = color
          p.stroke_width = "2"
          p.fill = "none"
        end

        svg.add_element(path)
      end

      # Renders all nodes with their shapes.
      #
      # @param layout [Hash] layout data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_nodes(layout, svg)
        layout[:nodes].each do |node|
          render_node(node, svg)
        end
      end

      # Renders a single node with appropriate shape.
      #
      # @param node [Hash] node data
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_node(node, svg)
        x = node[:x] + @offset_x
        y = node[:y] + @offset_y

        case node[:shape]
        when "circle"
          render_circle_node(node, x, y, svg)
        when "cloud"
          render_cloud_node(node, x, y, svg)
        when "bang"
          render_bang_node(node, x, y, svg)
        when "hexagon"
          render_hexagon_node(node, x, y, svg)
        when "square"
          render_square_node(node, x, y, svg)
        else
          render_default_node(node, x, y, svg)
        end
      end

      # Renders a default rounded rectangle node.
      #
      # @param node [Hash] node data
      # @param x [Numeric] X position
      # @param y [Numeric] Y position
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_default_node(node, x, y, svg)
        width = node[:width]
        height = node[:height]
        color = get_node_color(node)

        # Rounded rectangle background
        rect = Svg::Rect.new.tap do |r|
          r.x = x - width / 2
          r.y = y
          r.width = width
          r.height = height
          r.rx = 5
          r.ry = 5
          r.fill = lighten_color(color, 0.9)
          r.stroke = color
          r.stroke_width = "2"
        end

        svg.add_element(rect)

        # Text
        render_node_text(node, x, y + height / 2, svg)
      end

      # Renders a circle node.
      #
      # @param node [Hash] node data
      # @param x [Numeric] X position
      # @param y [Numeric] Y position
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_circle_node(node, x, y, svg)
        radius = [node[:width], node[:height]].max / 2
        color = get_node_color(node)

        circle = Svg::Circle.new.tap do |c|
          c.cx = x
          c.cy = y + radius
          c.r = radius
          c.fill = lighten_color(color, 0.9)
          c.stroke = color
          c.stroke_width = "2"
        end

        svg.add_element(circle)

        # Text
        render_node_text(node, x, y + radius, svg)
      end

      # Renders a square node.
      #
      # @param node [Hash] node data
      # @param x [Numeric] X position
      # @param y [Numeric] Y position
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_square_node(node, x, y, svg)
        width = node[:width]
        height = node[:height]
        color = get_node_color(node)

        rect = Svg::Rect.new.tap do |r|
          r.x = x - width / 2
          r.y = y
          r.width = width
          r.height = height
          r.fill = lighten_color(color, 0.9)
          r.stroke = color
          r.stroke_width = "2"
        end

        svg.add_element(rect)

        # Text
        render_node_text(node, x, y + height / 2, svg)
      end

      # Renders a hexagon node.
      #
      # @param node [Hash] node data
      # @param x [Numeric] X position
      # @param y [Numeric] Y position
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_hexagon_node(node, x, y, svg)
        width = node[:width]
        height = node[:height]
        color = get_node_color(node)

        # Hexagon points
        offset = width * 0.2
        points = [
          [x - width / 2 + offset, y],
          [x + width / 2 - offset, y],
          [x + width / 2, y + height / 2],
          [x + width / 2 - offset, y + height],
          [x - width / 2 + offset, y + height],
          [x - width / 2, y + height / 2]
        ]

        points_str = points.map { |p| p.join(",") }.join(" ")

        polygon = Svg::Polygon.new.tap do |p|
          p.points = points_str
          p.fill = lighten_color(color, 0.9)
          p.stroke = color
          p.stroke_width = "2"
        end

        svg.add_element(polygon)

        # Text
        render_node_text(node, x, y + height / 2, svg)
      end

      # Renders a cloud node.
      #
      # @param node [Hash] node data
      # @param x [Numeric] X position
      # @param y [Numeric] Y position
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_cloud_node(node, x, y, svg)
        width = node[:width]
        height = node[:height]
        color = get_node_color(node)

        # Cloud shape using path
        cloud_path = create_cloud_path(x, y, width, height)

        path = Svg::Path.new.tap do |p|
          p.d = cloud_path
          p.fill = lighten_color(color, 0.9)
          p.stroke = color
          p.stroke_width = "2"
        end

        svg.add_element(path)

        # Text
        render_node_text(node, x, y + height / 2, svg)
      end

      # Renders a bang node (cloud with emphasis).
      #
      # @param node [Hash] node data
      # @param x [Numeric] X position
      # @param y [Numeric] Y position
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_bang_node(node, x, y, svg)
        # Similar to cloud but with different styling
        render_cloud_node(node, x, y, svg)
      end

      # Creates a cloud path.
      #
      # @param x [Numeric] center X
      # @param y [Numeric] top Y
      # @param width [Numeric] width
      # @param height [Numeric] height
      # @return [String] SVG path data
      def create_cloud_path(x, y, width, height)
        # Simplified cloud shape
        w2 = width / 2
        h = height

        "M #{x - w2} #{y + h * 0.6} " \
        "Q #{x - w2} #{y + h * 0.3}, #{x - w2 * 0.6} #{y + h * 0.2} " \
        "Q #{x - w2 * 0.6} #{y}, #{x - w2 * 0.2} #{y + h * 0.1} " \
        "Q #{x} #{y}, #{x + w2 * 0.2} #{y + h * 0.1} " \
        "Q #{x + w2 * 0.6} #{y}, #{x + w2 * 0.6} #{y + h * 0.2} " \
        "Q #{x + w2} #{y + h * 0.3}, #{x + w2} #{y + h * 0.6} " \
        "Q #{x + w2} #{y + h}, #{x} #{y + h} " \
        "Q #{x - w2} #{y + h}, #{x - w2} #{y + h * 0.6} Z"
      end

      # Renders text content for a node.
      #
      # @param node [Hash] node data
      # @param x [Numeric] X position
      # @param y [Numeric] Y position
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_node_text(node, x, y, svg)
        return unless node[:content]

        text = Svg::Text.new.tap do |t|
          t.x = x
          t.y = y + 5
          t.text_anchor = "middle"
          t.fill = theme_color(:text) || "#000000"
          t.font_size = (theme_typography(:font_size) || 12).to_s
          t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
          t.content = node[:content]
        end

        svg.add_element(text)
      end

      # Gets the color for a node based on its level.
      #
      # @param node [Hash] node data
      # @return [String] color value
      def get_node_color(node)
        level = node[:level] || 0

        colors = [
          theme_color(:primary) || "#2563eb",
          theme_color(:secondary) || "#7c3aed",
          theme_color(:accent) || "#db2777",
          "#ea580c",
          "#16a34a",
          "#0891b2"
        ]

        colors[level % colors.length]
      end

      # Lightens a color by a given factor.
      #
      # @param color [String] hex color
      # @param factor [Float] lightening factor (0-1)
      # @return [String] lightened hex color
      def lighten_color(color, factor)
        # Remove # if present
        color = color.sub(/^#/, "")

        # Parse RGB
        r = color[0..1].to_i(16)
        g = color[2..3].to_i(16)
        b = color[4..5].to_i(16)

        # Lighten
        r = (r + (255 - r) * factor).round
        g = (g + (255 - g) * factor).round
        b = (b + (255 - b) * factor).round

        # Return hex
        format("#%02x%02x%02x", r, g, b)
      end
    end
  end
end