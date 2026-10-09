# frozen_string_literal: true

require_relative "item"
require_relative "integrity"
require_relative "dimension"
require_relative "series"
require_relative "data_value"

module Sirena
  module IR
    class Data < Item
      attribute :dimensions, Dimension, collection: true, default: -> { [] }
      attribute :series, Series, collection: true, default: -> { [] }
      attribute :values, DataValue, collection: true, default: -> { [] }
      attribute :items, Item, collection: true, default: -> { [] }

      private

      def semantic_errors
        super +
          Integrity.unique_id_errors([self] + members) +
          Integrity.parent_errors(members) +
          reference_errors
      end

      def members
        dimensions + series + values + items
      end

      def reference_errors
        Integrity.reference_errors(
          values,
          dimensions: dimensions,
          series: series,
        )
      end
    end
  end
end
