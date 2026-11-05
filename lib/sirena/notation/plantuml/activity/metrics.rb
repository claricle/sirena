# frozen_string_literal: true

require_relative "../../../text_measurement"
require_relative "../style"
require_relative "box"

module Sirena
  module Notation
    module PlantUML
      module Activity
        # Sizes of the shapes, from the text they carry and the font size
        # the source gives each role (action, diamond, note, arrow,
        # partition). A larger font grows the box, never overflows it.
        class Metrics
          FONT_SIZE = 12
          LINE_HEIGHT = 15.0
          PAD_X = 12.0
          PAD_Y = 8.0
          NOTE_PAD = 7.0
          FIXED = { start: [20.0, 20.0], stop: [24.0, 24.0], kill: [24.0, 24.0],
                    merge: [14.0, 14.0], bar: [40.0, 6.0] }.freeze

          # Skinparam names PlantUML reads for a role, besides the role.
          SKIN_ALIASES = { diamond: :activitydiamond,
                           arrow: :activityarrow }.freeze
          private_constant :SKIN_ALIASES

          # @param style [Style::Sheet]
          def initialize(style = Style::Sheet.new)
            @style = style
          end

          # PlantUML cascades `activityDiagram` down to every role from
          # `<style>` only; skinparam `activityFontSize` is the action's.
          #
          # @param role [Symbol, nil] :diamond, :note, :arrow, :partition;
          #   nil is an action
          # @return [Numeric] the font size of the role's text
          def size(role = nil)
            written = role ? role_size(role) : activity_size
            return FONT_SIZE unless written

            written.to_i == written ? written.to_i : written
          end

          # @return [Float] the distance between the baselines of two lines
          def line_height(role = nil)
            LINE_HEIGHT * size(role) / FONT_SIZE
          end

          # @return [Float] the baseline of a line below the top of its row
          def ascent(role = nil)
            11.0 * size(role) / FONT_SIZE
          end

          # @return [Float] the width of the widest of the lines
          def text_width(lines, role: nil, size: size(role))
            lines.map do |line|
              TextMeasurement.measure(line, font_size: size)[:width]
            end.max.to_f
          end

          def text_height(lines, role: nil)
            [lines.size, 1].max * line_height(role)
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
            Box.new(width: [(1.8 * text_width(lines, role: :diamond)) + 16,
                            40.0].max,
                    height: [(1.8 * text_height(lines, role: :diamond)) + 16,
                             32.0].max)
          end

          # @return [Box] a note's box
          def note_box(note)
            Box.new(width: text_width(note.lines, role: :note) +
                           (2 * NOTE_PAD) + 6,
                    height: text_height(note.lines, role: :note) +
                            (2 * NOTE_PAD))
          end

          private

          def activity_size
            @style.explicit(:activity, :font_size)
          end

          def role_size(role)
            @style.from_style(role, :font_size) ||
              @style.from_style(:activity, :font_size) || skin_size(role)
          end

          def skin_size(role)
            [role, SKIN_ALIASES[role]].compact.filter_map do |name|
              @style.explicit(name, :font_size)
            end.first
          end
        end
      end
    end
  end
end
