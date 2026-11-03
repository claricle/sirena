# frozen_string_literal: true

require_relative "../../../text_measurement"
require_relative "box"

module Sirena
  module Notation
    module PlantUML
      module Activity
        # Sizes of the shapes, from the text they carry.
        module Metrics
          module_function

          FONT_SIZE = 12
          LINE_HEIGHT = 15.0
          PAD_X = 12.0
          PAD_Y = 8.0
          NOTE_PAD = 7.0
          FIXED = { start: [20.0, 20.0], stop: [24.0, 24.0],
                    merge: [14.0, 14.0], bar: [40.0, 6.0] }.freeze

          # @return [Float] the width of the widest of the lines
          def text_width(lines)
            lines.map do |line|
              TextMeasurement.measure(line, font_size: FONT_SIZE)[:width]
            end.max.to_f
          end

          def text_height(lines)
            [lines.size, 1].max * LINE_HEIGHT
          end

          # @param node [Node]
          # @return [Box] a box of the node's size, not yet placed
          def box_for(node)
            return fixed_box(FIXED[node.kind]) if FIXED.key?(node.kind)
            return decision_box(node.lines) if node.kind == :decision

            action_box(node.lines)
          end

          def action_box(lines)
            Box.new(width: text_width(lines) + (2 * PAD_X),
                    height: text_height(lines) + (2 * PAD_Y))
          end

          def fixed_box(size)
            Box.new(width: size.first, height: size.last)
          end

          def decision_box(lines)
            Box.new(width: [(1.8 * text_width(lines)) + 16, 40.0].max,
                    height: [(1.8 * text_height(lines)) + 16, 32.0].max)
          end

          # @return [Box] a note's box
          def note_box(note)
            Box.new(width: text_width(note.lines) + (2 * NOTE_PAD) + 6,
                    height: text_height(note.lines) + (2 * NOTE_PAD))
          end
        end
      end
    end
  end
end
