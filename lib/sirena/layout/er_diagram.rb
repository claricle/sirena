# frozen_string_literal: true

require_relative "base"
require_relative "grid"
require_relative "../diagram/er_diagram"
require_relative "../notation/mermaid/ir_adapters/er_diagram"

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

      SemanticAttribute = Struct.new(
        :name, :attribute_type, :key_type, :note, keyword_init: true
      )
      SemanticEntity = Struct.new(
        :id, :name, :attributes, :classes, keyword_init: true
      )
      SemanticRelationship = Struct.new(
        :from_id, :to_id, :relationship_type, :cardinality_from,
        :cardinality_to, :label, keyword_init: true
      )
      SemanticDiagram = Struct.new(
        :id, :title, :direction, :theme, :entities, :relationships,
        :class_defs, keyword_init: true
      )
      private_constant :SemanticAttribute, :SemanticEntity,
                       :SemanticRelationship, :SemanticDiagram

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
        attribute :attributes, AttributeRow,
                  collection: true, default: -> { [] }
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
        bounds = node_bounds(from_node)
        from = center(bounds)
        to = center(node_bounds(to_node))
        boundary_point(bounds, from, to)
      end

      def self.marker(point, opposite, cardinality)
        lines = []
        circles = []
        one = %w[one one_or_more zero_or_one]
        many = %w[zero_or_more one_or_more]
        lines.concat(one_lines(point, opposite)) if one.include?(cardinality)
        if %w[zero_or_more zero_or_one].include?(cardinality)
          circles << circle(point, opposite)
        end
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

      def self.attribute_row(x_coordinate, y_coordinate, attribute, theme: nil)
        layout = new
        layout.theme = theme if theme
        font_size = layout.send(:small_text_size)
        AttributeRow.new(
          text: layout.send(:format_attribute, attribute),
          x: x_coordinate + ENTITY_PADDING,
          y: y_coordinate + font_size,
          font_size: font_size,
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
        diagram = semantic_diagram(ir_graph(diagram))
        {
          id: diagram.id || "er_diagram",
          children: transform_entities(diagram),
          edges: transform_relationships(diagram),
          class_defs: diagram.class_defs,
          layoutOptions: layout_options,
        }
      end

      def ir_graph(diagram)
        return diagram if diagram.is_a?(IR::Graph)

        Notation::Mermaid::IRAdapters::ErDiagram.call(diagram)
      end

      def semantic_diagram(graph)
        children, nodes_by_id = semantic_context(graph)
        SemanticDiagram.new(
          **semantic_metadata(graph, children),
          entities: semantic_entities(graph, children),
          relationships: semantic_relationships(graph, children, nodes_by_id),
          class_defs: semantic_class_defs(graph, children),
        )
      end

      def semantic_context(graph)
        children = graph.nodes.group_by(&:parent_id)
        nodes_by_id = graph.nodes.to_h { |node| [node.id, node] }
        [children, nodes_by_id]
      end

      def semantic_metadata(graph, children)
        settings = graph.nodes.find { |node| node.role == "diagram_settings" }
        fields = semantic_fields(children[settings&.id])
        {
          id: fields["diagram_identifier"], title: graph.label,
          direction: fields["layout_direction"],
          theme: fields["theme_reference"]
        }
      end

      def semantic_entities(graph, children)
        graph.nodes.select { |node| node.role == "entity" }.map do |node|
          semantic_entity(node, children)
        end
      end

      def semantic_entity(node, children)
        child_nodes = children[node.id] || []
        SemanticEntity.new(
          id: source_identifier(node, children), name: node.label,
          classes: child_nodes
            .select { |child| child.role == "style_reference" }.map(&:label),
          attributes: child_nodes.select { |child| child.role == "attribute" }
            .map { |attribute| semantic_attribute(attribute, children) }
        )
      end

      def semantic_attribute(node, children)
        fields = semantic_fields(children[node.id])
        SemanticAttribute.new(
          name: node.label, attribute_type: fields["attribute_type"],
          key_type: fields["key_type"], note: fields["note"]
        )
      end

      def semantic_relationships(graph, children, nodes_by_id)
        graph.edges.map do |edge|
          semantic_relationship(edge, children, nodes_by_id)
        end
      end

      def semantic_relationship(edge, children, nodes_by_id)
        fields = semantic_fields(children[edge.parent_id])
        SemanticRelationship.new(
          from_id: source_identifier(nodes_by_id[edge.source_id], children),
          to_id: source_identifier(nodes_by_id[edge.target_id], children),
          relationship_type: relationship_type(edge, fields),
          cardinality_from: cardinality(edge, fields, :source),
          cardinality_to: cardinality(edge, fields, :target),
          label: edge.label,
        )
      end

      def cardinality(edge, fields, endpoint)
        fields["#{endpoint}_cardinality"] ||
          edge.properties.public_send("#{endpoint}_marker")
      end

      def relationship_type(edge, fields)
        return fields["relationship_type"] if fields["relationship_type"]
        return "identifying" if edge.role == "identifying_relationship"

        "non-identifying"
      end

      def semantic_class_defs(graph, children)
        graph.nodes.select { |node| node.role == "style_class" }.to_h do |node|
          fields = semantic_fields(children[node.id])
          [node.label, fields["style_declaration"]]
        end
      end

      def semantic_fields(nodes)
        Array(nodes).to_h { |node| [node.role, node.label] }
      end

      def source_identifier(node, children)
        return unless node

        semantic_fields(children[node.id]).fetch("original_identifier", node.id)
      end

      def scene_from_graph(graph)
        width, height = scene_dimensions(graph)
        Scene.new(
          id: graph[:id] || "er_diagram",
          width: width,
          height: height,
          view_box: "0 0 #{width} #{height}",
          children: typed_nodes(graph[:children] || []),
          edges: typed_edges(graph[:edges] || [], graph[:children] || []),
          class_defs: typed_class_defs(graph[:class_defs] || {}),
        )
      end

      def typed_nodes(nodes)
        nodes.map { |node| typed_node(node) }
      end

      def typed_node(node)
        geometry = node_geometry(node)
        metadata = node[:metadata] || {}
        Node.new(**typed_node_values(node, metadata, geometry))
      end

      def node_geometry(node)
        {
          x: node[:x] || 0, y: node[:y] || 0,
          width: node[:width] || 150, height: node[:height] || 100
        }
      end

      def typed_node_values(node, metadata, geometry)
        label = node_label(node, metadata, geometry)
        separator = node_separator(label, geometry)
        {
          id: node[:id], **geometry, labels: [label], shape: "rect",
          name: label.text, classes: metadata[:classes] || [],
          attributes: typed_attributes(
            metadata[:attributes] || [], geometry[:x], separator.y1
          ),
          separator: separator
        }
      end

      def node_label(node, metadata, geometry)
        name = metadata[:name] || node[:id]
        y = geometry[:y] + ENTITY_PADDING + large_text_size
        positioned_label(
          name, geometry[:x] + (geometry[:width] / 2), y, large_text_size
        )
      end

      def node_separator(label, geometry)
        y = label.y + TEXT_LINE_HEIGHT
        Line.new(x1: geometry[:x], y1: y,
                 x2: geometry[:x] + geometry[:width], y2: y)
      end

      def typed_attributes(attributes, x_coordinate, separator_y)
        attributes.each_with_index.map do |attribute, index|
          typed_attribute(attribute, x_coordinate, separator_y, index)
        end
      end

      def typed_attribute(attribute, x_coordinate, separator_y, index)
        AttributeRow.new(
          name: attribute[:name], attribute_type: attribute[:attribute_type],
          key_type: attribute[:key_type], note: attribute[:note],
          text: format_attribute(attribute),
          x: x_coordinate + ENTITY_PADDING,
          y: separator_y + ENTITY_PADDING + small_text_size +
            (index * TEXT_LINE_HEIGHT),
          font_size: small_text_size
        )
      end

      def typed_edges(edges, nodes)
        nodes_by_id = nodes.to_h { |node| [node[:id], node] }
        edges.filter_map { |edge| typed_edge_for(edge, nodes_by_id) }
      end

      def typed_edge_for(edge, nodes_by_id)
        source = nodes_by_id[edge[:sources]&.first]
        target = nodes_by_id[edge[:targets]&.first]
        typed_edge(edge, source, target) if source && target
      end

      def typed_edge(edge, source, target)
        sections = typed_sections(edge, source, target)
        Edge.new(
          id: edge[:id], source: source[:id], target: target[:id],
          sections: sections, **typed_edge_details(edge, sections)
        )
      end

      def typed_edge_details(edge, sections)
        metadata = edge[:metadata] || {}
        {
          labels: typed_edge_labels(edge, sections),
          relationship_type: metadata[:relationship_type] || "non-identifying",
          cardinality_from: metadata[:cardinality_from],
          cardinality_to: metadata[:cardinality_to],
          **typed_marker_values(sections, metadata),
        }
      end

      def typed_edge_labels(edge, sections)
        label = (edge[:labels] || []).find { |item| !item[:position] }
        typed_relationship_labels(label, *section_endpoints(sections))
      end

      def typed_marker_values(sections, metadata)
        source, target = typed_markers(sections, metadata)
        { source_marker: source, target_marker: target }
      end

      def typed_sections(edge, source, target)
        sections, supplied = supplied_value(edge, :sections)
        return default_sections(source, target) unless supplied

        Array(sections).map { |section| typed_section(section) }
      end

      def default_sections(source, target)
        from = self.class.connection_point(source, target)
        to = self.class.connection_point(target, source)
        [Section.new(start_point: from, end_point: to)]
      end

      def typed_section(section)
        return section if section.is_a?(Section)

        Section.new(
          start_point: typed_section_point(section, :start_point, :startPoint),
          end_point: typed_section_point(section, :end_point, :endPoint),
          bend_points: typed_bend_points(section),
        )
      end

      def typed_section_point(section, snake_key, camel_key)
        self.class.point(hash_value(section, snake_key, camel_key))
      end

      def typed_bend_points(section)
        points = hash_value(section, :bend_points, :bendPoints)
        Array(points).map { |point| self.class.point(point) }
      end

      def section_endpoints(sections)
        return [nil, nil] if sections.empty?

        [sections.first.start_point, sections.last.end_point]
      end

      def typed_markers(sections, metadata)
        return [Marker.new, Marker.new] if sections.empty?

        [
          typed_source_marker(sections.first, metadata[:cardinality_from]),
          typed_target_marker(sections.last, metadata[:cardinality_to]),
        ]
      end

      def typed_source_marker(section, cardinality)
        opposite = section.bend_points.first || section.end_point
        self.class.marker(section.start_point, opposite, cardinality)
      end

      def typed_target_marker(section, cardinality)
        opposite = section.bend_points.last || section.start_point
        self.class.marker(section.end_point, opposite, cardinality)
      end

      def supplied_value(hash, key)
        return [hash[key], true] if hash.key?(key)
        return [hash[key.to_s], true] if hash.key?(key.to_s)

        [nil, false]
      end

      def hash_value(hash, *keys)
        keys.each do |key|
          return hash[key] if hash.key?(key)
          return hash[key.to_s] if hash.key?(key.to_s)
        end
        nil
      end

      def typed_relationship_labels(label, from, to)
        return [] unless label && from && to

        [self.class.relationship_label(label[:text], from, to, small_text_size)]
      end

      def typed_class_defs(class_defs)
        class_defs.map do |name, declaration|
          ClassDef.new(name: name, declaration: declaration)
        end
      end

      def positioned_label(text, x_coordinate, y_coordinate, font_size)
        dimensions = measure_text(text, font_size: font_size)
        Label.new(text: text, width: dimensions[:width],
                  height: dimensions[:height],
                  x: x_coordinate,
                  y: y_coordinate,
                  font_size: font_size)
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
              classes: entity.classes,
              attributes: entity.attributes.map do |item|
                attribute_to_hash(item)
              end,
            },
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
        {
          width: entity_width(entity),
          height: entity_height(entity),
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
        %i[key_type attribute_type name note]
          .filter_map { |key| value(attribute, key) }
          .reject(&:empty?)
          .join(" ")
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

      def scene_dimensions(graph)
        padding = empty_graph?(graph) ? EMPTY_DIAGRAM_PADDING : DIAGRAM_PADDING
        [content_width(graph), content_height(graph)].map do |extent|
          extent + (padding * 2)
        end
      end

      def entity_width(entity)
        widths = entity.attributes.map do |attribute|
          measured_width(format_attribute(attribute),
                         small_text_size, monospace: true)
        end
        widths.push(MIN_ENTITY_WIDTH,
                    measured_width(entity.name, large_text_size)).max +
          (ENTITY_PADDING * 2)
      end

      def entity_height(entity)
        ((1 + entity.attributes.length) * LINE_HEIGHT) +
          (ENTITY_PADDING * 2)
      end

      def content_width(graph)
        content_extent(graph, :x, :width, 150, 800)
      end

      def content_height(graph)
        content_extent(graph, :y, :height, 100, 600)
      end

      def content_extent(graph, coordinate, dimension, default_size, fallback)
        return 0 if empty_graph?(graph)
        return fallback unless graph[:children]

        maximum = graph[:children].map do |node|
          (node[coordinate] || 0) + (node[dimension] || default_size)
        end.max || fallback
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

        def node_bounds(node)
          {
            x: value(node, :x, 0), y: value(node, :y, 0),
            width: value(node, :width, 150),
            height: value(node, :height, 100)
          }
        end

        def center(bounds)
          {
            x: bounds[:x] + (bounds[:width] / 2),
            y: bounds[:y] + (bounds[:height] / 2),
          }
        end

        def boundary_point(bounds, from, to)
          dx = to[:x] - from[:x]
          dy = to[:y] - from[:y]
          return point(from) if coincident?(dx, dy)

          return horizontal_boundary(bounds, from, dx, dy) if dx.abs > dy.abs

          vertical_boundary(bounds, from, dx, dy)
        end

        def coincident?(delta_x, delta_y)
          delta_x.abs < 0.001 && delta_y.abs < 0.001
        end

        def horizontal_boundary(bounds, from, delta_x, delta_y)
          x = delta_x.positive? ? bounds[:x] + bounds[:width] : bounds[:x]
          y = if delta_y.abs < 0.001
                from[:y]
              else
                from[:y] + ((delta_y / delta_x) * (x - from[:x]))
              end
          Point.new(x: x, y: y)
        end

        def vertical_boundary(bounds, from, delta_x, delta_y)
          y = delta_y.positive? ? bounds[:y] + bounds[:height] : bounds[:y]
          x = if delta_x.abs < 0.001
                from[:x]
              else
                from[:x] + ((delta_x / delta_y) * (y - from[:y]))
              end
          Point.new(x: x, y: y)
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
          center = offset_point(point, opposite, CARDINALITY_SIZE / 2)
          Circle.new(
            cx: center.x,
            cy: center.y,
            radius: CARDINALITY_SIZE / 3,
          )
        end

        def offset_point(point, opposite, distance)
          angle = direction(point, opposite)
          Point.new(
            x: point.x + (distance * Math.cos(angle)),
            y: point.y + (distance * Math.sin(angle)),
          )
        end

        def direction(point, opposite)
          Math.atan2(opposite.y - point.y, opposite.x - point.x)
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
