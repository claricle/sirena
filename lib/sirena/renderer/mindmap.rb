# frozen_string_literal: true

require_relative "base"
require_relative "line_break_text"
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
    # Emits SVG from final, typed mindmap geometry.
    class Mindmap < Base
      # mmdc's class on every node group.
      NODE_CLASS = "node mindmap-node"

      # @param scene [Layout::Mindmap::Scene] final canvas geometry
      # @return [Svg::Document] rendered SVG document
      def render(scene)
        svg = create_document(scene)
        render_connections(scene, svg)
        render_nodes(scene, svg)

        svg
      end

      protected

      # Renders all connections between nodes.
      #
      # @param scene [Layout::Mindmap::Scene] final canvas geometry
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_connections(scene, svg)
        scene.edges.each { |edge| render_connection(edge, svg) }
      end

      # Renders a single connection line.
      #
      # @param edge [Layout::Mindmap::Edge] connection geometry
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_connection(edge, svg)
        path = Svg::Path.new.tap do |p|
          p.d = edge.path
          p.stroke = level_color(edge.colour_level)
          p.stroke_width = "2"
          p.fill = "none"
        end

        svg.add_element(path)
      end

      # Renders all nodes with their shapes.
      #
      # @param scene [Layout::Mindmap::Scene] final canvas geometry
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_nodes(scene, svg)
        scene.children.each { |node| render_node(node, svg) }
      end

      # Renders a single node with appropriate shape.
      #
      # @param node [Layout::Mindmap::Node] node geometry
      # @param svg [Svg::Document] SVG document
      # @return [void]
      def render_node(node, svg)
        group = Svg::Group.new.tap { |item| item.class_name = NODE_CLASS }
        render_shape(node, group)
        svg.add_element(group)
      end

      def render_shape(node, group)
        case node.shape
        when "circle"
          render_circle_node(node, group)
        when "cloud"
          render_cloud_node(node, group)
        when "bang"
          render_bang_node(node, group)
        when "hexagon"
          render_hexagon_node(node, group)
        when "square"
          render_square_node(node, group)
        else
          render_default_node(node, group)
        end
      end

      # Renders a default rounded rectangle node.
      #
      # @param node [Hash] node data
      # @param x [Numeric] X position
      # @param y [Numeric] Y position
      # @param group [Svg::Group] the node's group
      # @return [void]
      def render_default_node(node, group)
        color = level_color(node.level)
        rect = Svg::Rect.new.tap do |r|
          r.x = node.x
          r.y = node.y
          r.width = node.width
          r.height = node.height
          r.rx = 5
          r.ry = 5
          r.fill = lighten_color(color, 0.9)
          r.stroke = color
          r.stroke_width = "2"
        end

        group.add_child(rect)

        render_node_text(node, group)
      end

      # Renders a circle node.
      #
      # @param node [Hash] node data
      # @param x [Numeric] X position
      # @param y [Numeric] Y position
      # @param group [Svg::Group] the node's group
      # @return [void]
      def render_circle_node(node, group)
        color = level_color(node.level)

        circle = Svg::Circle.new.tap do |c|
          c.cx = node.center_x
          c.cy = node.center_y
          c.r = node.radius
          c.fill = lighten_color(color, 0.9)
          c.stroke = color
          c.stroke_width = "2"
        end

        group.add_child(circle)

        render_node_text(node, group)
      end

      # Renders a square node.
      #
      # @param node [Hash] node data
      # @param x [Numeric] X position
      # @param y [Numeric] Y position
      # @param group [Svg::Group] the node's group
      # @return [void]
      def render_square_node(node, group)
        color = level_color(node.level)

        rect = Svg::Rect.new.tap do |r|
          r.x = node.x
          r.y = node.y
          r.width = node.width
          r.height = node.height
          r.fill = lighten_color(color, 0.9)
          r.stroke = color
          r.stroke_width = "2"
        end

        group.add_child(rect)

        render_node_text(node, group)
      end

      # Renders a hexagon node.
      #
      # @param node [Hash] node data
      # @param x [Numeric] X position
      # @param y [Numeric] Y position
      # @param group [Svg::Group] the node's group
      # @return [void]
      def render_hexagon_node(node, group)
        color = level_color(node.level)
        polygon = Svg::Polygon.new.tap do |p|
          p.points = node.shape_points
          p.fill = lighten_color(color, 0.9)
          p.stroke = color
          p.stroke_width = "2"
        end

        group.add_child(polygon)

        render_node_text(node, group)
      end

      # Renders a cloud node.
      #
      # @param node [Hash] node data
      # @param x [Numeric] X position
      # @param y [Numeric] Y position
      # @param group [Svg::Group] the node's group
      # @return [void]
      def render_cloud_node(node, group)
        color = level_color(node.level)
        path = Svg::Path.new.tap do |p|
          p.d = node.shape_path
          p.fill = lighten_color(color, 0.9)
          p.stroke = color
          p.stroke_width = "2"
        end

        group.add_child(path)

        render_node_text(node, group)
      end

      # Renders a bang node (cloud with emphasis).
      #
      # @param node [Hash] node data
      # @param x [Numeric] X position
      # @param y [Numeric] Y position
      # @param group [Svg::Group] the node's group
      # @return [void]
      def render_bang_node(node, group)
        render_cloud_node(node, group)
      end

      # Renders text content for a node.
      #
      # @param node [Layout::Mindmap::Node] node geometry
      # @param group [Svg::Group] the node's group
      # @return [void]
      def render_node_text(node, group)
        label = node.labels.first
        return unless label&.text

        text = Svg::Text.new.tap do |t|
          t.x = label.x
          t.y = label.y
          t.text_anchor = "middle"
          t.fill = theme_color(:text) || "#000000"
          t.font_size = (label.font_size || 12).to_s
          t.font_family = theme_typography(:font_family) || "Arial, sans-serif"
        end
        fill_lines(text, label.text)

        group.add_child(text)
      end

      # One tspan per line. A line that is followed by another ends in a
      # space, so the label still reads as one sentence.
      def fill_lines(text, raw)
        lines = raw.split("\n", -1)
        return text.tap { text.content = raw } if lines.one?

        spaced = lines[0...-1].map { |line| "#{line} " } << lines.last
        LineBreakText.fill_lines(text, spaced)
      end

      # Gets the color for a level.
      # @param level [Integer] depth in the tree
      # @return [String] color value
      def level_color(level)
        colors = [
          theme_color(:primary) || "#2563eb",
          theme_color(:secondary) || "#7c3aed",
          theme_color(:accent) || "#db2777",
          "#ea580c",
          "#16a34a",
          "#0891b2",
        ]

        colors[(level || 0) % colors.length]
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
        format("#%<red>02x%<green>02x%<blue>02x", red: r, green: g, blue: b)
      end
    end
  end
end
