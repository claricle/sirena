# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # A link between two nodes.
        #
        # `head` is `:target`, `:source`, `:socket` or `nil`; `style` is
        # `:solid` or `:dashed`.
        Edge = Struct.new(:from, :to, :label, :style, :head, :color, :width,
                          keyword_init: true)
      end
    end
  end
end
