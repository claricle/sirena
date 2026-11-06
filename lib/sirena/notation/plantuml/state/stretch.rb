# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module State
        # Lowers a state inside a top-level composite to the rank below
        # another composite it follows, and stretches its composite to
        # hold it. PlantUML ranks every state across all containers at once,
        # so a transition from one composite's bottom to a state of another
        # puts that state a rank under the first composite, however short
        # its own container would be.
        class Stretch
          # The distance from a composite's bottom to the state a transition
          # out of it leads to: one rank and the label that rank carries.
          RANK_GAP = 77.0
          private_constant :RANK_GAP

          # @param edges [Array<Hash>] the transitions, ELK-shaped
          # @param nodes [Hash{String=>Hash}] every state by id
          # @param parent [Hash{String=>String}] the container of each state
          # @param ranking [Ranking]
          def initialize(edges, nodes, parent, ranking)
            @edges = edges
            @nodes = nodes
            @parent = parent
            @ranking = ranking
          end

          # @param top [Array<Hash>] the placed top-level states
          # @return [Array<Hash>] the states that moved
          def apply(top)
            composites = top.select { |node| Array(node[:children]).any? }
            ids = composites.map { |node| node[:id] }
            @edges.flat_map do |edge|
              lower(edge, @nodes[edge[:sources].first], ids)
            end
          end

          private

          def lower(edge, source, ids)
            target = @nodes[edge[:targets].first]
            holder = @nodes[@parent[target[:id]]]
            return [] unless follows?(source, target, holder, ids)

            drop = floor(source) - holder[:y] - target[:y]
            drop.positive? ? sink(holder, target, drop) : []
          end

          def floor(source)
            source[:y] + source[:height] + RANK_GAP
          end

          def follows?(source, target, holder, ids)
            holder && !holder.equal?(source) &&
              ids.include?(source[:id]) && ids.include?(holder[:id]) &&
              @ranking.below?(target[:id], source[:id])
          end

          def sink(holder, target, drop)
            moved = holder[:children].select { |node| node[:y] >= target[:y] }
            moved.each { |node| node[:y] += drop }
            holder[:height] += drop
            moved
          end
        end
      end
    end
  end
end
