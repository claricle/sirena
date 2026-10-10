# frozen_string_literal: true

require_relative "frame_shape"
require_relative "box_shape"

module Sirena
  module Layout
    class Sequence < Base
      # Decides where the control frames and `box` groups of a sequence
      # diagram go. Frames need room between message rows, so every row
      # below a frame edge is pushed down by `row_shift`.
      #
      # At each message index the room is stacked top to bottom: frames
      # closing there, section dividers, then frames opening. The message
      # row follows.
      #
      # @example A diagram without frames moves nothing
      #   FramePlacement.new.row_shift(3) # => 0
      class FramePlacement
        OPEN_HEIGHT = 30
        RECT_OPEN_HEIGHT = 10
        CLOSE_HEIGHT = 12
        RECT_CLOSE_HEIGHT = 8
        SECTION_HEIGHT = 40
        SLOT_HALF = 30
        SIDE_MARGIN = 11
        NEST_MARGIN = 10
        TAB_MIN_WIDTH = 50
        TAB_CHAR_WIDTH = 8
        TAB_PADDING = 18
        TAB_HEIGHT = 20
        BOX_PAD = 10
        BOX_HEADER = 28
        BOX_TOP = 8
        BOX_BOTTOM_PAD = 10
        TITLE_BASELINE = 18
        DIVIDER_OFFSET = 14
        LOOP_WIDTH = 56
        NO_NOTES = Class.new do
          def slots_before(_index, _order) = 0

          def x_range(_from, _to) = nil
        end.new.freeze

        # @param frames [Array<Hash>] from FrameReader
        # @param boxes [Array<Hash>] from FrameReader
        # @param spans [Array<Array>] the [source, target] ids of each
        #   message, by message index
        def initialize(frames: [], boxes: [], spans: [])
          @frames = frames
          @boxes = boxes
          @spans = spans
          @notes = NO_NOTES
        end

        # Extra space above the participant row when a box has a title.
        def top_inset
          @boxes.any? { |box| !box[:title].empty? } ? BOX_HEADER : 0
        end

        # Distance every row at `index` or below is pushed down.
        def row_shift(index)
          (0..index).sum { |at| room(at) }
        end

        def total_shift = row_shift(@spans.length)

        def gap_before(id)
          @boxes.count { |box| box[:members].first == id } * BOX_PAD
        end

        def gap_after(id)
          @boxes.count { |box| box[:members].last == id } * BOX_PAD
        end

        def extra_width = @boxes.length * 2 * BOX_PAD

        # Height of the frame edges at `index` that come before `order`
        # in the source: where a note written at `order` starts.
        def lead(index, order)
          edges(index).sum do |edge|
            edge[:order] < order ? edge[:height] : 0
          end
        end

        # @param positions [Hash] participant id => position hash
        # @param row_y [Proc] message index => y of that message row,
        #   note slots included
        # @param notes [#slots_before] note slots above a frame edge
        # @return [Array<FrameShape>]
        def frame_shapes(positions, row_y, notes = NO_NOTES)
          @notes = notes
          @frames.each_index.map do |index|
            frame_shape(index, positions, row_y)
          end
        end

        # @param positions [Hash] participant id => position hash
        # @param widths [Hash] participant id => box width
        # @param bottom [Numeric] y of the bottom edge of every box
        # @return [Array<BoxShape>]
        def box_shapes(positions, widths, bottom)
          @boxes.filter_map do |box|
            members = box[:members].select { |id| positions.key?(id) }
            next if members.empty?

            box_shape(box, members, positions, widths, bottom)
          end
        end

        private

        def room(index)
          opening(index).sum { |frame| open_height(frame) } +
            closing(index).sum { |frame| close_height(frame) } +
            (sections_at(index).length * SECTION_HEIGHT)
        end

        def opening(index) = @frames.select { |f| f[:start] == index }

        def closing(index) = @frames.select { |f| f[:stop] == index }

        def sections_at(index)
          @frames.flat_map { |f| f[:sections] }.select do |section|
            section[:start] == index
          end
        end

        def open_height(frame)
          frame[:kind] == "rect" ? RECT_OPEN_HEIGHT : OPEN_HEIGHT
        end

        def close_height(frame)
          frame[:kind] == "rect" ? RECT_CLOSE_HEIGHT : CLOSE_HEIGHT
        end

        def edges(index)
          opening(index).map { |f| edge(f[:open_order], open_height(f)) } +
            closing(index).map { |f| edge(f[:close_order], close_height(f)) } +
            sections_at(index).map { |s| edge(s[:order], SECTION_HEIGHT) }
        end

        def edge(order, height) = { order: order, height: height }

        # Top of the room stacked at `index`, note slots included.
        def base(index, row_y)
          row_y.call(index) - SLOT_HALF - room(index) -
            @notes.slots_before(index, Float::INFINITY)
        end

        def frame_shape(index, positions, row_y)
          frame = @frames.fetch(index)
          left, right = horizontal_extent(frame, positions)
          top = frame_top(index, row_y)
          bottom = [frame_bottom(index, row_y), top + TAB_HEIGHT].max
          FrameShape.new(
            kind: frame[:kind], x: left, y: top, width: right - left,
            height: bottom - top, **frame_decoration(frame)
          ).tap do |shape|
            shape.dividers = dividers(index, row_y)
          end
        end

        def frame_decoration(frame)
          if frame[:kind] == "rect"
            return { color: frame[:label], tab_width: 0 }
          end

          { tab_width: tab_width(frame[:kind]),
            title: frame[:label].empty? ? nil : "[#{frame[:label]}]" }
        end

        def tab_width(kind)
          [TAB_MIN_WIDTH, (kind.length * TAB_CHAR_WIDTH) + TAB_PADDING].max
        end

        def frame_top(index, row_y)
          frame = @frames.fetch(index)
          start = frame[:start]
          earlier = @frames.first(index).select { |f| f[:start] == start }
          base(start, row_y) + closing_room(start) +
            (sections_at(start).length * SECTION_HEIGHT) +
            earlier.sum { |f| open_height(f) } +
            @notes.slots_before(start, frame[:open_order])
        end

        def closing_room(at)
          closing(at).sum { |frame| close_height(frame) }
        end

        def frame_bottom(index, row_y)
          frame = @frames.fetch(index)
          deeper = closing(frame[:stop]).count { |f| f[:depth] > frame[:depth] }
          base(frame[:stop], row_y) - 12 + (CLOSE_HEIGHT * deeper) +
            @notes.slots_before(frame[:stop], frame[:close_order])
        end

        def dividers(index, row_y)
          @frames.fetch(index)[:sections].map do |section|
            divider(section, section_rank(section), row_y)
          end
        end

        def section_rank(section)
          all = @frames.flat_map { |f| f[:sections] }
          all.take_while { |other| !other.equal?(section) }
            .count { |other| other[:start] == section[:start] }
        end

        def divider(section, rank, row_y)
          at = section[:start]
          line_y = base(at, row_y) + closing_room(at) +
                   (SECTION_HEIGHT * rank) + DIVIDER_OFFSET +
                   @notes.slots_before(at, section[:order])
          FrameDivider.new(y: line_y, text: "[#{section[:label]}]",
                           text_y: line_y + TITLE_BASELINE)
        end

        def horizontal_extent(frame, positions)
          centres = span_centres(frame, positions)
          centres = positions.values.map { |p| p[:center_x] } if centres.empty?
          margin = SIDE_MARGIN + (NEST_MARGIN * nesting_below(frame))
          low, high = (centres + note_edges(frame)).minmax
          [low - margin, high + margin]
        end

        def note_edges(frame)
          @notes.x_range(frame[:open_order], frame[:close_order]) || []
        end

        def span_centres(frame, positions)
          (frame[:start]...frame[:stop]).flat_map do |index|
            message_centres(@spans[index], positions)
          end
        end

        def message_centres(span, positions)
          source, target = (span || []).map { |id| positions[id] }
          return [] unless source && target

          centres = [source[:center_x], target[:center_x]]
          return centres unless source.equal?(target)

          centres + [source[:center_x] + LOOP_WIDTH]
        end

        def nesting_below(frame)
          inside = @frames.select do |other|
            other[:depth] > frame[:depth] && other[:start] >= frame[:start] &&
              other[:stop] <= frame[:stop]
          end
          inside.map { |other| other[:depth] - frame[:depth] }.max || 0
        end

        def box_shape(box, members, positions, widths, bottom)
          left = members.map { |id| positions[id][:x] }.min - BOX_PAD
          right = members.map do |id|
            positions[id][:x] + widths.fetch(id)
          end.max + BOX_PAD
          BoxShape.new(
            x: left, y: BOX_TOP, width: right - left,
            height: bottom - BOX_TOP, color: box[:color],
            title: box[:title].empty? ? nil : box[:title],
            title_y: BOX_TOP + TITLE_BASELINE
          )
        end
      end
    end
  end
end
