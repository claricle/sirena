# frozen_string_literal: true

require_relative "../../../layout/base"
require_relative "chrome_rows"
require_relative "edge"
require_relative "ir_adapter"
require_relative "ir_reader"
require_relative "message_wrap"
require_relative "note"
require_relative "note_geometry"
require_relative "numbered_label"
require_relative "parser"
require_relative "picture"
require_relative "ref"
require_relative "ref_shape"
require_relative "scene"
require_relative "walker"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # Places participant heads in one row, the items down the page in
        # source order, and the same heads again at the foot of the lifelines.
        class Layout < Sirena::Layout::Base
          MARGIN = 20.0
          HEAD_PADDING = 12.0
          MIN_HEAD_WIDTH = 80.0
          MIN_GAP = 30.0
          BOX_PADDING = 8.0
          BOX_TITLE_HEIGHT = 26.0
          MIN_WIDTH_PADDING = 14.0
          HEAD_LEADING = 1.1776
          EDGE_GAP = 5.0
          EDGE_MARGIN = 10.0
          PAGE_BREAK_INSET = 6.0
          BANNER_LEFT = 3.0
          BANNER_TOP = 8.0
          BANNER_HEIGHT = 16.64
          BANNER_STEP = 21.64
          BANNER_PADDING = 7.0
          MONOSPACE_ADVANCE = 6.02
          SELF_WIDTH = Walker::SELF_WIDTH
          private_constant :MARGIN, :HEAD_PADDING, :MIN_HEAD_WIDTH, :MIN_GAP,
                           :SELF_WIDTH, :BOX_PADDING, :BOX_TITLE_HEIGHT,
                           :MIN_WIDTH_PADDING, :HEAD_LEADING, :EDGE_GAP,
                           :EDGE_MARGIN,
                           :PAGE_BREAK_INSET, :BANNER_LEFT, :BANNER_TOP,
                           :BANNER_HEIGHT, :BANNER_STEP, :BANNER_PADDING,
                           :MONOSPACE_ADVANCE

          # @param graph [IR::Graph] from {IRAdapter}
          def scene(graph)
            @diagram = pictured(IRReader.call(graph))
            measure_heads
            place_origin
            @flow = walk
            recentre if @flow.left < MARGIN
            build(@widths)
          end

          private

          def place_origin
            @origin = MARGIN + banner_room + chrome_rows.top_room
            @top = @origin + (@diagram.boxes.empty? ? 0 : BOX_TITLE_HEIGHT)
          end

          # Lays out each note's embedded diagram, so the notes know their
          # size before the participants are spaced.
          def pictured(diagram)
            return diagram unless diagram.items.any? { |i| embedding?(i) }

            diagram.with_items(diagram.items.map { |item| picture(item) })
          end

          def embedding?(item)
            item.is_a?(Note) && !item.embedded.nil?
          end

          def picture(item)
            return item unless embedding?(item)

            embedded = item.embedded
            item.with_picture(Picture.new(inner_scene(embedded),
                                          embedded.scale))
          end

          def inner_scene(embedded)
            inner = self.class.new
            inner.theme = theme
            parsed = Parser.new.parse(embedded.document)
            inner.scene(IRAdapter.call(parsed))
          end

          def measure_heads
            @widths = @diagram.participants.map { |p| head_width(p) }
            @centers = centers(@widths)
            @head_height = head_height
          end

          def walk
            @edge_right = right_edge
            Walker.new(lifelines: ids.zip(@centers).to_h, bounds: head_bounds,
                       measure: ->(text) { text_width(text) },
                       font_size: font_size,
                       start_y: @top + @head_height + Walker::ROW)
              .run(@diagram.items, edge_right: @edge_right,
                                   appearance: @diagram.appearance)
          end

          # Where `->]` messages end: past every head, and far enough from
          # each sender to fit its label. Nil when there are none.
          def right_edge
            ends = edge_messages(:right).map do |m|
              @centers[ids.index(m.from)] + edge_room(m)
            end
            return if ends.empty?

            [head_bounds.last + EDGE_GAP, *ends].max
          end

          def edge_messages(side)
            @diagram.messages.select do |m|
              m.edge&.global? && m.edge.side == side
            end
          end

          # Label plus the run either side of it, and the ring if one is drawn.
          def edge_room(message)
            ring = message.edge_end.circle ? Edge::RING_INSET : 0.0
            label_width(message) + Edge::RUN_PADDING + ring
          end

          def head_bounds
            [@centers.first - (@widths.first / 2),
             @centers.last + (@widths.last / 2)]
          end

          # Items such as a note left of the first participant stick out
          # past the margin; move everything right instead of clipping.
          def recentre
            shift = MARGIN - @flow.left
            @centers = @centers.map { |centre| centre + shift }
            @flow = walk
          end

          def build(widths)
            Scene.new(width: canvas_width(widths),
                      height: page_height,
                      banners: banners, title: title_scene(widths),
                      text_blocks: text_blocks(widths),
                      legend: legend_scene(widths),
                      frames: frames(widths),
                      heads: heads(widths),
                      lifelines: lifelines, page_breaks: page_breaks(widths),
                      **flow_items)
          end

          # A dotted line across the page where the first page ends.
          def page_breaks(widths)
            right = canvas_width(widths) - PAGE_BREAK_INSET
            @flow.page_breaks.map do |y|
              PlantUML::Scene::Segment.new(x1: 0.0, y1: y, x2: right, y2: y)
            end
          end

          def heads(widths)
            return place_heads(widths, @top) unless @diagram.footbox?

            place_heads(widths, @top) + place_heads(widths, @flow.y)
          end

          # The lifelines end where the foot heads would begin.
          def foot_height
            @diagram.footbox? ? @head_height : 0.0
          end

          def flow_items
            { arrows: @flow.arrows, fragments: @flow.fragments,
              notes: @flow.notes, dividers: @flow.dividers,
              bars: @flow.bars, crosses: @flow.crosses }
          end

          def head_height
            plain = @diagram.participants.all? do |p|
              p.kind == :participant && p.stereotype.nil?
            end
            (plain ? 36.0 : 56.0) + head_growth
          end

          def head_style
            @diagram.appearance.head_style
          end

          def head_font_size
            head_style.size || font_size
          end

          # PlantUML grows a head by 1.1776 for each point its text grows.
          def head_growth
            (head_font_size - font_size) * HEAD_LEADING
          end

          def head_width(participant)
            text = measure_text(participant.label, font_size: head_font_size)
            [MIN_HEAD_WIDTH, text[:width] + (2 * HEAD_PADDING),
             boxed_title_width(participant), requested_width].max
          end

          # PlantUML draws a head 14 wider than the minimum it is given.
          def requested_width
            return 0.0 unless @diagram.min_head_width

            @diagram.min_head_width + MIN_WIDTH_PADDING
          end

          # A box round one participant is as wide as that head, so the head
          # must be wide enough for the title.
          def boxed_title_width(participant)
            box = @diagram.boxes.find { |b| b.members == [participant.id] }
            box ? title_width(box) : 0.0
          end

          def title_width(box)
            measure_text(box.title, font_size: font_size)[:width]
          end

          def centers(widths)
            gaps = required_gaps(widths)
            x = MARGIN + (widths.first / 2) + left_edge_room(widths, gaps)
            widths.each_index.map do |index|
              x += gaps[index - 1] if index.positive?
              x
            end
          end

          # How far to push every head right so the label of a `[->` message
          # fits between the left edge and the head it points at.
          def left_edge_room(widths, gaps)
            start = MARGIN + (widths.first / 2)
            short = edge_messages(:left).map do |m|
              index = ids.index(m.to)
              edge_room(m) - start - gaps.first(index).sum
            end
            [0.0, *short].max
          end

          # Distance between neighbouring centres: heads must not overlap and
          # every label must fit on the span it crosses.
          def required_gaps(widths)
            gaps = widths.each_cons(2).map { |a, b| ((a + b) / 2) + MIN_GAP }
            widen_for_items(gaps)
            gaps
          end

          def widen_for_items(gaps)
            @diagram.messages.each { |m| widen(gaps, m) }
            @diagram.boxes.each { |box| widen_box(gaps, box) }
            each_note { |note, span| widen_note(gaps, note, span) }
            @diagram.items.grep(Ref).each { |ref| widen_ref(gaps, ref) }
          end

          def each_note
            previous = nil
            @diagram.items.each do |item|
              if free_note?(item, previous)
                yield item, NoteGeometry.span(item, previous, ids)
              end
              previous = item unless item.is_a?(Activation)
            end
          end

          # A note that is not attached to the fragment before it.
          def free_note?(item, previous)
            item.is_a?(Note) && !(item.attached? && previous.is_a?(Fragment))
          end

          # Room beside a note so it does not cover a neighbour's lifeline.
          def widen_note(gaps, note, span)
            need = NoteGeometry.natural_width(note, method(:text_width))
            low, high = span
            case note.side
            when :left then raise_gap(gaps, low - 1, need + 12)
            when :right then raise_gap(gaps, high, need + 12)
            else widen_over(gaps, (low...high).to_a, low, need)
            end
          end

          # A ref wider than the lifelines it names pushes them apart.
          def widen_ref(gaps, ref)
            low, high = ref.targets.map { |id| ids.index(id) }.minmax
            need = RefShape.width_for(ref.label, method(:text_width))
            widen_over(gaps, (low...high).to_a, low, need)
          end

          def widen_over(gaps, between, index, need)
            if between.empty?
              share = (need / 2) + 12
              [index - 1, index].each { |i| raise_gap(gaps, i, share) }
            else
              share = (need - 20) / between.size
              between.each { |i| raise_gap(gaps, i, share) }
            end
          end

          def raise_gap(gaps, index, need)
            gaps[index] = [gaps[index], need].max if index >= 0 && gaps[index]
          end

          def widen_box(gaps, box)
            span = member_span(box)
            need = title_width(box) / span.size
            span.each { |i| raise_gap(gaps, i, need) }
          end

          def member_indexes(box)
            box.members.map { |id| ids.index(id) }
          end

          def member_span(box)
            places = member_indexes(box).sort
            (places.first...places.last).to_a
          end

          def ids
            @diagram.participants.map(&:id)
          end

          def widen(gaps, message)
            return if message.edge

            low, high = indexes(message).sort
            span = gap_span(gaps, message, low, high)
            need = message_room(message, low == high)
            span.each { |i| raise_gap(gaps, i, need / span.size) }
          end

          # The gaps a message crosses; a leftward loop uses the one on the
          # left of its participant.
          def gap_span(gaps, message, low, high)
            return [low - 1] if message.self_message? && message.leftward?

            (low...[high, low + 1].max).select { |i| i < gaps.size }
          end

          def message_room(message, self_message)
            room = label_width(message) + (2 * HEAD_PADDING)
            self_message ? room + SELF_WIDTH : room
          end

          def indexes(message)
            [ids.index(message.from), ids.index(message.to)]
          end

          def label_width(message)
            return 0.0 unless message.label

            wrap.width(message.label) + numbering.extra(message)
          end

          def wrap
            MessageWrap.new(@diagram.appearance.max_message,
                            method(:text_width))
          end

          def numbering
            NumberedLabel.new(method(:text_width))
          end

          def canvas_width(widths)
            padded = [head_extent(widths), @flow.right].max + MARGIN
            [padded, edge_extent, banner_extent, title_extent].max
          end

          def title_extent
            chrome_rows.width
          end

          def chrome_rows
            @chrome_rows ||= ChromeRows.new(@diagram, method(:chrome_width))
          end

          def chrome_width(text, size)
            measure_text(text, font_size: size || font_size)[:width]
          end

          def page_height
            @flow.y + foot_height + MARGIN + chrome_rows.bottom_room
          end

          def chrome_top
            MARGIN + banner_room
          end

          def title_scene(widths)
            chrome_rows.title(chrome_top, canvas_width(widths))
          end

          def text_blocks(widths)
            chrome_rows.blocks(chrome_top, @flow.y + foot_height,
                               canvas_width(widths))
          end

          def legend_scene(widths)
            chrome_rows.legend(chrome_top, @flow.y + foot_height,
                               canvas_width(widths))
          end

          def banner_room
            @diagram.warnings.size * BANNER_STEP
          end

          def banner_extent
            widest = @diagram.warnings.map { |line| banner_width(line) }.max
            widest ? BANNER_LEFT + widest + BANNER_LEFT : 0.0
          end

          def banner_width(line)
            text = line.length * MONOSPACE_ADVANCE
            (text + (2 * BANNER_PADDING)).round(2)
          end

          def banners
            @diagram.warnings.each_with_index.map do |line, index|
              banner(line, BANNER_TOP + (index * BANNER_STEP))
            end
          end

          def banner(line, top)
            width = banner_width(line)
            Scene::Banner.new(
              x: BANNER_LEFT, y: top, width: width, height: BANNER_HEIGHT,
              texts: [PlantUML::Scene::Text.new(
                content: line, x: BANNER_LEFT + BANNER_PADDING,
                y: top + BANNER_HEIGHT - 6, role: "warning", anchor: "start"
              )]
            )
          end

          def head_extent(widths)
            right = @centers.last + (widths.last / 2)
            self_room = self_reach(@diagram.participants.size - 1)
            [right, @centers.last + self_room].max
          end

          def edge_extent
            @edge_right ? @edge_right + EDGE_MARGIN : 0.0
          end

          def self_reach(index)
            labels = @diagram.messages.select do |m|
              m.self_message? && !m.leftward? && indexes(m).first == index
            end
            return 0.0 if labels.empty?

            SELF_WIDTH + 6 + labels.map { |m| label_width(m) }.max
          end

          def place_heads(widths, top)
            @diagram.participants.each_with_index.map do |participant, index|
              head(participant, @centers[index], widths[index], top)
            end
          end

          def head(participant, centre, width, top)
            Scene::Head.new(
              id: participant.id, kind: participant.kind.to_s,
              x: centre - (width / 2), y: top, width: width,
              height: @head_height, fill: participant.fill&.colour,
              fill_opacity: participant.fill&.opacity,
              stroke: head_style.line,
              texts: head_texts(participant, centre, top)
            )
          end

          def head_texts(participant, centre, top)
            label = head_label(participant, centre, top)
            name = above_label(participant)
            return [label] unless name

            lines = [text(name, centre, top + 14, "kind"), label]
            participant.stereotype ? align(lines, centre) : lines
          end

          def head_label(participant, centre, top)
            label = text(participant.label, centre, top + @head_height - 12,
                         "participant")
            restyle(label, head_style)
          end

          def restyle(label, style)
            label.colour = style.colour
            label.size = style.size
            label.family = style.family
            label.font_style = style.style
            label.weight = style.weight
            label
          end

          # Lines of a stereotyped head sit against the edge of the block
          # they form, which is as wide as its widest line.
          def align(lines, centre)
            alignment = @diagram.appearance.alignment
            return lines if alignment == :center

            half = lines.map { |line| line_width(line) }.max / 2
            lines.each do |line|
              line.anchor = alignment == :left ? "start" : "end"
              line.x = alignment == :left ? centre - half : centre + half
            end
          end

          # The renderer draws a "kind" line at 0.85 of the normal size.
          def line_width(line)
            scale = line.role == "kind" ? 0.85 : 1.0
            measure_text(line.content, font_size: font_size * scale)[:width]
          end

          def above_label(participant)
            return "«#{participant.stereotype}»" if participant.stereotype
            return if participant.kind == :participant

            participant.kind.to_s
          end

          def frames(widths)
            @diagram.boxes.map { |box| frame(box, widths) }
          end

          def frame(box, widths)
            left, right = frame_edges(box, widths)
            Scene::Frame.new(
              x: left, y: @origin, width: right - left,
              height: @flow.y + foot_height + BOX_PADDING - @origin,
              texts: [text(box.title, (left + right) / 2, @origin + 17, "box")]
            )
          end

          def frame_edges(box, widths)
            first, last = member_indexes(box).minmax
            [@centers[first] - (widths[first] / 2) - BOX_PADDING,
             @centers[last] + (widths[last] / 2) + BOX_PADDING]
          end

          def lifelines
            @centers.map do |centre|
              PlantUML::Scene::Segment.new(
                x1: centre, y1: @top + @head_height,
                x2: centre, y2: @flow.y
              )
            end
          end

          def text(content, at_x, at_y, role, anchor = "middle")
            PlantUML::Scene::Text.new(content: content, x: at_x, y: at_y,
                                      role: role, anchor: anchor)
          end

          def font_size
            theme.typography.font_size_normal.to_f
          end

          def text_width(string)
            measure_text(string, font_size: font_size)[:width]
          end
        end
      end
    end
  end
end
