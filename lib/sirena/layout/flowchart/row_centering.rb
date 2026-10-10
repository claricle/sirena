# frozen_string_literal: true

module Sirena
  module Layout
    class Flowchart < Base
      # Centres every layer of a laid-out level on one axis, the way dagre
      # leaves a chain of different-sized nodes straight. elkrb sets each
      # layer against the left edge. Works on a level laid out downward.
      class RowCentering
        # @param flat [Hash] a level whose boxes elkrb has placed
        def self.apply(flat)
          new(flat).apply
        end

        def initialize(flat)
          @flat = flat
        end

        def apply
          rows = @flat[:children].group_by { |box| box[:y] }
          widest = rows.values.map { |row| span(row) }.max
          rows.each_value { |row| centre(row, widest) }
          @flat
        end

        private

        def centre(row, widest)
          shift = (widest - span(row)) / 2.0
          row.each { |box| box[:x] += shift }
        end

        def span(row)
          left = row.map { |box| box[:x] }.min
          row.map { |box| box[:x] + box[:width] }.max - left
        end
      end
    end
  end
end
