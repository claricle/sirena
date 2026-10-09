# frozen_string_literal: true

require_relative "item"

module Sirena
  module IR
    class Edge < Item
      attribute :source_id, :string
      attribute :target_id, :string

      private

      def semantic_errors
        errors = super
        if source_id.nil? || source_id.empty?
          errors << validation_error("source_id must be nonempty")
        end
        if target_id.nil? || target_id.empty?
          errors << validation_error("target_id must be nonempty")
        end
        errors
      end
    end
  end
end
