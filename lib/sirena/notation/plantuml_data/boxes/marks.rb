# frozen_string_literal: true

require_relative "text"

module Sirena
  module Notation
    module PlantUMLData
      module Boxes
        # Builds the marks both layouts draw boxes, rules, text and arrows
        # with. PlantUML's palette: grey fill, black ink.
        module Marks
          extend self

          INK = "#181818"
          BLACK = "#000000"
          PAPER = "#F1F1F1"
          # How far a text's baseline lies below its vertical middle.
          BASELINE = 5.5

          def rect(left, top, width, height, **style)
            { kind: :rect, x: left, y: top, width: width, height: height,
              rx: 5, fill: PAPER, stroke: INK, stroke_width: 1.5 }.merge(style)
          end

          def line(from, to, stroke: BLACK, width: 1)
            { kind: :line, x1: from[0], y1: from[1], x2: to[0], y2: to[1],
              stroke: stroke, stroke_width: width }
          end

          # @param middle [Float] the y of the text's vertical middle
          # @param style [Hash] bold, italic, fill and anchor
          def text(content, left, middle, **style)
            { kind: :text, content: content, x: left, y: middle + BASELINE,
              bold: false, italic: false, fill: BLACK, anchor: nil }
              .merge(style)
          end

          def curve(from, to, dashed: false, stroke: BLACK)
            { kind: :path, d: bezier(from, to), dashed: dashed,
              stroke: stroke }
          end

          def polygon(points, fill: BLACK, stroke: fill)
            { kind: :polygon, points: points, fill: fill, stroke: stroke }
          end

          # The small notched arrow PlantUML ends a tree link with: 7.6 long,
          # 6.1 wide, notched 2.3 in from its base; filled, never outlined.
          def arrowhead(tip)
            x, y = tip
            polygon([[x - 7.6, y - 3.0], [x - 5.3, y], [x - 7.6, y + 3.0], tip],
                    fill: BLACK, stroke: "none")
          end

          def dot(centre)
            { kind: :circle, cx: centre[0], cy: centre[1], r: 3, fill: BLACK }
          end

          private

          def bezier(from, to)
            start, *rest = [from, *handles(from, to), to].map do |point|
              point.join(" ")
            end
            "M #{start} C #{rest.join(' ')}"
          end

          def handles(from, to)
            reach = [(to[0] - from[0]).abs / 2.0, 13.0].max
            [[from[0] + reach, from[1]], [to[0] - reach, to[1]]]
          end
        end
      end
    end
  end
end
