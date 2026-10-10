# frozen_string_literal: true

require_relative "base"
require_relative "../diagram/generic_text"
require_relative "../layout/class_diagram"
require_relative "line_break_text"

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

      # Gap between the lines of a note, as mmdc draws them
      NOTE_LINE_HEIGHT = Layout::ClassNoteNodes::LINE_HEIGHT

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

        svg = create_document(Layout::ClassDiagram.from_graph(graph,
                                                              theme: theme))

        # Add marker definitions
        add_markers(svg)

        # Render edges first (so they appear under nodes)
        render_relationships(graph, svg) if graph[:edges]

        # Render class boxes
        render_classes(graph, svg) if graph[:children]

        svg
      end

      def render_scene(scene)
        svg = create_document(scene)
        add_markers(svg)
        scene.namespaces.each { |box| render_scene_namespace(box, svg) }
        render_relationships(scene, svg)
        render_classes(scene, svg)
        scene.notes.each { |note| render_scene_note(note, svg) }
        svg
      end

      protected

      def render_scene_node(node, svg)
        group = Svg::Group.new.tap { |item| item.id = "class-#{node.id}" }
        group.children.concat(scene_node_parts(node))
        svg << group
      end

      def scene_node_parts(node)
        scene_node_header(node) + scene_node_members(node)
      end

      def scene_node_header(node)
        [
          scene_node_box(node),
          node.stereotype && scene_text(node.stereotype),
          scene_text(node.name),
          scene_separator(node.separators.first),
        ].compact
      end

      def scene_node_members(node)
        node.attributes.map { |label| scene_text(label) } +
          [additional_scene_separator(node)].compact +
          node.method_rows.map { |label| scene_text(label) }
      end

      def additional_scene_separator(node)
        return unless node.separators.length > 1

        scene_separator(node.separators.last)
      end

      def render_scene_namespace(box, svg)
        group = Svg::Group.new.tap { |item| item.id = "namespace-#{box.title}" }
        group.children << scene_namespace_rect(box)
        group.children << scene_namespace_title(box)
        svg << group
      end

      def scene_namespace_rect(box)
        Svg::Rect.new(
          x: svg_number(box.x), y: svg_number(box.y),
          width: svg_number(box.width), height: svg_number(box.height),
          fill: "none", stroke: "#000000", stroke_width: "1"
        )
      end

      def scene_namespace_title(box)
        Svg::Text.new(
          x: svg_number(box.x + (box.width / 2)), y: svg_number(box.y + 22),
          content: box.title, fill: "#000000",
          font_family: "Arial, sans-serif", font_size: "16",
          text_anchor: "middle"
        )
      end

      def render_scene_note(note, svg)
        group = Svg::Group.new.tap { |item| item.id = "note-#{note.id}" }
        group.children.concat(scene_note_parts(note))
        svg << group
      end

      def scene_note_parts(note)
        parts = [scene_note_box(note), scene_note_text(note)]
        note.linked? ? [scene_note_link(note), *parts] : parts
      end

      def scene_note_link(note)
        Svg::Line.new(
          x1: svg_number(note.link_x1), y1: svg_number(note.link_y1),
          x2: svg_number(note.link_x2), y2: svg_number(note.link_y2),
          stroke: "#aaaa33", stroke_width: "1", stroke_dasharray: "2,2"
        )
      end

      def scene_note_box(note)
        Svg::Rect.new(
          x: svg_number(note.x), y: svg_number(note.y),
          width: svg_number(note.width), height: svg_number(note.height),
          fill: "#fff5ad", stroke: "#aaaa33", stroke_width: "1"
        )
      end

      def scene_note_text(note)
        text = Svg::Text.new(
          x: svg_number(note.x + (note.width / 2)),
          y: svg_number(note.y + 23), fill: "#000000",
          font_family: "Arial, sans-serif", font_size: "16",
          text_anchor: "middle"
        )
        fill_note_lines(text, note.lines)
      end

      def fill_note_lines(text, lines)
        return text.tap { text.content = lines.first } if lines.one?

        LineBreakText.fill_lines(text, lines, pitch: NOTE_LINE_HEIGHT)
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
        group.children.concat(scene_edge_parts(edge))
        svg << group
      end

      def scene_edge_parts(edge)
        edge.sections.map do |section|
          scene_edge_section(section, edge.dashed)
        end +
          edge.markers.map { |marker| scene_marker(marker) } +
          edge.labels.map { |label| scene_text(label) }
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
        geometry = class_geometry(node)
        metadata = node[:metadata] || {}
        group = legacy_class_group(node[:id], geometry)
        render_class_content(node, metadata, group)
        svg << group
      end

      def class_geometry(node)
        {
          x: node[:x] || 0,
          y: node[:y] || 0,
          width: node[:width] || 150,
          height: node[:height] || 100,
        }
      end

      def legacy_class_group(id, geometry)
        Svg::Group.new.tap do |group|
          group.id = "class-#{id}"
          group.children << legacy_class_box(geometry)
        end
      end

      def legacy_class_box(geometry)
        Svg::Rect.new(
          x: geometry[:x], y: geometry[:y],
          width: geometry[:width], height: geometry[:height],
          fill: "#ffffff", stroke: "#000000", stroke_width: "2",
          rx: 3, ry: 3
        )
      end

      def render_class_content(node, metadata, group)
        geometry = class_geometry(node)
        current_y = render_class_header(node, metadata, geometry, group)
        current_y = render_attribute_compartment(
          geometry[:x], current_y, geometry[:width], metadata, group
        )
        render_method_compartment(
          geometry[:x], current_y, geometry[:width], metadata, group
        )
      end

      def render_class_header(node, metadata, geometry, group)
        current_y = render_optional_stereotype(
          geometry[:x], geometry[:y] + BOX_PADDING,
          geometry[:width], metadata, group
        )
        name = metadata[:name] || node[:id]
        current_y = render_class_name(
          geometry[:x], current_y, geometry[:width], name, group
        )
        render_separator(geometry[:x], current_y, geometry[:width], group)
      end

      def render_optional_stereotype(x_pos, y_pos, width, metadata, group)
        stereotype = metadata[:stereotype]
        return y_pos unless stereotype && !stereotype.empty?

        render_stereotype(x_pos, y_pos, width, stereotype, group)
      end

      def render_separator(x_pos, y_pos, width, group)
        separator_y = y_pos + 5
        group.children << Svg::Line.new(
          x1: x_pos, y1: separator_y,
          x2: x_pos + width, y2: separator_y,
          stroke: "#000000", stroke_width: "1"
        )
        separator_y + 10
      end

      def render_attribute_compartment(x_pos, y_pos, width, metadata, group)
        attributes = metadata[:attributes] || []
        return y_pos if attributes.empty?

        next_y = render_attributes(x_pos, y_pos, width, attributes, group)
        render_separator(x_pos, next_y, width, group)
      end

      def render_method_compartment(x_pos, y_pos, width, metadata, group)
        methods = metadata[:methods] || []
        return y_pos if methods.empty?

        render_methods(x_pos, y_pos, width, methods, group)
      end

      def render_stereotype(x_pos, y_pos, width, stereotype, group)
        group.children << Svg::Text.new(
          x: x_pos + (width / 2), y: y_pos,
          content: "«#{stereotype}»", fill: "#000000",
          font_family: "Arial, sans-serif",
          font_size: STEREOTYPE_FONT_SIZE.to_s, text_anchor: "middle"
        )
        y_pos + LINE_HEIGHT
      end

      def render_class_name(x_pos, y_pos, width, name, group)
        group.children << Svg::Text.new(
          x: x_pos + (width / 2), y: y_pos,
          content: Diagram::GenericText.display(name), fill: "#000000",
          font_family: "Arial, sans-serif",
          font_size: CLASS_NAME_FONT_SIZE.to_s, text_anchor: "middle",
          font_weight: "bold"
        )
        y_pos + LINE_HEIGHT
      end

      def render_attributes(x_pos, y_pos, _width, attributes, group)
        render_members(x_pos, y_pos, attributes, group)
      end

      def render_methods(x_pos, y_pos, _width, methods, group)
        render_members(x_pos, y_pos, methods, group)
      end

      def render_members(x_pos, y_pos, members, group)
        rows = members.each_with_index.map do |member, index|
          member_text(x_pos, y_pos + (index * LINE_HEIGHT), member[:text])
        end
        group.children.concat(rows)
        y_pos + (members.length * LINE_HEIGHT)
      end

      def member_text(x_pos, y_pos, content)
        Svg::Text.new(
          x: x_pos + BOX_PADDING, y: y_pos, content: content,
          fill: "#000000", font_family: "monospace",
          font_size: MEMBER_FONT_SIZE.to_s
        )
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
        endpoints = relationship_endpoints(edge, graph)
        return unless endpoints

        svg << legacy_relationship_group(edge, *endpoints)
      end

      def relationship_endpoints(edge, graph)
        source = find_node(graph, edge[:sources]&.first)
        target = find_node(graph, edge[:targets]&.first)
        [source, target] if source && target
      end

      def legacy_relationship_group(edge, source, target)
        metadata = edge[:metadata] || {}
        source_point = calculate_connection_point(source, target)
        target_point = calculate_connection_point(target, source)
        group = Svg::Group.new.tap { |item| item.id = "rel-#{edge[:id]}" }
        render_relationship_body(source_point, target_point, metadata, group)
        render_relationship_labels(edge, source_point, target_point, group)
        group
      end

      def render_relationship_body(source_point, target_point, metadata, group)
        if metadata[:start_marker] || metadata[:end_marker]
          render_mixed_marker_relationship(
            source_point, target_point, metadata, group
          )
          return
        end

        type = metadata[:relationship_type] || "association"
        render_relationship_line(source_point, target_point, type, group)
        render_relationship_marker(source_point, target_point, type, group)
      end

      def find_node(graph, node_id)
        return nil unless graph[:children] && node_id

        graph[:children].find { |n| n[:id] == node_id }
      end

      def calculate_connection_point(from_node, to_node)
        Layout::ClassDiagram.connection_point(from_node, to_node)
      end

      def render_relationship_line(from, to, rel_type, group)
        group.children << Svg::Line.new(
          x1: from[:x], y1: from[:y], x2: to[:x], y2: to[:y],
          stroke: "#000000", stroke_width: "2",
          stroke_dasharray: rel_type == "dependency" ? "5,5" : nil
        )
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

      def render_mixed_marker_relationship(
        source_point, target_point, metadata, group
      )
        group.children << mixed_relationship_line(
          source_point, target_point, metadata[:dashed]
        )
        render_marker_at(
          source_point, target_point, metadata[:start_marker], group
        )
        render_marker_at(
          target_point, source_point, metadata[:end_marker], group
        )
      end

      def mixed_relationship_line(source_point, target_point, dashed)
        Svg::Line.new(
          x1: source_point[:x], y1: source_point[:y],
          x2: target_point[:x], y2: target_point[:y],
          stroke: "#000000", stroke_width: "2",
          stroke_dasharray: dashed ? "5,5" : nil
        )
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
          render_triangle_marker(away_from, point, false, group)
        when "dependency"
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

        render_main_relationship_label(labels, from, to, group)
        render_cardinality_label(labels, "source", from, group)
        render_cardinality_label(labels, "target", to, group)
      end

      def render_main_relationship_label(labels, from, to, group)
        label = labels.find { |candidate| !candidate[:position] }
        return unless label

        group.children << main_relationship_text(label, from, to)
      end

      def main_relationship_text(label, from, to)
        Svg::Text.new(
          x: (from[:x] + to[:x]) / 2,
          y: ((from[:y] + to[:y]) / 2) - 5,
          content: label[:text], fill: "#000000",
          font_family: "Arial, sans-serif", font_size: "11",
          text_anchor: "middle"
        )
      end

      def render_cardinality_label(labels, position, point, group)
        label = labels.find { |candidate| candidate[:position] == position }
        return unless label

        group.children << cardinality_text(label, position, point)
      end

      def cardinality_text(label, position, point)
        target = position == "target"
        Svg::Text.new(
          x: point[:x] + (target ? -5 : 5), y: point[:y] - 5,
          content: label[:text], fill: "#000000",
          font_family: "Arial, sans-serif", font_size: "10",
          text_anchor: target ? "end" : nil
        )
      end
    end
  end
end
