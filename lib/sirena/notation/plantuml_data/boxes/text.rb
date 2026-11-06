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
          # A line of text is this many times its font size tall.
          LINE_RATIO = 1.1778
          private_constant :LITERAL, :CODE_POINT, :LINE_RATIO

          # @return [String] the text as it reads, with creole and HTML
          #   emphasis removed
          def plain(text)
            runs(text).map(&:text).join
          end

          # Gives an SVG text element a cell's content, styled by its markup.
          def assign(element, text)
            creole.assign(element, text, literal: LITERAL, inline: true)
          end

          # @return [Array<Creole::Run>] the styled pieces of a cell's text
          def runs(text)
            creole.parse(text.to_s, literal: LITERAL, inline: true)
          end

          # @return [Float] how many points taller than a plain line the
          #   text's largest `<size:..>` makes its row
          def growth(text)
            sizes = runs(text).map { |piece| piece_size(piece) }
            [((sizes.max || FONT_SIZE) - FONT_SIZE) * LINE_RATIO, 0.0].max
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
            wide = runs(text).sum do |piece|
              TextMeasurement.measure(piece.text,
                                      font_size: piece_size(piece))[:width]
            end
            bold ? wide * 1.04 : wide
          end

          private

          def piece_size(piece)
            size = piece.style[:size]
            size&.match?(/\A\d+\z/) ? size.to_i : FONT_SIZE
          end

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
