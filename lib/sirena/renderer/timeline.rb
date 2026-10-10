# frozen_string_literal: true

require_relative "base"
require_relative "line_break_text"
require_relative "timeline_palette"
require_relative "../layout/timeline"
require_relative "../svg/document"
require_relative "../svg/group"
require_relative "../svg/line"
require_relative "../svg/path"
require_relative "../svg/text"

module Sirena
  module Renderer
    # Emits SVG from final, typed timeline geometry.
    class Timeline < Base
      FONT_FAMILY = "Trebuchet MS, Verdana, Arial, sans-serif"
      LINE_PITCH = 17.6
      # Baseline of the first text line inside a card's text group.
      FIRST_BASELINE = 21
      CARD_WRAPPERS = {
        "section" => nil, "period" => "taskWrapper", "event" => "eventWrapper"
      }.freeze
      ARROW = "url(#arrowhead)"

      # @param scene [Layout::Timeline::Scene] final timeline geometry
      # @return [Svg::Document] rendered SVG document
      def render(scene)
        svg = create_document(scene)
        scene.cards.each { |card| render_card(card, svg) }
        svg << title_element(scene) if scene.title
        svg << line_group(scene.axis)
        svg
      end

      protected

      def render_card(card, svg)
        svg << card_group(card)
        svg << line_group(card.connector) if card.connector
      end

      def card_group(card)
        wrapper = Svg::Group.new(
          class_name: CARD_WRAPPERS.fetch(card.kind),
          transform: "translate(#{number(card.x)}, #{number(card.y)})",
        )
        wrapper.tap { |group| group << node_group(card) }
      end

      def node_group(card)
        fill, text, rule = TimelinePalette.for(card.color_index)
        Svg::Group.new(class_name: "timeline-node").tap do |node|
          node << background(card, fill, rule)
          node << text_group(card, text)
        end
      end

      def background(card, fill, rule)
        Svg::Group.new.tap do |group|
          group << card_path(card, fill)
          group << rule_line(card, rule)
        end
      end

      def card_path(card, fill)
        height = card.height
        width = card.width
        Svg::Path.new(
          d: "M0 #{number(height - 5)} v#{number(5 - height + 5)} " \
             "q0,-5 5,-5 h#{number(width - 10)} q5,0 5,5 " \
             "v#{number(height - 5)} H0 Z",
          fill: fill, class_name: "node-bkg"
        )
      end

      def rule_line(card, rule)
        Svg::Line.new(
          x1: 0, y1: card.height, x2: card.width, y2: card.height,
          stroke: rule, stroke_width: "3", class_name: "node-line"
        )
      end

      def text_group(card, color)
        group = Svg::Group.new(
          transform: "translate(#{number(card.width / 2)}, 10)",
        )
        group.tap { |text| text << text_element(card, color) }
      end

      def text_element(card, color)
        lines = card.lines
        text = Svg::Text.new(
          x: 0, y: FIRST_BASELINE, fill: color, font_family: FONT_FAMILY,
          font_size: number(card.font_size), text_anchor: "middle"
        )
        return LineBreakText.fill(text, lines.first.to_s) if lines.length < 2

        LineBreakText.fill_lines(text, lines, pitch: LINE_PITCH)
      end

      def title_element(scene)
        text = Svg::Text.new(
          x: scene.title_x, y: scene.title_y, fill: "#333333",
          font_family: FONT_FAMILY, font_size: number(scene.title_size),
          font_weight: "bold"
        )
        LineBreakText.fill(text, scene.title)
      end

      def line_group(line)
        Svg::Group.new(class_name: "lineWrapper").tap do |group|
          group << arrow_path(line)
        end
      end

      def arrow_path(line)
        Svg::Path.new(
          d: "M #{number(line.x1)} #{number(line.y1)} " \
             "L #{number(line.x2)} #{number(line.y2)}",
          fill: "none", stroke: "#000000", marker_end: ARROW,
          stroke_width: number(line.stroke_width),
          stroke_dasharray: ("5,5" if line.dashed)
        )
      end

      def number(value)
        value.to_i == value ? value.to_i.to_s : value.round(4).to_s
      end
    end
  end
end
