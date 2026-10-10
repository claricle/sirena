# frozen_string_literal: true

module Sirena
  module Renderer
    # The twelve section colours of mermaid's default theme: card fill,
    # text colour and the rule under each card, as [fill, text, rule].
    module TimelinePalette
      SECTIONS = [
        %w[#8686ff #ffffff #ffffb9], %w[#ffff78 #000000 #ababff],
        %w[#d7ff86 #000000 #d0b9ff], %w[#c286ff #ffffff #dcffb9],
        %w[#ff86ff #000000 #b9ffb9], %w[#ff86c2 #000000 #b9ffdc],
        %w[#ff8686 #000000 #b9ffff], %w[#ffc286 #000000 #b9dcff],
        %w[#c2ff86 #000000 #dcb9ff], %w[#86ffc2 #000000 #ffb9dc],
        %w[#86ffff #000000 #ffb9b9], %w[#86c2ff #000000 #ffdcb9]
      ].freeze

      # @param index [Integer] section number, counted from 0
      # @return [Array<String>] [fill, text, rule] colours
      def self.for(index)
        SECTIONS.fetch(index % SECTIONS.length)
      end
    end
  end
end
