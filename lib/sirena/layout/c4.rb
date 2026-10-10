# frozen_string_literal: true

require_relative "base"
require_relative "c4_stereotype"
require_relative "elk_placement"
require_relative "grid"
require_relative "../diagram/c4"
require_relative "../notation/mermaid/ir_adapters/c4"

module Sirena
  module Layout
    # C4 transformer for converting C4 models to graphs.
    #
    # Converts a typed C4 diagram model into a generic graph structure
    # suitable for layout computation by elkrb. Handles element positioning,
    # boundary grouping, and relationship routing.
    #
    # @example Transform a C4 diagram
    #   transform = C4.new
    #   graph = transform.to_graph(c4_diagram)
    class C4 < Base
      SemanticElement = Struct.new(
        :id, :label, :element_type, :description, :technology, :sprite, :link,
        :tags, :external, :boundary_id, keyword_init: true
      ) do
        def base_type
          element_type&.gsub(/_Ext$/, "") || element_type
        end

        def person?
          base_type == "Person"
        end

        def system?
          %w[System SystemDb SystemQueue].include?(base_type)
        end

        def container?
          %w[Container ContainerDb ContainerQueue].include?(base_type)
        end

        def component?
          base_type == "Component"
        end
      end
      SemanticRelationship = Struct.new(
        :from_id, :to_id, :label, :technology, :rel_type, keyword_init: true
      ) do
        def bidirectional?
          rel_type == "BiRel"
        end
      end
      SemanticBoundary = Struct.new(
        :id, :label, :boundary_type, :type_param, :link, :tags, :parent_id,
        keyword_init: true
      )
      SemanticDiagram = Struct.new(
        :id, :level, :title, :layout_config, :elements, :relationships,
        :boundaries, keyword_init: true
      ) do
        def elements_in_boundary(boundary_id)
          elements.select { |element| element.boundary_id == boundary_id }
        end

        def boundaries_in_boundary(boundary_id)
          boundaries.select { |boundary| boundary.parent_id == boundary_id }
        end
      end
      private_constant :SemanticElement, :SemanticRelationship,
                       :SemanticBoundary, :SemanticDiagram

      # Element dimensions based on type
      PERSON_WIDTH = 140
      PERSON_HEIGHT = 180
      SYSTEM_WIDTH = 160
      SYSTEM_HEIGHT = 120
      CONTAINER_WIDTH = 160
      CONTAINER_HEIGHT = 120
      COMPONENT_WIDTH = 160
      COMPONENT_HEIGHT = 100

      # Spacing
      ELEMENT_SPACING = 60
      BOUNDARY_PADDING = 40
      LEVEL_SPACING = 80
      DIAGRAM_PADDING = 40
      TEXT_PADDING = 10
      LINE_HEIGHT = 16
      ARROW_SIZE = 8
      TITLE_Y = 30
      TITLE_FONT_SIZE = 16
      STEREOTYPE_FONT_SIZE = 12

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
        attribute :font_weight, :string
        attribute :font_style, :string
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
        attribute :stereotype, Label
        attribute :kind, :string
        attribute :external, :boolean, default: false
        attribute :head_center, Point
        attribute :body_center, Point
        attribute :children, Node, collection: true, default: -> { [] }
      end

      class Edge < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :source, :string
        attribute :target, :string
        attribute :sections, Section, collection: true, default: -> { [] }
        attribute :labels, Label, collection: true, default: -> { [] }
        attribute :line_end, Point
        attribute :arrowheads, :string, collection: true, default: -> { [] }
      end

      class Scene < Layout::Scene
        attribute :view_box, :string
        attribute :children, Node, collection: true, default: -> { [] }
        attribute :edges, Edge, collection: true, default: -> { [] }
        attribute :title, Label
      end

      # :grid (the default) or :elk. Grid remains the default until the
      # parity ratchet permits changing it.
      attr_accessor :placement

      # Converts a C4 diagram to a graph structure.
      #
      # @param diagram [Diagram::C4] the C4 diagram to transform
      # @return [Hash] elkrb-compatible graph hash
      def build_graph(diagram)
        diagram = semantic_diagram(ir_graph(diagram))
        {
          id: diagram.id || "c4",
          children: transform_root_nodes(diagram, *root_items(diagram)),
          edges: transform_relationships(diagram),
          layoutOptions: layout_options(diagram),
          metadata: graph_metadata(diagram),
        }
      end

      private

      ELEMENT_ROLES = %w[
        person system system_database system_queue container
        container_database container_queue component element
      ].freeze
      BOUNDARY_ROLES = %w[enterprise_boundary system_boundary boundary].freeze
      private_constant :ELEMENT_ROLES, :BOUNDARY_ROLES

      def root_items(diagram)
        elements = diagram.elements.select { |item| item.boundary_id.nil? }
        boundaries = diagram.boundaries.select { |item| item.parent_id.nil? }
        [elements, boundaries]
      end

      def graph_metadata(diagram)
        {
          level: diagram.level, title: diagram.title,
          element_count: diagram.elements.length,
          relationship_count: diagram.relationships.length
        }
      end

      def ir_graph(diagram)
        return diagram if diagram.is_a?(IR::Graph)

        Notation::Mermaid::IRAdapters::C4.call(diagram)
      end

      def semantic_diagram(graph)
        children, nodes_by_id = semantic_context(graph)
        settings = diagram_settings(graph, children)
        collections = semantic_collections(graph, children, nodes_by_id)
        SemanticDiagram.new(
          **diagram_metadata(graph, settings), **collections,
        )
      end

      def semantic_context(graph)
        children = graph.nodes.group_by(&:parent_id)
        nodes_by_id = graph.nodes.to_h { |node| [node.id, node] }
        [children, nodes_by_id]
      end

      def diagram_settings(graph, children)
        settings = graph.nodes.find { |node| node.role == "diagram_settings" }
        semantic_fields(children[settings&.id])
      end

      def diagram_metadata(graph, settings)
        {
          id: settings["diagram_identifier"], level: settings["level"],
          title: graph.label, layout_config: settings["layout_intent"]
        }
      end

      def semantic_collections(graph, children, nodes_by_id)
        {
          boundaries: semantic_boundaries(graph, children, nodes_by_id),
          elements: semantic_elements(graph, children, nodes_by_id),
          relationships: semantic_relationships(graph, children, nodes_by_id),
        }
      end

      def semantic_boundaries(graph, children, nodes_by_id)
        graph.nodes.select { |node| BOUNDARY_ROLES.include?(node.role) }
          .map { |node| semantic_boundary(node, children, nodes_by_id) }
      end

      def semantic_boundary(node, children, nodes_by_id)
        fields = semantic_fields(children[node.id])
        SemanticBoundary.new(
          id: source_identifier(node, children), label: node.label,
          boundary_type: fields["boundary_type"],
          type_param: fields["type_label"], link: fields["link"],
          tags: fields["tags"],
          parent_id: source_parent(fields, node, nodes_by_id, children)
        )
      end

      def semantic_elements(graph, children, nodes_by_id)
        graph.nodes.select { |node| ELEMENT_ROLES.include?(node.role) }
          .map { |node| semantic_element(node, children, nodes_by_id) }
      end

      def semantic_element(node, children, nodes_by_id)
        fields = semantic_fields(children[node.id])
        SemanticElement.new(
          id: source_identifier(node, children), label: node.label,
          element_type: fields["element_type"],
          description: fields["description"],
          technology: fields["technology"], sprite: fields["sprite"],
          link: fields["link"], tags: fields["tags"],
          external: fields["external"] == "true",
          boundary_id: source_boundary(fields, node, nodes_by_id, children)
        )
      end

      def semantic_relationships(graph, children, nodes_by_id)
        graph.edges.map do |edge|
          semantic_relationship(edge, children, nodes_by_id)
        end
      end

      def semantic_relationship(edge, children, nodes_by_id)
        details = semantic_fields(children[edge.parent_id])
        SemanticRelationship.new(
          from_id: source_identifier(nodes_by_id[edge.source_id], children),
          to_id: source_identifier(nodes_by_id[edge.target_id], children),
          label: edge.label, technology: details["technology"],
          rel_type: details["relationship_type"]
        )
      end

      def semantic_fields(nodes)
        Array(nodes).to_h { |node| [node.role, node.label] }
      end

      def source_identifier(node, children)
        return unless node

        semantic_fields(children[node.id]).fetch("original_identifier", node.id)
      end

      def parent_source_identifier(node, nodes_by_id, children)
        source_identifier(nodes_by_id[node.parent_id], children)
      end

      def source_parent(fields, node, nodes_by_id, children)
        fields.fetch("parent_identifier") do
          parent_source_identifier(node, nodes_by_id, children)
        end
      end

      def source_boundary(fields, node, nodes_by_id, children)
        fields.fetch("boundary_identifier") do
          parent_source_identifier(node, nodes_by_id, children)
        end
      end

      def scene(diagram)
        graph = build_graph(diagram)
        placer.apply(graph)
        children = graph[:children].map { |node| typed_node(node) }
        title = title_label(graph.dig(:metadata, :title))
        width, height = scene_dimensions(children, title)
        Scene.new(
          width: width, height: height, view_box: "0 0 #{width} #{height}",
          children: children, title: title,
          edges: typed_edges(graph[:edges], children)
        )
      end

      def title_label(title)
        return if title.nil? || title.empty?

        size = measure_text(title, font_size: TITLE_FONT_SIZE)
        Label.new(text: title, width: size[:width], height: size[:height],
                  x: DIAGRAM_PADDING, y: TITLE_Y,
                  font_size: TITLE_FONT_SIZE, font_weight: "bold")
      end

      def placer
        placement == :elk ? ElkPlacement : Grid
      end

      def typed_node(node)
        kind = node_kind(node)
        children = (node[:children] || []).map { |child| typed_node(child) }
        Node.new(**node_attributes(node, kind), children: children)
      end

      def node_attributes(node, kind)
        node.slice(:id, :x, :y, :width, :height).merge(
          kind: kind, external: node.dig(:metadata, :external) || false,
          labels: positioned_node_labels(node, kind),
          stereotype: positioned_stereotype(node, kind),
          head_center: person_head(node, kind),
          body_center: person_body(node, kind)
        )
      end

      def node_kind(node)
        metadata = node[:metadata] || {}
        return "boundary" if metadata[:boundary_type]
        return "person" if metadata[:person]
        return "container" if metadata[:container]
        return "component" if metadata[:component]

        "system"
      end

      def positioned_node_labels(node, kind)
        labels = node[:labels] || []
        return [] unless node[:x] && node[:y]
        return boundary_labels(labels, node) if kind == "boundary"

        start_y = label_top(node, kind) + LINE_HEIGHT
        labels.map.with_index do |label, index|
          positioned_node_label(label, node, start_y, index)
        end
      end

      def label_top(node, kind)
        node[:y] + { "person" => 108, "component" => 15 }.fetch(kind, 20)
      end

      def positioned_stereotype(node, kind)
        text = node[:stereotype]
        return unless text && node[:x] && node[:y] && kind != "boundary"

        Label.new(
          text: text, **stereotype_size(text),
          x: node[:x] + (node[:width] / 2), y: label_top(node, kind),
          font_size: STEREOTYPE_FONT_SIZE, font_style: "italic",
          font_weight: "normal"
        )
      end

      def stereotype_size(text)
        size = measure_text(text, font_size: STEREOTYPE_FONT_SIZE)
        { width: size[:width], height: size[:height] }
      end

      def boundary_labels(labels, node)
        labels.first ? [boundary_label(labels.first, node)] : []
      end

      def positioned_node_label(label, node, start_y, index)
        Label.new(
          **label_measurements(label), x: node[:x] + (node[:width] / 2),
                                       y: start_y + (index * LINE_HEIGHT),
                                       font_size: [14, 11, 10].fetch(index, 10),
                                       font_weight: label_weight(index),
                                       font_style: label_style(index)
        )
      end

      def label_weight(index)
        index.zero? ? "bold" : "normal"
      end

      def label_style(index)
        index == 2 ? "italic" : "normal"
      end

      def label_measurements(label)
        { text: label[:text], width: label[:width], height: label[:height] }
      end

      def boundary_label(label, node)
        Label.new(
          **label_measurements(label),
          x: node[:x] + TEXT_PADDING, y: node[:y] + 20,
          font_size: 16, font_weight: "bold"
        )
      end

      def person_head(node, kind)
        return unless kind == "person"

        Point.new(x: node[:x] + (node[:width] / 2), y: node[:y] + 30)
      end

      def person_body(node, kind)
        head = person_head(node, kind)
        Point.new(x: head.x, y: head.y + 35) if head
      end

      def typed_edges(edges, nodes)
        index = index_nodes(nodes)
        edges.filter_map do |edge|
          source = index[edge[:sources]&.first]
          target = index[edge[:targets]&.first]
          next unless source && target

          typed_edge(edge, source, target)
        end
      end

      def index_nodes(nodes, result = {})
        nodes.each do |node|
          result[node.id] = node unless node.kind == "boundary"
          index_nodes(node.children, result)
        end
        result
      end

      def typed_edge(edge, source, target)
        start_point = node_center(source)
        end_point = node_center(target)
        section = Section.new(start_point: start_point, end_point: end_point)
        Edge.new(
          id: edge[:id], source: source.id, target: target.id,
          sections: [section], line_end: line_end(end_point),
          arrowheads: edge_arrowheads(edge, start_point, end_point),
          labels: relationship_labels(edge[:labels], start_point, end_point)
        )
      end

      def node_center(node)
        Point.new(x: node.x + (node.width / 2),
                  y: node.y + (node.height / 2))
      end

      def line_end(end_point)
        Point.new(x: end_point.x - ARROW_SIZE, y: end_point.y)
      end

      def edge_arrowheads(edge, start_point, end_point)
        heads = [arrowhead_points(start_point, end_point)]
        if edge.dig(:metadata, :bidirectional)
          heads << arrowhead_points(end_point, start_point)
        end
        heads
      end

      def arrowhead_points(from, to)
        wing_x = to.x + arrowhead_offset(from, to)
        half_height = ARROW_SIZE / 2
        [[to.x, to.y], [wing_x, to.y - half_height],
         [wing_x, to.y + half_height]].map { |point| point.join(",") }.join(" ")
      end

      def arrowhead_offset(from, to)
        to.x > from.x ? -ARROW_SIZE : ARROW_SIZE
      end

      def relationship_labels(labels, from, to)
        (labels || []).map.with_index do |label, index|
          relationship_label(label, from, to, index)
        end
      end

      def relationship_label(label, from, to, index)
        Label.new(
          **label_measurements(label), x: (from.x + to.x) / 2,
                                       y: relationship_label_y(from, to, index),
                                       font_size: index.zero? ? 12 : 10
        )
      end

      def relationship_label_y(from, to, index)
        ((from.y + to.y) / 2) - 15 + (index * 14)
      end

      def scene_dimensions(nodes, title = nil)
        flat_nodes = flatten_nodes(nodes)
        width = [extent(flat_nodes, :x, :width, 760), title_right(title)].max
        height = extent(flat_nodes, :y, :height, 560)
        [width + DIAGRAM_PADDING, height + DIAGRAM_PADDING]
      end

      def extent(nodes, origin, size, fallback)
        ends = nodes.map { |n| n.public_send(origin) + n.public_send(size) }
        ends.max || fallback
      end

      def title_right(title)
        title ? title.x + title.width : 0
      end

      def flatten_nodes(nodes)
        nodes.flat_map { |node| [node, *flatten_nodes(node.children)] }
      end

      def transform_root_nodes(diagram, elements, boundaries)
        # Add root-level boundaries (which contain their own elements)
        nodes = boundaries.map do |boundary|
          transform_boundary(diagram, boundary)
        end

        # Add root-level elements (not in any boundary)
        elements.each do |element|
          nodes << transform_element(element)
        end

        nodes
      end

      def transform_boundary(diagram, boundary)
        children = boundary_children(diagram, boundary)
        dims = calculate_boundary_dimensions(children)
        {
          id: boundary.id, width: dims[:width], height: dims[:height],
          labels: [graph_boundary_label(boundary)], children: children,
          layoutOptions: boundary_layout_options,
          metadata: boundary_metadata(boundary)
        }
      end

      def boundary_children(diagram, boundary)
        children = diagram.boundaries_in_boundary(boundary.id).map do |child|
          transform_boundary(diagram, child)
        end
        diagram.elements_in_boundary(boundary.id).each do |element|
          children << transform_element(element)
        end
        children
      end

      def graph_boundary_label(boundary)
        dims = measure_text(boundary.label, font_size: large_font_size)
        { text: boundary.label, width: dims[:width], height: dims[:height] }
      end

      def boundary_metadata(boundary)
        {
          boundary_type: boundary.boundary_type,
          type_param: boundary.type_param,
          link: boundary.link, tags: boundary.tags
        }
      end

      def transform_element(element)
        dims = element_dimensions(element)
        {
          id: element.id, width: dims[:width], height: dims[:height],
          labels: element_labels(element),
          stereotype: C4Stereotype.text(element.element_type),
          metadata: element_metadata(element)
        }
      end

      def element_labels(element)
        [
          measured_label(element.label, large_font_size),
          optional_label(element.description),
          optional_technology_label(element.technology),
        ].compact
      end

      def measured_label(text, size, rendered_text = text)
        dims = measure_text(text, font_size: size)
        { text: rendered_text, width: dims[:width], height: dims[:height] }
      end

      def optional_label(text)
        measured_label(text, small_font_size) if text && !text.empty?
      end

      def optional_technology_label(text)
        return unless text && !text.empty?

        measured_label(text, small_font_size, "[#{text}]")
      end

      def element_metadata(element)
        {
          element_type: element.element_type, base_type: element.base_type,
          external: element.external, sprite: element.sprite,
          link: element.link, tags: element.tags,
          person: element.person?, system: element.system?,
          container: element.container?, component: element.component?
        }
      end

      def transform_relationships(diagram)
        Array(diagram.relationships).map.with_index do |relationship, index|
          transform_relationship(relationship, index)
        end
      end

      def transform_relationship(relationship, index)
        {
          id: "rel_#{index}", sources: [relationship.from_id],
          targets: [relationship.to_id],
          labels: graph_relationship_labels(relationship),
          metadata: {
            rel_type: relationship.rel_type,
            bidirectional: relationship.bidirectional?,
          }
        }
      end

      def graph_relationship_labels(relationship)
        [
          optional_relationship_label(relationship.label),
          optional_relationship_technology(relationship.technology),
        ].compact
      end

      def optional_relationship_label(text)
        measured_label(text, normal_font_size) if text && !text.empty?
      end

      def optional_relationship_technology(text)
        return unless text && !text.empty?

        rendered = "[#{text}]"
        measured_label(rendered, small_font_size)
      end

      def element_dimensions(element)
        return { width: PERSON_WIDTH, height: PERSON_HEIGHT } if element.person?
        if element.container?
          return { width: CONTAINER_WIDTH, height: CONTAINER_HEIGHT }
        end
        if element.component?
          return { width: COMPONENT_WIDTH, height: COMPONENT_HEIGHT }
        end

        { width: SYSTEM_WIDTH, height: SYSTEM_HEIGHT }
      end

      def calculate_boundary_dimensions(children)
        return { width: 300, height: 200 } if children.empty?

        columns, rows = boundary_grid(children.length)
        width = boundary_extent(columns, child_extent(children, :width, 160))
        child_height = child_extent(children, :height, 120)
        height = boundary_extent(rows, child_height) + 30
        { width: [width, 300].max, height: [height, 200].max }
      end

      def boundary_grid(count)
        columns = Math.sqrt(count).ceil
        [columns, (count.to_f / columns).ceil]
      end

      def child_extent(children, dimension, fallback)
        children.map { |child| child[dimension] || fallback }.max
      end

      def boundary_extent(item_count, item_extent)
        (item_count * item_extent) + ((item_count + 1) * ELEMENT_SPACING) +
          (2 * BOUNDARY_PADDING)
      end

      def layout_options(diagram)
        build_elk_options(
          algorithm: ALGORITHM_LAYERED,
          direction: layout_direction(diagram.level),
          ElkOptions::NODE_NODE_SPACING => ELEMENT_SPACING,
          ElkOptions::LAYER_SPACING => LEVEL_SPACING,
          ElkOptions::EDGE_NODE_SPACING => 25,
          ElkOptions::EDGE_EDGE_SPACING => 20,
          ElkOptions::HIERARCHY_HANDLING => "INCLUDE_CHILDREN",
          ElkOptions::NODE_PLACEMENT => "NETWORK_SIMPLEX",
        )
      end

      def layout_direction(level)
        %w[Component Code].include?(level) ? DIRECTION_RIGHT : DIRECTION_DOWN
      end

      def boundary_layout_options
        # Boundaries use box packing for internal layout
        padding = "[top=#{BOUNDARY_PADDING},left=#{BOUNDARY_PADDING}," \
                  "bottom=#{BOUNDARY_PADDING},right=#{BOUNDARY_PADDING}]"
        {
          "elk.algorithm" => "box",
          "elk.box.packingMode" => "GROUP_MIXED",
          "elk.padding" => padding,
          "elk.spacing.nodeNode" => ELEMENT_SPACING.to_s,
        }
      end

      def normal_font_size
        theme.typography&.font_size_normal ||
          Theme::Registry.get(:default).typography.font_size_normal
      end

      def large_font_size
        theme.typography&.font_size_large || (normal_font_size + 2)
      end

      def small_font_size
        theme.typography&.font_size_small || (normal_font_size - 2)
      end
    end
  end
end
