# frozen_string_literal: true

require "time"

module Sirena
  module Layout
    # Picks the axis tick times of a Gantt chart the way mermaid does: d3's
    # time-scale ladder aiming for about ten ticks, each interval aligned
    # to the calendar (hours to midnight, weeks to Sunday, months to Jan,
    # Apr, Jul, Oct for a 3-month step, years to a multiple of the step).
    #
    # Times are UTC so the result does not depend on the machine's zone.
    class GanttTicks
      TARGET_COUNT = 10
      HOUR = 3600
      DAY = 24 * HOUR
      # [unit, step, approximate seconds] as in d3-scale's tickIntervals.
      LADDER = [
        [:hour, 1, HOUR], [:hour, 3, 3 * HOUR], [:hour, 6, 6 * HOUR],
        [:hour, 12, 12 * HOUR], [:day, 1, DAY], [:day, 2, 2 * DAY],
        [:week, 1, 7 * DAY], [:month, 1, 30 * DAY], [:month, 3, 90 * DAY],
        [:year, 1, 365 * DAY]
      ].freeze
      INTERVAL_PATTERN = /\A([1-9]\d*)(hour|day|week|month)\z/
      SUNDAY_OFFSET_DAYS = 4
      # An explicit tickInterval that would draw more ticks than this over
      # the range is ignored in favour of the automatic ladder, so a span of
      # millennia cannot produce millions of labels.
      MAX_TICKS = 2000
      UNIT_SECONDS = {
        hour: HOUR, day: DAY, week: 7 * DAY, month: 30 * DAY
      }.freeze

      def self.times(start_time, stop_time, interval = nil)
        new(start_time, stop_time, interval).times
      end

      def initialize(start_time, stop_time, interval)
        @start = start_time
        @stop = stop_time
        @interval = affordable(parse(interval)) || pick_interval
      end

      def times
        unit, step = @interval
        candidates(unit).select do |time|
          time.between?(@start, @stop) && aligned?(unit, step, time)
        end
      end

      private

      def parse(text)
        match = INTERVAL_PATTERN.match(text.to_s.strip)
        [match[2].to_sym, match[1].to_i] if match
      end

      def affordable(interval)
        return unless interval

        unit, step = interval
        seconds = UNIT_SECONDS.fetch(unit) * step
        interval if (@stop - @start).abs / seconds <= MAX_TICKS
      end

      def pick_interval
        target = (@stop - @start).abs / TARGET_COUNT
        index = LADDER.index { |entry| entry.last > target }
        return year_interval unless index
        return LADDER.first.first(2) if index.zero?

        below = LADDER[index - 1]
        above = LADDER[index]
        (target / below.last < above.last / target ? below : above).first(2)
      end

      def year_interval
        years = (@stop - @start).abs / LADDER.last.last
        [:year, nice_step(years / TARGET_COUNT)]
      end

      # d3.tickIncrement's 1, 2, 5, 10 ladder, never below one year.
      def nice_step(raw)
        power = Math.log10(raw).floor
        error = raw / (10.0**power)
        factor = [[Math.sqrt(50), 10], [Math.sqrt(10), 5],
                  [Math.sqrt(2), 2]].find { |limit, _| error >= limit }
        [((factor&.last || 1) * (10**power)).to_i, 1].max
      end

      def candidates(unit)
        cursor = floor_to(unit, @start)
        found = []
        while cursor <= @stop
          found << cursor
          cursor = advance(unit, cursor)
        end
        found
      end

      def floor_to(unit, time)
        case unit
        when :hour then Time.utc(time.year, time.month, time.day, time.hour)
        when :month then Time.utc(time.year, time.month)
        when :year then Time.utc(time.year)
        else floor_days(unit, time)
        end
      end

      def floor_days(unit, time)
        day = Time.utc(time.year, time.month, time.day)
        unit == :week ? day - (day.wday * DAY) : day
      end

      def advance(unit, time)
        case unit
        when :hour then time + HOUR
        when :day then time + DAY
        when :week then time + (7 * DAY)
        when :month then next_month(time)
        else Time.utc(time.year + 1)
        end
      end

      def next_month(time)
        Time.utc(time.year + (time.month / 12), (time.month % 12) + 1)
      end

      def aligned?(unit, step, time)
        (index_of(unit, time) % step).zero?
      end

      def index_of(unit, time)
        case unit
        when :hour then time.hour
        when :day then time.day - 1
        when :week then ((time.to_i / DAY) + SUNDAY_OFFSET_DAYS) / 7
        when :month then ((time.year - 1970) * 12) + time.month - 1
        else time.year
        end
      end
    end
  end
end
