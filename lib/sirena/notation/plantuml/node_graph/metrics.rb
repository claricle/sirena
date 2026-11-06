# frozen_string_literal: true

require_relative "../../../text_measurement"
require_relative "../../plantuml_data/boxes/table_box"
require_relative "archimate"
require_relative "entity_metrics"

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # The size of each shape, from the text it carries.
        module Metrics
          FONT_SIZE = 14
          LINE_HEIGHT = 16.4883
          ASCENT = 13.5352
          HEADER_PAD = 10.0

          module_function

          # @return [Array<String>] the stereotype line, if any, then the
          #   label lines
          def text_lines(node)
            lines = node.lines.reject(&:empty?)
            node.stereotype ? ["«#{node.stereotype}»"] + lines : lines
          end

          def text_width(lines)
            lines.map do |line|
              TextMeasurement.measure(line, font_size: FONT_SIZE)[:width]
            end.max.to_f
          end

          def text_height(lines)
            [lines.size, 1].max * LINE_HEIGHT
          end

          # @return [Array(Float, Float)] width and height of a leaf node
          def size(node)
            return EntityMetrics.size(node) if node.kind == :entity
            return data_size(node) if node.kind == :data

            lines = text_lines(node)
            width = text_width(lines)
            height = text_height(lines)
            send(:"size_#{shape(node.kind)}", width, height + sprite_room(node))
          end

          def sprite_room(node)
            node.sprite ? Archimate::SPRITE_ROOM : 0.0
          end

          def data_size(node)
            box = PlantUMLData::Boxes::TableBox.size(node.table)
            [box.width, box.height]
          end

          def shape(kind)
            return kind if %i[actor usecase component interface portin
                              portout note database cloud node
                              circle].include?(kind)

            :box
          end

          def size_actor(width, height) = [[width + 8, 40.0].max, 54.0 + height]

          def size_usecase(width, height)
            [[(width * 1.35) + 24, 80.0].max, height + 34]
          end

          def size_component(width, height)
            [width + 40, height + 30]
          end

          def size_interface(width, height) = [[width, 20.0].max, 28.0 + height]
          def size_portin(width, height) = [[width, 14.0].max, 24.0 + height]
          def size_portout(width, height) = [[width, 14.0].max, 12.0 + height]
          def size_circle(width, height) = [[width, 16.0].max, 24.0 + height]
          def size_note(width, height) = [width + 24, height + 16]
          def size_database(width, height) = [width + 30, height + 40]

          def size_cloud(width, height) = [width + 34, height + 31]

          def size_node(width, height) = [width + 38, height + 28]
          def size_box(width, height) = [width + 26, height + 20]

          # @return [Float] the room a container's label takes at its top
          def header_height(node)
            lines = text_lines(node).reject(&:empty?)
            lines.empty? ? HEADER_PAD : text_height(lines) + HEADER_PAD
          end

          def header_width(node)
            text_width(text_lines(node)) + 28
          end
        end
      end
    end
  end
end
