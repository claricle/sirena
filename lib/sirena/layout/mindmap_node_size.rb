# frozen_string_literal: true

require_relative "../text_measurement"

module Sirena
  module Layout
    # The box mmdc draws around a mindmap label. mmdc measures the label at
    # 16px, wraps it at 200px, stacks 24px lines, and pads that text box per
    # shape. Hexagon, bang and cloud sizes are linear fits to the mmdc
    # references (one, three and two measured labels), not mmdc's own rule.
    class MindmapNodeSize
      FONT_SIZE = 16
      LINE_HEIGHT = 24
      MAX_TEXT_WIDTH = 200
      BREAK = %r{<br\s*/?>|\r?\n}i

      # Each entry maps the text box (width, height) to the node box.
      SHAPES = {
        "default" => ->(wide, high) { [wide + 40, high + 10] },
        "square" => ->(wide, high) { [wide + 40, high + 20] },
        "round" => ->(wide, high) { [wide + 30, high + 30] },
        "circle" => lambda { |wide, high|
          [[wide, high].max + 20] * 2
        },
        "hexagon" => ->(wide, high) { [wide + 68, high + 20] },
        "bang" => ->(wide, high) { [(wide * 1.25) + 62.4, high + 56] },
        "cloud" => lambda { |wide, _high|
          [(wide * 0.74) + 48.5, (wide * 0.49) + 38.3]
        },
      }.freeze

      # @param label [String] node label, possibly with line breaks
      # @param shape [String] mindmap node shape
      # @return [Hash] :width, :height and the wrapped :lines
      def self.call(label, shape)
        new(label).call(shape)
      end

      def initialize(label)
        @lines = label.to_s.split(BREAK).map(&:strip).reject(&:empty?)
        @lines = [""] if @lines.empty?
      end

      def call(shape)
        rule = SHAPES.fetch(shape.to_s, SHAPES["default"])
        wide, high = rule.call(text_width, text_height)
        { width: wide.to_f, height: high.to_f, lines: wrapped }
      end

      private

      def wrapped
        @wrapped ||= @lines.flat_map { |line| wrap(line) }
      end

      def wrap(line)
        return [line] if measure(line) <= MAX_TEXT_WIDTH

        line.split.each_with_object([]) { |word, rows| add_word(rows, word) }
      end

      def add_word(rows, word)
        joined = "#{rows.last} #{word}"
        if rows.any? && measure(joined) <= MAX_TEXT_WIDTH
          rows[-1] = joined
        else
          rows << word
        end
      end

      def text_width
        widest = wrapped.map { |line| measure(line) }.max
        wrapped.length > @lines.length ? [widest, MAX_TEXT_WIDTH].max : widest
      end

      def text_height
        wrapped.length * LINE_HEIGHT
      end

      def measure(text)
        TextMeasurement.measure(text, font_size: FONT_SIZE)[:width]
      end
    end
  end
end
