# frozen_string_literal: true

require_relative "model"

module Sirena
  module IR
    class PropertySet < Model
      TOKEN = /\A[a-z][a-z0-9_]*\z/
      PRIVATE_SPELLINGS = %w[mermaid plantuml puml].freeze

      attribute :source_marker, :string
      attribute :target_marker, :string
      attribute :weight, :float

      private

      def semantic_errors
        marker_errors + weight_errors
      end

      def marker_errors
        %i[source_marker target_marker].filter_map do |name|
          marker = public_send(name)
          next if marker.nil? || normalized_marker?(marker)

          message = "#{name} must be a notation-neutral snake_case token"
          validation_error(message)
        end
      end

      def normalized_marker?(marker)
        marker.match?(TOKEN) &&
          PRIVATE_SPELLINGS.none? { |word| marker.include?(word) }
      end

      def weight_errors
        return [] if weight.nil? || (weight.finite? && !weight.negative?)

        [validation_error("weight must be finite and nonnegative")]
      end
    end
  end
end
