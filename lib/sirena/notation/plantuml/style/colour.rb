# frozen_string_literal: true

require_relative "colour_names"

module Sirena
  module Notation
    module PlantUML
      module Style
        # Reads a PlantUML colour (`#red`, `LightYellow`, `#F80`, `#a1b2c3`,
        # `#white|red` for a gradient) as the `#RRGGBB` PlantUML writes into
        # its SVG, or "none" for `transparent`.
        module Colour
          extend self

          HEX = /\A\h{3}(?:\h{3})?\z/
          GRADIENT = /[|\\\/-]/
          private_constant :HEX, :GRADIENT

          # @param text [String] the colour, with or without its `#`
          # @return [String, nil] the hex colour, "none", or nil when the
          #   text names no colour; a gradient reads as its first colour
          def resolve(text)
            word = text.to_s.strip.delete_prefix("#").split(GRADIENT).first
            return if word.nil? || word.empty?
            return "none" if word.casecmp?("transparent")
            return expand(word) if HEX.match?(word)

            ColourNames::TABLE[word.downcase]
          end

          private

          def expand(digits)
            digits = digits.gsub(/\h/) { |digit| digit * 2 } if digits.size == 3
            "##{digits.upcase}"
          end
        end
      end
    end
  end
end
