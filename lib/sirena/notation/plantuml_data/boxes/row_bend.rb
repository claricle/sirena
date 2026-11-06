# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUMLData
      module Boxes
        # The two handles of the spline a link to or from a map row is drawn
        # as: it leaves a row by its side, square to it, and meets a box edge
        # head on.
        module RowBend
          extend self

          REACH = 30.0
          EASE = 0.35

          # @param ends [Array<Array<Float>>] where the line starts and stops
          # @param rows [Array<Boolean>] whether each end is a row of its box
          # @param centres [Array<Array<Float>>] the middle of each end's box
          # @return [Array<Array<Float>>] the handle of the start, then of
          #   the stop
          def handles(ends, rows, centres)
            [0, 1].map do |at|
              point = ends[at]
              other = ends[1 - at]
              next square(point, other, centres[at]) if rows[at]

              [point[0], point[1] + ((other[1] - point[1]) * EASE)]
            end
          end

          private

          # A point out from the side of the box `point` is on.
          def square(point, other, centre)
            reach = [(other[0] - point[0]).abs / 2, REACH].max
            side = point[0] >= centre[0] ? 1 : -1
            [point[0] + (side * reach), point[1]]
          end
        end
      end
    end
  end
end
