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

      # Loop drawn when a participant messages itself
      SELF_LOOP_WIDTH = 56
      SELF_LOOP_HEIGHT = 20

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
        style = {
          line: metadata[:line_style] || 'solid',
          head: metadata[:head_style] || 'filled',
          side: metadata[:head_side] || 'target'
        }
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
          style,
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

      def render_arrow(x1, y1, x2, y2, style, group)
        return render_self_message(x1, y1, style, group) if x1 == x2

        span = { x1: x1, y1: y1, x2: x2, y2: y2 }
        ends = head_ends(style)

        group.children << message_line(span, style, ends)
        ends.each { |which| render_head(which, span, style, group) }
      end

      # A participant messaging itself has no horizontal run, so a straight
      # shaft collapses to nothing — `A->A` drew no line and no head at all.
      # Mermaid loops it back to the same lifeline instead.
      def render_self_message(x, y, style, group)
        top = y - (SELF_LOOP_HEIGHT / 2)
        bottom = y + (SELF_LOOP_HEIGHT / 2)
        reach = x + SELF_LOOP_WIDTH

        group.children << Svg::Path.new.tap do |p|
          p.d = "M #{x},#{top} C #{reach},#{top} #{reach},#{bottom} #{x},#{bottom}"
          p.fill = 'none'
          p.stroke = '#000000'
          p.stroke_width = '2'
          p.stroke_dasharray = '5,5' if style[:line] == 'dotted'
        end

        # Each end of the loop carries its own head, so a bidirectional
        # self-message gets one at the top and one at the bottom — mermaid
        # emits both a marker-start and a marker-end for `A<<->>A`.
        head_ends(style).each do |which|
          edge_y = which == :source ? top : bottom
          render_head(:target,
                      { x1: x + ARROW_SIZE, y1: edge_y, x2: x, y2: edge_y },
                      style, group)
        end
      end

      # Which ends of the message carry a marker. Mermaid draws one at the
      # target, one at the source for the reversed spellings, both for its
      # <<->> arrows, and none for the bare -> and -->.
      HEAD_ENDS = {
        'target' => [:target].freeze,
        'source' => [:source].freeze,
        'both' => [:source, :target].freeze
      }.freeze

      def head_ends(style)
        return [] if style[:head] == 'none'

        HEAD_ENDS.fetch(style[:side], HEAD_ENDS['target'])
      end

      # Heads that sit on the line rather than in front of it. Only a
      # filled wedge fills the last few pixels of the shaft, so only it
      # earns an inset. A cross straddles the tip, a stick is one diagonal
      # stroke from it, and the concave chevron of `-)` touches the
      # centreline at its notch rather than its back edge — insetting for
      # that one left the shaft ending at 212 with the notch at 215.2.
      FLUSH_HEADS = %w[cross open stick_top stick_bottom].freeze

      def message_line(span, style, ends)
        # Signed, so a right-to-left message insets towards its own head
        # rather than past it. Unsigned, B<<->>A started its shaft at 228
        # while the head occupied 212 to 220.
        inset = FLUSH_HEADS.include?(style[:head]) ? 0 : ARROW_SIZE
        inset *= (span[:x2] <=> span[:x1])

        Svg::Line.new.tap do |l|
          l.x1 = span[:x1] + (ends.include?(:source) ? inset : 0)
          l.y1 = span[:y1]
          l.x2 = span[:x2] - (ends.include?(:target) ? inset : 0)
          l.y2 = span[:y2]
          l.stroke = '#000000'
          l.stroke_width = '2'
          l.stroke_dasharray = '5,5' if style[:line] == 'dotted'
        end
      end

      def render_head(which, span, style, group)
        tip_x, tip_y, from_x = if which == :target
                                 span.values_at(:x2, :y2, :x1)
                               else
                                 span.values_at(:x1, :y1, :x2)
                               end

        # Every mermaid marker is `orient="auto-start-reverse"`, so a head
        # is rotated to face the way it points — and rotating it swaps its
        # top and bottom halves. What decides the flip is the direction
        # from the shaft to the tip, not which end of the line it sits on:
        # keying on the end drew `B/|-A` and every other right-to-left
        # message as the mirror of what mmdc renders.
        side = tip_x <=> from_x

        case style[:head]
        when 'cross' then render_cross(tip_x, tip_y, group)
        when 'open' then render_chevron(from_x, tip_x, tip_y, group)
        when 'half_bottom'
          render_half_head(from_x, tip_x, tip_y, side, group)
        when 'half_top'
          render_half_head(from_x, tip_x, tip_y, -side, group)
        when 'stick_bottom'
          render_stick_head(from_x, tip_x, tip_y, side, group)
        when 'stick_top'
          render_stick_head(from_x, tip_x, tip_y, -side, group)
        else render_filled_arrowhead(from_x, tip_y, tip_x, tip_y, group)
        end
      end

      # The stick head is one stroke, not a filled wedge: mermaid's marker
      # is `M 0 0 L 7 7` with `fill="none"`. Drawing it as a polygon would
      # have made `-//` indistinguishable from `-|/`.
      def render_stick_head(from_x, tip_x, tip_y, side, group)
        direction = tip_x >= from_x ? 1 : -1

        group.children << Svg::Line.new.tap do |l|
          l.x1 = tip_x
          l.y1 = tip_y
          l.x2 = tip_x - (direction * ARROW_SIZE)
          l.y2 = tip_y + (side * ARROW_SIZE / 2)
          l.stroke = '#000000'
          l.stroke_width = '2'
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

      # The -|/ and -|\ arrows draw only one barb, below the line or above
      # it — mermaid's solidBottomArrowHead and solidTopArrowHead markers.
      #
      # @param side [Integer] 1 for the barb below the line, -1 for above
      def render_half_head(from_x, tip_x, tip_y, side, group)
        direction = tip_x >= from_x ? 1 : -1
        back = tip_x - (direction * ARROW_SIZE)

        polygon = Svg::Polygon.new.tap do |p|
          p.points = [
            "#{tip_x},#{tip_y}",
            "#{back},#{tip_y + (side * ARROW_SIZE / 2)}",
            "#{back},#{tip_y}"
          ].join(' ')
          p.fill = '#000000'
          p.stroke = '#000000'
        end
        group.children << polygon
      end

      # Mermaid draws the -) and --) arrows with a filled, concave head
      # (its `filled-head` marker, path "M 18,7 L9,13 L14,7 L9,1 Z"), not
      # the two open strokes this renderer drew for them before.
      def render_chevron(from_x, tip_x, tip_y, group)
        direction = tip_x >= from_x ? 1 : -1
        back = tip_x - (direction * ARROW_SIZE)
        notch = tip_x - (direction * ARROW_SIZE * 0.6)

        polygon = Svg::Polygon.new.tap do |p|
          p.points = [
            "#{tip_x},#{tip_y}",
            "#{back},#{tip_y - ARROW_SIZE / 2}",
            "#{notch},#{tip_y}",
            "#{back},#{tip_y + ARROW_SIZE / 2}"
          ].join(' ')
          p.fill = '#000000'
          p.stroke = '#000000'
        end
        group.children << polygon
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
        # Position label above the arrow. A self-message needs more room:
        # its loop reaches half its height above y, so the ordinary 10px
        # put the text baseline exactly on the loop's top edge.
        label_x = (x1 + x2) / 2
        label_y = y - (x1 == x2 ? (SELF_LOOP_HEIGHT / 2) + 10 : 10)

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
