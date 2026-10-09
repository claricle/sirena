# frozen_string_literal: true

require_relative "item"
require_relative "integrity"
require_relative "node"
require_relative "edge"

module Sirena
  module IR
    class Graph < Item
      attribute :nodes, Node, collection: true, default: -> { [] }
      attribute :edges, Edge, collection: true, default: -> { [] }

      def items
        nodes + edges
      end

      private

      def semantic_errors
        super +
          Integrity.unique_id_errors([self] + items) +
          Integrity.parent_errors(items, parents: nodes) +
          Integrity.endpoint_errors(edges, endpoints: nodes)
      end
    end
  end
end
