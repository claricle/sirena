# frozen_string_literal: true

require_relative "ir_adapter/sink"
require_relative "ir_adapter/structure"
require_relative "ir_adapter/links"
require_relative "ir_adapter/annotations"

module Sirena
  module Notation
    module PlantUML
      # Maps the private class Diagram to a notation-neutral IR::Graph:
      # classes, packages, notes and association classes are nodes, members
      # and every remaining fact are child nodes, and relations, note
      # attachments and association-class ends are edges. {IRReader} is the
      # inverse; layout still owns measuring, placing and routing.
      module IRAdapter
        module_function

        # @param diagram [Diagram] a parsed class diagram
        # @return [IR::Graph]
        def call(diagram)
          sink = Sink.new
          ids = Structure.call(diagram, sink)
          Links.call(diagram, sink, ids)
          Annotations.call(diagram, sink)
          IR::Graph.new(id: "class_diagram", role: "class_diagram",
                        nodes: sink.nodes, edges: sink.edges)
        end
      end
    end
  end
end
