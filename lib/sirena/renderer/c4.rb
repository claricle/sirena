# frozen_string_literal: true

require_relative "base"
require_relative "../layout/c4"

module Sirena
  module Renderer
    # Emits SVG from final, typed C4 geometry.
    class C4 < Base
      C4_COLOR_ROLES = {
        person: { bg: :primary, border: :edge_stroke, text: :background },
        person_ext: { bg: :secondary, border: :edge_stroke,
                      text: :background },
        system: { bg: :primary, border: :edge_stroke, text: :background },
        system_ext: { bg: :secondary, border: :edge_stroke,
                      text: :background },
        container: { bg: :primary, border: :edge_stroke,
                     text: :background },
        component: { bg: :surface_variant, border: :node_stroke,
                     text: :foreground },
        boundary: { bg: :background, border: :node_stroke,
                    text: :foreground },
      }.freeze

      # @param scene [Layout::C4::Scene] final canvas geometry
      # @return [Svg::Document] rendered SVG document
      def render(scene)
        svg = create_document(scene)
        render_boundaries(scene.children, svg)
        scene.edges.each { |edge| render_relationship(edge, svg) }
        render_elements(scene.children, svg)
        add_title(svg, scene.title)
        svg
      end

      protected

      # Keeps the scene's own view box: the title shifts its origin above 0.
      def create_document(scene, overflow: nil)
        super.tap do |svg|
          svg.view_box = scene.view_box if scene.view_box
        end
      end

      def render_boundaries(nodes, svg)
        nodes.each do |node|
          next unless node.kind == "boundary"

          svg << boundary_group(node) if positioned?(node)
          render_boundaries(node.children, svg)
        end
      end

      def boundary_group(node)
        Svg::Group.new.tap do |group|
          group.id = "boundary-#{node.id}"
          group.children << boundary_rect(node)
          unless node.labels.empty?
            group.children << label_element(node.labels.first,
                                            element_colours(node)[:text])
          end
        end
      end

      def boundary_rect(node)
        colours = element_colours(node)
        Svg::Rect.new.tap do |rect|
          apply_box(rect, node)
          rect.fill = colours[:bg]
          rect.stroke = colours[:border]
          rect.stroke_width = "2"
          rect.stroke_dasharray = "10,5"
          rect.rx = 8
          rect.ry = 8
        end
      end

      def render_elements(nodes, svg)
        nodes.each do |node|
          if node.kind == "boundary"
            render_elements(node.children, svg)
          elsif positioned?(node)
            svg << element_group(node)
          end
        end
      end

      def element_group(node)
        Svg::Group.new.tap do |group|
          group.id = "element-#{node.id}"
          colours = element_colours(node)
          group.children << element_box(node, colours)
          add_person_icon(group, node, colours) if node.kind == "person"
          add_stereotype(group, node, colours)
          node.labels.each do |label|
            group.children << label_element(label, colours[:text])
          end
        end
      end

      def add_title(svg, title)
        svg << label_element(title, theme_color(:foreground)) if title
      end

      def add_stereotype(group, node, colours)
        return unless node.stereotype

        group.children << label_element(node.stereotype, colours[:text])
      end

      def element_colours(node)
        key = case node.kind
              when "person" then node.external ? :person_ext : :person
              when "system" then node.external ? :system_ext : :system
              else node.kind.to_sym
              end
        C4_COLOR_ROLES.fetch(key).transform_values { |role| theme_color(role) }
      end

      def element_box(node, colours)
        case node.shape
        when "database" then database_shape(node, colours)
        when "queue" then queue_shape(node, colours)
        else plain_box(node, colours)
        end
      end

      # mmdc draws a database as a cylinder whose caps lie outside the box.
      def database_shape(node, colours)
        half = node.width / 2
        x = node.x
        y = node.y
        body = "M#{x},#{y}c0,-10 #{half},-10 #{half},-10c0,0 #{half},0 " \
               "#{half},10l0,#{node.height}c0,10 -#{half},10 -#{half},10" \
               "c0,0 -#{half},0 -#{half},-10l0,-#{node.height}"
        rim = "M#{x},#{y}c0,10 #{half},10 #{half},10c0,0 #{half},0 " \
              "#{half},-10"
        shape_group(body, rim, colours)
      end

      # mmdc draws a queue as a pill whose end caps lie outside the box.
      def queue_shape(node, colours)
        half = node.height / 2
        x = node.x
        y = node.y
        body = "M#{x},#{y}l#{node.width},0c5,0 5,#{half} 5,#{half}" \
               "c0,0 0,#{half} -5,#{half}l-#{node.width},0" \
               "c-5,0 -5,-#{half} -5,-#{half}c0,0 0,-#{half} 5,-#{half}"
        rim = "M#{x + node.width},#{y}c-5,0 -5,#{half} -5,#{half}" \
              "c0,#{half} 5,#{half} 5,#{half}"
        shape_group(body, rim, colours)
      end

      def shape_group(body, rim, colours)
        Svg::Group.new.tap do |group|
          group.children << shape_path(body, colours[:bg], colours)
          group.children << shape_path(rim, "none", colours)
        end
      end

      def shape_path(data, fill, colours)
        Svg::Path.new.tap do |path|
          path.d = data
          path.fill = fill
          path.stroke = colours[:border]
          path.stroke_width = "2"
        end
      end

      def plain_box(node, colours)
        Svg::Rect.new.tap do |rect|
          apply_box(rect, node)
          rect.fill = colours[:bg]
          rect.stroke = colours[:border]
          rect.stroke_width = "2"
          rect.rx = node.kind == "person" ? 10 : 5
          rect.ry = node.kind == "person" ? 10 : 5
        end
      end

      def add_person_icon(group, node, colours)
        group.children << person_head(node, colours[:text])
        group.children << person_body(node, colours[:text])
      end

      def person_head(node, colour)
        Svg::Circle.new.tap do |circle|
          circle.cx = node.head_center.x
          circle.cy = node.head_center.y
          circle.r = 10
          circle.fill = colour
        end
      end

      def person_body(node, colour)
        Svg::Ellipse.new.tap do |ellipse|
          ellipse.cx = node.body_center.x
          ellipse.cy = node.body_center.y
          ellipse.rx = 18
          ellipse.ry = 12
          ellipse.fill = colour
        end
      end

      def label_element(label, colour)
        Svg::Text.new.tap do |text|
          text.x = label.x
          text.y = label.y
          text.content = label.text
          text.fill = colour
          style_label(text, label)
        end
      end

      def style_label(text, label)
        text.font_family = "Arial, sans-serif"
        text.font_size = label.font_size.to_s
        text.font_weight = label.font_weight
        text.font_style = label.font_style
        text.dominant_baseline = label.baseline
        text.text_anchor = "middle" unless label.font_size == 16
      end

      def render_relationship(edge, svg)
        section = edge.sections.first
        group = Svg::Group.new.tap { |item| item.id = edge.id }
        group.children << relationship_stroke(section)
        edge.arrowheads.each do |points|
          group.children << arrowhead(points)
        end
        edge.labels.each do |label|
          group.children << label_element(label, theme_color(:label_text))
        end
        svg << group
      end

      def relationship_stroke(section)
        control = section.bend_points.first
        return relationship_curve(section, control) if control

        relationship_line(section.start_point, section.end_point)
      end

      def relationship_curve(section, control)
        start_point = section.start_point
        end_point = section.end_point
        Svg::Path.new.tap do |path|
          path.d = "M#{start_point.x},#{start_point.y} " \
                   "Q#{control.x},#{control.y} #{end_point.x},#{end_point.y}"
          path.fill = "none"
          path.stroke = theme_color(:edge_stroke)
          path.stroke_width = "2"
        end
      end

      def relationship_line(start_point, end_point)
        Svg::Line.new.tap do |line|
          line.x1 = start_point.x
          line.y1 = start_point.y
          line.x2 = end_point.x
          line.y2 = end_point.y
          line.stroke = theme_color(:edge_stroke)
          line.stroke_width = "2"
        end
      end

      def arrowhead(points)
        Svg::Polygon.new.tap do |polygon|
          polygon.points = points
          polygon.fill = theme_color(:edge_stroke)
          polygon.stroke = theme_color(:edge_stroke)
        end
      end

      def apply_box(rect, node)
        rect.x = node.x
        rect.y = node.y
        rect.width = node.width
        rect.height = node.height
      end

      def positioned?(node)
        !node.x.nil? && !node.y.nil?
      end
    end
  end
end
