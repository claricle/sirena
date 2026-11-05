# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # A link between two nodes.
        #
        # `head` is `:target`, `:source`, `:socket` or `nil`; `style` is
        # `:solid` or `:dashed`. `from_row` and `to_row` are the index of the
        # row of a map or object box the line starts or ends at, or nil. `ends`
        # is nil, or for an entity link the crow's foot markers of its two
        # ends, `[from, to]`, each listed from the box outward (see
        # {CrowsFoot}). `rank_step` is how many ranks the layout puts `to`
        # after `from` (0 keeps them in one rank); `backwards` reads the link
        # from `to`. `pointer` marks the tail of a note written beside its
        # target (`note right of X`); a link to or from a named note is a
        # plain line.
        Edge = Struct.new(:from, :to, :label, :style, :head, :color, :width,
                          :ends, :from_row, :to_row, :rank_step, :backwards,
                          :pointer, keyword_init: true)
      end
    end
  end
end
