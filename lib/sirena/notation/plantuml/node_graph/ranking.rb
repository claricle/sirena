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
            sink_sources
            @tie_order = tie_order
            @layers = @pairs.empty? ? grid : group
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
          # A group of items with no link in (items tied by a link of step 0
          # move together) drops to the rank just before its nearest target,
          # which shortens every link it has, as the JAR's ranking does.
          def sink_sources
            groups = same_rank_groups
            groups.sort_by { |group| -@rank[group.first] }.each do |group|
              target = sink_rank(group)
              next unless target && target > @rank[group.first]

              group.each { |item| @rank[item] = target }
            end
          end

          # @return [Integer, nil] the rank before the nearest target of
          #   `group`, when no link feeds it
          def sink_rank(group)
            return if fed?(group)

            @forward.filter_map do |from, to, step|
              next unless group.include?(from) && !group.include?(to)

              @rank[to] - (step || 1)
            end.min
          end

          # Whether a link from outside `group` ends in it.
          def fed?(group)
            @forward.any? do |from, to, _|
              group.include?(to) && !group.include?(from)
            end
          end

          def same_rank_groups
            groups = @items.to_h { |item| [item, [item]] }
            @forward.each do |from, to, step|
              next unless step&.zero?

              merged = groups[from] | groups[to]
              merged.each { |item| groups[item] = merged }
            end
            groups.values.uniq
          end

          def hold?(from, to, step)
            step ||= 1
            want = @rank[from] + step
            ends = step.zero? ? [from, to] : [to]
            want = ends.map { |item| @rank[item] }.push(want).max
            ends.map { |item| @rank[item] < want && @rank[item] = want }.any?
          end

          # Items with no links between them are packed into the squarest
          # grid, `ceil(sqrt(n))` to a rank, in source order, as the
          # PlantUML JAR does.
          def grid
            @items.each_slice([Math.sqrt(@items.size).ceil, 1].max).to_a
          end

          def group
            by_rank = @items.group_by { |item| @rank[item] }
            (0..(by_rank.keys.max || -1)).map do |rank|
              tied_first(by_rank.fetch(rank, []))
            end
          end

          # A rank with its tied items (links of step 0) first, in the order
          # their first tie was written; the JAR places the actor of the
          # first `A -> (B)` left of an actor declared earlier but untied.
          def tied_first(layer)
            layer.sort_by.with_index do |item, at|
              tie = @tie_order[item]
              [tie ? 0 : 1, tie || 0, at]
            end
          end

          # @return [Hash] each item tied to another by a step-0 link, to
          #   the position of its first such link
          def tie_order
            order = {}
            @pairs.each_with_index do |(from, to, step), at|
              next unless step&.zero?

              order[from] ||= at
              order[to] ||= at
            end
            order
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
