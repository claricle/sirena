# frozen_string_literal: true

require_relative "../../../svg"
require_relative "cloud"
require_relative "figures"
require_relative "../creole"
require_relative "metrics"

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # Draws one placed node as SVG elements.
        class Shapes
          STROKE = "#181818"
          FILL = "#F1F1F1"
          FONT = "sans-serif"
          HEX = /\A[0-9A-Fa-f]{3,8}\z/
          LINE = { stroke: STROKE, stroke_width: "1" }.freeze

          # @param placed [Placed]
          # @return [Array<Svg::Element>]
          def draw(placed)
            @p = placed
            @out = []
            placed.node.container? ? container : figure
            @out
          end

          private

          def add(type, **attrs)
            @out << type.new.tap do |node|
              attrs.each { |key, value| node.public_send(:"#{key}=", value) }
            end
          end

          def fill
            color = @p.node.color
            return container_fill unless color

            color.match?(HEX) ? "##{color}" : color
          end

          def at(spec)
            [@p.x + (spec[0] * @p.width) + spec[2],
             @p.y + (spec[1] * @p.height) + spec[3]]
          end

          def size(spec)
            [(spec[0] * @p.width) + spec[2], (spec[1] * @p.height) + spec[3]]
          end

          def figure
            kind = @p.node.kind
            Figures.for(kind).each do |type, *args|
              send(:"draw_#{type}", *args)
            end
            label(Figures.label(kind))
          end

          def draw_rect(origin, extent)
            x, y = at(origin)
            width, height = size(extent)
            add(Svg::Rect, x: x, y: y, width: width, height: height,
                           fill: fill, **LINE)
          end

          def draw_circle(center, radius)
            x, y = at(center)
            add(Svg::Circle, cx: x, cy: y, r: radius, fill: fill, **LINE)
          end

          def draw_line(from, to)
            x1, y1 = at(from)
            x2, y2 = at(to)
            add(Svg::Line, x1: x1, y1: y1, x2: x2, y2: y2, **LINE)
          end

          def draw_ellipse
            add(Svg::Ellipse, cx: @p.x + (@p.width / 2),
                              cy: @p.y + (@p.height / 2), rx: @p.width / 2,
                              ry: @p.height / 2, fill: fill, **LINE)
          end

          def draw_polygon(points, color = fill)
            add(Svg::Polygon, points: points.map { |pt| at(pt).join(",") }
              .join(" "),
                              fill: color, **LINE)
          end

          def draw_path(commands, color = fill)
            add(Svg::Path, d: commands.map { |cmd| command(*cmd) }.join(" "),
                           fill: color, **LINE)
          end

          def draw_cloud
            add(Svg::Path, d: Cloud.new(@p).to_d, fill: fill, **LINE)
          end

          def command(verb, *args)
            case verb
            when :Z then "Z"
            when :A then arc(*args)
            else "#{verb}#{at(args.first).join(',')}"
            end
          end

          def arc(radii, sweep, target)
            "A#{size(radii).join(',')} 0 0 #{sweep} #{at(target).join(',')}"
          end

          def lines
            Metrics.text_lines(@p.node)
          end

          def label(options)
            top = options[:top] ? @p.y + options[:top] : middle(options)
            lines.each_with_index do |line, index|
              y = top + (index * Metrics::LINE_HEIGHT) + 11
              anchor, x_pos = label_anchor(options)
              text(x_pos, y, line, anchor)
            end
          end

          def label_anchor(options)
            return ["start", @p.x + options[:left]] if options[:left]

            width = @p.width - options.fetch(:shrink, 0)
            ["middle", @p.x + options.fetch(:shift, 0) + (width / 2)]
          end

          def middle(options)
            @p.y + ((@p.height - Metrics.text_height(lines)) / 2) +
              options.fetch(:dy, 0)
          end

          # A container is open: only a colour of its own fills it, so what it
          # holds shows through.
          def container_fill
            @p.node.container? ? "none" : FILL
          end

          def container
            outline = Figures.container(@p.node.kind)
            if outline
              outline.each { |type, *args| send(:"draw_#{type}", *args) }
            else
              draw_rect(Figures::ORIGIN, Figures::FULL)
            end
            lines.each_with_index { |line, index| header(line, index) }
          end

          # A header clears the cap of a cylinder, the bumps of a cloud and
          # the slanted top of a node.
          HEADER_DROP = { database: 10, cloud: 12, node: 8, folder: 14,
                          frame: 14 }.freeze
          HEADER_LEFT = { cloud: 24 }.freeze
          private_constant :HEADER_DROP, :HEADER_LEFT

          def header(line, index)
            kind = @p.node.kind
            y_pos = @p.y + 18 + HEADER_DROP.fetch(kind, 0) +
              (index * Metrics::LINE_HEIGHT)
            text(@p.x + 12 + HEADER_LEFT.fetch(kind, 0), y_pos, line, "start",
                 index.zero? ? "bold" : nil)
          end

          def text(x_pos, y_pos, content, anchor, weight = nil)
            add(Svg::Text, x: x_pos, y: y_pos, content: content,
                           text_anchor: anchor, font_family: FONT,
                           font_size: Metrics::FONT_SIZE.to_s,
                           font_weight: weight, fill: "#000000")
            Creole.assign(@out.last, content)
          end
        end
      end
    end
  end
end
