# frozen_string_literal: true

require_relative "base"
require_relative "grid"
require_relative "../diagram/state_diagram"

module Sirena
  module Layout
    # Computes final canvas geometry for state diagrams.
    class StateDiagram < Base
      DEFAULT_FONT_SIZE = 14.0
      DEFAULT_SMALL_FONT_SIZE = 12.0

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
          x = state[:x] || 0
          y = state[:y] || 0
          width = state[:width] || 100
          height = state[:height] || 50
          center = center(state)
          radius = [width, height].min / 2
          points = if state_type == "choice"
                     [
                       "#{center[:x]},#{y}",
                       "#{x + width},#{center[:y]}",
                       "#{center[:x]},#{y + height}",
                       "#{x},#{center[:y]}",
                     ].join(" ")
                   end

          {
            x: x, y: y, width: width, height: height,
            center_x: center[:x], center_y: center[:y], radius: radius,
            inner_radius: radius - 5,
            shape_points: points, shape_y: y + (height / 2) - 5,
            shape_height: 10
          }
        end

        def label_geometry(state, label, index, font_sizes)
          center = center(state)
          label_count = (state[:labels] || []).length
          stack_offset = (label_count - 1) * 10
          {
            text: label[:text], width: label[:width], height: label[:height],
            x: center[:x],
            y: center[:y] - stack_offset + (index * 20),
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
          if graph.is_a?(Scene)
            return coordinate(graph.public_send(axis) - 40)
          end

          boxes = graph[:children]
          return axis == :width ? 800 : 600 unless boxes

          position = axis == :width ? :x : :y
          fallback = axis == :width ? 100 : 50
          maximum = boxes.map do |state|
            (state[position] || 0) + (state[axis] || fallback)
          end.max || (axis == :width ? 800 : 600)
          maximum + 60
        end

        private

        def coordinate(number)
          number.to_i == number ? number.to_i : number
        end
      end

      def scene(diagram)
        graph = build_graph(diagram)
        Grid.apply(graph)
        scene_from_graph(graph)
      end

      private

      # Converts a state diagram to a graph structure.
      #
      # @param diagram [Diagram::StateDiagram] the state diagram to transform
      # @return [Hash] elkrb-compatible graph hash
      def build_graph(diagram)
        {
          id: diagram.id || "state_diagram",
          children: transform_states(diagram),
          edges: transform_transitions(diagram),
          layoutOptions: layout_options(diagram),
        }
      end

      def scene_from_graph(graph)
        children = typed_children(graph[:children] || [])
        padding = graph.key?(:children) ? 100 : 40
        width = canvas_width(graph) + padding
        height = canvas_height(graph) + padding

        Scene.new(
          id: graph[:id] || "state_diagram",
          width: width,
          height: height,
          view_box: "0 0 #{width} #{height}",
          children: children,
          edges: typed_edges(
            graph[:edges] || [], children, graph[:children] || []
          ),
        )
      end

      def typed_children(children)
        children.map do |state|
          state_type = state.dig(:metadata, :state_type) || "normal"
          shape_type = state.dig(:metadata, :shape_type) || state_type
          geometry = self.class.shape_geometry(state, shape_type)
          labels = (state[:labels] || []).each_with_index.map do |label, index|
            Label.new(**self.class.label_geometry(
              state, label, index, label_font_sizes
            ))
          end

          Node.new(
            id: state[:id], labels: labels, state_type: state_type,
            shape_type: shape_type, **geometry
          )
        end
      end

      def typed_edges(edges, children, raw_children)
        nodes = children.to_h { |node| [node.id, node] }
        raw_nodes = raw_children.to_h { |node| [node[:id], node] }
        edges.filter_map do |edge|
          source = nodes[edge[:sources]&.first]
          target = nodes[edge[:targets]&.first]
          next unless source && target

          typed_edge(
            edge, source, target, raw_nodes[source.id], raw_nodes[target.id]
          )
        end
      end

      def typed_edge(edge, source, target, raw_source, raw_target)
        sections = typed_sections(edge, raw_source, raw_target)
        label = (edge[:labels] || []).first
        labels = if label
                   [Label.new(**self.class.transition_label_geometry(
                     raw_source, raw_target, label,
                     small_font_size
                   ))]
                 else
                   []
                 end

        Edge.new(
          id: edge[:id], source: source.id, target: target.id,
          sections: sections, labels: labels,
          path: section_path(sections.first),
          trigger: edge.dig(:metadata, :trigger),
          guard_condition: edge.dig(:metadata, :guard_condition)
        )
      end

      def typed_sections(edge, source, target)
        source_point = point(self.class.center(source))
        target_point = point(self.class.center(target))
        sections = edge[:sections]
        unless sections&.any?
          return [Section.new(start_point: source_point,
                              end_point: target_point)]
        end

        sections.map do |section|
          Section.new(
            start_point: point(section[:startPoint]) || source_point,
            end_point: point(section[:endPoint]) || target_point,
            bend_points: (section[:bendPoints] || []).map { |item| point(item) },
          )
        end
      end

      def section_path(section)
        self.class.path_data(
          section.start_point, section.end_point, section.bend_points
        )
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

      def transform_states(diagram)
        diagram.states.map do |state|
          dims = calculate_state_dimensions(state)

          {
            id: state.id,
            width: dims[:width],
            height: dims[:height],
            labels: state_labels(state),
            metadata: {
              state_type: state.state_type,
              shape_type: state_shape_type(state),
              description: state.description,
            },
          }
        end
      end

      def transform_transitions(diagram)
        return [] if diagram.transitions.nil? || diagram.transitions.empty?

        diagram.transitions.map do |transition|
          {
            id: "#{transition.from_id}_to_#{transition.to_id}",
            sources: [transition.from_id],
            targets: [transition.to_id],
            labels: transition_labels(transition),
            metadata: {
              trigger: transition.trigger,
              guard_condition: transition.guard_condition,
            },
          }
        end
      end

      def state_labels(state)
        state_texts(state).each_with_index.map do |text, index|
          text_dims = measure_text(
            text,
            font_size: index.zero? ? normal_font_size : small_font_size,
          )
          {
            text: text,
            width: text_dims[:width],
            height: text_dims[:height],
          }
        end
      end

      def transition_labels(transition)
        label = transition.label
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
        label_text = texts.first || state.id
        label_dims = measure_text(
          label_text,
          font_size: normal_font_size,
        )

        # Adjust dimensions based on state type
        state_dims = case state_shape_type(state)
                     when "start", "end"
                       calculate_terminal_dimensions
                     when "choice"
                       calculate_choice_dimensions(label_dims)
                     when "fork", "join"
                       calculate_fork_join_dimensions
                     else
                       calculate_normal_state_dimensions(
                         label_dims,
                         texts.drop(1),
                       )
                     end

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
        # Normal states are rounded rectangles
        width = label_dims[:width] + 40
        height = label_dims[:height] + 30

        descriptions.each do |description|
          desc_dims = measure_text(
            description,
            font_size: small_font_size,
          )
          height += desc_dims[:height] + 10
          width = [width, desc_dims[:width] + 40].max
        end

        # Minimum dimensions
        width = [width, 100].max
        height = [height, 50].max

        {
          width: width,
          height: height,
        }
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

      def layout_options(diagram)
        # State diagrams use layered algorithm for state machine flow
        # This ensures proper hierarchical layout of states with clear
        # transition paths from start to end states
        build_elk_options(
          algorithm: ALGORITHM_LAYERED,
          direction: direction_to_layout(diagram.direction),
          ElkOptions::NODE_NODE_SPACING => 60,
          ElkOptions::LAYER_SPACING => 60,
          ElkOptions::EDGE_NODE_SPACING => 40,
          ElkOptions::EDGE_EDGE_SPACING => 30,
          # SIMPLE node placement for predictable state flow
          ElkOptions::NODE_PLACEMENT => "SIMPLE",
        )
      end

      def direction_to_layout(direction)
        case direction
        when "TD", "TB"
          DIRECTION_DOWN
        when "LR"
          DIRECTION_RIGHT
        when "RL"
          DIRECTION_LEFT
        when "BT"
          DIRECTION_UP
        else
          DIRECTION_DOWN # Default direction
        end
      end
    end
  end
end
