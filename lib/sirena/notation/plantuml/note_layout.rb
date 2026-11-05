# frozen_string_literal: true

require_relative "creole"
require_relative "scene"

module Sirena
  module Notation
    module PlantUML
      # Notes of a class diagram, placed once the classes are: a note beside
      # a class sits on the side it names with a pointer tail running to the
      # class, a note on a member sits at the member's row, and a free note
      # (`note as N`) stands to the right of everything. Notes on one side of
      # one class stack downwards.
      #
      # Each note is a {Scene::Box} of kind "note" whose first separator is
      # its pointer, tip first, ending on the edge of the note that faces the
      # class.
      class NoteLayout
        GAP = 30.0
        STACK_GAP = 10.0
        FREE_GAP = 20.0
        TEXT_SCALE = 1.15
        LINE_HEIGHT = 15.310546875
        PADDING = 10.0
        SIDE = 21.0
        TEXT_INDENT = 6.0
        FIRST_BASELINE = 17.568
        ROW_CENTRE = 5.2911
        private_constant :GAP, :STACK_GAP, :FREE_GAP, :TEXT_SCALE,
                         :LINE_HEIGHT, :PADDING, :SIDE, :TEXT_INDENT,
                         :FIRST_BASELINE, :ROW_CENTRE

        # A rectangle, as the boxes and notes of a scene are.
        Rect = Struct.new(:x, :y, :width, :height) do
          def self.of(box)
            new(box.x, box.y, box.width, box.height)
          end

          def right
            x + width
          end

          def bottom
            y + height
          end

          def mid_x
            x + (width / 2)
          end

          def mid_y
            y + (height / 2)
          end

          def overlaps?(other)
            x < other.x + other.width && other.x < right &&
              y < other.y + other.height && other.y < bottom
          end

          def moved(across, down)
            Rect.new(x + across, y + down, width, height)
          end
        end
        private_constant :Rect

        # Where a note's top left corner goes, from the class it sits beside,
        # the note's size and the height its centre aims at.
        ORIGINS = {
          left: ->(c, w, h, mid) { [c.x - GAP - w, mid - (h / 2)] },
          right: ->(c, _w, h, mid) { [c.right + GAP, mid - (h / 2)] },
          top: ->(c, w, h, _mid) { [c.mid_x - (w / 2), c.y - GAP - h] },
          bottom: ->(c, w, _h, _mid) { [c.mid_x - (w / 2), c.bottom + GAP] },
        }.freeze
        # How far, in whole gaps, a blocked note moves out on each side.
        OUTWARD = { left: [-1, 0], right: [1, 0], top: [0, -1],
                    bottom: [0, 1] }.freeze
        private_constant :ORIGINS, :OUTWARD

        # @param diagram [Diagram]
        # @param measure [#call] width of a note line at the note font
        # @param member_measure [#call] width of a member row at the class
        #   font; a note on a member points at the near end of that text
        def initialize(diagram, measure, member_measure = measure)
          @diagram = diagram
          @measure = measure
          @member_measure = member_measure
        end

        # @param boxes [Array<Scene::Box>] the placed class boxes
        # @return [Array<Scene::Box>] the note boxes, in source order
        def place(boxes)
          start(boxes)
          @diagram.notes.each_with_index.map do |note, index|
            place_note(note, index).tap { |placed| @others << placed }
          end
        end

        private

        def start(boxes)
          @by_name = boxes.to_h { |box| [box.id, box] }
          @taken = Hash.new(0.0)
          @free_left = free_edge(boxes)
          @free_top = boxes.map(&:y).min.to_f
          @others = boxes.dup
        end

        def free_edge(boxes)
          boxes.map { |box| box.x + box.width }.max.to_f + FREE_GAP
        end

        def place_note(note, index)
          target = note.target && @by_name[note.target]
          target ? attached_note(note, index, target) : free_note(note, index)
        end

        def attached_note(note, index, target)
          member = member_row(note, target)
          frame = Rect.of(target)
          rect = clear_of_others(note.side, target.id,
                                 anchored(note, frame, member))
          build(note, index, rect, pointer_for(note.side, rect, frame, member))
        end

        def free_note(note, index)
          rect = Rect.new(@free_left, @free_top, *size(note))
          @free_top += rect.height + STACK_GAP
          build(note, index, rect, nil)
        end

        def size(note)
          lines = [note.lines.size, 1].max
          [note.lines.map { |line| line_width(line) }.max.to_f + SIDE,
           PADDING + (lines * LINE_HEIGHT)]
        end

        def line_width(line)
          plain = Creole.parse(line).map(&:text).join
          @measure.call(plain) * TEXT_SCALE
        end

        # The baseline-centre of the member's row in the class box, or nil.
        def member_row(note, target)
          index = member_index(note)
          return unless index

          row = member_text(target, index)
          row && [row.x, row.y - ROW_CENTRE, row.content]
        end

        def member_text(target, index)
          target.texts.select { |text| text.role.start_with?("member") }[index]
        end

        def member_index(note)
          return unless note.member

          klass = @diagram.classes.find { |item| item.name == note.target }
          wanted = note.member.delete('"')
          klass&.body&.index { |item| signature(item) == wanted }
        end

        # `counter` and `start(int timeoutms)`: how a note names a member.
        def signature(item)
          return item.name unless item.parameters

          "#{item.name}(#{item.parameters})"
        end

        def anchored(note, target, member)
          width, height = size(note)
          mid = member ? member[1] : target.y + (target.height / 2)
          x, y = ORIGINS.fetch(note.side).call(target, width, height, mid)
          Rect.new(x, y, width, height)
        end

        # Stacks below an earlier note on the same side of the class, then
        # moves outward until nothing else stands in the way.
        def clear_of_others(side, target_id, rect)
          key = [target_id, side]
          rect.y = [rect.y, @taken[key]].max if %i[left right].include?(side)
          rect = step_out(side, rect)
          @taken[key] = rect.bottom + STACK_GAP
          rect
        end

        def step_out(side, rect)
          across, down = OUTWARD.fetch(side)
          rect = rect.moved(across * GAP, down * GAP) while blocked?(rect)
          rect
        end

        def blocked?(rect)
          @others.any? { |box| rect.overlaps?(box) }
        end

        # `[tip, anchor]`: the tip on the class's edge (at the member's row
        # for a member note), the anchor on the note's facing edge.
        def pointer_for(side, rect, target, member)
          tip, anchor = if %i[left right].include?(side)
                          horizontal_pointer(side, rect, target, member)
                        else
                          vertical_pointer(side, rect, target)
                        end
          Scene::Segment.new(x1: tip[0], y1: tip[1], x2: anchor[0],
                             y2: anchor[1])
        end

        def horizontal_pointer(side, rect, target, member)
          mid = rect.mid_y.clamp(rect.y + 6.0, rect.bottom - 6.0)
          row = member ? member[1] : rect.mid_y
          if side == :right
            [[right_tip(target, member), row], [rect.x, mid]]
          else
            [[left_tip(target, member), row], [rect.right, mid]]
          end
        end

        # A member note points at the text itself: the end of the text for a
        # note on the right, its start for a note on the left.
        def right_tip(target, member)
          return target.x + target.width unless member

          member[0] + @member_measure.call(member[2])
        end

        def left_tip(target, member)
          member ? member[0] : target.x
        end

        def vertical_pointer(side, rect, target)
          if side == :top
            return [[rect.mid_x, target.y],
                    [rect.mid_x, rect.bottom]]
          end

          [[rect.mid_x, target.y + target.height], [rect.mid_x, rect.y]]
        end

        def build(note, index, rect, pointer)
          Scene::Box.new(id: "note-#{index}", x: rect.x, y: rect.y,
                         width: rect.width, height: rect.height, kind: "note",
                         fill: note.color, texts: texts(note, rect),
                         separators: [*pointer])
        end

        def texts(note, rect)
          note.lines.each_with_index.map do |line, index|
            Scene::Text.new(content: line, x: rect.x + TEXT_INDENT,
                            y: rect.y + FIRST_BASELINE + (index * LINE_HEIGHT),
                            role: "member_note", anchor: "start")
          end
        end
      end
    end
  end
end
