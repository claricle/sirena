# frozen_string_literal: true

require_relative "base"
require_relative "../layout/state_diagram"

module Sirena
  module Renderer
    # Emits SVG from final, typed state-diagram geometry.
    class StateDiagram < Base
      # @param scene [Layout::StateDiagram::Scene] final canvas geometry
      # @return [Svg::Document] rendered SVG document
      def render(scene)
        if scene.is_a?(Hash)
          scene = Layout::StateDiagram.from_graph(scene, theme: theme)
        end
        svg = create_document(scene)
        render_transitions(scene, svg)
        render_states(scene, svg)
        svg
      end

      protected

      def calculate_width(graph)
        Layout::StateDiagram.renderer_extent(graph, :width)
      end

      def calculate_height(graph)
        Layout::StateDiagram.renderer_extent(graph, :height)
      end

      def render_states(graph, svg)
        children_for(graph).each { |state| render_state(state, svg) }
      end

      def render_state(state, svg)
        typed = typed_state(state)
        group = Svg::Group.new.tap { |item| item.id = "state-#{typed.id}" }
        group.children << create_state_shape(typed, typed.shape_type)
        typed.labels.each_with_index do |label, index|
          group.children << create_state_label(typed, label, index)
        end
        svg << group
      end

      def render_transitions(graph, svg)
        edges_for(graph).each do |transition|
          render_transition(transition, graph, svg)
        end
      end

      def render_transition(transition, graph, svg)
        edge = typed_transition(transition, graph)
        return unless edge

        source = find_state(graph, edge.source)
        target = find_state(graph, edge.target)

        group = Svg::Group.new.tap { |item| item.id = "transition-#{edge.id}" }
        group.children << Svg::Path.new.tap do |path|
          path.d = calculate_transition_path(source, target, edge)
          path.fill = "none"
          path.stroke = "#000000"
          path.stroke_width = "2"
          path.marker_end = "url(#arrowhead)"
        end
        if edge.labels.any?
          group.children << create_transition_label(
            source, target, edge.labels.first
          )
        end
        svg << group
      end

      def transition_label(label)
        Svg::Text.new.tap do |text|
          text.x = label.x
          text.y = label.y
          text.content = label.text
          text.fill = "#000000"
          text.font_family = "Arial, sans-serif"
          text.font_size = formatted_number(label.font_size)
          text.text_anchor = "middle"
        end
      end

      def find_state(graph, state_id)
        return unless state_id

        children_for(graph).find do |state|
          if state.is_a?(Layout::StateDiagram::Node)
            state.id == state_id
          else
            state[:id] == state_id
          end
        end
      end

      def calculate_transition_path(source, target, transition)
        if transition.is_a?(Layout::StateDiagram::Edge)
          section = transition.sections.first
          return create_path_with_bends(
            section.start_point.x, section.start_point.y,
            section.end_point.x, section.end_point.y, section.bend_points
          )
        end

        source_point = point(Layout::StateDiagram.center(source))
        target_point = point(Layout::StateDiagram.center(target))
        bends = transition.dig(:sections, 0, :bendPoints) || []
        create_path_with_bends(
          source_point.x, source_point.y, target_point.x, target_point.y, bends
        )
      end

      def create_path_with_bends(sx, sy, tx, ty, bend_points)
        Layout::StateDiagram.path_data(
          point(x: sx, y: sy), point(x: tx, y: ty),
          bend_points.map { |item| point(item) }
        )
      end

      def create_transition_label(source, target, label)
        return transition_label(label) if label.is_a?(Layout::StateDiagram::Label)

        geometry = Layout::StateDiagram.transition_label_geometry(
          source, target, label, small_font_size
        )
        transition_label(Layout::StateDiagram::Label.new(**geometry))
      end

      def create_state_shape(state, state_type)
        typed = typed_state(state, state_type)
        @current_state = typed
        case state_type
        when "start"
          create_start_state(typed.x, typed.y, typed.width, typed.height)
        when "end"
          create_end_state(typed.x, typed.y, typed.width, typed.height)
        when "choice"
          create_choice_state(typed.x, typed.y, typed.width, typed.height)
        when "fork", "join"
          create_fork_join_state(typed.x, typed.y, typed.width, typed.height)
        else
          create_normal_state(typed.x, typed.y, typed.width, typed.height)
        end
      ensure
        @current_state = nil
      end

      def create_normal_state(x, y, width, height)
        Svg::Rect.new.tap do |rect|
          rect.x = x
          rect.y = y
          rect.width = width
          rect.height = height
          rect.rx = 10
          rect.ry = 10
          rect.fill = "#ffffff"
          rect.stroke = "#000000"
          rect.stroke_width = "2"
        end
      end

      def create_start_state(x, y, width, height)
        state = current_state_or(x, y, width, height, "start")
        Svg::Circle.new.tap do |circle|
          circle.cx = state.center_x
          circle.cy = state.center_y
          circle.r = state.radius
          circle.fill = "#000000"
          circle.stroke = "none"
        end
      end

      def create_end_state(x, y, width, height)
        state = current_state_or(x, y, width, height, "end")
        Svg::Group.new.tap do |group|
          group.children << state_circle(state, state.radius, "none", "2")
          group.children << state_circle(
            state, state.inner_radius, "#000000", nil
          )
        end
      end

      def create_choice_state(x, y, width, height)
        state = current_state_or(x, y, width, height, "choice")
        Svg::Polygon.new.tap do |polygon|
          polygon.points = state.shape_points
          polygon.fill = "#ffffff"
          polygon.stroke = "#000000"
          polygon.stroke_width = "2"
        end
      end

      def create_fork_join_state(x, y, width, height)
        state = current_state_or(x, y, width, height, "fork")
        Svg::Rect.new.tap do |rect|
          rect.x = state.x
          rect.y = state.shape_y
          rect.width = state.width
          rect.height = state.shape_height
          rect.fill = "#000000"
          rect.stroke = "none"
        end
      end

      def create_state_label(state, label, index)
        return state_label(label) if label.is_a?(Layout::StateDiagram::Label)

        geometry = Layout::StateDiagram.label_geometry(
          state, label, index,
          { normal: normal_font_size, small: small_font_size }
        )
        state_label(Layout::StateDiagram::Label.new(**geometry))
      end

      private

      def state_circle(state, radius, fill, stroke_width)
        Svg::Circle.new.tap do |circle|
          circle.cx = state.center_x
          circle.cy = state.center_y
          circle.r = radius
          circle.fill = fill
          circle.stroke = fill == "none" ? "#000000" : "none"
          circle.stroke_width = stroke_width
        end
      end

      def state_label(label)
        Svg::Text.new.tap do |text|
          text.x = label.x
          text.y = label.y
          text.content = label.text
          text.fill = "#000000"
          text.font_family = "Arial, sans-serif"
          text.font_size = formatted_number(label.font_size)
          text.text_anchor = "middle"
          text.dominant_baseline = "middle"
        end
      end

      def typed_state(state, shape_type = nil)
        return state if state.is_a?(Layout::StateDiagram::Node)

        resolved_type = shape_type || state.dig(:metadata, :shape_type) ||
          state.dig(:metadata, :state_type) || "normal"
        geometry = Layout::StateDiagram.shape_geometry(state, resolved_type)
        labels = (state[:labels] || []).each_with_index.map do |label, index|
          values = Layout::StateDiagram.label_geometry(
            state, label, index,
            { normal: normal_font_size, small: small_font_size }
          )
          Layout::StateDiagram::Label.new(**values)
        end
        Layout::StateDiagram::Node.new(
          id: state[:id], state_type: state.dig(:metadata, :state_type),
          shape_type: resolved_type, labels: labels, **geometry
        )
      end

      def typed_transition(transition, graph)
        return transition if transition.is_a?(Layout::StateDiagram::Edge)

        source = find_state(graph, transition[:sources]&.first)
        target = find_state(graph, transition[:targets]&.first)
        return unless source && target

        scene = Layout::StateDiagram.from_graph(
          { id: "state_diagram", children: [source, target],
            edges: [transition] },
          theme: theme,
        )
        scene.edges.first
      end

      def current_state_or(x_position, y_position, width, height, shape_type)
        return @current_state if @current_state

        values = {
          x: x_position, y: y_position, width: width, height: height
        }
        Layout::StateDiagram::Node.new(
          shape_type: shape_type,
          **Layout::StateDiagram.shape_geometry(values, shape_type),
        )
      end

      def point(value)
        return value if value.is_a?(Layout::StateDiagram::Point)

        Layout::StateDiagram::Point.new(x: value[:x], y: value[:y])
      end

      def children_for(graph)
        return graph.children if graph.is_a?(Layout::StateDiagram::Scene)

        graph[:children] || []
      end

      def edges_for(graph)
        return graph.edges if graph.is_a?(Layout::StateDiagram::Scene)

        graph[:edges] || []
      end

      def normal_font_size
        theme_typography(:font_size_normal) || Layout::StateDiagram::DEFAULT_FONT_SIZE
      end

      def small_font_size
        theme_typography(:font_size_small) ||
          Layout::StateDiagram::DEFAULT_SMALL_FONT_SIZE
      end

      def formatted_number(number)
        number.to_i == number ? number.to_i.to_s : number.to_s
      end
    end
  end
end
