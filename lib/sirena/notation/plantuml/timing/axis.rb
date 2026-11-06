# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Timing
        # Maps times to x positions. The span runs from the first time to a
        # little past the last. Ticks fall on a regular step: the `scale`
        # unit, or else the greatest common divisor of the change times and
        # clock periods, each step drawn 50 pixels wide as PlantUML does.
        # Where no step exists (fractional or dated times without a scale),
        # the span fills `plot` pixels and ticks fall on every time.
        class Axis
          TAIL = 0.25
          FALLBACK_SPAN = 100.0
          STEP_PIXELS = 50.0

          attr_reader :start, :finish

          # @param diagram [Diagram]
          # @param left [Float] x of the first time
          # @param plot [Float] width in pixels when the source gives no scale
          def initialize(diagram, left, plot)
            @diagram = diagram
            @left = left
            times = moments
            @start = times.min || 0.0
            last = times.max || @start
            span = last > @start ? last - @start : FALLBACK_SPAN
            @step = tick_step
            @finish = last + (@step || (span * TAIL))
            @pixels = diagram.pixels_per_unit || pixels_for(plot)
          end

          # @return [Float]
          def x(time)
            @left + ((time - @start) * @pixels)
          end

          # @return [Array<Float>] the times worth a tick, ascending
          def ticks
            return moments.uniq.sort unless @step

            count = ((@finish - @start) / @step).floor
            Array.new(count + 1) { |index| @start + (index * @step) }
          end

          # @return [Boolean] whether the tick at `time` carries its label
          def labelled?(time)
            return true unless @step && !@diagram.pixels_per_unit

            named_times.any? { |named| (named - time).abs < 1e-9 }
          end

          # @return [String] the tick's label
          def label(time)
            return Time.at(time).utc.strftime("%m/%d") if @diagram.dated

            time == time.floor ? time.to_i.to_s : time.to_s
          end

          private

          def pixels_for(plot)
            return STEP_PIXELS / @step if @step

            plot / (@finish - @start)
          end

          def tick_step
            return @diagram.scale_units.to_f if @diagram.scale_units
            return if @diagram.dated

            common_divisor
          end

          def common_divisor
            times = named_times
            return unless times.all? { |time| time == time.floor }

            step = times.map(&:to_i).reduce(0, :gcd)
            step.to_f if step.positive?
          end

          def named_times
            periods = @diagram.participants.values.filter_map(&:period)
            @diagram.changes.map(&:time) + periods
          end

          def moments
            d = @diagram
            d.changes.map(&:time) +
              d.messages.flat_map { |m| [m.time, m.arrives] }.compact +
              d.highlights.flat_map { |h| [h.from, h.to] }
          end
        end
      end
    end
  end
end
