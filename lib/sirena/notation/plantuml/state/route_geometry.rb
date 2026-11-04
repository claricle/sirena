# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module State
        # The plane geometry {Routes} draws with.
        module RouteGeometry
          SPREAD = 16.0
          LOOP = 28.0
          LABEL_GAP = 6.0

          # A state's absolute box and the layout hash it came from.
          Box = Struct.new(:x, :y, :w, :h, :node)
          # A transition's place among those joining the same two states.
          Slot = Struct.new(:index, :total, :offset) do
            # @return [Float] how far the slot sits from the group's middle
            def lane
              index - ((total - 1) / 2.0)
            end
          end

          private

          def centre(box)
            [box.x + (box.w / 2.0), box.y + (box.h / 2.0)]
          end

          def loop_points(box)
            right = box.x + box.w
            top = box.y + (box.h * 0.35)
            bottom = box.y + (box.h * 0.65)
            [[right, top], [right + LOOP, top], [right + LOOP, bottom],
             [right, bottom]]
          end

          def shifted(section, origin, shift)
            dx = origin.x + shift.first
            dy = origin.y + shift.last
            [section[:startPoint], *section[:bendPoints], section[:endPoint]]
              .map { |point| [point[:x] + dx, point[:y] + dy] }
          end

          # Where the line from a box's centre toward a point leaves the box.
          def border(box, toward)
            cx, cy = centre(box)
            dx = toward.first - cx
            dy = toward.last - cy
            return [cx, cy] if dx.zero? && dy.zero?

            scale = fit(box, dx, dy)
            [cx + (dx * scale), cy + (dy * scale)]
          end

          def fit(box, run, rise)
            return (box.w / 2.0) / Math.hypot(run, rise) if circle?(box)

            [(box.w / 2.0) / run.abs, (box.h / 2.0) / rise.abs].min
          end

          def circle?(box)
            %w[start end].include?(box.node.dig(:metadata, :shape_type))
          end

          def sideways(points, from, to, offset)
            run = to.first - from.first
            rise = to.last - from.last
            scale = offset / Math.hypot(run, rise)
            points.map { |x, y| [x - (rise * scale), y + (run * scale)] }
          end

          def section(points)
            {
              startPoint: point_hash(points.first),
              endPoint: point_hash(points.last),
              bendPoints: points[1...-1].map { |point| point_hash(point) },
            }
          end

          def point_hash(point)
            { x: point.first, y: point.last }
          end

          # Beside the longest stretch of the route; parallel labels are
          # stacked so none is written over another.
          def label_point(points, label, slot)
            return unless label

            from, to = longest_stretch(points)
            middle = midpoint(from, to)
            return beside(label, slot, middle) if steep?(from, to)

            { x: middle.first,
              y: middle.last - LABEL_GAP - (label[:height] / 2.0) }
          end

          def midpoint(from, to)
            [(from.first + to.first) / 2.0, (from.last + to.last) / 2.0]
          end

          def steep?(from, to)
            (to.first - from.first).abs < (to.last - from.last).abs
          end

          def longest_stretch(points)
            points.each_cons(2).max_by do |from, to|
              Math.hypot(to.first - from.first, to.last - from.last)
            end || [points.first, points.first]
          end

          # Right of the group's rightmost line, one row per transition.
          def beside(label, slot, middle)
            { x: rightmost(slot, middle.first) + (label[:width] / 2.0) +
              LABEL_GAP,
              y: middle.last + (slot.lane * (label[:height] + 4)) }
          end

          def rightmost(slot, line_x)
            line_x - slot.offset + (SPREAD * (slot.total - 1) / 2.0)
          end
        end
      end
    end
  end
end
