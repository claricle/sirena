# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # The outline of a cloud as PlantUML draws it: the box's rectangle
        # with its corners cut, every side a run of small outward bumps.
        class Cloud
          BUMP = 11.0
          PUSH = 8.0
          RISE = 4.0
          CUT = 9.0

          # @param box [Placed]
          def initialize(box)
            @left = box.x + RISE
            @top = box.y + RISE
            @right = box.x + box.width - RISE
            @bottom = box.y + box.height - RISE
          end

          # @return [String] SVG path data
          def to_d
            "M#{coords(corners.first)} #{sides.join(' ')} Z"
          end

          private

          def corners
            [[@left + CUT, @top], [@right - CUT, @top], [@right, @top + CUT],
             [@right, @bottom - CUT], [@right - CUT, @bottom],
             [@left + CUT, @bottom], [@left, @bottom - CUT],
             [@left, @top + CUT]]
          end

          def sides
            corners.zip(corners.rotate).map { |from, to| side(from, to) }
          end

          # Bumps along one side, each a quadratic curve whose control point
          # lies outside the side.
          def side(from, to)
            count = [(Math.hypot(*delta(from, to)) / BUMP).round, 1].max
            Array.new(count) { |index| bump(from, to, index, count) }.join(" ")
          end

          def bump(from, to, index, count)
            control = point(from, to, (index + 0.5) / count, PUSH)
            stop = point(from, to, (index + 1.0) / count, 0)
            "Q#{coords(control)} #{coords(stop)}"
          end

          # The point `along` the side, `push` to the outside of it.
          def point(from, to, along, push)
            dx, dy = delta(from, to)
            unit = push / Math.hypot(dx, dy)
            [from[0] + (dx * along) + (dy * unit),
             from[1] + (dy * along) - (dx * unit)]
          end

          def delta(from, to)
            [to[0] - from[0], to[1] - from[1]]
          end

          def coords(point)
            point.map { |value| value.round(2) }.join(",")
          end
        end
      end
    end
  end
end
