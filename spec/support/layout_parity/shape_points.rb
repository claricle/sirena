# frozen_string_literal: true

module SpecSupport
  module LayoutParity
    # The outline points of one drawn primitive in its own local space.
    # Circles and ellipses are sampled at 64 points (a multiple of four, so an
    # untransformed bbox is exact).
    class ShapePoints
      PRIMITIVES = %w[rect circle ellipse polygon polyline path line].freeze
      ROUND_STEPS = 64

      def self.primitive?(node)
        PRIMITIVES.include?(node.name)
      end

      def initialize(node)
        @node = node
      end

      def points
        send(:"#{@node.name}_points")
      end

      private

      def num(name)
        @node[name].to_s[Matrix::NUMBER].to_f
      end

      def rect_points
        x = num("x")
        y = num("y")
        w = num("width")
        h = num("height")
        [[x, y], [x + w, y], [x + w, y + h], [x, y + h]]
      end

      def circle_points
        round(num("cx"), num("cy"), num("r"), num("r"))
      end

      def ellipse_points
        round(num("cx"), num("cy"), num("rx"), num("ry"))
      end

      def round(cx, cy, rx, ry)
        Array.new(ROUND_STEPS) do |i|
          a = 2 * Math::PI * i / ROUND_STEPS
          [cx + (rx * Math.cos(a)), cy + (ry * Math.sin(a))]
        end
      end

      def polygon_points
        @node["points"].to_s.scan(Matrix::NUMBER).map(&:to_f).each_slice(2).select { |s| s.size == 2 }
      end
      alias polyline_points polygon_points

      def line_points
        [[num("x1"), num("y1")], [num("x2"), num("y2")]]
      end

      def path_points
        PathPoints.new(@node["d"]).points
      end
    end
  end
end
