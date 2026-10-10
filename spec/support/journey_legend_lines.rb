# frozen_string_literal: true

# Wrapped legend lines of one actor name, and their rendered widths.
module JourneyLegendLines
  module_function

  def of(name)
    Sirena::Layout::UserJourneyLegend.new([name]).rows.first[3]
  end

  def width(line)
    Sirena::TextMeasurement.measure(line, font_size: 16)[:width]
  end
end
