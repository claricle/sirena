# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module State
        # The ranks PlantUML's layout (graphviz) gives the states of a
        # diagram, read across every container at once. A state sits one rank
        # below the states that lead to it, and a composite spans the ranks
        # from its own top to its bottom, so two composites whose spans
        # overlap stand side by side, as graphviz draws them, instead of one
        # above the other.
        #
        # A transition into a composite arrives at its top and one out of it
        # leaves from its bottom. A transition that would close a cycle is
        # left out of the ranking, as graphviz reverses it; the search that
        # finds it starts from the composites, so the cycle is cut at the
        # transition into a composite.
        class Ranking
          # @param nodes [Hash{String=>Hash}] the graph's states by id
          # @param children [Array<Hash>] the top-level states
          # @param edges [Array<Hash>] the transitions, ELK-shaped
          def initialize(children, edges)
            @arcs = Hash.new { |hash, key| hash[key] = [] }
            @order = []
            @ends = {}
            structure(children)
            edges.each { |edge| transition(edge) }
          end

          # @return [Range, nil] the ranks a composite spans
          def span(id)
            ends = @ends[id]
            return unless ends

            (rank[ends.first]..rank[ends.last])
          end

          # @return [Boolean] whether two composites share a rank
          def overlap?(one, other)
            first = span(one)
            second = span(other)
            return false unless first && second

            first.cover?(second.begin) || second.cover?(first.begin)
          end

          private

          def structure(children, owner = nil)
            children.reject { |node| note?(node) }.each do |node|
              enter(node, owner)
            end
          end

          def note?(node)
            node.dig(:metadata, :state_type) == "note"
          end

          def enter(node, owner)
            top, bottom = keys_of(node)
            @order << top
            link(owner, top, bottom)
            structure(node[:children] || [], [top, bottom]) if top != bottom
          end

          def link(owner, top, bottom)
            return unless owner

            @arcs[owner.first] << top
            @arcs[bottom] << owner.last
          end

          def keys_of(node)
            return [node[:id]] * 2 unless node[:children]&.any?

            @ends[node[:id]] = [[node[:id], :top], [node[:id], :bottom]]
          end

          def transition(edge)
            from = bottom_of(edge[:sources].first)
            to = top_of(edge[:targets].first)
            @arcs[from] << to if from && to && from != to
          end

          def bottom_of(id)
            @ends.key?(id) ? @ends[id].last : known(id)
          end

          def top_of(id)
            @ends.key?(id) ? @ends[id].first : known(id)
          end

          def known(id)
            id if @order.include?(id)
          end

          # Longest path from the sources, over the arcs that do not close a
          # cycle. Composites are searched first.
          def rank
            @rank ||= begin
              acyclic = Hash.new { |hash, key| hash[key] = [] }
              cut_cycles(acyclic)
              depths(acyclic)
            end
          end

          def cut_cycles(acyclic)
            state = {}
            roots = @order.partition { |key| key.is_a?(Array) }.flatten(1)
            roots.each { |key| visit(key, state, acyclic) }
          end

          def visit(key, state, acyclic)
            return if state[key]

            state[key] = :open
            @arcs[key].each do |target|
              next if state[target] == :open

              acyclic[key] << target
              visit(target, state, acyclic)
            end
            state[key] = :done
          end

          def depths(acyclic)
            depth = Hash.new(0)
            keys = acyclic.keys | acyclic.values.flatten(1) | @order
            topological(keys, acyclic).each do |key|
              deepen(depth, key, acyclic[key])
            end
            depth
          end

          def deepen(depth, key, targets)
            targets.each do |target|
              depth[target] = [depth[target], depth[key] + 1].max
            end
          end

          def topological(keys, acyclic)
            seen = {}
            sorted = []
            keys.each { |key| sort_from(key, acyclic, seen, sorted) }
            sorted.reverse
          end

          def sort_from(key, acyclic, seen, sorted)
            return if seen[key]

            seen[key] = true
            acyclic[key].each do |target|
              sort_from(target, acyclic, seen, sorted)
            end
            sorted << key
          end
        end
      end
    end
  end
end
