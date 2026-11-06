# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # The path a link is drawn as: a straight line between two points,
        # a smooth curve through every point when the route bends, as the
        # PlantUML JAR draws splines.
        module Curve
          # A bend closer than this to the point before it would only make
          # the curve hook.
          MIN_GAP = 12.0

          extend self

          # @param points [Array<Array(Float, Float)>] a route
          # @return [String] SVG path data
          def path(points)
            route = spaced(points)
            "M #{write(route.first)} " \
              "#{route.size < 3 ? "L #{write(route.last)}" : curves(route)}"
          end

          private

          def curves(route)
            route.each_cons(2).with_index.map do |(from, to), index|
              segment(from, to, route[[index - 1, 0].max],
                      route[[index + 2, route.size - 1].min])
            end.join(" ")
          end

          def segment(from, to, before, after)
            "C #{write(control(from, to, before))} " \
              "#{write(control(to, from, after))} #{write(to)}"
          end

          def spaced(points)
            kept = points[0...-1].each_with_object([]) do |point, found|
              found << point if found.empty? || far?(found.last, point)
            end
            kept.pop if kept.size > 1 && !far?(kept.last, points.last)
            [*kept, points.last]
          end

          def far?(from, to)
            Math.hypot(to[0] - from[0], to[1] - from[1]) >= MIN_GAP
          end

          # The control point a sixth of the way along the chord between
          # the neighbours of `anchor`, on the side of `ahead`.
          def control(anchor, ahead, behind)
            anchor.zip(ahead, behind).map do |here, forward, back|
              here + ((forward - back) / 6.0)
            end
          end

          def write(point)
            point.map { |value| value.round(2) }.join(" ")
          end
        end
      end
    end
  end
end
