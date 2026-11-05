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
          # @return [Hash{Node => Array(Node, Node)}] for each decision that
          #   splits into side by side branches, its first and last branch;
          #   the decision's own column is a trunk hung between them
          attr_reader :spans

          # @return [Boolean] whether the decision splits three or more ways
          def wide?(node)
            @wide.include?(node)
          end

          def initialize(diagram, ranking)
            @diagram = diagram
            @ranking = ranking
            @lane_names = diagram.lanes.map(&:first)
            @key = {}.compare_by_identity
            @taken = Set.new
            @widest = Hash.new(-1)
            start_branch_tables
            place_all
          end

          private

          def start_branch_tables
            @last = Hash.new(-1)
            @trunks = Set.new
            @spans, @joins, @after = Array.new(3) { {}.compare_by_identity }
            @wide = Set.new.compare_by_identity
          end

          def place_all
            pending = @diagram.nodes.dup
            until pending.empty?
              node = pending.find { |n| ready?(n) } || pending.first
              place(node, beside(node)) unless @key[node]
              pending.reject! { |n| @key[n] }
            end
          end

          # A node reached along a row waits for the node it lies beside.
          def ready?(node)
            level = level_in(node)
            level.nil? || !@key[level.from].nil?
          end

          def level_in(node)
            @ranking.level_in(node)
          end

          def beside(node)
            edge = level_in(node)
            return 0 unless edge && @key[edge.from]

            column = @key[edge.from].last
            edge.direction == :left ? column - 1 : column + 1
          end

          def place(node, preferred)
            lane = lane_of(node)
            column = free_column(lane, preferred, @ranking.rank[node])
            @key[node] = [lane, column]
            @widest[lane] = [@widest[lane], column.ceil].max
            note_depth(lane, column, @ranking.rank[node])
            hang_branches(node, lane, column)
            place_children(node, lane, column)
          end

          def place_children(node, lane, column)
            heads = @spans[node]
            keep = heads.nil?
            @ranking.forward(node).each do |edge|
              next if placed_or_held?(edge)

              place(edge.to, preference(edge.to, [lane, column, keep], heads))
              keep = false
            end
            close_branches(node, lane, column)
          end

          def placed_or_held?(edge)
            @key[edge.to] || edge.level? || pending?(edge.to)
          end

          def preference(child, spot, heads)
            lane, column, keep = spot
            return column - 0.5 if heads && child.equal?(heads.first)
            return 0 unless lane_of(child) == lane
            return column if keep
            return room_right(lane, column, child) if heads

            @widest[lane] + 1
          end

          # The nearest column on the right that no step of an earlier part
          # of the flow still reaches down to, and that no decision hangs
          # from.
          def room_right(lane, column, child)
            rank = @ranking.rank[child]
            found = column.floor + 1
            found += 1 while @trunks.include?([lane, found]) ||
                @last[[lane, found]] >= rank ||
                @taken.include?([lane, found, rank])
            found
          end

          # The node where a decision's branches meet waits until they are
          # all placed, then goes on the trunk.
          def pending?(node)
            @joins.key?(node)
          end

          def close_branches(node, _lane, column)
            join = @after[node]
            return unless join && !@key[join]

            @joins.delete(join)
            place(join, column)
          end

          # A decision with two or more branches of its own keeps its
          # column for the flow that runs through it: its first branch
          # takes the column on its left, the rest those on its right, and
          # the node where they meet goes back to the trunk.
          def hang_branches(node, lane, column)
            heads = @ranking.forward(node).map(&:to)
            join = split_join(node, heads)
            return unless join && lane_of(join) == lane

            @spans[node] = [heads.first, heads.last]
            @wide << node if heads.size > 2
            @trunks << [lane, column]
            @joins[join] = column
            @after[node] = join
          end

          # The merge that closes a decision with two or more branches of
          # its own, when it has one.
          def split_join(node, heads)
            return unless forks?(node, heads)

            join = join_of(heads)
            join if join&.kind == :merge
          end

          def forks?(node, heads)
            node.kind == :decision && heads.size > 1 &&
              heads.none? { |head| head.kind == :merge }
          end

          def note_depth(lane, column, rank)
            @last[[lane, column]] = [@last[[lane, column]], rank].max
          end

          # The first node every branch reaches, nearest first.
          def join_of(heads)
            common = heads.map { |head| downstream(head) }.reduce(:&)
            common.min_by { |node| @ranking.rank[node] }
          end

          def downstream(node, seen = Set.new.compare_by_identity)
            return seen unless seen.add?(node)

            @ranking.forward(node).each { |edge| downstream(edge.to, seen) }
            seen
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
