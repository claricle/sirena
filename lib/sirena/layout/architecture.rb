# frozen_string_literal: true

require_relative "base"
require_relative "elk_placement"
require_relative "../diagram/architecture"
require_relative "../notation/mermaid/ir_adapters/architecture"
require_relative "../renderer/architecture_edge_router"

module Sirena
  module Layout
    # Transforms architecture diagram models into positioned layouts.
    class Architecture < Base
      # Default dimensions
      # Service icon boxes are 80x80 in mmdc; the label sits below the box.
      DEFAULT_SERVICE_WIDTH = 80
      DEFAULT_SERVICE_HEIGHT = 80
      SERVICE_LABEL_OFFSET = 16
      # Group padding measured from mmdc: 42.5 on three sides, 17 more below
      # for the service labels.
      DEFAULT_GROUP_PADDING = 42.5
      GROUP_LABEL_ALLOWANCE = 17
      EMPTY_GROUP_SIZE = 112
      EMPTY_GROUP_GAP = 98
      # Centre-to-centre spacing of the grid that edge sides imply.
      GRID_PITCH_X = 201
      GRID_PITCH_Y = 201
      GRID_ORIGIN = 60
      COMPONENT_GAP = 100
      BLOCK_GAP = 100
      DEFAULT_SPACING = 40
      DEFAULT_ICON_SIZE = 24
      DEFAULT_JUNCTION_SIZE = 12

      VALID_SIDES = %w[L R T B].freeze
      LABEL_FONT_ROLES = {
        group: [:font_size_title, 14],
        service: [:font_size_normal, 12],
        edge: [:font_size_small, 10],
      }.freeze

      SemanticGroup = Struct.new(
        :id, :label, :icon, :parent_id, keyword_init: true
      )
      SemanticService = Struct.new(
        :id, :label, :icon, :group_id, keyword_init: true
      )
      SemanticJunction = Struct.new(:id, :group_id, keyword_init: true)
      SemanticEdge = Struct.new(
        :from_id, :to_id, :from_position, :to_position, :label,
        keyword_init: true
      )
      SemanticDiagram = Struct.new(
        :id, :title, :direction, :theme, :acc_title, :acc_descr,
        :groups, :services, :junctions, :edges, keyword_init: true
      )
      private_constant :SemanticGroup, :SemanticService, :SemanticJunction,
                       :SemanticEdge, :SemanticDiagram

      class Point < Lutaml::Model::Serializable
        attribute :x, :float
        attribute :y, :float
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

      class Node < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :x, :float
        attribute :y, :float
        attribute :width, :float
        attribute :height, :float
        attribute :labels, Label, collection: true, default: -> { [] }
        attribute :kind, :string
        attribute :icon, :string
        attribute :icon_x, :float
        attribute :icon_y, :float
        attribute :center_x, :float
        attribute :center_y, :float
        attribute :radius, :float
        attribute :group_id, :string
        attribute :parent_id, :string
      end

      class Section < Lutaml::Model::Serializable
        attribute :start_point, Point
        attribute :end_point, Point
        attribute :bend_points, Point, collection: true, default: -> { [] }
      end

      class Edge < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :source, :string
        attribute :target, :string
        attribute :sections, Section, collection: true, default: -> { [] }
        attribute :labels, Label, collection: true, default: -> { [] }
      end

      class Scene < Layout::Scene
        attribute :view_box, :string
        attribute :children, Node, collection: true, default: -> { [] }
        attribute :edges, Edge, collection: true, default: -> { [] }
      end

      ElkPositions = Data.define(:services, :junctions, :groups)
      private_constant :ElkPositions

      # :grid (the byte-compatible default) or :elk. The explicit switch
      # lets the parity ratchet measure real elkrb output before it becomes
      # the default.
      attr_accessor :placement

      # Converts an architecture diagram to a positioned layout structure
      #
      # @param diagram [Diagram::Architecture] the diagram to transform
      # @return [Hash] positioned layout hash
      def build_graph(diagram)
        diagram = semantic_diagram(ir_graph(diagram))
        # Build hierarchy
        hierarchy = build_hierarchy(diagram)

        # Calculate positions
        service_positions, junction_positions, group_bounds =
          position_nodes(diagram, hierarchy)
        edge_positions = position_edges(
          diagram,
          service_positions.merge(junction_positions),
        )

        {
          services: service_positions,
          junctions: junction_positions,
          groups: group_bounds,
          edges: edge_positions,
          width: calculate_total_width(
            service_positions,
            junction_positions,
            group_bounds,
          ),
          height: calculate_total_height(
            service_positions,
            junction_positions,
            group_bounds,
          ),
        }
      end

      private

      ENTITY_ROLES = %w[group service junction].freeze
      private_constant :ENTITY_ROLES

      def ir_graph(diagram)
        return diagram if diagram.is_a?(IR::Graph)

        Notation::Mermaid::IRAdapters::Architecture.call(diagram)
      end

      def semantic_diagram(graph)
        children, nodes_by_id = semantic_context(graph)
        SemanticDiagram.new(
          **semantic_attributes(graph, children, nodes_by_id),
        )
      end

      def semantic_context(graph)
        children = graph.nodes.group_by(&:parent_id)
        nodes_by_id = graph.nodes.to_h { |node| [node.id, node] }
        [children, nodes_by_id]
      end

      def semantic_attributes(graph, children, nodes_by_id)
        semantic_metadata(graph, children).merge(
          semantic_collections(graph, children, nodes_by_id),
        )
      end

      def semantic_metadata(graph, children)
        settings = graph.nodes.find { |node| node.role == "diagram_settings" }
        fields = semantic_fields(children[settings&.id])
        {
          id: fields["diagram_identifier"], title: graph.label,
          direction: fields["layout_direction"], theme: fields["theme"],
          acc_title: graph.accessibility_title,
          acc_descr: graph.accessibility_description
        }
      end

      def semantic_collections(graph, children, nodes_by_id)
        entities = graph.nodes.select do |node|
          ENTITY_ROLES.include?(node.role)
        end
        {
          groups: semantic_groups(entities, children, nodes_by_id),
          services: semantic_services(entities, children, nodes_by_id),
          junctions: semantic_junctions(entities, children, nodes_by_id),
          edges: semantic_edges(graph.edges, children, nodes_by_id),
        }
      end

      def semantic_groups(entities, children, nodes_by_id)
        entities.select { |node| node.role == "group" }.map do |node|
          fields = semantic_fields(children[node.id])
          SemanticGroup.new(
            id: source_identifier(node, children), label: node.label,
            icon: fields["icon"],
            parent_id: source_container(fields, node, nodes_by_id, children,
                                        "parent_identifier")
          )
        end
      end

      def semantic_services(entities, children, nodes_by_id)
        entities.select { |node| node.role == "service" }.map do |node|
          fields = semantic_fields(children[node.id])
          SemanticService.new(
            id: source_identifier(node, children), label: node.label,
            icon: fields["icon"],
            group_id: source_container(fields, node, nodes_by_id, children,
                                       "group_identifier")
          )
        end
      end

      def semantic_junctions(entities, children, nodes_by_id)
        entities.select { |node| node.role == "junction" }.map do |node|
          fields = semantic_fields(children[node.id])
          SemanticJunction.new(
            id: source_identifier(node, children),
            group_id: source_container(fields, node, nodes_by_id, children,
                                       "group_identifier"),
          )
        end
      end

      def semantic_edges(edges, children, nodes_by_id)
        edges.map do |edge|
          fields = semantic_fields(children[edge.parent_id])
          SemanticEdge.new(
            from_id: source_identifier(nodes_by_id[edge.source_id], children),
            to_id: source_identifier(nodes_by_id[edge.target_id], children),
            from_position: fields["source_position"],
            to_position: fields["target_position"], label: edge.label
          )
        end
      end

      def semantic_fields(nodes)
        Array(nodes).to_h { |node| [node.role, node.label] }
      end

      def source_identifier(node, children)
        return unless node

        semantic_fields(children[node.id]).fetch("original_identifier", node.id)
      end

      def source_container(fields, node, nodes_by_id, children, field)
        fields.fetch(field) do
          source_identifier(nodes_by_id[node.parent_id], children)
        end
      end

      def scene(diagram)
        return elk_scene(diagram) if placement == :elk

        graph = build_graph(diagram)
        routed = route_edges(graph)
        positioned_scene(graph, routed)
      end

      def positioned_scene(graph, routed)
        width, height = scene_dimensions(graph, routed)
        Scene.new(
          width: width, height: height, view_box: "0 0 #{width} #{height}",
          children: typed_nodes(graph), edges: typed_edges(routed)
        )
      end

      def elk_scene(source)
        diagram = semantic_diagram(ir_graph(source))
        elk_graph = build_elk_graph(diagram)
        ElkPlacement.apply(elk_graph)
        graph = positioned_elk_graph(diagram, elk_graph)
        routed = elk_routed_edges(diagram, elk_graph, graph)
        positioned_scene(graph, routed)
      end

      def elk_routed_edges(diagram, elk_graph, graph)
        return routed_elk_edges(elk_graph) if diagram.groups.empty?

        route_edges(graph)
      end

      def build_elk_graph(diagram)
        {
          id: diagram.id || "architecture",
          children: elk_children(diagram),
          edges: elk_root_edges(diagram),
          layoutOptions: elk_layout_options,
        }
      end

      def elk_root_edges(diagram)
        return [] unless diagram.groups.empty?

        ids = diagram.services.map(&:id) + diagram.junctions.map(&:id)
        elk_edges(diagram.edges, ids.to_h { |id| [id, true] })
      end

      def elk_layout_options
        {
          ElkOptions::ALGORITHM => ALGORITHM_LAYERED,
          ElkOptions::DIRECTION => DIRECTION_DOWN,
          ElkOptions::NODE_NODE_SPACING => DEFAULT_SPACING,
          ElkOptions::LAYER_SPACING => DEFAULT_SPACING,
        }
      end

      def elk_children(diagram, parent_id = nil)
        groups = elk_children_for(diagram.groups, :parent_id, parent_id)
        services = elk_children_for(diagram.services, :group_id, parent_id)
        junctions = elk_children_for(diagram.junctions, :group_id, parent_id)
        groups.map { |group| elk_group_node(group, diagram) } +
          elk_service_nodes(services) + elk_junction_nodes(junctions)
      end

      def elk_children_for(records, association, parent_id)
        records.select do |record|
          record.public_send(association) == parent_id
        end
      end

      def elk_group_node(group, diagram)
        {
          id: group.id, width: EMPTY_GROUP_SIZE, height: EMPTY_GROUP_SIZE,
          children: elk_children(diagram, group.id), edges: [],
          metadata: { kind: :group, model: group }
        }
      end

      def elk_service_nodes(services)
        services.map do |service|
          dimensions = calculate_service_dimensions(service)
          { id: service.id, **dimensions,
            metadata: { kind: :service, model: service } }
        end
      end

      def elk_junction_nodes(junctions)
        junctions.map do |junction|
          { id: junction.id, width: DEFAULT_JUNCTION_SIZE,
            height: DEFAULT_JUNCTION_SIZE,
            metadata: { kind: :junction, model: junction } }
        end
      end

      def elk_edges(edges, node_ids)
        edges.filter_map.with_index do |edge, index|
          next unless node_ids[edge.from_id] && node_ids[edge.to_id]

          { id: "edge_#{index}", sources: [edge.from_id],
            targets: [edge.to_id], metadata: { edge: edge } }
        end
      end

      def positioned_elk_graph(diagram, elk_graph)
        positions = ElkPositions.new(
          services: {}, junctions: {}, groups: {},
        )
        collect_elk_positions(elk_graph.fetch(:children), positions)
        normalize_elk_group_bounds!(diagram, positions)
        positioned_elk_result(diagram, positions)
      end

      def positioned_elk_result(diagram, positions)
        {
          services: positions.services, junctions: positions.junctions,
          groups: positions.groups,
          edges: position_edges(diagram, positioned_elk_nodes(positions)),
          width: calculate_total_width(*positions.to_h.values),
          height: calculate_total_height(*positions.to_h.values)
        }
      end

      def positioned_elk_nodes(positions)
        positions.services.merge(positions.junctions)
      end

      def collect_elk_positions(nodes, positions, parent_x = 0, parent_y = 0)
        nodes.each do |node|
          x_coord = parent_x + node.fetch(:x)
          y_coord = parent_y + node.fetch(:y)
          collect_elk_node(node, x_coord, y_coord, positions)
          collect_elk_positions(
            Array(node[:children]), positions, x_coord, y_coord
          )
        end
      end

      def collect_elk_node(node, x_coord, y_coord, positions)
        metadata = node.fetch(:metadata)
        model = metadata.fetch(:model)
        target = {
          service: positions.services,
          junction: positions.junctions,
          group: positions.groups,
        }
          .fetch(metadata.fetch(:kind))
        target[model.id] = positioned_elk_node(node, x_coord, y_coord, model)
      end

      def positioned_elk_node(node, x_coord, y_coord, model)
        kind = node.dig(:metadata, :kind)
        height = node.fetch(:height)
        if kind == :group && Array(node[:children]).any?
          height += GROUP_LABEL_ALLOWANCE
        end
        {
          kind => model, x: x_coord, y: y_coord,
          width: node.fetch(:width), height: node.fetch(:height),
          group_id: model.respond_to?(:group_id) ? model.group_id || :root : nil
        }.merge(height: height)
      end

      def normalize_elk_group_bounds!(diagram, positions)
        deepest_groups_first(diagram.groups).each do |group|
          normalize_elk_group!(diagram, group, positions)
        end
        pack_elk_siblings!(diagram, nil, positions)
      end

      def normalize_elk_group!(diagram, group, positions)
        pack_elk_siblings!(diagram, group.id, positions)
        bounds = positions.groups.fetch(group.id)
        members = elk_direct_members(diagram, group.id, positions)
        return if members.empty?

        resize_elk_group!(bounds, members)
      end

      def resize_elk_group!(bounds, members)
        width = elk_group_span(bounds, members, :x, :width)
        height = elk_group_height(bounds, members)
        bounds[:width] = [bounds[:width], width].max
        bounds[:height] = [bounds[:height], height].max
      end

      def elk_direct_members(diagram, parent_id, positions)
        group_id = parent_id || :root
        elk_member_nodes(positions, group_id) +
          elk_child_groups(diagram, parent_id, positions.groups)
      end

      def elk_member_nodes(positions, group_id)
        [positions.services, positions.junctions].flat_map do |nodes|
          nodes.values.select { |node| node[:group_id] == group_id }
        end
      end

      def elk_child_groups(diagram, parent_id, groups)
        diagram.groups.filter_map do |child|
          groups[child.id] if child.parent_id == parent_id
        end
      end

      def pack_elk_siblings!(diagram, parent_id, positions)
        siblings = elk_direct_members(diagram, parent_id, positions)
          .sort_by { |node| node[:x] }
        cursor = nil
        siblings.each do |node|
          shift = cursor ? [cursor - node[:x], 0].max : 0
          shift_elk_component!(diagram, node, shift, positions)
          cursor = node[:x] + node[:width] + DEFAULT_SPACING
        end
      end

      def shift_elk_component!(diagram, node, shift, positions)
        return if shift.zero?

        if node[:group]
          shift_elk_group!(diagram, node, shift, positions)
        else
          node[:x] += shift
        end
      end

      def shift_elk_group!(diagram, node, shift, positions)
        ids = descendant_group_ids(diagram, node[:group].id)
        positions.groups.slice(*ids).each_value do |group|
          group[:x] += shift
        end
        positioned_elk_nodes(positions).each_value do |member|
          shift_elk_member!(member, ids, shift)
        end
      end

      def shift_elk_member!(member, group_ids, shift)
        member[:x] += shift if group_ids.include?(member[:group_id])
      end

      def elk_group_span(group, members, start, size)
        members.map { |member| member[start] + member[size] }.max - group[start]
      end

      def elk_group_height(group, members)
        bottoms = members.map do |member|
          allowance = member[:service] ? SERVICE_LABEL_OFFSET : 0
          member[:y] + member[:height] + allowance
        end
        bottoms.max - group[:y]
      end

      def routed_elk_edges(elk_graph)
        elk_graph.fetch(:edges).filter_map do |edge|
          section = Array(edge[:sections]).first
          next unless section

          { edge: edge.dig(:metadata, :edge),
            points: elk_section_points(section) }
        end
      end

      def elk_section_points(section)
        [section.fetch(:startPoint), *Array(section[:bendPoints]),
         section.fetch(:endPoint)]
      end

      def typed_nodes(graph)
        typed_groups(graph[:groups]) + typed_services(graph[:services]) +
          typed_junctions(graph[:junctions])
      end

      def typed_groups(groups)
        groups.values.map { |info| typed_group(info) }
      end

      def typed_group(info)
        group = info[:group]
        attributes = node_geometry(info).merge(
          id: group.id, kind: "group", icon: group.icon,
          icon_x: info[:x] + info[:width] - 30,
          icon_y: info[:y] + 25, parent_id: group.parent_id,
          labels: group_labels(group, info)
        )
        Node.new(**attributes)
      end

      def group_labels(group, info)
        positioned_label(
          group.label, info[:x] + 10, info[:y] + 20,
          **label_typography(:group)
        )
      end

      def typed_services(services)
        services.values.map { |info| typed_service(info) }
      end

      def typed_service(info)
        service = info[:service]
        attributes = node_geometry(info).merge(
          id: service.id, kind: "service",
          icon: service.icon, icon_x: horizontal_center(info),
          icon_y: info[:y] + (info[:height] / 2),
          group_id: normalized_group_id(info[:group_id]),
          labels: service_labels(service, info)
        )
        Node.new(**attributes)
      end

      def service_labels(service, info)
        positioned_label(
          service.label, horizontal_center(info),
          info[:y] + info[:height] + SERVICE_LABEL_OFFSET,
          **label_typography(:service)
        )
      end

      def horizontal_center(info)
        info[:x] + (info[:width] / 2)
      end

      def node_geometry(info)
        { x: info[:x], y: info[:y], width: info[:width], height: info[:height] }
      end

      def typed_junctions(junctions)
        junctions.values.map { |info| typed_junction(info) }
      end

      def typed_junction(info)
        attributes = node_geometry(info).merge(
          id: info[:junction].id, kind: "junction",
          group_id: normalized_group_id(info[:group_id])
        )
        Node.new(**attributes, **circle_geometry(info))
      end

      def circle_geometry(info)
        { center_x: horizontal_center(info),
          center_y: info[:y] + (info[:height] / 2),
          radius: info[:width] / 2 }
      end

      def normalized_group_id(group_id)
        group_id == :root ? nil : group_id
      end

      def positioned_label(text, x_coord, y_coord, **typography)
        return [] unless text

        [Label.new(text: text, x: x_coord, y: y_coord, **typography)]
      end

      def typed_edges(routed_edges)
        routed_edges.map.with_index do |routed, index|
          typed_edge(routed, index)
        end
      end

      def typed_edge(routed, index)
        edge = routed[:edge]
        points = routed[:points].map { |point| typed_point(point) }
        Edge.new(
          id: "edge_#{index}", source: edge.from_id, target: edge.to_id,
          sections: [typed_section(points)],
          labels: edge_label(edge.label, points)
        )
      end

      def typed_point(point)
        Point.new(x: point[:x], y: point[:y])
      end

      def typed_section(points)
        Section.new(start_point: points.first, end_point: points.last,
                    bend_points: points[1...-1])
      end

      def edge_label(text, points)
        return [] unless text && !text.empty?

        first, second = points
        [Label.new(text: text, x: midpoint(first.x, second.x),
                   y: midpoint(first.y, second.y) - 5,
                   **label_typography(:edge))]
      end

      def label_typography(kind)
        role, target = LABEL_FONT_ROLES.fetch(kind)
        { font_size: scaled_font_size(role, target) }.merge(label_style(kind))
      end

      def label_style(kind)
        {
          group: { font_weight: typography_value(:font_weight_bold) || "bold" },
          service: { font_family: typography_value(:font_family),
                     text_anchor: "middle" },
          edge: { text_anchor: "middle" },
        }.fetch(kind)
      end

      def scaled_font_size(role, target)
        default = Theme::Registry.get(:default).typography.public_send(role)
        configured = typography_value(role)
        configured = default unless configured&.positive?
        size = configured * target / default
        size.to_i == size ? size.to_i : size
      rescue NoMethodError
        target
      end

      def typography_value(role)
        theme.typography&.public_send(role)
      rescue NoMethodError
        nil
      end

      def midpoint(first, second)
        (first + second) / 2
      end

      def route_edges(graph)
        graph[:edges].map do |edge_info|
          edge = edge_info[:edge]
          from = route_endpoint(edge_info, find_node(graph, edge.from_id),
                                :from)
          to = route_endpoint(edge_info, find_node(graph, edge.to_id), :to)
          { edge: edge, points: routed_points(edge, from, to, graph) }
        end
      end

      def route_endpoint(edge_info, box, endpoint)
        { point: { x: edge_info[:"#{endpoint}_x"],
                   y: edge_info[:"#{endpoint}_y"] },
          box: box, side: edge_info[:"#{endpoint}_side"] }
      end

      def routed_points(edge, from, to, graph)
        architecture_edge_router.route(
          from: from, to: to, obstacles: obstacles_for(edge, graph),
        )
      rescue StandardError
        [from[:point], to[:point]]
      end

      def architecture_edge_router
        @architecture_edge_router ||=
          Renderer::ArchitectureEdgeRouter.new
      end

      def obstacles_for(edge, graph)
        excluded_ids = [edge.from_id, edge.to_id]
        node_obstacles(graph, excluded_ids) + group_obstacles(edge, graph)
      end

      def node_obstacles(graph, excluded_ids)
        nodes = graph[:services].values + graph[:junctions].values
        nodes.reject { |info| excluded_ids.include?(positioned_node_id(info)) }
      end

      def group_obstacles(edge, graph)
        excluded = endpoint_ancestor_groups(edge.from_id, graph) |
          endpoint_ancestor_groups(edge.to_id, graph)
        graph[:groups].except(*excluded).values
      end

      def endpoint_ancestor_groups(node_id, graph)
        ancestor_group_ids(find_node(graph, node_id)[:group_id], graph)
      end

      def ancestor_group_ids(group_id, graph)
        ids = []
        current_id = group_id
        while current_id && current_id != :root && !ids.include?(current_id)
          ids << current_id
          current_id = graph[:groups][current_id]&.dig(:group)&.parent_id
        end
        ids
      end

      def find_node(graph, id)
        graph[:services][id] || graph[:junctions][id]
      end

      def positioned_node_id(info)
        info[:service]&.id || info[:junction]&.id
      end

      def scene_dimensions(graph, routed_edges)
        points = routed_edges.flat_map { |routed| routed[:points] }
        width = [graph[:width], *points.map { |point| point[:x] }].max
        height = [graph[:height], *points.map { |point| point[:y] }].max
        [width, height]
      end

      def build_hierarchy(diagram)
        hierarchy = {
          groups: {},
          services_by_group: {},
          junctions_by_group: {},
        }

        # Map groups
        hierarchy[:groups] = diagram.groups.to_h do |group|
          parent_id = group.parent_id || :root
          [
            group.id,
            {
              group: group,
              parent_id: parent_id,
              children: [],
            },
          ]
        end

        # Build parent-child relationships for groups
        diagram.groups.each do |group|
          if group.parent_id && hierarchy[:groups][group.parent_id]
            hierarchy[:groups][group.parent_id][:children] << group.id
          end
        end

        # Map services to groups
        diagram.services.each do |service|
          group_id = service.group_id || :root
          hierarchy[:services_by_group][group_id] ||= []
          hierarchy[:services_by_group][group_id] << service
        end

        # Map junctions to groups
        diagram.junctions.each do |junction|
          group_id = junction.group_id || :root
          hierarchy[:junctions_by_group][group_id] ||= []
          hierarchy[:junctions_by_group][group_id] << junction
        end

        hierarchy
      end

      # Edge sides imply a grid, as in mmdc: "a:R -- L:b" puts b to the right
      # of a. A diagram without edges, or whose grid would put a group box
      # over a node or group that is not inside it, keeps the row layout.
      # @return [Array(Hash, Hash, Hash)] services, junctions, group bounds
      def position_nodes(diagram, hierarchy)
        unless diagram.edges.empty?
          placed = bounded(diagram, *position_on_grid(diagram))
          return placed if groups_separate?(diagram, *placed)

          placed = bounded(diagram, *position_in_blocks(diagram))
          return placed if groups_separate?(diagram, *placed)
        end
        bounded(diagram, *position_by_rows(diagram, hierarchy))
      end

      def bounded(diagram, services, junctions)
        [services, junctions,
         calculate_group_bounds(diagram, services, junctions)]
      end

      def groups_separate?(diagram, services, junctions, bounds)
        nodes = services.values + junctions.values
        bounds.all? do |id, box|
          inside = descendant_group_ids(diagram, id)
          nodes.all? do |node|
            inside.include?(node[:group_id]) || !boxes_overlap?(box, node)
          end && sibling_groups_clear?(diagram, bounds, id, inside)
        end
      end

      def sibling_groups_clear?(diagram, bounds, id, inside)
        related = inside | ancestor_ids(diagram, id)
        bounds.none? do |other_id, other|
          !related.include?(other_id) && boxes_overlap?(bounds[id], other)
        end
      end

      def descendant_group_ids(diagram, id)
        ids = [id]
        ids.each do |current|
          diagram.groups.each do |group|
            next if group.parent_id != current || ids.include?(group.id)

            ids << group.id
          end
        end
        ids
      end

      def ancestor_ids(diagram, id)
        by_id = diagram.groups.to_h { |group| [group.id, group] }
        ids = []
        current = by_id[id]&.parent_id
        while current && !ids.include?(current)
          ids << current
          current = by_id[current]&.parent_id
        end
        ids
      end

      def boxes_overlap?(first, second)
        spans_overlap?(first, second, :x, :width) &&
          spans_overlap?(first, second, :y, :height)
      end

      def spans_overlap?(first, second, start, size)
        first[start] < second[start] + second[size] &&
          second[start] < first[start] + first[size]
      end

      def position_by_rows(diagram, hierarchy)
        services = position_services(diagram, hierarchy)
        [services, position_junctions(diagram, hierarchy, services)]
      end

      def position_on_grid(diagram)
        nodes = grid_nodes(diagram)
        cells = grid_cells(nodes, diagram.edges)
        entries = cells.to_h do |id, (x_coord, y_coord)|
          [id, grid_entry(nodes.fetch(id), x_coord, y_coord)]
        end
        services_and_junctions(nodes, entries)
      end

      def services_and_junctions(nodes, entries)
        entries.partition { |id, _| nodes.fetch(id)[:service] }.map(&:to_h)
      end

      # Each top-level group is laid out as its own grid block, and the blocks
      # are placed along the sides of the edges that join them, as mmdc
      # offsets whole groups. A node outside every group is a block of its own.
      def position_in_blocks(diagram)
        nodes = grid_nodes(diagram)
        owner = block_owners(diagram, nodes)
        inner, outer = diagram.edges.partition do |edge|
          owner[edge.from_id] == owner[edge.to_id]
        end
        shifts = block_shifts(nodes, owner, inner, outer)
        entries = block_entries(nodes, owner, inner, shifts)
        services_and_junctions(nodes, entries)
      end

      def block_entries(nodes, owner, inner, shifts)
        shifts.flat_map do |block, (shift_x, shift_y)|
          members = block_members(nodes, owner, block)
          grid_cells(members, inner).map do |id, (x_coord, y_coord)|
            [id, grid_entry(nodes.fetch(id), x_coord + shift_x,
                            y_coord + shift_y)]
          end
        end.to_h
      end

      def block_members(nodes, owner, block)
        nodes.select { |id, _| owner[id] == block }
      end

      def block_owners(diagram, nodes)
        nodes.to_h do |id, node|
          group = node[:group_id]
          top = ([group] + ancestor_ids(diagram, group)).last
          [id, top == :root ? id : top]
        end
      end

      # block => [x shift, y shift]. Blocks take the cell of the side the
      # joining edge names; each grid column and row is as wide as its
      # largest block.
      def block_shifts(nodes, owner, inner, outer)
        blocks = owner.values.uniq
        extents = block_extents(blocks, nodes, owner, inner)
        cells = place_blocks(blocks, owner, outer)
        x_starts = block_starts(cells, extents, 0, :right)
        y_starts = block_starts(cells, extents, 1, :bottom)
        blocks.to_h do |block|
          col, row = cells.fetch(block)
          [block, [x_starts.fetch(col), y_starts.fetch(row)]]
        end
      end

      def block_extents(blocks, nodes, owner, inner)
        blocks.to_h do |block|
          members = block_members(nodes, owner, block)
          [block, block_extent(members, grid_cells(members, inner))]
        end
      end

      def block_extent(members, cells)
        {
          right: cells.map { |id, c| c[0] + (members[id][:width] / 2.0) }.max,
          bottom: cells.map { |id, c| c[1] + (members[id][:height] / 2.0) }.max,
        }
      end

      def place_blocks(blocks, owner, outer)
        links = edge_links(outer) do |edge|
          [owner[edge.from_id], owner[edge.to_id]]
        end
        cells = {}
        offset = 0
        each_placed_component(blocks, links) do |placed|
          placed.each { |block, (col, row)| cells[block] = [offset + col, row] }
          offset += placed.values.map(&:first).max + 1
        end
        cells
      end

      def block_starts(cells, extents, axis, edge)
        tracks = cells.group_by { |_, cell| cell[axis] }
        start = 0
        tracks.sort.to_h do |index, members|
          at = start
          start += track_size(members, extents, edge) + BLOCK_GAP
          [index, at]
        end
      end

      def track_size(members, extents, edge)
        members.map { |block, _| extents[block][edge] }.max
      end

      def grid_nodes(diagram)
        services = diagram.services.to_h do |service|
          dims = calculate_service_dimensions(service)
          [service.id, dims.merge(service: service,
                                  group_id: service.group_id || :root)]
        end
        junctions = diagram.junctions.to_h do |junction|
          [junction.id, { junction: junction, width: DEFAULT_JUNCTION_SIZE,
                          height: DEFAULT_JUNCTION_SIZE,
                          group_id: junction.group_id || :root }]
        end
        services.merge(junctions)
      end

      def grid_entry(node, x_coord, y_coord)
        node.merge(x: x_coord - (node[:width] / 2.0),
                   y: y_coord - (node[:height] / 2.0))
      end

      # Pixel cell centres per node id; components sit side by side.
      def grid_cells(nodes, edges)
        links = grid_links(nodes, edges)
        cells = {}
        offset = GRID_ORIGIN
        each_placed_component(nodes.keys, links) do |placed|
          cells.merge!(pixel_cells(placed, offset))
          offset += pixel_width(placed) + COMPONENT_GAP
        end
        cells
      end

      def pixel_cells(placed, offset)
        placed.transform_values do |(col, row)|
          [offset + (col * GRID_PITCH_X), GRID_ORIGIN + (row * GRID_PITCH_Y)]
        end
      end

      def pixel_width(placed)
        (placed.values.map(&:first).max * GRID_PITCH_X) + DEFAULT_SERVICE_WIDTH
      end

      # Yields each connected component's cells, moved so that its leftmost
      # column and topmost row are 0.
      def each_placed_component(ids, links)
        components(ids, links).each do |component|
          yield from_origin(place_component(component, links))
        end
      end

      def from_origin(placed)
        min_col = placed.values.map(&:first).min
        min_row = placed.values.map(&:last).min
        placed.transform_values { |(col, row)| [col - min_col, row - min_row] }
      end

      SIDE_STEPS = {
        "R" => [1, 0], "L" => [-1, 0], "T" => [0, -1], "B" => [0, 1]
      }.freeze
      private_constant :SIDE_STEPS

      # id => [[neighbour id, [dx, dy] from id to neighbour], ...]
      def grid_links(nodes, edges)
        known = edges.select do |edge|
          nodes.key?(edge.from_id) && nodes.key?(edge.to_id)
        end
        edge_links(known) { |edge| [edge.from_id, edge.to_id] }
      end

      # The block returns the [from, to] keys that an edge joins.
      def edge_links(edges)
        links = Hash.new { |hash, key| hash[key] = [] }
        edges.each do |edge|
          from, to = yield(edge)
          step = SIDE_STEPS.fetch(valid_side(edge.from_position, "R"))
          links[from] << [to, step]
          links[to] << [from, step.map(&:-@)]
        end
        links
      end

      def components(ids, links)
        seen = {}
        ids.filter_map { |id| reachable_from(id, links, seen) unless seen[id] }
      end

      def reachable_from(start, links, seen)
        queue = [start]
        seen[start] = true
        queue.each do |current|
          links[current].map(&:first).each do |neighbour|
            next if seen[neighbour]

            seen[neighbour] = true
            queue << neighbour
          end
        end
        queue
      end

      def place_component(component, links)
        placed = { component.first => [0, 0] }
        taken = { [0, 0] => true }
        component.each do |id|
          links[id].each do |neighbour, step|
            next if placed.key?(neighbour)

            placed[neighbour] = claim_free_cell(placed.fetch(id), step, taken)
          end
        end
        placed
      end

      def claim_free_cell(from, step, taken)
        cell = [from[0] + step[0], from[1] + step[1]]
        cell = [cell[0] + step[0], cell[1] + step[1]] while taken[cell]
        taken[cell] = true
        cell
      end

      def position_services(diagram, hierarchy)
        positions = {}
        current_x = DEFAULT_SPACING
        current_y = DEFAULT_SPACING

        # Group services by their group
        groups_to_layout = [:root] + diagram.groups.map(&:id)

        groups_to_layout.each do |group_id|
          services = hierarchy[:services_by_group][group_id] || []
          next if services.empty?

          # Position services in this group
          services.each do |service|
            dims = calculate_service_dimensions(service)

            positions[service.id] = {
              service: service,
              x: current_x,
              y: current_y,
              width: dims[:width],
              height: dims[:height],
              group_id: group_id,
            }

            current_x += dims[:width] + DEFAULT_SPACING
          end

          # Move to next row
          current_x = DEFAULT_SPACING
          current_y += DEFAULT_SERVICE_HEIGHT + (DEFAULT_SPACING * 2)
        end

        positions
      end

      # Junctions lay out on their own row-per-group grid, same shape as
      # position_services but with a fixed small size since a junction has
      # no label or icon to size against. A group that already has services
      # anchors its junction row past them (vertically centered on that
      # row) instead of at the group's default origin, so a junction never
      # lands on the same coordinates as a service in its own group. A
      # group with no services falls back to a shared cursor that starts
      # below every already-placed service in ANY group (not just its
      # own), so a junction-only group can never land on a service that
      # was laid out under a different group entirely.
      def position_junctions(diagram, hierarchy, service_positions)
        positions = {}
        current_x = DEFAULT_SPACING
        current_y = junction_fallback_floor(service_positions)

        groups_to_layout = [:root] + diagram.groups.map(&:id)

        groups_to_layout.each do |group_id|
          junctions = hierarchy[:junctions_by_group][group_id] || []
          next if junctions.empty?

          group_services = services_in_group(service_positions, group_id)
          row_x, row_y = junction_row_origin(
            group_services, current_x,
            current_y
          )

          junctions.each do |junction|
            positions[junction.id] = {
              junction: junction,
              x: row_x,
              y: row_y,
              width: DEFAULT_JUNCTION_SIZE,
              height: DEFAULT_JUNCTION_SIZE,
              group_id: group_id,
            }

            row_x += DEFAULT_JUNCTION_SIZE + DEFAULT_SPACING
          end

          if group_services.any?
            current_y = next_junction_y(current_y, row_y)
          else
            # current_x is never reassigned elsewhere in this method, so
            # re-setting it to its own initial value here was a no-op.
            current_y += DEFAULT_JUNCTION_SIZE + DEFAULT_SPACING
          end
        end

        positions
      end

      def services_in_group(service_positions, group_id)
        service_positions.values.select { |pos| pos[:group_id] == group_id }
      end

      def next_junction_y(current_y, row_y)
        row_bottom = row_y + DEFAULT_JUNCTION_SIZE + DEFAULT_SPACING
        [current_y, row_bottom].max
      end

      def junction_row_origin(group_services, fallback_x, fallback_y)
        return [fallback_x, fallback_y] if group_services.empty?

        row_x = group_services.map do |service|
          service[:x] + service[:width]
        end.max + DEFAULT_SPACING
        row_top = group_services.map { |s| s[:y] }.min
        row_y =
          row_top + ((DEFAULT_SERVICE_HEIGHT - DEFAULT_JUNCTION_SIZE) / 2.0)

        [row_x, row_y]
      end

      # A junction-only group (no services of its own) has no row to
      # anchor against, so it falls back to a shared cursor. That cursor
      # must start below every service in the WHOLE diagram, not just
      # DEFAULT_SPACING. Otherwise, it reuses the origin that position_services
      # gave to a service in an unrelated group.
      def junction_fallback_floor(service_positions)
        return DEFAULT_SPACING if service_positions.empty?

        service_positions.values.map do |pos|
          pos[:y] + pos[:height]
        end.max + DEFAULT_SPACING
      end

      def calculate_service_dimensions(_service)
        { width: DEFAULT_SERVICE_WIDTH, height: DEFAULT_SERVICE_HEIGHT }
      end

      def calculate_group_bounds(diagram, service_positions, junction_positions)
        bounds = {}
        members = service_positions.values + junction_positions.values

        deepest_groups_first(diagram.groups).each do |group|
          boxes = group_boxes(diagram, group, members, bounds)
          bounds[group.id] = padded_bounds(group, boxes) if boxes.any?
        end
        place_empty_groups(diagram, bounds, members)
      end

      def group_boxes(diagram, group, members, bounds)
        members.select { |pos| pos[:group_id] == group.id } +
          child_group_bounds(diagram, group, bounds)
      end

      def child_group_bounds(diagram, group, bounds)
        diagram.groups.select { |child| child.parent_id == group.id }
          .filter_map { |child| bounds[child.id] }
      end

      def padded_bounds(group, boxes)
        min_x, width = span(boxes, :x, :width)
        min_y, height = span(boxes, :y, :height)
        pad = DEFAULT_GROUP_PADDING
        {
          group: group,
          x: min_x - pad,
          y: min_y - pad,
          width: width + (pad * 2),
          height: height + (pad * 2) + GROUP_LABEL_ALLOWANCE,
        }
      end

      # [lowest start, length] covered by the boxes along one axis.
      def span(boxes, start, size)
        low = boxes.map { |box| box[start] }.min
        high = boxes.map { |box| box[start] + box[size] }.max
        [low, high - low]
      end

      # mmdc draws a group with nothing in it as a small box beside the
      # diagram. A chain of empty nested groups stays undrawn: only an
      # isolated empty group (no parent, no child groups) is placed.
      def place_empty_groups(diagram, bounds, members)
        right = right_edge(members + bounds.values)
        centre_y = members_centre_y(members)
        diagram.groups.each do |group|
          next unless isolated_empty_group?(diagram, group, bounds)

          x_coord = right ? right + EMPTY_GROUP_GAP : GRID_ORIGIN
          bounds[group.id] = empty_group_bounds(group, x_coord, centre_y)
          right = x_coord + EMPTY_GROUP_SIZE
        end
        bounds
      end

      def right_edge(boxes)
        boxes.map { |box| box[:x] + box[:width] }.max
      end

      def members_centre_y(members)
        return GRID_ORIGIN + (EMPTY_GROUP_SIZE / 2) if members.empty?

        top = members.map { |box| box[:y] }.min
        bottom = members.map { |box| box[:y] + box[:height] }.max
        (top + bottom) / 2.0
      end

      def isolated_empty_group?(diagram, group, bounds)
        return false if bounds.key?(group.id) || group.parent_id

        diagram.groups.none? { |other| other.parent_id == group.id }
      end

      def empty_group_bounds(group, x_coord, centre_y)
        { group: group, x: x_coord, y: centre_y - (EMPTY_GROUP_SIZE / 2.0),
          width: EMPTY_GROUP_SIZE, height: EMPTY_GROUP_SIZE }
      end

      # A parent group with no direct service/junction of its own must read
      # its child group's bounds, so the child has to be processed first.
      # diagram.groups is in source-declaration order, which puts a parent
      # before a childless-of-its-own child when the mermaid source declares
      # the parent group first (the natural way to write nesting) - sort by
      # depth, deepest first, so every child is bounded before its parent
      # looks it up. A parent_id cycle (malformed diagram) can't loop
      # forever: `seen` stops recursion the second time an id reappears.
      def deepest_groups_first(groups)
        by_id = groups.to_h { |g| [g.id, g] }
        depths = groups.to_h { |g| [g.id, group_depth(g, by_id, [])] }

        groups.each_with_index
          .sort_by { |group, index| [-depths[group.id], index] }
          .map(&:first)
      end

      def group_depth(group, by_id, seen)
        return 0 if seen.include?(group.id)

        parent = group.parent_id && by_id[group.parent_id]
        return 0 unless parent

        1 + group_depth(parent, by_id, seen + [group.id])
      end

      # The declared (or defaulted) side is used literally, never mirrored -
      # a junction or service positioned on the "wrong" side of its hint is
      # no longer worked around here by lying about which face the line
      # attaches to. Architecture's ArchitectureEdgeRouter draws
      # around whatever is in the way instead, so the transform only needs
      # to hand it the real anchor point and the real declared side.
      def position_edges(diagram, service_positions)
        diagram.edges.filter_map do |edge|
          from = service_positions[edge.from_id]
          to = service_positions[edge.to_id]

          next unless from && to

          from_side = valid_side(edge.from_position, "R")
          to_side = valid_side(edge.to_position, "L")
          from_point = calculate_connection_point(from, from_side)
          to_point = calculate_connection_point(to, to_side)

          {
            edge: edge,
            from_x: from_point[:x],
            from_y: from_point[:y],
            to_x: to_point[:x],
            to_y: to_point[:y],
            from_side: from_side,
            to_side: to_side,
          }
        end
      end

      # The grammar's position token is match("[LRTB]").repeat(1) - one OR
      # MORE, no upper bound - so a grammar-valid edge like `a:RT -- L:b`
      # parses to from_position == "RT". ArchitectureEdgeRouter::
      # FACE_NORMAL only has single-character keys, so an un-clamped value
      # reaches the router and raises the moment a detour is actually
      # needed. Falling back to +default+ here keeps that contract at the
      # one place every declared side passes through.
      def valid_side(position, default)
        VALID_SIDES.include?(position) ? position : default
      end

      def calculate_connection_point(service_pos, position)
        case position
        when "L"
          {
            x: service_pos[:x],
            y: service_pos[:y] + (service_pos[:height] / 2),
          }
        when "R"
          {
            x: service_pos[:x] + service_pos[:width],
            y: service_pos[:y] + (service_pos[:height] / 2),
          }
        when "T"
          { x: service_pos[:x] + (service_pos[:width] / 2), y: service_pos[:y] }
        when "B"
          {
            x: service_pos[:x] + (service_pos[:width] / 2),
            y: service_pos[:y] + service_pos[:height],
          }
        else
          # Default to right
          {
            x: service_pos[:x] + service_pos[:width],
            y: service_pos[:y] + (service_pos[:height] / 2),
          }
        end
      end

      def calculate_total_width(
        service_positions,
        junction_positions,
        group_bounds
      )
        max_service_x = service_positions.values.map do |service|
          service[:x] + service[:width]
        end.max || 0
        max_junction_x = junction_positions.values.map do |junction|
          junction[:x] + junction[:width]
        end.max || 0
        max_group_x = group_bounds.values.map { |g| g[:x] + g[:width] }.max || 0

        [max_service_x, max_junction_x, max_group_x].max + DEFAULT_SPACING
      end

      def calculate_total_height(
        service_positions,
        junction_positions,
        group_bounds
      )
        max_service_y = service_positions.values.map do |service|
          service[:y] + service[:height]
        end.max || 0
        max_junction_y = junction_positions.values.map do |junction|
          junction[:y] + junction[:height]
        end.max || 0
        max_group_y = group_bounds.values.map do |group|
          group[:y] + group[:height]
        end.max || 0

        [max_service_y, max_junction_y, max_group_y].max + DEFAULT_SPACING
      end

      def normal_font_size
        theme.typography&.font_size_normal ||
          Theme::Registry.get(:default).typography.font_size_normal
      end
    end
  end
end
