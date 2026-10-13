# frozen_string_literal: true

require_relative "base"
require_relative "../layout/sequence"
require_relative "sequence/note_drawing"
require_relative "sequence/frame_drawing"

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
      include FrameDrawing

      LAYOUT_SCENE = Layout::Sequence::Scene

      HEAD_ENDS = {
        "target" => [:target].freeze,
        "source" => [:source].freeze,
        "both" => %i[source target].freeze,
      }.freeze
      FLUSH_HEADS = %w[cross open stick_top stick_bottom].freeze
      SHAPED_PARTICIPANTS = %w[boundary control entity].freeze
      private_constant :LAYOUT_SCENE

      # @param diagram [Layout::Sequence::Scene, Hash] final geometry or graph
      # @return [Svg::Document] rendered SVG document
      def render(diagram)
        return render_scene(diagram) if diagram.is_a?(Layout::Sequence::Scene)

        render_graph(diagram)
      end

      protected

      def render_scene(scene)
        svg = create_document(scene)
        draw_boxes(scene, svg)
        scene.lifelines.each { |lifeline| draw_lifeline(lifeline, svg) }
        draw_frames(scene, svg)
        scene.messages.each { |message| draw_message(message, svg) }
        draw_participants_and_notes(scene, svg)
        svg
      end

      def draw_participants_and_notes(scene, svg)
        scene.participants.each do |participant|
          draw_participant(participant, svg)
        end
        scene.notes.each { |note| svg << NoteDrawing.new(note).group }
      end

      def render_graph(graph)
        scene = graph_canvas(graph)
        svg = create_document(scene)
        metadata = graph[:metadata] || {}
        positions = calculate_participant_positions(graph[:children])
        render_graph_contents(graph, metadata, positions, svg)
        svg
      end

      def render_graph_notes(metadata, positions, svg)
        return unless metadata[:notes]

        render_notes(metadata[:note_entries] || metadata[:notes],
                     positions, svg)
      end

      def draw_lifeline(lifeline, svg)
        svg << svg_line(lifeline, stroke_width: "1", dash: LIFELINE_DASH)
      end

      def draw_message(message, svg)
        group = Svg::Group.new.tap { |item| item.id = message.id }
        draw_message_geometry(message, group)
        group.children << message_label(message.label) if message.label
        svg << group
      end

      def message_path(message)
        Svg::Path.new.tap do |path|
          path.d = message.loop_path
          path.fill = "none"
          path.stroke = theme_color(:edge_stroke)
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
          polygon.fill = theme_color(:edge_stroke)
          polygon.stroke = theme_color(:edge_stroke)
        end
      end

      def head_line(geometry)
        svg_line(geometry, stroke_width: "2")
      end

      def message_label(label)
        Svg::Text.new.tap do |text|
          position_label(text, label)
          label_content(text, label)
          style_label(text, label)
        end
      end

      # One run per line when the text wraps or breaks; each run places
      # itself, so no line offset is written.
      def label_content(text, label)
        return text.content = label.text unless label.lines.length > 1

        text.tspans = label.lines.each_with_index.map do |line, row|
          message_label_run(line, label.x, label.line_ys.fetch(row))
        end
      end

      def draw_participant(participant, svg)
        group = Svg::Group.new.tap do |item|
          item.id = "participant-#{participant.id}"
        end
        draw_participant_shape(participant, group)
        svg << group
      end

      def draw_shaped_participant(participant, group)
        group.children << participant_circle(participant.shape_circle,
                                             theme_color(:node_fill))
        draw_participant_lines(participant.shape_lines, group)
        draw_participant_label(participant, group)
      end

      def draw_participant_box(participant, group)
        group.children << participant_rectangle(participant)
        draw_participant_label(participant, group)
      end

      def participant_label(label)
        Svg::Text.new.tap do |text|
          position_label(text, label)
          text.content = label.text
          style_label(text, label)
          text.dominant_baseline = "middle"
        end
      end

      def draw_actor(participant, group)
        group.children << participant_circle(participant.actor_head, "none")
        draw_participant_lines(participant.actor_lines, group)
        draw_participant_label(participant, group)
      end

      def actor_line(geometry)
        svg_line(
          geometry, stroke_width: "2", stroke: theme_color(:node_stroke)
        )
      end

      def svg_line(geometry, stroke_width:, dash: nil,
                   stroke: theme_color(:edge_stroke))
        Svg::Line.new(
          x1: geometry.x1, y1: geometry.y1,
          x2: geometry.x2, y2: geometry.y2,
          stroke: stroke, stroke_width: stroke_width, stroke_dasharray: dash
        )
      end

      def number_string(value)
        value.to_i == value ? value.to_i.to_s : value.to_s
      end

      # Compatibility shims for the protected v0.1 renderer surface. Hash
      # rendering uses this chain; typed scenes already contain final geometry.

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

      def render_participant_box(position_x, position_y, participant, group)
        geometry = sequence_layout.send(
          :typed_participant_at, participant, position_x, position_y
        )
        draw_participant_box(geometry, group)
      end

      def render_actor(position_x, position_y, participant, group)
        actor = (participant || {}).merge(
          metadata: ((participant || {})[:metadata] || {})
            .merge(actor_type: "actor"),
        )
        geometry = sequence_layout.send(
          :typed_participant_at, actor, position_x, position_y
        )
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

      def render_arrow(*arguments)
        unless arguments.length == 6
          raise ArgumentError,
                "wrong number of arguments " \
                "(given #{arguments.length}, expected 6)"
        end

        geometry = sequence_layout.send(:arrow_geometry, *arguments.first(5))
        draw_arrow_geometry(geometry, arguments[-2], arguments.last)
      end

      def render_self_message(position_x, position_y, style, group)
        geometry = sequence_layout.send(
          :self_arrow_geometry, position_x, position_y, style
        )
        draw_arrow_geometry(geometry, style, group)
      end

      def draw_arrow_geometry(geometry, style, group)
        draw_arrow_shaft(geometry, style, group)
        geometry[:heads].each do |head|
          group.children.concat(head_elements(head))
        end
      end

      def head_ends(style)
        sequence_layout.send(:head_ends, style)
      end

      def message_line(span, style, ends)
        line = sequence_layout.send(:message_line, span, style, ends)
        line.then do |geometry|
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

      def render_filled_arrowhead(start_x, _start_y, end_x, end_y, group)
        points = sequence_layout.send(
          :filled_head_points, start_x, end_x, end_y
        )
        group.children << polygon_head(
          Layout::Sequence::Head.new(shape: "polygon", points: points),
        )
      end

      def render_open_arrowhead(start_x, _start_y, end_x, end_y, group)
        lines = sequence_layout.send(:open_head, start_x, end_x, end_y)
        lines.each do |geometry|
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

      def render_cross(position_x, position_y, group)
        head = sequence_layout.send(:cross_head, position_x, position_y)
        group.children.concat(head_elements(head))
      end

      def render_message_label(start_x, end_x, position_y, text, group)
        label = sequence_layout.send(
          :compatibility_label, start_x, end_x, position_y, text
        )
        group.children << message_label(label)
      end

      def render_notes(entries, positions, svg)
        placement = sequence_layout.send(:note_placement,
                                         entries.grep(Hash), positions)
        placement.notes.each { |note| svg << NoteDrawing.new(note).group }
      end

      def sequence_layout
        Layout::Sequence.new.tap { |layout| layout.theme = theme }
      end

      private

      def graph_canvas(graph)
        LAYOUT_SCENE.new(width: calculate_width(graph) + 40,
                         height: calculate_height(graph) + 40)
      end

      def render_graph_contents(graph, metadata, positions, svg)
        render_lifelines(positions, metadata[:message_count] || 0, svg)
        render_messages(graph, positions, svg) if graph[:edges]
        render_participants(graph[:children], positions, svg)
        render_graph_notes(metadata, positions, svg)
      end

      def draw_message_geometry(message, group)
        group.children << message_path(message) if message.loop_path
        group.children << message_shaft(message.shaft, message.line_style) if
          message.shaft
        draw_message_heads(message.heads, group)
      end

      def draw_message_heads(heads, group)
        heads.each { |head| group.children.concat(head_elements(head)) }
      end

      def message_shaft(geometry, line_style)
        svg_line(geometry, stroke_width: "2",
                           dash: line_style == "dotted" ? "5,5" : nil)
      end

      def position_label(text, label)
        text.x = label.x
        text.y = label.y
      end

      def style_label(text, label)
        text.fill = theme_color(:label_text)
        text.font_family = "Arial, sans-serif"
        text.font_size = number_string(label.font_size)
        text.text_anchor = "middle"
      end

      def message_label_run(line, position_x, position_y)
        Svg::Tspan.new.tap do |run|
          run.x = position_x
          run.y = position_y
          run.content = line
        end
      end

      def draw_participant_shape(participant, group)
        if SHAPED_PARTICIPANTS.include?(participant.shape_type)
          draw_shaped_participant(participant, group)
        elsif participant.actor_type == "actor"
          draw_actor(participant, group)
        else
          draw_participant_box(participant, group)
        end
      end

      def participant_circle(geometry, fill)
        Svg::Circle.new.tap do |circle|
          circle.cx = geometry.x
          circle.cy = geometry.y
          circle.r = geometry.radius
          circle.fill = fill
          circle.stroke = theme_color(:node_stroke)
          circle.stroke_width = "2"
        end
      end

      def draw_participant_lines(lines, group)
        lines.each { |geometry| group.children << actor_line(geometry) }
      end

      def draw_participant_label(participant, group)
        group.children << participant_label(participant.label) if
          participant.label
      end

      def participant_rectangle(participant)
        Svg::Rect.new.tap do |rect|
          position_participant_rectangle(rect, participant)
          rect.fill = theme_color(:node_fill)
          rect.stroke = theme_color(:node_stroke)
          rect.stroke_width = "2"
          rect.rx = participant.corner_radius
          rect.ry = participant.corner_radius
        end
      end

      def position_participant_rectangle(rect, participant)
        rect.x = participant.x
        rect.y = participant.y
        rect.width = participant.width
        rect.height = participant.height
      end

      def draw_arrow_shaft(geometry, style, group)
        if geometry[:loop_path]
          message = Layout::Sequence::Message.new(
            loop_path: geometry[:loop_path], line_style: style[:line],
          )
          group.children << message_path(message)
        elsif geometry[:shaft]
          group.children << message_shaft(geometry[:shaft], style[:line])
        end
      end
    end
  end
end
