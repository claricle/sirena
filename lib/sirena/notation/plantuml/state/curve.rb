# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module State
        # The curve a transition is drawn as: PlantUML draws splines where
        # a layout gives a route of bends.
        module Curve
          # A bend closer than this to the point before it would only make
          # the curve hook.
          MIN_GAP = 12.0

          extend self

          # @param points [Array<Layout::StateDiagram::Point>] a route
          # @return [String] SVG path data: a line for two points, a smooth
          #   curve through every point for more
          def path(points)
            route = spaced(points.map { |point| [point.x, point.y] })
            "M #{write(route.first)} " \
              "#{route.size < 3 ? "L #{write(route.last)}" : curves(route)}"
          end

          private

          def curves(route)
            route.each_cons(2).with_index.map do |(_, to), index|
              segment(route, index, to)
            end.join(" ")
          end

          def spaced(points)
            kept = thinned(points[0...-1])
            kept.pop if kept.size > 1 && !far?(kept.last, points.last)
            [*kept, points.last]
          end

          def thinned(points)
            points.each_with_object([]) do |point, found|
              found << point if found.empty? || far?(found.last, point)
            end
          end

          def far?(from, to)
            Math.hypot(to[0] - from[0], to[1] - from[1]) >= MIN_GAP
          end

          # Catmull-Rom segment from point `index` to `to`, as a cubic.
          def segment(route, index, to)
            from = route[index]
            before = route[[index - 1, 0].max]
            after = route[[index + 2, route.size - 1].min]
            "C #{write(control(from, to, before))} " \
              "#{write(control(to, from, after))} #{write(to)}"
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
