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
        OPEN_HEIGHT = 45
        RECT_OPEN_HEIGHT = 10
        CLOSE_HEIGHT = 10
        RECT_CLOSE_HEIGHT = 8
        SECTION_HEIGHT = 45
        # A frame or section with no text lacks the label line.
        UNLABELLED_DROP = 20
        SLOT_HALF = 34
        SIDE_MARGIN = 11
        NEST_MARGIN = 10
        TAB_MIN_WIDTH = 50
        TAB_CHAR_WIDTH = 8
        TAB_PADDING = 18
        TAB_HEIGHT = 20
        BOX_PAD = 5
        BOX_AFTER = 15
        BOX_EDGE = 25
        BOX_HEADER = 27
        BOX_HEADER_BARE = 10
        BOX_BELOW = 10
        BOX_TOP = 5
        BOX_TITLE_BASELINE = 21
        BOX_BOTTOM_PAD = 10
        TITLE_BASELINE = 18
        DIVIDER_OFFSET = 5
        LOOP_WIDTH = 56
        NO_NOTES = Class.new do
          def slots_before(_index, _order) = 0

          def x_range(_from, _to) = nil
        end.new.freeze

        # @param frames [Array<Hash>] from FrameReader
        # @param boxes [Array<Hash>] from FrameReader
        # @param spans [Array<Array>] the [source, target] ids of each
        #   message, by message index
        # @param ids [Array<String>] participant ids, left to right
        def initialize(frames: [], boxes: [], spans: [], ids: [])
          @frames = frames
          @boxes = boxes
          @spans = spans
          @ids = ids
          @notes = NO_NOTES
        end

        # Extra space above the participant row when there is a box: more
        # when a box has a title.
        def top_inset
          return 0 if @boxes.empty?

          titled_box? ? BOX_HEADER : BOX_HEADER_BARE
        end

        # Distance every row at `index` or below is pushed down.
        def row_shift(index)
          (0..index).sum { |at| room(at) }
        end

        def total_shift = row_shift(@spans.length)

        # Room a box leaves under the canvas for its own frame.
        def bottom_inset
          @boxes.empty? ? 0 : BOX_BELOW
        end

        def gap_before(id)
          @boxes.count { |box| box[:members].first == id } * BOX_PAD
        end

        def gap_after(id)
          @boxes.count { |box| box[:members].last == id } * BOX_AFTER
        end

        # A box ending the diagram has no neighbour to push away.
        def extra_width
          @boxes.sum do |box|
            BOX_PAD + (box[:members].last == @ids.last ? BOX_PAD : BOX_AFTER)
          end
        end

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

        def titled_box? = @boxes.any? { |box| !box[:title].empty? }

        def room(index)
          opening(index).sum { |frame| open_height(frame) } +
            closing(index).sum { |frame| close_height(frame) } +
            sections_height(index)
        end

        def opening(index) = @frames.select { |f| f[:start] == index }

        def closing(index) = @frames.select { |f| f[:stop] == index }

        def sections_at(index)
          @frames.flat_map { |f| f[:sections] }.select do |section|
            section[:start] == index
          end
        end

        def open_height(frame)
          return RECT_OPEN_HEIGHT if frame[:kind] == "rect"

          labelled_height(OPEN_HEIGHT, frame[:label])
        end

        def section_height(section)
          labelled_height(SECTION_HEIGHT, section[:label])
        end

        def labelled_height(height, label)
          label.empty? ? height - UNLABELLED_DROP : height
        end

        def close_height(frame)
          frame[:kind] == "rect" ? RECT_CLOSE_HEIGHT : CLOSE_HEIGHT
        end

        def edges(index)
          opening_edges(index) + closing_edges(index) + section_edges(index)
        end

        def opening_edges(index)
          opening(index).map { |f| edge(f[:open_order], open_height(f)) }
        end

        def closing_edges(index)
          closing(index).map { |f| edge(f[:close_order], close_height(f)) }
        end

        def section_edges(index)
          sections_at(index).map { |s| edge(s[:order], section_height(s)) }
        end

        def edge(order, height) = { order: order, height: height }

        # Top of the room stacked at `index`, note slots included.
        def base(index, row_y)
          row_y.call(index) - SLOT_HALF - room(index) -
            @notes.slots_before(index, Float::INFINITY)
        end

        def frame_shape(index, positions, row_y)
          frame = @frames.fetch(index)
          box = frame_box(index, frame, positions, row_y)
          attributes = box.merge(frame_decoration(frame))
          shape = FrameShape.new(kind: frame[:kind], **attributes)
          shape.dividers = dividers(index, row_y)
          shape
        end

        def frame_box(index, frame, positions, row_y)
          left, right = horizontal_extent(frame, positions)
          top = frame_top(index, row_y)
          bottom = [frame_bottom(index, row_y), top + TAB_HEIGHT].max
          { x: left, y: top, width: right - left, height: bottom - top }
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
          base(start, row_y) + closing_room(start) + sections_height(start) +
            opened_before(index, start) +
            @notes.slots_before(start, frame[:open_order])
        end

        def closing_room(at)
          closing(at).sum { |frame| close_height(frame) }
        end

        def sections_height(at)
          sections_at(at).sum { |section| section_height(section) }
        end

        def opened_before(index, start)
          earlier = @frames.first(index).select { |f| f[:start] == start }
          earlier.sum { |f| open_height(f) }
        end

        def frame_bottom(index, row_y)
          frame = @frames.fetch(index)
          base(frame[:stop], row_y) +
            (CLOSE_HEIGHT * deeper_closing(frame)) +
            @notes.slots_before(frame[:stop], frame[:close_order])
        end

        def deeper_closing(frame)
          closing(frame[:stop]).count { |f| f[:depth] > frame[:depth] }
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
          notes = @notes.slots_before(at, section[:order])
          line_y = divider_top(at, rank, row_y) + notes
          FrameDivider.new(y: line_y, text: "[#{section[:label]}]",
                           text_y: line_y + TITLE_BASELINE)
        end

        def divider_top(at, rank, row_y)
          earlier = sections_at(at).first(rank)
          base(at, row_y) + closing_room(at) + DIVIDER_OFFSET +
            earlier.sum { |section| section_height(section) }
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
          left, right = box_extent(members, positions, widths)
          BoxShape.new(
            x: left, y: BOX_TOP, width: right - left,
            height: bottom - BOX_TOP, color: box[:color],
            title: box[:title].empty? ? nil : box[:title],
            title_y: BOX_TOP + BOX_TITLE_BASELINE
          )
        end

        def box_extent(members, positions, widths)
          lefts = members.map { |id| positions[id][:x] }
          rights = members.map { |id| positions[id][:x] + widths.fetch(id) }
          [lefts.min - BOX_EDGE, rights.max + BOX_EDGE]
        end
      end
    end
  end
end
