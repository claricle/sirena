# frozen_string_literal: true

module Sirena
  module Layout
    # Reads the note records an IR graph carries for a class diagram.
    module ClassDiagramNotes
      Note = Struct.new(:text, :target_id, keyword_init: true)

      module_function

      # @param graph [IR::Graph] a class diagram graph
      # @return [Array<Note>] the notes in source order
      def call(graph)
        children = graph.nodes.group_by(&:parent_id)
        graph.nodes.select { |node| node.role == "note" }.map do |node|
          target = Array(children[node.id]).find { |n| n.role == "target" }
          Note.new(text: node.label, target_id: target&.label)
        end
      end
    end
  end
end
