# frozen_string_literal: true

require_relative "base"
require_relative "../svg/document"
require_relative "../svg/circle"
require_relative "../svg/rect"
require_relative "../svg/path"
require_relative "../svg/line"
require_relative "../svg/text"
require_relative "../svg/tspan"
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
        shape_renderer = case node.shape
                         when "circle" then :render_circle_node
                         when "cloud" then :render_cloud_node
                         when "bang" then :render_bang_node
                         when "hexagon" then :render_hexagon_node
                         when "square" then :render_square_node
                         else :render_default_node
                         end
        send(shape_renderer, node, group)
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
        rect = node_rectangle(node)
        rect.rx = 5
        rect.ry = 5
        paint_node_shape(rect, color)
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
        circle = Svg::Circle.new.tap do |shape|
          shape.cx = node.center_x
          shape.cy = node.center_y
          shape.r = node.radius
        end
        paint_node_shape(circle, color)
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
        rect = node_rectangle(node)
        paint_node_shape(rect, color)
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

        text = node_label(label)
        fill_lines(text, label)
        group.add_child(text)
      end

      # One tspan per line. A line that is followed by another ends in a
      # space, so the label still reads as one sentence.
      def fill_lines(text, label)
        if label.lines.one?
          return text.tap { text.content = label.lines.first.text }
        end

        text.tspans = label.lines.each_with_index.map do |line, index|
          label_run(line, first: index.zero?)
        end
      end

      def label_run(line, first:)
        Svg::Tspan.new.tap do |run|
          run.content = line.text
          run.x = line.x
          run.y = line.y unless first
        end
      end

      # Gets the color for a level.
      # @param level [Integer] depth in the tree
      # @return [String] color value
      def level_color(level)
        colors = theme&.colors
        palette = colors&.mindmap_palette
        colors = Theme::Registry.get(:default).colors if palette.nil? ||
          palette.empty?
        colors.palette(:mindmap, level || 0)
      end

      # Lightens a color by a given factor.
      #
      # @param color [String] hex color
      # @param factor [Float] lightening factor (0-1)
      # @return [String] lightened hex color
      def lighten_color(color, factor)
        color = color.sub(/^#/, "")
        red = lighten_channel(color[0..1].to_i(16), factor)
        green = lighten_channel(color[2..3].to_i(16), factor)
        blue = lighten_channel(color[4..5].to_i(16), factor)
        format("#%<red>02x%<green>02x%<blue>02x",
               red: red, green: green, blue: blue)
      end

      private

      def node_rectangle(node)
        Svg::Rect.new.tap do |rect|
          rect.x = node.x
          rect.y = node.y
          rect.width = node.width
          rect.height = node.height
        end
      end

      def paint_node_shape(shape, color)
        shape.fill = lighten_color(color, 0.9)
        shape.stroke = color
        shape.stroke_width = "2"
      end

      def node_label(label)
        Svg::Text.new.tap do |text|
          text.x = label.x
          text.y = label.y
          text.text_anchor = "middle"
          text.fill = theme_color(:label_text)
          node_label_font(text, label)
        end
      end

      def node_label_font(text, label)
        text.font_size = (label.font_size || 12).to_s
        text.font_family = theme_typography(:font_family) || "Arial, sans-serif"
      end

      def lighten_channel(channel, factor)
        (channel + ((255 - channel) * factor)).round
      end
    end
  end
end
