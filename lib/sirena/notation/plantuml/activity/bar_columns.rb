# frozen_string_literal: true

module Sirena
  module Notation
    module PlantUML
      module Activity
        # Where a bar stands: it hangs over the branches it joins, and a
        # decision whose branch starts with one aims at the middle of them.
        class BarColumns
          # How far a bar reaches past the boxes it joins; PlantUML leaves 12
          # on the left and 14 on the right.
          OVERHANG = 13.0

          def initialize(diagram, ranking, columns, boxes)
            @diagram = diagram
            @ranking = ranking
            @columns = columns
            @boxes = boxes
          end

          # @return [Array<Node>] the nodes on the side of the bar where
          #   several branches meet it, or all its neighbours when no side
          #   has more than the other
          def fan(bar)
            sides = joined(bar).group_by do |node|
              @ranking.rank[node] <=> @ranking.rank[bar]
            end.values
            widest = sides.map(&:size).max
            sides.select { |side| side.size == widest }.flatten
          end

          # @return [Array<Array>, nil] the columns of the boxes a bar fans
          #   out to or gathers; nil for any other node
          def fan_keys(node)
            return unless node.kind == :bar

            fan(node).map { |other| @columns.key[other] }
          end

          # Gives the outermost columns a bar joins room for its overhang.
          # @param reach [Hash{Array => Array(Float, Float)}]
          def widen(reach)
            @diagram.nodes.select { |n| n.kind == :bar }.each do |bar|
              widen_bar(reach, bar)
            end
            reach
          end

          private

          def widen_bar(reach, bar)
            boxes = fan(bar).map { |n| [@columns.key[n], @boxes[n]] }
            return if boxes.empty?

            overhang(reach, boxes.min_by(&:first), 0)
            overhang(reach, boxes.max_by(&:first), 1)
          end

          def overhang(reach, (key, box), side)
            reach[key][side] =
              [reach[key][side], (box.width / 2.0) + OVERHANG].max
          end

          def joined(bar)
            @diagram.edges.filter_map do |edge|
              other = edge.from.equal?(bar) ? edge.to : edge.from
              other if (edge.from.equal?(bar) || edge.to.equal?(bar)) &&
                other.kind != :bar
            end
          end
        end
      end
    end
  end
end
