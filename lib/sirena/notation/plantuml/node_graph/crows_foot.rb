# frozen_string_literal: true

require_relative "../../../svg"

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # The cardinality ends of an entity link: `}|` one or many, `}o`
        # zero or many, `||` exactly one, `|o` zero or one, and the
        # mirrored forms on the right.
        module CrowsFoot
          GLYPHS = { "}|" => %i[many one], "}o" => %i[many zero],
                     "||" => %i[one one], "|o" => %i[one zero] }.freeze
          REACH = 10.0
          SPREAD = 6.0
          BAR = 5.0
          RING = 4.0

          module_function

          # @param left [String] the glyph left of the line, e.g. `}|`
          # @param right [String] the glyph right of it, e.g. `||`
          # @return [Array<Array<Symbol>>] each end's markers, box outward
          def parse(left, right)
            [GLYPHS.fetch(left), GLYPHS.fetch(right.reverse.tr("{", "}"))]
          end

          # @param markers [Array<Symbol>] one end's markers, box outward
          # @param tip [Array(Float, Float)] where the line meets the box
          # @param vec [Array(Float, Float)] unit vector along the line,
          #   away from the box
          # @return [Array<Svg::Element>]
          def draw(markers, tip, vec, color)
            offset = 0.0
            markers.flat_map do |marker|
              shapes = send(marker, tip, vec, offset, color)
              offset += marker == :many ? REACH + 4 : BAR + 1
              shapes
            end
          end

          def many(tip, vec, offset, color)
            apex = step(tip, vec, offset + REACH)
            side = [-vec[1], vec[0]]
            [-SPREAD, SPREAD].map do |spread|
              stroke(apex, step(step(tip, vec, offset), side, spread), color)
            end
          end

          def one(tip, vec, offset, color)
            mid = step(tip, vec, offset + BAR)
            side = [-vec[1], vec[0]]
            [stroke(step(mid, side, SPREAD), step(mid, side, -SPREAD), color)]
          end

          def zero(tip, vec, offset, color)
            cx, cy = step(tip, vec, offset + RING)
            [Svg::Circle.new.tap do |ring|
              ring.cx = cx
              ring.cy = cy
              ring.r = RING
              ring.fill = "#FFFFFF"
              ring.stroke = color
              ring.stroke_width = "1"
            end]
          end

          def stroke(from, to, color)
            Svg::Line.new.tap do |line|
              line.x1, line.y1 = from
              line.x2, line.y2 = to
              line.stroke = color
              line.stroke_width = "1"
            end
          end

          def step(from, vec, distance)
            [from[0] + (vec[0] * distance), from[1] + (vec[1] * distance)]
          end
        end
      end
    end
  end
end
