# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUMLSalt
      # A `{...}` group. `modifier` is what followed the brace (`T!`, `#`,
      # `+`, `S` for scroll bars, `/` for tabs, `^` for a titled box, an
      # empty string for a plain group); `title` is a `{^` box's heading.
      class Block
        attr_reader :modifier, :rows, :title

        def initialize(modifier, title: nil)
          @modifier = modifier
          @title = title
          @rows = []
        end

        # @return [Boolean] a frame with scroll bars (`{S`, `{SI`, `{S-`)
        def scroll?
          modifier.start_with?("S")
        end

        # @return [Boolean] a vertical scroll bar: `{S` and `{SI`
        def vertical_bar?
          scroll? && !modifier.include?("-")
        end

        # @return [Boolean] a horizontal scroll bar: `{S` and `{S-`
        def horizontal_bar?
          scroll? && !modifier.include?("I")
        end

        # @return [Boolean] a row of tabs
        def tabs?
          modifier.include?("/")
        end

        # @return [Boolean] a frame whose heading sits in its top edge
        def titled?
          !title.nil?
        end

        # @return [Boolean] whether rows nest by leading `+` marks
        def tree?
          modifier.include?("T")
        end

        # @return [Boolean] a line around every cell
        def grid?
          modifier.include?("#")
        end

        # @return [Boolean] a line between rows only
        def row_lines?
          !scroll? && modifier.include?("-")
        end

        # @return [Boolean] a line between columns only
        def column_lines?
          modifier.include?("!")
        end

        # @return [Boolean] a rule between rows (`-` or `#`)
        def row_rules?
          grid? || row_lines?
        end

        # @return [Boolean] a rule between columns (`!` or `#`)
        def column_rules?
          grid? || column_lines?
        end

        # @return [Boolean] a frame around the block
        def border?
          modifier.include?("+") || (modifier == "^" && !titled?)
        end
      end
    end
  end
end
