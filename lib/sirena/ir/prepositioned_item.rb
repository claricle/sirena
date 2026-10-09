# frozen_string_literal: true

require_relative "item"
require_relative "placement"

module Sirena
  module IR
    class PrepositionedItem < Item
      attribute :placements, Placement, collection: true, default: -> { [] }

      private

      def semantic_errors
        errors = super
        if placements.empty?
          errors << validation_error("placements must not be empty")
        end
        dimensions = placements.map(&:dimension)
        if dimensions.uniq.length != dimensions.length
          errors << validation_error("placement dimensions must be unique")
        end
        errors
      end
    end
  end
end
