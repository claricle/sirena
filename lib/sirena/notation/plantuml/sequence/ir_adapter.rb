# frozen_string_literal: true

require_relative "../../../ir"
require_relative "../ir_adapter/sink"
require_relative "ir_adapter/fills"
require_relative "ir_adapter/participants"
require_relative "ir_adapter/settings"
require_relative "ir_adapter/messages"
require_relative "ir_adapter/blocks"
require_relative "ir_adapter/items"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # Maps the private sequence Diagram to a notation-neutral IR::Graph:
        # participants and boxes first, then one node per item in source
        # order. A message is a node plus an edge between its participant
        # nodes, and every other fact is a child node. {IRReader} is the
        # inverse; layout still owns measuring and placing.
        module IRAdapter
          module_function

          # @param diagram [Diagram] a parsed sequence diagram
          # @return [IR::Graph]
          def call(diagram)
            sink = PlantUML::IRAdapter::Sink.new
            ids = Participants.call(diagram, sink)
            Settings.call(diagram, sink)
            Items.call(diagram, sink, ids)
            IR::Graph.new(id: "sequence_diagram", role: "sequence_diagram",
                          nodes: sink.nodes, edges: sink.edges)
          end
        end
      end
    end
  end
end
