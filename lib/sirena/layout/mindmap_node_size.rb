# frozen_string_literal: true

require_relative "../text_measurement"

module Sirena
  module Layout
    # The box mmdc draws around a mindmap label. mmdc measures the label at
    # 16px, wraps it at 200px, stacks lines at 1.5 times their size, and
    # pads that text box per shape. Mindmaps draw in Trebuchet MS, so their
    # browser widths use the generated Trebuchet advance table. Hexagon, bang
    # and cloud sizes are linear fits to the mmdc references, not mmdc's own
    # rule.
    class MindmapNodeSize
      FONT_SIZE = 16
      LINE_HEIGHT = 24
      LINE_HEIGHT_RATIO = LINE_HEIGHT.fdiv(FONT_SIZE)
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
      def self.call(label, shape, font_size: FONT_SIZE,
                    line_height: LINE_HEIGHT_RATIO)
        new(label, font_size, line_height).call(shape)
      end

      def initialize(label, font_size, line_height)
        @font_size = font_size
        @line_height = line_height
        @lines = label.to_s.split(BREAK).map(&:strip).reject(&:empty?)
        @lines = [""] if @lines.empty?
      end

      def call(shape)
        wide, high = dimensions(shape)
        { width: wide.to_f, height: high.to_f, lines: wrapped }
      end

      private

      def wrapped
        @wrapped ||= @lines.flat_map { |line| wrap(line) }
      end

      def dimensions(shape)
        return circle_dimensions if shape.to_s == "circle"

        SHAPES.fetch(shape.to_s, SHAPES["default"])
          .call(text_width, text_height)
      end

      def circle_dimensions
        two_lines = @font_size * @line_height * 2
        side = if text_width > two_lines
                 text_width
               else
                 text_height.clamp(text_width, two_lines)
               end
        [side + 20, side + 20]
      end

      def wrap(line)
        return [line] if measure(line) <= wrap_width

        line.split.each_with_object([]) { |word, rows| add_word(rows, word) }
      end

      def add_word(rows, word)
        joined = "#{rows.last} #{word}"
        if rows.any? && measure(joined) <= wrap_width
          rows[-1] = joined
        else
          rows << word
        end
      end

      def text_width
        widest = wrapped.map { |line| measure(line) }.max
        wrapped.length > @lines.length ? [widest, MAX_TEXT_WIDTH].max : widest
      end

      def wrap_width
        @wrap_width ||= [MAX_TEXT_WIDTH, widest_word].max
      end

      def widest_word
        @lines.flat_map(&:split).map { |word| measure(word) }.max.to_f
      end

      def text_height
        wrapped.length * @font_size * @line_height
      end

      def measure(text)
        TextMeasurement.measure_in(
          :trebuchet, text, font_size: @font_size
        )[:width]
      end
    end
  end
end
