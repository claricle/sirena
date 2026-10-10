# frozen_string_literal: true

require_relative "scene"

module Sirena
  module Notation
    module PlantUML
      module Sequence
        # The label of a message under `autonumber`: its number in bold,
        # then the label, four pixels on. The pair is placed as one unit
        # where the plain label would have been.
        class NumberedLabel
          GAP = 4.0

          # @param measure [#call] text width in pixels
          def initialize(measure)
            @measure = measure
          end

          # @return [Float] the width the number adds to the label
          def extra(message)
            return 0.0 unless message.number

            @measure.call(message.number.to_s) + GAP
          end

          # @param anchor [String] where the unit sits at `at_x`: "start",
          #   "middle" or "end"
          # @return [Array<Scene::Text>] the number, then the label
          def texts(message, at_x, at_y, anchor)
            left = left_of(message, at_x, anchor)
            [piece(message.number.to_s, left, at_y, "message_number", "bold"),
             piece(message.label, left + extra(message), at_y, "message_label")]
          end

          private

          def left_of(message, at_x, anchor)
            total = extra(message) + @measure.call(message.label)
            { "middle" => at_x - (total / 2), "end" => at_x - total }
              .fetch(anchor, at_x)
          end

          def piece(content, at_x, at_y, role, weight = nil)
            PlantUML::Scene::Text.new(content: content, x: at_x, y: at_y,
                                      role: role, anchor: "start",
                                      weight: weight)
          end
        end
      end
    end
  end
end
