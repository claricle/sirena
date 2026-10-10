# frozen_string_literal: true

require_relative "class_note"

module Sirena
  module Layout
    # Turns the notes of a class diagram into grid nodes, and back into
    # positioned ClassNote objects once the grid has placed them.
    class ClassNoteNodes
      LINE_HEIGHT = 24
      VERTICAL_PADDING = 12
      PADDING = 12

      # @param font_size [Numeric] the note text size
      # @param measure [#call] given text and font size, returns its width
      # @param connect [#call] given two boxes, returns the point on the
      #   first box's edge facing the second
      def initialize(font_size:, measure:, connect:)
        @font_size = font_size
        @measure = measure
        @connect = connect
      end

      # @param notes [Array<Diagram::ClassNote>]
      # @return [Array<Hash>] one grid node per note
      def nodes(notes)
        notes.each_with_index.map { |note, index| node(note, index) }
      end

      # @param node [Hash] a node made by #nodes
      def note?(node)
        node.dig(:metadata, :note) == true
      end

      # @param nodes [Array<Hash>] placed note nodes
      # @param classes [Hash{String => Hash}] placed class nodes by id
      # @return [Array<ClassNote>]
      def notes(nodes, classes)
        nodes.map { |node| note(node, classes[node[:metadata][:target_id]]) }
      end

      private

      def node(note, index)
        lines = ClassNote.lines_of(note.text)
        {
          id: "note:#{index}",
          width: width(lines),
          height: (lines.size * LINE_HEIGHT) + VERTICAL_PADDING,
          metadata: { note: true, text: note.text, target_id: note.target_id },
        }
      end

      def width(lines)
        lines.map { |line| @measure.call(line, @font_size) }.max + PADDING
      end

      def note(node, target)
        ClassNote.new(
          id: node[:id].delete_prefix("note:"), text: node[:metadata][:text],
          target_id: node[:metadata][:target_id],
          x: node[:x], y: node[:y], width: node[:width], height: node[:height],
          **link(node, target)
        )
      end

      def link(node, target)
        return {} unless target

        from = @connect.call(node, target)
        to = @connect.call(target, node)
        { link_x1: from[:x], link_y1: from[:y],
          link_x2: to[:x], link_y2: to[:y] }
      end
    end
  end
end
