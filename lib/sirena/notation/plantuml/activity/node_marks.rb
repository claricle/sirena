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
          private_constant :PAPER, :NOTE_PAPER, :INK, :BAR_GREY, :FOLD

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
            when :stop, :kill then terminal(node, box)
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
            @canvas.polygon(outline(box), fill: NOTE_PAPER, role: :note)
            pad = Metrics::NOTE_PAD
            @canvas.lines(note.lines,
                          [box.left + pad,
                           box.top + pad + @metrics.ascent(:note)],
                          role: :note)
            connector(@boxes.fetch(node), note.side, box)
          end

          private

          # A rectangle with its top right corner folded.
          def outline(box)
            [[box.left, box.top], [box.right - FOLD, box.top],
             [box.right, box.top + FOLD], [box.right, box.bottom],
             [box.left, box.bottom]]
          end

          def connector(anchor, side, box)
            near = if side == :right
                     [anchor.right,
                      box.left]
                   else
                     [anchor.left, box.right]
                   end
            @canvas.path(near.map { |x_pos| [x_pos, anchor.cy] }, stroke: INK,
                                                                  dash: "7,5")
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
            node.kind == :kill ? kill(box) : stop(box)
          end

          def stop(box)
            @canvas.circle(box, 11.0, fill: "none")
            @canvas.circle(box, 6.0, fill: "#222222")
          end

          def kill(box)
            reach = 9.0
            [[-1, -1, 1, 1], [-1, 1, 1, -1]].each do |ax, ay, bx, by|
              @canvas.path([[box.cx + (ax * reach), box.cy + (ay * reach)],
                            [box.cx + (bx * reach), box.cy + (by * reach)]],
                           stroke: "#222222", width: 2.0)
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
