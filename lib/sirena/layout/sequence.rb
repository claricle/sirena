# frozen_string_literal: true

require_relative "base"
require_relative "../diagram/sequence"
require_relative "../diagram/sequence_text"
require_relative "../notation/mermaid/ir_adapters/sequence"
require_relative "sequence/geometry"
require_relative "sequence/actor_gaps"
require_relative "sequence/text_width"
require_relative "sequence/text_wrap"
require_relative "sequence/message_rows"
require_relative "sequence/note_placement"
require_relative "sequence/frame_reader"
require_relative "sequence/frame_placement"

module Sirena
  module Layout
    # Builds final sequence-diagram geometry without an external layout pass.
    class Sequence < Base
      # mmdc draws every sequence text at 16px.
      DEFAULT_FONT_SIZE = 16
      PARTICIPANT_SPACING = Geometry::ACTOR_WIDTH
      PARTICIPANT_WIDTH = Geometry::ACTOR_WIDTH
      PARTICIPANT_HEIGHT = Geometry::ACTOR_HEIGHT
      PARTICIPANT_MARGIN = Geometry::ACTOR_MARGIN
      PARTICIPANT_LABEL_PADDING = 20
      MESSAGE_SPACING = Geometry::MESSAGE_PITCH
      LIFELINE_DASH = "5,5"
      ARROW_SIZE = 8
      SELF_LOOP_WIDTH = 56
      SELF_LOOP_HEIGHT = 20
      ACTOR_LABEL_OFFSET = 55
      # The released renderer hooks size the canvas this much smaller
      # than the scene they draw (Renderer::Sequence#calculate_width).
      CANVAS_PAD = 40

      HEAD_ENDS = {
        "target" => [:target].freeze,
        "source" => [:source].freeze,
        "both" => %i[source target].freeze,
      }.freeze
      FLUSH_HEADS = %w[cross open stick_top stick_bottom].freeze
      PARTICIPANT_ROLES = %w[participant actor].freeze

      class Line < Lutaml::Model::Serializable
        attribute :x1, :float
        attribute :y1, :float
        attribute :x2, :float
        attribute :y2, :float
      end

      class Circle < Lutaml::Model::Serializable
        attribute :x, :float
        attribute :y, :float
        attribute :radius, :float
      end

      class Label < Lutaml::Model::Serializable
        attribute :text, :string
        attribute :width, :float
        attribute :height, :float
        attribute :x, :float
        attribute :y, :float
        attribute :font_size, :float
        # Drawn lines when the text wraps or holds a `<br>`; empty for
        # a one-line text. Line i sits `line_pitch * i` below `y`.
        attribute :lines, :string, collection: true, default: -> { [] }
        attribute :line_pitch, :float
      end

      class Head < Lutaml::Model::Serializable
        attribute :shape, :string
        attribute :points, :string
        attribute :lines, Line, collection: true, default: -> { [] }
      end

      class Participant < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :actor_type, :string
        attribute :x, :float
        attribute :y, :float
        attribute :width, :float
        attribute :height, :float
        attribute :corner_radius, :float
        attribute :label, Label
        attribute :actor_head, Circle
        attribute :actor_lines, Line, collection: true, default: -> { [] }
      end

      class Message < Lutaml::Model::Serializable
        attribute :id, :string
        attribute :line_style, :string
        attribute :shaft, Line
        attribute :loop_path, :string
        attribute :heads, Head, collection: true, default: -> { [] }
        attribute :label, Label
      end

      require_relative "sequence/note"

      class Scene < Layout::Scene
        attribute :id, :string
        attribute :view_box, :string
        attribute :participants, Participant, collection: true,
                                              default: -> { [] }
        attribute :lifelines, Line, collection: true, default: -> { [] }
        attribute :messages, Message, collection: true, default: -> { [] }
        attribute :notes, Note, collection: true, default: -> { [] }
        attribute :frames, FrameShape, collection: true, default: -> { [] }
        attribute :boxes, BoxShape, collection: true, default: -> { [] }
      end

      # Retains the pre-Scene graph shape for direct layout callers.
      def build_graph(diagram)
        graph = ir_graph(diagram)
        {
          id: source_diagram_id(graph),
          children: transform_participants(graph),
          edges: transform_messages(graph),
          layoutOptions: layout_options,
          metadata: graph_metadata(graph),
        }
      end

      private

      def ir_graph(diagram)
        return diagram if diagram.is_a?(IR::Graph)

        Notation::Mermaid::IRAdapters::Sequence.call(diagram)
      end

      def source_diagram_id(graph)
        settings = graph.nodes.find { |node| node.role == "diagram_settings" }
        semantic_value(graph, settings&.id, "diagram_identifier") || graph.id
      end

      def graph_metadata(graph)
        participants = participant_nodes(graph)
        {
          participants: participants.map(&:id),
          message_count: message_edges(graph).length,
          notes: graph.nodes.select { |node| node.role == "note" },
          note_entries: NotePlacement.entries(graph),
          title: graph.label,
          accessibility_title: graph.accessibility_title,
          accessibility_description: graph.accessibility_description,
        }.merge(FrameReader.call(graph), wrap: wrap_setting?(graph))
      end

      def wrap_setting?(graph)
        settings = graph.nodes.find { |node| node.role == "diagram_settings" }
        semantic_value(graph, settings&.id, "wrap") == "true"
      end

      def scene(diagram)
        graph = build_graph(diagram)
        @wrap = graph.dig(:metadata, :wrap) || false
        @frame_layout = frame_placement(graph)
        @gaps = build_gaps(graph)
        build_scene(graph, *shifted_placement(graph))
      end

      # A note left of the first actor may stick out past the left margin;
      # mmdc then grows the canvas leftwards, so every actor moves right.
      def shifted_placement(graph)
        entries = graph.dig(:metadata, :note_entries)
        positions = participant_positions(graph[:children])
        @rows = MessageRows.new(graph[:edges], positions,
                                font_size: message_font_size, wrap: @wrap)
        placement = note_placement(entries, positions)
        @shift = placement.overhang
        return [positions, placement] if @shift.zero?

        positions = participant_positions(graph[:children], @shift)
        [positions, note_placement(entries, positions)]
      end

      def frame_layout
        @frame_layout ||= FramePlacement.new
      end

      def build_gaps(graph)
        ActorGaps.new(graph[:children], graph[:edges],
                      graph.dig(:metadata, :note_entries),
                      font_size: message_font_size,
                      wrap: graph.dig(:metadata, :wrap))
      end

      def gaps
        @gaps ||= ActorGaps.new([], [], [], font_size: message_font_size)
      end

      def rows
        @rows ||= MessageRows.new([], {}, font_size: message_font_size,
                                  wrap: @wrap)
      end

      # Height the notes and the messages' extra lines add to the diagram.
      def stack_height(placement)
        placement.total_height + rows.total_extra
      end

      def frame_placement(graph)
        metadata = graph[:metadata]
        spans = graph[:edges].map { |e| [e[:sources].first, e[:targets].first] }
        FramePlacement.new(frames: metadata[:frames],
                           boxes: metadata[:boxes], spans: spans)
      end

      def build_scene(graph, positions, placement)
        width, height = scene_dimensions(graph, placement)
        Scene.new(
          id: graph[:id], width: width, height: height,
          view_box: "0 0 #{width} #{height}",
          participants: typed_participants(graph[:children], positions),
          **placed_geometry(graph, positions, placement)
        )
      end

      def placed_geometry(graph, positions, placement)
        count = graph.dig(:metadata, :message_count) || 0
        {
          lifelines: lifeline_geometry(positions, count,
                                       stack_height(placement)),
          messages: typed_messages(graph[:edges], positions, placement),
          notes: placement.notes,
          frames: frame_shapes(positions, placement),
          boxes: box_shapes(graph[:children], positions, count, placement),
        }
      end

      def note_placement(entries, positions)
        NotePlacement.new(entries, positions, font_size: message_font_size,
                                              frames: frame_layout,
                                              rows: rows)
      end

      def frame_shapes(positions, notes)
        row_y = lambda do |index|
          message_vertical(index) + notes.shift_for(index) +
            rows.extra_before(index)
        end
        frame_layout.frame_shapes(positions, row_y, notes)
      end

      def box_shapes(children, positions, count, notes)
        widths = children.to_h { |child| [child[:id], child[:width]] }
        bottom = lifeline_bottom(count, stack_height(notes))
        bottom += FramePlacement::BOX_BOTTOM_PAD
        frame_layout.box_shapes(positions, widths, bottom)
      end

      def scene_dimensions(graph, placement)
        children = graph[:children]
        count = graph.dig(:metadata, :message_count) || 0
        wide = canvas_width(children) + CANVAS_PAD + @shift
        [[wide, notes_right_edge(placement)].max,
         canvas_height(children, count) + stack_height(placement) + CANVAS_PAD]
      end

      def notes_right_edge(placement)
        return 0 if placement.notes.empty?

        placement.right_edge + Geometry::DIAGRAM_MARGIN_X
      end

      def transform_participants(graph)
        participant_nodes(graph).map.with_index do |participant, index|
          label = measured_label(participant.label, participant_font_size)
          {
            id: participant.id,
            width: participant_width(label),
            height: PARTICIPANT_HEIGHT,
            labels: [label],
            metadata: {
              actor_type: participant_type(graph, participant),
              index: index,
              lifeline_length: calculate_lifeline_length(graph),
            },
          }
        end
      end

      def participant_nodes(graph)
        graph.nodes.select do |node|
          PARTICIPANT_ROLES.include?(node.role)
        end
      end

      def participant_type(graph, participant)
        semantic_value(graph, participant.id, "participant_type") ||
          participant.role
      end

      def transform_messages(graph)
        message_edges(graph).map.with_index do |message, index|
          transformed_message(graph, message, index)
        end
      end

      def transformed_message(graph, message, index)
        semantics = semantic_fields(graph, message.parent_id)
        text = shown_text(message.label.to_s)
        {
          id: message.id, sources: [message.source_id],
          targets: [message.target_id], labels: message_labels(text),
          metadata: message_metadata(semantics, text, index, message.label.to_s)
        }
      end

      def message_metadata(semantics, text, index, source)
        {
          line_style: semantics["line_style"],
          head_style: semantics["head_style"],
          head_side: semantics["head_side"],
          message_index: index, message_text: text,
          message_source: source
        }
      end

      def message_edges(graph)
        graph.edges.select { |edge| edge.role == "message" }
      end

      def semantic_fields(graph, parent_id)
        graph.nodes.filter_map do |node|
          [node.role, node.label] if node.parent_id == parent_id
        end.to_h
      end

      def semantic_value(graph, parent_id, role)
        semantic_fields(graph, parent_id)[role]
      end

      def shown_text(text)
        Diagram::SequenceText.display(text)
      end

      def message_labels(text)
        return [] if text.empty?

        [measured_label(text, message_font_size)]
      end

      def measured_label(text, font_size)
        measure_text(text, font_size: font_size).merge(text: text)
      end

      def participant_font_size
        text_font_size
      end

      def message_font_size
        text_font_size
      end

      def text_font_size
        value = theme&.typography&.sequence_font_size
        value&.positive? ? value : DEFAULT_FONT_SIZE
      end

      def calculate_lifeline_length(graph)
        base_height = message_edges(graph).length * MESSAGE_SPACING
        note_count = graph.nodes.count { |node| node.role == "note" }
        base_height + (note_count * 30)
      end

      def layout_options
        build_elk_options(
          algorithm: ALGORITHM_LAYERED,
          direction: DIRECTION_DOWN,
          ElkOptions::NODE_NODE_SPACING => PARTICIPANT_SPACING,
          ElkOptions::LAYER_SPACING => MESSAGE_SPACING,
          ElkOptions::EDGE_NODE_SPACING => 20,
          ElkOptions::EDGE_EDGE_SPACING => 15,
          ElkOptions::NODE_PLACEMENT => "SIMPLE",
          ElkOptions::MODEL_ORDER => "NODES_AND_EDGES",
        )
      end

      def canvas_width(participants)
        return 800 unless participants
        return 0 if participants.empty?

        participants_span(participants) +
          (2 * Geometry::DIAGRAM_MARGIN_X) - CANVAS_PAD +
          frame_layout.extra_width
      end

      def participants_span(participants)
        total_width = participants.sum do |participant|
          participant_width_value(participant)
        end
        total_width + ((participants.length - 1) * PARTICIPANT_MARGIN) +
          inner_gaps(participants)
      end

      def inner_gaps(participants)
        participants.first(participants.length - 1).sum do |participant|
          gaps.extra_after(participant_id(participant))
        end
      end

      def canvas_height(participants, message_count)
        return 0 if (participants || []).empty?

        (2 * Geometry::DIAGRAM_MARGIN_Y) + (PARTICIPANT_HEIGHT * 2) +
          lifeline_length(message_count) + frame_layout.top_inset +
          Geometry::CANVAS_TRIM - CANVAS_PAD
      end

      def participant_positions(participants, shift = 0)
        cursor = Geometry::DIAGRAM_MARGIN_X + shift
        participants.to_h do |participant|
          id = participant_id(participant)
          left = cursor + frame_layout.gap_before(id)
          width = participant_width_value(participant)
          cursor = left + participant_advance(id, width)
          [id, participant_position(left, width)]
        end
      end

      def participant_advance(id, width)
        width + PARTICIPANT_MARGIN + frame_layout.gap_after(id) +
          gaps.extra_after(id)
      end

      def participant_position(left, width)
        { x: left, y: origin_y, center_x: left + (width / 2) }
      end

      def typed_participants(participants, positions)
        participants.filter_map do |participant|
          typed_participant(participant, positions[participant[:id]])
        end
      end

      def typed_participant(participant, position)
        return unless position

        label = participant[:labels]&.first
        actor_type = participant.dig(:metadata, :actor_type) || "participant"
        Participant.new(
          id: participant[:id], actor_type: actor_type,
          x: position[:x], y: position[:y],
          width: participant[:width] || PARTICIPANT_WIDTH,
          height: participant[:height] || PARTICIPANT_HEIGHT,
          corner_radius: 5,
          label: typed_participant_label(label, position, actor_type),
          actor_head: actor_head(position, actor_type),
          actor_lines: actor_lines(position, actor_type)
        )
      end

      def typed_participant_at(participant, horizontal, vertical)
        width = participant[:width] || PARTICIPANT_WIDTH
        typed_participant(
          participant,
          {
            x: horizontal, y: vertical,
            center_x: horizontal + (width / 2)
          },
        )
      end

      def participant_width(label)
        lines = label[:text].to_s.split(Diagram::SequenceText::LINE_BREAK, -1)
        text = TextWidth.widest(lines, participant_font_size)
        padded = (text + PARTICIPANT_LABEL_PADDING).to_f
        [PARTICIPANT_WIDTH, padded].max
      end

      def participant_width_value(participant)
        if participant.is_a?(Participant)
          participant.width
        else
          participant[:width] || PARTICIPANT_WIDTH
        end
      end

      def participant_id(participant)
        participant.is_a?(Participant) ? participant.id : participant[:id]
      end

      def typed_participant_label(label, position, actor_type = nil)
        return unless label

        Label.new(
          text: label[:text], width: label[:width], height: label[:height],
          x: position[:center_x],
          y: position[:y] + label_offset(actor_type),
          font_size: participant_font_size
        )
      end

      def label_offset(actor_type)
        actor_type == "actor" ? ACTOR_LABEL_OFFSET : PARTICIPANT_HEIGHT / 2
      end

      def actor_head(position, actor_type)
        return unless actor_type == "actor"

        Circle.new(x: position[:center_x], y: position[:y] + 10, radius: 8)
      end

      def actor_lines(position, actor_type)
        return [] unless actor_type == "actor"

        center = position[:center_x]
        body_top = position[:y] + 18
        body_bottom = body_top + 15
        [
          line(center, body_top, center, body_bottom),
          line(center - 10, body_top + 7, center + 10, body_top + 7),
          *actor_leg_lines(center, body_bottom),
        ]
      end

      def actor_leg_lines(center, body_bottom)
        [
          line(center, body_bottom, center - 8, body_bottom + 10),
          line(center, body_bottom, center + 8, body_bottom + 10),
        ]
      end

      def origin_y
        Geometry::DIAGRAM_MARGIN_Y + frame_layout.top_inset
      end

      def lifeline_bottom(message_count, note_height = 0)
        origin_y + PARTICIPANT_HEIGHT +
          lifeline_length(message_count, note_height)
      end

      def lifeline_length(message_count, note_height = 0)
        (message_count * MESSAGE_SPACING) + Geometry::LIFELINE_TAIL +
          frame_layout.total_shift + note_height
      end

      def lifeline_geometry(positions, message_count, note_height = 0)
        length = lifeline_length(message_count, note_height)
        positions.values.map do |position|
          line(
            position[:center_x], origin_y + PARTICIPANT_HEIGHT,
            position[:center_x], origin_y + PARTICIPANT_HEIGHT + length
          )
        end
      end

      def typed_messages(edges, positions, placement)
        (edges || []).each_with_index.filter_map do |edge, index|
          typed_message(edge, positions, index, placement.shift_for(index))
        end
      end

      def typed_message(edge, positions, index, shift = 0)
        source, target = message_endpoints(edge, positions)
        return unless source && target

        vertical = message_vertical(index) + shift + rows.extra_through(index)
        build_typed_message(edge, index, source, target, vertical)
      end

      def message_endpoints(edge, positions)
        [positions[edge[:sources]&.first],
         positions[edge[:targets]&.first]]
      end

      def message_vertical(index)
        origin_y + PARTICIPANT_HEIGHT + ((index + 1) * MESSAGE_SPACING) +
          frame_layout.row_shift(index)
      end

      def build_typed_message(edge, index, source, target, vertical)
        style = message_style(edge)
        arrow = message_arrow(source, target, vertical, style)
        Message.new(
          id: "message-#{index}", line_style: style[:line],
          shaft: arrow[:shaft], loop_path: arrow[:loop_path],
          heads: arrow[:heads],
          label: typed_message_label(edge, source[:center_x],
                                     target[:center_x], vertical, index)
        )
      end

      def message_arrow(source, target, vertical, style)
        arrow_geometry(
          source[:center_x], vertical, target[:center_x], vertical, style
        )
      end

      def message_style(edge)
        metadata = edge[:metadata] || {}
        {
          line: metadata[:line_style] || "solid",
          head: metadata[:head_style] || "filled",
          side: metadata[:head_side] || "target",
        }
      end

      def typed_message_label(edge, source_x, target_x, vertical, index = nil)
        text = edge.dig(:metadata, :message_text)
        return if text.nil? || text.empty?

        source_label = edge[:labels]&.first || {}
        Label.new(
          text: text, width: source_label[:width],
          height: source_label[:height],
          x: midpoint(source_x, target_x),
          y: label_top(source_x, target_x, vertical, index),
          font_size: message_font_size, **drawn_lines(index)
        )
      end

      # Baseline of the first line: a many-line text starts higher so that
      # its last line, not its first, sits just above the arrow.
      def label_top(source_x, target_x, vertical, index)
        vertical - message_label_offset(source_x, target_x) -
          rows.extra(index)
      end

      def drawn_lines(index)
        shown = rows.lines(index)
        return {} unless shown.length > 1

        { lines: shown, line_pitch: rows.line_pitch }
      end

      def midpoint(source_x, target_x)
        (source_x + target_x) / 2
      end

      def message_label_offset(source_x, target_x)
        source_x == target_x ? (SELF_LOOP_HEIGHT / 2) + 10 : 10
      end

      def compatibility_label(source_x, target_x, vertical, text)
        edge = {
          labels: [{}],
          metadata: { message_text: text },
        }
        typed_message_label(edge, source_x, target_x, vertical)
      end

      def arrow_geometry(start_x, start_y, end_x, end_y, style)
        return self_arrow_geometry(start_x, start_y, style) if start_x == end_x

        span = { x1: start_x, y1: start_y, x2: end_x, y2: end_y }
        ends = head_ends(style)
        {
          shaft: message_line(span, style, ends),
          heads: ends.map { |which| head_geometry(which, span, style) },
        }
      end

      def self_arrow_geometry(horizontal, vertical, style)
        top = vertical - (SELF_LOOP_HEIGHT / 2)
        bottom = vertical + (SELF_LOOP_HEIGHT / 2)
        reach = horizontal + SELF_LOOP_WIDTH
        heads = head_ends(style).map do |which|
          edge_y = which == :source ? top : bottom
          span = {
            x1: horizontal + ARROW_SIZE, y1: edge_y,
            x2: horizontal, y2: edge_y
          }
          head_geometry(:target, span, style)
        end
        {
          loop_path: "M #{horizontal},#{top} C #{reach},#{top} " \
                     "#{reach},#{bottom} #{horizontal},#{bottom}",
          heads: heads,
        }
      end

      def head_ends(style)
        return [] if style[:head] == "none"

        HEAD_ENDS.fetch(style[:side], HEAD_ENDS["target"])
      end

      def message_line(span, style, ends)
        inset = FLUSH_HEADS.include?(style[:head]) ? 0 : ARROW_SIZE
        inset *= (span[:x2] <=> span[:x1])
        line(
          span[:x1] + (ends.include?(:source) ? inset : 0), span[:y1],
          span[:x2] - (ends.include?(:target) ? inset : 0), span[:y2]
        )
      end

      def head_geometry(which, span, style)
        tip_x, tip_y, from_x = head_coordinates(which, span)
        side = tip_x <=> from_x
        build_head(style[:head], from_x, tip_x, tip_y, side)
      end

      def build_head(shape, from_x, tip_x, tip_y, side)
        case shape
        when "cross" then cross_head(tip_x, tip_y)
        when "open" then polygon_head(chevron_points(from_x, tip_x, tip_y))
        when "half_bottom", "half_top"
          build_half_head(shape, from_x, tip_x, tip_y, side)
        when "stick_bottom", "stick_top"
          build_stick_head(shape, from_x, tip_x, tip_y, side)
        else polygon_head(filled_head_points(from_x, tip_x, tip_y))
        end
      end

      def build_half_head(shape, from_x, tip_x, tip_y, side)
        points = half_head_points(
          from_x, tip_x, tip_y, oriented_side(shape, side)
        )
        polygon_head(points)
      end

      def build_stick_head(shape, from_x, tip_x, tip_y, side)
        geometry = stick_head_line(
          from_x, tip_x, tip_y, oriented_side(shape, side)
        )
        line_head(geometry)
      end

      def oriented_side(shape, side)
        shape.end_with?("bottom") ? side : -side
      end

      def head_coordinates(which, span)
        if which == :target
          span.values_at(:x2, :y2, :x1)
        else
          span.values_at(:x1, :y1, :x2)
        end
      end

      def filled_head_points(from_x, tip_x, tip_y)
        direction = tip_x > from_x ? 1 : -1
        back = tip_x - (direction * ARROW_SIZE)
        "#{tip_x},#{tip_y} #{back},#{tip_y - (ARROW_SIZE / 2)} " \
          "#{back},#{tip_y + (ARROW_SIZE / 2)}"
      end

      def half_head_points(from_x, tip_x, tip_y, side)
        direction = tip_x >= from_x ? 1 : -1
        back = tip_x - (direction * ARROW_SIZE)
        "#{tip_x},#{tip_y} #{back},#{tip_y + (side * ARROW_SIZE / 2)} " \
          "#{back},#{tip_y}"
      end

      def chevron_points(from_x, tip_x, tip_y)
        direction = tip_x >= from_x ? 1 : -1
        back = tip_x - (direction * ARROW_SIZE)
        notch = tip_x - (direction * ARROW_SIZE * 0.6)
        "#{tip_x},#{tip_y} #{back},#{tip_y - (ARROW_SIZE / 2)} " \
          "#{notch},#{tip_y} #{back},#{tip_y + (ARROW_SIZE / 2)}"
      end

      def stick_head_line(from_x, tip_x, tip_y, side)
        direction = tip_x >= from_x ? 1 : -1
        line(tip_x, tip_y, tip_x - (direction * ARROW_SIZE),
             tip_y + (side * ARROW_SIZE / 2))
      end

      def open_head(from_x, tip_x, tip_y)
        direction = tip_x > from_x ? 1 : -1
        [
          line(tip_x, tip_y, tip_x - (direction * ARROW_SIZE),
               tip_y - (ARROW_SIZE / 2)),
          line(tip_x, tip_y, tip_x - (direction * ARROW_SIZE),
               tip_y + (ARROW_SIZE / 2)),
        ]
      end

      def cross_head(horizontal, vertical)
        size = ARROW_SIZE / 2
        Head.new(
          shape: "cross",
          lines: [
            line(horizontal - size, vertical - size,
                 horizontal + size, vertical + size),
            line(horizontal - size, vertical + size,
                 horizontal + size, vertical - size),
          ],
        )
      end

      def polygon_head(points)
        Head.new(shape: "polygon", points: points)
      end

      def line_head(geometry)
        Head.new(shape: "line", lines: [geometry])
      end

      def line(start_x, start_y, end_x, end_y)
        Line.new(x1: start_x, y1: start_y, x2: end_x, y2: end_y)
      end
    end
  end
end
