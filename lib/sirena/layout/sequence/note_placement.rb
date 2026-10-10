# frozen_string_literal: true

require_relative "../../diagram/sequence_text"
require_relative "geometry"
require_relative "note_box"
require_relative "text_width"
require_relative "frame_placement"

module Sirena
  module Layout
    class Sequence < Base
      # Gives every note its own vertical slot between two message rows and
      # reports how far that slot pushes the later rows down.
      class NotePlacement
        LINE_BREAK = Diagram::SequenceText::LINE_BREAK
        FIRST_ROW = Geometry::FIRST_ROW
        ROW_SPACING = Geometry::MESSAGE_PITCH
        TOP_GAP = Geometry::NOTE_MARGIN
        SLOT_GAP = Geometry::NOTE_MARGIN
        PADDING = NoteBox::PADDING
        NO_ROWS = Class.new do
          def extra_before(_index) = 0

          def wrap? = false
        end.new.freeze
        LINE_SPACING = 1.2

        # @param graph [Sirena::IR::Graph] the sequence graph
        # @return [Array<Hash>] text, position, participant_ids and
        #   message_index per note, in source order
        def self.entries(graph)
          graph.nodes.select { |node| node.role == "note" }.map do |node|
            entry_for(graph, node)
          end
        end

        def self.entry_for(graph, node)
          fields = fields_of(graph, node)
          {
            text: node.label.to_s, position: fields["note_position"],
            message_index: fields["message_index"].to_i,
            order: fields["order"].to_i,
            participant_ids: reference_ids(graph, node)
          }
        end

        def self.fields_of(graph, node)
          details = graph.nodes.select { |item| item.parent_id == node.id }
          details.to_h { |item| [item.role, item.label] }
        end

        def self.reference_ids(graph, node)
          graph.edges.select do |edge|
            edge.role == "note_reference" && edge.source_id == node.id
          end.map(&:target_id)
        end
        private_class_method :entry_for, :fields_of, :reference_ids

        # @param entries [Array<Hash>, nil] see {.entries}
        # @param positions [Hash] participant id to its x/center_x
        # @param font_size [Numeric] note text size
        # @param frames [FramePlacement] frame room the notes sit between
        # @param rows [MessageRows] height the messages' extra lines add
        def initialize(entries, positions, font_size:,
                       frames: FramePlacement.new, rows: NO_ROWS)
          @entries = entries || []
          @positions = positions
          @font_size = font_size
          @frames = frames
          @rows = rows
        end

        # @return [Array<Note>] placed notes; ones naming no known
        #   participant are left out
        def notes
          @notes ||= pairs.map(&:last)
        end

        # @param from [Integer] source order of the opening frame edge
        # @param to [Integer] source order of the closing frame edge
        # @return [Array<Numeric>, nil] left and right edge of the notes
        #   written between the two, nil when there are none
        def x_range(from, to)
          inside = notes_between(from, to)
          return if inside.empty?

          [inside.map(&:x).min, inside.map { |n| n.x + n.width }.max]
        end

        # @return [Numeric] height all note slots add to the diagram
        def total_height
          slots.sum
        end

        # @param index [Integer] message index
        # @return [Numeric] how far the note slots above it push it down
        def shift_for(index)
          @entries.each_index.sum do |at|
            @entries[at][:message_index] <= index ? slots[at] : 0
          end
        end

        # @param index [Integer] message index
        # @param order [Integer] source order of a frame edge
        # @return [Numeric] height of the note slots at `index` that
        #   come before that edge in the source
        def slots_before(index, order)
          @entries.each_index.sum do |at|
            entry = @entries[at]
            at_index = entry[:message_index] == index
            at_index && entry[:order] < order ? slots[at] : 0
          end
        end

        # @return [Numeric] how far the left-most note reaches past the
        #   left margin, 0 when none does
        def overhang
          left = notes.map(&:x).min
          return 0 unless left && left < Geometry::DIAGRAM_MARGIN_X

          Geometry::DIAGRAM_MARGIN_X - left
        end

        # @return [Numeric] the right-most x any note reaches
        def right_edge
          notes.map { |note| note.x + note.width }.max || 0
        end

        private

        def notes_between(from, to)
          inside = pairs.select do |entry, _note|
            entry[:order] > from && entry[:order] < to
          end
          inside.map(&:last)
        end

        def pairs
          @pairs ||= @entries.each_index.filter_map do |index|
            note = build_note(index)
            [@entries[index], note] if note
          end
        end

        def build_note(index)
          centers = centers_of(@entries[index])
          return if centers.empty?

          place(index, boxes.fetch(index))
        end

        def centers_of(entry)
          entry[:participant_ids].filter_map do |id|
            @positions.dig(id, :center_x)
          end
        end

        def place(index, box)
          top = top_of(index)
          Note.new(x: box.left, y: top, width: box.width,
                   height: height(box.lines),
                   lines: line_labels(box.lines, box.left + (box.width / 2),
                                      top))
        end

        def boxes
          @boxes ||= @entries.map { |entry| box_for(entry) }
        end

        def box_for(entry)
          NoteBox.new(entry, centers_of(entry), size: @font_size,
                                                wrap: @rows.wrap?,
                                                actor_width: actor_width(entry))
        end

        def actor_width(entry)
          position = @positions[entry[:participant_ids].first] || {}
          return NoteBox::MIN_WIDTH unless position[:x] && position[:center_x]

          2 * (position[:center_x] - position[:x])
        end

        def line_height
          (@font_size * LINE_SPACING).round
        end

        def height(lines)
          (lines.length * line_height) + PADDING
        end

        def slots
          @slots ||= boxes.map { |box| height(box.lines) + SLOT_GAP }
        end

        def top_of(index)
          own = @entries[index][:message_index]
          above = @entries.first(index).each_index.sum do |at|
            @entries[at][:message_index] <= own ? slots[at] : 0
          end
          FIRST_ROW + (own * ROW_SPACING) + above + TOP_GAP +
            @rows.extra_before(own) +
            frame_offset(own, @entries[index][:order])
        end

        def frame_offset(own, order)
          lead = @frames.lead(own, order)
          @frames.top_inset + @frames.row_shift(own - 1) + lead +
            (lead.zero? ? 0 : TOP_GAP)
        end

        def line_labels(lines, center, top)
          lines.each_with_index.map do |line, row|
            Label.new(text: line, x: center, font_size: @font_size,
                      y: top + (PADDING / 2) + (line_height * (row + 0.5)))
          end
        end
      end
    end
  end
end
