# frozen_string_literal: true

require_relative "../../renderer/base"
require_relative "../../svg"
require_relative "layout"

module Sirena
  module Notation
    module PlantUMLSalt
      # Draws a {Scene} the way PlantUML draws a salt window: black one-pixel
      # rules and widgets as small outlined shapes.
      class Renderer < Sirena::Renderer::Base
        FONT_FAMILY = "sans-serif"
        INK = "#000000"
        private_constant :FONT_FAMILY, :INK

        # @param scene [Scene]
        # @return [Svg::Document]
        def render(scene)
          Svg::Document.new(
            width: scene.width, height: scene.height,
            view_box: scene.view_box
          ).tap do |document|
            scene.marks.each { |mark| document << draw(mark) }
          end
        end

        private

        def draw(mark)
          case mark.kind
          when :rect then rectangle(mark)
          when :ellipse then ellipse(mark)
          when :polygon then polygon(mark)
          when :line then rule(mark)
          else text(mark)
          end
        end

        def element(type, **attributes)
          type.new.tap do |node|
            attributes.each do |name, value|
              node.public_send(:"#{name}=", value) unless value.nil?
            end
          end
        end

        def outline(mark)
          { fill: mark.fill, stroke: mark.ink || INK,
            stroke_width: mark.weight.to_s }
        end

        def rectangle(mark)
          box = mark.box
          element(Svg::Rect, x: box.left, y: box.top, width: box.width,
                             height: box.height, rx: mark.radius,
                             ry: mark.radius, **outline(mark))
        end

        def ellipse(mark)
          radius = mark.box.width / 2
          element(Svg::Ellipse, cx: mark.box.left + radius,
                                cy: mark.box.top + radius, rx: radius,
                                ry: radius, **outline(mark))
        end

        def polygon(mark)
          points = mark.points.map { |pair| pair.map { |n| n.round(4) } }
          element(Svg::Polygon, points: Svg::Polygon.build_points(points),
                                **outline(mark))
        end

        def rule(mark)
          box = mark.box
          element(Svg::Line, x1: box.left, y1: box.top, x2: box.right,
                             y2: box.bottom, stroke: mark.ink || INK,
                             stroke_width: "1")
        end

        def text(mark)
          run = mark.run
          element(Svg::Text, x: mark.box.left + lead_width(run.text),
                             y: mark.box.top + 4, content: run.text.lstrip,
                             **typeface(run))
        end

        def typeface(run)
          { font_family: FONT_FAMILY, font_size: Layout::FONT_SIZE.to_s,
            font_weight: ("bold" if run.bold),
            font_style: ("italic" if run.italic), fill: run.color }
        end

        # SVG collapses a text element's leading spaces, so they are
        # measured and added to x instead.
        def lead_width(text)
          lead = text[/\A\s*/].length
          TextMeasurement.measure(" " * lead,
                                  font_size: Layout::FONT_SIZE)[:width]
        end
      end
    end
  end
end
