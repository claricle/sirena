# frozen_string_literal: true

require_relative "../../../text_measurement"

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # Decides where each edge label is drawn so that no two labels print
        # over one another. A label starts on the middle of its edge; when
        # that spot is taken by an earlier label it slides along the edge and
        # then steps up and down in whole lines until a free spot is found.
        class LabelPlacer
          FONT_SIZE = 12
          LINE_STEP = 14.0
          RISE = 4.0
          MARGIN = 2.0
          FRACTIONS = [0.5, 0.65, 0.35, 0.8, 0.2].freeze
          MAX_STEPS = 24
          private_constant :FONT_SIZE, :LINE_STEP, :RISE, :MARGIN, :FRACTIONS,
                           :MAX_STEPS

          Placement = Struct.new(:route, :x, :y)

          # @param routes [Array<Route>] each answering `points` and `edge`
          # @return [Array<Placement>] one per route that carries a label
          def call(routes)
            taken = []
            routes.filter_map do |route|
              text = route.edge.label.to_s
              next if text.empty?

              place(route, width_of(text), taken)
            end
          end

          private

          def place(route, width, taken)
            candidates(route.points).each do |x_pos, y_pos|
              box = bounds(x_pos, y_pos, width)
              next if taken.any? { |other| overlap?(box, other) }

              taken << box
              return Placement.new(route, x_pos, y_pos)
            end
            fallback(route, width, taken)
          end

          # Every candidate, nearest the edge first: along the edge, then one
          # line off it, then two, alternately above and below.
          def candidates(points)
            offsets.flat_map do |shift|
              FRACTIONS.map do |fraction|
                x_pos, y_pos = along(points, fraction)
                [x_pos, y_pos - RISE + shift]
              end
            end
          end

          def offsets
            [0.0, *(1..MAX_STEPS).flat_map do |step|
              [-step * LINE_STEP, step * LINE_STEP]
            end]
          end

          def fallback(route, width, taken)
            x_pos, y_pos = along(route.points, FRACTIONS.first)
            taken << bounds(x_pos, y_pos - RISE, width)
            Placement.new(route, x_pos, y_pos - RISE)
          end

          def bounds(x_pos, y_pos, width)
            [x_pos - (width / 2) - MARGIN, y_pos - FONT_SIZE,
             x_pos + (width / 2) + MARGIN, y_pos + (FONT_SIZE / 4.0)]
          end

          def overlap?(first, second)
            first[0] < second[2] && second[0] < first[2] &&
              first[1] < second[3] && second[1] < first[3]
          end

          def width_of(text)
            TextMeasurement.measure(text, font_size: FONT_SIZE)[:width].to_f
          end

          # The point `fraction` of the way along the polyline.
          def along(points, fraction)
            segments = measured_segments(points)
            remaining = segments.sum(&:last) * fraction
            segments.each_with_index do |(start, finish, length), index|
              last = index == segments.size - 1
              return lerp(start, finish, ratio(remaining, length)) if
                remaining <= length || last

              remaining -= length
            end
          end

          def measured_segments(points)
            points.each_cons(2).map do |a, b|
              [a, b, Math.hypot(b[0] - a[0], b[1] - a[1])]
            end
          end

          def ratio(part, length)
            length.zero? ? 0 : part / length
          end

          def lerp(start, finish, ratio)
            [start[0] + ((finish[0] - start[0]) * ratio),
             start[1] + ((finish[1] - start[1]) * ratio)]
          end
        end
      end
    end
  end
end
