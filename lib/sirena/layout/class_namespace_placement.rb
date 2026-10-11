# frozen_string_literal: true

require_relative "class_cell_placement"
require_relative "flowchart/directed_placement"

module Sirena
  module Layout
    # Routes namespace-bearing Class graphs through the compound-aware
    # directed placer while preserving ClassCellPlacement for flat graphs.
    module ClassNamespacePlacement
      module_function

      def apply(graph)
        return Flowchart::DirectedPlacement.apply(graph) if nested?(graph)

        ClassCellPlacement.apply(graph)
      end

      def nested?(graph)
        Array(graph[:children]).any? do |child|
          child[:children] || child[:id].to_s.start_with?("namespace:")
        end
      end
      private_class_method :nested?
    end
  end
end
