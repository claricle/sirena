# frozen_string_literal: true

require_relative "base"
require_relative "c4_boundary_metrics"
require_relative "c4_intersection"
require_relative "c4_placement"
require_relative "c4_shape_metrics"
require_relative "c4_stereotype"
require_relative "c4_text"
require_relative "elk_placement"
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

      # Spacing the ELK path still uses; the default placement is
      # C4Placement, which takes its numbers from mermaid.
      ELEMENT_SPACING = 60
      BOUNDARY_PADDING = 40
      LEVEL_SPACING = 80
      DIAGRAM_PADDING = 40
      ARROW_SIZE = 8
      TITLE_Y = 30
      TITLE_FONT_SIZE = 16
      STEREOTYPE_FONT_SIZE = 12
      RELATIONSHIP_FONT_SIZE = 12

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
        attribute :baseline, :string
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

      # nil (the default, mermaid's own placement) or :elk.
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
          layout_config: diagram.layout_config,
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
        canvas = canvas_for(graph, children)
        title = title_label(graph.dig(:metadata, :title), canvas)
        Scene.new(
          **canvas.slice(:width, :height, :view_box),
          children: children, title: title,
          edges: typed_edges(graph[:edges], children)
        )
      end

      def canvas_for(graph, children)
        canvas = graph.dig(:metadata, :canvas)
        return legacy_canvas(children) unless canvas

        title = graph.dig(:metadata, :title).to_s.empty? ? 0 : 60
        width = canvas[:width]
        height = canvas[:height] + title
        view_box = "0 #{-(C4Placement::MARGIN_Y + title)} #{width} #{height}"
        canvas.merge(height: height, view_box: view_box)
      end

      def legacy_canvas(children)
        width, height = scene_dimensions(children)
        { width: width, height: height, view_box: "0 0 #{width} #{height}",
          title_x: DIAGRAM_PADDING, title_y: TITLE_Y }
      end

      def title_label(title, canvas)
        return if title.nil? || title.empty?

        size = measure_text(title, font_size: TITLE_FONT_SIZE)
        Label.new(text: title, width: size[:width], height: size[:height],
                  x: canvas[:title_x], y: canvas[:title_y],
                  font_size: TITLE_FONT_SIZE, font_weight: "bold")
      end

      def placer
        placement == :elk ? ElkPlacement : C4Placement
      end

      def typed_node(node)
        kind = node_kind(node)
        children = (node[:children] || []).map { |child| typed_node(child) }
        Node.new(**node_attributes(node, kind), children: children)
      end

      def node_attributes(node, kind)
        node.slice(:id, :x, :y, :width, :height).merge(
          kind: kind, external: node.dig(:metadata, :external) || false,
          labels: positioned_node_labels(node),
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

      def positioned_node_labels(node)
        return [] unless node[:x] && node[:y]

        (node[:labels] || []).map { |label| node_label(label, node) }
      end

      def node_label(label, node)
        Label.new(
          **label_measurements(label), x: node[:x] + (node[:width] / 2.0),
                                       y: node[:y] + label[:offset], baseline: "middle",
                                       font_size: label[:font_size], font_weight: label[:font_weight],
                                       font_style: label[:font_style]
        )
      end

      def positioned_stereotype(node, kind)
        text = node[:stereotype]
        return unless text && node[:x] && node[:y] && kind != "boundary"

        Label.new(
          text: text, **stereotype_size(text),
          x: node[:x] + (node[:width] / 2.0),
          y: node[:y] + node.dig(:metadata, :stereotype_offset),
          font_size: STEREOTYPE_FONT_SIZE, font_style: "italic",
          font_weight: "normal"
        )
      end

      def stereotype_size(text)
        size = measure_text(text, font_size: STEREOTYPE_FONT_SIZE)
        { width: size[:width], height: size[:height] }
      end

      def label_measurements(label)
        { text: label[:text], width: label[:width], height: label[:height] }
      end

      def person_head(node, kind)
        return unless kind == "person" && node[:x] && node[:y]

        top = node[:y] + node.dig(:metadata, :image_offset)
        Point.new(x: node[:x] + (node[:width] / 2.0), y: top + 14)
      end

      def person_body(node, kind)
        head = person_head(node, kind)
        Point.new(x: head.x, y: head.y + 22) if head
      end

      def typed_edges(edges, nodes)
        index = index_nodes(nodes)
        edges.each_with_index.filter_map do |edge, position|
          source = index[edge[:sources]&.first]
          target = index[edge[:targets]&.first]
          next unless source && target

          typed_edge(edge, source, target, position)
        end
      end

      def index_nodes(nodes, result = {})
        nodes.each do |node|
          result[node.id] = node unless node.kind == "boundary"
          index_nodes(node.children, result)
        end
        result
      end

      # Mermaid draws the first relationship as a straight line and every
      # later one as a quadratic curve bent by a control point.
      def typed_edge(edge, source, target, position)
        start_point, end_point = edge_ends(source, target)
        section = Section.new(
          start_point: start_point, end_point: end_point,
          bend_points: bend_points(start_point, end_point, position)
        )
        Edge.new(
          id: edge[:id], source: source.id, target: target.id,
          sections: [section], line_end: end_point,
          arrowheads: edge_arrowheads(edge, section),
          labels: relationship_labels(edge[:labels], start_point, end_point)
        )
      end

      def edge_ends(source, target)
        C4Intersection.points(source, target).map do |x_pos, y_pos|
          Point.new(x: x_pos, y: y_pos)
        end
      end

      def bend_points(start_point, end_point, position)
        return [] if position.zero?

        run = end_point.x - start_point.x
        [Point.new(x: start_point.x + (run / 4.0),
                   y: start_point.y + ((end_point.y - start_point.y) / 2.0))]
      end

      def edge_arrowheads(edge, section)
        start_point = section.start_point
        end_point = section.end_point
        control = section.bend_points.first
        heads = [arrowhead_points(control || start_point, end_point)]
        if edge.dig(:metadata, :bidirectional)
          heads << arrowhead_points(control || end_point, start_point)
        end
        heads.compact
      end

      def arrowhead_points(from, tip)
        run = tip.x - from.x
        rise = tip.y - from.y
        length = Math.hypot(run, rise)
        return if length.zero?

        unit = [run / length, rise / length]
        arrowhead_polygon(tip, unit).map { |point| point.join(",") }.join(" ")
      end

      def arrowhead_polygon(tip, unit)
        base_x = tip.x - (unit[0] * ARROW_SIZE)
        base_y = tip.y - (unit[1] * ARROW_SIZE)
        wing_x = -unit[1] * ARROW_SIZE / 2
        wing_y = unit[0] * ARROW_SIZE / 2
        [[tip.x, tip.y], [base_x + wing_x, base_y + wing_y],
         [base_x - wing_x, base_y - wing_y]]
      end

      def relationship_labels(labels, from, to)
        (labels || []).map.with_index do |label, index|
          relationship_label(label, from, to, index)
        end
      end

      def relationship_label(label, from, to, index)
        Label.new(
          **label_measurements(label),
          x: (from.x + to.x) / 2.0, y: relationship_label_y(from, to, index),
          font_size: RELATIONSHIP_FONT_SIZE, baseline: "middle",
          font_style: index.zero? ? "normal" : "italic"
        )
      end

      def relationship_label_y(from, to, index)
        middle = (from.y + to.y) / 2.0
        middle + (index * (RELATIONSHIP_FONT_SIZE + 5))
      end

      def scene_dimensions(nodes)
        flat_nodes = flatten_nodes(nodes)
        width = extent(flat_nodes, :x, :width, 760)
        height = extent(flat_nodes, :y, :height, 560)
        [width + DIAGRAM_PADDING, height + DIAGRAM_PADDING]
      end

      def extent(nodes, origin, size, fallback)
        ends = nodes.map { |n| n.public_send(origin) + n.public_send(size) }
        ends.max || fallback
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
        heading = boundary_heading(boundary)
        {
          id: boundary.id, width: dims[:width], height: dims[:height],
          labels: boundary_labels(boundary, heading), children: children,
          layoutOptions: boundary_layout_options,
          metadata: boundary_metadata(boundary, heading)
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

      BOUNDARY_TYPE_TEXTS = {
        "Enterprise_Boundary" => "ENTERPRISE",
        "System_Boundary" => "SYSTEM",
        "Container_Boundary" => "CONTAINER",
      }.freeze
      private_constant :BOUNDARY_TYPE_TEXTS

      def boundary_heading(boundary)
        C4BoundaryMetrics.new(label: boundary.label,
                              type: boundary_type_text(boundary))
      end

      def boundary_type_text(boundary)
        BOUNDARY_TYPE_TEXTS.fetch(boundary.boundary_type) do
          boundary.type_param.to_s.empty? ? "system" : boundary.type_param
        end
      end

      def boundary_labels(boundary, heading)
        label_lines(boundary.label, heading.label_offset, 16, "bold") +
          label_lines(bracket(boundary_type_text(boundary)),
                      heading.type_offset, 14)
      end

      def bracket(text)
        text.to_s.empty? ? "" : "[#{text}]"
      end

      def boundary_metadata(boundary, heading)
        {
          boundary_type: boundary.boundary_type,
          type_param: boundary.type_param,
          link: boundary.link, tags: boundary.tags,
          header: heading.height
        }
      end

      def transform_element(element)
        metrics = shape_metrics(element)
        {
          id: element.id, width: metrics.width, height: metrics.height,
          labels: element_labels(element, metrics),
          stereotype: C4Stereotype.text(element.element_type),
          metadata: element_metadata(element, metrics)
        }
      end

      def shape_metrics(element)
        C4ShapeMetrics.new(
          label: element.label, technology: element.technology,
          description: element.description, person: element.person?
        )
      end

      # One entry per drawn line: mermaid centres each line on its offset
      # from the top of the box, spread by the font size.
      def element_labels(element, metrics)
        label_lines(element.label, metrics.label_offset, 16, "bold") +
          label_lines(bracket(element.technology),
                      metrics.technology_offset, 14, "normal", "italic") +
          label_lines(element.description, metrics.description_offset, 14)
      end

      def label_lines(text, offset, size, weight = "normal", style = "normal")
        return [] if text.to_s.empty? || offset.nil?

        lines = C4Text.lines(text)
        lines.each_with_index.map do |line, index|
          spread = (index * size) - (size * (lines.length - 1) / 2.0)
          { text: line, width: C4Text.width(line, size),
            height: C4Text.height(line, size), offset: offset + spread,
            font_size: size, font_weight: weight, font_style: style }
        end
      end

      def element_metadata(element, metrics)
        {
          element_type: element.element_type, base_type: element.base_type,
          external: element.external, sprite: element.sprite,
          link: element.link, tags: element.tags,
          person: element.person?, system: element.system?,
          container: element.container?, component: element.component?,
          stereotype_offset: metrics.stereotype_offset,
          image_offset: metrics.image_offset
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
        [relationship.label, bracket(relationship.technology)]
          .reject(&:empty?).map { |text| relationship_text(text) }
      end

      def relationship_text(text)
        size = RELATIONSHIP_FONT_SIZE
        { text: text, width: C4Text.width(text, size),
          height: C4Text.height(text, size) }
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
    end
  end
end
