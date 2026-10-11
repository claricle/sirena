# frozen_string_literal: true

require_relative "item"

module Sirena
  module IR
    class Edge < Item
      attribute :source_id, :string
      attribute :target_id, :string
      attribute :minimum_rank_span, :integer

      private

      def semantic_errors
        errors = super
        if source_id.nil? || source_id.empty?
          errors << validation_error("source_id must be nonempty")
        end
        if target_id.nil? || target_id.empty?
          errors << validation_error("target_id must be nonempty")
        end
        if minimum_rank_span && !minimum_rank_span.positive?
          errors << validation_error(
            "minimum_rank_span must be a positive integer"
          )
        end
        errors
      end
    end
  end
end
