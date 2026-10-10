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
        svg = create_document(scene)
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
        children = [requirement_box(node), requirement_header(node)]
        children.concat(requirement_body_labels(node))
        svg << group_with_children("requirement-#{node.id}", children)
      end

      def requirement_body_labels(node)
        node.labels.reject { |label| label.role == "header" }.map do |label|
          requirement_label(label, node.risk)
        end
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
        children = [requirement_header_background(node)]
        children.concat(
          node.labels.select { |label| label.role == "header" }.map do |label|
            header_label(label)
          end,
        )
        group_with_children(nil, children)
      end

      def requirement_header_background(node)
        Svg::Rect.new.tap do |rect|
          apply_rect(rect, node.header)
          rect.fill = risk_color(node.risk) ||
            theme_color(:node_fill) || "#e0e0e0"
          rect.opacity = "0.3"
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
        children = [element_shape(node)]
        children.concat(node.labels.map { |label| element_label(label) })
        svg << group_with_children("element-#{node.id}", children)
      end

      def element_shape(node)
        Svg::Polygon.new.tap do |polygon|
          polygon.points = node.shape_points
          polygon.fill = theme_color(:node_fill) || "#e0f2f1"
          polygon.stroke = theme_color(:border_color) || "#00796b"
          polygon.stroke_width = "2"
        end
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
        children = [relationship_path(edge)]
        children.concat(relationship_label_elements(edge))
        id = "relationship-#{edge.source}-#{edge.target}"
        svg << group_with_children(id, children)
      end

      def relationship_path(edge)
        Svg::Path.new.tap do |path|
          path.d = edge.path
          path.fill = "none"
          path.stroke = theme_color(:edge_color) || "#666"
          path.stroke_width = "2"
          path.marker_end = "url(#arrowhead)"
        end
      end

      def relationship_label_elements(edge)
        return [] if edge.labels.empty?

        [
          relationship_label_background(edge),
          relationship_label(edge.labels.first),
        ]
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

      def group_with_children(id, children)
        Svg::Group.new.tap do |group|
          group.id = id if id
          group.children.concat(children)
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
