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
          PAIRS = %w[** // "" -- ~~].freeze
          TAG = %r{</?(?:b|i|u|s|w|size|color|back|font)(?::[^>]*)?>}i
          BLANK = "   "
          private_constant :PAIRS, :TAG

          # @return [String] the text with creole and HTML emphasis removed
          def plain(text)
            PAIRS.reduce(text.to_s.gsub(TAG, "")) do |out, pair|
              out.gsub(/#{Regexp.escape(pair)}(.+?)#{Regexp.escape(pair)}/,
                       '\1')
            end.strip
          end

          # @return [String] how a JSON or YAML scalar reads in a cell
          def scalar(value)
            case value
            when true then "☑ true"
            when false then "☐ false"
            when nil then "␀"
            else plain(value).then { |s| s.empty? ? BLANK : s }
            end
          end

          # @return [String] how a scalar of a mixed `json` element reads: the
          #   JSON literal, with no check box
          def literal(value)
            value.nil? ? "null" : plain(value)
          end

          # @return [Float] the width of the text in the diagram's font
          def width(text, bold: false)
            wide = TextMeasurement.measure(text.to_s,
                                           font_size: FONT_SIZE)[:width]
            bold ? wide * 1.04 : wide
          end
        end
      end
    end
  end
end
