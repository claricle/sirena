# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Activity
        # A flow arrow between two nodes.
        class Edge
          attr_reader :from, :to, :label, :colour, :style

          # @param from [Node]
          # @param to [Node]
          # @param label [String, nil]
          # @param colour [String, nil] an SVG colour
          # @param style [Symbol, nil] :dashed, :dotted or :bold
          def initialize(from:, to:, label: nil, colour: nil, style: nil)
            @from = from
            @to = to
            @label = label
            @colour = colour
            @style = style
          end
        end
      end
    end
  end
end
