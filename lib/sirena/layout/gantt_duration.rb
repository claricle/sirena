# frozen_string_literal: true

require "date"

module Sirena
  module Layout
    # Adds a Gantt duration such as "30d", "20h" or "1.5w" to a time the
    # way mermaid does: h, m, s and ms are fixed lengths, d and w round
    # to whole days, and M and y move the calendar by whole units. A bare
    # number counts days for compatibility with direct model callers.
    #
    # Times are UTC, so a day is always 86400 seconds.
    module GanttDuration
      PATTERN = /\A(\d+(?:\.\d+)?)(ms|[Mdhmswy])?\z/
      SECONDS = {
        "ms" => 0.001, "s" => 1, "m" => 60, "h" => 3600,
        nil => 86_400
      }.freeze
      DAYS = { "d" => 1, "w" => 7 }.freeze
      MONTHS = { "M" => 1, "y" => 12 }.freeze

      def self.add(time, text)
        duration = parse(text)
        return time unless duration

        add_value(time, *duration)
      end

      def self.parse(text)
        match = PATTERN.match(text.to_s.strip)
        [match[1].to_f, match[2]] if match
      end

      def self.add_value(time, value, unit)
        return add_months(time, value.to_i * MONTHS.fetch(unit)) if MONTHS[unit]
        return time + ((value * DAYS.fetch(unit)).round * 86_400) if DAYS[unit]

        time + (value * SECONDS.fetch(unit))
      end

      def self.add_months(time, months)
        whole = months.to_i
        shifted = (time.to_date >> whole).to_time.utc
        shifted + (time - time.to_date.to_time.utc)
      end
      private_class_method :parse, :add_value, :add_months
    end
  end
end
