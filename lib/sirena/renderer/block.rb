# frozen_string_literal: true

require_relative 'base'

module Sirena
  module Renderer
    # Block diagram renderer for converting positioned layouts to SVG.
    #
    # Converts a positioned block diagram layout into SVG using the Svg
    # builder classes. Handles different block shapes, compound blocks,
    # and connections.
    #
    # @example Render a block diagram
    #   renderer = BlockRenderer.new
    #   svg = renderer.render(layout)
    class BlockRenderer < Base
      # Renders a positioned layout to SVG.
      #
      # @param layout [Hash] positioned layout with block positions
      # @return [Svg::Document] the rendered SVG document
      def render(layout)
        svg = create_document_from_layout(layout)

        # Render connections first (so they appear under blocks)
        render_connections(layout, svg) if layout[:connections]

        # Render blocks
        render_blocks(layout, svg) if layout[:blocks]

        svg
      end

      protected

      def create_document_from_layout(layout)
        width = layout[:width] || 800
        height = layout[:height] || 600

        Svg::Document.new(width: width, height: height)
      end

      def render_blocks(layout, svg)
        # Render all blocks (including children)
        layout[:blocks].each do |block_id, block_info|
          render_block(block_info, svg, layout)
        end
      end

      def render_block(block_info, svg, layout)
        block = block_info[:block]

        # Skip space blocks (they're just placeholders)
        return if block.space?

        # Create group for block
        group = Svg::Group.new.tap do |g|
          g.id = "block-#{block.id}"
        end

        # Render compound block border if compound
        if block.compound?
          border = create_compound_border(block_info)
          group.children << border if border

          # Render child blocks within the compound block
          block.children.each do |child|
            child_info = layout[:blocks][child.id]
            if child_info
              child_group = render_child_block(child_info)
              group.children << child_group if child_group
            end
          end
        else
          # Only render shape and label for non-compound blocks that aren't children
          unless block_info[:parent_id]
            # Render block shape
            shape_element = create_block_shape(block_info)
            group.children << shape_element if shape_element

            # Render block label
            if block.label && !block.label.empty?
              text_element = create_block_label(block_info)
              group.children << text_element if text_element
            end
          end
        end

        svg << group unless block_info[:parent_id]
      end

      def render_child_block(block_info)
        block = block_info[:block]
        return nil if block.space?

        group = Svg::Group.new.tap do |g|
          g.id = "block-#{block.id}"
        end

        # Render block shape
        shape_element = create_block_shape(block_info)
        group.children << shape_element if shape_element

        # Render block label
        if block.label && !block.label.empty?
          text_element = create_block_label(block_info)
          group.children << text_element if text_element
        end

        group
      end

      def create_compound_border(block_info)
        x = block_info[:x]
        y = block_info[:y]
        width = block_info[:width]
        height = block_info[:height]

        Svg::Rect.new.tap do |rect|
          rect.x = x
          rect.y = y
          rect.width = width
          rect.height = height
          rect.fill = 'none'
          rect.stroke = theme_color(:border_color) || '#666'
          rect.stroke_width = '2'
          rect.stroke_dasharray = '5,5'
        end
      end

      def create_block_shape(block_info)
        block = block_info[:block]
        x = block_info[:x]
        y = block_info[:y]
        width = block_info[:width]
        height = block_info[:height]

        # Don't draw shape for compound blocks (just border)
        return nil if block.compound?

        case block.shape
        when 'circle'
          create_circle_block(x, y, width, height)
        when 'arrow'
          create_arrow_block(x, y, width, height, block.direction)
        else
          create_rectangle_block(x, y, width, height)
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

      def create_arrow_block(x, y, width, height, direction)
        # Simple triangle pointing in the specified direction
        cx = x + width / 2
        cy = y + height / 2

        points = case direction
                 when 'up'
                   [
                     "#{cx},#{y}",
                     "#{x + width},#{y + height}",
                     "#{x},#{y + height}"
                   ]
                 when 'down'
                   [
                     "#{x},#{y}",
                     "#{x + width},#{y}",
                     "#{cx},#{y + height}"
                   ]
                 when 'left'
                   [
                     "#{x},#{cy}",
                     "#{x + width},#{y}",
                     "#{x + width},#{y + height}"
                   ]
                 when 'right'
                   [
                     "#{x},#{y}",
                     "#{x + width},#{cy}",
                     "#{x},#{y + height}"
                   ]
                 else
                   [
                     "#{x},#{y}",
                     "#{x + width},#{cy}",
                     "#{x},#{y + height}"
                   ]
                 end

        Svg::Polygon.new.tap do |polygon|
          polygon.points = points.join(' ')
          apply_theme_to_node(polygon)
        end
      end

      def create_block_label(block_info)
        block = block_info[:block]
        x = block_info[:x]
        y = block_info[:y]
        width = block_info[:width]
        height = block_info[:height]

        # Center text in block
        text_x = x + width / 2
        text_y = y + height / 2

        Svg::Text.new.tap do |text|
          text.x = text_x
          text.y = text_y
          text.content = block.label
          apply_theme_to_text(text)
          text.text_anchor = 'middle'
          text.dominant_baseline = 'middle'
        end
      end

      def render_connections(layout, svg)
        layout[:connections].each do |conn|
          render_connection(conn, svg)
        end
      end

      def render_connection(conn, svg)
        # Calculate path for connection
        path_data = calculate_connection_path(conn)

        # Create path element
        path = Svg::Path.new.tap do |p|
          p.d = path_data
          p.fill = 'none'
          apply_theme_to_edge(p)
          p.marker_end = 'url(#arrowhead)' if conn[:connection_type] == 'arrow'
        end

        # Create group for connection
        group = Svg::Group.new.tap do |g|
          g.id = "connection-#{conn[:from]}-#{conn[:to]}"
        end

        group.children << path

        svg << group
      end

      def calculate_connection_path(conn)
        from_x = conn[:from_x]
        from_y = conn[:from_y]
        to_x = conn[:to_x]
        to_y = conn[:to_y]

        # Simple straight line for now
        # Could be enhanced with bezier curves for better aesthetics
        "M #{from_x} #{from_y} L #{to_x} #{to_y}"
      end

      def calculate_width(layout)
        layout[:width] || 800
      end

      def calculate_height(layout)
        layout[:height] || 600
      end
    end
  end
end