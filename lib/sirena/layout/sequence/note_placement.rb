# frozen_string_literal: true

require_relative "../../text_measurement"
require_relative "../../diagram/sequence_text"
require_relative "frame_placement"

module Sirena
  module Layout
    class Sequence < Base
      # Gives every note its own vertical slot between two message rows and
      # reports how far that slot pushes the later rows down.
      class NotePlacement
        LINE_BREAK = Diagram::SequenceText::LINE_BREAK
        FIRST_ROW = 60
        ROW_SPACING = 60
        TOP_GAP = 15
        SLOT_GAP = 20
        PADDING = 20
        SIDE_GAP = 25
        MIN_WIDTH = 100
        LINE_SPACING = 1.4

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
        def initialize(entries, positions, font_size:,
                       frames: FramePlacement.new)
          @entries = entries || []
          @positions = positions
          @font_size = font_size
          @frames = frames
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
          @entries.sum { |entry| slot(entry) }
        end

        # @param index [Integer] message index
        # @return [Numeric] how far the note slots above it push it down
        def shift_for(index)
          @entries.sum do |entry|
            entry[:message_index] <= index ? slot(entry) : 0
          end
        end

        # @param index [Integer] message index
        # @param order [Integer] source order of a frame edge
        # @return [Numeric] height of the note slots at `index` that
        #   come before that edge in the source
        def slots_before(index, order)
          @entries.sum do |entry|
            at_index = entry[:message_index] == index
            at_index && entry[:order] < order ? slot(entry) : 0
          end
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
          entry = @entries[index]
          centers = centers_of(entry)
          return if centers.empty?

          place(index, entry, centers)
        end

        def centers_of(entry)
          entry[:participant_ids].filter_map do |id|
            @positions.dig(id, :center_x)
          end
        end

        def place(index, entry, centers)
          lines = text_lines(entry)
          width, left = box_horizontal(entry[:position], centers, lines)
          top = top_of(index)
          Note.new(x: left, y: top, width: width, height: height(lines),
                   lines: line_labels(lines, left + (width / 2), top))
        end

        def text_lines(entry)
          entry[:text].split(LINE_BREAK, -1)
        end

        def line_height
          (@font_size * LINE_SPACING).round
        end

        def height(lines)
          (lines.length * line_height) + PADDING
        end

        def slot(entry)
          height(text_lines(entry)) + SLOT_GAP
        end

        def top_of(index)
          own = @entries[index][:message_index]
          above = @entries.first(index).sum do |entry|
            entry[:message_index] <= own ? slot(entry) : 0
          end
          FIRST_ROW + (own * ROW_SPACING) + above + TOP_GAP +
            frame_offset(own, @entries[index][:order])
        end

        def frame_offset(own, order)
          lead = @frames.lead(own, order)
          @frames.top_inset + @frames.row_shift(own - 1) + lead +
            (lead.zero? ? 0 : TOP_GAP)
        end

        def text_width(lines)
          lines.map do |line|
            TextMeasurement.measure(line, font_size: @font_size)[:width]
          end.max.to_f
        end

        def box_horizontal(position, centers, lines)
          wide = [text_width(lines) + PADDING, MIN_WIDTH].max
          case position
          when "left_of" then [wide, [centers.first - SIDE_GAP - wide, 10].max]
          when "right_of" then [wide, centers.first + SIDE_GAP]
          else over_box(centers, wide)
          end
        end

        def over_box(centers, wide)
          span = centers.max - centers.min
          width = [wide, span + (2 * SIDE_GAP)].max
          [width, ((centers.min + centers.max) / 2.0) - (width / 2)]
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
