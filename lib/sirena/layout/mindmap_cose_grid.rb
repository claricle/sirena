# frozen_string_literal: true

require_relative "mindmap_cose_geometry"

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
        left, top, right, bottom = MindmapCoseGeometry.bounding_box(@bodies)
        width = right - left
        height = bottom - top
        [left - MARGIN, top - MARGIN, left + width + MARGIN,
         top + height + MARGIN]
      end

      def add(body, left, top)
        first_x, last_x = span(body.x, body.width, left)
        first_y, last_y = span(body.y, body.height, top)
        (first_x..last_x).each do |column|
          (first_y..last_y).each { |row| @cells[column][row] << body }
        end
        body.cells = [first_x, last_x, first_y, last_y]
      end

      # @return [Array<Integer>] first and last cell index along one axis
      def span(start, size, origin)
        [((start - origin) / @range).floor,
         ((size + start - origin) / @range).floor]
      end

      def candidates(body)
        first_x, last_x, first_y, last_y = body.cells
        found = []
        ((first_x - 1)..(last_x + 1)).each do |column|
          ((first_y - 1)..(last_y + 1)).each do |row|
            found.concat(cell_members(column, row, body))
          end
        end
        found
      end

      def cell_members(column, row, body)
        return [] unless cell?(column, row)

        @cells[column][row].reject { |other| other.equal?(body) }
      end

      def cell?(column, row)
        column >= 0 && row >= 0 && column < @cells.length &&
          row < @cells.first.length
      end

      def within_range?(body, other)
        gap_x = gap(body.center_x, other.center_x, body.width, other.width)
        gap_y = gap(body.center_y, other.center_y, body.height, other.height)
        gap_x <= @range && gap_y <= @range
      end

      def gap(centre, other_centre, size, other_size)
        (centre - other_centre).abs - ((size / 2) + (other_size / 2))
      end
    end
  end
end
