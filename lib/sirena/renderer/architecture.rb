# frozen_string_literal: true

require_relative "base"
require_relative "../layout/architecture"

module Sirena
  module Renderer
    # Emits SVG from final, typed architecture geometry.
    class Architecture < Base
      ICON_GLYPHS = {
        "database" => "⬢",
        "server" => "▦",
        "disk" => "◎",
        "cloud" => "☁",
        "internet" => "◈",
        "browser" => "⊞",
      }.freeze

      UNKNOWN_ICON_GLYPH = "?"

      # @param scene [Layout::Architecture::Scene] final canvas geometry
      # @return [Svg::Document] rendered SVG document
      def render(scene)
        svg = document(scene)
        scene.children.select { |node| node.kind == "group" }
          .each { |group| render_group(group, svg) }
        scene.edges.each { |edge| render_edge(edge, svg) }
        scene.children.reject { |node| node.kind == "group" }
          .each { |node| render_node(node, svg) }
        svg
      end

      protected

      def document(scene)
        Svg::Document.new(width: scene.width, height: scene.height,
                          view_box: scene.view_box)
      end

      def render_group(node, svg)
        group = Svg::Group.new.tap { |item| item.id = "group-#{node.id}" }
        group.children << group_boundary(node)
        group.children << group_label(node) unless node.labels.empty?
        group.children << icon(node, 20) if node.icon
        svg << group
      end

      def group_boundary(node)
        Svg::Rect.new.tap do |rect|
          apply_box(rect, node)
          rect.fill = theme_color(:group_background) || "#f0f0f0"
          rect.fill_opacity = "0.3"
          rect.stroke = theme_color(:border_color) || "#999"
          rect.stroke_width = "2"
          rect.stroke_dasharray = "5,5"
          rect.rx = "8"
          rect.ry = "8"
        end
      end

      def group_label(node)
        positioned_text(node.labels.first).tap do |text|
          text.font_size = "14"
          text.font_weight = "bold"
          text.fill = theme_color(:text_color) || "#333"
        end
      end

      def render_node(node, svg)
        if node.kind == "junction"
          render_junction(node, svg)
        else
          render_service(node, svg)
        end
      end

      def render_service(node, svg)
        group = Svg::Group.new.tap { |item| item.id = "service-#{node.id}" }
        group.children << service_box(node)
        group.children << icon(node, 24) if node.icon
        group.children << service_label(node) unless node.labels.empty?
        svg << group
      end

      def service_box(node)
        Svg::Rect.new.tap do |rect|
          apply_box(rect, node)
          apply_theme_to_node(rect)
          rect.rx = "5"
          rect.ry = "5"
        end
      end

      def icon(node, size)
        Svg::Text.new.tap do |text|
          text.x = node.icon_x
          text.y = node.icon_y
          text.content = icon_glyph(node.icon)
          text.font_size = size.to_s
          text.text_anchor = "middle" if node.kind == "service"
          text.dominant_baseline = "middle" if node.kind == "service"
          text.fill = theme_color(:text_color) || "#666"
        end
      end

      def service_label(node)
        positioned_text(node.labels.first).tap do |text|
          apply_theme_to_text(text)
          text.text_anchor = "middle"
          text.dominant_baseline = "middle"
          text.font_size = "12"
        end
      end

      def positioned_text(label)
        Svg::Text.new.tap do |text|
          text.x = label.x
          text.y = label.y
          text.content = label.text
        end
      end

      def render_junction(node, svg)
        group = Svg::Group.new.tap { |item| item.id = "junction-#{node.id}" }
        group.children << Svg::Circle.new.tap do |circle|
          circle.cx = node.x + (node.width / 2)
          circle.cy = node.y + (node.height / 2)
          circle.r = node.width / 2
          apply_theme_to_node(circle)
        end
        svg << group
      end

      def render_edge(edge, svg)
        group = Svg::Group.new.tap do |item|
          item.id = "edge-#{edge.source}-#{edge.target}"
        end
        group.children << edge_path(edge)
        group.children << edge_label(edge.labels.first) unless edge.labels.empty?
        svg << group
      end

      def edge_path(edge)
        Svg::Path.new.tap do |path|
          path.d = section_path(edge.sections.first)
          path.fill = "none"
          apply_theme_to_edge(path)
          path.marker_end = "url(#arrowhead)"
        end
      end

      def section_path(section)
        points = [section.start_point, *section.bend_points, section.end_point]
        points.map.with_index do |point, index|
          "#{index.zero? ? 'M' : 'L'} #{point.x} #{point.y}"
        end.join(" ")
      end

      def edge_label(label)
        Svg::Text.new.tap do |text|
          text.x = label.x
          text.y = label.y
          text.content = label.text
          text.font_size = "10"
          text.text_anchor = "middle"
          text.fill = theme_color(:text_color) || "#666"
        end
      end

      def apply_box(rect, node)
        rect.x = node.x
        rect.y = node.y
        rect.width = node.width
        rect.height = node.height
      end

      def icon_glyph(icon_name)
        ICON_GLYPHS.fetch(icon_name.split(":").last, UNKNOWN_ICON_GLYPH)
      end
    end
  end
end
