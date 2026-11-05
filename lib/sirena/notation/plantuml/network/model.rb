# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Network
        # A node's membership of one network.
        Member = Struct.new(:name, :address, keyword_init: true)

        # A named shaded cluster of nodes.
        Group = Struct.new(:name, :color, :names, keyword_init: true)

        # One horizontal bar and the nodes hanging from it.
        Network = Struct.new(:name, :address, :color, :nodes, :groups,
                             keyword_init: true)

        # The whole diagram: its networks, and each node's shape.
        Diagram = Struct.new(:networks, :shapes, keyword_init: true)
      end
    end
  end
end
