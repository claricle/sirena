# frozen_string_literal: true

require_relative "route_points"

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
          @rows = @flat[:children].group_by { |box| box[:y] }
          widest = @rows.values.map { |row| span(row) }.max
          @shifts = @rows.transform_values { |row| (widest - span(row)) / 2.0 }
          @flat[:children].each { |box| box[:x] += @shifts[box[:y]] }
          RoutePoints.of(@flat).each { |point| point[:x] += shift_at(point[:y]) }
          @flat
        end

        private

        def span(row)
          row.map { |box| box[:x] + box[:width] }.max - row.map { |box| box[:x] }.min
        end

        # A point between two layers moves with the layer above it.
        def shift_at(y_pos)
          top = @shifts.keys.sort.reverse.find { |key| key <= y_pos }
          @shifts.fetch(top || @shifts.keys.min)
        end
      end
    end
  end
end
