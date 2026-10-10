# frozen_string_literal: true

require_relative "base"
require_relative "../layout/requirement"

module Sirena
  module Renderer
    # Emits SVG from final, typed requirement geometry.
    class Requirement < Base
      RISK_COLORS = {
        "high" => "#ff6b6b",
        "medium" => "#ffd93d",
        "low" => "#6bcf7f",
      }.freeze

      REQUIREMENT_TYPE_LABELS = Layout::Requirement::REQUIREMENT_TYPE_LABELS

      # @param scene [Layout::Requirement::Scene] final canvas geometry
      # @return [Svg::Document] rendered SVG document
      def render(scene)
        svg = Svg::Document.new(width: scene.width, height: scene.height,
                                view_box: scene.view_box)
        scene.edges.each { |edge| render_relationship(edge, svg) }
        scene.children.each { |node| render_node(node, svg) }
        svg
      end

      protected

      def render_node(node, svg)
        if node.kind == "requirement"
          render_requirement(node, svg)
        else
          render_element(node, svg)
        end
      end

      def render_requirement(node, svg)
        group = Svg::Group.new.tap do |item|
          item.id = "requirement-#{node.id}"
        end
        group.children << requirement_box(node)
        group.children << requirement_header(node)
        node.labels.reject { |label| label.role == "header" }.each do |label|
          group.children << requirement_label(label, node.risk)
        end
        svg << group
      end

      def requirement_box(node)
        Svg::Rect.new.tap do |rect|
          apply_rect(rect, node.box)
          rect.fill = theme_color(:node_fill) || "#f9f9f9"
          rect.stroke = risk_color(node.risk) ||
            theme_color(:border_color) || "#333"
          rect.stroke_width = "2"
          rect.rx = "5"
          rect.ry = "5"
        end
      end

      def requirement_header(node)
        labels = node.labels.select { |label| label.role == "header" }
        Svg::Group.new.tap do |group|
          group.children << Svg::Rect.new.tap do |rect|
            apply_rect(rect, node.header)
            rect.fill = risk_color(node.risk) ||
              theme_color(:node_fill) || "#e0e0e0"
            rect.opacity = "0.3"
          end
          labels.each { |label| group.children << header_label(label) }
        end
      end

      def header_label(label)
        Svg::Text.new.tap do |text|
          apply_label(text, label)
          text.fill = theme_color(:text_color) || "#000"
          text.dominant_baseline = "middle"
        end
      end

      def requirement_label(label, risk)
        Svg::Text.new.tap do |text|
          apply_label(text, label)
          text.fill = if label.role == "risk"
                        risk_color(risk)
                      else
                        theme_color(:text_color) || "#000"
                      end
        end
      end

      def render_element(node, svg)
        group = Svg::Group.new.tap { |item| item.id = "element-#{node.id}" }
        group.children << Svg::Polygon.new.tap do |polygon|
          polygon.points = node.shape_points
          polygon.fill = theme_color(:node_fill) || "#e0f2f1"
          polygon.stroke = theme_color(:border_color) || "#00796b"
          polygon.stroke_width = "2"
        end
        node.labels.each do |label|
          group.children << element_label(label)
        end
        svg << group
      end

      def element_label(label)
        Svg::Text.new.tap do |text|
          apply_label(text, label)
          text.fill = if label.role == "detail"
                        theme_color(:text_color) || "#666"
                      else
                        theme_color(:text_color) || "#000"
                      end
          text.dominant_baseline = "middle"
        end
      end

      def render_relationship(edge, svg)
        group = Svg::Group.new.tap do |item|
          item.id = "relationship-#{edge.source}-#{edge.target}"
        end
        group.children << Svg::Path.new.tap do |path|
          path.d = edge.path
          path.fill = "none"
          path.stroke = theme_color(:edge_color) || "#666"
          path.stroke_width = "2"
          path.marker_end = "url(#arrowhead)"
        end
        unless edge.labels.empty?
          group.children << relationship_label_background(edge)
          group.children << relationship_label(edge.labels.first)
        end
        svg << group
      end

      def relationship_label_background(edge)
        Svg::Rect.new.tap do |rect|
          apply_rect(rect, edge.label_background)
          rect.fill = "#fff"
          rect.stroke = theme_color(:edge_color) || "#666"
          rect.stroke_width = "1"
          rect.rx = "3"
        end
      end

      def relationship_label(label)
        Svg::Text.new.tap do |text|
          apply_label(text, label)
          text.fill = theme_color(:text_color) || "#000"
          text.dominant_baseline = "middle"
        end
      end

      def apply_rect(rect, geometry)
        rect.x = geometry.x
        rect.y = geometry.y
        rect.width = geometry.width
        rect.height = geometry.height
      end

      def apply_label(text, label)
        text.x = label.x
        text.y = label.y
        text.content = label.text
        text.font_size = label.font_size.to_s
        text.font_weight = label.font_weight
        text.text_anchor = label.text_anchor
      end

      def risk_color(risk)
        return unless risk

        RISK_COLORS[risk.downcase] || theme_color(:border_color) || "#666"
      end
    end
  end
end
