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
        center_vertical_siblings(ranked[:children])
        graph.merge!(ranked.except(:edges))
      end

      def center_vertical_siblings(children)
        Array(children).each do |child|
          center_vertical_siblings(child[:children])
        end
        Array(children).group_by { |child| child[:x] }.each_value do |column|
          next unless column.map { |child| child[:y] }.uniq.size > 1

          width = column.map { |child| child[:width] }.max
          column.each { |child| child[:x] += (width - child[:width]) / 2.0 }
        end
      end

      def nested?(graph)
        Array(graph[:children]).any? do |child|
          child[:children] || child[:id].to_s.start_with?("namespace:")
        end
      end
      private_class_method :center_vertical_siblings, :directed, :nested?
    end
  end
end
