# frozen_string_literal: true

require_relative "../style"

module Sirena
  module Notation
    module PlantUML
      module Activity
        # A parsed activity diagram: nodes and edges in source order, the
        # swimlanes in order of first use and an optional title.
        class Diagram
          attr_reader :nodes, :edges, :lanes, :title
          # @return [Style::Sheet] what the source says about fonts and
          #   looks; the layout sizes boxes from it
          attr_accessor :style

          # @param lanes [Array<Array(String, String)>] name and colour
          def initialize(nodes:, edges:, lanes: [], title: nil)
            @nodes = nodes
            @edges = edges
            @lanes = lanes
            @title = title
            @style = Style::Sheet.new
          end
        end
      end
    end
  end
end
