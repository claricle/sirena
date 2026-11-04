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
          private_constant :FONT_FAMILY, :PAPER, :INK

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
                               rx: look(:round_corner) || attrs[:rx],
                               fill: paper(attrs[:fill]),
                               stroke: ink(attrs),
                               stroke_width: thickness,
                               stroke_dasharray: look(:line_style))
          end

          def draw_circle(attrs)
            element(Svg::Circle, cx: attrs[:cx], cy: attrs[:cy], r: attrs[:r],
                                 fill: attrs[:fill], stroke: attrs[:stroke],
                                 stroke_width: "1")
          end

          def draw_polygon(attrs)
            arrowhead = attrs[:fill] == INK
            element(Svg::Polygon, points: format_points(attrs[:points]),
                                  fill: arrowhead ? arrow : paper(attrs[:fill]),
                                  stroke: arrowhead ? arrow : ink(attrs),
                                  stroke_width: "1")
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
                               font_family: look(:font_name) || FONT_FAMILY,
                               font_size: attrs[:size].to_s,
                               font_weight: attrs[:weight],
                               fill: look(:font_colour) || "#000000")
              .tap { |text| Creole.assign(text, attrs[:content]) }
          end

          def look(property)
            @style.explicit(:activity, property)
          end

          def arrow
            @style.explicit(:arrow, :border) || INK
          end

          # The default box paint stands for what the source sets.
          def paper(fill)
            fill == PAPER ? look(:background) || fill : fill
          end

          def ink(attrs)
            stroke = attrs[:stroke]
            stroke == INK ? look(:border) || stroke : stroke
          end

          def line_ink(stroke)
            stroke == INK ? arrow : stroke
          end

          def thickness
            (look(:line_thickness) || 1).to_s
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
