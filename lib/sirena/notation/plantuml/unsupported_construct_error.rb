# frozen_string_literal: true

require_relative "../../error"

module Sirena
  module Notation
    module PlantUML
      # Raised for PlantUML that is valid or invalid but outside the subset
      # this notation reads. A Sirena::Error, so the engine propagates it
      # unwrapped.
      class UnsupportedConstructError < Sirena::Error
        # Longest stretch of the offending line the message quotes.
        EXCERPT_LIMIT = 60
        private_constant :EXCERPT_LIMIT

        # @return [String] what was refused, e.g. "enum" or "note"
        attr_reader :construct

        # @return [Integer] 1-based line of the construct
        attr_reader :line

        def initialize(construct:, line:, text:)
          @construct = construct
          @line = line
          super("PlantUML #{construct} is not yet supported " \
                "(line #{line}): #{excerpt(text).inspect}")
        end

        private

        def excerpt(text)
          return text if text.length <= EXCERPT_LIMIT

          "#{text[0, EXCERPT_LIMIT - 3]}..."
        end
      end
    end
  end
end
