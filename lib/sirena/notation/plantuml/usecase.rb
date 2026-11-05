# frozen_string_literal: true

require_relative "node_graph"

module Sirena
  module Notation
    module PlantUML
      # The PlantUML use case diagram: actors, use cases and the links
      # between them. Dispatched to from {PlantUML.parse}.
      module Usecase
        extend self

        # Lines only a use case diagram has: `:Actor:`, `(Use case)` and the
        # `usecase` keyword. `(A, B)` is a class diagram's association class.
        PAIR = /\(\s*\w+\s*,\s*\w+\s*\)/
        MARKER = /\A(?:usecase\s|:[^:;]+:(?:\s|\z)|
                  \((?!#{PAIR.source[2..]})[^()*]+\)(?:\s|\z))/xi
        private_constant :PAIR, :MARKER

        # @return [Boolean] whether the source reads as a use case diagram
        def usecase?(source)
          lines = NodeGraph.lines_of(source)
          lines.none? { |line| NodeGraph::FOREIGN.match?(line) } &&
            lines.any? { |line| MARKER.match?(line) }
        end

        # @return [Notation::Parsed]
        def parse(source)
          NodeGraph.parsed(source, type: :usecase_diagram,
                                   direction: :top_to_bottom,
                                   default_kind: :actor)
        end
      end
    end
  end
end
