# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Activity
        # Gives each node a column. A walk down the forward edges keeps a
        # node's first unplaced successor in its column and sends the others
        # to fresh columns on its right, so branches do not cross the body
        # they split from. With swimlanes a node sits in its lane's columns.
        class Columns
          # @return [Hash{Node => Array(Integer, Integer)}] lane index and
          #   column inside the lane
          attr_reader :key

          def initialize(diagram, ranking)
            @diagram = diagram
            @ranking = ranking
            @lane_names = diagram.lanes.map(&:first)
            @key = {}.compare_by_identity
            @taken = Set.new
            @widest = Hash.new(-1)
            diagram.nodes.each { |node| place(node, 0) unless @key[node] }
          end

          private

          def place(node, preferred)
            lane = lane_of(node)
            column = free_column(lane, preferred, @ranking.rank[node])
            @key[node] = [lane, column]
            @widest[lane] = [@widest[lane], column].max
            place_children(node, lane, column)
          end

          def place_children(node, lane, column)
            keep = true
            @ranking.forward(node).each do |edge|
              next if @key[edge.to]

              place(edge.to, child_preference(edge.to, lane, column, keep))
              keep = false
            end
          end

          def child_preference(child, lane, column, keep_in_column)
            return 0 unless lane_of(child) == lane
            return column if keep_in_column

            @widest[lane] + 1
          end

          def free_column(lane, preferred, rank)
            column = preferred
            column += 1 while @taken.include?([lane, column, rank])
            @taken << [lane, column, rank]
            column
          end

          def lane_of(node)
            node.lane ? @lane_names.index(node.lane) : -1
          end
        end
      end
    end
  end
end
