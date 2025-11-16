# frozen_string_literal: true

module Sirena
  module Diagram
    # Represents a packet diagram showing network packet structures
    class PacketDiagram < Base
      attr_accessor :title, :fields

      def initialize
        super
        @fields = []
      end

      def type
        :packet
      end

      # Add a field to the packet
      def add_field(field)
        @fields << field
      end

      # Get the maximum bit position used in the packet
      def max_bit_position
        return 0 if @fields.empty?

        @fields.map(&:bit_end).max
      end

      # Calculate the number of rows needed (assuming 32-bit width)
      def row_count(bits_per_row = 32)
        return 1 if @fields.empty?

        ((max_bit_position + 1).to_f / bits_per_row).ceil
      end
    end

    # Represents a field in a packet diagram
    class PacketField
      attr_accessor :bit_start, :bit_end, :label

      def initialize(bit_start, bit_end, label)
        @bit_start = bit_start.to_i
        @bit_end = bit_end.to_i
        @label = label
      end

      # Get the size of the field in bits
      def size
        @bit_end - @bit_start + 1
      end

      # Get the row this field starts in (for 32-bit rows)
      def start_row(bits_per_row = 32)
        @bit_start / bits_per_row
      end

      # Get the row this field ends in (for 32-bit rows)
      def end_row(bits_per_row = 32)
        @bit_end / bits_per_row
      end

      # Check if this field spans multiple rows
      def spans_rows?(bits_per_row = 32)
        start_row(bits_per_row) != end_row(bits_per_row)
      end

      # Get the bit position within a row (0-31 for 32-bit rows)
      def start_bit_in_row(bits_per_row = 32)
        @bit_start % bits_per_row
      end

      # Get the ending bit position within a row
      def end_bit_in_row(bits_per_row = 32)
        @bit_end % bits_per_row
      end
    end
  end
end