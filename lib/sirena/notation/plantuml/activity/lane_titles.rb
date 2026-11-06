# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Activity
        # Keeps each swimlane band as wide as its title, which the JAR draws
        # at one size in every lane. A band that falls short takes the rest
        # evenly from the first and last columns of its lane.
        class LaneTitles
          # @param metrics [Metrics] measures the title
          # @param size [Numeric] the title's font size
          # @param pad [Float] the room kept about the title in its band
          def initialize(metrics, size, pad)
            @metrics = metrics
            @size = size
            @pad = pad
          end

          # @param bands [Array<Hash>] the bands, each with its `:name`,
          #   its `:left` and `:right`, and the `:columns` of its lane
          # @param reach [Reach] widened where a band falls short
          # @return [Integer] how many bands were short
          def widen(bands, reach)
            bands.count { |band| widen_band(band, reach) }
          end

          private

          def widen_band(band, reach)
            half = shortfall(band) / 2
            return unless half.positive?

            reach.widen_column(band[:columns].first, 0, half)
            reach.widen_column(band[:columns].last, 1, half)
          end

          def shortfall(band)
            @metrics.text_width([band[:name]], size: @size) + @pad -
              (band[:right] - band[:left])
          end
        end
      end
    end
  end
end
