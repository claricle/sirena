# frozen_string_literal: true

require_relative "box"
require_relative "mark"
require_relative "scroll_marks"
require_relative "widget"

module Sirena
  module Notation
    module PlantUMLSalt
      # The groups PlantUML frames with something more than a rule: `{^` a
      # box whose title sits in its top edge, `{/` a row of tabs, and `{S`
      # a box with scroll bars. Each is a frame cut at every cell boundary,
      # as the one `{+` draws, plus what hangs from it.
      module GroupMarks
        # A title is a line high and sits over the frame's top edge; the
        # group reserves a second line below it that nothing fills.
        TITLE_LEFT = 6.0
        WHITE = "#FFFFFF"

        private

        # What a group adds to its content's width and height.
        def group_room(block)
          [block.vertical_bar? ? ScrollMarks::BAR_ROOM : 0.0, group_drop(block)]
        end

        def group_drop(block)
          drop = block.horizontal_bar? ? ScrollMarks::BAR_ROOM : 0.0
          block.titled? ? drop + (2 * title_line(block)) : drop
        end

        def title_line(block)
          line_of(runs_size(block.title))
        end

        # The frame and the content's start: a titled box's frame runs from
        # the middle of its title, and its content starts below the title.
        def group_boxes(block, area)
          lift = block.titled? ? title_line(block) : 0.0
          frame = Box.new(area.left, area.top + (lift / 2),
                          *framed_size(block, area, lift))
          [frame, Box.new(area.left, area.top + lift, frame.width, 0.0)]
        end

        def framed_size(block, area, lift)
          width, drop = group_room(block)
          [area.width - width, area.height - drop + lift - (lift / 2)]
        end

        def group_frame(block, frame, lefts, tops)
          cut_frame(frame, lefts, tops)
          overlay { title(block, frame) } if block.titled?
          vertical_bar(frame) if block.vertical_bar?
          horizontal_bar(frame) if block.horizontal_bar?
        end

        # The heading on a white ground that hides the frame's edge.
        def title(block, frame)
          box = title_box(block, frame)
          @marks << ground(box)
          text(block.title, box.left, box.top + runs_drop(block.title))
        end

        def title_box(block, frame)
          line = title_line(block)
          Box.new(frame.left + TITLE_LEFT, frame.top - (line / 2),
                  runs_width(block.title), line)
        end

        def ground(box)
          Mark.new(:rect, box, fill: WHITE, ink: WHITE)
        end
      end
    end
  end
end
