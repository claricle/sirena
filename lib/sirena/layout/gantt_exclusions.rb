# frozen_string_literal: true

require "time"

module Sirena
  module Layout
    # Mermaid's `excludes` rule for a Gantt task end: every excluded day
    # from the day after the start up to the end pushes the end one day
    # later, so excluded days never count toward a duration.
    #
    # Handles `weekends` (Saturday and Sunday, or Friday and Saturday after
    # `weekend friday`), weekday names and specific dates.
    class GanttExclusions
      DAY = 86_400
      WEEKEND_START = { "friday" => 5, "saturday" => 6 }.freeze
      DATE_TOKENS = {
        "YYYY" => "%Y", "YY" => "%y", "MM" => "%m", "DD" => "%d",
        "M" => "%-m", "D" => "%-d"
      }.freeze
      # Mermaid gives up after this many days of pushing.
      MAX_PUSH_DAYS = 10_000

      def initialize(entries, weekend, date_format)
        @tokens = entries.flat_map { |line| line.downcase.split(/[\s,]+/) }
        @weekend_start = WEEKEND_START.fetch(weekend.to_s.strip, 6)
        @date_format = strftime_format(date_format.to_s.strip)
      end

      # @return [Array(Time, Time)] the pushed end, and the end to draw
      #   the bar to (nil when the bar simply ends at the pushed end)
      def settle(start, stop)
        return [stop, nil] if @tokens.empty?

        push(start + DAY, stop, stop + (MAX_PUSH_DAYS * DAY))
      end

      private

      def push(day, stop, limit)
        drawn = nil
        pushed = false
        while stop.between?(day, limit)
          drawn = stop unless pushed
          pushed = excluded?(day)
          stop += DAY if pushed
          day += DAY
        end
        [stop, drawn]
      end

      def excluded?(day)
        return true if weekend?(day)

        @tokens.include?(day.strftime("%A").downcase) || dated?(day)
      end

      def weekend?(day)
        return false unless @tokens.include?("weekends")

        iso = day.wday.zero? ? 7 : day.wday
        [@weekend_start, @weekend_start + 1].include?(iso)
      end

      def dated?(day)
        [day.strftime("%Y-%m-%d"), day.strftime(@date_format)]
          .any? { |text| @tokens.include?(text.downcase) }
      end

      def strftime_format(format)
        format.gsub(/YYYY|YY|MM|DD|M|D/, DATE_TOKENS)
      end
    end
  end
end
