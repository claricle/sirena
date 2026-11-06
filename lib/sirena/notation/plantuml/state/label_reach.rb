# frozen_string_literal: true

require_relative "routes"

module Sirena
  module Notation
    module PlantUML
      module State
        # How far right a container must reach to hold the labels of the
        # transitions between its members. Graphviz makes each label a node
        # of the rank between the two states it joins, so the labels of one
        # rank stand side by side and the cluster grows to hold them, which a
        # layout that only sees the states does not.
        class LabelReach
          # The room graphviz keeps between two nodes of a rank.
          GAP = 18.0
          # The room between the last label and the cluster's border.
          MARGIN = 12.5
          private_constant :GAP, :MARGIN

          # @param edges [Array<Hash>] every transition of the graph
          # @param parent [Hash{String=>String}] the container of each state
          def initialize(edges, parent)
            @edges = edges.select { |edge| Array(edge[:labels]).any? }
            @parent = parent
          end

          # @param members [Array<Hash>] the placed states of a container,
          #   positioned relative to it
          # @return [Float] the width the container needs for its labels
          def width(members)
            ranks = by_rank(members)
            return 0.0 if ranks.empty?

            ranks.values.map { |labels| reach(labels) }.max + MARGIN
          end

          private

          # The labels of each rank, as [ideal left, width] pairs.
          def by_rank(members)
            by_id = members.to_h { |node| [node[:id], node] }
            joined = @edges.filter_map { |edge| joint(edge, by_id) }
            joined.group_by(&:first).transform_values do |rows|
              rows.map(&:last)
            end
          end

          # The rank key and the label of an edge between two members.
          def joint(edge, by_id)
            pair = Routes.level_pair(edge, @parent, by_id.keys)
            return unless pair

            from, to = pair.map { |id| by_id.fetch(id) }
            [rank_of(from, to),
             [middle(from, to) + 1, edge[:labels].first[:width]]]
          end

          def rank_of(from, to)
            upper = [from, to].min_by { |node| node[:y] }
            upper[:y] + upper[:height]
          end

          def middle(from, to)
            centres = [from, to].map { |node| node[:x] + (node[:width] / 2.0) }
            centres.sum / 2.0
          end

          def reach(labels)
            labels.sort.reduce(0.0) do |right, (left, width)|
              [left, right + GAP].max + width
            end
          end
        end
      end
    end
  end
end
