# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Activity
        # How an arrow leaves its node, once the columns are centred: from
        # the foot of a decision, straight or with a jog to a step standing
        # under the decision's width, or from its side.
        class Exits
          # @param columns [Columns]
          # @param boxes [Hash{Node => Box}]
          def initialize(columns, boxes)
            @columns = columns
            @boxes = boxes
          end

          # @return [Boolean] whether the arrow runs beside its row: out of
          #   a decision's side, or into the diamond that closes branches
          def beside?(edge)
            !same_column?(edge) && !under?(edge) &&
              (edge.to.kind == :merge || edge.from.kind == :decision)
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
