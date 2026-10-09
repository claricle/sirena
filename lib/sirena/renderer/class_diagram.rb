# frozen_string_literal: true

require_relative "base"
require_relative "../diagram/generic_text"
require_relative "../layout/class_diagram"

module Sirena
  module Renderer
    # Class diagram renderer for converting graphs to SVG.
    #
    # Converts a laid-out graph structure (with computed positions) into
    # SVG using the Svg builder classes. Handles UML class boxes with
    # compartments, various relationship types with appropriate arrow
    # styles, and cardinality labels.
    #
    # @example Render a class diagram
    #   renderer = ClassDiagram.new
    #   svg = renderer.render(laid_out_graph)
    class ClassDiagram < Base
      # Font size for class names
      CLASS_NAME_FONT_SIZE = 16

      # Font size for attributes and methods
      MEMBER_FONT_SIZE = 12

      # Font size for stereotypes
      STEREOTYPE_FONT_SIZE = 11

      # Line height for text
      LINE_HEIGHT = 18

      # Padding within class boxes
      BOX_PADDING = 10

      # Arrow/marker dimensions
      ARROW_SIZE = Layout::ClassDiagram::ARROW_SIZE
      DIAMOND_SIZE = Layout::ClassDiagram::DIAMOND_SIZE

      # Dependency marker (dart) dimensions, matching mermaid's own
      # `M 5,7 L9,13 L1,7 L9,1 Z`: a CONCAVE dart, not a convex kite --
      # (1,7) is the tip, (9,13)/(9,1) are the back corners, and (5,7) is
      # a reflex notch midway between the tip and the back edge. Building
      # this as a convex 4-point shape collapses the notch onto the back
      # edge and silently degenerates to a triangle -- keep the notch
      # derived as the midpoint of tip and back in the layout's dart geometry,
      # never a separate offset. DART_NEAR/DART_FAR set the tip-close/
      # back-far asymmetry; DART_WIDTH is the half-width of the back edge.
      DART_NEAR = Layout::ClassDiagram::DART_NEAR
      DART_FAR = Layout::ClassDiagram::DART_FAR
      DART_WIDTH = Layout::ClassDiagram::DART_WIDTH

      # Renders final class-diagram geometry to SVG. Hash support remains for
      # released callers; Engine always supplies the typed Scene.
      #
      # @param graph [Layout::ClassDiagram::Scene, Hash] final geometry or a
      #   released legacy graph
      # @return [Svg::Document] the rendered SVG document
      def render(graph)
        return render_scene(graph) if graph.is_a?(Layout::ClassDiagram::Scene)

        svg = create_document(graph)

        # Add marker definitions
        add_markers(svg)

        # Render edges first (so they appear under nodes)
        render_relationships(graph, svg) if graph[:edges]

        # Render class boxes
        render_classes(graph, svg) if graph[:children]

        svg
      end

      def render_scene(scene)
        svg = scene_document(scene)
        add_markers(svg)
        render_relationships(scene, svg)
        render_classes(scene, svg)
        svg
      end

      protected

      def scene_document(scene)
        Svg::Document.new.tap do |svg|
          svg.width = svg_number(scene.width)
          svg.height = svg_number(scene.height)
          svg.view_box = scene.view_box
        end
      end

      def render_scene_node(node, svg)
        group = Svg::Group.new.tap { |item| item.id = "class-#{node.id}" }
        group.children << scene_node_box(node)
        group.children << scene_text(node.stereotype) if node.stereotype
        group.children << scene_text(node.name)
        group.children << scene_separator(node.separators.first)
        node.attributes.each { |label| group.children << scene_text(label) }
        if node.separators.length > 1
          group.children << scene_separator(node.separators.last)
        end
        node.method_rows.each { |label| group.children << scene_text(label) }
        svg << group
      end

      def scene_node_box(node)
        Svg::Rect.new(
          x: svg_number(node.x), y: svg_number(node.y),
          width: svg_number(node.width), height: svg_number(node.height),
          fill: "#ffffff", stroke: "#000000", stroke_width: "2",
          rx: 3, ry: 3
        )
      end

      def scene_separator(separator)
        Svg::Line.new(
          x1: svg_number(separator.x1),
          y1: svg_number(separator.y1),
          x2: svg_number(separator.x2),
          y2: svg_number(separator.y2),
          stroke: "#000000",
          stroke_width: "1",
        )
      end

      def scene_text(label)
        Svg::Text.new(
          x: svg_number(label.x),
          y: svg_number(label.y),
          content: label.text,
          fill: "#000000",
          font_family: label.font_family,
          font_size: svg_number(label.font_size).to_s,
          text_anchor: label.text_anchor,
          font_weight: label.font_weight,
        )
      end

      def render_scene_edge(edge, svg)
        group = Svg::Group.new.tap { |item| item.id = "rel-#{edge.id}" }
        edge.sections.each do |section|
          group.children << scene_edge_section(section, edge.dashed)
        end
        edge.markers.each { |marker| group.children << scene_marker(marker) }
        edge.labels.each { |label| group.children << scene_text(label) }
        svg << group
      end

      def scene_edge_section(section, dashed)
        return scene_edge_line(section, dashed) if section.bend_points.empty?

        Svg::Path.new(
          d: section_path(section), fill: "none", stroke: "#000000",
          stroke_width: "2", stroke_dasharray: dashed ? "5,5" : nil
        )
      end

      def section_path(section)
        points = [section.start_point, *section.bend_points, section.end_point]
        points.map.with_index do |point, index|
          command = index.zero? ? "M" : "L"
          "#{command} #{svg_number(point.x)} #{svg_number(point.y)}"
        end.join(" ")
      end

      def scene_edge_line(section, dashed)
        Svg::Line.new(
          x1: svg_number(section.start_point.x),
          y1: svg_number(section.start_point.y),
          x2: svg_number(section.end_point.x),
          y2: svg_number(section.end_point.y),
          stroke: "#000000",
          stroke_width: "2",
          stroke_dasharray: dashed ? "5,5" : nil,
        )
      end

      def scene_marker(marker)
        Svg::Polygon.new.tap do |polygon|
          polygon.points = marker.points
          polygon.fill = marker.fill
          polygon.stroke = "#000000"
          polygon.stroke_width = "2"
        end
      end

      def svg_number(value)
        value.to_i == value ? value.to_i : value
      end

      def calculate_width(graph)
        return 800 unless graph[:children]

        max_x = graph[:children].map do |node|
          (node[:x] || 0) + (node[:width] || 150)
        end.max || 800

        max_x + 40
      end

      def calculate_height(graph)
        return 600 unless graph[:children]

        max_y = graph[:children].map do |node|
          (node[:y] || 0) + (node[:height] || 100)
        end.max || 600

        max_y + 40
      end

      def add_markers(svg)
        # Add definitions for various arrow types
        defs = Svg::Group.new
        defs.id = "defs"

        # Inheritance marker (hollow triangle)
        add_inheritance_marker(defs)

        # Composition marker (filled diamond)
        add_composition_marker(defs)

        # Aggregation marker (hollow diamond)
        add_aggregation_marker(defs)

        svg << defs
      end

      def add_inheritance_marker(defs)
        # This will be rendered as a hollow triangle in render_relationship
      end

      def add_composition_marker(defs)
        # This will be rendered as a filled diamond in render_relationship
      end

      def add_aggregation_marker(defs)
        # This will be rendered as a hollow diamond in render_relationship
      end

      def render_classes(graph, svg)
        if graph.is_a?(Layout::ClassDiagram::Scene)
          graph.children.each { |node| render_scene_node(node, svg) }
          return
        end

        graph[:children].each do |node|
          render_class(node, svg)
        end
      end

      def render_class(node, svg)
        x = node[:x] || 0
        y = node[:y] || 0
        width = node[:width] || 150
        height = node[:height] || 100

        metadata = node[:metadata] || {}

        # Create group for the class
        group = Svg::Group.new.tap do |g|
          g.id = "class-#{node[:id]}"
        end

        # Render outer box
        box = Svg::Rect.new.tap do |r|
          r.x = x
          r.y = y
          r.width = width
          r.height = height
          r.fill = "#ffffff"
          r.stroke = "#000000"
          r.stroke_width = "2"
          r.rx = 3
          r.ry = 3
        end
        group.children << box

        # Render compartment separators and content
        render_class_content(node, metadata, group)

        svg << group
      end

      def render_class_content(node, metadata, group)
        x = node[:x] || 0
        y = node[:y] || 0
        width = node[:width] || 150

        current_y = y + BOX_PADDING

        # Render stereotype if present
        stereotype = metadata[:stereotype]
        current_y = render_stereotype(x, current_y, width, stereotype, group) if stereotype && !stereotype.empty?

        # Render class name
        name = metadata[:name] || node[:id]
        current_y = render_class_name(x, current_y, width, name, group)

        # Add separator after name
        separator_y = current_y + 5
        separator = Svg::Line.new.tap do |l|
          l.x1 = x
          l.y1 = separator_y
          l.x2 = x + width
          l.y2 = separator_y
          l.stroke = "#000000"
          l.stroke_width = "1"
        end
        group.children << separator
        current_y = separator_y + 10

        # Render attributes
        attributes = metadata[:attributes] || []
        unless attributes.empty?
          current_y = render_attributes(x, current_y, width, attributes, group)

          # Add separator after attributes
          separator_y = current_y + 5
          separator = Svg::Line.new.tap do |l|
            l.x1 = x
            l.y1 = separator_y
            l.x2 = x + width
            l.y2 = separator_y
            l.stroke = "#000000"
            l.stroke_width = "1"
          end
          group.children << separator
          current_y = separator_y + 10
        end

        # Render methods
        methods = metadata[:methods] || []
        render_methods(x, current_y, width, methods, group) unless
          methods.empty?
      end

      def render_stereotype(x, y, width, stereotype, group)
        text = Svg::Text.new.tap do |t|
          t.x = x + width / 2
          t.y = y
          t.content = "«#{stereotype}»"
          t.fill = "#000000"
          t.font_family = "Arial, sans-serif"
          t.font_size = STEREOTYPE_FONT_SIZE.to_s
          t.text_anchor = "middle"
        end
        group.children << text
        y + LINE_HEIGHT
      end

      def render_class_name(x, y, width, name, group)
        text = Svg::Text.new.tap do |t|
          t.x = x + width / 2
          t.y = y
          t.content = Diagram::GenericText.display(name)
          t.fill = "#000000"
          t.font_family = "Arial, sans-serif"
          t.font_size = CLASS_NAME_FONT_SIZE.to_s
          t.text_anchor = "middle"
          t.font_weight = "bold"
        end
        group.children << text
        y + LINE_HEIGHT
      end

      def render_attributes(x, y, _width, attributes, group)
        current_y = y

        attributes.each do |attr|
          text = Svg::Text.new.tap do |t|
            t.x = x + BOX_PADDING
            t.y = current_y
            t.content = attr[:text]
            t.fill = "#000000"
            t.font_family = "monospace"
            t.font_size = MEMBER_FONT_SIZE.to_s
          end
          group.children << text
          current_y += LINE_HEIGHT
        end

        current_y
      end

      def render_methods(x, y, _width, methods, group)
        current_y = y

        methods.each do |method|
          text = Svg::Text.new.tap do |t|
            t.x = x + BOX_PADDING
            t.y = current_y
            t.content = method[:text]
            t.fill = "#000000"
            t.font_family = "monospace"
            t.font_size = MEMBER_FONT_SIZE.to_s
          end
          group.children << text
          current_y += LINE_HEIGHT
        end

        current_y
      end

      # Released protected hook retained for callers that format legacy rows.
      def visibility_symbol(visibility)
        {
          "public" => "+",
          "private" => "-",
          "protected" => "#",
          "package" => "~",
        }.fetch(visibility, "+")
      end

      def render_relationships(graph, svg)
        if graph.is_a?(Layout::ClassDiagram::Scene)
          graph.edges.each { |edge| render_scene_edge(edge, svg) }
          return
        end

        graph[:edges].each do |edge|
          render_relationship(edge, graph, svg)
        end
      end

      def render_relationship(edge, graph, svg)
        source = find_node(graph, edge[:sources]&.first)
        target = find_node(graph, edge[:targets]&.first)

        return unless source && target

        metadata = edge[:metadata] || {}
        rel_type = metadata[:relationship_type] || "association"

        # Create group for the relationship
        group = Svg::Group.new.tap do |g|
          g.id = "rel-#{edge[:id]}"
        end

        # Calculate connection points
        source_point = calculate_connection_point(source, target)
        target_point = calculate_connection_point(target, source)

        if metadata[:start_marker] || metadata[:end_marker]
          # Mixed-marker operator (e.g. `o--|>`): each end carries its own
          # marker independently, so relationship_type alone can't drive
          # rendering here.
          render_mixed_marker_relationship(source_point, target_point, metadata, group)
        else
          # Render the line
          render_relationship_line(source_point, target_point, rel_type, group)

          # Render arrow/marker at target
          render_relationship_marker(source_point, target_point, rel_type, group)
        end

        # Render labels if present
        render_relationship_labels(edge, source_point, target_point, group)

        svg << group
      end

      def find_node(graph, node_id)
        return nil unless graph[:children] && node_id

        graph[:children].find { |n| n[:id] == node_id }
      end

      def calculate_connection_point(from_node, to_node)
        Layout::ClassDiagram.connection_point(from_node, to_node)
      end

      def render_relationship_line(from, to, rel_type, group)
        line = Svg::Line.new.tap do |l|
          l.x1 = from[:x]
          l.y1 = from[:y]
          l.x2 = to[:x]
          l.y2 = to[:y]
          l.stroke = "#000000"
          l.stroke_width = "2"
          l.stroke_dasharray = "5,5" if rel_type == "dependency"
        end
        group.children << line
      end

      def render_relationship_marker(from, to, rel_type, group)
        case rel_type
        when "inheritance", "realization"
          render_triangle_marker(from, to, rel_type == "inheritance", group)
        when "composition"
          render_diamond_marker(from, to, true, group)
        when "aggregation"
          render_diamond_marker(from, to, false, group)
        end
      end

      def render_mixed_marker_relationship(source_point, target_point, metadata, group)
        line = Svg::Line.new.tap do |l|
          l.x1 = source_point[:x]
          l.y1 = source_point[:y]
          l.x2 = target_point[:x]
          l.y2 = target_point[:y]
          l.stroke = "#000000"
          l.stroke_width = "2"
          l.stroke_dasharray = "5,5" if metadata[:dashed]
        end
        group.children << line

        render_marker_at(source_point, target_point, metadata[:start_marker], group)
        render_marker_at(target_point, source_point, metadata[:end_marker], group)
      end

      # Draws `marker` at `point`, oriented along the connecting line away
      # from `away_from`. A triangle tip lands exactly at `point`; a diamond
      # straddles `point` (half on each side) with its outer tip toward
      # `away_from`; a dart sits entirely on the `away_from` side of `point`
      # (DART_NEAR/DART_FAR, both positive offsets) so it never digs back
      # into the node at `point` -- see render_dart_marker.
      def render_marker_at(point, away_from, marker, group)
        case marker
        when "inheritance"
          # mermaid's classDiagram CSS renders extension/inheritance markers
          # with `fill: transparent !important` -- a hollow triangle, not the
          # filled one the single-type inheritance path draws.
          render_triangle_marker(away_from, point, false, group)
        when "dependency"
          # mermaid renders the dependency marker filled (`fill: lineColor`)
          # as a concave dart -- see DART_NEAR/DART_FAR/DART_WIDTH above.
          render_dart_marker(point, away_from, group)
        when "composition"
          render_diamond_marker(point, away_from, true, group)
        when "aggregation"
          render_diamond_marker(point, away_from, false, group)
        end
      end

      def render_triangle_marker(from, to, filled, group)
        marker = Layout::ClassDiagram.triangle_marker(from, to, filled)
        group.children << scene_marker(marker)
      end

      # A filled dart anchored at `from`, sitting entirely on the `to` side
      # of `from` -- same convention render_triangle_marker already uses --
      # so the whole shape stays outside the node at `from` instead of
      # digging back into it: a short tip touches near `from`, a wider back
      # edge sits further out toward `to`, and the notch is the reflex
      # vertex on the tip-to-back axis, midway between them -- see
      # DART_NEAR/DART_FAR/DART_WIDTH.
      def render_dart_marker(from, to, group)
        marker = Layout::ClassDiagram.dart_marker(from, to)
        group.children << scene_marker(marker)
      end

      def render_diamond_marker(from, to, filled, group)
        marker = Layout::ClassDiagram.diamond_marker(from, to, filled)
        group.children << scene_marker(marker)
      end

      def render_relationship_labels(edge, from, to, group)
        labels = edge[:labels] || []
        return if labels.empty?

        # Main label in the middle
        main_label = labels.find { |l| !l[:position] }
        if main_label
          mid_x = (from[:x] + to[:x]) / 2
          mid_y = (from[:y] + to[:y]) / 2

          text = Svg::Text.new.tap do |t|
            t.x = mid_x
            t.y = mid_y - 5
            t.content = main_label[:text]
            t.fill = "#000000"
            t.font_family = "Arial, sans-serif"
            t.font_size = "11"
            t.text_anchor = "middle"
          end
          group.children << text
        end

        # Source cardinality
        source_label = labels.find { |l| l[:position] == "source" }
        if source_label
          text = Svg::Text.new.tap do |t|
            t.x = from[:x] + 5
            t.y = from[:y] - 5
            t.content = source_label[:text]
            t.fill = "#000000"
            t.font_family = "Arial, sans-serif"
            t.font_size = "10"
          end
          group.children << text
        end

        # Target cardinality
        target_label = labels.find { |l| l[:position] == "target" }
        return unless target_label

        text = Svg::Text.new.tap do |t|
          t.x = to[:x] - 5
          t.y = to[:y] - 5
          t.content = target_label[:text]
          t.fill = "#000000"
          t.font_family = "Arial, sans-serif"
          t.font_size = "10"
          t.text_anchor = "end"
        end
        group.children << text
      end
    end
  end
end
