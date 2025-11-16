# frozen_string_literal: true

require_relative "base"

module Sirena
  module Renderer
    # Architecture diagram renderer for converting positioned layouts to SVG
    class ArchitectureRenderer < Base
      # Icon mappings for common service types
      ICON_GLYPHS = {
        "database" => "⬢",
        "server" => "▦",
        "disk" => "◎",
        "cloud" => "☁",
        "internet" => "◈",
        "browser" => "⊞",
      }.freeze

      # Renders a positioned layout to SVG
      #
      # @param layout [Hash] positioned layout with service positions
      # @return [Svg::Document] the rendered SVG document
      def render(layout)
        svg = create_document_from_layout(layout)

        # Render groups first (as backgrounds)
        render_groups(layout, svg) if layout[:groups]

        # Render edges (connections)
        render_edges(layout, svg) if layout[:edges]

        # Render services on top
        render_services(layout, svg) if layout[:services]

        svg
      end

      protected

      def create_document_from_layout(layout)
        width = layout[:width] || 800
        height = layout[:height] || 600

        Svg::Document.new(width: width, height: height)
      end

      def render_groups(layout, svg)
        # Render groups in order (parent groups before children)
        layout[:groups].each do |group_id, group_info|
          render_group(group_info, svg)
        end
      end

      def render_group(group_info, svg)
        group = group_info[:group]
        x = group_info[:x]
        y = group_info[:y]
        width = group_info[:width]
        height = group_info[:height]

        # Create group element
        g = Svg::Group.new.tap do |elem|
          elem.id = "group-#{group.id}"
        end

        # Draw group boundary
        boundary = Svg::Rect.new.tap do |rect|
          rect.x = x
          rect.y = y
          rect.width = width
          rect.height = height
          rect.fill = theme_color(:group_background) || "#f0f0f0"
          rect.fill_opacity = "0.3"
          rect.stroke = theme_color(:border_color) || "#999"
          rect.stroke_width = "2"
          rect.stroke_dasharray = "5,5"
          rect.rx = "8"
          rect.ry = "8"
        end

        g.children << boundary

        # Draw group label
        if group.label
          label = Svg::Text.new.tap do |text|
            text.x = x + 10
            text.y = y + 20
            text.content = group.label
            text.font_size = "14"
            text.font_weight = "bold"
            text.fill = theme_color(:text_color) || "#333"
          end

          g.children << label
        end

        # Draw group icon if present
        if group.icon
          icon_text = Svg::Text.new.tap do |text|
            text.x = x + width - 30
            text.y = y + 25
            text.content = icon_glyph(group.icon)
            text.font_size = "20"
            text.fill = theme_color(:text_color) || "#666"
          end

          g.children << icon_text
        end

        svg << g
      end

      def render_services(layout, svg)
        layout[:services].each do |service_id, service_info|
          render_service(service_info, svg)
        end
      end

      def render_service(service_info, svg)
        service = service_info[:service]
        x = service_info[:x]
        y = service_info[:y]
        width = service_info[:width]
        height = service_info[:height]

        # Create service group
        g = Svg::Group.new.tap do |elem|
          elem.id = "service-#{service.id}"
        end

        # Draw service box
        box = Svg::Rect.new.tap do |rect|
          rect.x = x
          rect.y = y
          rect.width = width
          rect.height = height
          apply_theme_to_node(rect)
          rect.rx = "5"
          rect.ry = "5"
        end

        g.children << box

        # Draw service icon
        if service.icon
          icon = Svg::Text.new.tap do |text|
            text.x = x + width / 2
            text.y = y + height / 3
            text.content = icon_glyph(service.icon)
            text.font_size = "24"
            text.text_anchor = "middle"
            text.dominant_baseline = "middle"
            text.fill = theme_color(:text_color) || "#666"
          end

          g.children << icon
        end

        # Draw service label
        if service.label
          label = Svg::Text.new.tap do |text|
            text.x = x + width / 2
            text.y = y + height * 2 / 3
            text.content = service.label
            apply_theme_to_text(text)
            text.text_anchor = "middle"
            text.dominant_baseline = "middle"
            text.font_size = "12"
          end

          g.children << label
        end

        svg << g
      end

      def render_edges(layout, svg)
        layout[:edges].each do |edge_info|
          render_edge(edge_info, svg)
        end
      end

      def render_edge(edge_info, svg)
        edge = edge_info[:edge]
        from_x = edge_info[:from_x]
        from_y = edge_info[:from_y]
        to_x = edge_info[:to_x]
        to_y = edge_info[:to_y]

        # Create edge group
        g = Svg::Group.new.tap do |elem|
          elem.id = "edge-#{edge.from_id}-#{edge.to_id}"
        end

        # Calculate path
        path_data = calculate_edge_path(from_x, from_y, to_x, to_y)

        # Draw connection line
        path = Svg::Path.new.tap do |p|
          p.d = path_data
          p.fill = "none"
          apply_theme_to_edge(p)
          p.marker_end = "url(#arrowhead)"
        end

        g.children << path

        # Draw edge label if present
        if edge.label && !edge.label.empty?
          mid_x = (from_x + to_x) / 2
          mid_y = (from_y + to_y) / 2

          label = Svg::Text.new.tap do |text|
            text.x = mid_x
            text.y = mid_y - 5
            text.content = edge.label
            text.font_size = "10"
            text.text_anchor = "middle"
            text.fill = theme_color(:text_color) || "#666"
          end

          g.children << label
        end

        svg << g
      end

      def calculate_edge_path(from_x, from_y, to_x, to_y)
        # Use simple straight line for now
        # Could be enhanced with bezier curves or orthogonal routing
        "M #{from_x} #{from_y} L #{to_x} #{to_y}"
      end

      def icon_glyph(icon_name)
        # Extract base icon name (remove prefixes like "logos:" or "fa:")
        base_name = icon_name.split(":").last

        # Map to glyph or use first letter as fallback
        ICON_GLYPHS[base_name] || base_name[0].upcase
      end

      def calculate_width(layout)
        layout[:width] || 800
      end

      def calculate_height(layout)
        layout[:height] || 600
      end
    end
  end
end