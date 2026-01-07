# frozen_string_literal: true

require_relative 'base'
require_relative '../diagram/block'

module Sirena
  module Transform
    # Block diagram transformer for converting block models to positioned layouts.
    #
    # Converts a typed block diagram model into a column-based layout structure.
    # Handles block dimension calculation, column-based positioning, and
    # connection routing.
    #
    # @example Transform a block diagram
    #   transform = BlockTransform.new
    #   layout = transform.to_layout(block_diagram)
    class BlockTransform < Base
      # Default dimensions
      DEFAULT_BLOCK_WIDTH = 100
      DEFAULT_BLOCK_HEIGHT = 60
      DEFAULT_SPACING = 20
      DEFAULT_COMPOUND_PADDING = 20

      # Converts a block diagram to a positioned layout structure.
      #
      # @param diagram [Diagram::BlockDiagram] the block diagram to transform
      # @return [Hash] positioned layout hash
      # @raise [TransformError] if diagram is invalid
      def to_graph(diagram)
        raise TransformError, 'Diagram cannot be nil' if diagram.nil?

        blocks_layout = calculate_column_layout(diagram)
        connections_layout = calculate_connections(diagram, blocks_layout)

        {
          blocks: blocks_layout,
          connections: connections_layout,
          columns: diagram.columns,
          width: calculate_total_width(blocks_layout, diagram.columns),
          height: calculate_total_height(blocks_layout)
        }
      end

      private

      def calculate_column_layout(diagram)
        columns = diagram.columns
        blocks = diagram.blocks
        positioned_blocks = {}

        current_row = 0
        current_col = 0
        row_heights = []
        col_widths = Array.new(columns, 0)

        blocks.each do |block|
          # Handle space blocks
          if block.space?
            current_col += 1
            if current_col >= columns
              current_col = 0
              current_row += 1
            end
            next
          end

          # Calculate block dimensions
          dims = calculate_block_dimensions(block)
          block_width = block.width || 1

          # Check if block fits in current row
          if current_col + block_width > columns
            current_col = 0
            current_row += 1
          end

          # Position block
          x = calculate_x_position(current_col, col_widths)
          y = calculate_y_position(current_row, row_heights)

          positioned_blocks[block.id] = {
            block: block,
            x: x,
            y: y,
            width: dims[:width] * block_width,
            height: dims[:height],
            row: current_row,
            col: current_col,
            col_span: block_width
          }

          # Update column widths
          (current_col...current_col + block_width).each do |col|
            col_widths[col] = [col_widths[col], dims[:width]].max if col < columns
          end

          # Update row height
          row_heights[current_row] = [row_heights[current_row] || 0, dims[:height]].max

          # Handle compound blocks
          if block.compound? && !block.children.empty?
            child_layout = layout_compound_children(block, x, y, dims)
            positioned_blocks.merge!(child_layout)
          end

          # Move to next position
          current_col += block_width
          if current_col >= columns
            current_col = 0
            current_row += 1
          end
        end

        positioned_blocks
      end

      def layout_compound_children(parent_block, parent_x, parent_y, parent_dims)
        positioned = {}
        child_y = parent_y + DEFAULT_COMPOUND_PADDING

        parent_block.children.each_with_index do |child, index|
          child_dims = calculate_block_dimensions(child)

          positioned[child.id] = {
            block: child,
            x: parent_x + DEFAULT_COMPOUND_PADDING,
            y: child_y,
            width: child_dims[:width],
            height: child_dims[:height],
            parent_id: parent_block.id
          }

          child_y += child_dims[:height] + DEFAULT_SPACING
        end

        positioned
      end

      def calculate_block_dimensions(block)
        if block.arrow?
          return {
            width: DEFAULT_BLOCK_WIDTH / 2,
            height: DEFAULT_BLOCK_HEIGHT / 2
          }
        end

        label = block.label || block.id
        label_dims = measure_text(label, font_size: 14)

        # Add padding
        width = [label_dims[:width] + 40, DEFAULT_BLOCK_WIDTH].max
        height = [label_dims[:height] + 30, DEFAULT_BLOCK_HEIGHT].max

        if block.compound?
          # Compound blocks need more space
          child_height = block.children.reduce(0) do |sum, child|
            child_dims = calculate_block_dimensions(child)
            sum + child_dims[:height] + DEFAULT_SPACING
          end
          height = [height, child_height + DEFAULT_COMPOUND_PADDING * 2].max
        end

        {
          width: width,
          height: height
        }
      end

      def calculate_x_position(col, col_widths)
        return DEFAULT_SPACING if col == 0

        col_widths[0...col].sum + (DEFAULT_SPACING * (col + 1))
      end

      def calculate_y_position(row, row_heights)
        return DEFAULT_SPACING if row == 0

        row_heights[0...row].sum + (DEFAULT_SPACING * (row + 1))
      end

      def calculate_connections(diagram, blocks_layout)
        diagram.connections.map do |conn|
          from_block = blocks_layout[conn.from]
          to_block = blocks_layout[conn.to]

          next unless from_block && to_block

          {
            from: conn.from,
            to: conn.to,
            from_x: from_block[:x] + from_block[:width] / 2,
            from_y: from_block[:y] + from_block[:height],
            to_x: to_block[:x] + to_block[:width] / 2,
            to_y: to_block[:y],
            connection_type: conn.connection_type
          }
        end.compact
      end

      def calculate_total_width(blocks_layout, columns)
        return DEFAULT_SPACING * 2 if blocks_layout.empty?

        max_x = blocks_layout.values.map { |b| b[:x] + b[:width] }.max || 0
        max_x + DEFAULT_SPACING
      end

      def calculate_total_height(blocks_layout)
        return DEFAULT_SPACING * 2 if blocks_layout.empty?

        max_y = blocks_layout.values.map { |b| b[:y] + b[:height] }.max || 0
        max_y + DEFAULT_SPACING
      end
    end
  end
end