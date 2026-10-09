# frozen_string_literal: true

require_relative "base"
require_relative "../layout/sequence"

module Sirena
  module Renderer
    # Emits SVG from final, typed sequence-diagram geometry.
    class Sequence < Base
      PARTICIPANT_WIDTH = 120
      PARTICIPANT_HEIGHT = 40
      PARTICIPANT_MARGIN = 20
      LIFELINE_DASH = "5,5"
      ARROW_SIZE = 8
      MESSAGE_Y_OFFSET = 60
      SELF_LOOP_WIDTH = 56
      SELF_LOOP_HEIGHT = 20

      HEAD_ENDS = {
        "target" => [:target].freeze,
        "source" => [:source].freeze,
        "both" => %i[source target].freeze,
      }.freeze
      FLUSH_HEADS = %w[cross open stick_top stick_bottom].freeze

      # @param scene [Layout::Sequence::Scene] final canvas geometry
      # @return [Svg::Document] rendered SVG document
      def render(scene)
        svg = create_document(scene)
        positions = calculate_participant_positions(scene.participants)
        render_lifelines(positions, scene.messages.length, svg)
        render_messages(scene, positions, svg)
        render_participants(scene.participants, positions, svg)
        svg
      end

      protected

      def create_document(graph, padding: 20, overflow: nil)
        width = calculate_width(graph) + (padding * 2)
        height = calculate_height(graph) + (padding * 2)
        Svg::Document.new.tap do |svg|
          svg.width = width
          svg.height = height
          svg.view_box = "0 0 #{number_string(width)} #{number_string(height)}"
          svg.overflow = overflow
        end
      end

      def draw_lifeline(lifeline, svg)
        svg << svg_line(lifeline, stroke_width: "1", dash: LIFELINE_DASH)
      end

      def draw_message(message, svg)
        group = Svg::Group.new.tap { |item| item.id = message.id }
        group.children << message_path(message) if message.loop_path
        if message.shaft
          group.children << svg_line(
            message.shaft, stroke_width: "2",
                           dash: message.line_style == "dotted" ? "5,5" : nil
          )
        end
        message.heads.each { |head| group.children.concat(head_elements(head)) }
        group.children << message_label(message.label) if message.label
        svg << group
      end

      def message_path(message)
        Svg::Path.new.tap do |path|
          path.d = message.loop_path
          path.fill = "none"
          path.stroke = "#000000"
          path.stroke_width = "2"
          path.stroke_dasharray = "5,5" if message.line_style == "dotted"
        end
      end

      def head_elements(head)
        return [polygon_head(head)] if head.shape == "polygon"

        head.lines.map { |geometry| head_line(geometry) }
      end

      def polygon_head(head)
        Svg::Polygon.new.tap do |polygon|
          polygon.points = head.points
          polygon.fill = "#000000"
          polygon.stroke = "#000000"
        end
      end

      def head_line(geometry)
        svg_line(geometry, stroke_width: "2")
      end

      def message_label(label)
        Svg::Text.new.tap do |text|
          text.x = label.x
          text.y = label.y
          text.content = label.text
          text.fill = "#000000"
          text.font_family = "Arial, sans-serif"
          text.font_size = number_string(label.font_size)
          text.text_anchor = "middle"
        end
      end

      def draw_participant(participant, svg)
        group = Svg::Group.new.tap do |item|
          item.id = "participant-#{participant.id}"
        end
        if participant.actor_type == "actor"
          draw_actor(participant, group)
        else
          draw_participant_box(participant, group)
        end
        svg << group
      end

      def draw_participant_box(participant, group)
        group.children << Svg::Rect.new.tap do |rect|
          rect.x = participant.x
          rect.y = participant.y
          rect.width = participant.width
          rect.height = participant.height
          rect.fill = "#ffffff"
          rect.stroke = "#000000"
          rect.stroke_width = "2"
          rect.rx = participant.corner_radius
          rect.ry = participant.corner_radius
        end
        group.children << participant_label(participant.label) if participant.label
      end

      def participant_label(label)
        Svg::Text.new.tap do |text|
          text.x = label.x
          text.y = label.y
          text.content = label.text
          text.fill = "#000000"
          text.font_family = "Arial, sans-serif"
          text.font_size = number_string(label.font_size)
          text.text_anchor = "middle"
          text.dominant_baseline = "middle"
        end
      end

      def draw_actor(participant, group)
        group.children << Svg::Circle.new.tap do |circle|
          circle.cx = participant.actor_head.x
          circle.cy = participant.actor_head.y
          circle.r = participant.actor_head.radius
          circle.fill = "none"
          circle.stroke = "#000000"
          circle.stroke_width = "2"
        end
        participant.actor_lines.each do |geometry|
          group.children << svg_line(geometry, stroke_width: "2")
        end
      end

      def svg_line(geometry, stroke_width:, dash: nil)
        Svg::Line.new.tap do |line|
          line.x1 = geometry.x1
          line.y1 = geometry.y1
          line.x2 = geometry.x2
          line.y2 = geometry.y2
          line.stroke = "#000000"
          line.stroke_width = stroke_width
          line.stroke_dasharray = dash if dash
        end
      end

      def number_string(value)
        value.to_i == value ? value.to_i.to_s : value.to_s
      end

      # Compatibility shims for the protected v0.1 renderer surface. Typed
      # geometry passes through the same hook chain as legacy graph data.

      def calculate_width(graph)
        if graph.is_a?(Layout::Sequence::Scene)
          return graph.width - (PARTICIPANT_MARGIN * 2)
        end

        sequence_layout.send(:canvas_width, graph[:children])
      end

      def calculate_height(graph)
        if graph.is_a?(Layout::Sequence::Scene)
          return graph.height - (PARTICIPANT_MARGIN * 2)
        end

        metadata = graph[:metadata] || {}
        sequence_layout.send(
          :canvas_height, graph[:children], metadata[:message_count] || 0
        )
      end

      def calculate_participant_positions(participants)
        sequence_layout.send(:participant_positions, participants)
      end

      def render_participants(participants, positions, svg)
        participants.each do |participant|
          render_participant(participant, positions, svg)
        end
      end

      def render_participant(participant, positions, svg)
        if participant.is_a?(Layout::Sequence::Participant)
          draw_participant(participant, svg)
          return
        end

        geometry = sequence_layout.send(
          :typed_participant, participant, positions[participant[:id]]
        )
        draw_participant(geometry, svg) if geometry
      end

      def render_participant_box(x, y, participant, group)
        geometry = sequence_layout.send(
          :typed_participant_at, participant, x, y
        )
        draw_participant_box(geometry, group)
      end

      def render_actor(x, y, participant, group)
        actor = (participant || {}).merge(
          metadata: ((participant || {})[:metadata] || {})
            .merge(actor_type: "actor"),
        )
        geometry = sequence_layout.send(:typed_participant_at, actor, x, y)
        draw_actor(geometry, group)
      end

      def render_lifelines(positions, message_count, svg)
        sequence_layout.send(:lifeline_geometry, positions, message_count)
          .each { |lifeline| draw_lifeline(lifeline, svg) }
      end

      def render_messages(graph, positions, svg)
        messages = if graph.is_a?(Layout::Sequence::Scene)
                     graph.messages
                   else
                     graph[:edges]
                   end
        messages.each_with_index do |edge, index|
          render_message(edge, positions, index, svg)
        end
      end

      def render_message(edge, positions, index, svg)
        if edge.is_a?(Layout::Sequence::Message)
          draw_message(edge, svg)
          return
        end

        geometry = sequence_layout.send(:typed_message, edge, positions, index)
        draw_message(geometry, svg) if geometry
      end

      def render_arrow(x1, y1, x2, y2, style, group)
        geometry = sequence_layout.send(
          :arrow_geometry, x1, y1, x2, y2, style
        )
        draw_arrow_geometry(geometry, style, group)
      end

      def render_self_message(x, y, style, group)
        geometry = sequence_layout.send(:self_arrow_geometry, x, y, style)
        draw_arrow_geometry(geometry, style, group)
      end

      def draw_arrow_geometry(geometry, style, group)
        if geometry[:loop_path]
          message = Layout::Sequence::Message.new(
            loop_path: geometry[:loop_path], line_style: style[:line],
          )
          group.children << message_path(message)
        elsif geometry[:shaft]
          group.children << svg_line(
            geometry[:shaft], stroke_width: "2",
                              dash: style[:line] == "dotted" ? "5,5" : nil
          )
        end
        geometry[:heads].each do |head|
          group.children.concat(head_elements(head))
        end
      end

      def head_ends(style)
        sequence_layout.send(:head_ends, style)
      end

      def message_line(span, style, ends)
        sequence_layout.send(:message_line, span, style, ends).then do |geometry|
          svg_line(
            geometry, stroke_width: "2",
                      dash: style[:line] == "dotted" ? "5,5" : nil
          )
        end
      end

      def render_head(which, span, style, group)
        head = sequence_layout.send(:head_geometry, which, span, style)
        group.children.concat(head_elements(head))
      end

      def render_stick_head(from_x, tip_x, tip_y, side, group)
        geometry = sequence_layout.send(
          :stick_head_line, from_x, tip_x, tip_y, side
        )
        group.children << head_line(geometry)
      end

      def render_filled_arrowhead(x1, _y1, x2, y2, group)
        points = sequence_layout.send(:filled_head_points, x1, x2, y2)
        group.children << polygon_head(
          Layout::Sequence::Head.new(shape: "polygon", points: points),
        )
      end

      def render_open_arrowhead(x1, _y1, x2, y2, group)
        sequence_layout.send(:open_head, x1, x2, y2).each do |geometry|
          group.children << head_line(geometry)
        end
      end

      def render_half_head(from_x, tip_x, tip_y, side, group)
        points = sequence_layout.send(
          :half_head_points, from_x, tip_x, tip_y, side
        )
        group.children << polygon_head(
          Layout::Sequence::Head.new(shape: "polygon", points: points),
        )
      end

      def render_chevron(from_x, tip_x, tip_y, group)
        points = sequence_layout.send(:chevron_points, from_x, tip_x, tip_y)
        group.children << polygon_head(
          Layout::Sequence::Head.new(shape: "polygon", points: points),
        )
      end

      def render_cross(x, y, group)
        head = sequence_layout.send(:cross_head, x, y)
        group.children.concat(head_elements(head))
      end

      def render_message_label(x1, x2, y, text, group)
        label = sequence_layout.send(:compatibility_label, x1, x2, y, text)
        group.children << message_label(label)
      end

      def render_notes(_notes, _positions, _svg); end

      def sequence_layout
        Layout::Sequence.new.tap { |layout| layout.theme = theme }
      end
    end
  end
end
