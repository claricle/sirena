# frozen_string_literal: true

require_relative "../diagram/class_note"

module Sirena
  module Parser
    # Collects the `note` statements of a class diagram parse tree.
    #
    # The class builder drops them, so they are read from the tree beside it.
    class ClassNotes
      LINE_BREAK = %r{<br\s*/?>}i

      # @param tree [Array<Hash>] the class diagram parse tree
      # @param diagram [Diagram::ClassDiagram] the built diagram, for the
      #   ids a `note for` can point at
      # @return [Array<Diagram::ClassNote>] the notes in source order
      def self.collect(tree, diagram)
        new(diagram).collect(tree)
      end

      def initialize(diagram)
        @ids = diagram.entities.map(&:id)
      end

      def collect(tree)
        Array(tree).filter_map do |statement|
          next unless statement.is_a?(Hash) && statement[:note_text]

          Diagram::ClassNote.new(text: note_text(statement[:note_text]),
                                 target_id: target(statement[:note_for]))
        end
      end

      private

      # mmdc renders the text as HTML: a <br> starts a new line and any
      # other tag shows as its content. A literal backslash-n stays text.
      def note_text(slice)
        text = slice.to_s.strip.sub(/\A"(.*)"\z/m, '\1')
        text.gsub(LINE_BREAK, "\n").gsub(/<[^>]*>/, "")
      end

      def target(slice)
        return unless slice

        name = slice.to_s.delete("`")
        return name if @ids.include?(name)

        matches = @ids.select { |id| id.end_with?(".#{name}") }
        matches.first if matches.one?
      end
    end
  end
end
