# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # A node placed at final coordinates.
        Placed = Struct.new(:node, :x, :y, :width, :height, :depth,
                            keyword_init: true)

        # A link routed between two placed nodes, as a list of points.
        Route = Struct.new(:edge, :points, keyword_init: true)

        # A laid-out diagram.
        Scene = Struct.new(:width, :height, :placed, :routes, :title,
                           keyword_init: true)
      end
    end
  end
end
