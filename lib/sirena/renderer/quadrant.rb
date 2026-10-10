# frozen_string_literal: true

require_relative "base"
require_relative "../layout/quadrant"
require_relative "../svg/document"
require_relative "../svg/rect"
require_relative "../svg/line"
require_relative "../svg/circle"
require_relative "../svg/group"
require_relative "../svg/text"

module Sirena
  module Renderer
    # Emits SVG from final, typed quadrant-chart geometry.
    class Quadrant < Base
      # mmdc's default-theme quadrant fills and text colour.
      QUADRANT_COLORS = {
        1 => "#ECECFF", 2 => "#f1f1ff", 3 => "#f6f6ff", 4 => "#fbfbff"
      }.freeze
      BORDER_COLOR = "#c7c7f1"
      TEXT_COLOR = "#131300"

      # @param scene [Layout::Quadrant::Scene] final chart geometry
      # @return [Svg::Document] rendered SVG document
      def render(scene)
        svg = create_document(scene)
        svg << quadrants_group(scene)
        svg << border_group(scene.axes)
        svg << points_group(scene.points)
        svg << labels_group(scene.axis_labels)
        svg << title_group(scene.title)
        svg
      end

      protected

      def group(name)
        Svg::Group.new(class_name: name)
      end

      # One `g.quadrant` per region: its rect, then its label when written.
      def quadrants_group(scene)
        group("quadrants").tap do |quadrants|
          scene.quadrants.each do |quadrant|
            quadrants << quadrant_group(quadrant, scene.quadrant_labels)
          end
        end
      end

      def quadrant_group(quadrant, labels)
        group("quadrant").tap do |cell|
          cell << quadrant_rect(quadrant)
          label = labels.find { |item| centred_in?(item, quadrant) }
          cell << text_element(label) if label
        end
      end

      def centred_in?(label, quadrant)
        (label.x - (quadrant.x + (quadrant.width / 2.0))).abs < 0.001 &&
          label.y.between?(quadrant.y, quadrant.y + quadrant.height)
      end

      def quadrant_rect(quadrant)
        Svg::Rect.new.tap do |rect|
          rect.x = quadrant.x
          rect.y = quadrant.y
          rect.width = quadrant.width
          rect.height = quadrant.height
          rect.fill = quadrant_color(quadrant.number)
        end
      end

      def border_group(lines)
        group("border").tap do |border|
          lines.each { |line| border << border_line(line) }
        end
      end

      def border_line(line)
        Svg::Line.new.tap do |element|
          element.x1 = line.x1
          element.y1 = line.y1
          element.x2 = line.x2
          element.y2 = line.y2
          element.stroke = theme_color(:grid_line) || BORDER_COLOR
          element.stroke_width = number_string(line.stroke_width)
        end
      end

      def points_group(points)
        group("data-points").tap do |container|
          points.each { |point| container << point_group(point) }
        end
      end

      def point_group(point)
        group("data-point").tap do |cell|
          cell << point_element(point)
          cell << text_element(point.label)
        end
      end

      def labels_group(labels)
        group("labels").tap do |container|
          labels.each do |label|
            container << group("label").tap { |cell| cell << text_element(label) }
          end
        end
      end

      def title_group(title)
        group("title").tap do |container|
          container << text_element(title) if title
        end
      end

      def point_element(point)
        Svg::Circle.new.tap do |circle|
          circle.cx = point.x
          circle.cy = point.y
          circle.r = point.radius
          apply_point_style(circle, point)
        end
      end

      def apply_point_style(circle, point)
        circle.fill = point.color || point_color(point.quadrant)
        circle.stroke = point_stroke(point)
        circle.stroke_width = number_string(point.stroke_width)
        circle.id = point.id
      end

      def point_stroke(point)
        point.stroke_color || theme_color(:node_stroke) || "#ffffff"
      end

      # mmdc places every text at the origin and moves it with a transform.
      def text_element(label)
        Svg::Text.new.tap do |text|
          text.x = 0
          text.y = 0
          text.content = label.text
          text.transform = transform(label)
          text.dominant_baseline = label.baseline
          text.text_anchor = label.text_anchor if label.text_anchor
          apply_text_style(text, label)
        end
      end

      def transform(label)
        "translate(#{number_string(label.x)}, #{number_string(label.y)}) " \
          "rotate(#{number_string(label.rotation || 0)})"
      end

      def apply_text_style(text, label)
        text.fill = theme_color(:label_text) || TEXT_COLOR
        text.font_family = theme_typography(:font_family) || "Arial, sans-serif"
        text.font_size = number_string(label.font_size)
        text.font_weight = label.font_weight if label.font_weight
      end

      def quadrant_color(number)
        theme_color(:"quadrant_#{number}") || QUADRANT_COLORS[number]
      end

      def point_color(number)
        {
          1 => theme_color(:primary) || "#2196f3",
          2 => theme_color(:secondary) || "#ff9800",
          3 => theme_color(:accent) || "#9c27b0",
          4 => theme_color(:success) || "#4caf50",
        }.fetch(number, theme_color(:primary) || "#2196f3")
      end

      def number_string(value)
        value = value.to_f.round(4)
        value.to_i == value ? value.to_i.to_s : value.to_s
      end
    end
  end
end
