# frozen_string_literal: true

require_relative "../../text_measurement"
require_relative "../../diagram/sequence_text"

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
          details = graph.nodes.select { |item| item.parent_id == node.id }
          fields = details.to_h { |item| [item.role, item.label] }
          {
            text: node.label.to_s, position: fields["note_position"],
            message_index: fields["message_index"].to_i,
            participant_ids: graph.edges.select do |edge|
              edge.role == "note_reference" && edge.source_id == node.id
            end.map(&:target_id)
          }
        end
        private_class_method :entry_for

        # @param entries [Array<Hash>, nil] see {.entries}
        # @param positions [Hash] participant id to its x/center_x
        # @param font_size [Numeric] note text size
        def initialize(entries, positions, font_size:)
          @entries = entries || []
          @positions = positions
          @font_size = font_size
        end

        # @return [Array<Note>] placed notes; ones naming no known
        #   participant are left out
        def notes
          @notes ||= @entries.each_index.filter_map do |index|
            build_note(index)
          end
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

        # @return [Numeric] the right-most x any note reaches
        def right_edge
          notes.map { |note| note.x + note.width }.max || 0
        end

        private

        def build_note(index)
          entry = @entries[index]
          centers = entry[:participant_ids].filter_map do |id|
            @positions.dig(id, :center_x)
          end
          return if centers.empty?

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
          FIRST_ROW + (own * ROW_SPACING) + above + TOP_GAP
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
