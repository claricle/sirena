# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # Puts the items of one scope into ranks and orders each rank, from
        # the links between them. Source order breaks every tie, so the
        # result is deterministic.
        class Ranking
          SWEEPS = 4

          # @return [Array<Array<Object>>] the items of each rank, in order
          attr_reader :layers

          # @param items [Array<Object>] in source order
          # @param pairs [Array<Array(Object, Object)>] links between items
          def initialize(items, pairs)
            @items = items
            @pairs = pairs.uniq.reject { |a, b| a.equal?(b) }
            @forward = acyclic(@pairs)
            @rank = items.to_h { |item| [item, 0] }
            items.each { |item| rank_of(item, {}) }
            @layers = group
            order
          end

          private

          # The links that remain once every link closing a cycle, found
          # depth first in source order, is dropped.
          def acyclic(pairs)
            @adjacency = pairs.group_by(&:first)
            @state = {}
            @kept = []
            @items.each { |item| descend(item) unless @state[item] }
            @kept
          end

          def descend(item)
            @state[item] = :open
            @adjacency.fetch(item, []).each { |pair| follow(pair) }
            @state[item] = :done
          end

          def follow(pair)
            return if @state[pair.last] == :open

            @kept << pair
            descend(pair.last) unless @state[pair.last]
          end

          def rank_of(item, seen)
            return @rank[item] if seen[item]

            seen[item] = true
            preds = @forward.select { |_, b| b.equal?(item) }.map(&:first)
            @rank[item] = preds.map { |pred| rank_of(pred, seen) + 1 }.max || 0
          end

          def group
            @items.group_by { |item| @rank[item] }.sort.map(&:last)
          end

          def order
            SWEEPS.times do |pass|
              down = pass.even?
              sweep = down ? 1...@layers.size : (@layers.size - 2).downto(0)
              sweep.each { |index| sort_layer(index, down ? -1 : 1) }
            end
          end

          def sort_layer(index, step)
            neighbour = @layers[index + step]
            return unless neighbour

            @layers[index] = @layers[index].sort_by.with_index do |item, at|
              [barycentre(item, neighbour) || at, at]
            end
          end

          def barycentre(item, layer)
            linked = @pairs.filter_map do |a, b|
              other = if a.equal?(item) then b elsif b.equal?(item) then a end
              layer.index { |entry| entry.equal?(other) } if other
            end
            linked.sum.fdiv(linked.size) unless linked.empty?
          end
        end
      end
    end
  end
end
