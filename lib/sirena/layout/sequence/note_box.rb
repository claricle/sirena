# frozen_string_literal: true

require_relative "../../diagram/sequence_text"
require_relative "geometry"
require_relative "text_width"
require_relative "text_wrap"

module Sirena
  module Layout
    class Sequence < Base
      # The box of one note and the text lines inside it. A note that
      # mermaid wraps is sized first, then broken to fit its width; any
      # other note is as wide as its widest line.
      class NoteBox
        LINE_BREAK = Diagram::SequenceText::LINE_BREAK
        PADDING = 20
        SIDE_GAP = 25
        MIN_WIDTH = Geometry::ACTOR_WIDTH

        # @param entry [Hash] text and position of the note
        # @param centers [Array<Numeric>] center x of the actors it names
        # @param size [Numeric] note text size
        # @param wrap [Boolean] the diagram's wrap setting
        # @param actor_width [Numeric] width of the first named actor
        def initialize(entry, centers, size:, wrap: false,
                       actor_width: MIN_WIDTH)
          @entry = entry
          @centers = centers
          @size = size
          @wrap = wrap
          @actor_width = actor_width
        end

        # @return [Array<String>] the text lines, as the source writes them
        def lines
          @lines ||= if wrapped? && @centers.any?
                       TextWrap.lines(body, width - PADDING, @size)
                     else
                       plain_lines
                     end
        end

        # @return [Numeric] width of the box
        def width
          box.first
        end

        # @return [Numeric] x of the box's left edge
        def left
          box.last
        end

        private

        def box
          @box ||= case @entry[:position]
                   when "left_of" then side_box(-1)
                   when "right_of" then side_box(1)
                   else over_box
                   end
        end

        def wrapped?
          return false if body.empty?

          TextWrap.wrapped?(@entry[:text].to_s, @wrap)
        end

        def body
          TextWrap.body(@entry[:text].to_s)
        end

        def plain_lines
          body.split(LINE_BREAK, -1)
        end

        def side_box(side)
          wide = side_width(side)
          return [wide, @centers.first + SIDE_GAP] if side.positive?

          [wide, @centers.first - SIDE_GAP - wide]
        end

        def side_width(side)
          return unwrapped_width unless wrapped?

          text = widest(TextWrap.lines(body, MIN_WIDTH, @size))
          [text + (side.negative? ? PADDING : 0), MIN_WIDTH].max
        end

        def unwrapped_width
          [widest(plain_lines) + PADDING, MIN_WIDTH].max
        end

        def over_box
          span = @centers.max - @centers.min
          width = over_width(span)
          [width, ((@centers.min + @centers.max) / 2.0) - (width / 2)]
        end

        def over_width(span)
          return span + (2 * SIDE_GAP) if wrapped? && span.positive?
          return [@actor_width, MIN_WIDTH].max if wrapped?

          [unwrapped_width, span + (2 * SIDE_GAP)].max
        end

        def widest(text_lines)
          TextWidth.widest(text_lines, @size).to_f
        end
      end
    end
  end
end
