# frozen_string_literal: true

require_relative "../../../renderer/base"
require_relative "../../../svg"
require_relative "ornaments"
require_relative "text"

module Sirena
  module Notation
    module PlantUMLData
      module Boxes
        # Draws a {Scene} the way PlantUML does: grey boxes with black
        # rules, dashed links in a JSON or YAML tree.
        class Renderer < Sirena::Renderer::Base
          FONT = "sans-serif"
          private_constant :FONT

          # @param scene [Scene]
          # @return [Svg::Document]
          def render(scene)
            Svg::Document.new(width: scene.width, height: scene.height,
                              view_box: scene.view_box).tap do |document|
              scene.marks.each do |mark|
                [*Ornaments.behind(mark), mark, *Ornaments.over(mark)]
                  .each { |piece| document << draw(piece) }
              end
            end
          end

          private

          def draw(mark)
            send(:"draw_#{mark[:kind]}", mark)
          end

          def element(type, **attributes)
            type.new.tap do |node|
              attributes.each do |name, value|
                node.public_send(:"#{name}=", value) unless value.nil?
              end
            end
          end

          def draw_rect(mark)
            element(Svg::Rect, **mark.slice(:x, :y, :width, :height, :rx, :fill,
                                            :stroke, :stroke_width),
                    ry: mark[:rx])
          end

          def draw_line(mark)
            element(Svg::Line,
                    **mark.slice(:x1, :y1, :x2, :y2, :stroke, :stroke_width))
          end

          def draw_text(mark)
            element(Svg::Text, x: mark[:x], y: mark[:y], fill: mark[:fill],
                               font_family: FONT, font_size: "14",
                               font_weight: ("bold" if mark[:bold]),
                               font_style: ("italic" if mark[:italic]),
                               text_anchor: mark[:anchor])
              .tap { |text| Text.assign(text, mark[:content]) }
          end

          def draw_path(mark)
            element(Svg::Path, d: mark[:d], fill: "none", stroke: mark[:stroke],
                               stroke_width: "1",
                               stroke_dasharray: dashes(mark))
          end

          def dashes(mark)
            mark[:dash] || "3,3" if mark[:dashed]
          end

          def draw_glyph(mark)
            element(Svg::Path, d: mark[:d], fill: mark[:fill],
                               transform: mark[:transform])
          end

          def draw_polygon(mark)
            element(Svg::Polygon, points: Svg::Polygon.build_points(mark[:points]),
                                  fill: mark[:fill], stroke: mark[:stroke],
                                  stroke_width: "1")
          end

          def draw_circle(mark)
            element(Svg::Circle, cx: mark[:cx], cy: mark[:cy], r: mark[:r],
                                 fill: mark[:fill], stroke: mark[:fill],
                                 stroke_width: "1")
          end
        end
      end
    end
  end
end
