# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module State
        # Rectangles and segments on the page, a rectangle as
        # `[left, top, right, bottom]`.
        module Plane
          STEPS = 60

          extend self

          def rect(box)
            [box.x, box.y, box.x + box.w, box.y + box.h]
          end

          def around(centre, half)
            [centre.first - half.first, centre.last - half.last,
             centre.first + half.first, centre.last + half.last]
          end

          def grow(rect, margin)
            rect.zip([-margin, -margin, margin, margin]).map(&:sum)
          end

          def corners(rect)
            [[rect[0], rect[1]], [rect[2], rect[1]],
             [rect[2], rect[3]], [rect[0], rect[3]]]
          end

          def centre(rect)
            [(rect[0] + rect[2]) / 2.0, (rect[1] + rect[3]) / 2.0]
          end

          def meet?(one, other)
            one[0] < other[2] && other[0] < one[2] &&
              one[1] < other[3] && other[1] < one[3]
          end

          def inside?(rect, spot)
            spot.first.between?(rect[0], rect[2]) &&
              spot.last.between?(rect[1], rect[3])
          end

          # @return [Boolean] whether the segment passes through the rect
          def crosses?(rect, from, to)
            (0..STEPS).any? do |step|
              inside?(rect, along(from, to, step.fdiv(STEPS)))
            end
          end

          def along(from, to, fraction)
            from.zip(to).map do |start, finish|
              start + ((finish - start) * fraction)
            end
          end

          # @return [Array] the point a fraction of the way along the
          #   polyline's length, with the stretch it lies on
          def at_length(points, fraction)
            stretch, left = stretch_at(points, fraction)
            back = (1 + (left / length(stretch))).clamp(..1.0)
            [along(*stretch, back), *stretch]
          end

          # @return [Array(Array, Float)] the stretch a length along the
          #   polyline lies on, and how far along that stretch it is
          def stretch_at(points, fraction)
            stretches = points.each_cons(2).reject { |from, to| from == to }
            left = length(points) * fraction
            stretch = stretches.find { |one| (left -= length(one)) <= 0 }
            [stretch || stretches.last, left]
          end

          def length(points)
            points.each_cons(2).sum do |from, to|
              Math.hypot(to.first - from.first, to.last - from.last)
            end
          end
        end
      end
    end
  end
end
