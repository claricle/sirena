# frozen_string_literal: true

require_relative "../../../text_measurement"
require_relative "entity_metrics"

module Sirena
  module Notation
    module PlantUML
      module NodeGraph
        # The size of each shape, from the text it carries.
        module Metrics
          FONT_SIZE = 12
          LINE_HEIGHT = 15.0
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

            lines = text_lines(node)
            width = text_width(lines)
            height = text_height(lines)
            send(:"size_#{shape(node.kind)}", width, height)
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
            [width + 44, [height + 20, 38.0].max]
          end

          def size_interface(width, height) = [[width, 20.0].max, 28.0 + height]
          def size_portin(width, height) = [[width, 14.0].max, 18.0 + height]
          def size_portout(width, height) = size_portin(width, height)
          def size_circle(width, height) = [[width, 16.0].max, 24.0 + height]
          def size_note(width, height) = [width + 24, height + 16]
          def size_database(width, height) = [width + 30, height + 40]

          def size_cloud(width, height)
            [(width * 1.5) + 30, (height * 1.5) + 34]
          end

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
