# frozen_string_literal: true

require_relative "metrics"

module Sirena
  module Notation
    module PlantUML
      module Activity
        # Draws a node, and the notes beside it.
        class NodeMarks
          PAPER = "#F1F1F1"
          NOTE_PAPER = "#FEFFDD"
          INK = "#181818"
          BAR_GREY = "#555555"
          FOLD = 6.0
          TAIL_HALF = 4.0
          private_constant :PAPER, :NOTE_PAPER, :INK, :BAR_GREY, :FOLD,
                           :TAIL_HALF

          def initialize(boxes, canvas, metrics)
            @boxes = boxes
            @canvas = canvas
            @metrics = metrics
          end

          # @param node [Node]
          def draw(node)
            box = @boxes.fetch(node)
            case node.kind
            when :start
              @canvas.circle(box, 10.0, fill: "#222222", role: :start)
            when :stop, :kill, :end then terminal(node, box)
            when :merge then diamond(box, node.fill)
            when :bar then bar(node, box)
            when :decision then decision(node, box)
            else action(node, box)
            end
          end

          # @param node [Node] the node the note is attached to
          # @param note [Note]
          # @param box [Box] where the note sits
          def note(node, note, box)
            @canvas.polygon(outline(box, @boxes.fetch(node), note.side),
                            fill: NOTE_PAPER, role: :note)
            pad = Metrics::NOTE_PAD
            @canvas.lines(note.lines,
                          [box.left + pad,
                           box.top + pad + @metrics.ascent(:note)],
                          role: :note)
          end

          private

          # A rectangle with its top right corner folded, and the note's
          # tail: a wedge from the middle of the edge facing the node to the
          # node's border, as PlantUML draws it.
          def outline(box, anchor, side)
            if side == :right
              return folded(box) + floor(box) + west(box,
                                                     anchor)
            end

            folded(box) + east(box, anchor) + floor(box)
          end

          def west(box, anchor)
            wedge(box.left, anchor.right, box.cy, -1)
          end

          def east(box, anchor)
            wedge(box.right, anchor.left, box.cy, 1)
          end

          def folded(box)
            [[box.left, box.top], [box.right - FOLD, box.top],
             [box.right, box.top + FOLD]]
          end

          def floor(box)
            [[box.right, box.bottom], [box.left, box.bottom]]
          end

          # @param edge [Float] x of the note's edge
          # @param tip [Float] x of the node's border
          # @param sign [Integer] 1 walking down the edge, -1 walking up
          def wedge(edge, tip, mid, sign)
            [[edge, mid - (sign * TAIL_HALF)], [tip, mid],
             [edge, mid + (sign * TAIL_HALF)]]
          end

          def action(node, box)
            @canvas.rect(box, fill: node.fill || PAPER, radius: 12.5)
            centred(node.lines, box)
          end

          def decision(node, box)
            return diamond(box, node.fill) if node.bare

            @canvas.polygon(hexagon(box), fill: node.fill || PAPER,
                                          role: :diamond)
            centred(node.lines, box, role: :diamond)
          end

          def hexagon(box)
            left = box.left + Metrics::DECISION_POINT
            right = box.right - Metrics::DECISION_POINT
            [[left, box.top], [right, box.top], [box.right, box.cy],
             [right, box.bottom], [left, box.bottom], [box.left, box.cy]]
          end

          def diamond(box, fill)
            @canvas.polygon([[box.cx, box.top], [box.right, box.cy],
                             [box.cx, box.bottom], [box.left, box.cy]],
                            fill: fill || PAPER, role: :diamond)
          end

          def terminal(node, box)
            case node.kind
            when :kill then kill(box)
            when :end then final(box)
            else stop(box)
            end
          end

          def stop(box)
            @canvas.circle(box, 11.0, fill: "none")
            @canvas.circle(box, 6.0, fill: "#222222")
          end

          def final(box)
            @canvas.circle(box, 10.0, fill: "none", width: 1.5)
            cross(box, 6.2, 2.5)
          end

          def kill(box)
            cross(box, 9.0, 2.0)
          end

          def cross(box, reach, width)
            [[-1, -1, 1, 1], [-1, 1, 1, -1]].each do |ax, ay, bx, by|
              @canvas.path([[box.cx + (ax * reach), box.cy + (ay * reach)],
                            [box.cx + (bx * reach), box.cy + (by * reach)]],
                           stroke: "#222222", width: width)
            end
          end

          def bar(node, box)
            draw_bar(node, box)
            return if node.legacy || !node.text

            @canvas.lines([node.text], [box.right + 6, box.cy + 4],
                          size: Metrics::FONT_SIZE)
          end

          # PlantUML draws a legacy bar as a grey slab and a fork bar as a
          # grey rounded one.
          def draw_bar(node, box)
            return @canvas.rect(box, fill: BAR_GREY) if node.legacy

            @canvas.rect(box, fill: BAR_GREY, stroke: BAR_GREY, radius: 2.5,
                              role: :bar)
          end

          def centred(rows, box, role: nil)
            height = @metrics.text_height(rows, role: role)
            first = box.cy - (height / 2.0) + @metrics.ascent(role)
            @canvas.lines(rows, [box.cx, first], anchor: "middle", role: role)
          end
        end
      end
    end
  end
end
