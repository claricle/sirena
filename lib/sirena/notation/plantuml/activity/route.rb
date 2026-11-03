# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Activity
        # The drawn path of one edge and where its label goes.
        class Route
          attr_reader :points, :label_x, :label_y, :anchor

          # @param points [Array<Array(Float, Float)>] corners, start to tip
          def initialize(points:, label_x:, label_y:, anchor: "start")
            @points = points
            @label_x = label_x
            @label_y = label_y
            @anchor = anchor
          end
        end
      end
    end
  end
end
