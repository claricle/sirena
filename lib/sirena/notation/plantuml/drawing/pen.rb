# frozen_string_literal: true

require_relative "../../../svg"
require_relative "../../../text_measurement"
require_relative "scene"

module Sirena
  module Notation
    module PlantUML
      module Drawing
        # Lays marks into `marks`, the array a layout owns, in PlantUML's
        # look: dark one-and-a-half pixel strokes on white.
        module Pen
          INK = "#181818"
          COMMAND_KEYS = { move: %i[x y], line: %i[x y],
                           curve: %i[cx cy x y],
                           bezier: %i[c1x c1y c2x c2y x y], close: [] }.freeze
          FONT_SIZE = 12

          def marks
            @marks ||= []
          end

          def rect(left, top, width, height, **style)
            put(Svg::Rect, { x: left, y: top, width: width, height: height,
                             fill: "none", stroke: INK, stroke_width: "1" },
                style)
          end

          def line(startx, starty, endx, endy, **style)
            put(Svg::Line, { x1: startx, y1: starty, x2: endx, y2: endy,
                             stroke: INK, stroke_width: "1" }, style)
          end

          # @param commands [Array<Hash, Array>] path commands, each a hash
          #   for {Svg::Path.build_path_data} or a tuple such as
          #   `[:line, x, y]`, `[:curve, cx, cy, x, y]` or
          #   `[:bezier, c1x, c1y, c2x, c2y, x, y]`
          def path(commands, **style)
            hashes = commands.map { |one| command_hash(one) }
            data = Svg::Path.build_path_data(hashes)
            put(Svg::Path, { d: data, fill: "none", stroke: INK,
                             stroke_width: "1" }, style)
          end

          def polygon(points, **style)
            put(Svg::Polygon, { points: Svg::Polygon.build_points(points),
                                fill: INK, stroke: INK, stroke_width: "1" },
                style)
          end

          def ellipse(center_x, center_y, radius_x, radius_y, **style)
            put(Svg::Ellipse, { cx: center_x, cy: center_y, rx: radius_x,
                                ry: radius_y, fill: "none", stroke: INK,
                                stroke_width: "1" }, style)
          end

          def circle(center_x, center_y, radius, **style)
            put(Svg::Circle, { cx: center_x, cy: center_y, r: radius,
                               fill: "none", stroke: INK, stroke_width: "1" },
                style)
          end

          # @param options [Hash] `size`, `anchor` (an SVG text-anchor),
          #   `bold` and `fill`
          def text(content, left, middle, **options)
            put(Svg::Text, { x: left, y: middle, content: content.to_s,
                             text_anchor: "start", font_family: "sans-serif",
                             font_size: FONT_SIZE.to_s, fill: INK,
                             dominant_baseline: "middle" },
                typeface(options))
          end

          def text_width(content, size: FONT_SIZE)
            TextMeasurement.measure(content.to_s, font_size: size)[:width]
          end

          def scene(width, height)
            Scene.new(width: width.ceil, height: height.ceil, marks: marks)
          end

          private

          def command_hash(command)
            return command unless command.is_a?(Array)

            type, *numbers = command
            COMMAND_KEYS.fetch(type).zip(numbers).to_h.merge(type: type)
          end

          def typeface(options)
            { font_size: options[:size]&.to_s, fill: options[:fill],
              text_anchor: options[:anchor],
              font_weight: ("bold" if options[:bold]) }.compact
          end

          def put(element, defaults, style)
            marks << Mark.new(element, defaults.merge(style))
          end
        end
      end
    end
  end
end
