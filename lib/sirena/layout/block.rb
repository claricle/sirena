# frozen_string_literal: true

require_relative "base"
require_relative "../diagram/block"
require_relative "../notation/mermaid/ir_adapters/block"

module Sirena
  module Layout
    # Block diagram transformer for converting block models to positioned
    # layouts.
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
      DEFAULT_COMPOUND_PADDING = 8
      COMPACT_TEXT_WIDTH_SCALE = 1.16
      COMPACT_TEXT_WIDTH_FONT_SIZE = 16

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
        attribute :center_x, :float
        attribute :center_y, :float
        attribute :radius, :float
        attribute :shape_points, :string
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
        top_level = top_level_blocks(document)
        columns, auto_layout = columns_for(document, top_level)
        span_layout = span_layout?(top_level)
        blocks_layout = calculate_column_layout(
          top_level, columns, auto_layout: auto_layout,
                              span_layout: span_layout
        )
        graph(document, top_level, columns, blocks_layout, auto_layout)
      end

      private

      def graph(document, source_items, columns, blocks, auto_layout)
        {
          blocks: blocks,
          connections: calculate_connections(
            document.connections, blocks, auto_layout: auto_layout
          ),
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

      def top_level_blocks(document)
        @children_by_parent = block_items(document).group_by(&:parent_id)
        @children_by_parent.fetch(nil, [])
      end

      def column_count(document)
        settings = document.items.find { |item| item.role == "layout_settings" }
        value(settings, "column_count")&.to_i
      end

      def columns_for(document, blocks)
        count = column_count(document)
        [count || auto_column_count(blocks), count.nil?]
      end

      def auto_column_count(blocks)
        [blocks.sum { |block| block_span(block) }, 1].max
      end

      def block_span(block)
        [value(block, "column_span").to_i, 1].max
      end

      def span_layout?(blocks)
        blocks.any? { |block| block_span(block) > 1 }
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
        shape = arrow?(block) ? "arrow" : value(block, "shape")
        direction = value(block, "direction")
        Node.new(
          **node_attributes(block, geometry),
          shape: shape, direction: direction, compound: compound?(block),
          children: typed_nodes(children(block), positioned),
          **shape_geometry(shape, direction, geometry)
        )
      end

      def node_attributes(block, geometry)
        {
          id: block.id, x: geometry[:x], y: geometry[:y],
          width: geometry[:width], height: geometry[:height],
          labels: block_label(block, geometry)
        }
      end

      def shape_geometry(shape, direction, box)
        case shape
        when "circle" then circle_geometry(box)
        when "arrow" then { shape_points: arrow_points(box, direction) }
        else {}
        end
      end

      def circle_geometry(box)
        {
          center_x: box[:x] + (box[:width] / 2),
          center_y: box[:y] + (box[:height] / 2),
          radius: [box[:width], box[:height]].min / 2,
        }
      end

      def arrow_points(box, direction)
        points = case direction
                 when "up" then up_arrow_points(box)
                 when "down" then down_arrow_points(box)
                 when "left" then left_arrow_points(box)
                 else right_arrow_points(box)
                 end
        points.join(" ")
      end

      def up_arrow_points(box)
        x, y, width, height = float_box(box)
        center_x = x + (width / 2)
        bottom = y + height
        ["#{center_x},#{y}", "#{x + width},#{bottom}", "#{x},#{bottom}"]
      end

      def down_arrow_points(box)
        x, y, width, height = float_box(box)
        center_x = x + (width / 2)
        ["#{x},#{y}", "#{x + width},#{y}", "#{center_x},#{y + height}"]
      end

      def left_arrow_points(box)
        x, y, width, height = float_box(box)
        center_y = y + (height / 2)
        right = x + width
        ["#{x},#{center_y}", "#{right},#{y}", "#{right},#{y + height}"]
      end

      def right_arrow_points(box)
        x, y, width, height = float_box(box)
        center_y = y + (height / 2)
        ["#{x},#{y}", "#{x + width},#{center_y}", "#{x},#{y + height}"]
      end

      def float_box(box)
        box.values_at(:x, :y, :width, :height).map(&:to_f)
      end

      def block_label(block, geometry)
        return [] unless block.label && !block.label.empty?

        [Label.new(text: block_label_text(block),
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

      def calculate_column_layout(blocks, columns, auto_layout:, span_layout:)
        positioned = {}
        cursor = column_layout_cursor(columns)
        settings = column_layout_settings(blocks, columns, auto_layout,
                                          span_layout)
        blocks.each do |block|
          place_column_block(block, cursor, settings, positioned)
        end
        positioned
      end

      def block_dimensions(block, auto_layout:, span_layout:, uniform_grid:,
                           width_font_size:)
        compact = (auto_layout || span_layout) && !compound?(block)
        dimensions = scaled_dimensions(block, compact, width_font_size)
        return dimensions unless uniform_grid
        return calculate_block_dimensions(block, auto_layout: true) if
          special_shape?(block)

        {
          width: uniform_grid_width(block, uniform_grid),
          height: uniform_grid.fetch(:height),
        }
      end

      # Special shapes keep the normal font size for their width.
      def scaled_dimensions(block, compact, width_font_size)
        font = special_shape?(block) ? normal_font_size : width_font_size
        calculate_block_dimensions(block, auto_layout: compact,
                                          width_font_size: font)
      end

      def uniform_grid_width(block, uniform_grid)
        span = block_span(block)
        (uniform_grid.fetch(:width) * span) +
          (DEFAULT_COMPOUND_PADDING * (span - 1))
      end

      def compact_spacing(auto_layout, span_layout, uniform_grid)
        return DEFAULT_COMPOUND_PADDING if auto_layout || span_layout ||
          uniform_grid

        DEFAULT_SPACING
      end

      def uniform_grid_dimensions(blocks, auto_layout)
        return if auto_layout || blocks.none? { |block| compound?(block) }

        dimensions = compact_grid_dimensions(blocks)
        return if dimensions.empty?

        maximum_dimensions(dimensions)
      end

      def compact_grid_dimensions(blocks)
        blocks.reject { |block| space?(block) || special_shape?(block) }
          .map { |block| compact_dimensions(block) }
      end

      def maximum_dimensions(dimensions)
        %i[width height].to_h do |key|
          [key, dimensions.map { |item| item.fetch(key) }.max.to_f]
        end
      end

      def special_shape?(block)
        arrow?(block) || value(block, "shape") == "circle"
      end

      def compact_dimensions(block)
        label = block_label_text(block)
        label_dims = measure_text(label, font_size: normal_font_size)
        width = (label_dims[:width] * COMPACT_TEXT_WIDTH_SCALE) + 8
        height = label_dims[:height] + 13
        return { width: width, height: height } unless compound?(block)

        compact_compound_dimensions(block, width, height)
      end

      def compact_compound_dimensions(block, width, height)
        dimensions = children(block).map { |child| compact_dimensions(child) }
        child_width, child_height = maximum_dimensions(dimensions).values
        count = dimensions.length
        {
          width: [width, (child_width * count) +
            (DEFAULT_COMPOUND_PADDING * (count + 1))].max,
          height: [height, child_height + (DEFAULT_COMPOUND_PADDING * 2)].max,
        }
      end

      def compact_width_font_size(columns, span_layout)
        return normal_font_size if span_layout && columns == 1

        COMPACT_TEXT_WIDTH_FONT_SIZE
      end

      def span_column_width(blocks, width_font_size)
        blocks.reject { |block| space?(block) }.map do |block|
          calculate_block_dimensions(
            block, auto_layout: !compound?(block),
                   width_font_size: width_font_size
          )[:width]
        end.max
      end

      def spanned_width(width, span, spacing, column_width)
        return width * span unless column_width

        (column_width * span) + (spacing * (span - 1))
      end

      def layout_compound_children(parent_block, parent_x, parent_y,
                                   compact: false, parent_width: nil)
        positioned = {}
        child_x = parent_x + DEFAULT_COMPOUND_PADDING
        compact_width = compact_child_width(parent_block, parent_width) if
          compact

        children(parent_block).each do |child|
          child_x = place_compound_child(
            positioned, child, parent_block, [child_x, parent_y], compact_width
          )
        end

        positioned
      end

      def place_compound_child(positioned, child, parent, position,
                               compact_width)
        child_x, parent_y = position
        geometry = compound_child_geometry(
          child, parent, child_x, compound_child_y(parent_y),
          compact_width: compact_width
        )
        positioned[child.id] = geometry
        positioned.merge!(nested_compound_children(child, geometry))
        child_x + geometry[:width] + DEFAULT_COMPOUND_PADDING
      end

      def compound_child_y(parent_y)
        parent_y + DEFAULT_COMPOUND_PADDING
      end

      def compact_child_width(parent_block, parent_width)
        count = children(parent_block).length
        (parent_width - (DEFAULT_COMPOUND_PADDING * (count + 1))) / count
      end

      def compound_child_geometry(child, parent, child_x, child_y,
                                  compact_width: nil)
        dimensions = if compact_width
                       compact_dimensions(child).merge(width: compact_width)
                     else
                       calculate_block_dimensions(child, auto_layout: false)
                     end
        {
          block: child, x: child_x, y: child_y,
          width: dimensions[:width], height: dimensions[:height],
          parent_id: parent.id
        }
      end

      def nested_compound_children(child, geometry)
        return {} unless compound?(child) && !children(child).empty?

        layout_compound_children(child, geometry[:x], geometry[:y])
      end

      # A compact block's width comes from its label at the compact font size.
      def label_width(label, label_dims, auto_layout, width_font_size)
        return label_dims[:width] unless
          auto_layout && width_font_size != normal_font_size

        measure_text(label, font_size: width_font_size)[:width]
      end

      def calculate_block_dimensions(block, auto_layout:,
                                     width_font_size: normal_font_size)
        return arrow_block_dimensions if arrow?(block)

        dimensions = label_block_dimensions(block, auto_layout, width_font_size)
        return dimensions unless compound?(block)

        compound_dimensions(block, dimensions[:width], dimensions[:height])
      end

      def block_label_text(block)
        label = (block.label || block.id).gsub("&nbsp;", "\u00a0")
        return label[1...-1] if quoted_label?(label)

        label
      end

      def quoted_label?(label)
        label.length >= 2 && %w[' "].include?(label[0]) &&
          label[-1] == label[0]
      end

      def compound_dimensions(block, width, height)
        dimensions = children(block).map do |child|
          calculate_block_dimensions(child, auto_layout: false)
        end
        {
          width: [width, compound_width(dimensions)].max,
          height: [height, compound_height(dimensions)].max,
        }
      end

      def compound_width(dimensions)
        dimensions.sum { |child| child[:width] } +
          (DEFAULT_COMPOUND_PADDING * (dimensions.length + 1))
      end

      def compound_height(dimensions)
        dimensions.map { |child| child[:height] }.max.to_f +
          (DEFAULT_COMPOUND_PADDING * 2)
      end

      def calculate_x_position(col, col_widths, spacing = DEFAULT_SPACING,
                               column_width = nil)
        return spacing if col.zero?

        if column_width
          return spacing + (col * (column_width + spacing))
        end

        col_widths[0...col].sum + (spacing * (col + 1))
      end

      def calculate_y_position(row, row_heights, spacing = DEFAULT_SPACING)
        return spacing if row.zero?

        # A skipped row (span wider than the column count, or filled by
        # "space" placeholders) leaves a nil row_heights entry and
        # contributes zero height; compact drops it rather than treating
        # it as a real row.
        row_heights[0...row].compact.sum + spacing + (spacing * row)
      end

      def calculate_connections(connections, blocks_layout, auto_layout:)
        connections.filter_map do |connection|
          positioned_connection(connection, blocks_layout, auto_layout)
        end
      end

      def connection_points(from_block, to_block, auto_layout)
        return horizontal_connection_points(from_block, to_block) if
          auto_layout && same_row?(from_block, to_block)

        vertical_connection_points(from_block, to_block)
      end

      def same_row?(from_block, to_block)
        from_block.key?(:row) && to_block.key?(:row) &&
          from_block[:row] == to_block[:row]
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

      def column_layout_cursor(columns)
        { row: 0, col: 0, row_heights: [], col_widths: Array.new(columns, 0) }
      end

      def column_layout_settings(blocks, columns, auto_layout, span_layout)
        width_font_size = compact_width_font_size(columns, span_layout)
        column_width = span_column_width(blocks, width_font_size) if span_layout
        {
          columns: columns, auto_layout: auto_layout, span_layout: span_layout,
          width_font_size: width_font_size, column_width: column_width,
          uniform_grid: uniform_grid_dimensions(blocks, auto_layout)
        }
      end

      def place_column_block(block, cursor, settings, positioned)
        span = block_span(block)
        return place_column_space(cursor, settings, span) if space?(block)

        dimensions = column_block_dimensions(block, settings)
        fit_column_block(cursor, settings, span)
        geometry = placed_geometry(block, dimensions, cursor, settings, span)
        positioned[block.id] = geometry
        update_column_dimensions(cursor, settings, dimensions, span)
        place_column_children(block, geometry, settings, positioned)
        advance_column(cursor, settings[:columns], span)
      end

      def column_block_dimensions(block, settings)
        block_dimensions(
          block, auto_layout: settings[:auto_layout],
                 span_layout: settings[:span_layout],
                 uniform_grid: settings[:uniform_grid],
                 width_font_size: settings[:width_font_size]
        )
      end

      def place_column_space(cursor, settings, span)
        grid = settings[:uniform_grid]
        cursor[:row_heights][cursor[:row]] = grid.fetch(:height) if grid
        advance_column(cursor, settings[:columns], span)
      end

      def advance_column(cursor, columns, span)
        cursor[:col] += span
        return if cursor[:col] < columns

        cursor[:col] = 0
        cursor[:row] += 1
      end

      def fit_column_block(cursor, settings, span)
        return if settings[:span_layout] ||
          cursor[:col] + span <= settings[:columns]

        cursor[:col] = 0
        cursor[:row] += 1
      end

      def placed_geometry(block, dimensions, cursor, settings, span)
        spacing = compact_spacing(settings[:auto_layout],
                                  settings[:span_layout],
                                  settings[:uniform_grid])
        horizontal, vertical = column_block_position(cursor, settings, spacing)
        horizontal, vertical = centered_column_position(
          block, dimensions, settings[:uniform_grid], [horizontal, vertical]
        )
        position = [horizontal, vertical, spacing, settings[:column_width]]
        column_geometry(block, dimensions, cursor, position, span)
      end

      def column_block_position(cursor, settings, spacing)
        [calculate_x_position(cursor[:col], cursor[:col_widths], spacing,
                              settings[:column_width]),
         calculate_y_position(cursor[:row], cursor[:row_heights], spacing)]
      end

      def centered_column_position(block, dimensions, grid, position)
        return position unless grid && special_shape?(block)

        horizontal, vertical = position
        horizontal += (grid.fetch(:width) - dimensions.fetch(:width)) / 2
        vertical += (grid.fetch(:height) - dimensions.fetch(:height)) / 2
        [horizontal, vertical]
      end

      def column_geometry(block, dimensions, cursor, position, span)
        horizontal, vertical, spacing, column_width = position
        {
          block: block, x: horizontal, y: vertical,
          width: spanned_width(dimensions[:width], span, spacing, column_width),
          height: dimensions[:height], row: cursor[:row], col: cursor[:col],
          col_span: span
        }
      end

      def update_column_dimensions(cursor, settings, dimensions, span)
        update_column_widths(cursor, settings[:columns], dimensions[:width],
                             span)
        row = cursor[:row]
        current_height = cursor[:row_heights][row] || 0
        height = settings[:uniform_grid]&.fetch(:height) || dimensions[:height]
        cursor[:row_heights][row] = [current_height, height].max
      end

      def update_column_widths(cursor, columns, width, span)
        (cursor[:col]...(cursor[:col] + span)).each do |col|
          next unless col < columns

          widths = cursor[:col_widths]
          widths[col] = [widths[col], width].max
        end
      end

      def place_column_children(block, geometry, settings, positioned)
        return unless compound?(block) && !children(block).empty?

        positioned.merge!(layout_compound_children(
                            block, geometry[:x], geometry[:y],
                            compact: !settings[:uniform_grid].nil?,
                            parent_width: geometry[:width]
                          ))
      end

      def arrow_block_dimensions
        { width: DEFAULT_BLOCK_WIDTH / 2, height: DEFAULT_BLOCK_HEIGHT / 2 }
      end

      def label_block_dimensions(block, auto_layout, width_font_size)
        label = block_label_text(block)
        label_dims = measure_text(label, font_size: normal_font_size)
        width = label_width(label, label_dims, auto_layout, width_font_size)
        width += auto_layout ? 8 : 40
        height = label_dims[:height] + (auto_layout ? 13 : 30)
        return { width: width, height: height } if auto_layout

        { width: [width, DEFAULT_BLOCK_WIDTH].max,
          height: [height, DEFAULT_BLOCK_HEIGHT].max }
      end

      def positioned_connection(connection, blocks_layout, auto_layout)
        from_block = blocks_layout[connection.source_id]
        to_block = blocks_layout[connection.target_id]
        return unless from_block && to_block

        connection_geometry(connection,
                            connection_points(from_block, to_block,
                                              auto_layout))
      end

      def connection_geometry(connection, points)
        {
          from: connection.source_id, to: connection.target_id,
          from_x: points[0], from_y: points[1],
          to_x: points[2], to_y: points[3], connection_type: connection.role
        }
      end

      def horizontal_connection_points(from_block, to_block)
        [from_block[:x] + from_block[:width],
         from_block[:y] + (from_block[:height] / 2),
         to_block[:x], to_block[:y] + (to_block[:height] / 2)]
      end

      def vertical_connection_points(from_block, to_block)
        [from_block[:x] + (from_block[:width] / 2),
         from_block[:y] + from_block[:height],
         to_block[:x] + (to_block[:width] / 2), to_block[:y]]
      end
    end
  end
end
