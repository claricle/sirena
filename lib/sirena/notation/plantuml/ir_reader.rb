# frozen_string_literal: true

require_relative "diagram"
require_relative "ir_reader/index"
require_relative "ir_reader/structure"
require_relative "ir_reader/links"
require_relative "ir_reader/annotations"

module Sirena
  module Notation
    module PlantUML
      # Rebuilds the private class Diagram from the IR::Graph {IRAdapter}
      # emitted, so layout can keep measuring and placing PlantUML's own
      # boxes. Nothing outside this notation reads the Diagram.
      module IRReader
        module_function

        # @param graph [IR::Graph] a graph from {IRAdapter.call}
        # @return [Diagram]
        def call(graph)
          index = Index.new(graph)
          Diagram.new(
            classes: Structure.classes(index).freeze,
            relations: Links.relations(index).freeze,
            packages: Structure.packages(index).freeze,
            **recorded(index),
          )
        end

        def recorded(index)
          {
            junctions: Links.junctions(index).freeze,
            notes: Links.notes(index).freeze,
            directives: Annotations.directives(index).freeze,
            captions: Annotations.captions(index).freeze,
            style: Annotations.style(index),
          }
        end
      end
    end
  end
end
