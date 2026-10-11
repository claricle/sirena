# frozen_string_literal: true

module Sirena
  module Layout
    class Flowchart < Base
      # The direction and rank spacing a level of boxes is laid out with.
      #
      # mmdc lays a subgraph out as a graph of its own, one rank step wider
      # than the graph around it. Without a `direction` of its own it turns
      # the graph sideways: a downward graph holds a rightward subgraph and
      # any other graph holds a downward one.
      #
      # A subgraph box keeps half a rank step from its contents along the
      # flow and CROSS_MARGIN across it.
      class LevelFrame
        RANK_STEP = 25.0
        CROSS_MARGIN = 35.0
        SIDEWAYS = [Base::DIRECTION_RIGHT, Base::DIRECTION_LEFT].freeze

        attr_reader :direction, :rank_spacing

        # @param direction [String] an ELK direction
        # @param rank_spacing [Numeric] the gap between ranks
        def initialize(direction, rank_spacing)
          @direction = direction
          @rank_spacing = rank_spacing
        end

        # @param direction [String, nil] the subgraph's own ELK direction
        # @return [LevelFrame] the frame of a subgraph laid out on its own
        def nested(direction = nil)
          LevelFrame.new(direction || turned, rank_spacing + RANK_STEP)
        end

        def sideways?
          SIDEWAYS.include?(direction)
        end

        # @return [Array<Float>] the room a subgraph box keeps from its
        #   contents on each side, as [beside, above and below]
        def box_margins
          along = rank_spacing / 2.0
          sideways? ? [along, CROSS_MARGIN] : [CROSS_MARGIN, along]
        end

        private

        def turned
          if direction == Base::DIRECTION_DOWN
            Base::DIRECTION_RIGHT
          else
            Base::DIRECTION_DOWN
          end
        end
      end
    end
  end
end
