# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Timing
        # Maps times to x positions. The span runs from the first time to a
        # little past the last; without a `scale` line it fills `plot`
        # pixels.
        class Axis
          TAIL = 0.25
          FALLBACK_SPAN = 100.0

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
            @finish = last + (span * TAIL)
            @pixels = diagram.pixels_per_unit || (plot / (@finish - @start))
          end

          # @return [Float]
          def x(time)
            @left + ((time - @start) * @pixels)
          end

          # @return [Array<Float>] the times worth a tick, ascending
          def ticks
            moments.uniq.sort
          end

          # @return [String] the tick's label
          def label(time)
            return Time.at(time).utc.strftime("%m/%d") if @diagram.dated

            time == time.floor ? time.to_i.to_s : time.to_s
          end

          private

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
