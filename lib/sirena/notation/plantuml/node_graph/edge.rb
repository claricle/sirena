# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # A link between two nodes.
        #
        # `head` is `:target`, `:source`, `:socket` or `nil`; `style` is
        # `:solid` or `:dashed`. `from_row` and `to_row` are the index of the
        # row of a map or object box the line starts or ends at, or nil.
        # `rank_step` is how many ranks the layout puts `to` after `from`
        # (0 keeps them in one rank); `backwards` reads the link from `to`.
        Edge = Struct.new(:from, :to, :label, :style, :head, :color, :width,
                          :from_row, :to_row, :rank_step, :backwards,
                          keyword_init: true)
      end
    end
  end
end
