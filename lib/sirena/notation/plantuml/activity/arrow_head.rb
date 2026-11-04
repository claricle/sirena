# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Activity
        # The triangle at the end of an edge.
        module ArrowHead
          module_function

          LENGTH = 9.0
          HALF_WIDTH = 3.5
          private_constant :LENGTH, :HALF_WIDTH

          # @param segment [Array<Array(Float, Float)>] the last two
          #   points of the edge
          # @return [Array<Array(Float, Float)>] tip, then the two corners
          def points(segment)
            tip = segment.last
            unit = unit_vector(segment)
            [tip, *corners(tip, unit)]
          end

          def corners(tip, unit)
            base = shifted(tip, unit, -LENGTH)
            side = [-unit.last, unit.first]
            [shifted(base, side, HALF_WIDTH), shifted(base, side, -HALF_WIDTH)]
          end

          def unit_vector(segment)
            run = segment.last.first - segment.first.first
            rise = segment.last.last - segment.first.last
            length = Math.hypot(run, rise)
            [run / length, rise / length]
          end

          def shifted(base, vector, scale)
            [base.first + (scale * vector.first),
             base.last + (scale * vector.last)]
          end
        end
      end
    end
  end
end
