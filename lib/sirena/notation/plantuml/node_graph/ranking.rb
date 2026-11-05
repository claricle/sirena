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
          # @param pairs [Array<Array>] links between items, each
          #   `[from, to, step]`: `to` sits `step` ranks after `from` (0 puts
          #   them in one rank, with `from` first; 1 when omitted)
          def initialize(items, pairs)
            @items = items
            @pairs = merged(pairs)
            @forward = acyclic(@pairs)
            @rank = items.to_h { |item| [item, 0] }
            settle_ranks
            @layers = group
            order
          end

          private

          # Each pair once, with the longest step asked of it.
          def merged(pairs)
            pairs.reject { |a, b| a.equal?(b) }
              .group_by { |a, b, _| [a.object_id, b.object_id] }
              .values.map { |group| group.max_by { |_, _, step| step || 1 } }
          end

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
            return if @state[pair[1]] == :open

            @kept << pair
            descend(pair[1]) unless @state[pair[1]]
          end

          # Longest path ranks: a link of step n puts its target n ranks
          # after its source, a step of 0 puts both in one rank. Stops after
          # a bounded number of sweeps, so links that cannot all hold (a
          # one-rank link across a pair held in one rank) cannot loop.
          def settle_ranks
            (@items.size + 1).times do
              break unless @forward.map { |link| hold?(*link) }.any?
            end
          end

          # @return [Boolean] whether the link moved a rank
          def hold?(from, to, step)
            step ||= 1
            want = @rank[from] + step
            ends = step.zero? ? [from, to] : [to]
            want = ends.map { |item| @rank[item] }.push(want).max
            ends.map { |item| @rank[item] < want && @rank[item] = want }.any?
          end

          def group
            by_rank = @items.group_by { |item| @rank[item] }
            (0..(by_rank.keys.max || -1)).map { |rank| by_rank.fetch(rank, []) }
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
            @layers[index] = @layers[index].sort_by.with_index do |item, at|
              [barycentre(item, neighbour) || at, at]
            end
            @layers[index] = settled(@layers[index])
          end

          # The layer with every item after the items that must come first
          # in its rank (links of step 0); an item goes right after the one
          # it is tied to, otherwise the layer keeps its order.
          def settled(layer)
            rest = layer.dup
            last = nil
            Array.new(layer.size) do
              last = pick_next(rest, last)
              rest.delete_if { |item| item.equal?(last) }
              last
            end
          end

          def pick_next(rest, last)
            ready = rest.reject { |item| before(item).intersect?(rest) }
            ready.find { |item| before(item).include?(last) } ||
              ready.first || rest.first
          end

          # The items a link of step 0 puts ahead of `item`.
          def before(item)
            @forward.filter_map do |from, to, step|
              from if step&.zero? && to.equal?(item)
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
