# frozen_string_literal: true

require_relative "model"
require_relative "scalar"

module Sirena
  module IR
    class Placement < Model
      DIMENSION = /\A[a-z][a-z0-9_]*\z/

      attribute :dimension, :string
      attribute :ordinal, :integer
      attribute :value, Scalar
      attribute :span, Scalar

      private

      def semantic_errors
        dimension_errors + ordinal_errors + value_errors + span_errors
      end

      def dimension_errors
        return [] if dimension&.match?(DIMENSION)

        [validation_error("dimension must be a nonempty snake_case token")]
      end

      def ordinal_errors
        return [] if ordinal && !ordinal.negative?

        [validation_error("ordinal must be a nonnegative Integer")]
      end

      def value_errors
        return [] if value&.valid?

        [validation_error("value must be a valid Scalar")]
      end

      def span_errors
        return [] if span.nil? || span.valid?

        [validation_error("span must be a valid Scalar")]
      end
    end
  end
end
