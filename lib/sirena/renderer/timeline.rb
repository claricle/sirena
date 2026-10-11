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
require_relative "../svg/tspan"

module Sirena
  module Renderer
    # Emits SVG from final, typed timeline geometry.
    class Timeline < Base
      FONT_FAMILY = "Trebuchet MS, Verdana, Arial, sans-serif"
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
        wrapper = Svg::Group.new(class_name: CARD_WRAPPERS.fetch(card.kind))
        wrapper.tap { |group| group << node_group(card) }
      end

      def node_group(card)
        fill, text, rule = TimelinePalette.for(theme.colors, card.color_index)
        Svg::Group.new(class_name: "timeline-node").tap do |node|
          node << background(card, fill, rule)
          node << text_element(card, text)
        end
      end

      def background(card, fill, rule)
        Svg::Group.new.tap do |group|
          group << Svg::Path.new(d: card.outline, fill: fill,
                                 class_name: "node-bkg")
          group << rule_line(card.rule, rule)
        end
      end

      def rule_line(line, stroke)
        Svg::Line.new(
          x1: number(line.x1), y1: number(line.y1),
          x2: number(line.x2), y2: number(line.y2),
          stroke: stroke, stroke_width: "3", class_name: "node-line"
        )
      end

      def text_element(card, color)
        text = Svg::Text.new(
          x: number(card.text_x), y: number(card.text_y), fill: color,
          font_family: FONT_FAMILY, font_size: number(card.font_size),
          text_anchor: "middle"
        )
        fill_text(text, card)
      end

      def fill_text(text, card)
        if card.lines.length < 2
          text.content = card.lines.first.to_s
        else
          text.tspans = tspans(card)
        end
        text
      end

      def tspans(card)
        baselines = [nil, *card.next_baselines]
        card.lines.zip(baselines).map do |line, baseline|
          Svg::Tspan.new(x: card.text_x, y: baseline).tap do |run|
            run.content = line
          end
        end
      end

      def title_element(scene)
        text = Svg::Text.new(
          x: scene.title_x, y: scene.title_y,
          fill: theme_color(:label_text),
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
          fill: "none", stroke: theme_color(:edge_stroke),
          marker_end: ARROW,
          stroke_width: number(line.stroke_width),
          stroke_dasharray: ("5,5" if line.dashed)
        )
      end

      def number(value)
        value.to_i == value ? value.to_i.to_s : value.to_s
      end
    end
  end
end
