# frozen_string_literal: true

require_relative "base"
require_relative "../notation/mermaid/ir_adapters/packet"

module Sirena
  module Layout
    # Transforms a Packet into a positioned layout structure.
    #
    # The layout algorithm handles:
    # - Organizing fields into rows based on bit positions
    # - Calculating cell positions in the packet grid
    # - Handling fields that span multiple bits
    # - Typical packet width is 32 bits per row
    #
    # @example Transform a packet diagram
    #   transform = Layout::Packet.new
    #   layout = transform.to_graph(diagram)
    class Packet < Base
      # Default number of bits per row (standard packet width)
      BITS_PER_ROW = 32

      # Cell dimensions
      CELL_WIDTH = 30
      CELL_HEIGHT = 40

      # Padding around the diagram
      PADDING = 40

      # Header height for bit position markers
      HEADER_HEIGHT = 30

      # Title spacing
      TITLE_HEIGHT = 40
      TITLE_MARGIN = 20

      class Line < Lutaml::Model::Serializable
        attribute :x1, :float
        attribute :y1, :float
        attribute :x2, :float
        attribute :y2, :float
      end

      class Box < Lutaml::Model::Serializable
        attribute :x, :float
        attribute :y, :float
        attribute :width, :float
        attribute :height, :float
      end

      class Label < Lutaml::Model::Serializable
        attribute :text, :string
        attribute :x, :float
        attribute :y, :float
        attribute :font_size, :float
        attribute :text_anchor, :string
        attribute :dominant_baseline, :string
        attribute :font_weight, :string
        attribute :style, :string
      end

      class Field < Lutaml::Model::Serializable
        attribute :box, Box
        attribute :label, Label
        attribute :range_label, Label
      end

      class Scene < Layout::Scene
        attribute :view_box, :string
        attribute :title, Label
        attribute :bit_markers, Label, collection: true, default: -> { [] }
        attribute :grid_lines, Line, collection: true, default: -> { [] }
        attribute :fields, Field, collection: true, default: -> { [] }
      end

      def self.from_graph(graph, theme: nil)
        layout = new
        layout.theme = theme if theme
        layout.send(:scene_from_graph, graph)
      end

      # Transforms the diagram into a layout structure.
      #
      # @param diagram [Diagram::Packet] the packet diagram
      # @return [Hash] layout data with positioned fields and dimensions
      def build_graph(diagram)
        document = ir_document(diagram)
        fields = document.items.select { |item| item.role == "field" }
        return empty_layout(document.label) if fields.empty?

        # Calculate the number of rows needed
        row_count = packet_row_count(fields)

        # Position each field
        positioned_fields = position_fields(fields, row_count)

        # Calculate dimensions
        width = BITS_PER_ROW * CELL_WIDTH + (PADDING * 2)
        content_height = row_count * CELL_HEIGHT + HEADER_HEIGHT
        title_offset = document.label ? TITLE_HEIGHT + TITLE_MARGIN : 0
        height = content_height + (PADDING * 2) + title_offset

        {
          fields: positioned_fields,
          row_count: row_count,
          bits_per_row: BITS_PER_ROW,
          cell_width: CELL_WIDTH,
          cell_height: CELL_HEIGHT,
          padding: PADDING,
          header_height: HEADER_HEIGHT,
          title_height: document.label ? TITLE_HEIGHT : 0,
          title_margin: document.label ? TITLE_MARGIN : 0,
          width: width,
          height: height,
          title: document.label,
        }
      end

      private

      def scene(diagram)
        scene_from_graph(build_graph(diagram))
      end

      def ir_document(diagram)
        return diagram if diagram.is_a?(IR::Prepositioned)

        Notation::Mermaid::IRAdapters::Packet.call(diagram)
      end

      def scene_from_graph(graph)
        width = graph.fetch(:width)
        height = graph.fetch(:height)
        Scene.new(
          width: width, height: height, view_box: "0 0 #{width} #{height}",
          title: title_label(graph), bit_markers: bit_markers(graph),
          grid_lines: grid_lines(graph),
          fields: graph.fetch(:fields).map { |field| typed_field(field, graph) }
        )
      end

      def title_label(graph)
        return unless graph[:title]

        Label.new(
          text: graph[:title], x: graph[:width] / 2.0,
          y: graph[:padding] + (graph[:title_height] / 2.0),
          font_size: font_size(:font_size_large, 16), text_anchor: "middle",
          dominant_baseline: "middle", font_weight: "bold", style: "title"
        )
      end

      def bit_markers(graph)
        graph.fetch(:row_count).times.flat_map do |row|
          Array.new(graph.fetch(:bits_per_row)) do |bit|
            bit_marker(graph, row, bit)
          end
        end
      end

      def bit_marker(graph, row, bit)
        Label.new(
          text: ((row * graph[:bits_per_row]) + bit).to_s,
          x: marker_x(graph, bit), y: marker_y(graph, row),
          font_size: font_size(:font_size_small, 10), text_anchor: "middle",
          dominant_baseline: "middle", style: "marker"
        )
      end

      def marker_x(graph, bit)
        graph[:padding] + (bit * graph[:cell_width]) +
          (graph[:cell_width] / 2.0)
      end

      def marker_y(graph, row)
        graph[:padding] + title_offset(graph) +
          (graph[:header_height] / 2.0) + (row * graph[:cell_height])
      end

      def grid_lines(graph)
        vertical_grid_lines(graph) + horizontal_grid_lines(graph)
      end

      def vertical_grid_lines(graph)
        Array.new(graph[:bits_per_row] + 1) do |index|
          vertical_line(graph, index)
        end
      end

      def vertical_line(graph, index)
        x_position = graph[:padding] + (index * graph[:cell_width])
        y_position = grid_top(graph)
        height = graph[:row_count] * graph[:cell_height]
        Line.new(x1: x_position, y1: y_position,
                 x2: x_position, y2: y_position + height)
      end

      def horizontal_grid_lines(graph)
        grid_width = graph[:bits_per_row] * graph[:cell_width]
        Array.new(graph[:row_count] + 1) do |index|
          horizontal_line(graph, index, grid_width)
        end
      end

      def horizontal_line(graph, index, width)
        y_position = grid_top(graph) + (index * graph[:cell_height])
        Line.new(x1: graph[:padding], y1: y_position,
                 x2: graph[:padding] + width, y2: y_position)
      end

      def grid_top(graph)
        graph[:padding] + title_offset(graph) + graph[:header_height]
      end

      def typed_field(field, graph)
        y_position = field[:y] + title_offset(graph)
        label_x, label_y = field_center(field, y_position)
        Field.new(
          box: field_box(field, y_position),
          label: field_label(field[:label], label_x, label_y),
          range_label: range_label(field, label_x, label_y),
        )
      end

      def field_center(field, y_position)
        [field[:x] + (field[:width] / 2.0),
         y_position + (field[:height] / 2.0)]
      end

      def field_box(field, y_position)
        Box.new(x: field[:x], y: y_position,
                width: field[:width], height: field[:height])
      end

      def field_label(text, x_position, y_position)
        Label.new(
          text: text, x: x_position, y: y_position,
          font_size: font_size(:font_size_normal, 12), text_anchor: "middle",
          dominant_baseline: "middle", style: "field"
        )
      end

      def range_label(field, x_position, y_position)
        return unless field[:width] > 100

        Label.new(
          text: "#{field[:bit_start]}-#{field[:bit_end]}",
          x: x_position, y: y_position + 16,
          font_size: font_size(:font_size_small, 9), text_anchor: "middle",
          dominant_baseline: "middle", style: "range"
        )
      end

      def title_offset(graph)
        graph[:title_height] + graph[:title_margin]
      end

      def font_size(name, fallback)
        value = theme.typography&.public_send(name)
        value&.positive? ? value : fallback
      end

      # Returns an empty layout structure.
      #
      # @return [Hash] empty layout
      def empty_layout(title = nil)
        title_height = title ? TITLE_HEIGHT : 0
        title_margin = title ? TITLE_MARGIN : 0
        {
          fields: [],
          row_count: 0,
          bits_per_row: BITS_PER_ROW,
          cell_width: CELL_WIDTH,
          cell_height: CELL_HEIGHT,
          padding: PADDING,
          header_height: HEADER_HEIGHT,
          title_height: title_height,
          title_margin: title_margin,
          width: PADDING * 2,
          height: (PADDING * 2) + title_height + title_margin,
          title: title,
        }
      end

      def packet_row_count(fields)
        maximum = fields.map { |field| bit_end(field) }.max
        ((maximum + 1).to_f / BITS_PER_ROW).ceil
      end

      # Positions all fields in the grid.
      #
      # @param fields [Array<Diagram::PacketField>] fields to position
      # @param row_count [Integer] total number of rows
      # @return [Array<Hash>] positioned fields with coordinates
      def position_fields(fields, row_count)
        positioned = []

        fields.each do |field|
          if start_row(field) == end_row(field)
            # Single row field
            positioned << position_single_field(field)
          else
            # Split into multiple visual segments
            positioned.concat(split_field_across_rows(field))
          end
        end

        positioned
      end

      # Positions a field that fits in a single row.
      #
      # @param field [Diagram::PacketField] field to position
      # @return [Hash] positioned field data
      def position_single_field(field)
        row = start_row(field)
        start_col = start_bit_in_row(field)
        end_col = end_bit_in_row(field)

        x = PADDING + (start_col * CELL_WIDTH)
        y = PADDING + HEADER_HEIGHT + (row * CELL_HEIGHT)
        width = (end_col - start_col + 1) * CELL_WIDTH
        height = CELL_HEIGHT

        {
          label: field.label,
          bit_start: bit_start(field),
          bit_end: bit_end(field),
          x: x,
          y: y,
          width: width,
          height: height,
          row: row,
          start_col: start_col,
          end_col: end_col,
        }
      end

      # Splits a field that spans multiple rows into visual segments.
      #
      # @param field [Diagram::PacketField] field to split
      # @return [Array<Hash>] array of positioned segments
      def split_field_across_rows(field)
        segments = []
        current_bit = bit_start(field)
        final_bit = bit_end(field)

        while current_bit <= final_bit
          row = current_bit / BITS_PER_ROW
          start_col = current_bit % BITS_PER_ROW

          # Determine end column for this row
          row_end_bit = ((row + 1) * BITS_PER_ROW) - 1
          segment_end_bit = [final_bit, row_end_bit].min
          end_col = segment_end_bit % BITS_PER_ROW

          x = PADDING + (start_col * CELL_WIDTH)
          y = PADDING + HEADER_HEIGHT + (row * CELL_HEIGHT)
          width = (end_col - start_col + 1) * CELL_WIDTH
          height = CELL_HEIGHT

          segments << {
            label: field.label,
            bit_start: current_bit,
            bit_end: segment_end_bit,
            x: x,
            y: y,
            width: width,
            height: height,
            row: row,
            start_col: start_col,
            end_col: end_col,
            is_continuation: current_bit > bit_start(field),
            is_final: segment_end_bit == final_bit,
          }

          current_bit = segment_end_bit + 1
        end

        segments
      end

      def bit_placement(field)
        field.placements.find { |placement| placement.dimension == "bit" }
      end

      def bit_start(field)
        bit_placement(field).value.value.to_i
      end

      def bit_end(field)
        bit_start(field) + bit_placement(field).span.value.to_i - 1
      end

      def start_row(field)
        bit_start(field) / BITS_PER_ROW
      end

      def end_row(field)
        bit_end(field) / BITS_PER_ROW
      end

      def start_bit_in_row(field)
        bit_start(field) % BITS_PER_ROW
      end

      def end_bit_in_row(field)
        bit_end(field) % BITS_PER_ROW
      end
    end
  end
end
