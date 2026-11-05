# frozen_string_literal: true

require_relative "../../../svg"
require_relative "archimate"
require_relative "cloud"
require_relative "data_shape"
require_relative "entity_shape"
require_relative "figures"
require_relative "../creole"
require_relative "metrics"
require_relative "tab"

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
            return DataShape.new(placed).elements if placed.node.kind == :data
            return entity(placed) if placed.node.kind == :entity

            @p = placed
            @out = []
            placed.node.container? ? container : figure
            @out
          end

          private

          def entity(placed)
            EntityShape.new(placed).elements
          end

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
            label(Figures.label(kind).merge(@p.node.sprite ? { dy: 10 } : {}))
            draw_sprite if @p.node.sprite
          end

          # The icon of an archimate element, centred at its top; the label
          # moves down to make room.
          def draw_sprite
            left = @p.x + (@p.width / 2) - 8.5
            add(Svg::Path, d: @p.node.sprite, fill: "#000000",
                           transform: "translate(#{left},#{@p.y + 12})")
          end

          def draw_rect(origin, extent, radius = nil)
            x, y = at(origin)
            width, height = size(extent)
            add(Svg::Rect, x: x, y: y, width: width, height: height,
                           rx: radius, ry: radius, fill: fill, **LINE)
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
              y = top + (index * Metrics::LINE_HEIGHT) + Metrics::ASCENT
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
            outline = Figures.container(@p.node.kind) || Figures::BOX
            outline.each { |type, *args| send(:"draw_#{type}", *args) }
            decorate
            lines.each_with_index { |line, index| header(line, index) }
          end

          def decorate
            draw_tab if tabbed?
            draw_icon if @p.node.kind == :component
          end

          def tabbed?
            Figures::TABBED.include?(@p.node.kind)
          end

          # A component container carries the glyph of a component too.
          def draw_icon
            Figures::COMPONENT.drop(1).each do |type, *args|
              send(:"draw_#{type}", *args)
            end
          end

          def draw_tab
            width = Metrics.text_width([lines.first.to_s]) * 1.05
            points = Tab.points(@p.x, @p.y, width, @p.node.kind)
            add(Svg::Polygon, points: points, fill: FILL, **LINE)
          end

          # A header clears the cap of a cylinder, the bumps of a cloud and
          # the slanted top of a node.
          HEADER_DROP = { database: 10, cloud: 12, node: 8 }.freeze
          HEADER_LEFT = { cloud: 24 }.freeze
          private_constant :HEADER_DROP, :HEADER_LEFT

          def header(line, index)
            return tab_text(line) if tabbed? && index.zero?

            weight = index.zero? ? "bold" : nil
            return centred_title(line, index, weight) if centred?

            text(@p.x + 12 + HEADER_LEFT.fetch(@p.node.kind, 0),
                 header_top(index), line, "start", weight)
          end

          # A component container names itself in the middle of its top.
          def centred? = @p.node.kind == :component

          def centred_title(line, index, weight)
            text(@p.x + (@p.width / 2), header_top(index), line, "middle",
                 weight)
          end

          def header_top(index)
            @p.y + 13 + Metrics::ASCENT + HEADER_DROP.fetch(@p.node.kind, 0) +
              (index * Metrics::LINE_HEIGHT)
          end

          def tab_text(line)
            text(@p.x + Tab::PAD, @p.y + 14, line, "start", "bold")
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
