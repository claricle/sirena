# frozen_string_literal: true

require_relative "../../../layout/base"
require_relative "note"
require_relative "note_geometry"
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
          SELF_WIDTH = Walker::SELF_WIDTH
          private_constant :MARGIN, :HEAD_PADDING, :MIN_HEAD_WIDTH, :MIN_GAP,
                           :SELF_WIDTH, :BOX_PADDING, :BOX_TITLE_HEIGHT

          def scene(diagram)
            @diagram = diagram
            @widths = diagram.participants.map { |p| head_width(p) }
            @centers = centers(@widths)
            @head_height = head_height
            @top = MARGIN + (@diagram.boxes.empty? ? 0 : BOX_TITLE_HEIGHT)
            @flow = walk
            recentre if @flow.left < MARGIN
            build(@widths)
          end

          private

          def walk
            bounds = [@centers.first - @widths.first / 2,
                      @centers.last + @widths.last / 2]
            Walker.new(centers: @centers, ids: ids, bounds: bounds,
                       measure: ->(text) { text_width(text) },
                       font_size: font_size,
                       y: @top + @head_height + Walker::ROW)
              .run(@diagram.items)
          end

          # Items such as a note left of the first participant stick out
          # past the margin; move everything right instead of clipping.
          def recentre
            shift = MARGIN - @flow.left
            @centers = @centers.map { |centre| centre + shift }
            @flow = walk
          end

          def build(widths)
            heads = place_heads(widths, @top) + place_heads(widths, @flow.y)
            Scene.new(width: canvas_width(widths),
                      height: @flow.y + @head_height + MARGIN,
                      frames: frames(widths), heads: heads,
                      lifelines: lifelines, arrows: @flow.arrows,
                      fragments: @flow.fragments, notes: @flow.notes,
                      dividers: @flow.dividers)
          end

          def head_height
            plain = @diagram.participants.all? { |p| p.kind == :participant }
            plain ? 36.0 : 56.0
          end

          def head_width(participant)
            text = measure_text(participant.label, font_size: font_size)
            [MIN_HEAD_WIDTH, text[:width] + 2 * HEAD_PADDING,
             boxed_title_width(participant)].max
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
            x = MARGIN + widths.first / 2
            widths.each_index.map do |index|
              x += gaps[index - 1] if index.positive?
              x
            end
          end

          # Distance between neighbouring centres: heads must not overlap and
          # every label must fit on the span it crosses.
          def required_gaps(widths)
            gaps = widths.each_cons(2).map { |a, b| (a + b) / 2 + MIN_GAP }
            @diagram.messages.each { |m| widen(gaps, m) }
            @diagram.boxes.each { |box| widen_box(gaps, box) }
            each_note { |note, span| widen_note(gaps, note, span) }
            gaps
          end

          def each_note
            previous = nil
            @diagram.items.each do |item|
              if item.is_a?(Note)
                yield item, NoteGeometry.span(item, previous, ids)
              end
              previous = item
            end
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

          def widen_over(gaps, between, index, need)
            if between.empty?
              [index - 1, index].each { |i| raise_gap(gaps, i, need / 2 + 12) }
            else
              share = (need - 20) / between.size
              between.each { |i| raise_gap(gaps, i, share) }
            end
          end

          def raise_gap(gaps, index, need)
            gaps[index] = [gaps[index], need].max if index >= 0 && gaps[index]
          end

          def widen_box(gaps, box)
            places = box.members.map { |id| ids.index(id) }.sort
            span = (places.first...places.last).to_a
            need = title_width(box) / span.size
            span.each { |i| gaps[i] = [gaps[i], need].max }
          end

          def ids
            @diagram.participants.map(&:id)
          end

          def widen(gaps, message)
            low, high = indexes(message).sort
            need = label_width(message) + 2 * HEAD_PADDING
            need += SELF_WIDTH if low == high
            span = (low...[high, low + 1].max).select { |i| i < gaps.size }
            span.each { |i| gaps[i] = [gaps[i], need / span.size].max }
          end

          def indexes(message)
            [ids.index(message.from), ids.index(message.to)]
          end

          def label_width(message)
            return 0.0 unless message.label

            measure_text(message.label, font_size: font_size)[:width]
          end

          def canvas_width(widths)
            right = @centers.last + widths.last / 2
            self_room = self_reach(@diagram.participants.size - 1)
            [right, @centers.last + self_room, @flow.right].max + MARGIN
          end

          def self_reach(index)
            labels = @diagram.messages.select do |m|
              m.self_message? && indexes(m).first == index
            end
            return 0.0 if labels.empty?

            SELF_WIDTH + 6 + labels.map { |m| label_width(m) }.max
          end

          def place_heads(widths, y)
            @diagram.participants.each_with_index.map do |participant, index|
              head(participant, @centers[index], widths[index], y)
            end
          end

          def head(participant, centre, width, y)
            Scene::Head.new(
              id: participant.id, kind: participant.kind.to_s,
              x: centre - width / 2, y: y, width: width, height: @head_height,
              texts: head_texts(participant, centre, y)
            )
          end

          def head_texts(participant, centre, y)
            label = text(participant.label, centre, y + @head_height - 12,
                         "participant")
            return [label] if participant.kind == :participant

            [text(participant.kind.to_s, centre, y + 14, "kind"), label]
          end

          def frames(widths)
            @diagram.boxes.map { |box| frame(box, widths) }
          end

          def frame(box, widths)
            first, last = box.members.map { |id| ids.index(id) }.minmax
            left = @centers[first] - widths[first] / 2 - BOX_PADDING
            right = @centers[last] + widths[last] / 2 + BOX_PADDING
            Scene::Frame.new(
              x: left, y: MARGIN, width: right - left,
              height: @flow.y + @head_height + BOX_PADDING - MARGIN,
              texts: [text(box.title, (left + right) / 2, MARGIN + 17, "box")]
            )
          end

          def lifelines
            @centers.map do |centre|
              PlantUML::Scene::Segment.new(
                x1: centre, y1: @top + @head_height,
                x2: centre, y2: @flow.y
              )
            end
          end

          def text(content, x, y, role, anchor = "middle")
            PlantUML::Scene::Text.new(content: content, x: x, y: y,
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
