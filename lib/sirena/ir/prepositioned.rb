# frozen_string_literal: true

require_relative "item"
require_relative "integrity"
require_relative "prepositioned_item"
require_relative "edge"

module Sirena
  module IR
    class Prepositioned < Item
      attribute :items, PrepositionedItem, collection: true, default: -> { [] }
      attribute :connections, Edge, collection: true, default: -> { [] }

      private

      def semantic_errors
        members = items + connections
        super +
          Integrity.unique_id_errors([self] + members) +
          Integrity.parent_errors(members, parents: items) +
          Integrity.endpoint_errors(connections, endpoints: items)
      end
    end
  end
end
