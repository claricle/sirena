# frozen_string_literal: true

require_relative "geometry"

module Sirena
  module Layout
    class Sequence < Base
      # The participants a `create` statement declares. mmdc draws such a
      # box on the row of the message that creates it, centred on that
      # message's line, starts its lifeline at the box, stops the arrow
      # at the box edge, and leaves half a box of room below the row.
      class Creations
        # Room added below a creating message: half the box height.
        DROP = Geometry::ACTOR_HEIGHT / 2.0
        # Gap between a box edge and the arrow that stops short of it.
        STOP_GAP = 3
        # Half the stick figure's width.
        FIGURE_HALF_WIDTH = 18

        # @param children [Array<Hash>] participants: id, width, metadata
        #   (`created`, `actor_type`)
        # @param edges [Array<Hash>] messages: targets
        def initialize(children, edges)
          @rows = {}
          @gaps = {}
          children.each do |child|
            next unless child.dig(:metadata, :created)

            row = (edges || []).index { |e| e[:targets].first == child[:id] }
            next unless row

            @rows[child[:id]] = row
            @gaps[child[:id]] = stop_gap(child)
          end
        end

        # @return [Array<String>] ids that have a creating message
        def ids
          @rows.keys
        end

        # @return [Array<Integer>] indexes of the creating messages
        def rows
          @rows.values
        end

        # @param id [String] participant id
        # @return [Integer, nil] index of its creating message
        def row(id)
          @rows[id]
        end

        # @return [Numeric] how far short of the centre the arrow stops
        def gap(id)
          @gaps[id]
        end

        # @param row_y [Numeric] y of the creating message's line
        # @return [Numeric] top of the box
        def top(row_y)
          row_y - DROP
        end

        private

        def stop_gap(child)
          figure = child.dig(:metadata, :actor_type) == "actor"
          (figure ? FIGURE_HALF_WIDTH : child[:width] / 2.0) + STOP_GAP
        end
      end
    end
  end
end
