# frozen_string_literal: true

require_relative "base"
require_relative "../layout/flowchart"

module Sirena
  module Renderer
    # Emits SVG from final, typed flowchart geometry.
    class Flowchart < Base
      LINK_THICK_MULTIPLE = 3.5
      LINK_DOTTED_DASHES = "2"
      CIRCLE_HEAD_STROKE = "1"
      CROSS_HEAD_STROKE = "2"

      private_constant :LINK_THICK_MULTIPLE, :LINK_DOTTED_DASHES,
                       :CIRCLE_HEAD_STROKE, :CROSS_HEAD_STROKE

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
        group.children << cluster_title(cluster.labels.first) if cluster.labels.any?
        svg << group
      end

      def cluster_box(cluster)
        Svg::Rect.new.tap do |rect|
          rect.x = cluster.shape_x
          rect.y = cluster.shape_y
          rect.width = cluster.shape_width
          rect.height = cluster.shape_height
          rect.rx = cluster.corner_radius
          rect.ry = cluster.corner_radius
          apply_theme_to_cluster(rect)
        end
      end

      def cluster_title(label)
        Svg::Text.new.tap do |text|
          text.x = label.x
          text.y = label.y
          text.content = label.text
          apply_theme_to_text(text)
          text.text_anchor = "middle"
          text.dominant_baseline = "middle"
        end
      end

      def apply_theme_to_cluster(element)
        element.fill = theme_color(:surface_variant) if theme_color(:surface_variant)
        element.stroke = theme_color(:node_stroke) if theme_color(:node_stroke)
        element.stroke_width = theme_shape(:stroke_width).to_s if theme_shape(:stroke_width)
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
        group.children << node_label(node.labels.first) if node.labels.any?
        svg << group
      end

      def node_shape(node)
        case node.shape_kind
        when "rounded" then rounded_rectangle(node)
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
          text.content = label.text
          apply_theme_to_text(text)
          text.text_anchor = "middle"
          text.dominant_baseline = "middle"
        end
      end

      def render_edge(edge, svg)
        group = Svg::Group.new.tap { |item| item.id = "edge-#{edge.id}" }
        group.children << edge_path(edge)
        edge.heads.each { |head| group.children.concat(head_elements(head)) }
        group.children << edge_label(edge.labels.first) if edge.labels.any?
        svg << group
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
        head.lines.map do |geometry|
          Svg::Line.new.tap do |line|
            line.x1 = geometry.x1
            line.y1 = geometry.y1
            line.x2 = geometry.x2
            line.y2 = geometry.y2
            line.stroke = edge_ink
            line.stroke_width = CROSS_HEAD_STROKE
          end
        end
      end

      def edge_ink
        theme_color(:edge_stroke)
      end

      def edge_label(label)
        Svg::Text.new.tap do |text|
          text.x = label.x
          text.y = label.y
          text.content = label.text
          apply_theme_to_text(text)
          if theme_typography(:font_size_small)
            text.font_size = theme_typography(:font_size_small).to_s
          end
          text.text_anchor = "middle"
        end
      end
    end
  end
end
