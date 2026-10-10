# frozen_string_literal: true

module Sirena
  module Layout
    # The running extent of one C4 boundary while its boxes are placed, a
    # port of mermaid's Bounds. Boxes fill a row left to right and start a
    # new row when the next one would pass the width limit or the row
    # already holds the configured number.
    class C4Bounds
      MARGIN = 50

      # A rectangle given by its four edges, grown to cover more.
      class Extent
        attr_accessor :startx, :stopx, :starty, :stopy

        def reset(x_pos, y_pos)
          @startx = @stopx = x_pos
          @starty = @stopy = y_pos
        end

        def cover(left, top, right, bottom)
          @startx = [@startx, left].min
          @starty = [@starty, top].min
          @stopx = [@stopx, right].max
          @stopy = [@stopy, bottom].max
        end
      end

      attr_reader :data, :width_limit

      # @param width_limit [Numeric] the right edge a box may not reach
      # @param per_row [Integer] boxes allowed in one row
      def initialize(width_limit:, per_row:)
        @width_limit = width_limit
        @per_row = per_row
        @data = Extent.new
        @upcoming = Extent.new
        @count = 0
      end

      # Restarts the extent at a point, as mermaid's setData does.
      def start_at(x_pos, y_pos)
        @data.reset(x_pos, y_pos)
        @upcoming.reset(x_pos, y_pos)
      end

      # Gives a box node its :x and :y and grows the extent over it.
      def insert(node)
        @count += 1
        left, top = origin
        right = left + node[:width]
        left, top, right = next_line(node) if overflows?(left, right)
        node[:x] = left
        node[:y] = top
        cover(left, top, right, top + node[:height])
      end

      def bump_last_margin
        @data.stopx += MARGIN
        @data.stopy += MARGIN
      end

      # Grows this extent to hold a finished child boundary and its margin.
      def absorb(child)
        @data.stopy = [child.data.stopy + MARGIN, @data.stopy].max
        @data.stopx = [child.data.stopx + MARGIN, @data.stopx].max
      end

      private

      def origin
        gap = @upcoming.startx == @upcoming.stopx ? MARGIN : MARGIN * 2
        [@upcoming.stopx + gap, @upcoming.starty + (MARGIN * 2)]
      end

      def overflows?(left, right)
        left >= @width_limit || right >= @width_limit || @count > @per_row
      end

      def next_line(node)
        left = @upcoming.startx + MARGIN
        top = @upcoming.stopy + (MARGIN * 2)
        @upcoming.stopx = left + node[:width]
        @upcoming.starty = @upcoming.stopy
        @upcoming.stopy = top + node[:height]
        @count = 1
        [left, top, @upcoming.stopx]
      end

      def cover(left, top, right, bottom)
        @data.cover(left, top, right, bottom)
        @upcoming.cover(left, top, right, bottom)
      end
    end
  end
end
