# frozen_string_literal: true

require_relative "../../../layout/base"
require_relative "scene"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # Places participant heads in one row, messages down the page in
        # source order, and the same heads again at the foot of the lifelines.
        class Layout < Sirena::Layout::Base
          MARGIN = 20.0
          HEAD_PADDING = 12.0
          MIN_HEAD_WIDTH = 80.0
          MIN_GAP = 30.0
          ROW_HEIGHT = 40.0
          SELF_WIDTH = 36.0
          SELF_HEIGHT = 20.0
          ARROW_LENGTH = 10.0
          ARROW_HALF_WIDTH = 4.0
          BOX_PADDING = 8.0
          BOX_TITLE_HEIGHT = 26.0
          private_constant :MARGIN, :HEAD_PADDING, :MIN_HEAD_WIDTH, :MIN_GAP,
                           :ROW_HEIGHT, :SELF_WIDTH, :SELF_HEIGHT,
                           :ARROW_LENGTH, :ARROW_HALF_WIDTH, :BOX_PADDING,
                           :BOX_TITLE_HEIGHT

          def scene(diagram)
            @diagram = diagram
            widths = diagram.participants.map { |p| head_width(p) }
            @centers = centers(widths)
            @head_height = head_height
            @top = MARGIN + (@diagram.boxes.empty? ? 0 : BOX_TITLE_HEIGHT)
            @foot_y = @top + @head_height + ROW_HEIGHT * (rows + 1)
            build(widths)
          end

          private

          def build(widths)
            heads = place_heads(widths, @top) + place_heads(widths, @foot_y)
            Scene.new(width: canvas_width(widths),
                      height: @foot_y + @head_height + MARGIN,
                      frames: frames(widths), heads: heads,
                      lifelines: lifelines, arrows: arrows)
          end

          def rows
            @diagram.messages.sum { |m| m.self_message? ? 1.5 : 1 }
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
            gaps
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
            [right, @centers.last + self_room].max + MARGIN
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
              height: @foot_y + @head_height + BOX_PADDING - MARGIN,
              texts: [text(box.title, (left + right) / 2, MARGIN + 17, "box")]
            )
          end

          def lifelines
            @centers.map do |centre|
              PlantUML::Scene::Segment.new(
                x1: centre, y1: @top + @head_height,
                x2: centre, y2: @foot_y
              )
            end
          end

          def arrows
            y = @top + @head_height + ROW_HEIGHT
            @diagram.messages.each_with_index.map do |message, index|
              arrow = message_arrow(message, index, y)
              y += message.self_message? ? ROW_HEIGHT * 1.5 : ROW_HEIGHT
              arrow
            end
          end

          def message_arrow(message, index, y)
            from, to = indexes(message).map { |i| @centers[i] }
            geometry = if message.self_message?
                         self_geometry(from, y)
                       else
                         straight_geometry(from, to, y)
                       end
            arrow_record(message, index, geometry)
          end

          def straight_geometry(from, to, y)
            sign = to >= from ? 1 : -1
            { path: "M #{from} #{y} L #{to} #{y}",
              tip: [to, y], dx: -sign,
              label: text_geometry((from + to) / 2, y - 6, "middle") }
          end

          def self_geometry(centre, y)
            right = centre + SELF_WIDTH
            bottom = y + SELF_HEIGHT
            { path: "M #{centre} #{y} L #{right} #{y} L #{right} #{bottom} " \
                    "L #{centre} #{bottom}",
              tip: [centre, bottom], dx: 1,
              label: text_geometry(right + 6, y + 12, "start") }
          end

          def text_geometry(x, y, anchor)
            [x, y, anchor]
          end

          def arrow_record(message, index, geometry)
            Scene::Arrow.new(
              id: "message-#{index + 1}", path: geometry[:path],
              dashed: message.dashed,
              marker_points: head_points(geometry[:tip], geometry[:dx]),
              marker_filled: message.head == :filled,
              texts: label_texts(message, geometry[:label])
            )
          end

          def head_points(tip, direction)
            x, y = tip
            back = x + direction * ARROW_LENGTH
            [[x, y], [back, y - ARROW_HALF_WIDTH],
             [back, y + ARROW_HALF_WIDTH]].map { |px, py| "#{px},#{py}" }
              .join(" ")
          end

          def label_texts(message, geometry)
            return [] unless message.label && !message.label.empty?

            x, y, anchor = geometry
            [text(message.label, x, y, "message_label", anchor)]
          end

          def text(content, x, y, role, anchor = "middle")
            PlantUML::Scene::Text.new(content: content, x: x, y: y,
                                      role: role, anchor: anchor)
          end

          def font_size
            theme.typography.font_size_normal.to_f
          end
        end
      end
    end
  end
end
