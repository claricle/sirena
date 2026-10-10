# frozen_string_literal: true

require_relative "../../ir_reader/index"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        module IRReader
          # The shared node lookup, plus the edges that belong to one item.
          class Index < PlantUML::IRReader::Index
            def initialize(graph)
              super
              @owned = graph.edges.group_by(&:parent_id)
            end

            # @return [Array<IR::Edge>] the edges `node` owns, in graph order
            def edges_of(node)
              @owned.fetch(node.id, [])
            end

            # @return [Array<String>] the participant ids `node` points at
            def target_names(node)
              edges_of(node).map { |edge| name(edge.target_id) }
            end

            # @return [String] the id a message names for a participant node
            def name(node_id)
              detail(node(node_id), "name")
            end
          end
        end
      end
    end
  end
end
