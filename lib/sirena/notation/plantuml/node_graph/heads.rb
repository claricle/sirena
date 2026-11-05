# frozen_string_literal: true

require_relative "../../../svg"
require_relative "crows_foot"

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # The ends of a link: arrowheads and the circle of a socket.
        module Heads
          LENGTH = 9.0
          HALF = 4.0
          SOCKET = 5.0

          module_function

          # @return [Array<Svg::Element>] what the edge draws at its ends
          # @param inner [Array] the points next to `from` and next to `to`
          #   on the line, which give each end its direction; the opposite
          #   end of a straight line
          def for(edge, from, to, color, inner = [to, from])
            return crows(edge.ends, [from, to], inner, color) if edge.ends

            case edge.head
            when :target then [arrow(to, inner[1], color)]
            when :source then [arrow(from, inner[0], color)]
            when :both then [arrow(to, inner[1], color),
                             arrow(from, inner[0], color)]
            when :socket then [socket(to, inner[1])]
            else []
            end
          end

          def crows(ends, (from, to), inner, color)
            CrowsFoot.draw(ends[0], from, unit(from, inner[0]), color) +
              CrowsFoot.draw(ends[1], to, unit(to, inner[1]), color)
          end

          # @param tip [Array(Float, Float)] where the head points
          # @param tail [Array(Float, Float)] the other end of the line
          def arrow(tip, tail, color)
            vec = unit(tip, tail)
            base = along(tip, vec, LENGTH)
            wings = [along(base, [-vec[1], vec[0]], HALF),
                     along(base, [vec[1], -vec[0]], HALF)]
            polygon([tip, *wings], color)
          end

          def polygon(corners, color)
            Svg::Polygon.new.tap do |poly|
              poly.points = corners.map { |pt| rounded(pt) }.join(" ")
              poly.fill = color
              poly.stroke = color
              poly.stroke_width = "1"
            end
          end

          def rounded(point)
            point.map { |value| value.round(2) }.join(",")
          end

          def socket(tip, tail)
            cx, cy = along(tip, unit(tip, tail), SOCKET)
            Svg::Circle.new.tap do |circle|
              circle.cx = cx
              circle.cy = cy
              circle.r = SOCKET
              circle.fill = "#FFFFFF"
              circle.stroke = "#181818"
              circle.stroke_width = "1"
            end
          end

          def along(from, vec, distance)
            [from[0] + (vec[0] * distance), from[1] + (vec[1] * distance)]
          end

          # @return [Array(Float, Float)] the unit vector from `from` to `to`
          def unit(from, to)
            delta = [to[0] - from[0], to[1] - from[1]]
            length = Math.hypot(*delta)
            length.zero? ? [0.0, 1.0] : delta.map { |v| v / length }
          end
        end
      end
    end
  end
end
