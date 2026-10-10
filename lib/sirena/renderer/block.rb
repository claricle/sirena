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
        group = Svg::Group.new.tap do |g|
          g.id = "block-#{node.id}"
        end

        if node.compound
          group.children << create_compound_border(node)
          node.children.each { |child| group.children << block_group(child) }
        else
          group.children << create_block_shape(node)
          group.children << create_block_label(node) unless node.labels.empty?
        end

        svg << group
      end

      def block_group(node)
        group = Svg::Group.new.tap do |g|
          g.id = "block-#{node.id}"
        end
        group.children << create_block_shape(node)
        group.children << create_block_label(node) unless node.labels.empty?
        group
      end

      def create_compound_border(node)
        Svg::Rect.new.tap do |rect|
          rect.x = node.x
          rect.y = node.y
          rect.width = node.width
          rect.height = node.height
          rect.fill = "none"
          rect.stroke = theme_color(:border_color) || "#666"
          rect.stroke_width = "2"
          rect.stroke_dasharray = "5,5"
        end
      end

      def create_block_shape(node)
        case node.shape
        when "circle"
          create_circle_block(node.x, node.y, node.width, node.height)
        when "arrow"
          create_arrow_block(node.x, node.y, node.width, node.height,
                             node.direction)
        else
          create_rectangle_block(node.x, node.y, node.width, node.height)
        end
      end

      def create_rectangle_block(x, y, width, height)
        Svg::Rect.new.tap do |rect|
          rect.x = x
          rect.y = y
          rect.width = width
          rect.height = height
          apply_theme_to_node(rect)
        end
      end

      def create_circle_block(x, y, width, height)
        cx = x + (width / 2)
        cy = y + (height / 2)
        r = [width, height].min / 2

        Svg::Circle.new.tap do |circle|
          circle.cx = cx
          circle.cy = cy
          circle.r = r
          apply_theme_to_node(circle)
        end
      end

      def create_arrow_block(x, y, width, height, direction)
        # Simple triangle pointing in the specified direction
        cx = x + (width / 2)
        cy = y + (height / 2)

        points = case direction
                 when "up"
                   [
                     "#{cx},#{y}",
                     "#{x + width},#{y + height}",
                     "#{x},#{y + height}",
                   ]
                 when "down"
                   [
                     "#{x},#{y}",
                     "#{x + width},#{y}",
                     "#{cx},#{y + height}",
                   ]
                 when "left"
                   [
                     "#{x},#{cy}",
                     "#{x + width},#{y}",
                     "#{x + width},#{y + height}",
                   ]
                 when "right"
                   [
                     "#{x},#{y}",
                     "#{x + width},#{cy}",
                     "#{x},#{y + height}",
                   ]
                 else
                   [
                     "#{x},#{y}",
                     "#{x + width},#{cy}",
                     "#{x},#{y + height}",
                   ]
                 end

        Svg::Polygon.new.tap do |polygon|
          polygon.points = points.join(" ")
          apply_theme_to_node(polygon)
        end
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
        path = Svg::Path.new.tap do |p|
          p.d = calculate_connection_path(edge)
          p.fill = "none"
          apply_theme_to_edge(p)
          p.marker_end = "url(#arrowhead)" if edge.connection_type == "arrow"
        end

        group = Svg::Group.new.tap do |g|
          g.id = "connection-#{edge.source}-#{edge.target}"
        end

        group.children << path

        svg << group
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
