# frozen_string_literal: true

require_relative "../../../text_measurement"

module Sirena
  module Notation
    module PlantUMLData
      module Boxes
        # What a cell shows for a source string, and how wide that is.
        module Text
          extend self

          FONT_SIZE = 14
          BLANK = "   "
          # JSON and YAML cells leave `__` and `""` as written, as PlantUML's
          # data diagrams do.
          LITERAL = ["__", '""'].freeze
          CODE_POINT = /<U\+(\h{4,6})>/
          private_constant :LITERAL, :CODE_POINT

          # @return [String] the text as it reads, with creole and HTML
          #   emphasis removed
          def plain(text)
            creole.parse(text.to_s, literal: LITERAL).map(&:text).join
          end

          # Gives an SVG text element a cell's content, styled by its markup.
          def assign(element, text)
            creole.assign(element, text, literal: LITERAL)
          end

          # @return [String] how a JSON or YAML scalar reads in a cell
          def scalar(value)
            case value
            when true then "☑ true"
            when false then "☐ false"
            when nil then "␀"
            else markup(value)
            end
          end

          # @return [String] how a scalar of a mixed `json` element reads: the
          #   JSON literal, with no check box
          def literal(value)
            value.nil? ? "null" : markup(value)
          end

          # @return [Float] the width of the text in the diagram's font
          def width(text, bold: false)
            wide = TextMeasurement.measure(plain(text),
                                           font_size: FONT_SIZE)[:width]
            bold ? wide * 1.04 : wide
          end

          private

          # Loaded on first use: `require "sirena"` must not define the
          # PlantUML namespace, and this module loads with it.
          def creole
            require_relative "../../plantuml/creole"
            Sirena::Notation::PlantUML::Creole
          end

          def markup(value)
            text = value.to_s.gsub(CODE_POINT) do
              [Regexp.last_match(1).hex].pack("U")
            end
            plain(text).strip.empty? ? BLANK : text.strip
          end
        end
      end
    end
  end
end
