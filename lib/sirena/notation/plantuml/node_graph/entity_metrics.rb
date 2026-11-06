# frozen_string_literal: true

require_relative "../../../text_measurement"

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # The size of an entity box, from its name and field sections.
        module EntityMetrics
          FONT_SIZE = 12
          HEADER = 32.0
          ROW = 16.5
          SECTION_PAD = 8.0
          SPOT = 11.0
          SPOT_ROOM = (2 * SPOT) + 4
          INDENT = 20.0
          MIN_WIDTH = 60.0

          module_function

          # @return [Array(Float, Float)] width and height of the entity
          def size(node)
            sections = node.sections || []
            [[header_width(node), fields_width(sections), MIN_WIDTH].max,
             HEADER + sections.sum { |rows| section_height(rows) }]
          end

          def header_width(node)
            SPOT_ROOM + 12 + text_width(node.lines.join(" "))
          end

          def fields_width(sections)
            widths = sections.flatten.map { |f| text_width(f.text) }
            widths.max.to_f + INDENT + 8
          end

          def section_height(rows)
            SECTION_PAD + (rows.size * ROW)
          end

          def text_width(text)
            Drawing::Face.width(text, size: FONT_SIZE).to_f
          end
        end
      end
    end
  end
end
