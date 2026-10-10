# frozen_string_literal: true

require_relative "base"
require_relative "../diagram/requirement"
require_relative "../notation/mermaid/ir_adapters/requirement"

module Sirena
  module Layout
    # Requirement diagram transformer for converting requirement models to positioned layouts.
    #
    # Converts a requirement diagram model into a positioned layout structure.
    # Handles requirement and element positioning, relationship routing,
    # and hierarchical layout based on dependencies.
    #
    # @example Transform a requirement diagram
    #   transform = Requirement.new
    #   layout = transform.to_layout(requirement_diagram)
    class Requirement < Base
      SemanticRequirement = Struct.new(
        :name, :type, :id, :text, :risk, :verifymethod,
        keyword_init: true
      )
      SemanticElement = Struct.new(
        :name, :type, :docref, keyword_init: true
      )
      SemanticRelationship = Struct.new(
        :source, :target, :type, keyword_init: true
      )
      SemanticDiagram = Struct.new(
        :requirements, :elements, :relationships, keyword_init: true
      )
      private_constant :SemanticRequirement, :SemanticElement,
                       :SemanticRelationship, :SemanticDiagram

      # Default dimensions
      DEFAULT_REQ_WIDTH = 180
      DEFAULT_REQ_HEIGHT = 140
      DEFAULT_ELEM_WIDTH = 150
      DEFAULT_ELEM_HEIGHT = 80
      DEFAULT_SPACING_X = 100
      DEFAULT_SPACING_Y = 80
      DEFAULT_PADDING = 20
      HEADER_HEIGHT = 30
      LINE_HEIGHT = 16
      HEXAGON_FACTORS = [[-1, 0], [-0.5, -1], [0.5, -1], [1, 0],
                         [0.5, 1], [-0.5, 1]].freeze

      REQUIREMENT_TYPE_LABELS = {
        "requirement" => "Requirement",
        "functionalRequirement" => "Functional Requirement",
        "interfaceRequirement" => "Interface Requirement",
        "performanceRequirement" => "Performance Requirement",
        "physicalRequirement" => "Physical Requirement",
        "designConstraint" => "Design Constraint",
      }.freeze

      class Point < Lutaml::Model::Serializable
        attribute :x, :float
        attribute :y, :float
      end

      class Rect < Lutaml::Model::Serializable
        attribute :x, :float
        attribute :y, :float
        attribute :width, :float
        attribute :height, :float
      end

      class Label < Lutaml::Model::Serializable
        attribute :text, :string
        attribute :x, :float
        attribute :y, :float
        attribute :font_size, :float
        attribute :font_weight, :string
        attribute :text_anchor, :string
        attribute :role, :string
      end

      class Section < Lutaml::Model::Serializable
        attribute :start_point, Point
        attribute :end_point, Point
        attribute :bend_points, Point, collection: true, default: -> { [] }
      end

      class Node < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :x, :float
        attribute :y, :float
        attribute :width, :float
        attribute :height, :float
        attribute :labels, Label, collection: true, default: -> { [] }
        attribute :kind, :string
        attribute :risk, :string
        attribute :box, Rect
        attribute :header, Rect
        attribute :shape_points, :string
        attribute :children, Node, collection: true, default: -> { [] }
      end

      class Edge < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :source, :string
        attribute :target, :string
        attribute :sections, Section, collection: true, default: -> { [] }
        attribute :labels, Label, collection: true, default: -> { [] }
        attribute :label_background, Rect
        attribute :path, :string
      end

      class Scene < Layout::Scene
        attribute :view_box, :string
        attribute :children, Node, collection: true, default: -> { [] }
        attribute :edges, Edge, collection: true, default: -> { [] }
      end

      # Converts a requirement diagram to a positioned layout structure.
      #
      # @param diagram [Diagram::Requirement] the requirement diagram to transform
      # @return [Hash] positioned layout hash
      def build_graph(diagram)
        diagram = semantic_diagram(ir_graph(diagram))
        nodes_layout = calculate_node_positions(diagram)
        relationships_layout = calculate_relationships(diagram, nodes_layout)
        graph_result(nodes_layout, relationships_layout)
      end

      private

      def graph_result(nodes_layout, relationships_layout)
        {
          requirements: nodes_layout[:requirements],
          elements: nodes_layout[:elements],
          relationships: relationships_layout,
          width: nodes_layout[:width],
          height: nodes_layout[:height],
        }
      end

      NORMALIZED_REQUIREMENT_TYPES = {
        "requirement" => "requirement",
        "functional_requirement" => "functionalRequirement",
        "interface_requirement" => "interfaceRequirement",
        "performance_requirement" => "performanceRequirement",
        "physical_requirement" => "physicalRequirement",
        "design_constraint" => "designConstraint",
      }.freeze
      ENTITY_ROLES = %w[requirement element].freeze
      private_constant :NORMALIZED_REQUIREMENT_TYPES
      private_constant :ENTITY_ROLES

      def ir_graph(diagram)
        return diagram if diagram.is_a?(IR::Graph)

        Notation::Mermaid::IRAdapters::Requirement.call(diagram)
      end

      def semantic_diagram(graph)
        entity_nodes = graph.nodes.select do |node|
          ENTITY_ROLES.include?(node.role)
        end
        children = graph.nodes.group_by(&:parent_id)
        SemanticDiagram.new(
          requirements: requirement_models(entity_nodes, children),
          elements: element_models(entity_nodes, children),
          relationships: relationship_models(graph.edges, entity_nodes),
        )
      end

      def requirement_models(nodes, children)
        nodes.select { |node| node.role == "requirement" }.map do |node|
          requirement_model(node, children[node.id])
        end
      end

      def requirement_model(node, child_nodes)
        fields = semantic_fields(child_nodes)
        normalized_type = fields["requirement_type"]
        SemanticRequirement.new(
          name: node.label,
          type: requirement_type(normalized_type),
          id: fields["external_identifier"], text: fields["description"],
          risk: fields["risk"],
          verifymethod: fields["verification_method"]
        )
      end

      def requirement_type(normalized_type)
        NORMALIZED_REQUIREMENT_TYPES.fetch(normalized_type, normalized_type)
      end

      def element_models(nodes, children)
        nodes.filter_map do |node|
          next unless node.role == "element"

          fields = semantic_fields(children[node.id])
          SemanticElement.new(
            name: node.label, type: fields["element_type"],
            docref: fields["document_reference"]
          )
        end
      end

      def semantic_fields(nodes)
        Array(nodes).to_h { |node| [node.role, node.label] }
      end

      def relationship_models(edges, nodes)
        nodes_by_id = nodes.to_h { |node| [node.id, node] }
        edges.filter_map { |edge| relationship_model(edge, nodes_by_id) }
      end

      def relationship_model(edge, nodes_by_id)
        source = nodes_by_id[edge.source_id]
        target = nodes_by_id[edge.target_id]
        return unless source && target

        SemanticRelationship.new(
          source: source.label, target: target.label, type: edge.role,
        )
      end

      def scene(diagram)
        graph = build_graph(diagram)
        nodes = typed_requirement_nodes(graph[:requirements]) +
          typed_element_nodes(graph[:elements])
        Scene.new(
          width: graph[:width], height: graph[:height],
          view_box: "0 0 #{graph[:width]} #{graph[:height]}",
          children: nodes, edges: typed_relationships(graph[:relationships])
        )
      end

      def typed_requirement_nodes(requirements)
        requirements.values.map do |info|
          requirement_node(info[:requirement], info)
        end
      end

      def requirement_node(requirement, geometry)
        Node.new(
          id: requirement.name, kind: "requirement", risk: requirement.risk,
          x: geometry[:x], y: geometry[:y], width: geometry[:width],
          height: geometry[:height], box: rect(geometry),
          header: Rect.new(x: geometry[:x], y: geometry[:y],
                           width: geometry[:width], height: HEADER_HEIGHT),
          labels: requirement_labels(requirement, geometry)
        )
      end

      def requirement_labels(requirement, geometry)
        requirement_header_labels(requirement, geometry) +
          positioned_property_labels(requirement, geometry)
      end

      def requirement_header_labels(requirement, geometry)
        type_label = REQUIREMENT_TYPE_LABELS.fetch(requirement.type,
                                                   requirement.type)
        middle_y = geometry[:y] + (HEADER_HEIGHT / 2)
        [requirement_type_label(type_label, geometry, middle_y),
         requirement_name_label(requirement.name, geometry, middle_y)]
      end

      def requirement_type_label(type_label, geometry, middle_y)
        Label.new(text: "<<#{type_label}>>", x: geometry[:x] + 10,
                  y: middle_y, font_size: 12, font_weight: "bold",
                  role: "header")
      end

      def requirement_name_label(name, geometry, middle_y)
        Label.new(text: name, x: geometry[:x] + geometry[:width] - 10,
                  y: middle_y, font_size: 11, text_anchor: "end",
                  role: "header")
      end

      def positioned_property_labels(requirement, geometry)
        y_coord = geometry[:y] + HEADER_HEIGHT + 15
        requirement_property_rows(requirement, geometry).map do |row|
          label = property_label(row[:text], geometry[:x], y_coord,
                                 role: row[:role], weight: row[:weight])
          y_coord += row[:advance]
          label
        end
      end

      def requirement_property_rows(requirement, geometry)
        id_rows(requirement) + text_rows(requirement, geometry) +
          risk_rows(requirement) + verification_rows(requirement)
      end

      def id_rows(requirement)
        return [] unless requirement.id

        [property_row("ID: #{requirement.id}")]
      end

      def text_rows(requirement, geometry)
        return [] unless requirement.text

        lines = wrap_text("Text: #{requirement.text}", geometry[:width] - 20,
                          property_font_size)
        lines.map.with_index do |line, index|
          gap = index == lines.length - 1 ? 5 : 0
          property_row(line, advance: LINE_HEIGHT + gap)
        end
      end

      def risk_rows(requirement)
        return [] unless requirement.risk

        [property_row("Risk: #{requirement.risk.capitalize}",
                      role: "risk", weight: "bold")]
      end

      def verification_rows(requirement)
        return [] unless requirement.verifymethod

        [property_row("Verification: #{requirement.verifymethod.capitalize}")]
      end

      def property_row(text, advance: LINE_HEIGHT, role: "property",
                       weight: nil)
        { text: text, advance: advance, role: role, weight: weight }
      end

      def property_label(text, left, y_coord, role: "property", weight: nil)
        Label.new(text: text, x: left + 10, y: y_coord,
                  font_size: property_font_size, font_weight: weight,
                  role: role)
      end

      def typed_element_nodes(elements)
        elements.values.map do |info|
          element = info[:element]
          Node.new(
            id: element.name, kind: "element", x: info[:x], y: info[:y],
            width: info[:width], height: info[:height], box: rect(info),
            shape_points: hexagon_points(info),
            labels: element_labels(element, info)
          )
        end
      end

      def element_labels(element, geometry)
        center_x = geometry[:x] + (geometry[:width] / 2)
        center_y = geometry[:y] + (geometry[:height] / 2)
        [element_stereotype(center_x, center_y),
         element_name(element.name, center_x, center_y),
         *element_detail_labels(element, center_x, center_y)]
      end

      def element_stereotype(center_x, center_y)
        Label.new(text: "<<Element>>", x: center_x, y: center_y - 26,
                  font_size: 11, text_anchor: "middle", role: "element")
      end

      def element_name(name, center_x, center_y)
        Label.new(text: name, x: center_x, y: center_y - 10,
                  font_size: 14, font_weight: "bold",
                  text_anchor: "middle", role: "element")
      end

      def element_detail_labels(element, center_x, center_y)
        [element.type && element_detail("Type: #{element.type}", center_x,
                                        center_y + 10),
         element.docref && element_detail("Doc Ref: #{element.docref}",
                                          center_x, center_y + 26)].compact
      end

      def element_detail(text, center_x, center_y)
        Label.new(text: text, x: center_x, y: center_y, font_size: 11,
                  text_anchor: "middle", role: "detail")
      end

      def hexagon_points(geometry)
        center = box_center(geometry)
        half_size = Point.new(x: geometry[:width] / 2,
                              y: geometry[:height] / 2)
        HEXAGON_FACTORS.map do |factors|
          scaled_point(center, half_size, factors)
        end.join(" ")
      end

      def box_center(geometry)
        Point.new(x: geometry[:x] + (geometry[:width] / 2),
                  y: geometry[:y] + (geometry[:height] / 2))
      end

      def scaled_point(center, half_size, factors)
        [center.x + (half_size.x * factors[0]),
         center.y + (half_size.y * factors[1])].join(",")
      end

      def typed_relationships(relationships)
        relationships.map.with_index do |relationship, index|
          typed_relationship(relationship, index)
        end
      end

      def typed_relationship(relationship, index)
        points = relationship_points(relationship)
        start_point, end_point = points
        bends = relationship_bends(start_point, end_point)
        decoration = relationship_label(relationship, start_point, end_point)
        relationship_edge(relationship, index, points, bends, decoration)
      end

      def relationship_points(relationship)
        [Point.new(x: relationship[:from_x], y: relationship[:from_y]),
         Point.new(x: relationship[:to_x], y: relationship[:to_y])]
      end

      def relationship_bends(start_point, end_point)
        offset = (end_point.y - start_point.y).abs / 3
        [Point.new(x: start_point.x, y: start_point.y + offset),
         Point.new(x: end_point.x, y: end_point.y - offset)]
      end

      def relationship_edge(relationship, index, points, bends, decoration)
        start_point, end_point = points
        label, background = decoration
        Edge.new(
          id: "relationship_#{index}", source: relationship[:source],
          target: relationship[:target],
          sections: [relationship_section(start_point, end_point, bends)],
          labels: [label].compact, label_background: background,
          path: bezier_path(start_point, bends, end_point)
        )
      end

      def relationship_section(start_point, end_point, bends)
        Section.new(start_point: start_point, end_point: end_point,
                    bend_points: bends)
      end

      def relationship_label(relationship, start_point, end_point)
        return [nil, nil] unless relationship[:type]

        text = "<<#{relationship[:type]}>>"
        midpoint = relationship_midpoint(start_point, end_point)
        width = (relationship[:type].length + 4) * 7
        [relationship_text(text, midpoint),
         relationship_background(midpoint, width)]
      end

      def relationship_midpoint(start_point, end_point)
        Point.new(x: (start_point.x + end_point.x) / 2,
                  y: (start_point.y + end_point.y) / 2)
      end

      def relationship_text(text, midpoint)
        Label.new(text: text, x: midpoint.x, y: midpoint.y, font_size: 10,
                  text_anchor: "middle", role: "relationship")
      end

      def relationship_background(midpoint, width)
        Rect.new(x: midpoint.x - (width / 2), y: midpoint.y - 10,
                 width: width, height: 18)
      end

      def bezier_path(start_point, bends, end_point)
        "M #{start_point.x} #{start_point.y} " \
          "C #{bends[0].x} #{bends[0].y}, " \
          "#{bends[1].x} #{bends[1].y}, #{end_point.x} #{end_point.y}"
      end

      def rect(geometry)
        Rect.new(x: geometry[:x], y: geometry[:y], width: geometry[:width],
                 height: geometry[:height])
      end

      def calculate_node_positions(diagram)
        requirements = diagram.requirements
        elements = diagram.elements
        relationships = diagram.relationships

        # Build dependency graph to determine layout
        levels = build_dependency_levels(requirements, elements, relationships)

        positioned_requirements = {}
        positioned_elements = {}

        current_y = DEFAULT_PADDING
        max_width = 0

        levels.each_with_index do |level_nodes, level_idx|
          current_x = DEFAULT_PADDING
          max_height = 0

          level_nodes.each do |node|
            if node[:type] == :requirement
              req = node[:object]
              dims = calculate_requirement_dimensions(req)

              positioned_requirements[req.name] = {
                requirement: req,
                x: current_x,
                y: current_y,
                width: dims[:width],
                height: dims[:height],
                level: level_idx,
              }
            else
              elem = node[:object]
              dims = calculate_element_dimensions(elem)

              positioned_elements[elem.name] = {
                element: elem,
                x: current_x,
                y: current_y,
                width: dims[:width],
                height: dims[:height],
                level: level_idx,
              }
            end

            current_x += dims[:width] + DEFAULT_SPACING_X
            max_height = [max_height, dims[:height]].max
          end

          max_width = [max_width, current_x].max
          current_y += max_height + DEFAULT_SPACING_Y
        end

        {
          requirements: positioned_requirements,
          elements: positioned_elements,
          width: max_width + DEFAULT_PADDING,
          height: current_y + DEFAULT_PADDING,
        }
      end

      def build_dependency_levels(requirements, elements, relationships)
        # Build a simple level-based layout
        # Level 0: Elements
        # Level 1: Requirements that depend on elements
        # Level 2+: Requirements that depend on other requirements

        nodes_by_name = {}
        requirements.each { |r| nodes_by_name[r.name] = { type: :requirement, object: r, level: nil } }
        elements.each { |e| nodes_by_name[e.name] = { type: :element, object: e, level: 0 } }

        # Build dependency map
        dependencies = Hash.new { |h, k| h[k] = [] }
        relationships.each do |rel|
          # Source depends on target (arrow direction)
          dependencies[rel.source] << rel.target
        end

        # Calculate levels for requirements
        changed = true
        max_iterations = 10
        iterations = 0

        while changed && iterations < max_iterations
          changed = false
          iterations += 1

          requirements.each do |req|
            node = nodes_by_name[req.name]
            next if node[:level]

            deps = dependencies[req.name]
            if deps.empty?
              # No dependencies, place at level 1
              node[:level] = 1
              changed = true
            else
              # Check if all dependencies have levels
              dep_levels = deps.map { |d| nodes_by_name[d]&.dig(:level) }.compact
              if dep_levels.size == deps.size
                # All dependencies have levels
                max_dep_level = dep_levels.max || 0
                node[:level] = max_dep_level + 1
                changed = true
              end
            end
          end
        end

        # Assign default level to any remaining nodes
        nodes_by_name.each_value do |node|
          node[:level] ||= 1 if node[:type] == :requirement
        end

        # Group by level
        levels = []
        nodes_by_name.values.group_by { |n| n[:level] }.sort.each do |_level, nodes|
          levels << nodes
        end

        levels
      end

      def calculate_requirement_dimensions(requirement)
        text_lines = requirement_text_line_count(requirement.text)
        height = DEFAULT_REQ_HEIGHT + ((text_lines - 1) * 20)
        { width: DEFAULT_REQ_WIDTH,
          height: [height, DEFAULT_REQ_HEIGHT].max }
      end

      def requirement_text_line_count(text)
        return 1 if !text || text.empty?

        wrap_text(text, DEFAULT_REQ_WIDTH - 20, property_font_size).length
      end

      def calculate_element_dimensions(_element)
        {
          width: DEFAULT_ELEM_WIDTH,
          height: DEFAULT_ELEM_HEIGHT,
        }
      end

      def calculate_relationships(diagram, nodes_layout)
        requirements = nodes_layout[:requirements]
        elements = nodes_layout[:elements]
        all_nodes = requirements.merge(elements)

        diagram.relationships.map do |rel|
          source_node = all_nodes[rel.source]
          target_node = all_nodes[rel.target]

          next unless source_node && target_node

          # Calculate connection points
          source_x = source_node[:x] + (source_node[:width] / 2)
          source_y = source_node[:y] + source_node[:height]
          target_x = target_node[:x] + (target_node[:width] / 2)
          target_y = target_node[:y]

          {
            relationship: rel,
            source: rel.source,
            target: rel.target,
            type: rel.type,
            from_x: source_x,
            from_y: source_y,
            to_x: target_x,
            to_y: target_y,
          }
        end.compact
      end

      def wrap_text(text, max_width, font_size)
        text.split.each_with_object([]) do |word, lines|
          candidate = [lines.pop, word].compact.join(" ")
          if measure_text(candidate, font_size: font_size)[:width] <= max_width
            lines << candidate
          else
            previous, current = candidate.rpartition(" ").values_at(0, 2)
            lines << previous unless previous.empty?
            lines << current
          end
        end
      end

      def property_font_size
        theme.typography&.font_size_small ||
          Theme::Registry.get(:default).typography.font_size_small
      end
    end
  end
end
