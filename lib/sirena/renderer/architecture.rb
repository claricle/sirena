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
        svg = create_document(scene)
        render_groups(scene, svg)
        scene.edges.each { |edge| render_edge(edge, svg) }
        render_nodes(scene, svg)
        svg
      end

      protected

      def render_groups(scene, svg)
        scene.children.select { |node| node.kind == "group" }
          .each { |group| render_group(group, svg) }
      end

      def render_nodes(scene, svg)
        scene.children.reject { |node| node.kind == "group" }
          .each { |node| render_node(node, svg) }
      end

      def named_architecture_group(identifier)
        Svg::Group.new.tap { |group| group.id = identifier }
      end

      def render_group(node, svg)
        group = named_architecture_group("group-#{node.id}")
        children = group.children
        children << group_boundary(node)
        children << group_label(node) unless node.labels.empty?
        children << icon(node, 20) if node.icon
        svg << group
      end

      def group_boundary(node)
        Svg::Rect.new.tap do |rect|
          apply_box(rect, node)
          rect.fill = theme_color(:group_background)
          rect.fill_opacity = "0.3"
          rect.stroke = theme_color(:architecture_group_border)
          rect.stroke_width = "2"
          rect.stroke_dasharray = "5,5"
          rect.rx = "8"
          rect.ry = "8"
        end
      end

      def group_label(node)
        positioned_text(node.labels.first).tap do |text|
          text.fill = theme_color(:architecture_group_label)
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
        group = named_architecture_group("service-#{node.id}")
        children = group.children
        children << service_box(node)
        children << icon(node, 24) if node.icon
        children << service_label(node) unless node.labels.empty?
        svg << group
      end

      def service_box(node)
        return fallback_service_box(node) if node.icon.to_s.empty?

        Svg::Rect.new.tap do |rect|
          apply_box(rect, node)
          apply_theme_to_node(rect)
          rect.rx = "5"
          rect.ry = "5"
        end
      end

      def fallback_service_box(node)
        Svg::Path.new.tap do |path|
          path.d = fallback_service_path(node)
          path.fill = "none"
          path.stroke = theme_color(:node_stroke)
          path.stroke_width = "2"
          path.stroke_dasharray = "8"
        end
      end

      def fallback_service_path(node)
        top = node.y + 5
        right = node.x + node.width
        bottom = node.y + node.height
        fallback_service_commands(node, top, right, bottom)
      end

      def fallback_service_commands(node, top, right, bottom)
        "M #{node.x} #{bottom} V #{top} Q #{node.x} #{node.y} " \
          "#{node.x + 5} #{node.y} H #{right - 5} Q #{right} #{node.y} " \
          "#{right} #{top} V #{bottom} H #{node.x} Z"
      end

      def icon(node, size)
        Svg::Text.new.tap do |text|
          position_icon(text, node)
          text.content = icon_glyph(node.icon)
          text.font_size = size.to_s
          align_service_icon(text, node)
          text.fill = theme_color(:edge_color)
        end
      end

      def position_icon(text, node)
        text.x = node.icon_x
        text.y = node.icon_y
      end

      def align_service_icon(text, node)
        return unless node.kind == "service"

        text.text_anchor = "middle"
        text.dominant_baseline = "middle"
      end

      def service_label(node)
        positioned_text(node.labels.first).tap do |text|
          text.fill = theme_color(:label_text)
          text.font_family = label_font_family
          text.dominant_baseline = "middle"
        end
      end

      def positioned_text(label)
        Svg::Text.new(
          x: label.x, y: label.y, content: label.text,
          font_size: number_string(label.font_size),
          font_weight: label.font_weight,
          text_anchor: label.text_anchor
        )
      end

      def label_font_family
        theme_typography(:font_family) || "Arial, Helvetica, sans-serif"
      end

      def render_junction(node, svg)
        group = named_architecture_group("junction-#{node.id}")
        group.children << junction_circle(node)
        svg << group
      end

      def junction_circle(node)
        Svg::Circle.new.tap do |circle|
          circle.cx = node.center_x
          circle.cy = node.center_y
          circle.r = node.radius
          apply_theme_to_node(circle)
        end
      end

      def render_edge(edge, svg)
        group = named_architecture_group("edge-#{edge.source}-#{edge.target}")
        group.children << edge_path(edge)
        unless edge.labels.empty?
          group.children << edge_label(edge.labels.first)
        end
        svg << group
      end

      def edge_path(edge)
        Svg::Path.new.tap do |path|
          path.d = section_path(edge.sections.first)
          path.fill = "none"
          apply_theme_to_edge(path)
        end
      end

      def section_path(section)
        points = [section.start_point, *section.bend_points, section.end_point]
        points.map.with_index do |point, index|
          "#{index.zero? ? 'M' : 'L'} #{point.x} #{point.y}"
        end.join(" ")
      end

      def edge_label(label)
        positioned_text(label).tap do |text|
          text.fill = theme_color(:edge_color)
        end
      end

      def number_string(value)
        value.to_i == value ? value.to_i.to_s : value.to_s
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
      private :render_groups, :render_nodes, :named_architecture_group,
              :position_icon, :align_service_icon, :junction_circle
    end
  end
end
