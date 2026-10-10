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

        fill_lines(text, lines)
      end

      # @param text [Svg::Text] element to fill
      # @param lines [Array<String>] already-split lines, at least two
      # @param pitch [Numeric, nil] user units between baselines; nil
      #   leaves the spacing to Svg::Text (1.2 x font size)
      # @return [Svg::Text] the same element
      def fill_lines(text, lines, pitch: nil)
        text.tspans = lines.each_with_index.map do |line, index|
          line_run(line, text, index, pitch)
        end
        text
      end

      def line_run(line, text, index, pitch)
        Svg::Tspan.new.tap do |run|
          run.x = text.x
          place(run, text, index, pitch)
          run.content = line
        end
      end

      def place(run, text, index, pitch)
        return unless index.positive?

        if pitch
          run.y = Svg::Numbers.read(text.y) + (index * pitch)
        else
          run.line_shift = 1
        end
      end
    end
  end
end
