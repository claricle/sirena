# frozen_string_literal: true

module Sirena
  module Transform
    # Transforms a PacketDiagram into a positioned layout structure.
    #
    # The layout algorithm handles:
    # - Organizing fields into rows based on bit positions
    # - Calculating cell positions in the packet grid
    # - Handling fields that span multiple bits
    # - Typical packet width is 32 bits per row
    #
    # @example Transform a packet diagram
    #   transform = Transform::Packet.new
    #   layout = transform.to_graph(diagram)
    class Packet
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

      # Transforms the diagram into a layout structure.
      #
      # @param diagram [Diagram::PacketDiagram] the packet diagram
      # @return [Hash] layout data with positioned fields and dimensions
      def to_graph(diagram)
        return empty_layout if diagram.fields.empty?

        # Calculate the number of rows needed
        row_count = diagram.row_count(BITS_PER_ROW)

        # Position each field
        positioned_fields = position_fields(diagram.fields, row_count)

        # Calculate dimensions
        width = BITS_PER_ROW * CELL_WIDTH + (PADDING * 2)
        content_height = row_count * CELL_HEIGHT + HEADER_HEIGHT
        title_offset = diagram.title ? TITLE_HEIGHT + TITLE_MARGIN : 0
        height = content_height + (PADDING * 2) + title_offset

        {
          fields: positioned_fields,
          row_count: row_count,
          bits_per_row: BITS_PER_ROW,
          cell_width: CELL_WIDTH,
          cell_height: CELL_HEIGHT,
          padding: PADDING,
          header_height: HEADER_HEIGHT,
          title_height: diagram.title ? TITLE_HEIGHT : 0,
          title_margin: diagram.title ? TITLE_MARGIN : 0,
          width: width,
          height: height,
          title: diagram.title
        }
      end

      private

      # Returns an empty layout structure.
      #
      # @return [Hash] empty layout
      def empty_layout
        {
          fields: [],
          row_count: 0,
          bits_per_row: BITS_PER_ROW,
          cell_width: CELL_WIDTH,
          cell_height: CELL_HEIGHT,
          padding: PADDING,
          header_height: HEADER_HEIGHT,
          title_height: 0,
          title_margin: 0,
          width: PADDING * 2,
          height: PADDING * 2,
          title: nil
        }
      end

      # Positions all fields in the grid.
      #
      # @param fields [Array<Diagram::PacketField>] fields to position
      # @param row_count [Integer] total number of rows
      # @return [Array<Hash>] positioned fields with coordinates
      def position_fields(fields, row_count)
        positioned = []

        fields.each do |field|
          # Handle fields that may span multiple rows
          if field.spans_rows?(BITS_PER_ROW)
            # Split into multiple visual segments
            positioned.concat(split_field_across_rows(field))
          else
            # Single row field
            positioned << position_single_field(field)
          end
        end

        positioned
      end

      # Positions a field that fits in a single row.
      #
      # @param field [Diagram::PacketField] field to position
      # @return [Hash] positioned field data
      def position_single_field(field)
        row = field.start_row(BITS_PER_ROW)
        start_col = field.start_bit_in_row(BITS_PER_ROW)
        end_col = field.end_bit_in_row(BITS_PER_ROW)

        x = PADDING + (start_col * CELL_WIDTH)
        y = PADDING + HEADER_HEIGHT + (row * CELL_HEIGHT)
        width = (end_col - start_col + 1) * CELL_WIDTH
        height = CELL_HEIGHT

        {
          label: field.label,
          bit_start: field.bit_start,
          bit_end: field.bit_end,
          x: x,
          y: y,
          width: width,
          height: height,
          row: row,
          start_col: start_col,
          end_col: end_col
        }
      end

      # Splits a field that spans multiple rows into visual segments.
      #
      # @param field [Diagram::PacketField] field to split
      # @return [Array<Hash>] array of positioned segments
      def split_field_across_rows(field)
        segments = []
        current_bit = field.bit_start

        while current_bit <= field.bit_end
          row = current_bit / BITS_PER_ROW
          start_col = current_bit % BITS_PER_ROW

          # Determine end column for this row
          row_end_bit = ((row + 1) * BITS_PER_ROW) - 1
          segment_end_bit = [field.bit_end, row_end_bit].min
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
            is_continuation: current_bit > field.bit_start,
            is_final: segment_end_bit == field.bit_end
          }

          current_bit = segment_end_bit + 1
        end

        segments
      end
    end
  end
end