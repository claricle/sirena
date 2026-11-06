# frozen_string_literal: true

require_relative "../../../text_measurement"
require_relative "../creole"
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
          # The action's size; the other roles' own defaults are
          # ROLE_SIZES, which is what PlantUML draws for an unstyled source.
          FONT_SIZE = 12
          ROLE_SIZES = { diamond: 11, arrow: 11, note: 13,
                         partition: 14 }.freeze
          # The line pitch and baseline of a font size, as PlantUML's
          # default face lays them out (14.1328 and 11.6016 at 12).
          LINE_RATIO = 1.1777
          ASCENT_RATIO = 0.9668
          PAD_X = 10.0
          PAD_Y = 10.0
          NOTE_PAD = 7.0
          # A decision is a hexagon: the text's own width and height, at
          # least this wide and tall, with a point of this reach each side.
          DECISION_POINT = 12.0
          DECISION_MIN = 24.0
          FIXED = { start: [20.0, 20.0], stop: [24.0, 24.0], kill: [24.0, 24.0],
                    end: [24.0, 24.0],
                    merge: [24.0, 24.0], bar: [40.0, 6.0] }.freeze

          # Skinparam names PlantUML reads for a role, besides the role.
          SKIN_ALIASES = { diamond: :activitydiamond,
                           arrow: :activityarrow }.freeze
          private_constant :SKIN_ALIASES

          # @param style [Style::Sheet]
          def initialize(style = Style::Sheet.new)
            @style = style
          end

          # PlantUML cascades `activityDiagram` down to every role from
          # `<style>` only; skinparam `activityFontSize` is the action's
          # and the decision's.
          #
          # @param role [Symbol, nil] :diamond, :note, :arrow, :partition;
          #   nil is an action
          # @return [Numeric] the font size of the role's text
          def size(role = nil)
            written = role ? role_size(role) : activity_size
            return ROLE_SIZES.fetch(role, FONT_SIZE) unless written

            written.to_i == written ? written.to_i : written
          end

          # @return [Float] the distance between the baselines of two lines
          def line_height(role = nil)
            LINE_RATIO * size(role)
          end

          # @return [Float] the baseline of a line below the top of its row
          def ascent(role = nil)
            ASCENT_RATIO * size(role)
          end

          # @return [Float] the width of the widest of the lines
          def text_width(lines, role: nil, size: size(role))
            face = face(role)
            lines.map { |line| line_width(line, face, size) }.max.to_f
          end

          def line_width(line, face, size)
            Creole.parse(line).sum do |run|
              if Creole.monospace?(run.style)
                TextMeasurement.measure(run.text, font_size: size,
                                                  monospace: true)[:width]
              else
                TextMeasurement.measure_in(face, run.text,
                                           font_size: size)[:width]
              end
            end
          end

          def text_height(lines, role: nil)
            [lines.size, 1].max * line_height(role)
          end

          # @param node [Node]
          # @return [Box] a box of the node's size, not yet placed
          def box_for(node)
            return fixed_box(FIXED[node.kind]) if FIXED.key?(node.kind)
            return fixed_box(FIXED[:merge]) if node.bare
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
            Box.new(width: [text_width(lines, role: :diamond),
                            DECISION_MIN].max + (2 * DECISION_POINT),
                    height: [text_height(lines, role: :diamond),
                             DECISION_MIN].max)
          end

          # @return [Box] a note's box
          def note_box(note)
            Box.new(width: text_width(note.lines, role: :note) +
                           (2 * NOTE_PAD) + 6,
                    height: text_height(note.lines, role: :note) +
                            (2 * NOTE_PAD))
          end

          # @return [Symbol] the face the role's text is measured in: the
          #   source's FontName when sirena has the table for it, else the
          #   default face
          def face(role = nil)
            name = written_face(role).to_s.downcase
            TextMeasurement::FACE_TABLES.keys.find do |face|
              name.include?(face.to_s)
            end || :arial
          end

          private

          def written_face(role)
            (role && @style.explicit(role, :font_name)) ||
              @style.explicit(:activity, :font_name)
          end

          def activity_size
            @style.explicit(:activity, :font_size)
          end

          def role_size(role)
            @style.from_style(role, :font_size) ||
              @style.from_style(:activity, :font_size) || skin_size(role)
          end

          def skin_size(role)
            own = [role, SKIN_ALIASES[role]].compact.filter_map do |name|
              @style.explicit(name, :font_size)
            end.first
            own || (activity_size if role == :diamond)
          end
        end
      end
    end
  end
end
