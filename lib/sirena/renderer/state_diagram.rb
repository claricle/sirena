# frozen_string_literal: true

require_relative "base"
require_relative "../layout/state_diagram"

module Sirena
  module Renderer
    # Emits SVG from final, typed state-diagram geometry.
    class StateDiagram < Base
      LAYOUT_SCENE = Layout::StateDiagram::Scene
      private_constant :LAYOUT_SCENE

      # @param scene [Layout::StateDiagram::Scene] final canvas geometry
      # @return [Svg::Document] rendered SVG document
      def render(scene)
        require_typed_scene!(scene)
        svg = create_document(scene)
        render_transitions(scene, svg)
        render_states(scene, svg)
        svg
      end

      protected

      def require_typed_scene!(scene)
        return if scene.is_a?(LAYOUT_SCENE)

        raise ArgumentError, "StateDiagram renderer requires a typed Scene"
      end

      def render_states(scene, svg)
        scene.children.each { |state| render_state(state, svg) }
      end

      def render_state(state, parent)
        parent << state_group(state)
      end

      def state_group(state)
        group = Svg::Group.new.tap { |item| item.id = "state-#{state.id}" }
        group.children << final_state_shape(state)
        state.labels.each do |label|
          group.children << state_label(label)
        end
        state.children.each do |child|
          render_state(child, group)
        end
        group
      end

      def render_transitions(scene, svg)
        scene.edges.each { |edge| render_transition(edge, svg) }
      end

      def render_transition(edge, svg)
        group = Svg::Group.new.tap { |item| item.id = "transition-#{edge.id}" }
        group.children << Svg::Path.new.tap do |path|
          path.d = edge.path
          path.fill = "none"
          path.stroke = theme_color(:edge_stroke)
          path.stroke_width = "2"
          path.marker_end = "url(#arrowhead)"
        end
        if edge.labels.any?
          group.children << transition_label(edge.labels.first)
        end
        svg << group
      end

      def transition_label(label)
        Svg::Text.new.tap do |text|
          text.x = label.x
          text.y = label.y
          text.content = label.text
          text.fill = theme_color(:label_text)
          text.font_family = "Arial, sans-serif"
          text.font_size = formatted_number(label.font_size)
          text.text_anchor = "middle"
        end
      end

      private

      def final_state_shape(state)
        case state.shape_type
        when "start" then start_state_shape(state)
        when "end" then end_state_shape(state)
        when "choice" then choice_state_shape(state)
        when "fork", "join" then fork_join_state_shape(state)
        when "note" then note_state_shape(state)
        else normal_state_shape(state.x, state.y, state.width, state.height)
        end
      end

      def note_state_shape(state)
        normal_state_shape(
          state.x, state.y, state.width, state.height
        ).tap do |rect|
          rect.rx = nil
          rect.ry = nil
          rect.fill = "#fff5ad"
          rect.stroke = "#aaaa33"
          rect.stroke_width = "1"
        end
      end

      def normal_state_shape(x_position, y_position, width, height)
        Svg::Rect.new.tap do |rect|
          rect.x = x_position
          rect.y = y_position
          rect.width = width
          rect.height = height
          rect.rx = 10
          rect.ry = 10
          apply_normal_state_style(rect)
          rect.stroke_width = "2"
        end
      end

      def apply_normal_state_style(rect)
        rect.fill = theme_color(:node_fill)
        rect.stroke = theme_color(:node_stroke)
      end

      def start_state_shape(state)
        Svg::Circle.new.tap do |circle|
          circle.cx = state.center_x
          circle.cy = state.center_y
          circle.r = state.radius
          circle.fill = theme_color(:node_stroke)
          circle.stroke = "none"
        end
      end

      def end_state_shape(state)
        Svg::Group.new.tap do |group|
          group.children << state_circle(state, state.radius, "none", "2")
          group.children << state_circle(
            state, state.inner_radius, theme_color(:node_stroke), nil
          )
        end
      end

      def choice_state_shape(state)
        Svg::Polygon.new.tap do |polygon|
          polygon.points = state.shape_points
          polygon.fill = theme_color(:node_fill)
          polygon.stroke = theme_color(:node_stroke)
          polygon.stroke_width = "2"
        end
      end

      def fork_join_state_shape(state)
        Svg::Rect.new.tap do |rect|
          rect.x = state.x
          rect.y = state.shape_y
          rect.width = state.width
          rect.height = state.shape_height
          rect.fill = theme_color(:node_stroke)
          rect.stroke = "none"
        end
      end

      def state_circle(state, radius, fill, stroke_width)
        Svg::Circle.new.tap do |circle|
          circle.cx = state.center_x
          circle.cy = state.center_y
          circle.r = radius
          circle.fill = fill
          circle.stroke = fill == "none" ? theme_color(:node_stroke) : "none"
          circle.stroke_width = stroke_width
        end
      end

      def state_label(label)
        Svg::Text.new.tap do |text|
          text.x = label.x
          text.y = label.y
          text.content = label.text
          text.fill = theme_color(:label_text)
          text.font_family = "Arial, sans-serif"
          text.font_size = formatted_number(label.font_size)
          text.text_anchor = "middle"
          text.dominant_baseline = "middle"
        end
      end

      def formatted_number(number)
        number.to_i == number ? number.to_i.to_s : number.to_s
      end
    end
  end
end
