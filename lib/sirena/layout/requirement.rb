# frozen_string_literal: true

require_relative "base"
require_relative "../diagram/requirement"
require_relative "../notation/mermaid/ir_adapters/requirement"

module Sirena
  module Layout
    # Requirement diagram transformer for converting requirement models to
    # positioned layouts.
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

      # Box metrics measured from mmdc output: 24px rows, 10px side padding,
      # 8px above the first row, a 20px gap under the name, 12px below.
      ROW_HEIGHT = 24
      PADDING_X = 10
      TOP_PADDING = 8
      SECTION_GAP = 20
      BOTTOM_PADDING = 12
      HEADER_ROWS = 2
      HEADER_HEIGHT = TOP_PADDING + (HEADER_ROWS * ROW_HEIGHT) +
        (SECTION_GAP / 2)
      BOLD_WIDTH_FACTOR = 1.06
      NODE_SEPARATION = 50
      RANK_SEPARATION = 74
      CANVAS_MARGIN = 8
      # Metrics-only: boxes are sized as if text were drawn at mmdc's 16px.
      LABEL_FONT_SIZE = 16
      TEXT_WRAP_WIDTH = 300
      EMPTY_WIDTH = 20
      EMPTY_HEIGHT = 40
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
      # @param diagram [Diagram::Requirement] the requirement diagram to
      #   transform
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
          labels: requirement_labels(geometry)
        )
      end

      def requirement_labels(geometry)
        row_labels(geometry, header_role: "header", body_role: "property")
      end

      def row_labels(geometry, header_role:, body_role:)
        geometry[:rows].each_with_index.map do |row, index|
          header = index < HEADER_ROWS
          row_label(row, index, geometry,
                    header ? header_role : body_role, header)
        end
      end

      def row_label(row, index, geometry, default_role, header)
        center_y = row_center_y(index, geometry)
        Label.new(
          text: row[:text], font_weight: row[:weight],
          font_size: row_font_size(row, index, default_role),
          role: row[:role] || default_role,
          x: header ? geometry[:x] + (geometry[:width] / 2) : geometry[:x] + PADDING_X,
          y: default_role == "property" ? center_y + 5 : center_y,
          text_anchor: header ? "middle" : nil
        )
      end

      def row_font_size(row, index, role)
        return property_font_size if %w[property].include?(role) || row[:role] == "risk"
        return 14 if role == "element" && index == 1
        return 12 if role == "header" && index.zero?

        11
      end

      def row_center_y(index, geometry)
        gap = index < HEADER_ROWS ? 0 : SECTION_GAP
        geometry[:y] + TOP_PADDING + gap + (index * ROW_HEIGHT) +
          (ROW_HEIGHT / 2)
      end

      def requirement_rows(requirement)
        type_label = REQUIREMENT_TYPE_LABELS.fetch(requirement.type,
                                                   requirement.type)
        [text_row("<<#{type_label}>>"),
         text_row(requirement.name, weight: "bold"),
         *requirement_body_rows(requirement)]
      end

      def requirement_body_rows(requirement)
        [
          requirement.id && text_row("ID: #{requirement.id}"),
          *text_rows(requirement.text),
          requirement.risk &&
            text_row("Risk: #{requirement.risk.capitalize}", role: "risk"),
          requirement.verifymethod &&
            text_row("Verification: #{requirement.verifymethod.capitalize}"),
        ].compact
      end

      def text_rows(text)
        return [] unless text

        wrap_text("Text: #{text}", TEXT_WRAP_WIDTH, LABEL_FONT_SIZE)
          .map { |line| text_row(line) }
      end

      def element_rows(element)
        [text_row("<<Element>>"),
         text_row(element.name, weight: "bold"),
         *[element.type && text_row("Type: #{element.type}"),
           element.docref && text_row("Doc Ref: #{element.docref}")].compact]
      end

      def text_row(text, weight: nil, role: nil)
        { text: text, weight: weight, role: role }
      end

      def typed_element_nodes(elements)
        elements.values.map do |info|
          element = info[:element]
          Node.new(
            id: element.name, kind: "element", x: info[:x], y: info[:y],
            width: info[:width], height: info[:height], box: rect(info),
            shape_points: rectangle_points(info),
            labels: row_labels(info, header_role: "element",
                                     body_role: "detail")
          )
        end
      end

      def rectangle_points(geometry)
        right = geometry[:x] + geometry[:width]
        bottom = geometry[:y] + geometry[:height]
        [[geometry[:x], geometry[:y]], [right, geometry[:y]],
         [right, bottom], [geometry[:x], bottom]]
          .map { |point| point.join(",") }.join(" ")
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
        ranks = rank_nodes(diagram)
        sized = ranks.map { |rank| rank.map { |node| size_node(node) } }
        canvas_width = sized.map { |rank| rank_width(rank) }.max.to_f
        positioned = { requirements: {}, elements: {} }
        top = CANVAS_MARGIN
        sized.each_with_index do |rank, level|
          place_rank(rank, level, top, canvas_width, positioned)
          top += rank.map { |node| node[:height] }.max + RANK_SEPARATION
        end
        return positioned.merge(width: EMPTY_WIDTH, height: EMPTY_HEIGHT) if sized.empty?

        positioned.merge(
          width: canvas_width + (2 * CANVAS_MARGIN),
          height: top - RANK_SEPARATION + CANVAS_MARGIN,
        )
      end

      def rank_width(rank)
        rank.sum { |node| node[:width] } + (NODE_SEPARATION * (rank.size - 1))
      end

      def place_rank(rank, level, top, canvas_width, positioned)
        left = CANVAS_MARGIN + ((canvas_width - rank_width(rank)) / 2)
        rank.each do |node|
          geometry = node.merge(x: left, y: top, level: level)
          bucket = node[:requirement] ? :requirements : :elements
          positioned[bucket][node[:name]] = geometry
          left += node[:width] + NODE_SEPARATION
        end
      end

      # Sources sit above their targets, as in mmdc: rank = longest path
      # from any root. Edges that close a cycle are ignored.
      def rank_nodes(diagram)
        nodes = diagram.requirements.map do |req|
          { name: req.name, requirement: req }
        end + diagram.elements.map do |elem|
          { name: elem.name, element: elem }
        end
        levels = node_levels(nodes.map { |node| node[:name] },
                             diagram.relationships)
        nodes.group_by { |node| levels[node[:name]] }.sort.map(&:last)
      end

      # Nodes on a cycle never resolve; they share the level below the rest.
      def node_levels(names, relationships)
        edges = relationships.select do |rel|
          names.include?(rel.source) && names.include?(rel.target) &&
            rel.source != rel.target
        end
        levels = {}
        loop do
          ready = names.reject { |name| levels.key?(name) }.select do |name|
            edges.select { |rel| rel.target == name }
              .all? { |rel| levels.key?(rel.source) }
          end
          break if ready.empty?

          ready.each do |name|
            levels[name] = edges.select { |rel| rel.target == name }
              .map { |rel| levels[rel.source] + 1 }.max || 0
          end
        end
        stuck = (levels.values.max || -1) + 1
        names.to_h { |name| [name, levels.fetch(name, stuck)] }
      end

      def size_node(node)
        rows = if node[:requirement]
                 requirement_rows(node[:requirement])
               else
                 element_rows(node[:element])
               end
        node.merge(rows: rows, width: rows_width(rows),
                   height: rows_height(rows))
      end

      def rows_width(rows)
        widest = rows.map do |row|
          scale = row[:weight] == "bold" ? BOLD_WIDTH_FACTOR : 1
          measure_text(row[:text], font_size: LABEL_FONT_SIZE)[:width] * scale
        end.max
        widest + (2 * PADDING_X)
      end

      def rows_height(rows)
        TOP_PADDING + SECTION_GAP + BOTTOM_PADDING + (rows.size * ROW_HEIGHT)
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
