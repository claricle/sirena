# frozen_string_literal: true

require_relative "../../../renderer/base"
require_relative "../../../svg"
require_relative "../style"
require_relative "layout"
require_relative "../creole"

module Sirena
  module Notation
    module PlantUML
      module Activity
        # Draws a {Scene}: each {Mark} becomes one SVG element, in order.
        class Renderer < Sirena::Renderer::Base
          FONT_FAMILY = "sans-serif"
          PAPER = "#F1F1F1"
          INK = "#181818"
          TERMINAL = "#222222"
          # The stroke width of the shapes PlantUML draws heavier than a box.
          DRAWN_WIDTHS = { warning: "3", bar: "1" }.freeze
          private_constant :FONT_FAMILY, :PAPER, :INK, :TERMINAL,
                           :DRAWN_WIDTHS

          # @param style [Style::Sheet] what the source sets; the drawn
          #   defaults stand for anything it leaves out
          def initialize(theme: nil, style: Style::Sheet.new)
            super(theme: theme)
            @style = style
          end

          # @param scene [Scene]
          # @return [Svg::Document]
          def render(scene)
            Svg::Document.new(width: scene.width, height: scene.height,
                              view_box: "0 0 #{scene.width} #{scene.height}")
              .tap do |document|
              scene.marks.each { |mark| document << draw(mark) }
            end
          end

          private

          def draw(mark)
            send(:"draw_#{mark.kind}", mark.attrs)
          end

          def element(type, **attributes)
            type.new.tap do |node|
              attributes.each do |name, value|
                node.public_send(:"#{name}=", value) unless value.nil?
              end
            end
          end

          def draw_rect(attrs)
            element(Svg::Rect, x: attrs[:x], y: attrs[:y], width: attrs[:width],
                               height: attrs[:height],
                               rx: corner(attrs),
                               fill: fill(attrs),
                               stroke: ink(attrs),
                               stroke_width: frame_width(attrs),
                               stroke_dasharray: look(:line_style))
          end

          def draw_circle(attrs)
            element(Svg::Circle, cx: attrs[:cx], cy: attrs[:cy], r: attrs[:r],
                                 fill: disc(attrs),
                                 stroke: line_ink(attrs[:stroke]),
                                 stroke_width: attrs[:width].to_s)
          end

          def draw_polygon(attrs)
            head = attrs[:fill] == INK
            element(Svg::Polygon, points: format_points(attrs[:points]),
                                  fill: head ? arrow : fill(attrs),
                                  stroke: head ? arrow : ink(attrs),
                                  stroke_width: head ? "1" : hairline(attrs))
          end

          def draw_path(attrs)
            element(Svg::Path, d: path_data(attrs[:points]), fill: "none",
                               stroke: line_ink(attrs[:stroke]),
                               stroke_width: attrs[:width].to_s,
                               stroke_dasharray: attrs[:dash])
          end

          def draw_text(attrs)
            element(Svg::Text, x: attrs[:x], y: attrs[:y],
                               content: attrs[:content],
                               text_anchor: attrs[:anchor],
                               font_family: attrs[:family] ||
                                            face(attrs, :font_name) ||
                                            FONT_FAMILY,
                               font_size: attrs[:size].to_s,
                               font_weight: attrs[:weight],
                               fill: face(attrs, :font_colour) || "#000000")
              .tap { |text| Creole.assign(text, attrs[:content]) }
          end

          def look(property)
            @style.explicit(:activity, property)
          end

          # The rule of the mark's own `<style>` selector (diamond, note,
          # partition, arrow), which wins over the activityDiagram block.
          def own(attrs, property)
            role = attrs[:role]
            @style.explicit(role, property) if role
          end

          def face(attrs, property)
            own(attrs, property) || look(property)
          end

          # A partition has no paint of its own, so only its own rule
          # fills it; a diamond falls back to the action paint.
          def fill(attrs)
            own(attrs, :background) ||
              (attrs[:role] == :partition ? attrs[:fill] : paper(attrs[:fill]))
          end

          # PlantUML draws a partition's corners at half the RoundCorner.
          def corner(attrs)
            return look(:round_corner) || attrs[:rx] unless
              attrs[:role] == :partition

            round = own(attrs, :round_corner)
            round ? round / 2 : attrs[:rx]
          end

          def arrow
            @style.explicit(:arrow, :border) ||
              @style.from_style(:activity, :border) || INK
          end

          # The start disc takes the activityDiagram background.
          def disc(attrs)
            return attrs[:fill] unless attrs[:role] == :start

            @style.from_style(:activity, :background) || attrs[:fill]
          end

          def hairline(attrs)
            (own(attrs, :line_thickness) || look(:line_thickness) || 0.5).to_s
          end

          def frame_width(attrs)
            unless attrs[:role] == :partition
              return DRAWN_WIDTHS.fetch(attrs[:role]) { hairline(attrs) }
            end

            (own(attrs, :line_thickness) || 1.5).to_s
          end

          # The default box paint stands for what the source sets.
          def paper(fill)
            fill == PAPER ? look(:background) || fill : fill
          end

          def ink(attrs)
            stroke = attrs[:stroke]
            return stroke unless stroke == INK

            own(attrs, :border) || look(:border) || stroke
          end

          def line_ink(stroke)
            case stroke
            when INK then arrow
            when TERMINAL then @style.from_style(:activity, :border) || stroke
            else stroke
            end
          end

          def format_points(points)
            points.map { |x, y| "#{number(x)},#{number(y)}" }.join(" ")
          end

          def path_data(points)
            points.each_with_index.map do |(x, y), index|
              "#{index.zero? ? 'M' : 'L'}#{number(x)},#{number(y)}"
            end.join(" ")
          end

          def number(value)
            value.round(2).to_s.delete_suffix(".0")
          end
        end
      end
    end
  end
end
