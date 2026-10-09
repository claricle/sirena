# frozen_string_literal: true

require_relative "scene"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # Pairs each activation with its deactivation into a bar on the
        # lifeline. Bars still open when {#finish} is called end there; a
        # bar opened inside another is drawn half a bar width to the right.
        class BarTracker
          WIDTH = 10.0

          attr_reader :bars

          # @param centre [#call] x of a participant's lifeline, by id
          def initialize(centre)
            @centre = centre
            @bars = []
            @open = Hash.new { |hash, id| hash[id] = [] }
          end

          # @param at [Float] the y where the bar starts or ends
          def apply(activation, at)
            id = activation.participant
            return @open[id] << at if activation.on?

            emit(id, @open[id].pop, at)
          end

          def finish(bottom)
            @open.each do |id, tops|
              emit(id, tops.pop, bottom) until tops.empty?
            end
          end

          private

          def emit(id, top, bottom)
            shift = @open[id].size * (WIDTH / 2)
            @bars << Scene::Bar.new(x: (@centre.call(id) - (WIDTH / 2)) + shift,
                                    y: top, width: WIDTH,
                                    height: [bottom - top, 0.0].max)
          end
        end
      end
    end
  end
end
