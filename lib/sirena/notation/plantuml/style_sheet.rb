# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      # What a `<style>` block sets: the canvas `background` and, for each
      # Caption kind, a Hash with any of :background, :colour and :size.
      class StyleSheet
        EMPTY_RULE = {}.freeze

        attr_reader :background

        def initialize(background: nil, rules: {})
          @background = background
          @rules = rules
          freeze
        end

        # @param kind [Symbol] a Caption kind
        # @return [Hash] the properties the block set, possibly none
        def rule(kind)
          @rules.fetch(kind, EMPTY_RULE)
        end
      end
    end
  end
end
