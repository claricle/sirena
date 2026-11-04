# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Activity
        # A parsed activity diagram: nodes and edges in source order, the
        # swimlanes in order of first use and an optional title.
        class Diagram
          attr_reader :nodes, :edges, :lanes, :title

          # @param lanes [Array<Array(String, String)>] name and colour
          def initialize(nodes:, edges:, lanes: [], title: nil)
            @nodes = nodes
            @edges = edges
            @lanes = lanes
            @title = title
          end
        end
      end
    end
  end
end
