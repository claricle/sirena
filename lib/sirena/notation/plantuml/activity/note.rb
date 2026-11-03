# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Activity
        # A note drawn beside the node it follows.
        class Note
          # @return [Symbol] :left or :right
          attr_reader :side
          # @return [String] the note text, lines separated by newlines
          attr_reader :text

          def initialize(side:, text:)
            @side = side
            @text = text
          end

          # @return [Array<String>]
          def lines
            text.split("\n")
          end
        end
      end
    end
  end
end
