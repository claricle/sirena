# frozen_string_literal: true

require_relative "diagram"
require_relative "ir_reader/index"
require_relative "ir_reader/fills"
require_relative "ir_reader/participants"
require_relative "ir_reader/settings"
require_relative "ir_reader/messages"
require_relative "ir_reader/blocks"
require_relative "ir_reader/items"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # Rebuilds the private sequence Diagram from the IR::Graph
        # {IRAdapter} emitted, so layout can keep measuring and placing
        # PlantUML's own rows. Nothing outside this notation reads the
        # Diagram.
        module IRReader
          module_function

          # @param graph [IR::Graph] a graph from {IRAdapter.call}
          # @return [Diagram]
          def call(graph)
            index = Index.new(graph)
            Diagram.new(
              participants: Participants.participants(index).freeze,
              items: Items.call(index).freeze,
              boxes: Participants.boxes(index).freeze,
              **Settings.call(index),
            )
          end
        end
      end
    end
  end
end
