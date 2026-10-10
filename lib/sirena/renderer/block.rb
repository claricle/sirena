# frozen_string_literal: true

require_relative "base"
require_relative "../layout/block"

module Sirena
  module Renderer
    # Block diagram renderer for converting positioned layouts to SVG.
    #
    # Converts a positioned block diagram layout into SVG using the Svg
    # builder classes. Handles different block shapes, compound blocks,
    # and connections.
    #
    # @example Render a block diagram
    #   renderer = Block.new
    #   svg = renderer.render(layout)
    class Block < Base
      # Renders a positioned layout to SVG.
      #
      # @param scene [Layout::Block::Scene] final canvas geometry
      # @return [Svg::Document] the rendered SVG document
      def render(scene)
        svg = create_document(scene)
        render_connections(scene, svg)
        render_blocks(scene, svg)

        svg
      end

      protected

      def render_blocks(scene, svg)
        scene.children.each { |node| render_block(node, svg) }
      end

      def render_block(node, svg)
        group = if node.compound
                  compound_block_group(node)
                else
                  block_group(node)
                end
        svg << group
      end

      def compound_block_group(node)
        group = named_block_group(node)
        group.children << create_compound_border(node)
        node.children.each { |child| group.children << block_group(child) }
        group
      end

      def block_group(node)
        group = named_block_group(node)
        group.children << create_block_shape(node)
        group.children << create_block_label(node) unless node.labels.empty?
        group
      end

      def named_block_group(node)
        Svg::Group.new.tap { |group| group.id = "block-#{node.id}" }
      end

      def create_compound_border(node)
        Svg::Rect.new.tap do |rect|
          apply_node_geometry(rect, node)
          rect.fill = "none"
          rect.stroke = theme_color(:border_color) || "#666"
          rect.stroke_width = "2"
          rect.stroke_dasharray = "5,5"
        end
      end

      def create_block_shape(node)
        case node.shape
        when "circle"
          create_circle_block(node)
        when "arrow"
          create_arrow_block(node)
        else
          create_rectangle_block(node)
        end
      end

      def create_rectangle_block(node)
        Svg::Rect.new.tap do |rect|
          apply_node_geometry(rect, node)
          apply_theme_to_node(rect)
        end
      end

      def apply_node_geometry(shape, node)
        shape.x = node.x
        shape.y = node.y
        shape.width = node.width
        shape.height = node.height
      end

      def create_circle_block(node)
        circle = Svg::Circle.new(
          cx: node_center(node.x, node.width),
          cy: node_center(node.y, node.height),
          r: [node.width, node.height].min / 2,
        )
        apply_theme_to_node(circle)
        circle
      end

      def node_center(origin, size)
        origin + (size / 2)
      end

      def create_arrow_block(node)
        Svg::Polygon.new.tap do |polygon|
          polygon.points = arrow_points(node).join(" ")
          apply_theme_to_node(polygon)
        end
      end

      def arrow_points(node)
        case node.direction
        when "up" then up_arrow_points(node)
        when "down" then down_arrow_points(node)
        when "left" then left_arrow_points(node)
        else right_arrow_points(node)
        end
      end

      def up_arrow_points(node)
        center_x = node.x + (node.width / 2)
        bottom = node.y + node.height
        ["#{center_x},#{node.y}",
         "#{node.x + node.width},#{bottom}",
         "#{node.x},#{bottom}"]
      end

      def down_arrow_points(node)
        center_x = node.x + (node.width / 2)
        ["#{node.x},#{node.y}", "#{node.x + node.width},#{node.y}",
         "#{center_x},#{node.y + node.height}"]
      end

      def left_arrow_points(node)
        center_y = node.y + (node.height / 2)
        right = node.x + node.width
        ["#{node.x},#{center_y}", "#{right},#{node.y}",
         "#{right},#{node.y + node.height}"]
      end

      def right_arrow_points(node)
        center_y = node.y + (node.height / 2)
        ["#{node.x},#{node.y}", "#{node.x + node.width},#{center_y}",
         "#{node.x},#{node.y + node.height}"]
      end

      def create_block_label(node)
        label = node.labels.first
        Svg::Text.new.tap do |text|
          text.x = label.x
          text.y = label.y
          text.content = label.text
          apply_theme_to_text(text)
          text.text_anchor = "middle"
          text.dominant_baseline = "middle"
        end
      end

      def render_connections(scene, svg)
        scene.edges.each { |edge| render_connection(edge, svg) }
      end

      def render_connection(edge, svg)
        group = Svg::Group.new
        group.id = "connection-#{edge.source}-#{edge.target}"
        group.children << connection_path(edge)
        svg << group
      end

      def connection_path(edge)
        Svg::Path.new.tap do |path|
          path.d = calculate_connection_path(edge)
          path.fill = "none"
          apply_theme_to_edge(path)
          if edge.connection_type == "arrow"
            path.marker_end = "url(#arrowhead)"
          end
        end
      end

      def calculate_connection_path(edge)
        section = edge.sections.first
        start_point = section.start_point
        end_point = section.end_point
        "M #{start_point.x} #{start_point.y} L #{end_point.x} #{end_point.y}"
      end
    end
  end
end
