# frozen_string_literal: true

require_relative "item"
require_relative "scalar"

module Sirena
  module IR
    class DataValue < Item
      attribute :dimension_id, :string
      attribute :series_id, :string
      attribute :value, Scalar

      private

      def semantic_errors
        super + reference_errors + value_errors
      end

      def reference_errors
        references = { dimension_id: dimension_id, series_id: series_id }
        references.filter_map do |name, reference|
          next unless reference == ""

          validation_error("#{name} must be nonempty when present")
        end
      end

      def value_errors
        return [] if value&.valid?

        [validation_error("value must be a valid Scalar")]
      end
    end
  end
end
