# frozen_string_literal: true

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
          LABEL_DROP = 13.0
          private_constant :DETOUR, :DETOUR_STEP, :LABEL_DROP

          # @param boxes [Hash{Node => Box}]
          # @param ranking [Ranking]
          # @param bottoms [Array<Float>] bottom of each row
          # @param gap [Float] space between rows
          def initialize(boxes:, ranking:, bottoms:, gap:)
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
            case shape(edge, from, to)
            when :side_exit then side_exit(from, to, end_x)
            when :side_entry then side_entry(from, to, start_x)
            when :straight then straight(from, to, start_x)
            else elbow(edge, [from, to], start_x, end_x)
            end
          end

          def shape(edge, from, to)
            return :straight if same_column?(from, to)
            return :side_exit if edge.from.kind == :decision

            edge.to.kind == :merge ? :side_entry : :elbow
          end

          def straight(from, to, x_pos)
            Route.new(points: [[x_pos, from.bottom], [x_pos, to.top]],
                      label_x: x_pos + 5, label_y: from.bottom + LABEL_DROP)
          end

          def elbow(edge, boxes, start_x, end_x)
            from, to = boxes
            return straight(from, to, start_x) if start_x == end_x

            mid = @bottoms[@ranking.rank[edge.from]] + (@gap / 2.0)
            Route.new(points: [[start_x, from.bottom], [start_x, mid],
                               [end_x, mid], [end_x, to.top]],
                      label_x: start_x + 5, label_y: from.bottom + LABEL_DROP)
          end

          def side_exit(from, to, end_x)
            sign = to.cx > from.cx ? 1 : -1
            edge_x = sign.positive? ? from.right : from.left
            Route.new(points: [[edge_x, from.cy], [end_x, from.cy],
                               [end_x, to.top]],
                      label_x: edge_x + (sign * 4), label_y: from.cy - 4,
                      anchor: sign.positive? ? "start" : "end")
          end

          def side_entry(from, to, start_x)
            edge_x = start_x > to.cx ? to.right : to.left
            Route.new(points: [[start_x, from.bottom], [start_x, to.cy],
                               [edge_x, to.cy]],
                      label_x: start_x + 5, label_y: from.bottom + LABEL_DROP)
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
