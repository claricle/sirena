# frozen_string_literal: true

require_relative "placement"
require_relative "route"

module Sirena
  module Notation
    module PlantUML
      module Activity
        # Draws every edge as straight and right-angled segments between the
        # placed nodes. Loops go round the left, forward edges that skip
        # rows round the right.
        class Router
          DETOUR = 16.0
          DETOUR_STEP = 7.0
          private_constant :DETOUR, :DETOUR_STEP

          # @param boxes [Hash{Node => Box}]
          # @param ranking [Ranking]
          # @param bottoms [Array<Float>] bottom of each row
          # @param gap [Float] space between rows
          # @param label_drop [Float] how far below a node a label's
          #   baseline sits
          def initialize(boxes:, ranking:, bottoms:, gap:, label_drop: 13.0)
            @label_drop = label_drop
            @boxes = boxes
            @ranking = ranking
            @bottoms = bottoms
            @gap = gap
            @detours = Hash.new(0)
          end

          # @return [Route]
          def call(edge)
            from = @boxes.fetch(edge.from)
            to = @boxes.fetch(edge.to)
            side = detour_side(edge, from, to)
            return detour(edge, from, to, side) if side

            forward(edge, from, to)
          end

          private

          def detour_side(edge, from, to)
            return :left if @ranking.back?(edge)

            skips = @ranking.rank[edge.to] - @ranking.rank[edge.from] > 1
            :right if skips && same_column?(from, to)
          end

          def forward(edge, from, to)
            start_x = anchor_x(edge.from, from, to)
            end_x = anchor_x(edge.to, to, from)
            shape = shape(edge, from, to)
            return decision_exit(from, to, end_x) if shape == :side_exit

            below_frame(edge, hanging(shape, edge, [from, to],
                                      [start_x, end_x]))
          end

          # A route that leaves the bottom of `from`.
          def hanging(shape, edge, boxes, anchors)
            case shape
            when :side_entry then side_entry(*boxes, anchors.first)
            when :straight then straight(*boxes, anchors.first)
            else elbow(edge, boxes, *anchors)
            end
          end

          # An edge that leaves a partition from the node's bottom crosses
          # the frame's bottom edge; its label hangs below that edge.
          def below_frame(edge, route)
            leaving = edge.from.partition
            return route unless leaving && leaving != edge.to.partition

            Route.new(points: route.points, label_x: route.label_x,
                      label_y: route.label_y + Placement::PARTITION_BELOW,
                      anchor: route.anchor)
          end

          def shape(edge, from, to)
            return :straight if same_column?(from, to)
            return :side_exit if edge.from.kind == :decision

            edge.to.kind == :merge ? :side_entry : :elbow
          end

          def straight(from, to, x_pos)
            Route.new(points: [[x_pos, from.bottom], [x_pos, to.top]],
                      label_x: x_pos + 5, label_y: from.bottom + @label_drop)
          end

          def elbow(edge, boxes, start_x, end_x)
            from, to = boxes
            return straight(from, to, start_x) if start_x == end_x

            mid = @bottoms[@ranking.rank[edge.from]] + (@gap / 2.0)
            Route.new(points: [[start_x, from.bottom], [start_x, mid],
                               [end_x, mid], [end_x, to.top]],
                      label_x: start_x + 5, label_y: from.bottom + @label_drop)
          end

          # A branch that lands under the decision's own tip needs no side
          # run: it drops straight, as the first branch of a switch does.
          def decision_exit(from, to, end_x)
            return straight(from, to, end_x) if (end_x - from.cx).abs < 1

            side_exit(from, to, end_x)
          end

          def side_exit(from, to, end_x)
            sign = end_x > from.cx ? 1 : -1
            edge_x = sign.positive? ? from.right : from.left
            # The label rides the branch's own drop, so the branches that
            # share one horizontal run do not print their labels on top of
            # each other.
            Route.new(points: [[edge_x, from.cy], [end_x, from.cy],
                               [end_x, to.top]],
                      label_x: end_x + 5, label_y: from.cy + @label_drop)
          end

          def side_entry(from, to, start_x)
            edge_x = start_x > to.cx ? to.right : to.left
            Route.new(points: [[start_x, from.bottom], [start_x, to.cy],
                               [edge_x, to.cy]],
                      label_x: start_x + 5, label_y: from.bottom + @label_drop)
          end

          # Out of one side of `from`, along a lane beside every node in
          # the rows between, and into the same side of `to`.
          def detour(edge, from, to, side)
            lane = lane_x(boxes_between(edge), side)
            left = side == :left
            ends = left ? [from.left, to.left] : [from.right, to.right]
            Route.new(points: loop_points(from, to, ends, lane),
                      label_x: ends.first + (left ? -4 : 4),
                      label_y: from.cy - 4, anchor: left ? "end" : "start")
          end

          def loop_points(from, to, ends, lane)
            [[ends.first, from.cy], [lane, from.cy], [lane, to.cy],
             [ends.last, to.cy]]
          end

          def boxes_between(edge)
            first, last = [@ranking.rank[edge.from],
                           @ranking.rank[edge.to]].minmax
            @boxes.filter_map do |node, box|
              box if (first..last).cover?(@ranking.rank[node])
            end
          end

          def lane_x(boxes, side)
            offset = DETOUR + (DETOUR_STEP * (@detours[side] += 1))
            if side == :left
              boxes.map(&:left).min - offset
            else
              boxes.map(&:right).max + offset
            end
          end

          def same_column?(from, to)
            (from.cx - to.cx).abs < 1
          end

          # A bar is crossed wherever its neighbour stands.
          def anchor_x(node, box, other)
            return box.cx unless node.kind == :bar

            other.cx.clamp(box.left, box.right)
          end
        end
      end
    end
  end
end
