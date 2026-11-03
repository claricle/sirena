# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUMLSalt
      # One line of a block: its cells (each a {Widget} or a nested {Block})
      # and, in a tree block, how deep its `+` marks nest it.
      class Row
        attr_reader :depth, :cells

        def initialize(cells, depth: 0)
          @cells = cells.freeze
          @depth = depth
          freeze
        end
      end
    end
  end
end
