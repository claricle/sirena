# frozen_string_literal: true

require_relative 'base'

module Sirena
  module Renderer
    # State diagram renderer for converting graphs to SVG.
    #
    # Converts a laid-out graph structure (with computed positions) into
    # SVG using the Svg builder classes. Handles different state types,
    # transition routing, and label positioning.
    #
    # @example Render a state diagram
    #   renderer = StateDiagramRenderer.new
    #   svg = renderer.render(laid_out_graph)
    class StateDiagramRenderer < Base
      # Renders a laid-out graph to SVG.
      #
      # @param graph [Hash] laid-out graph with state positions
      # @return [Svg::Document] the rendered SVG document
      def render(graph)
        svg = create_document(graph)

        # Render transitions first (so they appear under states)
        render_transitions(graph, svg) if graph[:edges]

        # Render states
        render_states(graph, svg) if graph[:children]

        svg
      end

      protected

      def calculate_width(graph)
        return 800 unless graph[:children]

        max_x = graph[:children].map do |state|
          (state[:x] || 0) + (state[:width] || 100)
        end.max || 800

        max_x + 60 # Add padding
      end

      def calculate_height(graph)
        return 600 unless graph[:children]

        max_y = graph[:children].map do |state|
          (state[:y] || 0) + (state[:height] || 50)
        end.max || 600

        max_y + 60 # Add padding
      end

      def render_states(graph, svg)
        graph[:children].each do |state|
          render_state(state, svg)
        end
      end

      def render_state(state, svg)
        state_type = state.dig(:metadata, :state_type) || 'normal'

        # Create group for state and its label
        group = Svg::Group.new.tap do |g|
          g.id = "state-#{state[:id]}"
        end

        # Render state shape based on type
        shape_element = create_state_shape(state, state_type)
        group.children << shape_element if shape_element

        # Render state label
        if state[:labels] && !state[:labels].empty?
          state[:labels].each_with_index do |label, index|
            text_element = create_state_label(state, label, index)
            group.children << text_element if text_element
          end
        end

        svg << group
      end

      def create_state_shape(state, state_type)
        x = state[:x] || 0
        y = state[:y] || 0
        width = state[:width] || 100
        height = state[:height] || 50

        case state_type
        when 'start'
          create_start_state(x, y, width, height)
        when 'end'
          create_end_state(x, y, width, height)
        when 'choice'
          create_choice_state(x, y, width, height)
        when 'fork', 'join'
          create_fork_join_state(x, y, width, height)
        else
          create_normal_state(x, y, width, height)
        end
      end

      def create_normal_state(x, y, width, height)
        Svg::Rect.new.tap do |rect|
          rect.x = x
          rect.y = y
          rect.width = width
          rect.height = height
          rect.rx = 10
          rect.ry = 10
          rect.fill = '#ffffff'
          rect.stroke = '#000000'
          rect.stroke_width = '2'
        end
      end

      def create_start_state(x, y, width, height)
        # Start state is a filled circle
        cx = x + width / 2
        cy = y + height / 2
        r = [width, height].min / 2

        Svg::Circle.new.tap do |circle|
          circle.cx = cx
          circle.cy = cy
          circle.r = r
          circle.fill = '#000000'
          circle.stroke = 'none'
        end
      end

      def create_end_state(x, y, width, height)
        # End state is a double circle (outer hollow, inner filled)
        cx = x + width / 2
        cy = y + height / 2
        r = [width, height].min / 2

        group = Svg::Group.new

        # Outer circle
        outer = Svg::Circle.new.tap do |circle|
          circle.cx = cx
          circle.cy = cy
          circle.r = r
          circle.fill = 'none'
          circle.stroke = '#000000'
          circle.stroke_width = '2'
        end
        group.children << outer

        # Inner filled circle
        inner = Svg::Circle.new.tap do |circle|
          circle.cx = cx
          circle.cy = cy
          circle.r = r - 5
          circle.fill = '#000000'
          circle.stroke = 'none'
        end
        group.children << inner

        group
      end

      def create_choice_state(x, y, width, height)
        # Choice state is a diamond
        cx = x + width / 2
        cy = y + height / 2

        points = [
          "#{cx},#{y}",
          "#{x + width},#{cy}",
          "#{cx},#{y + height}",
          "#{x},#{cy}"
        ].join(' ')

        Svg::Polygon.new.tap do |polygon|
          polygon.points = points
          polygon.fill = '#ffffff'
          polygon.stroke = '#000000'
          polygon.stroke_width = '2'
        end
      end

      def create_fork_join_state(x, y, width, height)
        # Fork/Join is a thick horizontal bar
        Svg::Rect.new.tap do |rect|
          rect.x = x
          rect.y = y + height / 2 - 5
          rect.width = width
          rect.height = 10
          rect.fill = '#000000'
          rect.stroke = 'none'
        end
      end

      def create_state_label(state, label, index)
        x = state[:x] || 0
        y = state[:y] || 0
        width = state[:width] || 100
        height = state[:height] || 50

        # Center text in state
        text_x = x + width / 2
        # Adjust y position based on label index (for multiple labels)
        text_y = if index.zero?
                   y + height / 2
                 else
                   y + height / 2 + (index * 20)
                 end

        font_size = index.zero? ? '14' : '12'

        Svg::Text.new.tap do |text|
          text.x = text_x
          text.y = text_y
          text.content = label[:text]
          text.fill = '#000000'
          text.font_family = 'Arial, sans-serif'
          text.font_size = font_size
          text.text_anchor = 'middle'
          text.dominant_baseline = 'middle'
        end
      end

      def render_transitions(graph, svg)
        graph[:edges].each do |transition|
          render_transition(transition, graph, svg)
        end
      end

      def render_transition(transition, graph, svg)
        source = find_state(graph, transition[:sources]&.first)
        target = find_state(graph, transition[:targets]&.first)

        return unless source && target

        # Calculate transition path
        path_data = calculate_transition_path(source, target, transition)

        # Create path element
        path = Svg::Path.new.tap do |p|
          p.d = path_data
          p.fill = 'none'
          p.stroke = '#000000'
          p.stroke_width = '2'
          p.marker_end = 'url(#arrowhead)'
        end

        # Create group for transition and label
        group = Svg::Group.new.tap do |g|
          g.id = "transition-#{transition[:id]}"
        end

        group.children << path

        # Render transition label if present
        if transition[:labels] && !transition[:labels].empty?
          label = transition[:labels].first
          text = create_transition_label(source, target, label)
          group.children << text if text
        end

        svg << group
      end

      def find_state(graph, state_id)
        return nil unless graph[:children] && state_id

        graph[:children].find { |s| s[:id] == state_id }
      end

      def calculate_transition_path(source, target, transition)
        # Calculate center points
        sx = (source[:x] || 0) + (source[:width] || 100) / 2
        sy = (source[:y] || 0) + (source[:height] || 50) / 2
        tx = (target[:x] || 0) + (target[:width] || 100) / 2
        ty = (target[:y] || 0) + (target[:height] || 50) / 2

        # Use sections if available (from elkrb layout)
        if transition[:sections] && !transition[:sections].empty?
          section = transition[:sections].first
          if section[:bendPoints] && !section[:bendPoints].empty?
            return create_path_with_bends(
              sx, sy, tx, ty,
              section[:bendPoints]
            )
          end
        end

        # Simple straight line path
        "M #{sx} #{sy} L #{tx} #{ty}"
      end

      def create_path_with_bends(sx, sy, tx, ty, bend_points)
        path_parts = ["M #{sx} #{sy}"]

        bend_points.each do |point|
          path_parts << "L #{point[:x]} #{point[:y]}"
        end

        path_parts << "L #{tx} #{ty}"
        path_parts.join(' ')
      end

      def create_transition_label(source, target, label)
        # Position label at midpoint of transition
        sx = (source[:x] || 0) + (source[:width] || 100) / 2
        sy = (source[:y] || 0) + (source[:height] || 50) / 2
        tx = (target[:x] || 0) + (target[:width] || 100) / 2
        ty = (target[:y] || 0) + (target[:height] || 50) / 2

        mid_x = (sx + tx) / 2
        mid_y = (sy + ty) / 2

        Svg::Text.new.tap do |text|
          text.x = mid_x
          text.y = mid_y - 8 # Offset slightly above line
          text.content = label[:text]
          text.fill = '#000000'
          text.font_family = 'Arial, sans-serif'
          text.font_size = '12'
          text.text_anchor = 'middle'
        end
      end
    end
  end
end
