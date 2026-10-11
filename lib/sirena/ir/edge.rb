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
        super.concat(missing_id_errors, rank_span_errors)
      end

      def missing_id_errors
        { "source_id" => source_id, "target_id" => target_id }
          .filter_map do |name, value|
          next unless value.nil? || value.empty?

          validation_error("#{name} must be nonempty")
        end
      end

      def rank_span_errors
        return [] unless minimum_rank_span && !minimum_rank_span.positive?

        [validation_error("minimum_rank_span must be a positive integer")]
      end
    end
  end
end
