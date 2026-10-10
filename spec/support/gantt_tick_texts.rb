# frozen_string_literal: true

# Dates Sirena::Layout::GanttTicks picks for a span, as YYYY-MM-DD text.
module GanttTickTexts
  module_function

  DAY = 86_400

  def for(first_day, days, interval = nil)
    start = Time.utc(*first_day)
    stop = start + (days * DAY)
    Sirena::Layout::GanttTicks.times(start, stop, interval)
      .map { |tick| tick.strftime("%Y-%m-%d %H") }
  end

  def summary(first_day, days, interval = nil)
    ticks = self.for(first_day, days, interval)
    [ticks.first, ticks.last, ticks.size]
  end
end
