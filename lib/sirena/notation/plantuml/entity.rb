# frozen_string_literal: true

require_relative "node_graph"

module Sirena
  module Notation
    module PlantUML
      # The PlantUML entity-relationship diagram: `entity Name { fields }`
      # blocks joined by crow's foot links such as `a }|..|| b`. Dispatched
      # to from {PlantUML.parse}. A bare `entity X` with messages is a
      # sequence participant, so a source is claimed only for a block with a
      # body or a cardinality link.
      module Entity
        extend self

        BLOCK = /\Aentity\s.*\{\z/i
        private_constant :BLOCK

        # @return [Boolean] whether the source reads as an entity diagram
        def entity?(source)
          lines = NodeGraph.lines_of(source)
          outside = outside_blocks(lines)
          outside.none? { |line| foreign?(line) } &&
            outside.any? do |line|
              line.match?(BLOCK) || line.match?(NodeGraph::References::ER_EDGE)
            end
        end

        # @return [Notation::Parsed]
        def parse(source)
          NodeGraph.parsed(source, type: :entity_diagram,
                                   direction: :top_to_bottom,
                                   default_kind: :entity)
        end

        private

        def foreign?(line)
          NodeGraph::FOREIGN.match?(line) && !line.match?(/\Aentity\b/i)
        end

        # The lines that are not the fields of an entity block.
        def outside_blocks(lines)
          inside = false
          lines.select do |line|
            keep = !inside
            inside = line.match?(BLOCK) || (inside && line != "}")
            keep
          end
        end
      end
    end
  end
end
