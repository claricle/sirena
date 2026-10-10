# frozen_string_literal: true

module Sirena
  module Layout
    # Squarified tiling of one treemap parent, the same rows and rounding
    # inputs as d3-hierarchy's treemapSquarify with the golden ratio, which is
    # what mmdc uses. Nodes are hashes with :value; x0/y0/x1/y1 are written.
    class TreemapSquarify
      RATIO = (1 + Math.sqrt(5)) / 2

      def self.call(nodes, value, bounds)
        new(nodes, value, bounds).call
      end

      def initialize(nodes, value, bounds)
        @nodes = nodes
        @value = value.to_f
        @x0, @y0, @x1, @y1 = bounds.map(&:to_f)
      end

      def call
        index = 0
        index = place_row(index) while index < @nodes.size
      end

      private

      def place_row(start)
        stop = row_end(start)
        row = @nodes[start...stop]
        sum = row.sum { |node| node[:value] }
        row_bounds(sum, row)
        @value -= sum
        stop
      end

      def row_end(start)
        alpha = alpha_for
        stop = start + 1
        stop += 1 while stop < @nodes.size && grows_well?(start, stop, alpha)
        stop
      end

      def alpha_for
        width = @x1 - @x0
        height = @y1 - @y0
        [height / width, width / height].max / (@value * RATIO)
      end

      def grows_well?(start, stop, alpha)
        before = worst_ratio(@nodes[start...stop], alpha)
        worst_ratio(@nodes[start..stop], alpha) <= before
      end

      def worst_ratio(row, alpha)
        values = row.map { |node| node[:value] }
        beta = values.sum**2 * alpha
        [values.max / beta, beta / values.min].max
      end

      def row_bounds(sum, row)
        width = @x1 - @x0
        height = @y1 - @y0
        if width < height
          dice(row, sum, [@x0, @y0, @x1, @y0 + height * sum / @value])
          @y0 += height * sum / @value
        else
          slice(row, sum, [@x0, @y0, @x0 + width * sum / @value, @y1])
          @x0 += width * sum / @value
        end
      end

      def dice(row, sum, bounds)
        x0, y0, x1, y1 = bounds
        scale = (x1 - x0) / sum
        row.each do |node|
          node.merge!(x0: x0, y0: y0, y1: y1)
          x0 += node[:value] * scale
          node[:x1] = x0
        end
      end

      def slice(row, sum, bounds)
        x0, y0, x1, y1 = bounds
        scale = (y1 - y0) / sum
        row.each do |node|
          node.merge!(x0: x0, x1: x1, y0: y0)
          y0 += node[:value] * scale
          node[:y1] = y0
        end
      end
    end
  end
end
