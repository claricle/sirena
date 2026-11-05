# frozen_string_literal: true

require_relative "node_graph"

module Sirena
  module Notation
    module PlantUML
      # The PlantUML component and basic deployment diagram: components,
      # interfaces and deployment nodes. Dispatched to from {PlantUML.parse}.
      module Component
        extend self

        # Lines only a component or deployment diagram has. `package`,
        # `database` and `interface` are not here: classes and sequences use
        # them too.
        MARKER = /\A(?:\[[^\]]+\]|component\s|portin\s|portout\s|\(\)\s|
                   (?:node|cloud|file|folder|frame|storage|artifact|card|
                   rectangle|archimate)\s)/xi
        private_constant :MARKER

        # @return [Boolean] whether the source reads as a component diagram
        def component?(source)
          lines = NodeGraph.lines_of(source)
          lines.none? { |line| NodeGraph::FOREIGN.match?(line) } &&
            lines.any? { |line| MARKER.match?(line) }
        end

        # @return [Notation::Parsed]
        def parse(source)
          NodeGraph.parsed(source, type: :component_diagram,
                                   direction: :top_to_bottom,
                                   default_kind: :interface)
        end
      end
    end
  end
end
