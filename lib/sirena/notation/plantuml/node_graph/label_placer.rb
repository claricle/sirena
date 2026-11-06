# frozen_string_literal: true

require_relative "../../../text_measurement"
require_relative "../label_clearance"

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # Decides where each edge label is drawn so that no two labels print
        # over one another. A label starts on the middle of its edge; when
        # that spot is taken by an earlier label it slides along the edge and
        # then steps up and down in whole lines until a free spot is found.
        # A label never covers its own edge: it sits above a flat leg of the
        # edge and to the right of a steep one.
        class LabelPlacer
          FONT_SIZE = 12
          LINE_STEP = 14.0
          RISE = 4.0
          MARGIN = 2.0
          FRACTIONS = [0.5, 0.65, 0.35, 0.8, 0.2].freeze
          MAX_STEPS = 24
          BESIDE_GAP = 4.0
          private_constant :FONT_SIZE, :LINE_STEP, :RISE, :MARGIN, :FRACTIONS,
                           :MAX_STEPS, :BESIDE_GAP

          # `width` is the width of the label's text; {#right} and
          # {#bottom} are how far the label reaches.
          Placement = Struct.new(:route, :x, :y, :width) do
            def right
              x + (width / 2) + MARGIN
            end

            def bottom
              y + (FONT_SIZE / 4.0)
            end
          end

          # @param routes [Array<Route>] each answering `points` and `edge`
          # @param boxes [Array<Placed>] the nodes, which no label covers
          # @return [Array<Placement>] one per route that carries a label
          def call(routes, boxes = [])
            taken = boxes.map { |box| area(box) }
            routes.filter_map do |route|
              text = route.edge.label.to_s
              next if text.empty?

              place(route, width_of(text), taken)
            end
          end

          private

          def place(route, width, taken)
            candidates(route, width).each do |x_pos, y_pos|
              box = bounds(x_pos, y_pos, width)
              next if taken.any? { |other| overlap?(box, other) }
              next if covers?(box, route)

              taken << box
              return Placement.new(route, x_pos, y_pos, width)
            end
            fallback(route, width, taken)
          end

          # Every candidate, nearest the edge first: beside its line, along
          # the edge, then one line off it, then two, alternately above and
          # below.
          def candidates(route, width)
            [*beside(route.label_at, width), *aside(route, width),
             *clear_of(route, width), *along_edge(route.points)]
          end

          # Right of a sloping edge, in the corner the edge leaves free:
          # above where it runs down to the right, below where it runs down
          # to the left. At the label's own point first, then along the edge.
          def aside(route, width)
            first, last = route.points.values_at(0, -1)
            slope = (last[0] - first[0]) * (last[1] - first[1])
            return [] if slope.zero?

            anchors(route).map { |anchor| corner(anchor, route, width, slope) }
          end

          def corner(anchor, route, width, slope)
            half = stroke(route.edge)
            [anchor[0] + half + BESIDE_GAP + (width / 2),
             corner_y(anchor[1], half, slope)]
          end

          def anchors(route)
            [route.label_at,
             *FRACTIONS.map { |share| along(route.points, share) }].compact
          end

          def corner_y(y_pos, half, slope)
            return y_pos - half - BESIDE_GAP if slope.positive?

            y_pos + half + 1.0 + FONT_SIZE
          end

          # The spots beside the edge itself, one per place along it.
          def clear_of(route, width)
            FRACTIONS.map do |fraction|
              from, to = leg(route.points, fraction)
              spot = along(route.points, fraction)
              half = stroke(route.edge)
              place = steep?(from, to) ? :right_of : :above
              send(place, from, to, spot, width, half)
            end
          end

          def steep?(from, to)
            (to[1] - from[1]).abs > (to[0] - from[0]).abs
          end

          def stroke(edge)
            edge.width.to_f / 2
          end

          def above(from, to, spot, width, half)
            reach = (width / 2) + MARGIN
            top = LabelClearance.top_between(from, to, spot[0] - reach,
                                             spot[0] + reach)
            [spot[0], top - half - 1.0 - (FONT_SIZE / 4.0)]
          end

          def right_of(from, to, spot, width, half)
            edge = LabelClearance.right_between(from, to,
                                                spot[1] - FONT_SIZE,
                                                spot[1] + (FONT_SIZE / 4.0))
            [edge + half + BESIDE_GAP + (width / 2),
             spot[1] + (FONT_SIZE / 3.0)]
          end

          # Whether the box lies across any part of the route's own line.
          def covers?(box, route)
            pad = stroke(route.edge)
            padded = box.zip([-pad, -pad, pad, pad]).map(&:sum)
            route.points.each_cons(2).any? { |a, b| crosses?(padded, a, b) }
          end

          # Liang-Barsky: the part of the segment from `from` to `to` inside
          # the box, if any, as a range of its length narrowed axis by axis.
          def crosses?(box, from, to)
            span = [0.0, 1.0]
            [0, 1].all? do |axis|
              inside?(span, from[axis], to[axis], box[axis], box[axis + 2])
            end
          end

          def inside?(span, start, finish, low, high)
            delta = finish - start
            return start.between?(low, high) if delta.zero?

            overlaps?(span, [(low - start) / delta, (high - start) / delta])
          end

          def overlaps?(span, bounds)
            first, last = bounds.minmax
            span[0] = [span[0], first].max
            span[1] = [span[1], last].min
            span[0] <= span[1]
          end

          # The JAR prints a label on the right of the point its line
          # passes through.
          def beside(anchor, width)
            return [] unless anchor

            x_pos, y_pos = anchor
            [[x_pos + (width / 2) + BESIDE_GAP, y_pos + (FONT_SIZE / 3.0)]]
          end

          def along_edge(points)
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
            Placement.new(route, x_pos, y_pos - RISE, width)
          end

          def area(box)
            [box.x, box.y, box.x + box.width, box.y + box.height]
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
            Drawing::Face.width(text, size: FONT_SIZE).to_f
          end

          # The point `fraction` of the way along the polyline.
          def along(points, fraction)
            start, finish, share = locate(points, fraction)
            lerp(start, finish, share)
          end

          # The segment of the polyline `fraction` of the way along it.
          def leg(points, fraction)
            locate(points, fraction).first(2)
          end

          # The segment holding that point and how far along it the point is.
          def locate(points, fraction)
            segments = measured_segments(points)
            remaining = segments.sum(&:last) * fraction
            segments.each_with_index do |(start, finish, length), index|
              last = index == segments.size - 1
              if remaining <= length || last
                return [start, finish, ratio(remaining, length)]
              end

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
