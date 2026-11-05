# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # A link between two nodes.
        #
        # `head` is `:target`, `:source`, `:socket` or `nil`; `style` is
        # `:solid` or `:dashed`. `ends` is nil, or for an entity link the
        # crow's foot markers of its two ends, `[from, to]`, each listed from
        # the box outward (see {CrowsFoot}).
        Edge = Struct.new(:from, :to, :label, :style, :head, :color, :width,
                          :ends, keyword_init: true)
      end
    end
  end
end
