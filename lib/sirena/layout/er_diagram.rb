# frozen_string_literal: true

require_relative "base"
require_relative "grid"
require_relative "../diagram/er_diagram"

module Sirena
  module Layout
    # Computes final canvas geometry for entity-relationship diagrams.
    class ErDiagram < Base
      MIN_ENTITY_WIDTH = 150
      LINE_HEIGHT = 20
      TEXT_LINE_HEIGHT = 18
      ENTITY_PADDING = 10
      ENTITY_SPACING = 100
      CARDINALITY_SIZE = 15
      DIAGRAM_PADDING = 20
      EMPTY_DIAGRAM_PADDING = 8

      class Point < Lutaml::Model::Serializable
        attribute :x, :float
        attribute :y, :float
      end

      class Label < Lutaml::Model::Serializable
        attribute :text, :string
        attribute :width, :float
        attribute :height, :float
        attribute :x, :float
        attribute :y, :float
        attribute :font_size, :float
      end

      class Line < Lutaml::Model::Serializable
        attribute :x1, :float
        attribute :y1, :float
        attribute :x2, :float
        attribute :y2, :float
      end

      class Circle < Lutaml::Model::Serializable
        attribute :cx, :float
        attribute :cy, :float
        attribute :radius, :float
      end

      class Marker < Lutaml::Model::Serializable
        attribute :lines, Line, collection: true, default: -> { [] }
        attribute :circles, Circle, collection: true, default: -> { [] }
        attribute :circle_first, :boolean, default: false
      end

      class Section < Lutaml::Model::Serializable
        attribute :start_point, Point
        attribute :end_point, Point
        attribute :bend_points, Point, collection: true, default: -> { [] }
      end

      class AttributeRow < Lutaml::Model::Serializable
        attribute :name, :string
        attribute :attribute_type, :string
        attribute :key_type, :string
        attribute :note, :string
        attribute :text, :string
        attribute :x, :float
        attribute :y, :float
        attribute :font_size, :float
      end

      class Node < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :x, :float
        attribute :y, :float
        attribute :width, :float
        attribute :height, :float
        attribute :labels, Label, collection: true, default: -> { [] }
        attribute :shape, :string
        attribute :children, Node, collection: true, default: -> { [] }
        attribute :name, :string
        attribute :classes, :string, collection: true, default: -> { [] }
        attribute :attributes, AttributeRow, collection: true, default: -> { [] }
        attribute :separator, Line
      end

      class Edge < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :source, :string
        attribute :target, :string
        attribute :sections, Section, collection: true, default: -> { [] }
        attribute :labels, Label, collection: true, default: -> { [] }
        attribute :relationship_type, :string
        attribute :cardinality_from, :string
        attribute :cardinality_to, :string
        attribute :source_marker, Marker
        attribute :target_marker, Marker
      end

      class ClassDef < Lutaml::Model::Serializable
        attribute :name, :string
        attribute :declaration, :string
      end

      class Scene < Layout::Scene
        attribute :id, :string
        attribute :view_box, :string
        attribute :children, Node, collection: true, default: -> { [] }
        attribute :edges, Edge, collection: true, default: -> { [] }
        attribute :class_defs, ClassDef, collection: true, default: -> { [] }
      end

      def self.from_graph(graph, theme: nil)
        layout = new
        layout.theme = theme if theme
        layout.send(:scene_from_graph, graph)
      end

      def self.connection_point(from_node, to_node)
        from_x = value(from_node, :x, 0)
        from_y = value(from_node, :y, 0)
        from_width = value(from_node, :width, 150)
        from_height = value(from_node, :height, 100)
        from_cx = from_x + (from_width / 2)
        from_cy = from_y + (from_height / 2)
        to_cx = value(to_node, :x, 0) + (value(to_node, :width, 150) / 2)
        to_cy = value(to_node, :y, 0) + (value(to_node, :height, 100) / 2)
        dx = to_cx - from_cx
        dy = to_cy - from_cy

        return Point.new(x: from_cx, y: from_cy) if dx.abs < 0.001 && dy.abs < 0.001

        if dx.abs > dy.abs
          x = dx.positive? ? from_x + from_width : from_x
          y = dy.abs < 0.001 ? from_cy : from_cy + ((dy / dx) * (x - from_cx))
        else
          y = dy.positive? ? from_y + from_height : from_y
          x = dx.abs < 0.001 ? from_cx : from_cx + ((dx / dy) * (y - from_cy))
        end

        Point.new(x: x, y: y)
      end

      def self.marker(point, opposite, cardinality)
        lines = []
        circles = []
        one = %w[one one_or_more zero_or_one]
        many = %w[zero_or_more one_or_more]
        lines.concat(one_lines(point, opposite)) if one.include?(cardinality)
        circles << circle(point, opposite) if %w[zero_or_more zero_or_one].include?(cardinality)
        lines.concat(crows_foot(point, opposite)) if many.include?(cardinality)
        Marker.new(lines: lines, circles: circles,
                   circle_first: cardinality&.start_with?("zero_"))
      end

      def self.relationship_label(text, from, to, font_size)
        Label.new(
          text: text,
          x: (from.x + to.x) / 2,
          y: ((from.y + to.y) / 2) - 5,
          font_size: font_size,
        )
      end

      def self.point(value)
        return value if value.is_a?(Point)

        Point.new(x: self.value(value, :x, 0), y: self.value(value, :y, 0))
      end

      def self.content_width(graph)
        new.send(:content_width, graph)
      end

      def self.content_height(graph)
        new.send(:content_height, graph)
      end

      def self.diagram_padding(graph)
        new.send(:empty_graph?, graph) ? EMPTY_DIAGRAM_PADDING : DIAGRAM_PADDING
      end

      def self.find_node(graph, node_id)
        return unless graph[:children] && node_id

        (graph[:children] || []).find { |node| node[:id] == node_id }
      end

      def self.entity_from_hash(node, theme: nil)
        from_graph({ children: [node], edges: [] }, theme: theme).children.first
      end

      def self.attribute_row(x, y, attribute, theme: nil)
        layout = new
        layout.theme = theme if theme
        font_size = layout.send(:small_text_size)
        AttributeRow.new(
          text: layout.send(:format_attribute, attribute),
          x: x + ENTITY_PADDING, y: y + font_size, font_size: font_size
        )
      end

      def self.edge_label(edge, from, to, theme: nil)
        label = (edge[:labels] || []).find { |item| !item[:position] }
        return unless label

        layout = new
        layout.theme = theme if theme
        relationship_label(label[:text], point(from), point(to),
                           layout.send(:small_text_size))
      end

      def self.section(from, to)
        Section.new(start_point: point(from), end_point: point(to))
      end

      def self.one_marker(point, opposite)
        Marker.new(lines: one_lines(self.point(point), self.point(opposite)))
      end

      def self.circle_marker(point, opposite)
        Marker.new(circles: [circle(self.point(point), self.point(opposite))],
                   circle_first: true)
      end

      def self.crows_marker(point, opposite)
        Marker.new(lines: crows_foot(self.point(point), self.point(opposite)))
      end

      def scene(diagram)
        graph = build_graph(diagram)
        Grid.apply(graph)
        scene_from_graph(graph)
      end

      private

      def build_graph(diagram)
        {
          id: diagram.id || "er_diagram",
          children: transform_entities(diagram),
          edges: transform_relationships(diagram),
          class_defs: diagram.class_defs,
          layoutOptions: layout_options,
        }
      end

      def scene_from_graph(graph)
        padding = empty_graph?(graph) ? EMPTY_DIAGRAM_PADDING : DIAGRAM_PADDING
        width = content_width(graph) + (padding * 2)
        height = content_height(graph) + (padding * 2)
        children = typed_nodes(graph[:children] || [])

        Scene.new(
          id: graph[:id] || "er_diagram",
          width: width,
          height: height,
          view_box: "0 0 #{width} #{height}",
          children: children,
          edges: typed_edges(graph[:edges] || [], graph[:children] || []),
          class_defs: typed_class_defs(graph[:class_defs] || {}),
        )
      end

      def typed_nodes(nodes)
        nodes.map do |node|
          x = node[:x] || 0
          y = node[:y] || 0
          width = node[:width] || 150
          height = node[:height] || 100
          metadata = node[:metadata] || {}
          font_size = large_text_size
          name = metadata[:name] || node[:id]
          name_y = y + ENTITY_PADDING + font_size
          separator_y = name_y + TEXT_LINE_HEIGHT

          Node.new(
            id: node[:id], x: x, y: y, width: width, height: height,
            labels: [positioned_label(name, x + (width / 2), name_y, font_size)],
            shape: "rect", name: name, classes: metadata[:classes] || [],
            attributes: typed_attributes(metadata[:attributes] || [], x, separator_y),
            separator: Line.new(x1: x, y1: separator_y,
                                x2: x + width, y2: separator_y)
          )
        end
      end

      def typed_attributes(attributes, x, separator_y)
        current_y = separator_y + ENTITY_PADDING
        attributes.map do |attribute|
          row = AttributeRow.new(
            name: attribute[:name], attribute_type: attribute[:attribute_type],
            key_type: attribute[:key_type], note: attribute[:note],
            text: format_attribute(attribute), x: x + ENTITY_PADDING,
            y: current_y + small_text_size, font_size: small_text_size
          )
          current_y += TEXT_LINE_HEIGHT
          row
        end
      end

      def typed_edges(edges, nodes)
        edges.filter_map do |edge|
          source_id = edge[:sources]&.first
          target_id = edge[:targets]&.first
          source = nodes.find { |node| node[:id] == source_id }
          target = nodes.find { |node| node[:id] == target_id }
          next unless source && target

          typed_edge(edge, source, target)
        end
      end

      def typed_edge(edge, source, target)
        from = self.class.connection_point(source, target)
        to = self.class.connection_point(target, source)
        metadata = edge[:metadata] || {}
        label = (edge[:labels] || []).find { |item| !item[:position] }

        Edge.new(
          id: edge[:id], source: source[:id], target: target[:id],
          sections: [Section.new(start_point: from, end_point: to)],
          labels: typed_relationship_labels(label, from, to),
          relationship_type: metadata[:relationship_type] || "non-identifying",
          cardinality_from: metadata[:cardinality_from],
          cardinality_to: metadata[:cardinality_to],
          source_marker: self.class.marker(from, to, metadata[:cardinality_from]),
          target_marker: self.class.marker(to, from, metadata[:cardinality_to])
        )
      end

      def typed_relationship_labels(label, from, to)
        return [] unless label

        [self.class.relationship_label(label[:text], from, to, small_text_size)]
      end

      def typed_class_defs(class_defs)
        class_defs.map do |name, declaration|
          ClassDef.new(name: name, declaration: declaration)
        end
      end

      def positioned_label(text, x, y, font_size)
        dimensions = measure_text(text, font_size: font_size)
        Label.new(text: text, width: dimensions[:width],
                  height: dimensions[:height], x: x, y: y,
                  font_size: font_size)
      end

      def transform_entities(diagram)
        diagram.entities.map do |entity|
          dimensions = calculate_entity_dimensions(entity)
          {
            id: entity.id, width: dimensions[:width], height: dimensions[:height],
            labels: entity_labels(entity),
            metadata: {
              name: entity.name, classes: entity.classes,
              attributes: entity.attributes.map { |item| attribute_to_hash(item) }
            }
          }
        end
      end

      def transform_relationships(diagram)
        diagram.relationships.map do |relationship|
          {
            id: "#{relationship.from_id}_to_#{relationship.to_id}",
            sources: [relationship.from_id], targets: [relationship.to_id],
            labels: relationship_labels(relationship),
            metadata: {
              relationship_type: relationship.relationship_type,
              cardinality_from: relationship.cardinality_from,
              cardinality_to: relationship.cardinality_to,
            }
          }
        end
      end

      def calculate_entity_dimensions(entity)
        widths = [MIN_ENTITY_WIDTH, measured_width(entity.name, large_text_size)]
        entity.attributes.each do |attribute|
          widths << measured_width(format_attribute(attribute),
                                   small_text_size, monospace: true)
        end
        {
          width: widths.max + (ENTITY_PADDING * 2),
          height: ((1 + entity.attributes.length) * LINE_HEIGHT) +
            (ENTITY_PADDING * 2),
        }
      end

      def entity_labels(entity)
        dimensions = measure_text(entity.name, font_size: large_text_size)
        [{ text: entity.name, width: dimensions[:width],
           height: dimensions[:height] }]
      end

      def relationship_labels(relationship)
        return [] if relationship.label.nil? || relationship.label.empty?

        dimensions = measure_text(relationship.label,
                                  font_size: small_text_size)
        [{ text: relationship.label, width: dimensions[:width],
           height: dimensions[:height] }]
      end

      def measured_width(text, font_size, monospace: false)
        measure_text(text, font_size: font_size,
                           monospace: monospace)[:width]
      end

      def format_attribute(attribute)
        parts = []
        key_type = value(attribute, :key_type)
        attribute_type = value(attribute, :attribute_type)
        note = value(attribute, :note)
        parts << key_type if key_type && !key_type.empty?
        parts << attribute_type if attribute_type && !attribute_type.empty?
        parts << value(attribute, :name)
        parts << note if note && !note.empty?
        parts.join(" ")
      end

      def attribute_to_hash(attribute)
        {
          name: attribute.name, attribute_type: attribute.attribute_type,
          key_type: attribute.key_type, note: attribute.note
        }
      end

      def empty_graph?(graph)
        graph.key?(:children) && graph.key?(:edges) &&
          graph[:children] == [] && graph[:edges] == []
      end

      def content_width(graph)
        return 0 if empty_graph?(graph)
        return 800 unless graph[:children]

        maximum = graph[:children].map do |node|
          (node[:x] || 0) + (node[:width] || 150)
        end.max || 800
        maximum + 40
      end

      def content_height(graph)
        return 0 if empty_graph?(graph)
        return 600 unless graph[:children]

        maximum = graph[:children].map do |node|
          (node[:y] || 0) + (node[:height] || 100)
        end.max || 600
        maximum + 40
      end

      def large_text_size
        valid_font_size(theme&.typography&.font_size_large) || 16.0
      end

      def small_text_size
        valid_font_size(theme&.typography&.font_size_small) || 12.0
      end

      def valid_font_size(font_size)
        font_size if font_size.is_a?(Numeric) && font_size.finite? &&
          font_size.positive?
      end

      def layout_options
        build_elk_options(
          algorithm: ALGORITHM_LAYERED,
          direction: DIRECTION_RIGHT,
          ElkOptions::NODE_NODE_SPACING => ENTITY_SPACING,
          ElkOptions::LAYER_SPACING => ENTITY_SPACING,
          ElkOptions::EDGE_NODE_SPACING => 50,
          ElkOptions::EDGE_EDGE_SPACING => 30,
          ElkOptions::NODE_PLACEMENT => "NETWORK_SIMPLEX",
          ElkOptions::MODEL_ORDER => "NODES_AND_EDGES",
          ElkOptions::HIERARCHY_HANDLING => "INCLUDE_CHILDREN",
        )
      end

      def value(item, key)
        item.is_a?(Hash) ? item[key] : item.public_send(key)
      end

      class << self
        private

        def value(item, key, default = nil)
          result = item.is_a?(Hash) ? item[key] : item.public_send(key)
          result.nil? ? default : result
        end

        def one_lines(point, opposite)
          angle = Math.atan2(opposite.y - point.y, opposite.x - point.x)
          perpendicular = angle + (Math::PI / 2)
          half = CARDINALITY_SIZE / 2
          [Line.new(
            x1: point.x + (half * Math.cos(perpendicular)),
            y1: point.y + (half * Math.sin(perpendicular)),
            x2: point.x - (half * Math.cos(perpendicular)),
            y2: point.y - (half * Math.sin(perpendicular)),
          )]
        end

        def circle(point, opposite)
          angle = Math.atan2(opposite.y - point.y, opposite.x - point.x)
          offset = CARDINALITY_SIZE / 2
          Circle.new(
            cx: point.x + (offset * Math.cos(angle)),
            cy: point.y + (offset * Math.sin(angle)),
            radius: CARDINALITY_SIZE / 3,
          )
        end

        def crows_foot(point, opposite)
          angle = Math.atan2(opposite.y - point.y, opposite.x - point.x)
          base_x = point.x + (CARDINALITY_SIZE * Math.cos(angle))
          base_y = point.y + (CARDINALITY_SIZE * Math.sin(angle))
          [-Math::PI / 4, 0, Math::PI / 4].map do |offset|
            line_angle = angle + Math::PI + offset
            Line.new(
              x1: base_x, y1: base_y,
              x2: base_x + (CARDINALITY_SIZE * Math.cos(line_angle)),
              y2: base_y + (CARDINALITY_SIZE * Math.sin(line_angle))
            )
          end
        end
      end
    end
  end
end
