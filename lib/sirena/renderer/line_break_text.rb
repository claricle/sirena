# frozen_string_literal: true

require_relative "../svg/text"
require_relative "../svg/tspan"

module Sirena
  module Renderer
    # Fills an Svg::Text from label text, turning a raw HTML line break
    # (<br>, <br/>, <br />) into a new line as mmdc does.
    module LineBreakText
      BREAK = %r{<br\s*/?>}i

      module_function

      # @param text [Svg::Text] element to fill
      # @param raw [String] label text, possibly holding line breaks
      # @return [Svg::Text] the same element
      def fill(text, raw)
        lines = raw.to_s.split(BREAK, -1).map(&:strip)
        return text.tap { text.content = raw } if lines.one?

        text.tspans = lines.each_with_index.map do |line, index|
          line_run(line, text.x, index)
        end
        text
      end

      def line_run(line, left, index)
        Svg::Tspan.new.tap do |run|
          run.x = left
          run.line_shift = 1 if index.positive?
          run.content = line
        end
      end
    end
  end
end
