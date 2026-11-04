# frozen_string_literal: true

require_relative "../../renderer/base"
require_relative "../../svg"
require_relative "layout"

module Sirena
  module Notation
    module PlantUMLSalt
      # Draws a {Scene} the way PlantUML draws a salt window: a bordered box
      # on white, black one-pixel rules, widgets as small outlined shapes.
      class Renderer < Sirena::Renderer::Base
        FONT_FAMILY = "sans-serif"
        INK = "#000000"
        PAPER = "#FFFFFF"
        WIDGET_PAPER = "#F1F1F1"
        WIDGET_FILLS = %w[button field droplist].freeze
        private_constant :FONT_FAMILY, :INK, :PAPER, :WIDGET_PAPER,
                         :WIDGET_FILLS

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

        def rectangle(mark)
          box = mark.box
          element(Svg::Rect, x: box.left, y: box.top, width: box.width,
                             height: box.height, fill: paper_for(mark.fill),
                             stroke: INK, stroke_width: "1", rx: corner(mark))
        end

        def corner(mark)
          mark.box.width / 2 if mark.fill.start_with?("radio")
        end

        def paper_for(fill)
          return "none" if fill == "frame"
          return INK if fill.end_with?("-checked")

          WIDGET_FILLS.include?(fill) ? WIDGET_PAPER : PAPER
        end

        def rule(mark)
          box = mark.box
          element(Svg::Line, x1: box.left, y1: box.top, x2: box.right,
                             y2: box.bottom, stroke: INK, stroke_width: "1")
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
