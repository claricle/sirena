# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Activity
        # Decides which edges are loops and which row each node sits on.
        # A depth-first walk from the first node marks an edge to a node
        # still being walked as a back edge; the rest form a DAG, and a row
        # is the longest path to it. A loop's exit must sit below the
        # loop's body, so each back edge also holds the exits of its target
        # beneath its source. An edge that lies along its row puts both its
        # ends on one row.
        class Ranking
          # @return [Hash{Node => Integer}]
          attr_reader :rank

          def initialize(diagram)
            @diagram = diagram
            @out = Hash.new { |hash, key| hash[key] = [] }
            diagram.edges.each { |edge| @out[edge.from] << edge }
            @back = Set.new.compare_by_identity
            walk
            @rank = longest_paths(constraints)
          end

          # @return [Boolean] whether the edge closes a loop
          def back?(edge)
            @back.include?(edge)
          end

          # @return [Array<Edge>] edges leaving the node, loops excluded
          def forward(node)
            @out[node].reject { |edge| back?(edge) }
          end

          # @return [Edge, nil] the edge that puts the node beside another
          def level_in(node)
            @level_in[node]
          end

          private

          def walk
            state = {}.compare_by_identity
            @diagram.nodes.each do |node|
              visit(node, state) unless state[node]
            end
          end

          def visit(node, state)
            state[node] = :open
            @out[node].each do |edge|
              case state[edge.to]
              when :open then @back << edge
              when nil then visit(edge.to, state)
              end
            end
            state[node] = :done
          end

          # [from, to] pairs: every forward edge, and for each loop the
          # exits of the loop head that cannot reach the loop's body.
          def constraints
            find_levels
            forward_pairs + @back.flat_map { |edge| exit_pairs(edge) }
          end

          def forward_pairs
            @diagram.edges.reject { |e| back?(e) || e.level? }
              .map { |e| [e.from, e.to] }
          end

          def find_levels
            @levels = @diagram.edges.select { |e| e.level? && !back?(e) }
            @level_in = {}.compare_by_identity
            @levels.reverse_each { |edge| @level_in[edge.to] = edge }
          end

          def exit_pairs(loop_edge)
            forward(loop_edge.to).filter_map do |exit_edge|
              next if reaches?(exit_edge.to, loop_edge.from)

              [loop_edge.from, exit_edge.to]
            end
          end

          def reaches?(from, target, seen = Set.new.compare_by_identity)
            return true if from.equal?(target)
            return false unless seen.add?(from)

            forward(from).any? { |edge| reaches?(edge.to, target, seen) }
          end

          def longest_paths(pairs)
            rank = @diagram.nodes.to_h { |node| [node, 0] }
            rank.compare_by_identity
            (@diagram.nodes.size + 1).times do
              break if settle(rank, pairs).zero?
            end
            rank
          end

          # One pass over the constraints; the number of nodes it moved.
          def settle(rank, pairs)
            pairs.count { |from, to| lift(rank, from, to) } +
              @levels.count { |edge| level(rank, edge.from, edge.to) }
          end

          # Puts both nodes on the lower of their two rows; nil when they
          # already share one.
          def level(rank, first, second)
            return if rank[first] == rank[second]

            rank[first] = rank[second] = [rank[first], rank[second]].max
          end

          # Puts `to` one row below `from`; nil when it already is.
          def lift(rank, from, to)
            return if rank[to] > rank[from]

            rank[to] = rank[from] + 1
          end
        end
      end
    end
  end
end
