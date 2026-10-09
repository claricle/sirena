# frozen_string_literal: true

require_relative "base"
require_relative "../layout/timeline"
require_relative "../svg/document"
require_relative "../svg/rect"
require_relative "../svg/text"
require_relative "../svg/circle"

module Sirena
  module Renderer
    # Emits SVG from final, typed timeline geometry.
    class Timeline < Base
      SECTION_COLORS = [
        "#4472C4", "#ED7D31", "#A5A5A5", "#FFC000", "#5B9BD5", "#70AD47"
      ].freeze

      # @param scene [Layout::Timeline::Scene] final timeline geometry
      # @return [Svg::Document] rendered SVG document
      def render(scene)
        svg = document(scene)
        svg << text_element(scene.title) if scene.title
        scene.tracks.each { |track| render_track(track, svg) }
        svg
      end

      protected

      def document(scene)
        Svg::Document.new.tap do |svg|
          svg.width = scene.width
          svg.height = scene.height
          svg.view_box = scene.view_box
        end
      end

      def render_track(track, svg)
        svg << text_element(track.header) if track.header
        svg << axis_element(track.axis)
        track.entries.each { |entry| render_entry(entry, svg) }
        track.range_labels.each { |label| svg << text_element(label) }
      end

      def render_entry(entry, svg)
        svg << marker_element(entry.marker)
        entry.labels.each { |label| svg << text_element(label) }
      end

      def axis_element(axis)
        Svg::Rect.new.tap do |rect|
          rect.x = axis.x
          rect.y = axis.y
          rect.width = axis.width
          rect.height = axis.height
          rect.fill = theme_color(:node_fill) || "#cccccc"
          rect.stroke = "none"
          rect.rx = axis.corner_radius
          rect.ry = axis.corner_radius
        end
      end

      def marker_element(marker)
        Svg::Circle.new.tap do |circle|
          circle.cx = marker.x
          circle.cy = marker.y
          circle.r = marker.radius
          circle.fill = section_color(marker.section_index)
          circle.stroke = theme_color(:node_stroke) || "#ffffff"
          circle.stroke_width = "2"
        end
      end

      def text_element(label)
        Svg::Text.new.tap do |text|
          text.x = label.x
          text.y = label.y
          text.content = label.text
          text.fill = label_color(label)
          text.font_family =
            theme_typography(:font_family) || "Arial, sans-serif"
          text.font_size = number_string(label.font_size)
          text.text_anchor = label.text_anchor if label.text_anchor
          text.font_weight = label.font_weight if label.font_weight
        end
      end

      def label_color(label)
        return section_color(label.section_index) if label.style == "section"
        return theme_color(:label_text) || "#666666" if label.style == "muted"

        theme_color(:label_text) || "#000000"
      end

      def section_color(index)
        SECTION_COLORS[index % SECTION_COLORS.length]
      end

      def number_string(value)
        value.to_i == value ? value.to_i.to_s : value.to_s
      end
    end
  end
end
