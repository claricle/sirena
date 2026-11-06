# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Activity
        # Stands columns left to right, each clear of every earlier one only
        # on the rows the two share, so a box may reach under or over a
        # neighbour's that lies on another row.
        class RowSpread
          # @param rows [Hash{Array => Hash{Numeric => Array(Float, Float)}}]
          #   how far each column reaches on each row
          # @param widths [Hash{Array => Array(Float, Float)}] the same for
          #   the whole column
          def initialize(rows, widths, margin)
            @rows = rows
            @widths = widths
            @margin = margin
          end

          # @param solid [Array<Array>] the column keys, in order
          # @yieldparam prior [Array] an earlier column
          # @yieldparam key [Array] the column being placed
          # @yieldreturn [Float] the gap to leave between the two
          # @return [Hash{Array => Float}] each column's centre
          def call(solid, &gap)
            solid.each_with_index.with_object({}) do |(key, index), placed|
              placed[key] = centre(solid.first(index), key, placed, &gap)
            end
          end

          private

          def centre(earlier, key, placed)
            clear = earlier.each_with_index.map do |prior, at|
              placed[prior] +
                clearance(prior, key, yield(prior, key), at == earlier.size - 1)
            end
            [@margin + @widths[key].first, *clear].max
          end

          # How far right of `prior` the column's centre stands: clear of
          # the rows they share, and no further left than the column
          # before it.
          def clearance(prior, key, gap, adjacent)
            shared = @rows[prior].keys & @rows[key].keys
            return adjacent ? 0.0 : -Float::INFINITY if shared.empty?

            shared.map { |row| reach(prior, key, row) }.max + gap
          end

          def reach(prior, key, row)
            @rows[prior][row].last + @rows[key][row].first
          end
        end
      end
    end
  end
end
