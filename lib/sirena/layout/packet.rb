# frozen_string_literal: true

require_relative "base"
require_relative "../notation/mermaid/ir_adapters/packet"

module Sirena
  module Layout
    # Transforms a Packet into a positioned layout structure.
    #
    # Geometry follows mermaid's packet renderer: one 32-bit word per row,
    # each bit 32px wide, each block 32px high with a 5px right gap, the
    # start and end bit numbers drawn just above the block, and the title
    # centred in the last row slot.
    #
    # @example Transform a packet diagram
    #   transform = Layout::Packet.new
    #   layout = transform.to_graph(diagram)
    class Packet < Base
      BITS_PER_ROW = 32
      BIT_WIDTH = 32
      ROW_HEIGHT = 32
      PADDING_X = 5
      # mermaid's paddingY (5) plus 10 for the bit numbers drawn above a row.
      PADDING_Y = 15
      ROW_PITCH = ROW_HEIGHT + PADDING_Y

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
        attribute :style, :string
      end

      class Field < Lutaml::Model::Serializable
        attribute :box, Box
        attribute :label, Label
        attribute :start_label, Label
        attribute :end_label, Label
      end

      class Scene < Layout::Scene
        attribute :view_box, :string
        attribute :title, Label
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
      # @return [Hash] layout data with field segments and canvas size
      def build_graph(diagram)
        document = ir_document(diagram)
        fields = document.items.select { |item| item.role == "field" }
        row_count = fields.empty? ? 0 : packet_row_count(fields)
        size = canvas_size(row_count, document.label)
        { fields: position_fields(fields), row_count: row_count,
          title: document.label, width: size.first, height: size.last }
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
        width, height = canvas_size(graph.fetch(:row_count), graph[:title])
        Scene.new(
          width: width, height: height, view_box: "0 0 #{width} #{height}",
          title: title_label(graph[:title], width, height),
          fields: graph.fetch(:fields).map { |field| typed_field(field) }
        )
      end

      # mermaid: (rows + 1) row slots, minus one row height without a title.
      def canvas_size(row_count, title)
        height = (ROW_PITCH * (row_count + 1)) - (title ? 0 : ROW_HEIGHT)
        [(BITS_PER_ROW * BIT_WIDTH) + 2, height]
      end

      def title_label(title, width, height)
        return unless title

        Label.new(
          text: title, x: width / 2.0, y: height - (ROW_PITCH / 2.0),
          font_size: 14, text_anchor: "middle",
          dominant_baseline: "middle", style: "title"
        )
      end

      def typed_field(field)
        first = field.fetch(:bit_start)
        last = field.fetch(:bit_end)
        box = block_box(first, last)
        Field.new(
          box: box, label: block_label(field[:label], box),
          start_label: start_label(first, last, box),
          end_label: end_label(first, last, box)
        )
      end

      def block_box(first, last)
        Box.new(
          x: ((first % BITS_PER_ROW) * BIT_WIDTH) + 1,
          y: ((first / BITS_PER_ROW) * ROW_PITCH) + PADDING_Y,
          width: ((last - first + 1) * BIT_WIDTH) - PADDING_X,
          height: ROW_HEIGHT,
        )
      end

      def block_label(text, box)
        Label.new(
          text: text, x: box.x + (box.width / 2.0),
          y: box.y + (ROW_HEIGHT / 2.0), font_size: 12,
          text_anchor: "middle", dominant_baseline: "middle", style: "field"
        )
      end

      def start_label(first, last, box)
        single = first == last
        Label.new(
          text: first.to_s, x: box.x + (single ? box.width / 2.0 : 0),
          y: box.y - 2, font_size: 10,
          text_anchor: single ? "middle" : "start",
          dominant_baseline: "auto", style: "start"
        )
      end

      def end_label(first, last, box)
        return if first == last

        Label.new(
          text: last.to_s, x: box.x + box.width, y: box.y - 2,
          font_size: 10, text_anchor: "end",
          dominant_baseline: "auto", style: "end"
        )
      end

      def packet_row_count(fields)
        maximum = fields.map { |field| bit_end(field) }.max
        ((maximum + 1).to_f / BITS_PER_ROW).ceil
      end

      # Positions all fields in the grid.
      #
      # @param fields [Array<Diagram::PacketField>] fields to position
      # @return [Array<Hash>] positioned fields with coordinates
      def position_fields(fields)
        fields.flat_map do |field|
          if start_row(field) == end_row(field)
            [position_single_field(field)]
          else
            split_field_across_rows(field)
          end
        end
      end

      # Positions a field that fits in a single row.
      #
      # @param field [Diagram::PacketField] field to position
      # @return [Hash] positioned field data
      def position_single_field(field)
        row = start_row(field)
        start_col = start_bit_in_row(field)
        end_col = end_bit_in_row(field)
        field_segment(
          field, bit_start(field)..bit_end(field), [row, start_col, end_col]
        )
      end

      def field_segment(field, bit_range, placement)
        row, start_col, end_col = placement
        {
          label: field.label,
          bit_start: bit_range.begin,
          bit_end: bit_range.end,
        }.merge(segment_geometry(row, start_col, end_col))
      end

      def segment_geometry(row, start_col, end_col)
        { row: row, start_col: start_col, end_col: end_col }
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
          segment = split_segment(field, current_bit, final_bit)
          segments << segment
          segment_end_bit = segment[:bit_end]
          current_bit = segment_end_bit + 1
        end

        segments
      end

      def split_segment(field, current_bit, final_bit)
        row = current_bit / BITS_PER_ROW
        start_col = current_bit % BITS_PER_ROW
        segment_end_bit = segment_end(row, final_bit)
        segment = field_segment(
          field, current_bit..segment_end_bit,
          [row, start_col, segment_end_bit % BITS_PER_ROW]
        )
        segment.merge(
          segment_status(field, current_bit, segment_end_bit, final_bit),
        )
      end

      def segment_end(row, final_bit)
        [final_bit, ((row + 1) * BITS_PER_ROW) - 1].min
      end

      def segment_status(field, current_bit, segment_end_bit, final_bit)
        {
          is_continuation: current_bit > bit_start(field),
          is_final: segment_end_bit == final_bit,
        }
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
