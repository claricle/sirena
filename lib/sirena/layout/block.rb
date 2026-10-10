# frozen_string_literal: true

require_relative "base"
require_relative "../diagram/block"
require_relative "../notation/mermaid/ir_adapters/block"

module Sirena
  module Layout
    # Block diagram transformer for converting block models to positioned layouts.
    #
    # Converts a typed block diagram model into a column-based layout structure.
    # Handles block dimension calculation, column-based positioning, and
    # connection routing.
    #
    # @example Transform a block diagram
    #   transform = Block.new
    #   layout = transform.to_layout(block_diagram)
    class Block < Base
      # Default dimensions
      DEFAULT_BLOCK_WIDTH = 100
      DEFAULT_BLOCK_HEIGHT = 60
      DEFAULT_SPACING = 20
      DEFAULT_COMPOUND_PADDING = 20

      class Label < Lutaml::Model::Serializable
        attribute :text, :string
        attribute :x, :float
        attribute :y, :float
      end

      class Node < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :x, :float
        attribute :y, :float
        attribute :width, :float
        attribute :height, :float
        attribute :labels, Label, collection: true, default: -> { [] }
        attribute :shape, :string
        attribute :direction, :string
        attribute :compound, :boolean, default: false
        attribute :children, Node, collection: true, default: -> { [] }
      end

      class Point < Lutaml::Model::Serializable
        attribute :x, :float
        attribute :y, :float
      end

      class Section < Lutaml::Model::Serializable
        attribute :start_point, Point
        attribute :end_point, Point
        attribute :bend_points, Point, collection: true, default: -> { [] }
      end

      class Edge < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :source, :string
        attribute :target, :string
        attribute :sections, Section, collection: true, default: -> { [] }
        attribute :labels, Label, collection: true, default: -> { [] }
        attribute :connection_type, :string
      end

      class Scene < Layout::Scene
        attribute :view_box, :string
        attribute :children, Node, collection: true, default: -> { [] }
        attribute :edges, Edge, collection: true, default: -> { [] }
      end

      # Converts a block diagram to a positioned layout structure.
      #
      # @param diagram [Diagram::Block, IR::Prepositioned] source structure
      # @return [Hash] positioned layout hash
      def build_graph(diagram)
        document = ir_document(diagram)
        items = block_items(document)
        @children_by_parent = items.group_by(&:parent_id)
        top_level = @children_by_parent.fetch(nil, [])
        columns = column_count(document)
        blocks_layout = calculate_column_layout(top_level, columns)
        graph(document, top_level, columns, blocks_layout)
      end

      private

      def graph(document, source_items, columns, blocks)
        {
          blocks: blocks,
          connections: calculate_connections(document.connections, blocks),
          source_items: source_items,
          columns: columns,
          width: calculate_total_width(blocks),
          height: calculate_total_height(blocks),
        }
      end

      def ir_document(diagram)
        return diagram if diagram.is_a?(IR::Prepositioned)

        Notation::Mermaid::IRAdapters::Block.call(diagram)
      end

      def block_items(document)
        document.items.reject { |item| item.role == "layout_settings" }
      end

      def column_count(document)
        settings = document.items.find { |item| item.role == "layout_settings" }
        value(settings, "column_count").to_i
      end

      def value(item, dimension)
        return unless item

        placement = item.placements.find do |candidate|
          candidate.dimension == dimension
        end
        placement&.value&.value
      end

      def children(block)
        @children_by_parent.fetch(block.id, [])
      end

      def compound?(block)
        value(block, "compound") || !children(block).empty?
      end

      def space?(block)
        block.role == "space"
      end

      def arrow?(block)
        block.role == "arrow"
      end

      def scene(diagram)
        graph = build_graph(diagram)
        nodes = typed_nodes(graph[:source_items], graph[:blocks])
        Scene.new(
          width: graph[:width], height: graph[:height],
          view_box: "0 0 #{graph[:width]} #{graph[:height]}",
          children: nodes,
          edges: typed_edges(graph[:connections])
        )
      end

      def typed_nodes(blocks, positioned)
        blocks.filter_map do |block|
          next if space?(block)

          typed_node(block, positioned)
        end
      end

      def typed_node(block, positioned)
        geometry = positioned.fetch(block.id)
        Node.new(
          id: block.id, x: geometry[:x], y: geometry[:y],
          width: geometry[:width], height: geometry[:height],
          labels: block_label(block, geometry), shape: value(block, "shape"),
          direction: value(block, "direction"), compound: compound?(block),
          children: typed_nodes(children(block), positioned)
        )
      end

      def block_label(block, geometry)
        return [] unless block.label && !block.label.empty?

        [Label.new(text: block.label,
                   x: geometry[:x] + (geometry[:width] / 2),
                   y: geometry[:y] + (geometry[:height] / 2))]
      end

      def typed_edges(connections)
        connections.map.with_index do |connection, index|
          typed_edge(connection, index)
        end
      end

      def typed_edge(connection, index)
        start_point = Point.new(x: connection[:from_x], y: connection[:from_y])
        end_point = Point.new(x: connection[:to_x], y: connection[:to_y])
        Edge.new(
          id: "edge_#{index}", source: connection[:from],
          target: connection[:to],
          sections: [Section.new(
            start_point: start_point, end_point: end_point,
          )],
          connection_type: connection[:connection_type]
        )
      end

      def calculate_column_layout(blocks, columns)
        positioned_blocks = {}

        current_row = 0
        current_col = 0
        row_heights = []
        col_widths = Array.new(columns, 0)

        blocks.each do |block|
          # Handle space blocks
          if space?(block)
            current_col += 1
            if current_col >= columns
              current_col = 0
              current_row += 1
            end
            next
          end

          # Calculate block dimensions
          dims = calculate_block_dimensions(block)
          block_width = value(block, "column_span").to_i

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
            col_span: block_width,
          }

          # Update column widths
          (current_col...(current_col + block_width)).each do |col|
            col_widths[col] = [col_widths[col], dims[:width]].max if col < columns
          end

          # Update row height
          row_heights[current_row] = [row_heights[current_row] || 0, dims[:height]].max

          # Handle compound blocks
          if compound?(block) && !children(block).empty?
            child_layout = layout_compound_children(block, x, y)
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

      def layout_compound_children(parent_block, parent_x, parent_y)
        positioned = {}
        child_y = parent_y + DEFAULT_COMPOUND_PADDING

        children(parent_block).each do |child|
          geometry = compound_child_geometry(child, parent_block, parent_x,
                                             child_y)
          positioned[child.id] = geometry
          positioned.merge!(nested_compound_children(child, geometry))
          child_y += geometry[:height] + DEFAULT_SPACING
        end

        positioned
      end

      def compound_child_geometry(child, parent, parent_x, child_y)
        dimensions = calculate_block_dimensions(child)
        {
          block: child, x: parent_x + DEFAULT_COMPOUND_PADDING, y: child_y,
          width: dimensions[:width], height: dimensions[:height],
          parent_id: parent.id
        }
      end

      def nested_compound_children(child, geometry)
        return {} unless compound?(child) && !children(child).empty?

        layout_compound_children(child, geometry[:x], geometry[:y])
      end

      def calculate_block_dimensions(block)
        if arrow?(block)
          return {
            width: DEFAULT_BLOCK_WIDTH / 2,
            height: DEFAULT_BLOCK_HEIGHT / 2,
          }
        end

        label = block.label || block.id
        label_dims = measure_text(label, font_size: normal_font_size)

        # Add padding
        width = [label_dims[:width] + 40, DEFAULT_BLOCK_WIDTH].max
        height = [label_dims[:height] + 30, DEFAULT_BLOCK_HEIGHT].max

        if compound?(block)
          # Compound blocks need more space
          child_height = children(block).reduce(0) do |sum, child|
            child_dims = calculate_block_dimensions(child)
            sum + child_dims[:height] + DEFAULT_SPACING
          end
          height = [height, child_height + (DEFAULT_COMPOUND_PADDING * 2)].max
        end

        {
          width: width,
          height: height,
        }
      end

      def calculate_x_position(col, col_widths)
        return DEFAULT_SPACING if col.zero?

        col_widths[0...col].sum + (DEFAULT_SPACING * (col + 1))
      end

      def calculate_y_position(row, row_heights)
        return DEFAULT_SPACING if row.zero?

        # A skipped row (span wider than the column count, or filled by
        # "space" placeholders) leaves a nil row_heights entry and
        # contributes zero height; compact drops it rather than treating
        # it as a real row.
        row_heights[0...row].compact.sum + (DEFAULT_SPACING * (row + 1))
      end

      def calculate_connections(connections, blocks_layout)
        connections.filter_map do |connection|
          from_block = blocks_layout[connection.source_id]
          to_block = blocks_layout[connection.target_id]

          next unless from_block && to_block

          {
            from: connection.source_id,
            to: connection.target_id,
            from_x: from_block[:x] + (from_block[:width] / 2),
            from_y: from_block[:y] + from_block[:height],
            to_x: to_block[:x] + (to_block[:width] / 2),
            to_y: to_block[:y],
            connection_type: connection.role,
          }
        end
      end

      def calculate_total_width(blocks_layout)
        return DEFAULT_SPACING * 2 if blocks_layout.empty?

        max_x = blocks_layout.values.map { |b| b[:x] + b[:width] }.max || 0
        max_x + DEFAULT_SPACING
      end

      def calculate_total_height(blocks_layout)
        return DEFAULT_SPACING * 2 if blocks_layout.empty?

        max_y = blocks_layout.values.map { |b| b[:y] + b[:height] }.max || 0
        max_y + DEFAULT_SPACING
      end

      def normal_font_size
        theme.typography&.font_size_normal ||
          Theme::Registry.get(:default).typography.font_size_normal
      end
    end
  end
end
