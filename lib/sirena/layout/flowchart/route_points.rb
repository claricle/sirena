# frozen_string_literal: true

module Sirena
  module Layout
    class Flowchart < Base
      # Every point of every route elkrb drew on a level.
      module RoutePoints
        module_function

        # @param flat [Hash] a level with edges
        # @return [Array<Hash>] start, bend and end points, to move in place
        def of(flat)
          (flat[:edges] || []).flat_map do |edge|
            (edge[:sections] || []).flat_map do |section|
              [section[:startPoint], *section[:bendPoints],
               section[:endPoint]].compact
            end
          end
        end
      end
    end
  end
end
