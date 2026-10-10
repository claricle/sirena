# frozen_string_literal: true

require "date"

module Sirena
  module Layout
    # Adds a Gantt duration such as "30d", "20h" or "1.5w" to a time the
    # way mermaid does: d, h, m, s and ms are fixed lengths, w is seven
    # days, M and y move the calendar. A bare number counts days.
    #
    # Times are UTC, so a day is always 86400 seconds.
    module GanttDuration
      PATTERN = /\A(\d+(?:\.\d+)?)(ms|[Mdhmswy])?\z/
      SECONDS = {
        "ms" => 0.001, "s" => 1, "m" => 60, "h" => 3600,
        "d" => 86_400, "w" => 7 * 86_400, nil => 86_400
      }.freeze
      MONTHS = { "M" => 1, "y" => 12 }.freeze

      def self.add(time, text)
        match = PATTERN.match(text.to_s.strip)
        return time unless match

        value = match[1].to_f
        unit = match[2]
        return add_months(time, value * MONTHS.fetch(unit)) if MONTHS[unit]

        time + (value * SECONDS.fetch(unit))
      end

      def self.add_months(time, months)
        whole = months.to_i
        shifted = (time.to_date >> whole).to_time.utc
        shifted + (time - time.to_date.to_time.utc)
      end
      private_class_method :add_months
    end
  end
end
