# frozen_string_literal: true

require_relative "../../../renderer/base"
require_relative "../../../svg"
require_relative "layout"
require_relative "../creole"

module Sirena
  module Notation
    module PlantUML
      module Activity
        # Draws a {Scene}: each {Mark} becomes one SVG element, in order.
        class Renderer < Sirena::Renderer::Base
          FONT_FAMILY = "sans-serif"
          private_constant :FONT_FAMILY

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
                               height: attrs[:height], rx: attrs[:rx],
                               fill: attrs[:fill], stroke: attrs[:stroke],
                               stroke_width: "1")
          end

          def draw_circle(attrs)
            element(Svg::Circle, cx: attrs[:cx], cy: attrs[:cy], r: attrs[:r],
                                 fill: attrs[:fill], stroke: attrs[:stroke],
                                 stroke_width: "1")
          end

          def draw_polygon(attrs)
            element(Svg::Polygon, points: format_points(attrs[:points]),
                                  fill: attrs[:fill], stroke: attrs[:stroke],
                                  stroke_width: "1")
          end

          def draw_path(attrs)
            element(Svg::Path, d: path_data(attrs[:points]), fill: "none",
                               stroke: attrs[:stroke],
                               stroke_width: attrs[:width].to_s,
                               stroke_dasharray: attrs[:dash])
          end

          def draw_text(attrs)
            element(Svg::Text, x: attrs[:x], y: attrs[:y],
                               content: attrs[:content],
                               text_anchor: attrs[:anchor],
                               font_family: FONT_FAMILY,
                               font_size: attrs[:size].to_s,
                               font_weight: attrs[:weight], fill: "#000000")
              .tap { |text| Creole.assign(text, attrs[:content]) }
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
