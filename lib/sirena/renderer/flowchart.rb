# frozen_string_literal: true

require_relative "base"
require_relative "../layout/flowchart"
require_relative "line_break_text"

module Sirena
  module Renderer
    # Emits SVG from final, typed flowchart geometry.
    class Flowchart < Base
      LINK_THICK_MULTIPLE = 3.5
      LINK_DOTTED_DASHES = "2"
      CIRCLE_HEAD_STROKE = "1"
      CROSS_HEAD_STROKE = "2"
      # How far below the middle of a line its baseline sits, in ems.
      MIDDLE_BASELINE_EMS = 0.35

      private_constant :LINK_THICK_MULTIPLE, :LINK_DOTTED_DASHES,
                       :CIRCLE_HEAD_STROKE, :CROSS_HEAD_STROKE,
                       :MIDDLE_BASELINE_EMS

      # @param scene [Layout::Flowchart::Scene] final canvas geometry
      # @return [Svg::Document] rendered SVG document
      def render(scene)
        svg = create_document(scene, overflow: "hidden")

        # Mermaid paints cluster surfaces first, then edges, then nodes.
        render_clusters(scene.children, svg)
        scene.edges.each { |edge| render_edge(edge, svg) }
        render_nodes(scene.children, svg)

        svg
      end

      protected

      def render_clusters(nodes, svg)
        nodes.each do |node|
          render_cluster(node, svg) if node.cluster
          render_clusters(node.children, svg)
        end
      end

      def render_cluster(cluster, svg)
        group = Svg::Group.new.tap { |item| item.id = "cluster-#{cluster.id}" }
        group.children << cluster_box(cluster)
        append_cluster_title(group, cluster)
        svg << group
      end

      def append_cluster_title(group, cluster)
        return if cluster.labels.empty?

        group.children << cluster_title(cluster.labels.first)
      end

      def cluster_box(cluster)
        Svg::Rect.new.tap do |rect|
          assign_cluster_geometry(rect, cluster)
          apply_theme_to_cluster(rect)
        end
      end

      def assign_cluster_geometry(rect, cluster)
        rect.x = cluster.shape_x
        rect.y = cluster.shape_y
        rect.width = cluster.shape_width
        rect.height = cluster.shape_height
        rect.rx = cluster.corner_radius
        rect.ry = cluster.corner_radius
      end

      def cluster_title(label)
        Svg::Text.new.tap do |text|
          text.x = label.x
          text.y = label.y
          text.content = label.text
          apply_flowchart_text_style(text)
          text.text_anchor = "middle"
          text.dominant_baseline = "middle"
        end
      end

      # A label of several lines is one <text> of <tspan>s, centred on the
      # node. Each line but the last ends in a space so the label still reads
      # as one sentence. The baselines are set here, not asked of
      # `dominant-baseline`, which would move the first line only.
      def fill_node_lines(text, label)
        lines = label.text.to_s.split("\n", -1)
        return text.content = label.text if lines.one?

        pitch = label.height / lines.size
        text.dominant_baseline = nil
        text.y = first_baseline(label, lines.size, pitch, text.font_size)
        spaced = lines[0...-1].map { |line| "#{line} " } << lines.last
        LineBreakText.fill_lines(text, spaced, pitch: pitch)
      end

      def first_baseline(label, count, pitch, font_size)
        top = label.y - (pitch * (count - 1) / 2.0)
        top + (MIDDLE_BASELINE_EMS * font_size.to_f)
      end

      def apply_theme_to_cluster(element)
        if theme_color(:surface_variant)
          element.fill = theme_color(:surface_variant)
        end
        element.stroke = theme_color(:node_stroke) if theme_color(:node_stroke)
        if theme_shape(:stroke_width)
          element.stroke_width = theme_shape(:stroke_width).to_s
        end
      end

      def render_nodes(nodes, svg)
        nodes.each do |node|
          render_node(node, svg) unless node.container
          render_nodes(node.children, svg)
        end
      end

      def render_node(node, svg)
        group = Svg::Group.new.tap { |item| item.id = "node-#{node.id}" }
        group.children << node_shape(node)
        append_node_label(group, node)
        svg << group
      end

      def append_node_label(group, node)
        return if node.labels.empty?

        group.children << node_label(node.labels.first)
      end

      def node_shape(node)
        case node.shape_kind
        when "rounded", "stadium" then rounded_rectangle(node)
        when "circle" then circle(node)
        when "rhombus", "hexagon" then polygon(node)
        else rectangle(node)
        end
      end

      def rectangle(node)
        Svg::Rect.new.tap do |rect|
          rect.x = node.shape_x
          rect.y = node.shape_y
          rect.width = node.shape_width
          rect.height = node.shape_height
          apply_theme_to_node(rect)
        end
      end

      def rounded_rectangle(node)
        rectangle(node).tap do |rect|
          rect.rx = node.corner_radius
          rect.ry = node.corner_radius
        end
      end

      def circle(node)
        Svg::Circle.new.tap do |item|
          item.cx = node.center_x
          item.cy = node.center_y
          item.r = node.radius
          apply_theme_to_node(item)
        end
      end

      def polygon(node)
        Svg::Polygon.new.tap do |item|
          item.points = node.shape_points
          apply_theme_to_node(item)
        end
      end

      def node_label(label)
        Svg::Text.new.tap do |text|
          text.x = label.x
          text.y = label.y
          apply_flowchart_text_style(text)
          text.text_anchor = "middle"
          text.dominant_baseline = "middle"
          fill_node_lines(text, label)
        end
      end

      def render_edge(edge, svg)
        svg << edge_group(edge)
      end

      def edge_group(edge)
        Svg::Group.new.tap do |group|
          group.id = "edge-#{edge.id}"
          append_edge_geometry(group, edge)
        end
      end

      def append_edge_geometry(group, edge)
        group.children << edge_path(edge)
        edge.heads.each { |head| group.children.concat(head_elements(head)) }
        append_edge_label(group, edge)
      end

      def append_edge_label(group, edge)
        return if edge.labels.empty?

        group.children << edge_label(edge.labels.first)
      end

      def edge_path(edge)
        Svg::Path.new.tap do |path|
          path.d = edge.path
          path.fill = "none"
          apply_theme_to_edge(path)
          apply_link_weight(path, edge.arrow_type)
          path.stroke = "none" if edge.arrow_type == "invisible"
        end
      end

      def apply_link_weight(path, type)
        path.stroke_width = thick_width.to_s if type.start_with?("thick_")
        path.stroke_dasharray = dotted_dashes if type.start_with?("dotted_")
      end

      def thick_width
        theme_shape(:stroke_width_thick) ||
          ((theme_shape(:stroke_width) || 1.0) * LINK_THICK_MULTIPLE)
      end

      def dotted_dashes
        theme_shape(:dash_pattern_dotted) || LINK_DOTTED_DASHES
      end

      def head_elements(head)
        case head.shape
        when "cross" then cross_head(head)
        when "circle" then [circle_head(head)]
        else [arrow_head(head)]
        end
      end

      def arrow_head(head)
        Svg::Polygon.new.tap do |polygon|
          polygon.points = head.points
          polygon.fill = edge_ink || "none"
          polygon.stroke = edge_ink
        end
      end

      def circle_head(head)
        Svg::Circle.new.tap do |circle|
          circle.cx = head.x
          circle.cy = head.y
          circle.r = head.radius
          circle.fill = edge_ink || "none"
          circle.stroke = edge_ink
          circle.stroke_width = CIRCLE_HEAD_STROKE
        end
      end

      def cross_head(head)
        head.lines.map { |geometry| cross_line(geometry) }
      end

      def cross_line(geometry)
        Svg::Line.new.tap do |line|
          line.x1 = geometry.x1
          line.y1 = geometry.y1
          line.x2 = geometry.x2
          line.y2 = geometry.y2
          line.stroke = edge_ink
          line.stroke_width = CROSS_HEAD_STROKE
        end
      end

      def edge_ink
        theme_color(:edge_stroke)
      end

      def edge_label(label)
        Svg::Text.new.tap do |text|
          assign_edge_label_geometry(text, label)
          apply_flowchart_text_style(text)
          text.text_anchor = "middle"
        end
      end

      def assign_edge_label_geometry(text, label)
        text.x = label.x
        text.y = label.y
        text.content = label.text
      end

      def apply_flowchart_text_style(text)
        apply_theme_to_text(text)
        text.font_size = Layout::Flowchart.font_size(theme).to_s
      end
    end
  end
end
