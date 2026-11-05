# frozen_string_literal: true

require_relative "mark"
require_relative "metrics"

module Sirena
  module Notation
    module PlantUML
      module Activity
        # Collects {Mark}s in drawing order and the extent they reach.
        class Canvas
          INK = "#181818"

          # @return [Array<Mark>]
          attr_reader :marks
          # @return [Float] the leftmost x any mark reaches
          attr_reader :min_x
          # @return [Float] the rightmost x any mark reaches
          attr_reader :max_x
          # @return [Float] the lowest y any mark reaches
          attr_reader :max_y

          def initialize
            @marks = []
            @min_x = Float::INFINITY
            @max_x = 0.0
            @max_y = 0.0
          end

          def add(kind, **attrs)
            @marks << Mark.new(kind, **attrs)
          end

          def see(left, right, bottom)
            @min_x = [@min_x, left].min
            @max_x = [@max_x, right].max
            @max_y = [@max_y, bottom].max
          end

          # `role` names the `<style>` selector that restyles the mark:
          # :partition, :diamond, :note or :arrow; nil is a plain action.
          #
          # @param box [Box]
          def rect(box, fill:, radius: nil, role: nil)
            see(box.left, box.right, box.bottom)
            add(:rect, x: box.left, y: box.top, width: box.width,
                       height: box.height, fill: fill, stroke: INK, rx: radius,
                       role: role)
          end

          # @param box [Box]
          def polygon(points, fill:, stroke: INK, role: nil)
            points.each { |x_pos, y_pos| see(x_pos, x_pos, y_pos) }
            add(:polygon, points: points, fill: fill, stroke: stroke,
                          role: role)
          end

          def circle(box, radius, fill:, stroke: "#222222", role: nil)
            see(box.left, box.right, box.bottom)
            add(:circle, cx: box.cx, cy: box.cy, r: radius, fill: fill,
                         stroke: stroke, role: role)
          end

          def path(points, stroke:, width: 1.0, dash: nil)
            points.each { |x_pos, y_pos| see(x_pos, x_pos, y_pos) }
            add(:path, points: points, stroke: stroke, width: width,
                       dash: dash)
          end

          # One text mark per line, the first baseline at `point`.
          def lines(rows, point, anchor: "start", role: nil, **face)
            face = { size: Metrics::FONT_SIZE, **face }
            rows.each_with_index do |content, index|
              y_pos = point.last + (index * Metrics::LINE_HEIGHT)
              text([point.first, y_pos], content, anchor,
                   face.merge(role: role))
            end
          end

          private

          def text(point, content, anchor, face)
            width = Metrics.text_width([content])
            left = point.first - (width * { "start" => 0, "middle" => 0.5,
                                            "end" => 1 }.fetch(anchor))
            see(left, left + width, point.last + 3)
            add(:text, x: point.first, y: point.last, content: content,
                       anchor: anchor, **face)
          end
        end
      end
    end
  end
end
