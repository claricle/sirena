# frozen_string_literal: true

require_relative 'base'

module Sirena
  module Renderer
    # Sequence renderer for converting graphs to SVG.
    #
    # Converts a laid-out graph structure (with computed positions) into
    # SVG using the Svg builder classes. Handles participants, lifelines,
    # messages with various arrow types, and notes.
    #
    # @example Render a sequence diagram
    #   renderer = SequenceRenderer.new
    #   svg = renderer.render(laid_out_graph)
    class SequenceRenderer < Base
      # Participant box dimensions
      PARTICIPANT_WIDTH = 120
      PARTICIPANT_HEIGHT = 40
      PARTICIPANT_MARGIN = 20

      # Lifeline styling
      LIFELINE_DASH = '5,5'

      # Message arrow dimensions
      ARROW_SIZE = 8
      MESSAGE_Y_OFFSET = 60

      # Renders a laid-out graph to SVG.
      #
      # @param graph [Hash] laid-out graph with node positions
      # @return [Svg::Document] the rendered SVG document
      def render(graph)
        svg = create_document(graph)

        metadata = graph[:metadata] || {}
        metadata[:participants] || []
        message_count = metadata[:message_count] || 0

        # Calculate positions
        participant_positions = calculate_participant_positions(
          graph[:children]
        )

        # Render lifelines first (under everything)
        render_lifelines(participant_positions, message_count, svg)

        # Render messages
        render_messages(graph, participant_positions, svg) if graph[:edges]

        # Render participants (on top)
        render_participants(graph[:children], participant_positions, svg)

        # Render notes if present
        render_notes(metadata[:notes], participant_positions, svg) if
          metadata[:notes]

        svg
      end

      protected

      def calculate_width(graph)
        return 800 unless graph[:children]

        # Calculate width based on participant count and spacing
        participant_count = graph[:children].length
        total_width = participant_count * (PARTICIPANT_WIDTH +
                                           PARTICIPANT_MARGIN)

        total_width + 80 # Add padding
      end

      def calculate_height(graph)
        metadata = graph[:metadata] || {}
        message_count = metadata[:message_count] || 0

        # Base height: participants + messages + padding
        PARTICIPANT_HEIGHT * 2 + # Top and bottom participants
          (message_count * MESSAGE_Y_OFFSET) +
          100 # Padding
      end

      def calculate_participant_positions(participants)
        positions = {}
        participants.each_with_index do |participant, index|
          x = PARTICIPANT_MARGIN + (index * (PARTICIPANT_WIDTH +
                                              PARTICIPANT_MARGIN))
          y = PARTICIPANT_MARGIN

          positions[participant[:id]] = {
            x: x,
            y: y,
            center_x: x + PARTICIPANT_WIDTH / 2
          }
        end
        positions
      end

      def render_participants(participants, positions, svg)
        participants.each do |participant|
          render_participant(participant, positions, svg)
        end
      end

      def render_participant(participant, positions, svg)
        pos = positions[participant[:id]]
        return unless pos

        metadata = participant[:metadata] || {}
        actor_type = metadata[:actor_type] || 'participant'

        # Create group for participant
        group = Svg::Group.new.tap do |g|
          g.id = "participant-#{participant[:id]}"
        end

        # Render participant shape
        if actor_type == 'actor'
          render_actor(pos[:x], pos[:y], participant, group)
        else
          render_participant_box(pos[:x], pos[:y], participant, group)
        end

        svg << group
      end

      def render_participant_box(x, y, participant, group)
        # Participant box
        rect = Svg::Rect.new.tap do |r|
          r.x = x
          r.y = y
          r.width = PARTICIPANT_WIDTH
          r.height = PARTICIPANT_HEIGHT
          r.fill = '#ffffff'
          r.stroke = '#000000'
          r.stroke_width = '2'
          r.rx = 5
          r.ry = 5
        end
        group.children << rect

        # Participant label
        label = participant[:labels]&.first
        return unless label

        text = Svg::Text.new.tap do |t|
          t.x = x + PARTICIPANT_WIDTH / 2
          t.y = y + PARTICIPANT_HEIGHT / 2
          t.content = label[:text]
          t.fill = '#000000'
          t.font_family = 'Arial, sans-serif'
          t.font_size = '14'
          t.text_anchor = 'middle'
          t.dominant_baseline = 'middle'
        end
        group.children << text
      end

      def render_actor(x, y, _participant, group)
        # Simple actor representation (stick figure)
        center_x = x + PARTICIPANT_WIDTH / 2
        head_y = y + 10

        # Head
        circle = Svg::Circle.new.tap do |c|
          c.cx = center_x
          c.cy = head_y
          c.r = 8
          c.fill = 'none'
          c.stroke = '#000000'
          c.stroke_width = '2'
        end
        group.children << circle

        # Body and limbs
        body_top = head_y + 8
        body_bottom = body_top + 15

        # Body line
        body = Svg::Line.new.tap do |l|
          l.x1 = center_x
          l.y1 = body_top
          l.x2 = center_x
          l.y2 = body_bottom
          l.stroke = '#000000'
          l.stroke_width = '2'
        end
        group.children << body

        # Arms
        arms = Svg::Line.new.tap do |l|
          l.x1 = center_x - 10
          l.y1 = body_top + 7
          l.x2 = center_x + 10
          l.y2 = body_top + 7
          l.stroke = '#000000'
          l.stroke_width = '2'
        end
        group.children << arms

        # Legs
        left_leg = Svg::Line.new.tap do |l|
          l.x1 = center_x
          l.y1 = body_bottom
          l.x2 = center_x - 8
          l.y2 = body_bottom + 10
          l.stroke = '#000000'
          l.stroke_width = '2'
        end
        group.children << left_leg

        right_leg = Svg::Line.new.tap do |l|
          l.x1 = center_x
          l.y1 = body_bottom
          l.x2 = center_x + 8
          l.y2 = body_bottom + 10
          l.stroke = '#000000'
          l.stroke_width = '2'
        end
        group.children << right_leg
      end

      def render_lifelines(positions, message_count, svg)
        lifeline_length = (message_count * MESSAGE_Y_OFFSET) + 100

        positions.each_value do |pos|
          line = Svg::Line.new.tap do |l|
            l.x1 = pos[:center_x]
            l.y1 = PARTICIPANT_MARGIN + PARTICIPANT_HEIGHT
            l.x2 = pos[:center_x]
            l.y2 = PARTICIPANT_MARGIN + PARTICIPANT_HEIGHT + lifeline_length
            l.stroke = '#000000'
            l.stroke_width = '1'
            l.stroke_dasharray = LIFELINE_DASH
          end
          svg << line
        end
      end

      def render_messages(graph, positions, svg)
        graph[:edges].each_with_index do |edge, index|
          render_message(edge, positions, index, svg)
        end
      end

      def render_message(edge, positions, index, svg)
        metadata = edge[:metadata] || {}
        arrow_type = metadata[:arrow_type] || 'solid'
        message_text = metadata[:message_text]

        source_id = edge[:sources]&.first
        target_id = edge[:targets]&.first

        return unless source_id && target_id

        source_pos = positions[source_id]
        target_pos = positions[target_id]

        return unless source_pos && target_pos

        # Calculate message Y position
        message_y = PARTICIPANT_MARGIN + PARTICIPANT_HEIGHT +
                    ((index + 1) * MESSAGE_Y_OFFSET)

        # Create group for message
        group = Svg::Group.new.tap do |g|
          g.id = "message-#{index}"
        end

        # Render arrow
        render_arrow(
          source_pos[:center_x],
          message_y,
          target_pos[:center_x],
          message_y,
          arrow_type,
          group
        )

        # Render message label if present
        if message_text && !message_text.empty?
          render_message_label(
            source_pos[:center_x],
            target_pos[:center_x],
            message_y,
            message_text,
            group
          )
        end

        svg << group
      end

      def render_arrow(x1, y1, x2, y2, arrow_type, group)
        # Determine line style
        stroke_dasharray = arrow_type.include?('dotted') ? '5,5' : nil
        has_arrowhead = !arrow_type.include?('cross')

        # Draw line
        line = Svg::Line.new.tap do |l|
          l.x1 = x1
          l.y1 = y1
          l.x2 = x2 - (has_arrowhead ? ARROW_SIZE : 0)
          l.y2 = y2
          l.stroke = '#000000'
          l.stroke_width = '2'
          l.stroke_dasharray = stroke_dasharray if stroke_dasharray
        end
        group.children << line

        # Draw arrowhead or cross
        if arrow_type.include?('cross')
          render_cross(x2, y2, group)
        elsif arrow_type.include?('async')
          render_open_arrowhead(x1, y1, x2, y2, group)
        else
          render_filled_arrowhead(x1, y1, x2, y2, group)
        end
      end

      def render_filled_arrowhead(x1, _y1, x2, y2, group)
        # Calculate arrow direction
        dx = x2 - x1
        angle = dx.positive? ? 0 : 180

        # Arrowhead points
        points = if angle.zero?
                   [
                     "#{x2},#{y2}",
                     "#{x2 - ARROW_SIZE},#{y2 - ARROW_SIZE / 2}",
                     "#{x2 - ARROW_SIZE},#{y2 + ARROW_SIZE / 2}"
                   ].join(' ')
                 else
                   [
                     "#{x2},#{y2}",
                     "#{x2 + ARROW_SIZE},#{y2 - ARROW_SIZE / 2}",
                     "#{x2 + ARROW_SIZE},#{y2 + ARROW_SIZE / 2}"
                   ].join(' ')
                 end

        polygon = Svg::Polygon.new.tap do |p|
          p.points = points
          p.fill = '#000000'
          p.stroke = '#000000'
        end
        group.children << polygon
      end

      def render_open_arrowhead(x1, _y1, x2, y2, group)
        dx = x2 - x1
        direction = dx.positive? ? 1 : -1

        # Open arrowhead (two lines)
        line1 = Svg::Line.new.tap do |l|
          l.x1 = x2
          l.y1 = y2
          l.x2 = x2 - (direction * ARROW_SIZE)
          l.y2 = y2 - ARROW_SIZE / 2
          l.stroke = '#000000'
          l.stroke_width = '2'
        end
        group.children << line1

        line2 = Svg::Line.new.tap do |l|
          l.x1 = x2
          l.y1 = y2
          l.x2 = x2 - (direction * ARROW_SIZE)
          l.y2 = y2 + ARROW_SIZE / 2
          l.stroke = '#000000'
          l.stroke_width = '2'
        end
        group.children << line2
      end

      def render_cross(x, y, group)
        size = ARROW_SIZE / 2

        # Diagonal cross
        line1 = Svg::Line.new.tap do |l|
          l.x1 = x - size
          l.y1 = y - size
          l.x2 = x + size
          l.y2 = y + size
          l.stroke = '#000000'
          l.stroke_width = '2'
        end
        group.children << line1

        line2 = Svg::Line.new.tap do |l|
          l.x1 = x - size
          l.y1 = y + size
          l.x2 = x + size
          l.y2 = y - size
          l.stroke = '#000000'
          l.stroke_width = '2'
        end
        group.children << line2
      end

      def render_message_label(x1, x2, y, text, group)
        # Position label above the arrow
        label_x = (x1 + x2) / 2
        label_y = y - 10

        text_element = Svg::Text.new.tap do |t|
          t.x = label_x
          t.y = label_y
          t.content = text
          t.fill = '#000000'
          t.font_family = 'Arial, sans-serif'
          t.font_size = '12'
          t.text_anchor = 'middle'
        end
        group.children << text_element
      end

      def render_notes(_notes, _positions, _svg)
        # Note rendering can be implemented if needed
        # For now, this is a placeholder
      end
    end
  end
end
