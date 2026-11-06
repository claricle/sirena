# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Activity
        # How an arrow leaves its node, once the columns are centred: from
        # the foot of a decision, straight or with a jog to a step standing
        # under the decision's width, or from its side.
        class Exits
          # A step that stands over the diamond closing the branches drops
          # into its top instead of its side; a bar runs round to the side.
          #
          # @return [Boolean]
          def self.top_entry?(edge, from, to)
            edge.to.kind == :merge && edge.from.kind != :bar &&
              from.spans?(to.cx)
          end

          # @param columns [Columns]
          # @param boxes [Hash{Node => Box}]
          def initialize(columns, boxes)
            @columns = columns
            @boxes = boxes
          end

          # @return [Boolean] whether the arrow runs beside its row: out of
          #   a decision's side, or into the side of the diamond that closes
          #   branches
          def beside?(edge)
            !same_column?(edge) && !under?(edge) && sideways?(edge)
          end

          # @return [Boolean] whether the arrow leaves a decision's foot and
          #   has to jog sideways to reach its step
          def jog?(edge)
            under?(edge) && !same_column?(edge)
          end

          def same_column?(edge)
            @columns.key[edge.from] == @columns.key[edge.to]
          end

          private

          def sideways?(edge)
            return edge.from.kind == :decision unless edge.to.kind == :merge

            !Exits.top_entry?(edge, @boxes[edge.from], @boxes[edge.to])
          end

          def under?(edge)
            edge.from.kind == :decision &&
              (@boxes[edge.to].cx - @boxes[edge.from].cx).abs <
                @boxes[edge.from].width / 2.0
          end
        end
      end
    end
  end
end
