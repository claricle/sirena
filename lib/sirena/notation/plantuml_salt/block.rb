# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUMLSalt
      # A `{...}` group. `modifier` is what followed the brace (`T!`, `#`,
      # `+`, an empty string for a plain group).
      class Block
        attr_reader :modifier, :rows

        def initialize(modifier)
          @modifier = modifier
          @rows = []
        end

        # @return [Boolean] whether rows nest by leading `+` marks
        def tree?
          modifier.include?("T")
        end

        # @return [Boolean] a line around every cell
        def grid?
          modifier.include?("#") || (modifier.include?("!") && tree?)
        end

        # @return [Boolean] a line between rows only
        def row_lines?
          modifier.include?("-")
        end

        # @return [Boolean] a line between columns only
        def column_lines?
          modifier.include?("!") && !tree?
        end

        # @return [Boolean] a frame around the block
        def border?
          modifier.include?("+") || grid?
        end
      end
    end
  end
end
