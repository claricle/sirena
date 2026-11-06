# frozen_string_literal: true

require_relative "row_spread"

module Sirena
  module Notation
    module PlantUML
      module Activity
        # How far each column reaches left and right of its centre, as a
        # whole and row by row. A row is a rank, or half a rank past it for
        # a parked node.
        class Reach
          # @return [Hash{Array => Array(Float, Float)}] the whole column
          attr_reader :columns
          # @return [Hash{Array => Hash{Numeric => Array(Float, Float)}}]
          attr_reader :rows

          # @param keys [Array<Array>] every column key
          # @param by_row [Boolean] whether columns clear each other row by
          #   row rather than as wholes
          def initialize(keys, by_row: false)
            @by_row = by_row
            @columns = keys.to_h { |key| [key, [0.0, 0.0]] }
            @rows = keys.to_h do |key|
              [key, Hash.new { |rows, row| rows[row] = [0.0, 0.0] }]
            end
          end

          # Widens a column, on one row, to at least `value` on a side.
          # @param side [Integer] 0 for left, 1 for right
          def grow(key, row, side, value)
            [@columns[key], @rows[key][row]].each do |reach|
              reach[side] = [reach[side], value].max
            end
          end

          # Stands a line on a column's rows, as wide as nothing.
          def line(key, rows)
            rows.each { |row| grow(key, row, 0, 0.0) }
          end

          # @return [RowSpread, nil] nil unless the columns clear by row
          def row_spread(margin)
            RowSpread.new(@rows, @columns, margin) if @by_row
          end
        end
      end
    end
  end
end
