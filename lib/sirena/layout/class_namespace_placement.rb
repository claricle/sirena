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
        return directed(graph) if nested?(graph)

        ClassCellPlacement.apply(graph)
      end

      # mmdc's dagre puts sibling class boxes 50 apart, not the layout's 80.
      # Keep the rank gap: cluster rank spacing already matches the reference.
      def directed(graph)
        graph[:layoutOptions] = (graph[:layoutOptions] || {}).merge(
          Base::ElkOptions::NODE_NODE_SPACING => ClassCellPlacement::DAGRE_GAP,
        )
        ranked = graph.merge(edges: ClassCellPlacement.written_edges(graph))
        Flowchart::DirectedPlacement.apply(ranked)
        graph.merge!(ranked.except(:edges))
      end

      def nested?(graph)
        Array(graph[:children]).any? do |child|
          child[:children] || child[:id].to_s.start_with?("namespace:")
        end
      end
      private_class_method :directed, :nested?
    end
  end
end
