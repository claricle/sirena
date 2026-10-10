# frozen_string_literal: true

module Sirena
  module Renderer
    # Reads the twelve section colours of mermaid's default theme from the
    # theme: card fill, text colour and the rule under each card.
    module TimelinePalette
      # @param colors [Theme::ColorPalette] the theme's colours
      # @param index [Integer] section number, counted from 0
      # @return [Array<String>] [fill, text, rule] colours
      def self.for(colors, index)
        %i[timeline_fill timeline_text timeline_rule].map do |name|
          colors.palette(name, index)
        end
      end
    end
  end
end
