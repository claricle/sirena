# frozen_string_literal: true

require_relative "../../../text_measurement"
require_relative "../label_clearance"
require_relative "../segment_box"

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # Decides where each edge label is drawn so that no two labels print
        # over one another. A label starts on the middle of its edge; when
        # that spot is taken by an earlier label it slides along the edge and
        # then steps up and down in whole lines until a free spot is found.
        # A label never covers its own edge, nor any other: it sits above a
        # flat leg of the edge and to the right of a steep one, and moves on
        # when a neighbouring edge runs through the spot.
        class LabelPlacer
          FONT_SIZE = 12
          LINE_STEP = 14.0
          RISE = 4.0
          MARGIN = 2.0
          FRACTIONS = [0.5, 0.65, 0.35, 0.8, 0.2].freeze
          SPREAD = (1..19).map { |step| step * 0.05 }
            .sort_by { |share| (share - 0.5).abs }.freeze
          MAX_STEPS = 24
          BESIDE_GAP = 4.0
          NEIGHBOUR_GAP = 6.0
          REACH = 20.0
          private_constant :FONT_SIZE, :LINE_STEP, :RISE, :MARGIN, :FRACTIONS,
                           :SPREAD, :MAX_STEPS, :BESIDE_GAP,
                           :NEIGHBOUR_GAP, :REACH

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

              place(route, width_of(text), taken,
                    routes.reject { |other| other.equal?(route) })
            end
          end

          private

          def place(route, width, taken, others)
            spot = spot_for(route, width, taken, others)
            return fallback(route, width, taken) unless spot

            taken << bounds(*spot, width)
            Placement.new(route, spot[0], spot[1], width)
          end

          # The first candidate that no edge but its own runs through; when
          # every candidate near the edge has some other edge across it, the
          # one with the fewest.
          def spot_for(route, width, taken, others)
            fewest = nil
            candidates(route, width).each do |spot|
              count = clashes(spot, route, width, [taken, others])
              next unless count
              return spot if count.zero?

              fewest = [spot, count] if fewer?(fewest, count)
            end
            fewest&.first
          end

          def fewer?(fewest, count)
            fewest.nil? || count < fewest[1]
          end

          # How many other edges lie across the candidate, or nil when it
          # cannot be used: on a taken spot, across its own edge or further
          # from it than a label is read with.
          def clashes(spot, route, width, around)
            taken, others = around
            box = bounds(*spot, width)
            return if taken.any? { |other| overlap?(box, other) }
            return if covers?(box, route) || !reaches?(box, route)

            others.count { |other| covers?(box, other, NEIGHBOUR_GAP) }
          end

          # Every candidate, nearest the edge first: beside its line, along
          # the edge, then one line off it, then two, alternately above and
          # below.
          def candidates(route, width)
            [*beside(route.label_at, width), *aside(route, width),
             *clear_of(route, width), *spread(route, width),
             *along_edge(route.points)]
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

          # Both sides of the edge at finer places along it, for when its
          # neighbours leave no room at the usual ones.
          def spread(route, width)
            SPREAD.flat_map do |fraction|
              from, to = leg(route.points, fraction)
              places = steep?(from, to) ? %i[right_of left_of] : %i[above below]
              places.map do |place|
                send(place, from, to, along(route.points, fraction), width,
                     stroke(route.edge))
              end
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

          def below(from, to, spot, width, half)
            reach = (width / 2) + MARGIN
            bottom = LabelClearance.bottom_between(from, to, spot[0] - reach,
                                                   spot[0] + reach)
            [spot[0], bottom + half + 1.0 + FONT_SIZE]
          end

          def left_of(from, to, spot, width, half)
            edge = LabelClearance.left_between(from, to, spot[1] - FONT_SIZE,
                                               spot[1] + (FONT_SIZE / 4.0))
            [edge - half - BESIDE_GAP - (width / 2),
             spot[1] + (FONT_SIZE / 3.0)]
          end

          def right_of(from, to, spot, width, half)
            edge = LabelClearance.right_between(from, to,
                                                spot[1] - FONT_SIZE,
                                                spot[1] + (FONT_SIZE / 4.0))
            [edge + half + BESIDE_GAP + (width / 2),
             spot[1] + (FONT_SIZE / 3.0)]
          end

          # Whether the box lies within `REACH` of the route's line, as the
          # crow flies from the line to the nearest point of the box.
          def reaches?(box, route)
            reach = stroke(route.edge) + REACH
            route.points.each_cons(2).any? do |from, to|
              SegmentBox.within?(box, from, to, reach)
            end
          end

          # Whether the box lies across any part of the route's line, or within
          # `gap` of it. A neighbour's line is drawn as a curve a little off
          # the points it passes through, so it takes a gap too.
          def covers?(box, route, gap = 0.0)
            pad = stroke(route.edge) + gap
            padded = box.zip([-pad, -pad, pad, pad]).map(&:sum)
            route.points.each_cons(2).any? do |from, to|
              SegmentBox.crosses?(padded, from, to)
            end
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
