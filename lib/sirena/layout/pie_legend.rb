# frozen_string_literal: true

require_relative "pie_legend_entry"
require_relative "../text_measurement"

module Sirena
  module Layout
    # Lays out the legend column of a pie chart, right of the pie.
    class PieLegend
      LEFT = 460
      ROW_HEIGHT = 22
      SWATCH = 18
      TEXT_GAP = 4
      RIGHT_MARGIN = 20

      def initialize(center_y:, font_size:)
        @center_y = center_y
        @font_size = font_size
      end

      # Mermaid captions a row with the label, plus " [value]" under showData.
      def entries(slices, show_data)
        top = @center_y - (slices.length * ROW_HEIGHT / 2.0)
        slices.each_with_index.map do |slice, index|
          entry(caption(slice, show_data), index, top + (index * ROW_HEIGHT))
        end
      end

      def width(entries)
        return 0 if entries.empty?

        widest = entries.map { |entry| text_width(entry.text) }.max
        LEFT + SWATCH + TEXT_GAP + widest + RIGHT_MARGIN
      end

      private

      def entry(text, index, row_y)
        PieLegendEntry.new(text: text, color_index: index, x: LEFT, y: row_y,
                           font_size: @font_size)
      end

      def caption(slice, show_data)
        return slice[:label].to_s unless show_data

        "#{slice[:label]} [#{format_value(slice[:value])}]"
      end

      def format_value(value)
        value.to_s.delete_suffix(".0")
      end

      def text_width(text)
        Sirena::TextMeasurement.measure(text, font_size: @font_size)[:width]
      end
    end
  end
end
