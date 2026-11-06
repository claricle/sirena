# frozen_string_literal: true

require_relative "../../../svg"

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # The pointer of a note: a pale triangle with its base on the note
        # and its tip on the note's target.
        class NoteTail
          HALF = 4.0
          FILL = "#FEFFDD"
          STROKE = "#181818"

          # @param points [Array<Array(Float, Float)>] the route, from the
          #   note to its target
          def initialize(points)
            @base = points.first
            @tip = points.last
          end

          # @return [Svg::Polygon]
          def element
            Svg::Polygon.new.tap do |polygon|
              polygon.points = outline
              polygon.fill = FILL
              polygon.stroke = STROKE
              polygon.stroke_width = "0.5"
            end
          end

          private

          def outline
            across = normal
            [offset(across, 1), @tip, offset(across, -1)]
              .map { |point| point.map { |value| value.round(2) }.join(",") }
              .join(" ")
          end

          def offset(across, sign)
            [@base[0] + (sign * across[0]), @base[1] + (sign * across[1])]
          end

          # @return [Array(Float, Float)] half the base's width, at a right
          #   angle to the route
          def normal
            dx = @tip[0] - @base[0]
            dy = @tip[1] - @base[1]
            scale = HALF / [Math.hypot(dx, dy), 1.0].max
            [-dy * scale, dx * scale]
          end
        end
      end
    end
  end
end
