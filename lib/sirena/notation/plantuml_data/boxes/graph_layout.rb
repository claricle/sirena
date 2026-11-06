# frozen_string_literal: true

require_relative "../../../text_measurement"
require_relative "frames"
require_relative "heads"
require_relative "link_text"
require_relative "marks"
require_relative "row_alignment"
require_relative "row_bend"
require_relative "scene"
require_relative "table_box"

module Sirena
  module Notation
    module PlantUMLData
      module Boxes
        # Lays an object diagram out in ranks: a relation's left end sits
        # as many ranks before its right end as its line is long less one
        # (`->` none, `-->` one, `--->` two), boxes of one rank stand in a
        # row (a column when the diagram runs left to right) in the order
        # they were declared, a box tied to another by a relation of no rank
        # right after it, and every rank is centred on the widest.
        class GraphLayout
          RANK_GAP = 60.0
          # A label on a line between neighbouring ranks takes a text row of
          # its own between them, the JAR's way: 17 for one line, 15 more
          # for each further line.
          LABEL_ROW = 15.0
          LABEL_PAD = 2.0
          DASH = "7,7"
          FONT_SIZE = 14
          SIBLING_GAP = 35.0
          MARGIN = 7.0
          TITLE_BAND = 30.0
          Rect = Data.define(:x, :y, :width, :height) do
            def centre = [x + (width / 2), y + (height / 2)]
            def right = x + width
            def bottom = y + height
          end
          private_constant :RANK_GAP, :LABEL_ROW, :LABEL_PAD, :SIBLING_GAP,
                           :MARGIN, :TITLE_BAND, :Rect, :DASH, :FONT_SIZE

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
            right = [extent.map(&:right).max, *text_rights(marks)].max
            Scene.new(width: right + MARGIN + 1,
                      height: extent.map(&:bottom).max + MARGIN + 1,
                      marks: marks)
          end

          # How far right the texts that start at a point and run on reach.
          def text_rights(marks)
            marks.filter_map do |mark|
              next unless mark[:kind] == :text && mark[:anchor].nil?

              mark[:x] + TextMeasurement.measure(
                mark[:content], font_size: FONT_SIZE
              )[:width].to_f
            end
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
            lanes = @tables.keys.group_by { |id| rank(id, []) }.sort
              .map { |_, ids| lane_order(ids) }
            rects = lane_rects(lanes, lanes.map { |ids| lane_boxes(ids) })
            across? ? rects : row_aligned(rects, lanes)
          end

          def row_aligned(rects, lanes)
            alone = lanes.select { |ids| ids.size == 1 }.flatten
            RowAlignment.new(@diagram.links).call(rects, alone)
          end

          def lane_boxes(ids)
            ids.map { |id| TableBox.size(@tables[id]) }
          end

          def span_of(boxes)
            boxes.sum { |box| cross_of(box) } + (sibling_gap * (boxes.size - 1))
          end

          def lane_rects(lanes, sizes)
            spans = sizes.map { |boxes| span_of(boxes) }
            starts = lane_starts(lanes, sizes)
            lanes.zip(sizes, starts, spans).map do |*lane, span|
              cross = (across? ? band : MARGIN) + ((spans.max - span) / 2)
              place_lane(*lane, cross)
            end.reduce({}, :merge)
          end

          # The coordinate along the ranks at which each lane begins.
          def lane_starts(lanes, sizes)
            main = across? ? MARGIN : band
            sizes.each_index.map do |index|
              start = main
              main += sizes[index].map { |box| main_of(box) }.max +
                rank_gap + label_room(lanes, index)
              start
            end
          end

          # The room the labels of the lines from lane `index` to the next
          # lane take: the tallest of them.
          def label_room(lanes, index)
            rows = @diagram.links.filter_map do |link|
              label_rows(link, lanes[index], lanes[index + 1])
            end.max
            rows ? LABEL_PAD + (rows * LABEL_ROW) : 0.0
          end

          def label_rows(link, above, below)
            return unless below && above.include?(link.from)
            return if !below.include?(link.to) || link.label.to_s.empty?

            link.label.split(/\\n|\n/).size
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
            @ranks[id] ||= parents(id).map do |parent, step|
              rank(parent, visiting + [id]) + step
            end.max || 0
          end

          # @return [Array<Array(String, Integer)>] each box with a relation
          #   into `id`, and the ranks that relation spans
          def parents(id)
            @diagram.links.filter_map do |l|
              next unless l.to == id && l.from != id && @tables.key?(l.from)

              [l.from, step(l)]
            end
          end

          # A direction word says it (`left` and `right` keep the ends in one
          # rank, `up` and `down` span one), as does a one-dash line (`->`,
          # which reads as `right`); otherwise the line is one shorter than
          # it is long. A JSON link spans one.
          def step(link)
            glyph = link.glyph
            return 1 unless glyph[:length]
            return direction_step(glyph[:direction]) if glyph[:direction]

            [glyph[:length] - 1, 0].max
          end

          def direction_step(word)
            %i[left right].include?(word) ? 0 : 1
          end

          # `ids` with each box tied to another of the rank by a relation of
          # no rank placed right after that box.
          def lane_order(ids)
            ids.each_with_object([]) { |id, out| settle(id, ids, out, []) }
          end

          def settle(id, ids, out, path)
            return if out.include?(id)

            parent = flat_parent(id, ids)
            if parent && !path.include?(parent)
              settle(parent, ids, out, path + [id])
              out.insert(after(parent, ids, out), id)
            else
              out << id
            end
          end

          def after(parent, ids, out)
            at = out.index(parent) + 1
            at += 1 while out[at] && flat_parent(out[at], ids) == parent
            at
          end

          def flat_parent(id, ids)
            @diagram.links.find do |l|
              l.to == id && l.from != id && ids.include?(l.from) &&
                step(l).zero?
            end&.from
          end

          def draw_link(link)
            line_link(link, @rects.fetch(link.from), @rects.fetch(link.to))
          end

          def line_link(link, from, to)
            start = anchor(link.from, link.from_row, from, to.centre)
            stop = anchor(link.to, link.to_row, to, from.centre)
            bend = row_bend(link, [start, stop], from, to)
            [line_mark(link, start, stop, bend),
             *heads(link.glyph[:markers], start, stop, bend),
             *LinkText.call(link, start, stop)]
          end

          def heads(markers, start, stop, bend)
            [*Heads.call(markers[:left], start, bend ? bend[0] : stop),
             *Heads.call(markers[:right], stop, bend ? bend[1] : start)]
          end

          def line_mark(link, start, stop, bend)
            { kind: :path, d: path_d(start, stop, bend),
              dashed: link.glyph[:dashed], dash: DASH, stroke: Marks::INK }
          end

          def path_d(start, stop, bend)
            return "M #{start.join(' ')} L #{stop.join(' ')}" unless bend

            "M #{start.join(' ')} C #{bend[0].join(' ')} " \
              "#{bend[1].join(' ')} #{stop.join(' ')}"
          end

          # Nil for a link between whole boxes, which stays straight.
          def row_bend(link, ends, from, to)
            return unless link.from_row || link.to_row

            rows = [link.from_row, link.to_row].map { |port| !port.nil? }
            RowBend.handles(ends, rows, [from.centre, to.centre])
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
