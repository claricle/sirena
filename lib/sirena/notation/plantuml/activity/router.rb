# frozen_string_literal: true

require_relative "exits"
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
          JOG = 11.97
          RUN_LIFT = 2.32
          private_constant :DETOUR, :DETOUR_STEP, :JOG, :RUN_LIFT

          # @param boxes [Hash{Node => Box}]
          # @param ranking [Ranking]
          # @param bottoms [Array<Float>] bottom of each row
          # @param gaps [Array<Float>] space above each row
          # @param label_drop [Float] how far below a node a label's
          #   baseline sits
          def initialize(boxes:, ranking:, bottoms:, gaps:, label_drop: 13.0)
            @label_drop = label_drop
            @boxes = boxes
            @ranking = ranking
            @bottoms = bottoms
            @gaps = gaps
            @detours = Hash.new(0)
          end

          # @return [Route]
          def call(edge)
            from = @boxes.fetch(edge.from)
            to = @boxes.fetch(edge.to)
            return level(edge, from, to) if level?(edge)

            side = detour_side(edge, from, to)
            return detour(edge, from, to, side) if side

            forward(edge, from, to)
          end

          private

          def level?(edge)
            edge.level? && !@ranking.back?(edge) &&
              @ranking.rank[edge.from] == @ranking.rank[edge.to]
          end

          # Along the row: out of the side of `from` that faces `to`. A
          # parked `to` sits half a row lower, so the arrow runs on to
          # above its middle and drops into it.
          def level(edge, from, to)
            right = to.cx >= from.cx
            ends = right ? [from.right, to.left] : [from.left, to.right]
            return parked_level(edge, from, to, ends.first) if parked?(from, to)

            Route.new(points: ends.map { |x_pos| [x_pos, from.cy] },
                      **level_label(edge, from, ends))
          end

          def parked?(from, to)
            (from.cy - to.cy).abs > 1
          end

          def parked_level(edge, from, to, start_x)
            Route.new(points: [[start_x, from.cy], [to.cx, from.cy],
                               [to.cx, to.top]],
                      **level_label(edge, from, [start_x, to.cx]))
          end

          # The label sits at the start of the run, unless a sibling exit
          # leaves the same side of the decision and prints its own there:
          # then it sits at the far end.
          def level_label(edge, from, ends)
            return { label_x: ends.min + 5, label_y: from.cy - 4 } unless
              shared_side?(edge, from, ends.last)

            { label_x: ends.max - 4, label_y: from.cy - 4, anchor: "end" }
          end

          def shared_side?(edge, from, end_x)
            return false unless edge.from.kind == :decision

            @ranking.forward(edge.from).any? do |other|
              sibling_beside?(other, edge, from, end_x)
            end
          end

          def sibling_beside?(other, edge, from, end_x)
            return false if other.equal?(edge) || other.level?

            offset = @boxes.fetch(other.to).cx - from.cx
            offset.abs >= from.width / 2.0 &&
              (offset <=> 0) == (end_x <=> from.cx)
          end

          def detour_side(edge, from, to)
            return :left if @ranking.back?(edge)
            return unless skips?(edge)
            return :right if same_column?(from, to)

            blocked_side(edge, from, to)
          end

          def skips?(edge)
            @ranking.rank[edge.to] - @ranking.rank[edge.from] > 1
          end

          # Round the left when everything in the way lies to the right.
          def blocked_side(edge, from, to)
            boxes = blockers(edge, from, to)
            return if boxes.empty?

            boxes.all? { |box| box.cx > from.cx } ? :left : :right
          end

          # Boxes on the rows between that stand where the edge drops.
          def blockers(edge, from, to)
            rows = (@ranking.rank[edge.from] + 1)...@ranking.rank[edge.to]
            drops = [from.cx, to.cx]
            @boxes.filter_map do |node, box|
              box if blocks?(node, box, rows, drops)
            end
          end

          def blocks?(node, box, rows, drops)
            node.kind != :bar && rows.cover?(@ranking.rank[node]) &&
              drops.any? { |x_pos| x_pos.between?(box.left, box.right) }
          end

          def forward(edge, from, to)
            start_x = anchor_x(edge.from, from, to, edge)
            end_x = anchor_x(edge.to, to, from, edge)
            shape = shape(edge, from, to)
            return decision_exit(from, to, end_x, edge) if shape == :side_exit

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

            side_entry?(edge, from, to) ? :side_entry : :elbow
          end

          def side_entry?(edge, from, to)
            edge.to.kind == :merge && !Exits.top_entry?(edge, from, to)
          end

          def straight(from, to, x_pos)
            Route.new(points: [[x_pos, from.bottom], [x_pos, to.top]],
                      label_x: x_pos + 5, label_y: from.bottom + @label_drop)
          end

          def elbow(edge, boxes, start_x, end_x)
            from, to = boxes
            return straight(from, to, start_x) if start_x == end_x

            mid = run_height(edge)
            Route.new(points: [[start_x, from.bottom], [start_x, mid],
                               [end_x, mid], [end_x, to.top]],
                      label_x: start_x + 5, label_y: from.bottom + @label_drop)
          end

          # Halfway down the space below the edge's row.
          def run_height(edge)
            row = @ranking.rank[edge.from]
            @bottoms[row] + (@gaps.fetch(row + 1, 0.0) / 2.0)
          end

          # A branch that lands under the decision's own tip needs no side
          # run: it drops straight, as the first branch of a switch does.
          def decision_exit(from, to, end_x, edge)
            return straight(from, to, end_x) if (end_x - from.cx).abs < 1
            return jog_exit(from, to, end_x) if (end_x - from.cx).abs <
              from.width / 2.0

            side_exit(from, to, end_x, edge)
          end

          # Down from the decision's foot, across, and down into the step.
          def jog_exit(from, to, end_x)
            level = from.bottom + JOG
            Route.new(points: [[from.cx, from.bottom], [from.cx, level],
                               [end_x, level], [end_x, to.top]],
                      label_x: end_x + 5, label_y: level + @label_drop)
          end

          def side_exit(from, to, end_x, edge)
            sign = end_x > from.cx ? 1 : -1
            edge_x = sign.positive? ? from.right : from.left
            Route.new(points: [[edge_x, from.cy], [end_x, from.cy],
                               [end_x, to.top]],
                      **exit_label(edge, [edge_x, end_x], from, sign))
          end

          # Two branches carry their label along the run, by the decision's
          # tip. Where there are more, the label rides the branch's own
          # drop, so branches that share one run do not print their labels
          # on top of each other.
          def exit_label(edge, ends, from, sign)
            if @ranking.forward(edge.from).size > 2
              return { label_x: ends.last + 5, label_y: from.cy + @label_drop }
            end

            { label_x: ends.first, label_y: from.cy - RUN_LIFT,
              anchor: sign.positive? ? "start" : "end" }
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

          # A bar is crossed wherever its neighbour stands. A decision
          # reaches for the middle of the branches the bar fans out to.
          def anchor_x(node, box, other, edge)
            return box.cx unless node.kind == :bar
            return box.anchor if edge.from.kind == :decision &&
              !box.fan&.any? { |f| f.equal?(other) }

            other.cx.clamp(box.left, box.right)
          end
        end
      end
    end
  end
end
