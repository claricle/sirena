# frozen_string_literal: true

module Sirena
  module Layout
    # Spatial index that limits which pairs of mindmap boxes repel each
    # other: only boxes in neighbouring cells within the repulsion range.
    class MindmapCoseGrid
      MARGIN = 15.0

      def initialize(bodies, range)
        @bodies = bodies
        @range = range
        @cells = []
      end

      # Rebuilds the cells from the current box positions.
      def refresh
        left, top, right, bottom = bounds
        @cells = Array.new(((right - left) / @range).ceil) do
          Array.new(((bottom - top) / @range).ceil) { [] }
        end
        @bodies.each { |body| add(body, left, top) }
      end

      # Recomputes which not yet processed boxes lie within range of +body+.
      def refresh_surrounding(body, processed)
        found = {}
        candidates(body).each do |other|
          next if processed.key?(other) || found.key?(other)

          found[other] = true if within_range?(body, other)
        end
        body.surrounding = found.keys
      end

      private

      def bounds
        left = @bodies.map(&:x).min
        top = @bodies.map(&:y).min
        width = @bodies.map(&:right).max - left
        height = @bodies.map(&:bottom).max - top
        [left - MARGIN, top - MARGIN, left + width + MARGIN,
         top + height + MARGIN]
      end

      def add(body, left, top)
        first_x = ((body.x - left) / @range).floor
        last_x = ((body.width + body.x - left) / @range).floor
        first_y = ((body.y - top) / @range).floor
        last_y = ((body.height + body.y - top) / @range).floor
        (first_x..last_x).each do |column|
          (first_y..last_y).each { |row| @cells[column][row] << body }
        end
        body.cells = [first_x, last_x, first_y, last_y]
      end

      def candidates(body)
        first_x, last_x, first_y, last_y = body.cells
        found = []
        ((first_x - 1)..(last_x + 1)).each do |column|
          ((first_y - 1)..(last_y + 1)).each do |row|
            next unless cell?(column, row)

            found.concat(@cells[column][row].reject { |other| other.equal?(body) })
          end
        end
        found
      end

      def cell?(column, row)
        column >= 0 && row >= 0 && column < @cells.length &&
          row < @cells.first.length
      end

      def within_range?(body, other)
        gap_x = (body.center_x - other.center_x).abs -
                ((body.width / 2) + (other.width / 2))
        gap_y = (body.center_y - other.center_y).abs -
                ((body.height / 2) + (other.height / 2))
        gap_x <= @range && gap_y <= @range
      end
    end
  end
end
