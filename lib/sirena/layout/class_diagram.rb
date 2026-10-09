# frozen_string_literal: true

require_relative "base"
require_relative "grid"
require_relative "../diagram/class_diagram"
require_relative "../diagram/generic_text"

module Sirena
  module Layout
    # Computes final canvas geometry for class diagrams.
    class ClassDiagram < Base
      DEFAULT_NAME_FONT_SIZE = 16
      DEFAULT_SMALL_FONT_SIZE = 12
      MIN_CLASS_WIDTH = 120
      LINE_HEIGHT = 20
      RENDER_LINE_HEIGHT = 18
      COMPARTMENT_PADDING = 10
      CLASS_SPACING = 80
      DIAGRAM_PADDING = 20
      ARROW_SIZE = 10
      DIAMOND_SIZE = 12
      DART_NEAR = 3
      DART_FAR = 14
      DART_WIDTH = 5

      class Point < Lutaml::Model::Serializable
        attribute :x, :float
        attribute :y, :float
      end

      class Section < Lutaml::Model::Serializable
        attribute :start_point, Point
        attribute :end_point, Point
        attribute :bend_points, Point, collection: true, default: -> { [] }
      end

      class Label < Lutaml::Model::Serializable
        attribute :text, :string
        attribute :x, :float
        attribute :y, :float
        attribute :font_size, :float
        attribute :font_family, :string
        attribute :font_weight, :string
        attribute :text_anchor, :string
      end

      class Marker < Lutaml::Model::Serializable
        attribute :points, :string
        attribute :fill, :string
      end

      class Separator < Lutaml::Model::Serializable
        attribute :x1, :float
        attribute :y1, :float
        attribute :x2, :float
        attribute :y2, :float
      end

      class Node < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :x, :float
        attribute :y, :float
        attribute :width, :float
        attribute :height, :float
        attribute :labels, Label, collection: true, default: -> { [] }
        attribute :name, Label
        attribute :stereotype, Label
        attribute :attributes, Label, collection: true, default: -> { [] }
        attribute :method_rows, Label, collection: true, default: -> { [] }
        attribute :separators, Separator, collection: true, default: -> { [] }
      end

      class Edge < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :source, :string
        attribute :target, :string
        attribute :sections, Section, collection: true, default: -> { [] }
        attribute :markers, Marker, collection: true, default: -> { [] }
        attribute :labels, Label, collection: true, default: -> { [] }
        attribute :dashed, :boolean, default: false
      end

      class Scene < Layout::Scene
        attribute :id, :string
        attribute :view_box, :string
        attribute :children, Node, collection: true, default: -> { [] }
        attribute :edges, Edge, collection: true, default: -> { [] }
      end

      def self.from_graph(graph, theme: nil)
        layout = new
        layout.theme = theme if theme
        layout.send(:scene_from_graph, graph)
      end

      def self.connection_point(from_node, to_node)
        new.send(:connection_point, from_node, to_node)
      end

      def self.triangle_marker(from, to, filled)
        new.send(:triangle_marker, from, to, filled)
      end

      def self.diamond_marker(from, to, filled)
        new.send(:diamond_marker, from, to, filled)
      end

      def self.dart_marker(from, to)
        new.send(:dart_marker, from, to)
      end

      def scene(diagram)
        graph = build_graph(diagram)
        Grid.apply(graph)
        scene_from_graph(graph)
      end

      private

      def build_graph(diagram)
        {
          id: diagram.id || "class_diagram",
          children: transform_entities(diagram),
          edges: transform_relationships(diagram),
          layoutOptions: layout_options(diagram),
        }
      end

      def scene_from_graph(graph)
        children = graph[:children] || []
        width, height = scene_dimensions(children)

        Scene.new(
          id: graph[:id] || "class_diagram",
          width: width,
          height: height,
          view_box: "0 0 #{width} #{height}",
          children: children.map { |node| typed_node(node) },
          edges: typed_edges(graph[:edges] || [], children),
        )
      end

      def scene_dimensions(children)
        [content_width(children), content_height(children)].map do |value|
          value + (DIAGRAM_PADDING * 2)
        end
      end

      def transform_entities(diagram)
        diagram.entities.map do |entity|
          dimensions = calculate_entity_dimensions(entity)
          {
            id: entity.id,
            width: dimensions[:width],
            height: dimensions[:height],
            labels: entity_labels(entity),
            metadata: {
              name: entity.name,
              stereotype: entity.stereotype,
              attributes: entity.attributes.map do |item|
                attribute_to_hash(item)
              end,
              methods: entity.class_methods.map { |item| method_to_hash(item) },
            },
          }
        end
      end

      def transform_relationships(diagram)
        diagram.relationships.map do |relationship|
          {
            id: "#{relationship.from_id}_to_#{relationship.to_id}",
            sources: [relationship.from_id],
            targets: [relationship.to_id],
            labels: relationship_labels(relationship),
            metadata: {
              relationship_type: relationship.relationship_type,
              start_marker: relationship.start_marker,
              end_marker: relationship.end_marker,
              dashed: relationship.dashed,
            },
          }
        end
      end

      def calculate_entity_dimensions(entity)
        widths = [MIN_CLASS_WIDTH, name_block_width(entity)]
        widths.concat(
          entity.attributes.map { |item| member_width(item.display_text) },
        )
        widths.concat(
          entity.class_methods.map { |item| member_width(item.display_text) },
        )
        compartments = 1 + present_compartments(entity)
        lines = (entity.stereotype ? 2 : 1) + entity.attributes.length +
                entity.class_methods.length

        {
          width: widths.max + (COMPARTMENT_PADDING * 2),
          height: (lines * LINE_HEIGHT) + ((compartments - 1) * 2) +
            (COMPARTMENT_PADDING * 2),
        }
      end

      def present_compartments(entity)
        [entity.attributes, entity.class_methods]
          .count { |items| !items.empty? }
      end

      def member_width(text)
        measure_text(text, font_size: small_font_size, monospace: true)[:width]
      end

      def name_block_width(entity)
        widths = [measure_text(entity.name, font_size: name_font_size)[:width]]
        if entity.stereotype
          widths << measure_text("<<#{entity.stereotype}>>",
                                 font_size: small_font_size)[:width]
        end
        widths.max
      end

      def entity_labels(entity)
        text = if entity.stereotype
                 "<<#{entity.stereotype}>>\n#{entity.name}"
               else
                 entity.name
               end
        dimensions = measure_text(text, font_size: name_font_size)
        [{
          text: text,
          width: name_block_width(entity),
          height: dimensions[:height],
        }]
      end

      def relationship_labels(relationship)
        [
          relationship_label(relationship.label),
          relationship_label(relationship.source_cardinality, "source"),
          relationship_label(relationship.target_cardinality, "target"),
        ].compact
      end

      def relationship_label(text, position = nil)
        return if text.nil? || text.empty?

        dimensions = measure_text(text, font_size: small_font_size)
        {
          text: text,
          width: dimensions[:width],
          height: dimensions[:height],
          position: position,
        }
      end

      def attribute_to_hash(attribute)
        {
          name: attribute.name,
          type: attribute.type,
          visibility: attribute.visibility,
          text: attribute.display_text,
        }
      end

      def method_to_hash(method)
        {
          name: method.name,
          parameters: method.parameters,
          return_type: method.return_type,
          visibility: method.visibility,
          text: method.display_text,
        }
      end

      def typed_node(node)
        dimensions = box_values(node)
        rows = node_rows(
          *dimensions.first(3), node[:id], node[:metadata] || {}
        )
        build_typed_node(node[:id], dimensions, rows)
      end

      def build_typed_node(id, dimensions, rows)
        x_coord, y_coord, width, height = dimensions
        Node.new(
          id: id, x: x_coord, y: y_coord,
          width: width, height: height,
          labels: node_labels(rows),
          name: rows[:name], stereotype: rows[:stereotype],
          attributes: rows[:attributes], method_rows: rows[:methods],
          separators: typed_separators(x_coord, width, rows[:separator_ys])
        )
      end

      def node_labels(rows)
        [rows[:stereotype], rows[:name], *rows[:attributes], *rows[:methods]]
          .compact
      end

      def typed_separators(x_coord, width, positions)
        positions.map do |y_coord|
          Separator.new(
            x1: x_coord, y1: y_coord,
            x2: x_coord + width, y2: y_coord
          )
        end
      end

      def node_rows(x_coord, y_coord, width, id, metadata)
        cursor = y_coord + COMPARTMENT_PADDING
        stereotype, cursor = stereotype_row(
          x_coord, cursor, width, metadata[:stereotype]
        )
        name, cursor = name_row(
          metadata[:name] || id, x_coord, cursor, width
        )
        attributes, cursor, separator_ys = attribute_rows(
          metadata[:attributes] || [], x_coord, cursor
        )
        methods, = member_rows(
          metadata[:methods] || [], x_coord, cursor
        )
        {
          name: name, stereotype: stereotype, attributes: attributes,
          methods: methods, separator_ys: separator_ys
        }
      end

      def name_row(name, x_coord, y_coord, width)
        row = label(
          Diagram::GenericText.display(name), x_coord + (width / 2),
          y_coord, name_font_size,
          family: "Arial, sans-serif",
          weight: "bold",
          anchor: "middle"
        )
        [row, y_coord + RENDER_LINE_HEIGHT]
      end

      def attribute_rows(items, x_coord, y_coord)
        separator_ys = [y_coord + 5]
        rows, cursor = member_rows(
          items, x_coord, separator_ys.last + 10
        )
        return [rows, cursor, separator_ys] if rows.empty?

        separator_ys << (cursor + 5)
        [rows, separator_ys.last + 10, separator_ys]
      end

      def stereotype_row(x_coord, y_coord, width, stereotype)
        return [nil, y_coord] if stereotype.nil? || stereotype.empty?

        row = label(
          "«#{stereotype}»", x_coord + (width / 2), y_coord,
          small_font_size, family: "Arial, sans-serif", anchor: "middle"
        )
        [row, y_coord + RENDER_LINE_HEIGHT]
      end

      def member_rows(items, x_coord, y_coord)
        rows = items.map.with_index do |item, index|
          label(item[:text], x_coord + COMPARTMENT_PADDING,
                y_coord + (index * RENDER_LINE_HEIGHT), small_font_size,
                family: "monospace")
        end
        [rows, y_coord + (items.length * RENDER_LINE_HEIGHT)]
      end

      def typed_edges(edges, nodes)
        by_id = nodes.to_h { |node| [node[:id], node] }
        edges.filter_map do |edge|
          source = by_id[edge[:sources]&.first]
          target = by_id[edge[:targets]&.first]
          typed_edge(edge, source, target) if source && target
        end
      end

      def typed_edge(edge, source, target)
        sections = typed_sections(edge, source, target)
        from, to = section_endpoints(sections)
        markers, dashed = typed_edge_style(edge, from, to)

        Edge.new(
          id: edge[:id], source: source[:id], target: target[:id],
          sections: sections,
          markers: markers,
          labels: positioned_labels(edge[:labels], from, to),
          dashed: dashed
        )
      end

      def typed_sections(edge, source, target)
        sections = edge[:sections] || []
        unless sections.empty?
          return sections.map { |section| typed_section(section) }
        end

        [Section.new(
          start_point: point(connection_point(source, target)),
          end_point: point(connection_point(target, source)),
        )]
      end

      def typed_section(section)
        Section.new(
          start_point: point(
            section_coordinate(section, :start_point, :startPoint),
          ),
          end_point: point(section_coordinate(section, :end_point, :endPoint)),
          bend_points: Array(
            section_coordinate(section, :bend_points, :bendPoints),
          ).map { |coordinates| point(coordinates) },
        )
      end

      def section_coordinate(section, snake_case, camel_case)
        section[snake_case] || section[camel_case] || section[camel_case.to_s]
      end

      def coordinate_hash(value)
        { x: normalized_coordinate(value.x), y: normalized_coordinate(value.y) }
      end

      def section_endpoints(sections)
        [
          coordinate_hash(sections.first.start_point),
          coordinate_hash(sections.last.end_point),
        ]
      end

      def normalized_coordinate(value)
        value.to_i == value ? value.to_i : value
      end

      def typed_edge_style(edge, from, to)
        edge_style(from, to, edge[:metadata] || {})
      end

      def edge_style(from, to, metadata)
        type = metadata[:relationship_type] || "association"
        mixed = metadata[:start_marker] || metadata[:end_marker]
        markers = if mixed
                    mixed_markers(from, to, metadata)
                  else
                    relationship_markers(from, to, type)
                  end
        [markers, mixed ? metadata[:dashed] : type == "dependency"]
      end

      def connection_point(from_node, to_node)
        from_x, from_y, from_width, from_height = box_values(from_node)
        to_x, to_y, to_width, to_height = box_values(to_node)
        from_center = {
          x: from_x + (from_width / 2),
          y: from_y + (from_height / 2),
        }
        to_center = {
          x: to_x + (to_width / 2),
          y: to_y + (to_height / 2),
        }
        dx = to_center[:x] - from_center[:x]
        dy = to_center[:y] - from_center[:y]
        return from_center if dx.abs < 0.001 && dy.abs < 0.001

        if dx.abs > dy.abs
          x = dx.positive? ? from_x + from_width : from_x
          y = if dy.abs < 0.001
                from_center[:y]
              else
                from_center[:y] + ((dy / dx) * (x - from_center[:x]))
              end
        else
          y = dy.positive? ? from_y + from_height : from_y
          x = if dx.abs < 0.001
                from_center[:x]
              else
                from_center[:x] + ((dx / dy) * (y - from_center[:y]))
              end
        end
        { x: x, y: y }
      end

      def box_values(node)
        return [node.x, node.y, node.width, node.height] if node.is_a?(Node)

        [
          node[:x] || 0,
          node[:y] || 0,
          node[:width] || 150,
          node[:height] || 100,
        ]
      end

      def mixed_markers(from, to, metadata)
        [
          marker_at(from, to, metadata[:start_marker]),
          marker_at(to, from, metadata[:end_marker]),
        ].compact
      end

      def relationship_markers(from, to, type)
        marker = case type
                 when "inheritance" then triangle_marker(from, to, true)
                 when "realization" then triangle_marker(from, to, false)
                 when "composition" then diamond_marker(from, to, true)
                 when "aggregation" then diamond_marker(from, to, false)
                 end
        marker ? [marker] : []
      end

      def marker_at(point, away_from, type)
        case type
        when "inheritance" then triangle_marker(away_from, point, false)
        when "dependency" then dart_marker(point, away_from)
        when "composition" then diamond_marker(point, away_from, true)
        when "aggregation" then diamond_marker(point, away_from, false)
        end
      end

      def triangle_marker(from, to, filled)
        to_x, to_y = coordinates(to)
        angle = marker_angle(from, to)
        first = marker_point(
          to_x, to_y, -ARROW_SIZE, angle + (Math::PI / 6)
        )
        second = marker_point(
          to_x, to_y, -ARROW_SIZE, angle - (Math::PI / 6)
        )
        marker([[to_x, to_y], first, second], filled)
      end

      def dart_marker(from, to)
        from_x, from_y = coordinates(from)
        angle = marker_angle(from, to)
        tip = marker_point(from_x, from_y, DART_NEAR, angle)
        back = marker_point(from_x, from_y, DART_FAR, angle)
        first, second = dart_wings(back, angle)
        marker([tip, first, midpoint(tip, back), second], true)
      end

      def diamond_marker(from, to, filled)
        from_x, from_y = coordinates(from)
        angle = marker_angle(from, to)
        points = [
          marker_point(from_x, from_y, DIAMOND_SIZE, angle),
          marker_point(from_x, from_y, DIAMOND_SIZE / 2,
                       angle + (Math::PI / 2)),
          marker_point(from_x, from_y, -DIAMOND_SIZE, angle),
          marker_point(from_x, from_y, DIAMOND_SIZE / 2,
                       angle - (Math::PI / 2)),
        ]
        marker(points, filled)
      end

      def marker_angle(from, to)
        from_x, from_y = coordinates(from)
        to_x, to_y = coordinates(to)
        Math.atan2(to_y - from_y, to_x - from_x)
      end

      def coordinates(point)
        [point[:x], point[:y]]
      end

      def dart_wings(back, angle)
        back_x, back_y = back
        [
          marker_point(
            back_x, back_y, DART_WIDTH, angle + (Math::PI / 2)
          ),
          marker_point(
            back_x, back_y, DART_WIDTH, angle - (Math::PI / 2)
          ),
        ]
      end

      def midpoint(first, second)
        [
          (first[0] + second[0]) / 2,
          (first[1] + second[1]) / 2,
        ]
      end

      def marker_point(x_coord, y_coord, distance, angle)
        [
          x_coord + (distance * Math.cos(angle)),
          y_coord + (distance * Math.sin(angle)),
        ]
      end

      def marker(points, filled)
        Marker.new(points: points.map { |x, y| "#{x},#{y}" }.join(" "),
                   fill: filled ? "#000000" : "#ffffff")
      end

      def positioned_labels(labels, from, to)
        (labels || []).filter_map do |item|
          case item[:position]
          when "source"
            label(item[:text], from[:x] + 5, from[:y] - 5, small_font_size,
                  family: "Arial, sans-serif")
          when "target"
            label(item[:text], to[:x] - 5, to[:y] - 5, small_font_size,
                  family: "Arial, sans-serif", anchor: "end")
          when nil
            label(item[:text], (from[:x] + to[:x]) / 2,
                  ((from[:y] + to[:y]) / 2) - 5, small_font_size,
                  family: "Arial, sans-serif", anchor: "middle")
          end
        end
      end

      def label(text, x_coord, y_coord, font_size, style = {})
        Label.new(text: text, x: x_coord, y: y_coord, font_size: font_size,
                  font_family: style[:family], font_weight: style[:weight],
                  text_anchor: style[:anchor])
      end

      def point(coordinates)
        Point.new(x: coordinates[:x], y: coordinates[:y])
      end

      def content_width(children)
        return 840 if children.empty?

        children.map { |node| (node[:x] || 0) + (node[:width] || 150) }.max + 40
      end

      def content_height(children)
        return 640 if children.empty?

        children.map do |node|
          (node[:y] || 0) + (node[:height] || 100)
        end.max + 40
      end

      def name_font_size
        valid_font_size(theme&.typography&.font_size_large) ||
          DEFAULT_NAME_FONT_SIZE
      end

      def small_font_size
        valid_font_size(theme&.typography&.font_size_small) ||
          DEFAULT_SMALL_FONT_SIZE
      end

      def valid_font_size(value)
        value if value.is_a?(Numeric) && value.finite? && value.positive?
      end

      def layout_options(diagram)
        build_elk_options(
          algorithm: ALGORITHM_LAYERED,
          direction: direction_to_layout(diagram.direction),
          ElkOptions::NODE_NODE_SPACING => CLASS_SPACING,
          ElkOptions::LAYER_SPACING => CLASS_SPACING,
          ElkOptions::EDGE_NODE_SPACING => 40,
          ElkOptions::EDGE_EDGE_SPACING => 20,
          ElkOptions::NODE_PLACEMENT => "NETWORK_SIMPLEX",
          ElkOptions::MODEL_ORDER => "NODES_AND_EDGES",
          ElkOptions::HIERARCHY_HANDLING => "INCLUDE_CHILDREN",
        )
      end

      def direction_to_layout(direction)
        {
          "TD" => DIRECTION_DOWN, "TB" => DIRECTION_DOWN,
          "LR" => DIRECTION_RIGHT, "RL" => DIRECTION_LEFT,
          "BT" => DIRECTION_UP
        }.fetch(direction, DIRECTION_DOWN)
      end
    end
  end
end
