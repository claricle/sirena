# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Activity
        # The two steps of a two-step side lane that PlantUML hangs from the
        # lane's ends rather than from the rows of the lane beside it: the
        # first sits just under its decision, the last just over the diamond
        # that closes the branches. Neither asks the rows for any height, so
        # a bar in the neighbouring lane is not set off from its steps by a
        # box that belongs to another lane.
        class LaneSteps
          # @return [Hash{Node => Node}] each step hung from the decision,
          #   with the step that follows it
          attr_reader :heads
          # @return [Hash{Node => Node}] each step hung from the diamond
          #   closing its branches, with that diamond
          attr_reader :tails

          # @param diagram [Diagram]
          # @param ranking [Ranking]
          # @param exits [Exits]
          def initialize(diagram, ranking, exits)
            @ranking = ranking
            @exits = exits
            @heads = {}.compare_by_identity
            @tails = {}.compare_by_identity
            @edges = diagram.legacy ? [] : diagram.edges
            @edges.select { |edge| closing?(edge) }.each { |edge| hang(edge) }
          end

          # @return [Boolean] whether the step hangs from either end
          def hung?(node)
            @heads.key?(node) || @tails.key?(node)
          end

          # @param node [Node]
          # @param height [Float] the height of the node's box
          # @param tops [Array<Float>] the top of each row
          # @return [Float, nil] where the step's centre stands, or nil when
          #   the rows place it
          def centre(node, height, tops)
            return tops[@ranking.rank[node]] + (height / 2.0) if
              @heads.key?(node)

            diamond = @tails[node]
            return unless diamond

            tops[@ranking.rank[diamond]] - RowGaps::CLOSE - (height / 2.0)
          end

          private

          def hang(tail_edge)
            head = @edges.find { |entry| lane?(entry, tail_edge.from) }
            return unless head

            @tails[tail_edge.from] = tail_edge.to
            @heads[head.to] = tail_edge.from
          end

          # A step that reaches the closing diamond beside its row, from
          # more than one row up.
          def closing?(edge)
            edge.to.kind == :merge && !@ranking.back?(edge) &&
              @ranking.rank[edge.to] - @ranking.rank[edge.from] > 1 &&
              @exits.beside?(edge)
          end

          # The edge that brings a decision's side branch to the first step
          # of a lane ending at `tail`; the lane is those two steps.
          def lane?(entry, tail)
            step = entry.to
            entry.from.kind == :decision && @exits.beside?(entry) &&
              @ranking.forward(step).map(&:to) == [tail]
          end
        end
      end
    end
  end
end
