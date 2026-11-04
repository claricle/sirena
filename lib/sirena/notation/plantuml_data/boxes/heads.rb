# frozen_string_literal: true

require_relative "marks"

module Sirena
  module Notation
    module PlantUMLData
      module Boxes
        # The shape at the end of a relation: an arrow, a hollow triangle
        # for extension and a diamond for composition and aggregation.
        module Heads
          extend self

          LENGTH = 10.0
          HALF = 4.5
          WHITE = "#FFFFFF"
          # kind => the outline drawn and what it is filled with
          SHAPES = {
            association: [:triangle, Marks::INK],
            dependency: [:triangle, Marks::INK],
            extension: [:triangle, WHITE],
            implementation: [:triangle, WHITE],
            composition: [:diamond, Marks::INK],
            aggregation: [:diamond, WHITE],
          }.freeze
          # [distance back along the line, distance to its side] of each corner
          OUTLINES = {
            triangle: [[LENGTH, HALF], [0, 0], [LENGTH, -HALF]],
            diamond: [[0, 0], [6, HALF], [12, 0], [6, -HALF]],
          }.freeze
          private_constant :WHITE, :SHAPES, :OUTLINES

          # @param kind [Symbol] an Arrow kind
          # @param tip [Array<Float>] where the shape touches the box
          # @param from [Array<Float>] a point on the line the shape ends
          # @return [Array<Hash>] its marks; none for an unmarked end
          def call(kind, tip, from)
            shape = SHAPES[kind] or return []
            outline, fill = shape
            axis = unit(tip, from)
            side = [-axis[1], axis[0]]
            points = OUTLINES.fetch(outline).map do |back, over|
              corner(tip, [axis, side], back, over)
            end
            [Marks.polygon(points, fill: fill, stroke: Marks::INK)]
          end

          private

          def unit(tip, from)
            dx = tip[0] - from[0]
            dy = tip[1] - from[1]
            size = Math.hypot(dx, dy)
            size.zero? ? [1.0, 0.0] : [dx / size, dy / size]
          end

          def corner(tip, (axis, side), back, over)
            [tip[0] - (axis[0] * back) + (side[0] * over),
             tip[1] - (axis[1] * back) + (side[1] * over)]
          end
        end
      end
    end
  end
end
