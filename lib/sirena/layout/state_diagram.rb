# frozen_string_literal: true

require_relative "base"
require_relative "elk_placement"
require_relative "grid"
require_relative "../diagram/state_diagram"
require_relative "../notation/mermaid/ir_adapters/state_diagram"

module Sirena
  module Layout
    # Computes final canvas geometry for state diagrams.
    class StateDiagram < Base
      DEFAULT_FONT_SIZE = 14.0
      DEFAULT_SMALL_FONT_SIZE = 12.0
      TERMINAL_RADIUS = 7.0
      TERMINAL_TYPES = %w[start end].freeze

      State = Data.define(
        :id, :label, :state_type, :description, :descriptions
      )
      private_constant :State

      STATE_TYPES = {
        "state" => "normal",
        "initial_state" => "start",
        "final_state" => "end",
        "choice_state" => "choice",
        "fork_state" => "fork",
        "join_state" => "join",
      }.freeze
      DIRECTIONS = {
        "TD" => DIRECTION_DOWN, "TB" => DIRECTION_DOWN,
        "LR" => DIRECTION_RIGHT, "RL" => DIRECTION_LEFT,
        "BT" => DIRECTION_UP
      }.freeze
      LAYOUT_SETTINGS = {
        ElkOptions::NODE_NODE_SPACING => 60,
        ElkOptions::LAYER_SPACING => 60,
        ElkOptions::EDGE_NODE_SPACING => 40,
        ElkOptions::EDGE_EDGE_SPACING => 30,
        ElkOptions::NODE_PLACEMENT => "SIMPLE",
      }.freeze
      private_constant :STATE_TYPES, :DIRECTIONS, :LAYOUT_SETTINGS,
                       :TERMINAL_RADIUS, :TERMINAL_TYPES

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
        attribute :path, :string
        attribute :trigger, :string
        attribute :guard_condition, :string
      end

      class Node < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :x, :float
        attribute :y, :float
        attribute :width, :float
        attribute :height, :float
        attribute :labels, Label, collection: true, default: -> { [] }
        attribute :state_type, :string
        attribute :shape_type, :string
        attribute :center_x, :float
        attribute :center_y, :float
        attribute :radius, :float
        attribute :inner_radius, :float
        attribute :shape_points, :string
        attribute :shape_y, :float
        attribute :shape_height, :float
      end

      class Scene < Layout::Scene
        attribute :id, :string
        attribute :view_box, :string
        attribute :children, Node, collection: true, default: -> { [] }
        attribute :edges, Edge, collection: true, default: -> { [] }
      end

      # :grid (the default) or :elk. Grid remains the default until the
      # parity ratchet permits changing it.
      attr_accessor :placement

      class << self
        def from_graph(graph, theme: nil)
          layout = new
          layout.theme = theme if theme
          layout.send(:scene_from_graph, graph)
        end

        def center(box)
          {
            x: (box[:x] || 0) + ((box[:width] || 100) / 2),
            y: (box[:y] || 0) + ((box[:height] || 50) / 2),
          }
        end

        def shape_geometry(state, state_type)
          dimensions = box_geometry(state)
          midpoint = center(dimensions)
          radius = state.dig(:metadata, :shape_radius)
          dimensions.merge(
            shape_details(dimensions, midpoint, state_type, radius),
          )
        end

        def label_geometry(state, label, index, font_sizes)
          x_position, y_position = label_position(state, index)
          {
            text: label[:text], width: label[:width], height: label[:height],
            x: x_position, y: y_position,
            font_size: index.zero? ? font_sizes[:normal] : font_sizes[:small]
          }
        end

        def transition_label_geometry(source, target, label, font_size)
          source_center = center(source)
          target_center = center(target)
          {
            text: label[:text], width: label[:width], height: label[:height],
            x: (source_center[:x] + target_center[:x]) / 2,
            y: ((source_center[:y] + target_center[:y]) / 2) - 8,
            font_size: font_size
          }
        end

        def path_data(start_point, end_point, bend_points)
          points = [start_point, *bend_points, end_point]
          ["M #{coordinate(points.first.x)} #{coordinate(points.first.y)}",
           *points.drop(1).map do |point|
             "L #{coordinate(point.x)} #{coordinate(point.y)}"
           end].join(" ")
        end

        def renderer_extent(graph, axis)
          return coordinate(graph.public_send(axis) - 40) if graph.is_a?(Scene)

          boxes = graph[:children]
          return default_extent(axis) unless boxes

          maximum_extent(boxes, axis) + 60
        end

        private

        def box_geometry(state)
          {
            x: state[:x] || 0, y: state[:y] || 0,
            width: state[:width] || 100, height: state[:height] || 50
          }
        end

        def shape_details(dimensions, midpoint, state_type, radius)
          radius ||= [dimensions[:width], dimensions[:height]].min / 2
          {
            center_x: midpoint[:x], center_y: midpoint[:y], radius: radius,
            inner_radius: radius - 5,
            shape_points: choice_points(dimensions, midpoint, state_type),
            shape_y: dimensions[:y] + (dimensions[:height] / 2) - 5,
            shape_height: 10
          }
        end

        def choice_points(dimensions, midpoint, state_type)
          return unless state_type == "choice"

          x_position = dimensions[:x]
          y_position = dimensions[:y]
          width = dimensions[:width]
          height = dimensions[:height]
          [
            "#{midpoint[:x]},#{y_position}",
            "#{x_position + width},#{midpoint[:y]}",
            "#{midpoint[:x]},#{y_position + height}",
            "#{x_position},#{midpoint[:y]}",
          ].join(" ")
        end

        def label_position(state, index)
          midpoint = center(state)
          stack_offset = ((state[:labels] || []).length - 1) * 10
          [midpoint[:x], midpoint[:y] - stack_offset + (index * 20)]
        end

        def default_extent(axis)
          axis == :width ? 800 : 600
        end

        def maximum_extent(boxes, axis)
          position, fallback = axis == :width ? [:x, 100] : [:y, 50]
          boxes.map do |state|
            (state[position] || 0) + (state[axis] || fallback)
          end.max || default_extent(axis)
        end

        def coordinate(number)
          number.to_i == number ? number.to_i : number
        end
      end

      def scene(diagram)
        graph = build_graph(diagram)
        placer.apply(graph)
        orient_grid_terminals(graph)
        scene_from_graph(graph)
      end

      private

      def placer
        placement == :elk ? ElkPlacement : Grid
      end

      def orient_grid_terminals(graph)
        return if placement == :elk
        return unless graph.dig(:layoutOptions, ElkOptions::DIRECTION) ==
          DIRECTION_DOWN

        graph[:children].each do |state|
          shape_type = state.dig(:metadata, :shape_type)
          next unless TERMINAL_TYPES.include?(shape_type)

          state[:x], state[:y] = state[:y], state[:x]
        end
      end

      # Converts a state diagram to a graph structure.
      #
      # @param diagram [Diagram::StateDiagram] the state diagram to transform
      # @return [Hash] elkrb-compatible graph hash
      def build_graph(diagram)
        graph = ir_graph(diagram)
        semantics = graph.nodes.group_by(&:parent_id)
        states = layout_states(graph, semantics)
        {
          id: diagram_identifier(graph, semantics),
          children: transform_states(states),
          edges: transform_transitions(graph, semantics),
          layoutOptions: layout_options(layout_direction(graph, semantics)),
        }
      end

      def ir_graph(diagram)
        return diagram if diagram.is_a?(IR::Graph)

        Notation::Mermaid::IRAdapters::StateDiagram.call(diagram)
      end

      def layout_states(graph, semantics)
        graph.nodes.filter_map do |node|
          next unless STATE_TYPES.key?(node.role) && node.parent_id.nil?

          state_from(node, semantics)
        end
      end

      def state_from(node, semantics)
        State.new(
          id: state_identifier(node, semantics),
          label: node.label,
          state_type: declared_state_type(node, semantics),
          description: semantic_value(semantics, node.id,
                                      "latest_description"),
          descriptions: semantic_values(semantics, node.id, "display_text"),
        )
      end

      def declared_state_type(node, semantics)
        semantic_value(semantics, node.id, "declared_state_type") ||
          STATE_TYPES.fetch(node.role)
      end

      def settings_node(graph)
        graph.nodes.find { |node| node.role == "diagram_settings" }
      end

      def diagram_identifier(graph, semantics)
        settings = settings_node(graph)
        return "state_diagram" unless settings

        semantic_value(semantics, settings.id, "diagram_identifier") ||
          "state_diagram"
      end

      def layout_direction(graph, semantics)
        settings = settings_node(graph)
        semantic_value(semantics, settings&.id, "layout_direction")
      end

      def semantic_value(semantics, parent_id, role)
        semantic_values(semantics, parent_id, role).first
      end

      def semantic_values(semantics, parent_id, role)
        Array(semantics[parent_id]).filter_map do |node|
          node.label if node.role == role
        end
      end

      def scene_from_graph(graph)
        children = typed_children(graph[:children] || [])
        Scene.new(
          id: graph[:id] || "state_diagram",
          **scene_geometry(graph),
          children: children,
          edges: typed_edges(
            graph[:edges] || [], children, graph[:children] || []
          ),
        )
      end

      def scene_geometry(graph)
        padding = graph.key?(:children) ? 100 : 40
        width = canvas_width(graph) + padding
        height = canvas_height(graph) + padding
        { width: width, height: height, view_box: "0 0 #{width} #{height}" }
      end

      def typed_children(children)
        children.map { |state| typed_node(state) }
      end

      def typed_node(state)
        state_type = state.dig(:metadata, :state_type) || "normal"
        shape_type = state.dig(:metadata, :shape_type) || state_type
        Node.new(
          id: state[:id], labels: typed_labels(state), state_type: state_type,
          shape_type: shape_type,
          **self.class.shape_geometry(state, shape_type)
        )
      end

      def typed_labels(state)
        (state[:labels] || []).each_with_index.map do |label, index|
          geometry = self.class.label_geometry(
            state, label, index, label_font_sizes
          )
          Label.new(**geometry)
        end
      end

      def typed_edges(edges, children, raw_children)
        nodes = children.to_h { |node| [node.id, node] }
        raw_nodes = raw_children.to_h { |node| [node[:id], node] }
        edges.filter_map { |edge| typed_edge_for(edge, nodes, raw_nodes) }
      end

      def typed_edge_for(edge, nodes, raw_nodes)
        source = nodes[edge[:sources]&.first]
        target = nodes[edge[:targets]&.first]
        return unless source && target

        typed_edge(
          edge, source, target, raw_nodes[source.id], raw_nodes[target.id]
        )
      end

      def typed_edge(edge, source, target, raw_source, raw_target)
        sections = typed_sections(edge, raw_source, raw_target)
        Edge.new(
          id: edge[:id], source: source.id, target: target.id,
          sections: sections,
          labels: typed_edge_labels(edge, raw_source, raw_target),
          path: sections_path(sections),
          trigger: edge.dig(:metadata, :trigger),
          guard_condition: edge.dig(:metadata, :guard_condition)
        )
      end

      def typed_edge_labels(edge, source, target)
        label = (edge[:labels] || []).first
        return [] unless label

        geometry = self.class.transition_label_geometry(
          source, target, label, small_font_size
        )
        [Label.new(**geometry)]
      end

      def typed_sections(edge, source, target)
        source_point = point(self.class.center(source))
        target_point = point(self.class.center(target))
        sections = edge[:sections]
        unless sections&.any?
          return [straight_section(source_point, target_point)]
        end

        sections.map do |section|
          typed_section(section, source_point, target_point)
        end
      end

      def straight_section(source_point, target_point)
        Section.new(start_point: source_point, end_point: target_point)
      end

      def typed_section(section, source_point, target_point)
        bends = (section[:bendPoints] || []).map { |item| point(item) }
        Section.new(
          start_point: point(section[:startPoint]) || source_point,
          end_point: point(section[:endPoint]) || target_point,
          bend_points: bends,
        )
      end

      def section_path(section)
        self.class.path_data(
          section.start_point, section.end_point, section.bend_points
        )
      end

      def sections_path(sections)
        sections.map { |section| section_path(section) }.join(" ")
      end

      def point(value)
        return unless value

        Point.new(x: value[:x], y: value[:y])
      end

      def canvas_width(graph)
        return 800 unless graph[:children]

        graph[:children].map do |state|
          (state[:x] || 0) + (state[:width] || 100)
        end.max || 800
      end

      def canvas_height(graph)
        return 600 unless graph[:children]

        graph[:children].map do |state|
          (state[:y] || 0) + (state[:height] || 50)
        end.max || 600
      end

      def transform_states(states)
        states.map { |state| transformed_state(state) }
      end

      def transformed_state(state)
        dimensions = calculate_state_dimensions(state)
        {
          id: state.id,
          width: dimensions[:width],
          height: dimensions[:height],
          labels: state_labels(state),
          metadata: state_metadata(state),
        }
      end

      def state_metadata(state)
        metadata = {
          state_type: state.state_type,
          shape_type: state_shape_type(state),
          description: state.description,
        }
        if TERMINAL_TYPES.include?(metadata[:shape_type])
          metadata[:shape_radius] = TERMINAL_RADIUS
        end
        metadata
      end

      def transform_transitions(graph, semantics)
        states = graph.nodes.to_h { |node| [node.id, node] }
        graph.edges.filter_map do |transition|
          next unless transition.role == "state_transition"

          transition_hash(transition, states, semantics)
        end
      end

      def transition_hash(transition, states, semantics)
        {
          id: transition_identifier(transition, semantics),
          sources: [state_identifier(states[transition.source_id], semantics)],
          targets: [state_identifier(states[transition.target_id], semantics)],
          labels: transition_labels(transition.label),
          metadata: transition_metadata(transition, semantics),
        }
      end

      def transition_identifier(transition, semantics)
        semantic_value(
          semantics, transition.parent_id, "transition_identifier"
        ) || transition.id
      end

      def transition_metadata(transition, semantics)
        parent_id = transition.parent_id
        {
          trigger: semantic_value(semantics, parent_id, "trigger"),
          guard_condition: semantic_value(
            semantics, parent_id, "guard_condition"
          ),
        }
      end

      def state_identifier(state, semantics)
        return unless state

        semantic_value(semantics, state.id, "original_identifier") || state.id
      end

      def state_labels(state)
        state_texts(state).each_with_index.map do |text, index|
          state_label(text, index)
        end
      end

      def state_label(text, index)
        font_size = index.zero? ? normal_font_size : small_font_size
        dimensions = measure_text(text, font_size: font_size)
        { text: text, width: dimensions[:width], height: dimensions[:height] }
      end

      def transition_labels(label)
        return [] if label.nil? || label.empty?

        label_dims = measure_text(label, font_size: small_font_size)

        [
          {
            text: label,
            width: label_dims[:width],
            height: label_dims[:height],
          },
        ]
      end

      def calculate_state_dimensions(state)
        texts = state_texts(state)
        label_dims = measure_text(
          texts.first || state.id, font_size: normal_font_size
        )
        state_dims = dimensions_for_shape(state, label_dims, texts.drop(1))
        dimensions_with_label(state_dims, label_dims)
      end

      def dimensions_for_shape(state, label_dims, descriptions)
        case state_shape_type(state)
        when "start", "end" then calculate_terminal_dimensions
        when "choice" then calculate_choice_dimensions(label_dims)
        when "fork", "join" then calculate_fork_join_dimensions
        else calculate_normal_state_dimensions(label_dims, descriptions)
        end
      end

      def dimensions_with_label(state_dims, label_dims)
        {
          width: state_dims[:width],
          height: state_dims[:height],
          label_width: label_dims[:width],
          label_height: label_dims[:height],
        }
      end

      # Parsed aliases and descriptions are Mermaid's ordered display text.
      # StateNode's scalar fields remain the fallback for callers that build
      # the model directly.
      def state_texts(state)
        descriptions = Array(state.descriptions).reject(&:empty?)
        return descriptions unless descriptions.empty?

        [state.label, state.description].compact.reject(&:empty?)
      end

      # Mermaid keeps the declared marker type, but displays a marker carrying
      # ANY display text as an ordinary rectangular state. An alias lands in
      # `descriptions`, never in the scalar `description`, so asking the scalar
      # alone left `state C <<choice>>` + `state "Label" as C` drawing a
      # polygon where mmdc 11.12.0 draws two rects, in both declaration orders.
      #
      # "Display text" here means `descriptions` or the scalar `description`,
      # and deliberately NOT the label. A label cannot be used: terminals carry
      # `label: "[*]"` with no descriptions, so keying the shape on the label
      # turns `[*]` into an ordinary state and its 30px circle into a 100px box.
      # Measured — adding a label check reddened "handles start state
      # dimensions", which is the guard that caught it.
      #
      # Nothing is lost by that. No parsed source produces a marker carrying a
      # label but no descriptions: `add_special_state` clears the label, and the
      # one input that sets one — `state C <<choice>>` with `state "L" as C` —
      # fills `descriptions` too, which the first check already catches. Only a
      # directly built model can hold that combination, and it keeps its
      # declared marker type.
      def state_shape_type(state)
        return "normal" unless Array(state.descriptions).reject(&:empty?).empty?
        return "normal" if state.description && !state.description.empty?

        state.state_type
      end

      def calculate_terminal_dimensions
        # Start and end states are small circles
        {
          width: 30,
          height: 30,
        }
      end

      def calculate_choice_dimensions(label_dims)
        # Choice states are diamonds
        size = [label_dims[:width], label_dims[:height]].max + 40
        {
          width: size,
          height: size,
        }
      end

      def calculate_fork_join_dimensions
        # Fork and join are represented as thick bars
        {
          width: 100,
          height: 10,
        }
      end

      def calculate_normal_state_dimensions(label_dims, descriptions)
        dimensions = descriptions.map do |description|
          measure_text(description, font_size: small_font_size)
        end
        width = normal_state_width(label_dims, dimensions)
        height = normal_state_height(label_dims, dimensions)
        { width: [width, 100].max, height: [height, 50].max }
      end

      def normal_state_width(label_dims, descriptions)
        descriptions.map { |item| item[:width] }
          .push(label_dims[:width]).max + 40
      end

      def normal_state_height(label_dims, descriptions)
        label_dims[:height] + 30 +
          descriptions.sum { |item| item[:height] + 10 }
      end

      def label_font_sizes
        { normal: normal_font_size, small: small_font_size }
      end

      def normal_font_size
        valid_font_size(theme.typography&.font_size_normal) || DEFAULT_FONT_SIZE
      end

      def small_font_size
        valid_font_size(theme.typography&.font_size_small) ||
          DEFAULT_SMALL_FONT_SIZE
      end

      def valid_font_size(value)
        value if value.is_a?(Numeric) && value.positive?
      end

      def layout_options(direction)
        build_elk_options(
          algorithm: ALGORITHM_LAYERED,
          direction: direction_to_layout(direction),
          **LAYOUT_SETTINGS,
        )
      end

      def direction_to_layout(direction)
        DIRECTIONS.fetch(direction, DIRECTION_DOWN)
      end
    end
  end
end
