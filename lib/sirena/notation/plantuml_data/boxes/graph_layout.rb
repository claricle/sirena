# frozen_string_literal: true

require_relative "frames"
require_relative "heads"
require_relative "marks"
require_relative "scene"
require_relative "table_box"

module Sirena
  module Notation
    module PlantUMLData
      module Boxes
        # Lays an object diagram out in ranks: a relation's left end sits
        # a rank before its right end, boxes of one rank stand in a row (a
        # column when the diagram runs left to right) in the order they were
        # declared, and every rank is centred on the widest.
        class GraphLayout
          RANK_GAP = 50.0
          SIBLING_GAP = 30.0
          MARGIN = 7.0
          TITLE_BAND = 30.0
          Rect = Data.define(:x, :y, :width, :height) do
            def centre = [x + (width / 2), y + (height / 2)]
            def right = x + width
            def bottom = y + height
          end
          private_constant :RANK_GAP, :SIBLING_GAP, :MARGIN, :TITLE_BAND, :Rect

          # @param diagram [Diagram]
          # @return [Scene]
          def call(diagram, **)
            @diagram = diagram
            @tables = diagram.tables.to_h { |t| [t.id, t] }
            @rects = place
            @frames = Frames.new(diagram.tables, @rects).frames
            nudge
            scene([*frame_marks, *table_marks, *link_marks, *title_marks])
          end

          private

          # Moves everything right and down when a frame reaches past the
          # margin.
          def nudge
            dx = [MARGIN - extent.map(&:x).min, 0].max
            dy = [band - extent.map(&:y).min, 0].max
            @rects = moved(@rects, dx, dy)
            @frames = moved(@frames, dx, dy)
          end

          def extent
            [*@rects.values, *@frames.values]
          end

          def moved(boxes, across, down)
            boxes.transform_values do |box|
              box.with(x: box.x + across, y: box.y + down)
            end
          end

          def frame_marks
            @frames.values.reverse.flat_map { |frame| Frames.marks(frame) }
          end

          def table_marks
            @diagram.tables.flat_map do |table|
              rect = @rects[table.id]
              TableBox.draw(table, rect.x, rect.y)
            end
          end

          def link_marks
            @diagram.links.flat_map { |link| draw_link(link) }
          end

          def scene(marks)
            Scene.new(width: extent.map(&:right).max + MARGIN + 1,
                      height: extent.map(&:bottom).max + MARGIN + 1,
                      marks: marks)
          end

          def title_marks
            return [] unless @diagram.title

            width = @rects.values.map(&:right).max + MARGIN
            [Marks.text(@diagram.title, width / 2, MARGIN + 8,
                        bold: true, anchor: "middle")]
          end

          def across?
            @diagram.direction == :right
          end

          # The size of a box along the ranks and across them.
          def main_of(box)
            across? ? box.width : box.height
          end

          def cross_of(box)
            across? ? box.height : box.width
          end

          def band
            MARGIN + (@diagram.title ? TITLE_BAND : 0)
          end

          def place
            lanes = @tables.keys.group_by { |id| rank(id, []) }.sort.map(&:last)
            lane_rects(lanes, lanes.map { |ids| lane_boxes(ids) })
          end

          def lane_boxes(ids)
            ids.map { |id| TableBox.size(@tables[id]) }
          end

          def span_of(boxes)
            boxes.sum { |box| cross_of(box) } + (sibling_gap * (boxes.size - 1))
          end

          def lane_rects(lanes, sizes)
            spans = sizes.map { |boxes| span_of(boxes) }
            lanes.zip(sizes, lane_starts(sizes), spans).map do |*lane, span|
              cross = (across? ? band : MARGIN) + ((spans.max - span) / 2)
              place_lane(*lane, cross)
            end.reduce({}, :merge)
          end

          # The coordinate along the ranks at which each lane begins.
          def lane_starts(sizes)
            main = across? ? MARGIN : band
            sizes.map do |boxes|
              start = main
              main += boxes.map { |box| main_of(box) }.max + rank_gap
              start
            end
          end

          # Frames take room between ranks and between boxes of a rank.
          def rank_gap
            RANK_GAP + framed_room
          end

          def sibling_gap
            SIBLING_GAP + framed_room
          end

          def framed_room
            @diagram.tables.any? { |t| t.group.any? } ? Frames::ROOM : 0.0
          end

          def place_lane(ids, boxes, main, cross)
            ids.zip(boxes).to_h do |id, box|
              rect = box_rect(box, main, cross)
              cross += cross_of(box) + sibling_gap
              [id, rect]
            end
          end

          def box_rect(box, main, cross)
            x, y = across? ? [main, cross] : [cross, main]
            Rect.new(x, y, box.width, box.height)
          end

          def rank(id, visiting)
            return 0 if visiting.include?(id)

            @ranks ||= {}
            @ranks[id] ||= parents(id).map do |parent|
              rank(parent, visiting + [id]) + 1
            end.max || 0
          end

          def parents(id)
            @diagram.links.filter_map do |l|
              l.from if l.to == id && l.from != id && @tables.key?(l.from)
            end
          end

          def draw_link(link)
            from = @rects.fetch(link.from)
            to = @rects.fetch(link.to)
            if link.from_row.is_a?(Row)
              tree_link(link, from, to)
            else
              line_link(link, from, to)
            end
          end

          def tree_link(link, from, to)
            start = tree_start(link, from)
            stop = [to.x, to.y + (to.height / 2)]
            [Marks.curve(start, stop, dashed: true), arrowhead(stop),
             Marks.dot(start)]
          end

          def tree_start(link, rect)
            table = @tables.fetch(link.from)
            index = table.rows.index do |r|
              r.equal?(link.from_row) || r.port == link.from_row
            end
            [rect.right - 11.6, TableBox.row_middle(table, index.to_i, rect.y)]
          end

          def arrowhead(stop)
            Marks.polygon([[stop[0] - 8, stop[1] - 3], stop,
                           [stop[0] - 8, stop[1] + 3]])
          end

          def line_link(link, from, to)
            start = anchor(link.from, link.from_row, from, to.centre)
            stop = anchor(link.to, link.to_row, to, from.centre)
            [line_mark(link, start, stop),
             *heads(link.glyph[:markers], start, stop),
             *label(link, start, stop)]
          end

          def heads(markers, start, stop)
            [*Heads.call(markers[:left], start, stop),
             *Heads.call(markers[:right], stop, start)]
          end

          def line_mark(link, start, stop)
            { kind: :path, d: "M #{start.join(' ')} L #{stop.join(' ')}",
              dashed: link.glyph[:dashed], stroke: Marks::INK }
          end

          def label(link, start, stop)
            return [] if link.label.to_s.empty?

            [Marks.text(link.label, (start[0] + stop[0]) / 2,
                        ((start[1] + stop[1]) / 2) - 6, anchor: "middle")]
          end

          def anchor(id, port, rect, toward)
            table = @tables.fetch(id)
            index = port && table.rows.index { |r| r.port == port }
            return border(rect, toward) unless index

            side = toward[0] >= rect.centre[0] ? rect.right : rect.x
            [side, TableBox.row_middle(table, index, rect.y)]
          end

          # Where the line from the rectangle's centre to `toward` leaves it.
          def border(rect, toward)
            centre = rect.centre
            delta = toward.zip(centre).map { |to, from| to - from }
            return centre if delta.all?(&:zero?)

            scale = reach(rect, delta)
            centre.zip(delta).map { |from, d| from + (d * scale) }
          end

          # How far along the line half of the rectangle lies.
          def reach(rect, delta)
            [rect.width, rect.height].zip(delta).map do |size, d|
              (size / 2) / (d.abs.zero? ? 1e-9 : d.abs)
            end.min
          end
        end
      end
    end
  end
end
