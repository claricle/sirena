# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # The outline of a cloud: eight quadratic bumps around an ellipse
        # that fits the box.
        class Cloud
          LOBES = 8
          BULGE = 1.12
          FIT = 0.88

          # @param box [Placed]
          def initialize(box)
            @cx = box.x + (box.width / 2)
            @cy = box.y + (box.height / 2)
            @rx = box.width / 2 * FIT
            @ry = box.height / 2 * FIT
          end

          # @return [String] SVG path data
          def to_d
            first = point(0, 1.0)
            curves = Array.new(LOBES) { |i| curve(i) }
            "M#{coords(first)} #{curves.join(' ')} Z"
          end

          private

          def curve(index)
            "Q#{coords(point(index + 0.5, BULGE))} " \
              "#{coords(point((index + 1) % LOBES, 1.0))}"
          end

          def point(step, scale)
            angle = step * Math::PI / (LOBES / 2)
            [@cx + (@rx * scale * Math.cos(angle)),
             @cy + (@ry * scale * Math.sin(angle))]
          end

          def coords(point)
            point.map { |value| value.round(2) }.join(",")
          end
        end
      end
    end
  end
end
