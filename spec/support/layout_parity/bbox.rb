# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # An axis-aligned box in root viewBox user units.
    class Bbox
      attr_reader :min_x, :min_y, :max_x, :max_y

      def initialize(min_x, min_y, max_x, max_y)
        @min_x = min_x.to_f
        @min_y = min_y.to_f
        @max_x = max_x.to_f
        @max_y = max_y.to_f
      end

      def self.from_points(points)
        return nil if points.empty?

        xs = points.map(&:first)
        ys = points.map(&:last)
        new(xs.min, ys.min, xs.max, ys.max)
      end

      def self.union(boxes)
        boxes = boxes.compact
        return nil if boxes.empty?

        new(boxes.map(&:min_x).min, boxes.map(&:min_y).min, boxes.map(&:max_x).max, boxes.map(&:max_y).max)
      end

      def width
        max_x - min_x
      end

      def height
        max_y - min_y
      end

      def area
        width * height
      end

      def center
        [(min_x + max_x) / 2, (min_y + max_y) / 2]
      end

      # True when other lies inside self (edges may touch).
      def contain?(other, tolerance: 1e-6)
        other.min_x >= min_x - tolerance && other.min_y >= min_y - tolerance &&
          other.max_x <= max_x + tolerance && other.max_y <= max_y + tolerance
      end

      def to_a
        [min_x, min_y, max_x, max_y]
      end
    end
  end
end
