# frozen_string_literal: true

require_relative "model"

module Sirena
  module IR
    class Scalar < Model
      attribute :text, :string
      attribute :number, :float
      attribute :boolean, :boolean

      def value
        [text, number, boolean].find { |candidate| !candidate.nil? }
      end

      private

      def semantic_errors
        return [] if [text, number, boolean].one? { |value| !value.nil? }

        [validation_error("scalar must contain exactly one value")]
      end
    end
  end
end
