# frozen_string_literal: true

require_relative "colour"

module Sirena
  module Notation
    module PlantUML
      module Style
        # Reads the colour a declaration carries on its own line:
        # `#pink`, `#pink;line:blue;line.dashed;text:green`, `##blue`,
        # `##[dashed]blue`, `#pink|white` (a gradient reads as its first
        # colour).
        module Inline
          extend self

          LINE_STYLES = { "dashed" => "7,7", "dotted" => "1,3",
                          "bold" => nil, "plain" => nil }.freeze
          LINE_ONLY = /\A##(?:\[(\w+)\])?(\S+)\z/
          private_constant :LINE_STYLES, :LINE_ONLY

          # @param text [String] the colour as written, `#` included
          # @return [Hash] any of :background, :border, :line_style,
          #   :font_colour; empty when the text names no colour
          def parse(text)
            if (match = LINE_ONLY.match(text))
              return line_only(match)
            end

            first, *parts = text.split(";")
            properties = { background: Colour.resolve(first) }.compact
            parts.each { |part| property(part, properties) }
            properties
          end

          private

          def line_only(match)
            { border: Colour.resolve(match[2]),
              line_style: LINE_STYLES[match[1]] }.compact
          end

          def property(part, properties)
            key, value = part.split(":", 2)
            case key.downcase
            when "line" then properties[:border] = Colour.resolve(value)
            when "text" then properties[:font_colour] = Colour.resolve(value)
            when "line.dashed", "line.dotted"
              properties[:line_style] = LINE_STYLES[key.split(".").last]
            end
            properties.compact!
          end
        end
      end
    end
  end
end
