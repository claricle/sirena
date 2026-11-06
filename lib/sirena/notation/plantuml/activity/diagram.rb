# frozen_string_literal: true

require_relative "../style"

module Sirena
  module Notation
    module PlantUML
      module Activity
        # A parsed activity diagram: nodes and edges in source order, the
        # swimlanes in order of first use, an optional title and the notices
        # PlantUML prints above the drawing.
        class Diagram
          attr_reader :nodes, :edges, :lanes, :title, :warnings
          # @return [Style::Sheet] what the source says about fonts and
          #   looks; the layout sizes boxes from it
          attr_accessor :style
          # @return [Boolean] whether it was written in the legacy `(*)`
          #   syntax, which PlantUML ranks differently from the new one
          attr_accessor :legacy

          # @param lanes [Array<Array(String, String)>] name and colour
          def initialize(nodes:, edges:, lanes: [], title: nil, warnings: [])
            @nodes = nodes
            @edges = edges
            @lanes = lanes
            @title = title
            @warnings = warnings
            @style = Style::Sheet.new
            @legacy = false
          end
        end
      end
    end
  end
end
